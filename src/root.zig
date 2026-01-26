const std = @import("std");
const Address = std.net.Address;
const posix = std.posix;
const linux = std.os.linux;
const Allocator = std.mem.Allocator;

pub const PORT: u16 = 8000;
pub const ADDRESS = "127.0.0.1";
pub const MAX_REQUEST_LINE = 8192;

pub const HTTPMethod = enum {
    GET,
    POST,
    PATCH,
    DELETE,
};

pub const HTTPRequest = struct { Method: HTTPMethod, RequestUri: []u8, Version: []u8, Headers: std.AutoHashMap([]u8, []u8), body: ?[]u8 };

pub const HTTPResponse = struct { Version: []u8, StatusCode: u8, Reason: []u8, Headers: std.AutoHashMap([]u8, []u8), body: ?[]u8 };

pub const Server = struct {
    address: Address,
    socket: posix.socket_t,

    pub fn init() !Server {
        const address = try Address.parseIp4(ADDRESS, PORT);
        const sock = try posix.socket(posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, posix.IPPROTO.TCP);
        errdefer posix.close(sock);
        var yes: c_int = 1;
        try posix.setsockopt(sock, posix.SOL.SOCKET, linux.SO.REUSEADDR | linux.SO.REUSEPORT, std.mem.asBytes(&yes));
        try std.posix.bind(sock, &address.any, address.getOsSockLen());
        try posix.listen(sock, 128);
        return .{ .address = address, .socket = sock };
    }

    pub fn listen(self: *Server) !void {
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
                    var buf: [MAX_REQUEST_LINE]u8 = undefined;
                    const n = posix.read(e.data.fd, &buf) catch |err| switch (err) {
                        error.WouldBlock => 0,
                        else => return err,
                    };
                    if (n == 0) {
                        _ = posix.close(e.data.fd);
                    } else {
                        _ = try posix.write(e.data.fd, buf[0..n]);
                    }
                }
            }
        }
    }

    pub fn deinit(self: *Server) void {
        posix.close(self.socket);
    }
};
