const std = @import("std");
const Message = @import("./message.zig");
const Types = @import("types.zig");
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const from_bytes = Types.from_bytes;

const DataRow = @This();

length: i32,
columns: i16,
current_column: u8 = 0,
reader: AnyReader,
context: *anyopaque,
send_event: SendEvent,
state: State = .{ .idle = undefined },

pub const SendEvent = *const fn (context: *anyopaque, event: Event) anyerror!void;

pub const NoContextDataRow = struct {
    length: i32,
    columns: i16,
    current_column: u8 = 0,
    reader: AnyReader,
};

pub const Error = error{
    UnexpectedNull,
    UnexpectedValue,
    OutOfBounds,
};

pub const State = union(enum) {
    idle: void,
    read_message_length: i32,
    read_reminder_alloc: []u8,
    read_alloc: []u8,
    read_buff: usize,
    read_alloc_optional: ?[]u8,
};

pub const Event = union(enum) {
    read_message_length: void,
    read_reminder_alloc: Allocator,
    read_buff: []u8,
    read_alloc: Allocator,
    read_alloc_optional: Allocator,
    drain: void,

    pub fn jsonStringify(self: Event, writer: anytype) !void {
        const tag_name = @tagName(self);
        try writer.beginObject();

        try writer.objectField("type");
        try writer.write(tag_name);

        try writer.endObject();
    }
};

pub fn init(
    no_context_data_row: NoContextDataRow,
    context: *anyopaque,
    send_event: SendEvent,
) DataRow {
    return DataRow{
        .length = no_context_data_row.length,
        .reader = no_context_data_row.reader,
        .columns = no_context_data_row.columns,
        .context = context,
        .send_event = send_event,
    };
}

pub fn transition(self: *DataRow, event: Event) !void {
    switch (event) {
        .read_message_length => {
            if (self.columns == self.current_column) return Error.OutOfBounds;

            const length = try self.reader.readInt(i32, .big);

            self.state = .{ .read_message_length = length };
        },
        .read_reminder_alloc => |allocator| {
            // We can only read the reminder if we have read the length
            switch (self.state) {
                .read_message_length => |message_length| {
                    if (message_length == -1) return Error.UnexpectedNull;

                    const buffer = try allocator.alloc(u8, @intCast(message_length));

                    _ = try self.reader.readAtLeast(buffer, @intCast(message_length));

                    self.state = .{ .read_reminder_alloc = buffer };
                    self.current_column += 1;
                },
                else => unreachable,
            }
        },
        .read_buff => |buffer| {
            if (self.columns == self.current_column) return Error.OutOfBounds;

            const length = try self.reader.readInt(i32, .big);

            // If null return 0 bytes read
            if (length == -1) {
                self.state = .{ .read_buff = 0 };
                return;
            }

            const bytes_read = try self.reader.readAtLeast(buffer, @intCast(length));

            self.state = .{ .read_buff = bytes_read };
            self.current_column += 1;
        },
        .read_alloc => |allocator| {
            if (self.columns == self.current_column) return Error.OutOfBounds;

            const length = try self.reader.readInt(i32, .big);

            if (length == -1) return Error.UnexpectedNull;

            const buffer = try allocator.alloc(u8, @intCast(length));

            _ = try self.reader.readAtLeast(buffer, @intCast(length));

            self.state = .{ .read_alloc = buffer };
            self.current_column += 1;
        },
        .drain => {
            while (self.current_column != self.columns) {
                const length = try self.reader.readInt(i32, .big);

                _ = try self.reader.skipBytes(@intCast(length), .{});
                self.current_column += 1;
            }
        },
        .read_alloc_optional => |allocator| {
            if (self.columns == self.current_column) return Error.OutOfBounds;

            const length = try self.reader.readInt(i32, .big);

            if (length == -1) {
                self.state = .{ .read_alloc_optional = null };
                self.current_column += 1;
                return;
            }

            const buffer = try allocator.alloc(u8, @intCast(length));

            _ = try self.reader.readAtLeast(buffer, @intCast(length));

            self.state = .{ .read_alloc_optional = buffer };
            self.current_column += 1;
        },
    }
}

pub fn drain(self: *const DataRow) !void {
    if (self.columns == self.current_column) return;

    try self.send_event(self.context, .{ .drain = undefined });
}

pub fn read_alloc(self: *const DataRow, allocator: Allocator) ![]u8 {
    try self.send_event(self.context, .{ .read_alloc = allocator });

    switch (self.state) {
        .read_alloc => |buff| return buff,
        else => unreachable,
    }
}

pub fn read_buff(self: *const DataRow, buff: []u8) !usize {
    try self.send_event(self.context, .{ .read_buff = buff });

    switch (self.state) {
        .read_buff => |bytes_read| return bytes_read,
        else => unreachable,
    }
}

pub fn read_alloc_optional(self: *const DataRow, allocator: Allocator) !?[]u8 {
    try self.send_event(self.context, .{ .read_alloc_optional = allocator });

    switch (self.state) {
        .read_alloc_optional => |buff| return buff,
        else => unreachable,
    }
}

pub fn from_field(self: *const DataRow, T: type, allocator: Allocator) !T {
    const message_length = try self.read_message_length();

    // Check for null
    switch (@typeInfo(T)) {
        .Optional => {
            if (message_length == -1) return null;
        },
        else => {
            if (message_length == -1) return Error.UnexpectedNull;
        },
    }

    // Should now be safe to read the rest if there is content
    const contents = try self.read_reminder_alloc(allocator);
    defer {
        // Only free the contents if not a slice of []u8 otherwise just return
        // TODO: Recurse call type to ensure optional works correctly
        switch (@typeInfo(T)) {
            .Pointer => |pointer| {
                switch (pointer.size) {
                    .Slice => {},
                    else => allocator.free(contents),
                }
            },
            else => allocator.free(contents),
        }
    }
    // Check for user defined def and pass the contents and allocator in
    if (std.meta.hasFn(T, "from_field")) {
        return T.from_field(contents, allocator);
    }

    switch (@typeInfo(T)) {
        .Bool => return try from_bytes(T, contents),
        .Float => return try from_bytes(T, contents),
        .Int => return try from_bytes(T, contents),
        .Enum => return try from_bytes(T, contents),
        .Array => return try from_bytes(T, contents),
        .Vector => return try from_bytes(T, contents),
        .Pointer => return try from_bytes(T, contents),
        .Optional => |optional| return try from_bytes(optional.child, contents),
        else => @compileError("Unsupported type"),
    }
}

pub fn jsonStringify(self: DataRow, writer: anytype) !void {
    try writer.beginObject();

    try writer.objectField("length");
    try writer.write(self.length);

    try writer.objectField("columns");
    try writer.write(self.columns);

    try writer.objectField("current_column");
    try writer.write(self.current_column);

    try writer.endObject();
}

fn read_message_length(self: *const DataRow) !i32 {
    try self.send_event(self.context, .{ .read_message_length = undefined });

    switch (self.state) {
        .read_message_length => |length| return length,
        else => unreachable,
    }
}

fn read_reminder_alloc(self: *const DataRow, allocator: Allocator) ![]u8 {
    try self.send_event(self.context, .{ .read_reminder_alloc = allocator });

    switch (self.state) {
        .read_reminder_alloc => |buff| return buff,
        else => unreachable,
    }
}
