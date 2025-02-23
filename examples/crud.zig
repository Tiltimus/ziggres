const std = @import("std");
const Client = @import("ziggres");
const ConnectInfo = Client.ConnectInfo;
const DataRow = Client.Protocol.Backend.DataRow;
const Allocator = std.mem.Allocator;
const allocator = std.testing.allocator;
const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

test "tls crud" {
    const User = struct {
        id: []const u8,
        firstname: []const u8,
        lastname: []const u8,
        email: ?[]const u8,
        data_row: DataRow,

        pub fn deinit(self: @This()) void {
            self.data_row.deinit();
        }
    };

    const cert = try std.fs.cwd().openFile("docker/postgres.crt", .{});

    const connect_info = ConnectInfo{
        .host = "localhost",
        .port = 5433,
        .database = "ziggres",
        .username = "scram_user",
        .password = "password",
        .tls = .{ .tls = cert },
    };

    var client = try Client.connect(allocator, connect_info);
    defer client.close();

    const table_sql =
        \\CREATE TABLE IF NOT EXISTS public.crud
        \\(
        \\ id serial NOT NULL,
        \\ firstname VARCHAR(40) NOT NULL,
        \\ lastname VARCHAR(40) NOT NULL,
        \\ email VARCHAR(40) NULL,
        \\ CONSTRAINT crud_pkey PRIMARY KEY (id)
        \\)
    ;

    try client.execute(table_sql, &.{});
    try client.execute("DELETE FROM public.crud", &.{});

    const insert_sql =
        \\ INSERT INTO public.crud
        \\ VALUES
        \\ (DEFAULT, $1, $2, $3),
        \\ (DEFAULT, $4, $5, $6),
        \\ (DEFAULT, $7, $8, $9)
    ;

    var params = [_]?[]const u8{
        "OneFirstname",
        "OneLastname",
        null,
        "TwoFirstname",
        "TwoLastname",
        "twoemail@addres.com",
        "ThreeFirstname",
        "ThreeLastname",
        "threeemail@address.com",
    };

    try client.execute(insert_sql, &params);

    const select_sql =
        \\ SELECT id, firstname, lastname, email FROM public.crud
    ;

    var data_reader = try client.prepare(select_sql, &.{});
    defer data_reader.deinit();

    var users: [3]User = undefined;
    defer for (users) |user| user.deinit();

    while (try data_reader.next()) |data_row| {
        const id = try data_row.get();
        const firstname = try data_row.get();
        const lastname = try data_row.get();
        const email = try data_row.get_optional();

        users[data_reader.index] = User{
            .id = id,
            .firstname = firstname,
            .lastname = lastname,
            .email = email,
            .data_row = data_row.*,
        };
    }

    try expectEqualStrings(users[0].firstname, "OneFirstname");
    try expectEqualStrings(users[0].lastname, "OneLastname");
    try expect(users[0].email == null);

    try expectEqualStrings(users[1].firstname, "TwoFirstname");
    try expectEqualStrings(users[1].lastname, "TwoLastname");
    try expectEqualStrings(users[1].email.?, "twoemail@addres.com");

    try expectEqualStrings(users[2].firstname, "ThreeFirstname");
    try expectEqualStrings(users[2].lastname, "ThreeLastname");
    try expectEqualStrings(users[2].email.?, "threeemail@address.com");

    var update_params = [_]?[]const u8{
        "Ziggres",
        users[0].id,
    };

    try client.execute(
        "UPDATE public.crud SET firstname = $1 WHERE id = $2",
        &update_params,
    );

    var select_updated = [_]?[]const u8{users[0].id};

    var data_reader_2 = try client.prepare(
        "SELECT * FROM public.crud WHERE id = $1",
        &select_updated,
    );
    defer data_reader_2.deinit();

    const data_row = try data_reader_2.next();

    if (data_row) |row| {
        defer row.deinit();

        _ = try row.get();
        const firstname = try row.get();

        try expectEqualStrings("Ziggres", firstname);
    }
}
