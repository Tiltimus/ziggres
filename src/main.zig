const std = @import("std");
const Connection = @import("connection.zig");
const Diagnostics = @import("diagnostics.zig");
const Listener = @import("listener.zig");
const Message = @import("message.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ConnectInfo = Connection.ConnectInfo;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const connect_info = .{
        .host = "db",
        .port = 5432,
        .database = "ziggres",
        .username = "root",
        .password = "G7TWaw4aTmGS",
        .diagnostics = Diagnostics.init(),
    };

    var connection = try Connection.connect(allocator, connect_info);
    defer connection.close();

    // var data_reader = try connection.prepare("SELECT * FROM test_table", .{});

    // while (try data_reader.next()) |data_row| {
    //     try data_row.drain();
    // }

    _ = try connection.listen("LISTEN table_change", &table_change);
}

fn stream_read_listen(connection: *Connection) !void {
    var cond = std.Thread.Condition{};

    while (connection.state == .ready) {
        connection.stream_mutex.lock();
        defer connection.stream_mutex.unlock();

        var buffer: [128]u8 = undefined;

        std.log.debug("READ THREAD BEFORE", .{});
        _ = try connection.stream.readAll(&buffer);
        std.log.debug("READ THREAD AFTER", .{});

        cond.wait(&connection.stream_mutex);
    }
}

fn table_change(_: Message.NotificationResponse) !void {
    std.log.debug("MESSAGE", .{});
}
