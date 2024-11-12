const std = @import("std");
const Message = @import("message.zig");
const Types = @import("types.zig");
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const from_text = Types.from_text;
const eql = std.mem.eql;

const DataRow = @This();

length: i32,
columns: i16,
current_column: u8 = 0,
reader: AnyReader,
emitter: EventEmitter(Event),
row_description: Message.RowDescription,
state: State = .{ .idle = undefined },

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
    MissingColumn,
};

pub const State = union(enum) {
    idle: void,
    drained: void,
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
    row_description: Message.RowDescription,
    emitter: EventEmitter(Event),
) DataRow {
    return DataRow{
        .length = no_context_data_row.length,
        .reader = no_context_data_row.reader,
        .columns = no_context_data_row.columns,
        .emitter = emitter,
        .row_description = row_description,
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

            self.state = .{ .drained = undefined };
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

// TODO: Better error handling when it either is missing a column or has one too many
pub fn map(self: *DataRow, T: type, allocator: Allocator) !T {
    var value: T = undefined;

    for (self.row_description.columns) |col| {
        inline for (std.meta.fields(T)) |field| {
            if (eql(u8, field.name, col.field_name)) {
                @field(value, field.name) = try self.from_field(field.type, allocator);
                break;
            }
        }
    }

    return value;
}

pub fn drain(self: DataRow) !void {
    if (self.columns == self.current_column) return;

    try self.emitter.emit(.{ .drain = undefined });
}

pub fn read_alloc(self: *DataRow, allocator: Allocator) ![]u8 {
    try self.emitter.emit(.{ .read_alloc = allocator });

    switch (self.state) {
        .read_alloc => |buff| return buff,
        else => unreachable,
    }
}

pub fn read_buff(self: *DataRow, buff: []u8) !usize {
    try self.emitter.emit(.{ .read_buff = buff });

    switch (self.state) {
        .read_buff => |bytes_read| return bytes_read,
        else => unreachable,
    }
}

pub fn read_alloc_optional(self: *DataRow, allocator: Allocator) !?[]u8 {
    try self.emitter.emit(.{ .read_alloc_optional = allocator });

    switch (self.state) {
        .read_alloc_optional => |buff| return buff,
        else => unreachable,
    }
}

pub fn from_field(self: *DataRow, T: type, allocator: Allocator) !T {
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
        .Bool => return try from_text(T, contents),
        .Float => return try from_text(T, contents),
        .Int => return try from_text(T, contents),
        .Enum => return try from_text(T, contents),
        .Array => return try from_text(T, contents),
        .Vector => return try from_text(T, contents),
        .Pointer => return try from_text(T, contents),
        .Optional => |optional| return try from_text(optional.child, contents),
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
    try self.emitter.emit(.{ .read_message_length = undefined });

    switch (self.state) {
        .read_message_length => |length| return length,
        else => unreachable,
    }
}

fn read_reminder_alloc(self: *const DataRow, allocator: Allocator) ![]u8 {
    try self.emitter.emit(.{ .read_reminder_alloc = allocator });

    switch (self.state) {
        .read_reminder_alloc => |buff| return buff,
        else => unreachable,
    }
}
