const std = @import("std");
const response = @import("response.zig");
const request = @import("request.zig");
const routes = @import("routes.zig");
const Address = std.net.Address;
const posix = std.posix;
const linux = std.os.linux;
const Allocator = std.mem.Allocator;

pub const PORT: u16 = 8000;
pub const ADDRESS = "127.0.0.1";
pub const MAX_REQUEST_LINE = 8192;

pub const Server = struct {
    address: Address,
    socket: posix.socket_t,
    routes: routes.Routes,

    pub fn init(rts: routes.Routes) !Server {
        const address = try Address.parseIp4(ADDRESS, PORT);
        const sock = try posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, posix.IPPROTO.TCP);
        errdefer posix.close(sock);
        var yes: c_int = 1;
        try posix.setsockopt(sock, posix.SOL.SOCKET, linux.SO.REUSEADDR | linux.SO.REUSEPORT, std.mem.asBytes(&yes));
        try std.posix.bind(sock, &address.any, address.getOsSockLen());
        try posix.listen(sock, 128);
        return .{ .address = address, .socket = sock, .routes = rts};
    }

    pub fn listen(self: *Server, allocator: Allocator) !void {
        const epfd = try posix.epoll_create1(0);
        defer posix.close(epfd);
        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN, .data = .{ .fd = self.socket } };
        try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, self.socket, &ev);

        var events: [1024]linux.epoll_event = undefined;

        while (true) {
            const nfds = posix.epoll_wait(epfd, &events, -1);

            var i: usize = 0;
            while (i < nfds) : (i += 1) {
                const e = events[i];

                if (e.data.fd == self.socket) {
                    while (true) {
                        var socklen = self.address.getOsSockLen();
                        const client_fd = posix.accept(self.socket, &self.address.any, @ptrCast(&socklen), 0) catch |err| switch (err) {
                            error.WouldBlock => break,
                            else => return err,
                        };

                        const cflags = try posix.fcntl(client_fd, posix.F.GETFL, 0);
                        _ = try posix.fcntl(client_fd, posix.F.SETFL, cflags | linux.SOCK.NONBLOCK);
                        var cev: linux.epoll_event = .{ .events = linux.EPOLL.IN, .data = .{ .fd = client_fd } };
                        try posix.epoll_ctl(epfd, linux.EPOLL.CTL_ADD, client_fd, &cev);
                    }
                } else {
                    var buf: [request.MAX_REQUEST_LINE]u8 = undefined;
                    const n = posix.read(e.data.fd, &buf) catch |err| switch (err) {
                        error.WouldBlock => 0,
                        else => return err,
                    };

                    if (n == 0) {
                        posix.close(e.data.fd);
                    } else {
                        var req = try request.HTTPRequest.init(allocator, buf[0..n]);
                        req.print();
                        defer req.Headers.deinit();
                        var resp = response.HTTPResponse{ .Version = "HTTP/1.0", .StatusCode = 200, .Reason = "OK", .Headers = std.StringHashMap([]const u8).init(allocator), .body = null };

                        defer resp.deinit();
                        const response_data = try resp.serialize(allocator);
                        defer allocator.free(response_data);

                        var file = std.fs.File{ .handle = e.data.fd };
                        defer file.close();
                        var socket_buf: [100]u8 = undefined;
                        var writer = file.writer(&socket_buf);

                        var caught = false;
                        for (self.routes.routes.items) |rt | {
                            if (std.mem.eql(u8, rt.Uri, req.RequestUri) and rt.Method == req.Method) {
                                try rt.f(allocator, req, &writer.interface);
                                caught = true;
                            }
                        }

                        if (caught) {
                            continue;
                        }

                        const notFoundResponse = try response.NotFound.serialize(allocator);
                        defer allocator.free(notFoundResponse);
                        _ = try posix.write(e.data.fd, notFoundResponse);
                    }
                }
            }
        }
    }

    pub fn deinit(self: *Server) void {
        posix.close(self.socket);
    }
};
