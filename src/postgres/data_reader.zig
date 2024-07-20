const std = @import("std");
const DataRow = @import("./data_row.zig");
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;

const DataReader = @This();

allocator: Allocator,
reader: AnyReader,
data_row: ?DataRow,

pub fn init(allocator: Allocator, reader: AnyReader) DataReader {
    return DataReader{
        .allocator = allocator,
        .reader = reader,
    };
}

pub fn next(self: *DataReader) !?*DataRow {
    // Check message type
    switch (try self.reader.readByte()) {
        'D' => {
            const message_len = try self.reader.readInt(i32, .big);
            const columns: i16 = try self.reader.readInt(i16, .big);

            self.data_row = DataRow{
                .length = message_len,
                .columns = columns,
                .reader = self.reader,
                .allocator = self.allocator,
                .cursor = 0,
            };

            return &self.data_row.?;
        },

        else => {
            self.data_row = null;
            return null;
        },
    }
}
