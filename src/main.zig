const std = @import("std");
const zerve = @import("zerve");
const Server = zerve.Server;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const HTTPRequest = zerve.request.HTTPRequest;
const HTTPError = zerve.HTTPError;

pub fn handleUri(allocator: Allocator, r: HTTPRequest, w: *std.Io.Writer) !void {
    _ = r;
    const response = zerve.response.SuccessNoData;
    const resp = try response.serialize(allocator);
    try w.writeAll(resp);
    try w.flush();
    return;
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    var routes = try zerve.Routes.init(gpa);
    defer routes.deinit(gpa);
    try routes.add(gpa, "/uri", zerve.Method.GET, handleUri);

    var server = try Server.init(routes);
    defer server.deinit();

    try stdout.interface.print("Server Listening on: {s}:{d}\n", .{ zerve.ADDRESS, zerve.PORT });
    try stdout.interface.flush();

    try server.listen(gpa);
}
