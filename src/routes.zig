const std = @import("std");
pub const request = @import("request.zig");
const Allocator = std.mem.Allocator;

pub const HTTPError = error{
    Bad,
    OutOfMemeory
};

pub fn doNothing(allocator: Allocator, r: request.HTTPRequest, w: *std.Io.Writer) HTTPError!void {
    _ = allocator;
    _ = r;
    _ = w;
}

pub const Routes = struct {
    routes: std.ArrayList(Route),

    pub fn init(allocator: Allocator) !Routes {
        const routes = try std.ArrayList(Route).initCapacity(allocator, 10);
        return .{ .routes = routes };
    }

    pub fn deinit(self: *Routes, allocator: Allocator) void {
        self.routes.deinit(allocator);
    }

    pub fn add(self: *Routes, allocator: Allocator, uri: []const u8, method: request.HTTPMethod, f: fn (Allocator, request.HTTPRequest, *std.Io.Writer) anyerror!void) !void {
        const route = Route{.Uri = uri, .Method = method, .f= f};
        try self.routes.append(allocator, route);
    }
}; 

pub const Route = struct {
    Uri: []const u8,
    Method: request.HTTPMethod,
    f: *const fn (Allocator, request.HTTPRequest, *std.Io.Writer) anyerror!void,
};

test "create routes" {
    const allocator = std.testing.allocator;
    var routes = try Routes.init(allocator);
    defer routes.deinit(allocator);
    
    try routes.add(allocator, "some", request.HTTPMethod.GET, doNothing);
    try routes.add(allocator, "some", request.HTTPMethod.GET, doNothing);

}
