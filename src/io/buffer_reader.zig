const std = @import("std");
const Endian = std.builtin.Endian;
const mem_read_int = std.mem.readInt;
const eql = std.mem.eql;
const assert = std.debug.assert;

pub const BufferReader = @This();

buffer: []const u8,
pos: usize,

const Self = @This();

pub const ReadError = error{
    EndOfStream,
    UnexpectedValue,
    OutOfBounds,
};

pub fn read(self: *Self, dest: []u8) !usize {
    const size = @min(dest.len, self.buffer.len - self.pos);
    const end = self.pos + size;

    @memcpy(dest[0..size], self.buffer[self.pos..end]);
    self.pos = end;

    return size;
}

pub fn readByte(self: *Self) !u8 {
    var result: [1]u8 = undefined;
    const amt_read = try self.read(result[0..]);
    if (amt_read < 1) return ReadError.EndOfStream;
    return result[0];
}

pub fn readCstr(self: *Self) ![]const u8 {
    const start = self.pos;
    var byte = try self.readByte();

    while (byte != 0 and self.pos != self.buffer.len) {
        byte = try self.readByte();
    }

    return self.buffer[start .. self.pos - 1];
}

pub fn expect(self: *Self, expected: []const u8) !void {
    const actual = self.buffer[self.pos .. self.pos + expected.len];

    if (eql(u8, expected, actual)) {
        self.pos += actual.len;
        return;
    }

    return error.UnexpectedValue;
}

pub fn readUntil(self: *Self, char: u21) ![]const u8 {
    const start = self.pos;
    var byte = try self.readByte();

    while (byte != char) {
        byte = try self.readByte();
    }

    return self.buffer[start .. self.pos - 1];
}

pub fn readUntilEnd(self: *Self) []const u8 {
    const buffer = self.buffer[self.pos..self.buffer.len];

    self.pos = self.buffer.len;

    return buffer;
}

pub fn readAtleast(self: *Self, size: usize) ![]const u8 {
    if (self.pos + size > self.buffer.len) return error.OutOfBounds;

    const bytes = self.buffer[self.pos .. self.pos + size];

    self.pos += size;

    return bytes;
}

pub fn readInt(
    self: *Self,
    comptime T: type,
    endian: Endian,
) anyerror!T {
    var buffer: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
    _ = try self.read(&buffer);
    return mem_read_int(T, &buffer, endian);
}

pub fn reset(self: *Self) void {
    self.pos = 0;
}

pub fn bufferReader(buffer: []const u8) BufferReader {
    return .{ .buffer = buffer, .pos = 0 };
}
