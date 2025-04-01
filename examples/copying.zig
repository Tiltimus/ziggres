const std = @import("std");
const Client = @import("ziggres");
const ConnectInfo = Client.ConnectInfo;
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const UNNAMED = Client.UNNAMED;

test "copying" {
    // TODO: Look into strange issue where after around 482ish copy data with TLSClient
    // It start to give bad bytes back causing it to fail
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

    try client.execute(UNNAMED, table_sql, &.{});
    try client.execute(UNNAMED, "DELETE FROM public.copy", &.{});

    var copy_in = try client.copyIn(
        copy_in_sql,
        &.{},
    );

    for (0..1000) |_| {
        try copy_in.write("Firstname\tLastname\t-1\n");
    }

    try copy_in.done();

    var copy_out = try client.copyOut(
        copy_out_sql,
        &.{},
    );
    defer copy_out.deinit();

    var count: usize = 0;

    while (try copy_out.read()) |row| {
        row.deinit();
        count += 1;
    }

    try expect(count == 1000);
}
