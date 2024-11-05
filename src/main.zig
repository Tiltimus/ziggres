const std = @import("std");
const Connection = @import("connection.zig");
const Diagnostics = @import("diagnostics.zig");
const Listener = @import("listener.zig");
const Message = @import("message.zig");
const Protocol = @import("protocol.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ConnectInfo = Connection.ConnectInfo;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const connect_info = .{
        .host = "db",
        .port = 5432,
        .database = "ziggres",
        .username = "root",
        .password = "G7TWaw4aTmGS",
        .diagnostics = Diagnostics.init(),
    };

    var connection = try Connection.connect(allocator, connect_info);
    defer connection.close();

    const sql =
        \\CREATE TABLE IF NOT EXISTS public.test_table
        \\(
        \\ id serial NOT NULL,
        \\ firstname character varying NOT NULL,
        \\ lastname character varying NOT NULL,
        \\ CONSTRAINT test_table_pkey PRIMARY KEY (id)
        \\)
    ;

    var data_reader = try connection.prepare(sql, .{});

    try data_reader.drain();

    var data_reader_2 = try connection.prepare("INSERT INTO test_table VALUES (DEFAULT, $1, $2)", .{ "hello", "world" });

    try data_reader_2.drain();

    const protocol = Protocol.net_stream();

    _ = try protocol.connect(std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 3000));
}
