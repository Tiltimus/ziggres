const std = @import("std");
const StringHashMap = std.StringHashMap([]const u8);
const File = std.fs.File;

pub const ConnectInfo = @This();

host: []const u8,
port: u16,
username: []const u8,
database: []const u8,
password: []const u8,
application_name: []const u8 = "zig",
options: ?StringHashMap = null,
tls: Tls = .no_tls,

pub const Tls = enum {
    no_tls,
    tls,
};

pub const default = ConnectInfo{
    .host = "127.0.0.1",
    .port = 5432,
    .database = "",
    .username = "postgres",
    .password = "postgres",
    .application_name = "zig",
    .options = null,
};
