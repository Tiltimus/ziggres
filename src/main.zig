const std = @import("std");
const Connection = @import("./postgres/connection.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ConnectInfo = Connection.ConnectInfo;

pub fn main() !void {
    const std_out = std.io.getStdOut();
    const writer = std_out.writer().any();

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
    defer connection.close();

    var timer = try std.time.Timer.start();

    const id: i32 = 1;

    const data_reader = try connection.prepare(
        "DELETE FROM test_table WHERE id = $1",
        .{id},
    );

    while (try data_reader.next()) |data_row| {
        _ = try data_row.from_field(i32, allocator);
        const something = try data_row.from_field([]const u8, allocator);
        defer allocator.free(something);

        std.log.debug("Something: {any}", .{something});
    }

    const lap = timer.lap();

    _ = try writer.print("\x1B[31mTime: {}\x1B[0m", .{lap});
}
