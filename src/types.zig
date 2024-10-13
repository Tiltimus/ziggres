const std = @import("std");
const Allocator = std.mem.Allocator;
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const split = std.mem.splitAny;

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
                        return_buff[count] = try from_bytes(array.child, buff, allocator);
                        count += 1;
                    }

                    return return_buff;
                },
                else => @compileError("Unsupported type"),
            }
        }
    };
}

pub const Error = error{
    UnexpectedValue,
};

pub fn from_bytes(T: type, input: []const u8) !T {
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

pub fn to_bytes(allocator: Allocator, value: anytype) !?[]const u8 {
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
        .Pointer => return to_bytes(allocator, value.*),
        .Optional => if (value) |inner| return to_bytes(allocator, inner),
        else => @compileError("Unsupported type"),
    }

    return null;
}
