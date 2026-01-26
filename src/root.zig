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

pub const HTTPRequest = struct {
    Method: HTTPMethod,
    RequestUri: []const u8,
    Version: []const u8,
    Headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn init(allocator: Allocator, data: []u8) !HTTPRequest {
        // TOP Phase
        var first_line_len: usize = 0;
        while (first_line_len < data.len and data[first_line_len] != '\n') : (first_line_len += 1) {}

        if (first_line_len == 0) {
            return error.NoData;
        }

        var first_it = std.mem.splitAny(u8, data[0 .. first_line_len - 1], " ");
        const method = first_it.next() orelse return error.MissingMethod;
        const requestURI = first_it.next() orelse return error.MissingRequestUri;
        const httpVersion = first_it.next() orelse return error.MissingVersion;

        var m: HTTPMethod = undefined;
        if (std.mem.eql(u8, "GET", method)) {
            m = HTTPMethod.GET;
        } else if (std.mem.eql(u8, "DELETE", method)) {
            m = HTTPMethod.DELETE;
        } else if (std.mem.eql(u8, "POST", method)) {
            m = HTTPMethod.POST;
        } else if (std.mem.eql(u8, "PATCH", method)) {
            m = HTTPMethod.PATCH;
        } else {
            return error.BadMethod;
        }

        const second_line_start = first_line_len + 1;
        var second_it = std.mem.splitSequence(u8, data[second_line_start..], "\r\n\r\n");

        const header_data = second_it.next();
        var headers = std.StringHashMap([]const u8).init(allocator);
        const body = second_it.next() orelse return error.NoBody;

        if (header_data) |header| {
            var header_it = std.mem.splitSequence(u8, header, "\r\n");

            while (header_it.next()) |value| {
                var index: usize = 0;
                for (value, 0..) |v, i| {
                    if (v == ':') {
                        index = i;
                        break;
                    }
                }
                if (index == 0) {
                    return error.BadHeader;
                }
                try headers.put(value[0..index], value[index + 2 ..]);
            }
        }

        return .{ .Method = m, .RequestUri = requestURI, .Version = httpVersion, .Headers = headers, .body = body };
    }

    pub fn print(self: HTTPRequest) void {
        std.debug.print("Method:\t\t {any}\n", .{self.Method});
        std.debug.print("RequestUri:\t {s}\n", .{self.RequestUri});
        std.debug.print("HTTPVersion:\t {s}\n", .{self.Version});
        std.debug.print("Headers:\t ", .{});
        var it = self.Headers.iterator();
        if (it.next()) |value| {
            std.debug.print("{s}: {s}\n", .{ value.key_ptr.*, value.value_ptr.* });
        }
        while (it.next()) |value| {
            std.debug.print("\t\t {s}: {s}\n", .{ value.key_ptr.*, value.value_ptr.* });
        }
        std.debug.print("Body:\t\t {s}\n", .{self.body});
    }
};

pub const HTTPResponse = struct {
    Version: []const u8,
    StatusCode: u8,
    Reason: []const u8,
    Headers: std.StringHashMap([]const u8),
    body: ?[]u8,

    pub fn serialize(self: HTTPResponse, allocator: Allocator) ![]u8 {
        var writer = try std.Io.Writer.Allocating.initCapacity(allocator, 100);
        try writer.writer.print("{s} {d} {s}\r\n", .{ self.Version, self.StatusCode, self.Reason });

        if (self.Headers.count() == 0) {
            try writer.writer.print("\r\n", .{});
        } else {
            var it = self.Headers.iterator();
            while (it.next()) |value| {
                try writer.writer.print("{s}: {s}\r\n", .{ value.key_ptr.*, value.value_ptr.* });
            }
            try writer.writer.print("\r\n", .{});
        }

        if (self.body) |b| {
            try writer.writer.print("{s}", .{b});
        }
        return writer.toOwnedSlice();
    }
};

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
                    var buf: [MAX_REQUEST_LINE]u8 = undefined;
                    const n = posix.read(e.data.fd, &buf) catch |err| switch (err) {
                        error.WouldBlock => 0,
                        else => return err,
                    };

                    if (n == 0) {
                        posix.close(e.data.fd);
                    } else {
                        var request = try HTTPRequest.init(allocator, buf[0..n]);
                        request.print();
                        defer request.Headers.deinit();
                        var response = HTTPResponse{ .Version = "HTTP/1.0", .StatusCode = 200, .Reason = "OK", .Headers = std.StringHashMap([]const u8).init(allocator), .body = null };
                        defer response.Headers.deinit();
                        const response_data = try response.serialize(allocator);
                        defer allocator.free(response_data);

                        _ = try posix.write(e.data.fd, response_data);
                        posix.close(e.data.fd);
                    }
                }
            }
        }
    }

    pub fn deinit(self: *Server) void {
        posix.close(self.socket);
    }
};
