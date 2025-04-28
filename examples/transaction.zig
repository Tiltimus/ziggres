const std = @import("std");
const ziggres = @import("ziggres");
const Client = ziggres.Client;
const ConnectInfo = ziggres.ConnectInfo;
const DataRow = ziggres.Protocol.Backend.DataRow;
const DataReader = ziggres.DataReader;
const ExtendedQuery = ziggres.ExtendedQuery;
const Allocator = std.mem.Allocator;
const allocator = std.testing.allocator;
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

test "transaction" {
    const connect_info = ConnectInfo{
        .host = "localhost",
        .port = 5433,
        .database = "ziggres",
        .username = "scram_user",
        .password = "password",
    };

    var client = try Client.connect(allocator, connect_info);
    defer client.close();

    const table_sql =
        \\CREATE TABLE IF NOT EXISTS public.batch
        \\(
        \\ id integer NOT NULL
        \\)
    ;

    try client.execute(table_sql, &.{});
    try client.execute("DELETE FROM public.batch", &.{});

    const insert_sql =
        \\ INSERT INTO public.batch (id)
        \\ SELECT * FROM generate_series(1, 1000);
    ;

    try client.execute(insert_sql, &.{});

    try client.begin();

    const exetened_query = ExtendedQuery{
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

    try client.rollback(null);

    try std.testing.expectEqual(1000, count);
}
