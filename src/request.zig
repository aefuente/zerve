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
        const sp1 = std.mem.indexOfScalar(u8, data, ' ') orelse { return error.BadRequest;};
        var sp2 = std.mem.indexOfScalar(u8, data[sp1 + 1..], ' ') orelse {return error.BadRequest;};
        sp2 += sp1 + 1;

        const requestURI = data[sp1+1 .. sp2];
        var m: HTTPMethod = undefined;
        if (std.mem.eql(u8, "GET", data[0..sp1])) {
            m = HTTPMethod.GET;
        } else if (std.mem.eql(u8, "DELETE", data[0..sp1])) {
            m = HTTPMethod.DELETE;
        } else if (std.mem.eql(u8, "POST", data[0..sp1])) {
            m = HTTPMethod.POST;
        } else if (std.mem.eql(u8, "PATCH", data[0..sp1])) {
            m = HTTPMethod.PATCH;
        } else {
            return error.BadMethod;
        }

        var crlf = std.mem.indexOf(u8, data[sp2+1..], "\r\n") orelse {return error.BadRequest;};
        crlf += sp2 + 1;

        const version = data[sp2+1..crlf];
        if (! std.mem.eql(u8, version, "HTTP/1.0")) {
            return error.BadVersion;
        }

        const start = crlf+2;
        var i = start;
        var headers = std.StringHashMap([]const u8).init(allocator);
        while (true) {
            const line_end = std.mem.indexOf(u8, data[i..], "\r\n") orelse {return error.BadHeader;};
            if (line_end == 0) {
                i += 2;
                break;
            }

            const line = data[i .. i + line_end];
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse { return error.BadHeaderLine;};
            var vstart = colon+1;
            while (vstart < line.len and (line[vstart] == ' ' or line[vstart] == '\t')) {
                vstart += 1;
            }

            const name = line[0..colon];
            const value = line[vstart..];
            try headers.put(name, value);
            i += line_end + 2;
        }

        var body: []const u8 = undefined;
        if (headers.get("Content-Length")) |length |{
            const n = try std.fmt.parseInt(usize, length, 10);
            if (n > data[i..].len) {
                return error.TruncatedBody;
            }
            body = data[i..n+i];
        }else {
            body = data[i..];
        }

        return .{ .Method = m, .RequestUri = requestURI, .Version = version, .Headers = headers, .body = body };
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
