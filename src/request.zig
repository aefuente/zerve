const std = @import("std");
pub const MAX_REQUEST_LINE = 8192;
const Allocator = std.mem.Allocator;

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
