const std = @import("std");
const zerve = @import("zerve");
const assert = std.debug.assert;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);

    var server = try zerve.Server.init();
    defer server.deinit();

    try stdout.interface.print("Server Listening on: {s}:{d}\n", .{ zerve.ADDRESS, zerve.PORT });
    try stdout.interface.flush();

    try server.listen(gpa);
}
