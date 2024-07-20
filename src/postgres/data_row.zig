const std = @import("std");
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;

const DataRow = @This();

length: i32,
columns: i16,
cursor: i32,
reader: AnyReader,
allocator: Allocator,

const Error = error{
    UnexpectedNull,
};

pub fn read_struct(_: *DataRow, comptime T: type) !T {}

// TODO: Check that the type is only int something and not something else
pub fn read_int(self: *DataRow, comptime T: type) !T {
    const length = try self.reader.readInt(i32, .big);

    if (length == -1) {
        const is_optional = @typeInfo(T) == .Optional;

        if (!is_optional) return Error.UnexpectedNull;
    }

    const buffer = try self.allocator.alloc(u8, @intCast(length));
    defer self.allocator.free(buffer);

    _ = try self.reader.read(buffer);

    self.cursor = self.cursor + length + 4;

    return try std.fmt.parseInt(T, buffer, 10);
}

pub fn read_alloc(self: *DataRow, allocator: Allocator) ![]u8 {
    const length = try self.reader.readInt(i32, .big);
    const buffer = try allocator.alloc(u8, @intCast(length));

    _ = try self.reader.readAtLeast(buffer, @intCast(length));

    self.cursor = self.cursor + length;

    return buffer;
}

pub fn read_alloc_optional(self: *DataRow, allocator: Allocator) !?[]u8 {
    const length = try self.reader.readInt(i32, .big);

    if (length == -1) return null;

    const buffer = try allocator.alloc(u8, @intCast(length));

    _ = try self.reader.readAtLeast(buffer, @intCast(length));

    self.cursor = self.cursor + length;

    return buffer;
}
pub fn read_buff(self: *DataRow, buffer: []u8) !usize {
    const length = try self.reader.readInt(i32, .big);

    if (length > buffer.len) .Overflow;

    return self.reader.read(buffer);
}

pub fn read_column_alloc(self: *DataRow, comptime T: type, allocator: Allocator) !T {
    comptime {
        const has_from_row = @hasDecl(T, "read_column_alloc");
        const type_name = @typeName(T);

        if (!has_from_row) @compileError("Type: " ++ type_name ++ " does not have function read_column_alloc.");
    }

    const length = try self.reader.readInt(i32, .big);

    return T.read_column_alloc(allocator, length);
}

pub fn read_column_buff(self: *DataRow, comptime T: type, buffer: []u8) !T {
    comptime {
        const has_from_row = @hasDecl(T, "read_column_buff");
        const type_name = @typeName(T);

        if (!has_from_row) @compileError("Type: " ++ type_name ++ " does not have function read_column_buff.");
    }

    const length = try self.reader.readInt(i32, .big);

    return T.read_column_buff(buffer, length);
}
