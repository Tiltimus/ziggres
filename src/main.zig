const std = @import("std");
const Connection = @import("./postgres/connection.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ConnectInfo = Connection.ConnectInfo;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const connect_info = .{
        .host = "127.0.0.1",
        .port = 5432,
        .database = "zig",
        .username = "postgres",
        .password = "[password]",
    };

    var connection = try Connection.connect(allocator, connect_info);

    var data_reader = try connection.query("SELECT * FROM test_table");

    while (try data_reader.next()) |data_row| {
        _ = try data_row.read_int(i32);
        const name = try data_row.read_alloc(allocator);
        defer allocator.free(name);

        // std.log.debug("Item: id: {d} name: {s}", .{ id, name });
    }
}
