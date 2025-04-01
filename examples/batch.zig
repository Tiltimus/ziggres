const std = @import("std");
const Client = @import("ziggres");
const ConnectInfo = Client.ConnectInfo;
const DataRow = Client.Protocol.Backend.DataRow;
const DataReader = Client.DataReader;
const Allocator = std.mem.Allocator;
const allocator = std.testing.allocator;
const UNNAMED = Client.UNNAMED;
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

test "batch" {
    // const cert = try std.fs.cwd().openFile("docker/postgres.crt", .{});

    const connect_info = ConnectInfo{
        .host = "localhost",
        .port = 5433,
        .database = "ziggres",
        .username = "scram_user",
        .password = "password",
        // .tls = .{ .tls = cert },
    };

    var client = try Client.connect(allocator, connect_info);
    defer client.close();

    const table_sql =
        \\CREATE TABLE IF NOT EXISTS public.batch
        \\(
        \\ id integer NOT NULL
        \\)
    ;

    try client.execute(UNNAMED, table_sql, &.{});
    try client.execute(UNNAMED, "DELETE FROM public.batch", &.{});

    const insert_sql =
        \\ INSERT INTO public.batch (id)
        \\ SELECT * FROM generate_series(1, 1000);
    ;

    try client.execute(UNNAMED, insert_sql, &.{});

    _ = try client.execute(UNNAMED, "BEGIN", &.{});

    const exetened_query = Client.ExtendedQuery{
        .statement = "SELECT * FROM public.batch",
        .rows = 100,
    };

    var data_reader = try client.extended(exetened_query);
    defer data_reader.deinit();

    var count: i32 = 0;

    while (try data_reader.next()) |dr| {
        dr.deinit();
        count += 1;
    }

    _ = try client.execute(UNNAMED, "COMMIT", &.{});

    try std.testing.expectEqual(1000, count);
}
