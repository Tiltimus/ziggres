const std = @import("std");
const Authenticator = @import("authenticator.zig");
const Query = @import("query.zig");
const DataRow = @import("data_row.zig");
const Message = @import("message.zig");
const ConnectInfo = @import("connect_info.zig");
const DataReader = @import("data_reader.zig");
const Listener = @import("listener.zig");
const Types = @import("types.zig");
const Datetime = @import("datetime.zig");
const EventEmitter = @import("event_emitter.zig").EventEmitter;
const Network = std.net;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Json = std.json;
const ArrayList = std.ArrayList;
const parseIp = std.net.Address.parseIp;

const Connection = @This();

allocator: Allocator,
arena_allocator: ArenaAllocator,
state: State,
stream: Network.Stream,
connect_info: ConnectInfo,

fn stream_read(context: *const anyopaque, buffer: []u8) anyerror!usize {
    const connection: *const Connection = @ptrCast(@alignCast(context));
    return try connection.stream.read(buffer);
}

fn stream_write(context: *const anyopaque, bytes: []const u8) anyerror!usize {
    const connection: *const Connection = @ptrCast(@alignCast(context));
    return connection.stream.write(bytes);
}

pub fn connect(allocator: Allocator, connect_info: ConnectInfo) !Connection {
    const stream = try Network.tcpConnectToHost(allocator, connect_info.host, connect_info.port);
    errdefer stream.close();

    const authenticator = Authenticator.init(connect_info);
    const initial_state = State{ .authenticating = authenticator };
    const arena_allocator = ArenaAllocator.init(allocator);

    var connection = Connection{
        .stream = stream,
        .state = initial_state,
        .allocator = allocator,
        .arena_allocator = arena_allocator,
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
    // No idea if this is good but I wanted the defer close :(
    self.transition(.{ .close = undefined }) catch
        @panic("Failed to close connection");

    self.* = undefined;
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

            const event_emitter = EventEmitter(DataReader.Event).init(self, &send_data_reader_event);

            const query_state = Query{
                .arena_allocator = &self.arena_allocator,
                .state = .parse,
                .emitter = event_emitter,
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

            switch (self.state) {
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
            const event_emitter = EventEmitter(DataReader.Event).init(self, &send_data_reader_event);

            const query_state = Query{
                .allocator = self.allocator,
                .state = .{ .query = statement },
                .emitter = event_emitter,
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

    // For some reason the complier doesn't catch the ureachable in the switch
    unreachable;
}

// TODO: Rewrite listen
pub fn listen(self: *Connection, statement: []const u8, func: *const fn (event: Message.NotificationResponse) anyerror!void) !void {
    switch (self.state) {
        .ready => {
            var data_reader = try self.prepare(statement, .{});

            try data_reader.drain();

            const reader = self.any_reader();

            const event_emitter = EventEmitter(Listener.Event).init(self, &send_listening_event);

            const listener = Listener{
                .reader = reader,
                .emitter = event_emitter,
                .state = .{ .listening = undefined },
            };

            self.state = .{ .listening = listener };

            switch (self.state) {
                .listening => |*listening| {
                    try listening.on_message(self.allocator, func);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn any_reader(self: *Connection) AnyReader {
    return AnyReader{
        .context = @ptrCast(self),
        .readFn = &stream_read,
    };
}

pub fn any_writer(self: *Connection) AnyWriter {
    return AnyWriter{
        .context = @ptrCast(self),
        .writeFn = &stream_write,
    };
}

fn transition(self: *Connection, event: Event) !void {
    const reader = self.any_reader();

    const writer = self.any_writer();

    switch (event) {
        .authenticator => |auth_event| {
            switch (self.state) {
                .authenticating => |*authenticator| {
                    try authenticator.transition(
                        &self.arena_allocator,
                        auth_event,
                        reader,
                        writer,
                    );

                    switch (authenticator.state) {
                        .authenticated => {
                            self.state = (.{ .ready = undefined });
                            _ = self.arena_allocator.reset(.free_all);
                        },
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
                        &self.arena_allocator,
                        query_event,
                        reader,
                        writer,
                    );

                    switch (current_query.state) {
                        .command_complete => {
                            self.state = (.{ .ready = undefined });
                            _ = self.arena_allocator.reset(.free_all);
                        },
                        .data_reader => |data_reader| {
                            self.state = .{ .data_reader = data_reader };
                        },
                        .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .data_reading => |data_reading_event| {
            switch (self.state) {
                .data_reader => |*data_reader| {
                    try data_reader.transition(data_reading_event);

                    switch (data_reader.state) {
                        .command_complete => {
                            self.state = (.{ .ready = undefined });
                            data_reader.* = undefined;
                            _ = self.arena_allocator.reset(.free_all);
                        },
                        .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .listening => |listener_event| {
            switch (self.state) {
                .listening => |*listener| {
                    try listener.transition(listener_event);
                },
                else => unreachable,
            }
        },
        .close => {
            _ = try Message.write(.{ .terminate = undefined }, writer);
            _ = self.arena_allocator.reset(.free_all);
            self.state = .{ .closed = undefined };
        },
    }

    if (self.connect_info.diagnostics) |diagnostics| {
        try diagnostics.log(.{event});
        try diagnostics.log(.{self.state});
    }
}

fn send_data_reader_event(ptr: *anyopaque, event: DataReader.Event) !void {
    var connection: *Connection = @alignCast(@ptrCast(ptr));

    try connection.transition(.{ .data_reading = event });
}

fn send_listening_event(ptr: *anyopaque, event: Listener.Event) !void {
    var connection: *Connection = @alignCast(@ptrCast(ptr));

    try connection.transition(.{ .listening = event });
}

pub const Event = union(enum) {
    authenticator: Authenticator.Event,
    querying: Query.Event,
    data_reading: DataReader.Event,
    listening: Listener.Event,
    close: void,

    pub fn format(self: Event, _: anytype, _: anytype, writer: anytype) !void {
        try writer.writeAll("[EVENT]");
        try Json.stringify(self, .{}, writer);
    }
};

pub const State = union(enum) {
    authenticating: Authenticator,
    querying: Query,
    data_reader: DataReader,
    ready: void,
    closed: void,
    listening: Listener,
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
            .data_reader => |data_reader| {
                try Json.stringify(data_reader.state, .{}, writer);
            },
            .ready => {
                try Json.stringify(@tagName(self), .{}, writer);
            },
            .listening => {
                try Json.stringify(@tagName(self), .{}, writer);
            },
            .closed => {
                try Json.stringify(@tagName(self), .{}, writer);
            },
        }
    }
};
