const std = @import("std");
const Connection = @import("connection.zig");
const Diagnostics = @import("diagnostics.zig");
const Listener = @import("listener.zig");
const Message = @import("message.zig");
const Protocol = @import("protocol.zig");
const Types = @import("types.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ConnectInfo = Connection.ConnectInfo;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

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

    var buffer: [1400]u8 = undefined;

    var copier = try connection.copy_in(
        &buffer,
        "COPY test_table (firstname, lastname) FROM STDIN WITH (FORMAT text)",
        .{},
    );

    for (0..1000) |_| {
        try copier.write(TestTableRow{ .firstname = "Don", .lastname = "Trump" });
    }

    try copier.flush();

    try copier.done();
}

const TestTableRow = struct {
    firstname: []const u8,
    lastname: []const u8,
};

pub const Something = union(enum) {
    write_text: *anyopaque,
};

fn example(value: anytype) void {
    const x: *anyopaque = @ptrCast(value);
    const y = .{ .write_text = x };

    std.log.debug("{any}", .{y});
}
