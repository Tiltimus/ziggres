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
    defer _ = gpa.deinit();

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

    var data_reader_2 = try connection.prepare("DELETE FROM test_table", .{});

    try data_reader_2.drain();

    var data_reader_3 = try connection.prepare("INSERT INTO test_table VALUES (DEFAULT, $1, $2)", .{ "hello", "world" });

    try data_reader_3.drain();

    var data_reader_4 = try connection.prepare("SELECT * FROM test_table", .{});

    while (try data_reader_4.next()) |data_row| {
        const value = try data_row.map(TestTableRow, allocator);
        std.log.debug("{any}", .{value});

        allocator.free(value.firstname);
        allocator.free(value.lastname);
    }
}

const TestTableRow = struct {
    firstname: []const u8,
    lastname: []const u8,
    id: i32,
};
