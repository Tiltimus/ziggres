const std = @import("std");
const ziggres = @import("ziggres");
const Client = ziggres.Client;
const Pool = ziggres.Pool;
const ConnectInfo = ziggres.ConnectInfo;
const DataRow = ziggres.Protocol.Backend.DataRow;
const Allocator = std.mem.Allocator;
const ThreadPool = std.Thread.Pool;
const allocator = std.testing.allocator;
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

test "pool simple" {
    const connect_info = ConnectInfo{
        .host = "localhost",
        .port = 5433,
        .database = "ziggres",
        .username = "scram_user",
        .password = "password",
    };

    const settings = Pool.Settings{
        .min = 1,
        .max = 3,
        .timeout = 30_000_000_000,
        .attempts = 3,
    };

    var pool = try Pool.init(
        allocator,
        connect_info,
        settings,
    );
    defer pool.deinit();

    const client_1 = try pool.acquire();
    defer pool.release(client_1);

    const client_2 = try pool.acquire();
    defer pool.release(client_2);

    const client_3 = try pool.acquire();
    defer pool.release(client_3);

    try expect(pool.connections.items.len == 3);
}

test "pool 100" {
    const connect_info = ConnectInfo{
        .host = "localhost",
        .port = 5433,
        .database = "ziggres",
        .username = "scram_user",
        .password = "password",
    };

    var pool = try Pool.init(
        allocator,
        connect_info,
        .default,
    );
    defer pool.deinit();

    const table_sql =
        \\CREATE TABLE IF NOT EXISTS public.pool
        \\(
        \\ id integer NOT NULL
        \\)
    ;

    const insert_sql =
        \\ INSERT INTO public.pool (id)
        \\ SELECT * FROM generate_series(1, 1000);
    ;

    const delete_sql = "DELETE FROM public.pool";
    const select_sql = "SELECT id FROM public.pool";

    try pool.execute(table_sql, &.{});
    try pool.execute(delete_sql, &.{});
    try pool.execute(insert_sql, &.{});

    var thread_pool: ThreadPool = undefined;
    defer thread_pool.deinit();

    try thread_pool.init(.{
        .allocator = allocator,
    });

    for (0..100) |_| {
        try thread_pool.spawn(handle, .{ &pool, select_sql });
    }
}

fn select(pool: *Pool, statement: []const u8) !void {
    var client = try pool.acquire();
    defer pool.release(client);

    var data_reader = try client.prepare(
        statement,
        &.{},
    );
    defer data_reader.deinit();

    try data_reader.drain();

    try expect(data_reader.rows() == 1000);
}

fn handle(pool: *Pool, statement: []const u8) void {
    select(pool, statement) catch {
        @panic("FAILED");
    };
}
