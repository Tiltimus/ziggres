const std = @import("std");
const Connection = @import("connection.zig");
const ConnectInfo = @import("connect_info.zig");
const Message = @import("message.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;

const Listener = @This();

reader: AnyReader,
context: *anyopaque,
send_event: SendEvent,
state: State = .{ .idle = undefined },

pub const SendEvent = *const fn (context: *anyopaque, event: Event) anyerror!void;

pub const State = union(enum) {
    idle: void,
    listening: void,

    pub fn jsonStringify(_: State, writer: anytype) !void {
        try writer.beginObject();

        try writer.endObject();
    }
};

pub const Event = union(enum) {
    listen: Listen,

    pub fn jsonStringify(_: Event, writer: anytype) !void {
        try writer.beginObject();

        try writer.endObject();
    }
};

pub const Listen = struct {
    allocator: Allocator,
    func: *const fn (event: Message.NotificationResponse) anyerror!void,
};

pub fn transition(self: *Listener, event: Event) !void {
    switch (event) {
        .listen => |listen| {
            var arena_allocator = ArenaAllocator.init(listen.allocator);
            defer arena_allocator.deinit();

            const message = try Message.read(self.reader, &arena_allocator);

            switch (message) {
                .notification_response => |notification_response| {
                    try listen.func(notification_response);
                },
                else => unreachable,
            }
        },
    }
}

pub fn on_message(self: *Listener, allocator: Allocator, func: *const fn (event: Message.NotificationResponse) anyerror!void) !void {
    while (self.state == .listening) {
        try self.send_event(self.context, .{
            .listen = Listen{
                .allocator = allocator,
                .func = func,
            },
        });
    }
}

pub fn jsonStringify(_: Listener, writer: anytype) !void {
    try writer.beginObject();

    try writer.endObject();
}
