const std = @import("std");
const Message = @import("message.zig");
const Types = @import("types.zig");
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const ArrayList = std.ArrayList;
const AnyWriter = std.io.AnyWriter;
const AnyReader = std.io.AnyReader;
const ArenaAllocator = std.heap.ArenaAllocator;
const bufPrint = std.fmt.bufPrint;

const CopyIn = @This();

state: State,
writer: AnyWriter,
reader: AnyReader,
arena_allocator: *ArenaAllocator,
emitter: EventEmitter(Event),
buffer: []u8,
cursor: usize,
row_cursor: usize,

pub const State = union(enum) {
    idle: void,
    writing: void,
    command_complete: Message.CommandComplete,
    error_response: Message.ErrorResponse,
};

pub const Event = union(enum) {
    write_text: void,
    flush: void,
    done: void,
};

pub fn init(
    buffer: []u8,
    writer: AnyWriter,
    reader: AnyReader,
    arean_allocator: *ArenaAllocator,
    emitter: EventEmitter(Event),
) CopyIn {
    // Zero buffer
    @memset(buffer, 0);

    return CopyIn{
        .emitter = emitter,
        .buffer = buffer,
        .state = .{ .idle = undefined },
        .cursor = 0,
        .row_cursor = 0,
        .writer = writer,
        .reader = reader,
        .arena_allocator = arean_allocator,
    };
}

pub fn transition(self: *CopyIn, event: Event) !void {
    switch (event) {
        .write_text => {
            self.state = .{ .writing = undefined };
        },
        .flush => {
            try Message.write(
                .{
                    .copy_data = Message.CopyData{
                        .data = self.buffer[0..self.row_cursor],
                    },
                },
                self.writer,
            );

            self.cursor = 0;
            self.row_cursor = 0;
            @memset(self.buffer, 0);
        },
        .done => {
            try Message.write(
                .{ .copy_done = undefined },
                self.writer,
            );

            try Message.write(
                .{ .sync = undefined },
                self.writer,
            );

            const message = try Message.read(self.reader, self.arena_allocator);

            switch (message) {
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
    }
}

pub fn write(self: *CopyIn, value: anytype) !void {
    self.write_text(value) catch |err| {
        switch (err) {

            // If there is no space left we can flush and try again to rewrite
            error.NoSpaceLeft => {
                try self.flush();
                try self.write(value); // Could loop forever if the buffer is really small check later
            },
            else => return err,
        }
    };
}

pub fn write_text(self: *CopyIn, value: anytype) !void {
    switch (@typeInfo(@TypeOf(value))) {
        .Struct => |strt| {
            const old_cursor = self.cursor;

            inline for (strt.fields, 0..) |field, index| {
                const bytes_written = try Types.to_text_buff(
                    self.buffer[self.cursor..self.buffer.len],
                    @field(value, field.name),
                );

                self.cursor += bytes_written;

                // If the cursor is going to overflow return NoSpaceLeft
                if (self.buffer.len < self.cursor + 1) return error.NoSpaceLeft;

                // Are we at the end of the row or not
                const char = if (strt.fields.len - 1 == index) '\n' else '\t';

                // Print end or row / column
                _ = try bufPrint(self.buffer[self.cursor .. self.cursor + 1], "{c}", .{char});

                self.cursor += 1;
            }

            // Check that we have actually added some bytes / row
            // Before moving the row cursor up
            if (old_cursor < self.cursor) self.row_cursor = self.cursor;
        },
        else => @compileError("Expected struct argument, found" ++ @typeName(value)),
    }

    // Just so it logs
    try self.emitter.emit(.{ .write_text = undefined });
}

pub fn flush(self: *CopyIn) !void {
    try self.emitter.emit(.{ .flush = undefined });
}

pub fn done(self: *CopyIn) !void {
    try self.emitter.emit(.{ .done = undefined });
}

pub fn jsonStringify(self: CopyIn, writer: anytype) !void {
    try writer.beginObject();

    try writer.objectField("state");
    try writer.write(self.state);

    try writer.endObject();
}
