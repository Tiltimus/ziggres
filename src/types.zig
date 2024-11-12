const std = @import("std");
const Message = @import("message.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const split = std.mem.splitAny;

pub const Error = error{
    UnexpectedValue,
};

pub const Row = std.ArrayList(?[]const u8);

// Numerical
pub const SmallInt = i16;

pub const Integer = i32;

pub const BigInt = i64;

pub const Real = f32;

pub const Double = f64;

pub const Serial = i32;

pub const BigSerial = i64;

pub fn Array(comptime T: type) type {
    return struct {
        pub fn from_field(input: []const u8, allocator: Allocator) !T {
            switch (@typeInfo(T)) {
                // TODO: Add support for slices and vectors
                .Array => |array| {
                    // Array literals come back as {1,2,3,4,5}
                    var iterator = split(u8, input[1 .. input.len - 1], ",");
                    var return_buff: [array.len]array.child = undefined;
                    var count: usize = 0;

                    while (iterator.next()) |buff| {
                        return_buff[count] = try to_text(array.child, buff, allocator);
                        count += 1;
                    }

                    return return_buff;
                },
                else => @compileError("Unsupported type"),
            }
        }
    };
}

pub fn to_row(
    allocator: Allocator,
    format: Message.Format,
    value: anytype,
) !Row {
    var row = Row.init(allocator);

    // Parameters should be a tuple of values we convert to a list
    switch (@typeInfo(@TypeOf(value))) {
        .Struct => |strt| {
            inline for (strt.fields) |field| {
                const new_parameter = try to_field(
                    allocator,
                    format,
                    @field(value, field.name),
                );

                try row.append(new_parameter);
            }
        },
        else => @compileError("Expected tuple argument, found" ++ @typeName(value)),
    }

    return row;
}

pub fn from_text(T: type, input: []const u8) !T {
    switch (@typeInfo(T)) {
        .Bool => {
            if (startsWith(u8, input, "t")) return true;
            if (startsWith(u8, input, "f")) return false;

            return Error.UnexpectedValue;
        },
        .Float => return std.fmt.parseFloat(T, input),
        .Int => return std.fmt.parseInt(T, input, 10),
        // TODO: Make a bit better by lower casing everything
        .Enum => {
            if (std.meta.stringToEnum(T, input)) |value| return value;

            return Error.UnexpectedValue;
        },
        .Array => |array| {
            var return_buff: [array.len]array.child = undefined;

            for (0..return_buff.len) |index| {
                if (input.len <= index) break;
                return_buff[index] = input[index];
            }

            return return_buff;
        },
        .Pointer => |pointer| {
            // Only deal with slices for the minute
            switch (pointer.size) {
                // TODO: Check if it is []u8 and [] const u8 make sure it gets casted correctly
                .Slice => return input,
                else => @compileError("Unsupported pointer type"),
            }
        },
        else => @compileError("Unsupported type"),
    }
}

pub fn to_text(allocator: Allocator, value: anytype) !?[]const u8 {
    switch (@typeInfo(@TypeOf(value))) {
        .Bool => {
            switch (value) {
                true => return try allocator.dupe(u8, "true"),
                false => return try allocator.dupe(u8, "false"),
            }
        },
        .Float => return try std.fmt.allocPrint(allocator, "{d}", .{value}),
        .Int => return try std.fmt.allocPrint(allocator, "{d}", .{value}),
        .Enum => return @tagName(value),
        .Array => return try allocator.dupe(u8, &value),
        .Pointer => |pointer| {
            switch (pointer.size) {
                .Slice => {
                    if (@TypeOf([]const u8) == @TypeOf(value)) return value;

                    var bytes = ArrayList([]const u8).init(allocator);
                    defer bytes.deinit();

                    for (value) |item| {
                        if (try to_text(allocator, item)) |something| {
                            try bytes.append(something);
                        }
                    }
                },
                .One => {
                    return to_text(allocator, value.*);
                },
                else => @compileError("Not yet supported"),
            }
        },
        .Optional => if (value) |inner| return to_text(allocator, inner),
        else => @compileError("Unsupported type"),
    }

    return null;
}

pub fn to_text_buff(buffer: []u8, value: anytype) !usize {
    switch (@typeInfo(@TypeOf(value))) {
        .Bool => {
            switch (value) {
                true => {
                    @memcpy(buffer, "true");
                    return 4;
                },
                false => {
                    @memcpy(buffer, "false");
                    return 5;
                },
            }
        },
        .Float => return try std.fmt.bufPrint(buffer, "{d}", .{value}),
        .Int => {
            const slice = try std.fmt.bufPrint(buffer, "{d}", .{value});

            return slice.len;
        },
        .Enum => return try std.fmt.bufPrint(buffer, "{s}", .{@tagName(value)}),
        // .Array => unreachable,
        .Pointer => |pointer| {
            switch (pointer.size) {
                .Slice => {
                    if ([]const u8 == @TypeOf(value)) {
                        const slice = try std.fmt.bufPrint(buffer, "{s}", .{value});
                        return slice.len;
                    }

                    unreachable;
                },
                .One => {
                    return try to_text_buff(buffer, value.*);
                },
                else => @compileError("Not yet supported"),
            }
        },
        .Optional => if (value) |inner| return try to_text_buff(buffer, inner),
        else => @compileError("Unsupported type"),
    }
}

pub fn from_binary(T: type, _: []const u8) !T {}
pub fn to_binary(_: Allocator, _: anytype) !?[]const u8 {
    unreachable;
}

pub fn from_field(T: type, format: Message.Format, input: []const u8) !T {
    switch (format) {
        .binary => return try from_binary(T, input),
        .text => return try from_text(T, input),
    }
}
pub fn to_field(allocator: Allocator, format: Message.Format, value: anytype) !?[]const u8 {
    switch (format) {
        .binary => return try to_binary(allocator, value),
        .text => return try to_text(allocator, value),
    }
}
