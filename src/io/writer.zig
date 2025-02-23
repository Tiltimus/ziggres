const std = @import("std");
const Endian = std.builtin.Endian;
const memWriteInt = std.mem.writeInt;

pub fn Writer(
    comptime Context: type,
    comptime WriteError: type,
    comptime writeFn: fn (context: Context, bytes: []const u8) WriteError!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();
        pub const Error = WriteError;

        pub fn write(self: Self, bytes: []const u8) Error!usize {
            return writeFn(self.context, bytes);
        }

        pub fn writeAll(self: Self, bytes: []const u8) Error!void {
            var index: usize = 0;

            while (index != bytes.len) {
                index += try self.write(bytes[index..]);
            }
        }

        pub fn writeInt(
            self: Self,
            comptime T: type,
            value: T,
            endian: Endian,
        ) Error!void {
            var bytes: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;

            memWriteInt(
                std.math.ByteAlignedInt(@TypeOf(value)),
                &bytes,
                value,
                endian,
            );

            return self.writeAll(&bytes);
        }

        pub fn writeByte(self: Self, byte: u8) Error!void {
            const array = [1]u8{byte};

            return self.writeAll(&array);
        }

        pub fn writeCstr(self: Self, str: []const u8) Error!usize {
            if (str.len == 0) {
                try self.writeByte(0);
                return 1;
            }

            const size = try self.write(str);

            try self.writeByte(0);

            return size + 1;
        }

        pub fn writeNullByte(self: Self) Error!void {
            try self.writeByte(0);
        }
    };
}
