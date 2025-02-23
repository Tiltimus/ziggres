const std = @import("std");
const Allocator = std.mem.Allocator;
const Endian = std.builtin.Endian;
const memReadInt = std.mem.readInt;
const assert = std.debug.assert;

pub fn Reader(
    comptime Context: type,
    comptime ReadError: type,
    comptime readFn: fn (context: Context, buffer: []u8) ReadError!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();

        pub const Error = ReadError;
        pub const NoEofError = ReadError || error{
            EndOfStream,
        };

        pub fn read(self: Self, buffer: []u8) Error!usize {
            return readFn(self.context, buffer);
        }

        pub fn readByte(self: Self) NoEofError!u8 {
            var result: [1]u8 = undefined;
            const amt_read = try self.read(result[0..]);
            if (amt_read < 1) return error.EndOfStream;
            return result[0];
        }

        pub fn readAtleast(self: Self, buffer: []u8, len: usize) Error!usize {
            assert(len <= buffer.len);
            var index: usize = 0;
            while (index < len) {
                const amt = try self.read(buffer[index..]);
                if (amt == 0) break;
                index += amt;
            }
            return index;
        }

        pub fn readAll(self: Self, buffer: []u8) NoEofError!usize {
            return self.readAtleast(buffer, buffer.len);
        }

        pub fn readNoEof(self: Self, buf: []u8) NoEofError!void {
            const amt_read = try self.readAll(buf);
            if (amt_read < buf.len) return error.EndOfStream;
        }

        pub fn readBytesNoEof(self: Self, comptime num_bytes: usize) NoEofError![num_bytes]u8 {
            var bytes: [num_bytes]u8 = undefined;
            try self.readNoEof(&bytes);
            return bytes;
        }

        pub fn readInt(
            self: Self,
            comptime T: type,
            endian: Endian,
        ) anyerror!T {
            const bytes = try self.readBytesNoEof(@divExact(@typeInfo(T).int.bits, 8));
            return memReadInt(T, &bytes, endian);
        }

        pub fn readAlloc(self: Self, allocator: Allocator, size: usize) ![]u8 {
            assert(size != 0);
            const buffer = try allocator.alloc(u8, size);

            _ = try self.read(buffer);

            return buffer;
        }
    };
}
