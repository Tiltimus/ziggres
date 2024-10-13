const Diagnostics = @import("diagnostics.zig");

const ConnectInfo = @This();

host: []const u8,
port: u16,
username: []const u8,
database: []const u8,
password: []const u8,
application_name: []const u8 = "zig",
diagnostics: ?Diagnostics = null,

pub const default = ConnectInfo{
    .host = "127.0.0.1",
    .port = 5432,
    .database = "",
    .username = "postgres",
    .password = "postgres",
    .application_name = "zig",
};
