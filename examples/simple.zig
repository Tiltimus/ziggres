const std = @import("std");
const Client = @import("ziggres");
const ConnectInfo = Client.ConnectInfo;
const allocator = std.testing.allocator;
const UNNAMED = Client.UNNAMED;
const expect = std.testing.expect;

test "simple" {
    const connect_info = ConnectInfo{
        .host = "localhost",
        .port = 5433,
        .database = "ziggres",
        .username = "scram_user",
        .password = "password",
    };

    var client = try Client.connect(allocator, connect_info);
    defer client.close();

    const table_sql_1 =
        \\CREATE TABLE IF NOT EXISTS public.simple_table_one
        \\(
        \\ id integer NOT NULL
        \\)
    ;

    const table_sql_2 =
        \\CREATE TABLE IF NOT EXISTS public.simple_table_two
        \\(
        \\ id integer NOT NULL
        \\)
    ;

    const insert_sql_1 =
        \\ INSERT INTO public.simple_table_one (id)
        \\ SELECT * FROM generate_series(1, 1000);
    ;

    const insert_sql_2 =
        \\ INSERT INTO public.simple_table_two (id)
        \\ SELECT * FROM generate_series(1, 1000);
    ;

    const simple_query =
        \\ SELECT * FROM public.simple_table_one;
        \\ SELECT * FROM public.simple_table_two;
    ;

    try client.execute(table_sql_1, &.{});
    try client.execute(table_sql_2, &.{});
    try client.execute("DELETE FROM public.simple_table_one", &.{});
    try client.execute("DELETE FROM public.simple_table_two", &.{});
    try client.execute(insert_sql_1, &.{});
    try client.execute(insert_sql_2, &.{});

    var simple_reader = try client.simple(simple_query);
    var count: i32 = 0;

    while (try simple_reader.next()) |data_reader| {
        defer data_reader.deinit();

        while (try data_reader.next()) |dr| {
            switch (simple_reader.index) {
                0 => {
                    dr.deinit();
                    count += 1;
                },
                1 => {
                    dr.deinit();
                    count += 1;
                },
                else => unreachable,
            }
        }
    }

    try expect(count == 2000);
}
