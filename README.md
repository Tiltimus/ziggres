## Ziggres

This library is a PostgreSQL driver written in Zig. Provides the basic functionality to perform queries. See examples folder for more.

## Installation

```zig
.{
    .name = "my-project",
    .version = "0.0.0",
    .dependencies = .{
        .ziggres = .{
            .url = "https://github.com/Tiltimus/ziggres/archive/<git-ref-here>.tar.gz",
            .hash = <hash-generated>,
        },
    },
}
```

And in your `build.zig`:

```zig
const ziggres = b.dependency("ziggres", .{ .target = target, .optimize = optimize });
exe.addModule("ziggres", ziggres.module("ziggres"));
```

## Basic CRUD Example

```zig
const User = struct {
    id: []const u8,
    firstname: []const u8,
    lastname: []const u8,
    email: ?[]const u8,
    data_row: DataRow.Row,

    pub fn deinit(self: @This()) void {
        self.data_row.deinit();
    }
};

const cert = try std.fs.cwd().openFile("<cert>", .{});

const connect_info = ConnectInfo{
    .host = "<host>",
    .port = <port>,
    .database = "<dbname>",
    .username = "<username>",
    .password = "<password>",
    .tls = .{ .tls = <cert> },
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

var data_reader: Client.DataReader = .empty;
defer data_reader.deinit();

try client.prepare(&data_reader, select_sql, &.{});

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
```