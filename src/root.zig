const std = @import("std");
const Address = std.net.Address;
const posix = std.posix;

pub const PORT: u16 = 8000;
pub const ADDRESS = "0.0.0.0";

pub const Server = struct {
    address: Address,
    socket: posix.socket_t,

    pub fn init() !Server {
        const address = try Address.parseIp4(ADDRESS, PORT);
        const sock = try posix.socket( posix.AF.INET, posix.SOCK.STREAM | posix.SOCK.NONBLOCK, posix.IPPROTO.TCP);
        errdefer posix.close(sock);

        try std.posix.bind(sock, &address.any, address.getOsSockLen());
        return .{.address = address, .socket = sock};
    }

    pub fn deinit(self: *Server) void {
        posix.close(self.socket);
    }
};


