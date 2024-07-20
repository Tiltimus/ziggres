const std = @import("std");
const Message = @import("./message.zig");
const DataReader = @import("./data_reader.zig");
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;

const Query = @This();

allocator: Allocator,
state: State,

pub fn init(allocator: Allocator, statement: []const u8) Query {
    return Query{
        .allocator = allocator,
        .state = .{ .start_query = statement },
    };
}

pub fn transition(self: *Query, reader: AnyReader, writer: AnyWriter) !void {
    switch (self.state) {
        .start_query => |statement| {
            const message = Message.Query{
                .statement = statement,
            };

            try Message.write(
                .{ .query = message },
                writer,
            );

            self.state = .{ .received_query_response = undefined };
        },
        .received_query_response => {
            const message = try Message.read(
                reader,
            );

            switch (message) {
                .row_description => |row_description| {
                    self.state = .{ .received_row_description = row_description };
                },

                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => @panic("Unexpected message."),
            }
        },
        .received_row_description => |_| {
            const data_reader = DataReader{
                .allocator = self.allocator,
                .reader = reader,
                .data_row = null,
            };

            self.state = .{ .data_reader = data_reader };
        },
        else => @panic("Not yet implemented."),
    }
}

pub const State = union(enum) {
    start_query: []const u8,
    received_query_response: void,
    received_row_description: Message.RowDescription,
    data_reader: DataReader,
    error_response: Message.ErrorResponse,
    done: void,

    pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
        const tag_name = @tagName(self);
        try writer.print("{s}", .{tag_name});
    }
};
