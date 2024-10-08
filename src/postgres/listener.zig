const std = @import("std");
const Connection = @import("./connection.zig");
const ConnectInfo = @import("./connect_info.zig");
const Message = @import("./message.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const Listener = @This();

connection: Connection,

pub fn init(allocator: Allocator, statement: []const u8, connect_info: ConnectInfo) !Listener {
    var connection = try Connection.connect(allocator, connect_info);

    var data_reader = try connection.prepare(statement, .{});

    try data_reader.drain();

    return Listener{
        .connection = connection,
    };
}

pub fn listen(self: *Listener, allocator: Allocator, func: *const fn (event: Event) anyerror!void) !void {
    while (true) {
        const reader = self.connection.stream.reader().any();
        var arena_allocator = ArenaAllocator.init(allocator);
        const message = try Message.read(reader, &arena_allocator);

        switch (message) {
            .notification_response => |notification_response| {
                const event = Event{
                    .arena_allocator = arena_allocator,
                    .message = notification_response,
                };

                try func(event);
            },
            else => unreachable,
        }
    }
}

pub const Event = struct {
    arena_allocator: ArenaAllocator,
    message: Message.NotificationResponse,

    pub fn deinit(self: Event) void {
        self.arena_allocator.deinit();
    }
};
