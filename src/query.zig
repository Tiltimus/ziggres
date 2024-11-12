const std = @import("std");
const Message = @import("message.zig");
const DataReader = @import("data_reader.zig");
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const CopyIn = @import("copy_in.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

arena_allocator: *ArenaAllocator,
state: State,
data_reader_emitter: EventEmitter(DataReader.Event),
copy_in_emitter: EventEmitter(CopyIn.Event),
row_description: ?Message.RowDescription = null,

const Query = @This();

pub const Event = union(enum) {
    send_query: void,
    send_parse: []const u8,
    send_bind: []?[]const u8,
    send_execute: void,
    send_sync: void,
    send_describe: void,
    read_bind_complete: void,
    read_row_description: void,
    read_query_response: void,
    read_parse_complete: void,
    read_parameter_description: void,
    read_ready_for_query: void,
    read_data_reader: void,
    read_copy_in_response: []u8,
};

pub const State = union(enum) {
    query: []const u8,
    parse: void,
    sent_query: void,
    sent_parse: void,
    sent_bind: void,
    sent_execute: void,
    sent_sync: void,
    sent_describe: void,
    received_query_response: void,
    received_row_description: Message.RowDescription,
    received_parse_complete: void,
    received_bind_complete: void,
    received_parameter_description: Message.ParameterDescription,
    received_no_data: void,
    received_ready_for_query: void,
    error_response: Message.ErrorResponse,
    command_complete: Message.CommandComplete,
    data_reader: DataReader,
    copy_in: CopyIn,
};

pub fn transition(
    self: *Query,
    arena_allocator: *ArenaAllocator,
    event: Event,
    reader: AnyReader,
    writer: AnyWriter,
) !void {
    switch (event) {
        .send_query => {
            switch (self.state) {
                .query => |statement| {
                    const message = Message.Query{
                        .statement = statement,
                    };

                    try Message.write(
                        .{ .query = message },
                        writer,
                    );

                    self.state = .{ .sent_query = undefined };
                },
                else => unreachable,
            }
        },
        .send_parse => |statement| {
            const message = Message.Parse{
                .name = "",
                .query = statement,
            };

            try Message.write(
                .{ .parse = message },
                writer,
            );

            self.state = .{ .sent_parse = undefined };
        },
        .send_bind => |parameters| {
            const message = Message.Bind{
                .portal_name = "",
                .statement_name = "",
                .parameters = parameters,
            };

            try Message.write(
                .{ .bind = message },
                writer,
            );

            self.state = .{ .sent_bind = undefined };
        },
        .send_execute => {
            const message = Message.Execute{
                .portal = "",
                .rows = 0,
            };

            try Message.write(
                .{ .execute = message },
                writer,
            );

            self.state = .{ .sent_execute = undefined };
        },
        .send_sync => {
            const message = Message.Sync{};

            try Message.write(
                .{ .sync = message },
                writer,
            );

            self.state = .{ .sent_sync = undefined };
        },
        .send_describe => {
            const message = Message.Describe{
                .target = .{ .statement = "" },
            };

            try Message.write(
                .{ .describe = message },
                writer,
            );

            self.state = .{ .sent_describe = undefined };
        },
        .read_parse_complete => {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .parse_complete => {
                    self.state = .{ .received_parse_complete = undefined };
                },
                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => unreachable,
            }
        },
        .read_bind_complete => {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .bind_complete => {
                    self.state = .{ .received_bind_complete = undefined };
                },
                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => unreachable,
            }
        },
        .read_row_description => {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .row_description => |row_description| {
                    self.row_description = row_description;
                    self.state = .{ .received_row_description = row_description };
                },
                .no_data => {
                    self.state = .{ .received_no_data = undefined };
                },
                else => unreachable,
            }
        },
        .read_parameter_description => {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .parameter_description => |parameter_description| {
                    self.state = .{ .received_parameter_description = parameter_description };
                },
                else => unreachable,
            }
        },
        .read_ready_for_query => {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .ready_for_query => {
                    self.state = .{ .received_ready_for_query = undefined };
                },
                else => unreachable,
            }
        },
        .read_query_response => {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .row_description => |row_description| {
                    self.state = .{ .received_row_description = row_description };
                },

                .command_complete => |command_complete| {
                    const next_message = try Message.read(reader, arena_allocator);

                    switch (next_message) {
                        .ready_for_query => {
                            const data_reader = DataReader{
                                .arena_allocator = self.arena_allocator,
                                .reader = reader,
                                .state = .{ .command_complete = command_complete },
                                .emitter = self.data_reader_emitter,
                            };

                            self.state = .{ .data_reader = data_reader };
                        },
                        else => unreachable,
                    }
                },

                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => unreachable,
            }
        },
        .read_data_reader => {
            const data_reader = DataReader{
                .arena_allocator = self.arena_allocator,
                .reader = reader,
                .state = .{ .start = undefined },
                .emitter = self.data_reader_emitter,
                .row_description = self.row_description,
            };

            self.state = .{ .data_reader = data_reader };
        },
        .read_copy_in_response => |buffer| {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .copy_in_response => {
                    self.state = .{
                        .copy_in = CopyIn.init(
                            buffer,
                            writer,
                            reader,
                            self.arena_allocator,
                            self.copy_in_emitter,
                        ),
                    };
                },
                else => unreachable,
            }
        },
    }
}
