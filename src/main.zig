const std = @import("std");
const Connection = @import("./postgres/connection.zig");
const Diagnostics = @import("./postgres/diagnostics.zig");
const Listener = @import("./postgres/listener.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ConnectInfo = Connection.ConnectInfo;

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const connect_info = .{
        .host = "127.0.0.1",
        .port = 5432,
        .database = "zig",
        .username = "postgres",
        .password = "[password]",
        .diagnostics = Diagnostics.init(),
    };

    var listener = try Listener.init(
        allocator,
        "LISTEN table_change",
        connect_info,
    );

    try listener.listen(allocator, &exec);

    // var connection = try Connection.connect(allocator, connect_info);
    // defer connection.close();

    // var data_reader = try connection.prepare("LISTEN table_change", .{});

    // try data_reader.drain();

    // while (true) {
    //     var buffer: [128]u8 = undefined;

    //     _ = try connection.stream.read(&buffer);

    //     std.log.debug("Bytes: {s}", .{buffer});
    // }
}

fn exec(event: Listener.Event) !void {
    std.log.debug("Message Payload: {s}", .{event.message.payload});
    event.deinit();
}

test "basic crud" {
    const TestTableRow = struct {
        id: i32,
        firstname: []const u8,
        lastname: []const u8,
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const connect_info = .{
        .host = "127.0.0.1",
        .port = 5432,
        .database = "zig",
        .username = "postgres",
        .password = "[password]",
        .diagnostics = Diagnostics.use_std_out(),
    };

    var connection = try Connection.connect(allocator, connect_info);
    defer connection.close();

    _ = try connection.prepare("INSERT INTO test_table VALUES (DEFAULT, $1, $2)", .{ "hello", "world !" });

    _ = try connection.prepare("UPDATE test_table SET firstname = $1, lastname = $2 WHERE firstname = 'hello'", .{ "warrick", "pardoe" });

    var data_reader = try connection.prepare("SELECT * FROM test_table LIMIT 1", .{});

    var test_table_row = try allocator.create(TestTableRow);

    while (try data_reader.next()) |data_row| {
        test_table_row.id = try data_row.from_field(i32, allocator);
        test_table_row.firstname = try data_row.from_field([]const u8, allocator);
        test_table_row.lastname = try data_row.from_field([]const u8, allocator);
    }

    try std.testing.expect(std.mem.eql(u8, test_table_row.firstname, "warrick"));
    try std.testing.expect(std.mem.eql(u8, test_table_row.lastname, "pardoe"));

    _ = try connection.prepare("DELETE FROM test_table WHERE firstname = $1", .{"warrick"});
}
