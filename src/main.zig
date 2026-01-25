const std = @import("std");
const zerve = @import("zerve");

pub fn main() !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var server = try zerve.Server.init();
    defer server.deinit();

    try stdout.interface.print("Server Listening on: {s}:{d}\n", .{zerve.ADDRESS, zerve.PORT});
    try stdout.interface.flush();
}
