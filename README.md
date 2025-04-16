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

### Simple

This function uses PostgreSQL’s Simple Query Flow and includes its own reader to iterate over each query in the statement. If you need to pass parameters to your queries, do not use this function. Instead, use prepared statements to help prevent SQL injection.

```zig
var simple_reader = try client.simple(<query>);

while (try simple_reader.next()) |data_reader| {
    defer data_reader.deinit();

    while (try data_reader.next()) |dr| {
        switch (simple_reader.index) {
            0 => {
                // First query in the simple reader
            },
            1 => {
                // Second query in the simple reader
            },
            // And so on
            else => unreachable,
        }
    }
}
```

### Extended

This function uses PostgreSQL’s Extended Query Flow. With this approach, you can use named prepared statements and portals, specify how many rows to fetch at a time, and choose the format type if you want to send or receive binary data.

```zig
    var data_reader = try client.extended(<exetened_query>);
    defer data_reader.deinit();

    while (try data_reader.next()) |data_row| {
        // Do whatever you want with the data row
    }
```


### Prepare

This prepared function wraps the extended call and defaults some of the settings to keep it simple. Use this function if you want to use an unnamed statement.

```zig
var data_reader = try client.prepare(
    <sql>,
    &.{},
);
defer data_reader.deinit();

while (try data_reader.next()) |data_row| {
    // Do whatever you want with the data row
}
```

### Execute

The execute function wraps the prepared call and discards the data reader if you are not interested in the result.

```zig
try client.execute(<sql>, &.{});
```

### Begin

Begin is a convenient wrapper that runs the BEGIN command in SQL to start a transaction.

```zig
try client.begin();
```

### Commit

Commit is a convenient wrapper that runs the COMMIT command in SQL to commit a transaction.

```zig
try client.commit();
```

### Savepoint

Savepoint creates a savepoint that you can roll back or release to perform the respective operations.

```zig
try client.savepoint("point");
```

### Rollback

Rollback rolls back to the specified savepoint. If no savepoint is provided, it will roll back the entire transaction.

```zig
try client.rollback(null); // Null for whole transaction or savedpoint name
```

### Release

Release releases the specified savepoint.

```zig
try client.release("point");
```

### CopyIn

Provides a way to bulk-insert data into the database using PostgreSQL's COPY command from the client side.

```zig
var copy_in = try client.copyIn(
    copy_in_sql,
    &.{},
);

for (0..1000) |_| {
    // Look at postgres docs for formatting / depends on query
    try copy_in.write("Firstname\tLastname\t-1\n");
}
```

### CopyOut

Allows you to retrieve bulk data from the database using the COPY command and stream it to the client side. Note CopyData is memory is caller owned. Call deinit to claim memory back.

```zig
var copy_out = try client.copyOut(
    copy_out_sql,
    &.{},
);

while (try copy_out.read()) |row| {
    // CopyData row do whatever
}
```
## DataReader

DataReader manages the reading of query results from a database operation. It tracks the operation’s state, row data, and metadata for result processing, and it provides methods for iterating through rows and accessing query metadata.

### Next

Next retrieves the next data row from the query results. It returns a pointer to the Backend.DataRow or null when there are no more rows. The caller owns the memory and must call deinit to clear the internal buffer.

### Drain

Drain consumes all remaining rows in the result set, deinitializing each row as it's processed, and continues until the result set is exhausted.

### Rows

Rows returns the number of rows affected by the query. Call this after the command has been drained and there are no more rows to return. If there are no rows, it returns 0.

## DataRow

A struct containing a buffer of the data row returned by the database. Ownership is held by the caller, and you must call deinit to free its memory. This struct provides the raw bytes for each value; it's the caller’s responsibility to transform these bytes into any needed format.

### Get

Retrieves the next column’s bytes from the buffer. This function expects a non-null value and will produce an error on null.

### Optional

Retrieves the next column’s bytes from the buffer, allowing for a possible null value.

## Pool

The Pool is a basic connection pool that allows you to set minimum and maximum connections, timeouts, and retry attempts. It also wraps the client function calls for convenience. Will improve later on with keep alive feature and more. Note: acquire will block until it times out if it cannot get a client.

```zig
const connect_info = ConnectInfo{
    .host = "localhost",
    .port = 5433,
    .database = "ziggres",
    .username = "scram_user",
    .password = "password",
};

const settings = Client.Pool.Settings{
    .min = 1,
    .max = 3,
    .timeout = 30_000_000_000,
    .attempts = 3,
};

var pool = try Client.Pool.init(
    allocator,
    connect_info,
    settings,
);
defer pool.deinit();

const client = try pool.acquire();
defer pool.release(client);

// Do whatever with client or grab more
```

## Authentication Support

| Method | Description |
| ------ | ----------- |
| md5 | Don’t use this | 
| scram | SHA-256 is supported but SHA-256-PLUS is not yet available | 
| gss (GSSAPI) | Not supported | 
| sspi | Not supported |
| kerberos | Not supported | 
