const std = @import("std");
const Allocator = std.mem.Allocator;

pub const HTTPResponse = struct {
    Version: []const u8,
    StatusCode: u16,
    Reason: []const u8,
    Headers: ?std.StringHashMap([]const u8),
    body: ?[]u8,

    pub fn serialize(self: HTTPResponse, allocator: Allocator) ![]u8 {
        var writer = try std.Io.Writer.Allocating.initCapacity(allocator, 100);
        try writer.writer.print("{s} {d} {s}\r\n", .{ self.Version, self.StatusCode, self.Reason });
        if (self.Headers) |headers| {
            if (headers.count() == 0) {
                try writer.writer.print("\r\n", .{});
            } else {
                var it = headers.iterator();
                while (it.next()) |value| {
                    try writer.writer.print("{s}: {s}\r\n", .{ value.key_ptr.*, value.value_ptr.* });
                }
                try writer.writer.print("\r\n", .{});
            }

            if (self.body) |b| {
                try writer.writer.print("{s}", .{b});
            }
        }

        return writer.toOwnedSlice();
    }

    pub fn deinit(self: *HTTPResponse) void {
        if (self.Headers) |_| {
            self.Headers.?.deinit();
        }
    }
};

pub const BadRequest = HTTPResponse{
    .Version = "HTTP/1.0",
    .StatusCode = 400,
    .Reason = "Bad Request",
    .Headers = null,
    .body = null,
};

pub const NotFound = HTTPResponse{
    .Version = "HTTP/1.0",
    .StatusCode = 404,
    .Reason = "Not Found",
    .Headers = null,
    .body = null,
};

pub const SuccessNoData = HTTPResponse{
    .Version = "HTTP/1.0",
    .StatusCode = 204,
    .Reason = "Ok",
    .Headers = null,
    .body = null,
};
