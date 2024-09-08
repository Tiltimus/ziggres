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

    // var data_reader = try connection.query("SELECT * FROM array_of_data LIMIT 5");

    // while (try data_reader.next()) |data_row| {
    //     _ = try data_row.from_field([5]u8, allocator);
    // }

    // while (try data_reader.next()) |data_row| {
    //     const smallint = try data_row.from_field(i16, allocator);
    //     const integer = try data_row.from_field(i32, allocator);
    //     const bigint = try data_row.from_field(i64, allocator);
    //     const decimal = try data_row.from_field(f64, allocator);
    //     const numeric = try data_row.from_field(f32, allocator);
    //     const real = try data_row.from_field(f32, allocator);
    //     const double = try data_row.from_field(f64, allocator);
    //     const small_serial = try data_row.from_field(u16, allocator);
    //     const serial = try data_row.from_field(u32, allocator);
    //     const big_serial = try data_row.from_field(u64, allocator);
    //     const money = try data_row.from_field([10]u8, allocator);

    //     std.log.debug("{} {} {} {} {} {} {} {} {} {} {any}", .{
    //         smallint,
    //         integer,
    //         bigint,
    //         decimal,
    //         numeric,
    //         real,
    //         double,
    //         small_serial,
    //         serial,
    //         big_serial,
    //         money,
    //     });
    // }

    const lap = timer.lap();

    _ = try writer.print("\x1B[31mTime: {}\x1B[0m", .{lap});
}
