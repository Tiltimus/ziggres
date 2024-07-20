const std = @import("std");
const Authenticator = @import("./authenticator.zig");
const Query = @import("./query.zig");
const Message = @import("./message.zig");
const ConnectInfo = @import("./connect_info.zig");
const DataReader = @import("./data_reader.zig");
const Network = std.net;
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const parseIp = std.net.Address.parseIp;

const Connection = @This();

allocator: Allocator,
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

    // TODO: Add checks to ensure it doesn't lock in loop
    while (true) {
        try connection.transition();

        switch (connection.state) {
            .ready => break,
            .error_response => break,
            else => continue,
        }
    }

    return connection;
}

pub fn query(self: *Connection, statement: []const u8) !DataReader {
    switch (self.state) {
        .ready => {
            const query_state = Query.init(self.allocator, statement);

            self.state = .{ .querying = query_state };

            while (true) {
                try self.transition();

                switch (self.state) {
                    .querying => |current_query| {
                        switch (current_query.state) {
                            .data_reader => |data_reader| return data_reader,
                            else => {},
                        }
                    },
                    .ready => break,
                    .error_response => break,
                    else => @panic("Fucks sake"),
                }
            }
        },
        else => @panic("Protocol is not in the ready state."),
    }

    @panic("Protocol is not in the ready state.");
}

fn transition(self: *Connection) !void {
    const reader = AnyReader{
        .context = @ptrCast(&self.stream),
        .readFn = &stream_read,
    };

    const writer = AnyWriter{
        .context = @ptrCast(&self.stream),
        .writeFn = &stream_write,
    };

    switch (self.state) {
        .authenticating => |*authenticator| {
            try authenticator.transition(
                reader,
                writer,
            );

            switch (authenticator.state) {
                .authenticated => self.state = (.{ .ready = undefined }),
                .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                else => {},
            }
        },
        .querying => |*current_query| {
            try current_query.transition(
                reader,
                writer,
            );

            switch (current_query.state) {
                .done => self.state = (.{ .ready = undefined }),
                .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                else => {},
            }
        },
        .ready => self.state = self.state, // Ready is an end state
        .error_response => self.state = self.state, // Error response is an end state
    }

    std.log.debug("STATE: {any}", .{self.state});
}

pub const State = union(enum) {
    authenticating: Authenticator,
    querying: Query,
    ready: void,
    error_response: Message.ErrorResponse,

    pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
        const tag_name = @tagName(self);

        try writer.print("{s}", .{tag_name});

        switch (self) {
            .error_response => |error_response| {
                try writer.print(" {any}", .{error_response});
            },

            .authenticating => |authenticator| {
                const auth_tag_name = @tagName(authenticator.state);
                try writer.print(" {s}", .{auth_tag_name});
            },

            .querying => |current_query| {
                const query_tag_name = @tagName(current_query.state);
                try writer.print(" {s}", .{query_tag_name});
            },
            else => {},
        }
    }
};
