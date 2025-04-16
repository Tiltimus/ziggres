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
const ziggres = b.dependency("ziggres", .{
    .target = target,
    .optimize = optimize,
});

exe.addModule("ziggres", ziggres.module("ziggres"));
```

## Basic Example

```zig
const connect_info = ConnectInfo{
    .host = "<host>",
    .port = <port>,
    .database = "<database>",
    .username = "<username>",
    .password = "<password>",
    // .tls = .tls, 
};

var client = try Client.connect(
    allocator,
    connect_info,
);
defer client.close();

var data_reader = try client.prepare(
    <sql>,
    &.{},
);
defer data_reader.deinit();

while (try data_reader.next()) |data_row| {
    // Do something with the data_row
}
```

## Client

The client is the primary interface for interacting with the database, and it offers the following functions.

### simple

This method uses PostgreSQL’s Simple Query Flow and includes its own reader to iterate over each query in the statement. If you need to pass parameters to your queries, do not use this method. Instead, use prepared statements to help prevent SQL injection.

### extended

This method uses PostgreSQL’s Extended Query Flow. With this approach, you can use named prepared statements and portals, specify how many rows to fetch at a time, and choose the format type if you want to send or receive binary data.

### prepare

This prepared method wraps the extended call and defaults some of the settings to keep it simple. Use this method if you want to use an unnamed statement.

### execute

The execute method wraps the prepared call and discards the data reader if you are not interested in the result.

### begin

Begin is a convenient wrapper that runs the BEGIN command in SQL to start a transaction.

### commit

Commit is a convenient wrapper that runs the COMMIT command in SQL to commit a transaction.

### savepoint

Savepoint creates a savepoint that you can roll back or release to perform the respective operations.

### rollback

Rollback rolls back to the specified savepoint. If no savepoint is provided, it will roll back the entire transaction.

### release

Release releases the specified savepoint.

### copyIn

Provides a way to bulk-insert data into the database using PostgreSQL's COPY command from the client side.

### copyOut

Allows you to retrieve bulk data from the database using the COPY command and stream it to the client side.

## Pool

The Pool is a basic connection pool that allows you to set minimum and maximum connections, timeouts, and retry attempts. It also wraps the client function calls for convenience. Will improve later on with keep alive feature and more.