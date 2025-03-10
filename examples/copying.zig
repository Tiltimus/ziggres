const std = @import("std");
const Client = @import("ziggres");
const ConnectInfo = Client.ConnectInfo;
const allocator = std.testing.allocator;
const expect = std.testing.expect;

test "copying" {
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
        \\CREATE TABLE IF NOT EXISTS public.copy
        \\(
        \\ id serial NOT NULL,
        \\ firstname VARCHAR(40) NOT NULL,
        \\ lastname VARCHAR(40) NOT NULL,
        \\ email VARCHAR(40) NULL,
        \\ CONSTRAINT copy_pkey PRIMARY KEY (id)
        \\)
    ;

    const copy_in_sql =
        \\ COPY copy (firstname, lastname, email)
        \\ FROM STDIN WITH (FORMAT text)
    ;

    const copy_out_sql =
        \\ COPY copy (firstname, lastname, email)
        \\ TO STDOUT WITH (FORMAT text)
    ;

    try client.execute(table_sql, &.{});
    try client.execute("DELETE FROM public.copy", &.{});

    var copy_in: Client.CopyIn = .empty;

    try client.copyIn(&copy_in, copy_in_sql, &.{});

    for (0..1000) |_| {
        try copy_in.write("Firstname\tLastname\t-1\n");
    }

    try copy_in.done();

    var copy_out: Client.CopyOut = .empty;
    defer copy_out.deinit();

    try client.copyOut(&copy_out, copy_out_sql, &.{});

    var count: usize = 0;

    while (try copy_out.read()) |row| {
        row.deinit();
        count += 1;
    }

    try expect(count == 1000);
}
