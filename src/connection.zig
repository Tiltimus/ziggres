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
const CopyIn = @import("copy_in.zig");
const Network = std.net;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Json = std.json;
const ArrayList = std.ArrayList;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const allocUpperString = std.ascii.allocUpperString;
const parseIp = std.net.Address.parseIp;

const Connection = @This();

allocator: Allocator,
arena_allocator: ArenaAllocator,
state: State,
stream: Network.Stream,
connect_info: ConnectInfo,

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
    self.transition(.{ .close = undefined }) catch {};
    _ = self.arena_allocator.reset(.free_all);
    self.* = undefined;
}

pub fn execute(self: *Connection, statement: []const u8, parameters: anytype) !void {
    var data_reader = try self.prepare(statement, parameters);
    try data_reader.drain();
}

pub fn insert(self: *Connection, statement: []const u8, parameters: anytype) !void {
    try self.execute(statement, parameters);
}

pub fn insert_returning(
    self: *Connection,
    T: type,
    allocator: Allocator,
    statement: []const u8,
    parameters: anytype,
) ![]T {
    return self.query(T, allocator, statement, parameters);
}

pub fn delete(self: *Connection, statement: []const u8, parameters: anytype) !void {
    try self.execute(statement, parameters);
}

pub fn delete_returning(
    self: *Connection,
    T: type,
    allocator: Allocator,
    statement: []const u8,
    parameters: anytype,
) ![]T {
    return self.query(T, allocator, statement, parameters);
}

pub fn update(self: *Connection, statement: []const u8, parameters: anytype) !void {
    try self.execute(statement, parameters);
}

pub fn update_returning(
    self: *Connection,
    T: type,
    allocator: Allocator,
    statement: []const u8,
    parameters: anytype,
) ![]T {
    return self.query(T, allocator, statement, parameters);
}

pub fn select(
    self: *Connection,
    T: type,
    allocator: Allocator,
    statement: []const u8,
    parameters: anytype,
) ![]T {
    return self.query(T, allocator, statement, parameters);
}

pub fn select_one(
    self: *Connection,
    T: type,
    allocator: Allocator,
    statement: []const u8,
    parameters: anytype,
) !?T {
    var data_reader = try self.prepare(statement, parameters);
    var value: ?T = null;
    const data_row = try data_reader.next();

    if (data_row) |row| {
        value = row.map(T, allocator);
    }

    try data_reader.drain();

    return value;
}

pub fn query(
    self: *Connection,
    T: type,
    allocator: Allocator,
    statement: []const u8,
    parameters: anytype,
) ![]T {
    var data_reader = try self.prepare(statement, parameters);

    return data_reader.map(T, allocator);
}

pub fn prepare(self: *Connection, statement: []const u8, parameters: anytype) !*DataReader {
    switch (self.state) {
        .ready => {
            const allocator = self.arena_allocator.allocator();

            const data = try Types.to_row(
                allocator,
                .text,
                parameters,
            );
            defer data.deinit();

            const data_reader_emitter = EventEmitter(
                DataReader.Event,
            ).init(
                self,
                &send_data_reader_event,
            );
            const copy_in_emitter = EventEmitter(
                CopyIn.Event,
            ).init(
                self,
                &send_copy_in_event,
            );

            const query_state = Query{
                .arena_allocator = &self.arena_allocator,
                .state = .parse,
                .data_reader_emitter = data_reader_emitter,
                .copy_in_emitter = copy_in_emitter,
            };

            self.state = .{ .querying = query_state };

            try self.transition(.{ .querying = .{ .send_parse = statement } });
            try self.transition(.{ .querying = .send_describe });
            try self.transition(.{ .querying = .send_sync });
            try self.transition(.{ .querying = .read_parse_complete });
            try self.transition(.{ .querying = .read_parameter_description });
            try self.transition(.{ .querying = .read_row_description });
            try self.transition(.{ .querying = .read_ready_for_query });
            try self.transition(.{ .querying = .{ .send_bind = data.items } });
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

pub fn copy_in(
    self: *Connection,
    buffer: []u8,
    statement: []const u8,
    parameters: anytype,
) !*CopyIn {
    switch (self.state) {
        .ready => {
            const allocator = self.arena_allocator.allocator();

            const data = try Types.to_row(
                allocator,
                .text,
                parameters,
            );
            defer data.deinit();

            const data_reader_emitter = EventEmitter(DataReader.Event).init(self, &send_data_reader_event);
            const copy_in_emitter = EventEmitter(CopyIn.Event).init(self, &send_copy_in_event);

            const query_state = Query{
                .arena_allocator = &self.arena_allocator,
                .state = .parse,
                .data_reader_emitter = data_reader_emitter,
                .copy_in_emitter = copy_in_emitter,
            };

            self.state = .{ .querying = query_state };

            try self.transition(.{ .querying = .{ .send_parse = statement } });
            try self.transition(.{ .querying = .send_describe });
            try self.transition(.{ .querying = .send_sync });
            try self.transition(.{ .querying = .read_parse_complete });
            try self.transition(.{ .querying = .read_parameter_description });
            try self.transition(.{ .querying = .read_row_description });
            try self.transition(.{ .querying = .read_ready_for_query });
            try self.transition(.{ .querying = .{ .send_bind = data.items } });
            try self.transition(.{ .querying = .send_execute });
            try self.transition(.{ .querying = .send_sync });
            try self.transition(.{ .querying = .read_bind_complete });
            try self.transition(.{ .querying = .{ .read_copy_in_response = buffer } });

            switch (self.state) {
                .copy_in => |*cp_in| return cp_in,
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

// TODO: Rewrite listener
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

fn stream_read(context: *const anyopaque, buffer: []u8) anyerror!usize {
    const connection: *const Connection = @ptrCast(@alignCast(context));
    return try connection.stream.read(buffer);
}

fn stream_write(context: *const anyopaque, bytes: []const u8) anyerror!usize {
    const connection: *const Connection = @ptrCast(@alignCast(context));
    return connection.stream.write(bytes);
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
                        .copy_in => |cp_in| {
                            self.state = .{ .copy_in = cp_in };
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
        .copying_in => |copy_in_event| {
            switch (self.state) {
                .copy_in => |*cp_in| {
                    try cp_in.transition(copy_in_event);

                    switch (cp_in.state) {
                        .command_complete => {
                            self.state = (.{ .ready = undefined });
                            cp_in.* = undefined;
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

fn send_copy_in_event(ptr: *anyopaque, event: CopyIn.Event) !void {
    var connection: *Connection = @alignCast(@ptrCast(ptr));

    try connection.transition(.{ .copying_in = event });
}

fn send_listening_event(ptr: *anyopaque, event: Listener.Event) !void {
    var connection: *Connection = @alignCast(@ptrCast(ptr));

    try connection.transition(.{ .listening = event });
}

pub const Event = union(enum) {
    authenticator: Authenticator.Event,
    querying: Query.Event,
    data_reading: DataReader.Event,
    copying_in: CopyIn.Event,
    listening: Listener.Event,
    close: void,

    pub fn format(self: Event, _: anytype, _: anytype, writer: anytype) !void {
        try writer.writeAll("[EVENT]");
        var buffer: [128]u8 = undefined;
        var fixed_allocator = FixedBufferAllocator.init(&buffer);
        defer fixed_allocator.reset();

        const allocator = fixed_allocator.allocator();

        _ = try writer.write("[");
        try writer.writeAll(try allocUpperString(allocator, @tagName(self)));
        _ = try writer.write("]");

        try Json.stringify(self, .{}, writer);
    }
};

pub const State = union(enum) {
    authenticating: Authenticator,
    querying: Query,
    data_reader: DataReader,
    copy_in: CopyIn,
    ready: void,
    closed: void,
    listening: Listener,
    error_response: Message.ErrorResponse,

    pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
        var buffer: [128]u8 = undefined;
        var fixed_allocator = FixedBufferAllocator.init(&buffer);
        defer fixed_allocator.reset();

        const allocator = fixed_allocator.allocator();

        try writer.writeAll("[STATE]");

        _ = try writer.write("[");
        try writer.writeAll(try allocUpperString(allocator, @tagName(self)));
        _ = try writer.write("]");

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
            .copy_in => |cp_in| {
                try Json.stringify(cp_in.state, .{}, writer);
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
