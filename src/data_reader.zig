const std = @import("std");
const Message = @import("message.zig");
const DataRow = @import("data_row.zig");
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;

const DataReader = @This();

arena_allocator: *ArenaAllocator,
reader: AnyReader,
state: State,
emitter: EventEmitter(Event),

pub const State = union(enum) {
    start: void,
    data_row: DataRow,
    command_complete: Message.CommandComplete,
    error_response: Message.ErrorResponse,
};

pub const Error = error{
    DataReaderOutOfScope,
};

pub const Event = union(enum) {
    next: void,
    data_row: DataRow.Event,
};

pub fn init(
    row_description: Message.RowDescription,
    arena_allocator: ArenaAllocator,
    reader: AnyReader,
) DataReader {
    return DataReader{
        .allocator = arena_allocator,
        .reader = reader,
        .row_description = row_description,
    };
}

pub fn next(self: *DataReader) !?*DataRow {
    try self.emitter.emit(.{ .next = undefined });

    switch (self.state) {
        .data_row => |*data_row| return data_row,
        else => return null,
    }
}

pub fn drain(self: *DataReader) !void {
    while (try self.next()) |data_row| {
        try data_row.drain();
    }
}

pub fn transition(self: *DataReader, event: Event) !void {
    switch (event) {
        .next => {
            switch (self.state) {
                .start => {
                    const message = try Message.read(self.reader, self.arena_allocator);

                    switch (message) {
                        .data_row => |no_context_data_row| {
                            const emitter = EventEmitter(DataRow.Event).init(self, &send_data_row_event);

                            const data_row = DataRow.init(
                                no_context_data_row,
                                emitter,
                            );

                            self.state = .{ .data_row = data_row };
                        },
                        .command_complete => |command_complete| {
                            const next_message = try Message.read(self.reader, self.arena_allocator);

                            switch (next_message) {
                                .ready_for_query => {},
                                else => unreachable,
                            }

                            self.state = .{ .command_complete = command_complete };
                        },
                        .error_response => |error_response| {
                            self.state = .{ .error_response = error_response };
                        },
                        // TODO: Decide how to handle notice_responses
                        .notice_response => |_| {
                            try self.transition(event);
                        },
                        else => unreachable,
                    }
                },
                .data_row => |*prev_data_row| {
                    try prev_data_row.drain();

                    const message = try Message.read(self.reader, self.arena_allocator);

                    switch (message) {
                        .data_row => |no_context_data_row| {
                            const emitter = EventEmitter(DataRow.Event).init(self, &send_data_row_event);

                            const data_row = DataRow.init(
                                no_context_data_row,
                                emitter,
                            );

                            self.state = .{ .data_row = data_row };
                        },
                        .command_complete => |command_complete| {
                            const next_message = try Message.read(self.reader, self.arena_allocator);

                            switch (next_message) {
                                .ready_for_query => {},
                                else => unreachable,
                            }

                            self.state = .{ .command_complete = command_complete };
                        },

                        else => unreachable,
                    }
                },
                .command_complete => {},
                .error_response => {},
            }
        },
        .data_row => |data_row_event| {
            switch (self.state) {
                .data_row => |*data_row| {
                    try data_row.transition(data_row_event);
                },
                else => return Error.DataReaderOutOfScope,
            }
        },
    }
}

fn send_data_row_event(ptr: *anyopaque, event: DataRow.Event) anyerror!void {
    var data_reader: *DataReader = @alignCast(@ptrCast(ptr));

    try data_reader.emitter.emit(.{ .data_row = event });
}

pub fn jsonStringify(self: DataReader, writer: anytype) !void {
    try writer.beginObject();

    try writer.objectField("state");
    try writer.write(self.state);

    try writer.endObject();
}
