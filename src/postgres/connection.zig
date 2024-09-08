const std = @import("std");
const Authenticator = @import("./authenticator.zig");
const Query = @import("./query.zig");
const DataRow = @import("./data_row.zig");
const Message = @import("./message.zig");
const ConnectInfo = @import("./connect_info.zig");
const DataReader = @import("./data_reader.zig");
const Types = @import("./types.zig");
const Datetime = @import("../datetime.zig");
const Network = std.net;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Json = std.json;
const ArrayList = std.ArrayList;
const parseIp = std.net.Address.parseIp;

// TODO: I've done the event stuff wrong, need to pull everything to this level
// Then have it transition at this level otherwise it will incorrectly log
// As it is recursively calling the transition without breaking out
// Logic should be sound just needs moving about

const Connection = @This();

allocator: Allocator, // TODO: Probably gonna wanna switch out for an arena allocator
state: State,
stream: Network.Stream,
connect_info: ConnectInfo,

fn stream_read(context: *const anyopaque, buffer: []u8) anyerror!usize {
    const ptr: *const Network.Stream = @alignCast(@ptrCast(context));
    return Network.Stream.read(ptr.*, buffer);
}

fn stream_write(context: *const anyopaque, bytes: []const u8) anyerror!usize {
    const ptr: *const Network.Stream = @alignCast(@ptrCast(context));
    return Network.Stream.write(ptr.*, bytes);
}

pub fn connect(allocator: Allocator, connect_info: ConnectInfo) !Connection {
    const stream = try Network.tcpConnectToHost(allocator, connect_info.host, connect_info.port);
    errdefer stream.close();

    const authenticator = Authenticator.init(connect_info);
    const initial_state = State{ .authenticating = authenticator };

    var connection = Connection{
        .stream = stream,
        .state = initial_state,
        .allocator = allocator,
        .connect_info = connect_info,
    };

    try connection.authenticate();

    return connection;
}

fn authenticate(self: *Connection) !void {
    try self.transition(.{ .authenticator = .send_startup_message });
    try self.transition(.{ .authenticator = .read_authentication });

    switch (self.state) {
        .authenticating => |authenticator| {
            switch (authenticator.state) {
                .received_sasl => {
                    try self.transition(.{ .authenticator = .send_sasl_initial_response });
                    try self.transition(.{ .authenticator = .read_sasl_continue });
                    try self.transition(.{ .authenticator = .send_sasl_response });
                    try self.transition(.{ .authenticator = .read_sasl_final });
                    try self.transition(.{ .authenticator = .read_authentication_ok });
                },
                // TODO: Add support for other authentication paths
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn close(self: *Connection) void {
    self.transition(.{ .close = undefined }) catch
        @panic("Failed to close connection");
}

// TODO: Maybe rename to extended query i dunno
pub fn prepare(self: *Connection, statement: []const u8, parameters: anytype) !*DataReader {
    switch (self.state) {
        .ready => {
            const ByteArrayList = ArrayList(?[]const u8);

            var arena_allocator = ArenaAllocator.init(self.allocator);
            defer arena_allocator.deinit();

            var byte_array_list = ByteArrayList.init(self.allocator);
            defer byte_array_list.deinit();

            // Parameters should be a tuple of values we convert to a list
            switch (@typeInfo(@TypeOf(parameters))) {
                .Struct => |strt| {
                    // Only work with tuples for the minute
                    if (!strt.is_tuple) @compileError("Expected tuple argument, found" ++ @typeName(parameters));

                    inline for (strt.fields, 0..) |_, index| {
                        const new_parameter = try Types.to_bytes(arena_allocator.allocator(), parameters[index]);
                        try byte_array_list.append(new_parameter);
                    }
                },
                else => @compileError("Expected tuple argument, found" ++ @typeName(parameters)),
            }

            const query_state = Query{
                .allocator = self.allocator,
                .state = .parse,
                .context = @ptrCast(self),
                .send_event = &send_data_reader_event,
            };

            self.state = .{ .querying = query_state };

            try self.transition(.{ .querying = .{ .send_parse = statement } });
            try self.transition(.{ .querying = .send_describe });
            try self.transition(.{ .querying = .send_sync });
            try self.transition(.{ .querying = .read_parse_complete });
            try self.transition(.{ .querying = .read_parameter_description });
            try self.transition(.{ .querying = .read_row_description });
            try self.transition(.{ .querying = .read_ready_for_query });
            try self.transition(.{ .querying = .{ .send_bind = byte_array_list.items } });
            try self.transition(.{ .querying = .send_execute });
            try self.transition(.{ .querying = .send_sync });
            try self.transition(.{ .querying = .read_bind_complete });
            try self.transition(.{ .querying = .read_data_reader });

            switch (self.state.querying.state) {
                .data_reader => |*data_reader| return data_reader,
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

// TODO: Rename and sort out to only use simple query
// Needs to support being able to handle multiple queries and yadyadaaa
pub fn query(self: *Connection, statement: []const u8) !*DataReader {
    switch (self.state) {
        .ready => {
            const query_state = Query{
                .allocator = self.allocator,
                .state = .{ .query = statement },
                .context = @ptrCast(self),
                .send_event = &send_data_reader_event,
            };

            self.state = .{ .querying = query_state };

            try self.transition(.{ .querying = .send_query });
            try self.transition(.{ .querying = .read_query_response });

            switch (self.state.querying.state) {
                .data_reader => |*data_reader| return data_reader,
                .received_row_description => {
                    try self.transition(.{ .querying = .read_data_reader });

                    switch (self.state.querying.state) {
                        .data_reader => |*data_reader| return data_reader,
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .querying => |*current_query| {
            switch (current_query.state) {
                .data_reader => |*data_reader| {

                    // Drain current data_reader and ensure stream has been cleared
                    try data_reader.drain();

                    // Set state ready
                    self.state = .{ .ready = undefined };

                    // Recursive call probably better way to write it but too much haskell brain
                    return self.query(statement);
                },
                .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                else => unreachable,
            }
        },
        else => unreachable,
    }

    unreachable;
}

fn transition(self: *Connection, event: Event) !void {
    const stdout = std.io.getStdOut();
    const stdout_writer = stdout.writer().any();
    const datetime = Datetime.now();

    const reader = AnyReader{
        .context = @ptrCast(&self.stream),
        .readFn = &stream_read,
    };

    const writer = AnyWriter{
        .context = @ptrCast(&self.stream),
        .writeFn = &stream_write,
    };

    switch (event) {
        .authenticator => |auth_event| {
            switch (self.state) {
                .authenticating => |*authenticator| {
                    try authenticator.transition(
                        self.allocator,
                        auth_event,
                        reader,
                        writer,
                    );

                    switch (authenticator.state) {
                        .authenticated => self.state = (.{ .ready = undefined }),
                        .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .querying => |query_event| {
            switch (self.state) {
                .querying => |*current_query| {
                    try current_query.transition(
                        self.allocator,
                        query_event,
                        reader,
                        writer,
                    );

                    switch (current_query.state) {
                        .command_complete => self.state = (.{ .ready = undefined }),
                        .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .data_reading => |data_reading_event| {
            switch (self.state) {
                .querying => |*current_query| {
                    try current_query.transition(
                        self.allocator,
                        .{ .data_reading = data_reading_event },
                        reader,
                        writer,
                    );

                    switch (current_query.state) {
                        .command_complete => self.state = (.{ .ready = undefined }),
                        .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .close => {
            _ = try Message.write(.{ .terminate = undefined }, writer);

            self.state = .{ .closed = undefined };
        },
    }

    try stdout_writer.print("[{}]{s}\n", .{ datetime, event });
    try stdout_writer.print("[{}]{s}\n", .{ datetime, self.state });
}

fn send_data_reader_event(ptr: *anyopaque, event: DataReader.Event) !void {
    var connection: *Connection = @alignCast(@ptrCast(ptr));

    try connection.transition(.{ .data_reading = event });
}

pub const Event = union(enum) {
    authenticator: Authenticator.Event,
    querying: Query.Event,
    data_reading: DataReader.Event,
    close: void,

    pub fn format(self: Event, _: anytype, _: anytype, writer: anytype) !void {
        try writer.writeAll("[EVENT]");
        try Json.stringify(self, .{}, writer);
    }
};

pub const State = union(enum) {
    authenticating: Authenticator,
    querying: Query,
    ready: void,
    closed: void,
    error_response: Message.ErrorResponse,

    pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
        try writer.writeAll("[STATE]");

        switch (self) {
            .error_response => |error_response| {
                try Json.stringify(error_response, .{}, writer);
            },

            .authenticating => |authenticator| {
                try Json.stringify(authenticator.state, .{}, writer);
            },

            .querying => |current_query| {
                try Json.stringify(current_query.state, .{}, writer);
            },
            .ready => {
                try Json.stringify(@tagName(self), .{}, writer);
            },
            .closed => {
                try Json.stringify(@tagName(self), .{}, writer);
            },
        }
    }
};
