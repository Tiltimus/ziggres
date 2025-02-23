const std = @import("std");
pub const Protocol = @import("protocol.zig");
pub const ConnectInfo = @import("protocol/connect_info.zig");
const Authenticator = @import("state_machine/authenticator.zig");
const Query = @import("state_machine/query.zig");
const DataReader = @import("state_machine/data_reader.zig");
const CopyIn = @import("state_machine/copy_in.zig");
const CopyOut = @import("state_machine/copy_out.zig");
const Backend = @import("protocol/backend.zig").Backend;
const StateMachine = @import("state_machine.zig").StateMachine;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Client = @This();

state: State,
protocol: Protocol,
connect_info: ConnectInfo,

pub const State = union(enum) {
    init: void,
    authenticator: Authenticator,
    querying: Query,
    data_reader: *DataReader,
    copy_in: *CopyIn,
    copy_out: *CopyOut,
    ready: void,
    closed: void,
    error_response: Backend.ErrorResponse,
};

pub const Event = union(enum) {
    authenticator: Authenticator.Event,
    querying: Query.Event,
    data_reading: DataReader.Event,
    copying_in: CopyIn.Event,
    copying_out: CopyOut.Event,
};

pub fn connect(allocator: Allocator, connect_info: ConnectInfo) !Client {
    const protocol = Protocol.init(allocator);

    var client = Client{
        .protocol = protocol,
        .connect_info = connect_info,
        .state = .{
            .authenticator = Authenticator.init(connect_info),
        },
    };

    try client.protocol.connect(connect_info);

    switch (connect_info.tls) {
        .no_tls => try client.authenticate(),
        .tls => {
            try client.transition(.{ .authenticator = .send_tls_request });
            try client.transition(.{ .authenticator = .read_supports_tls_byte });
            try client.transition(.{ .authenticator = .tls_handshake });
            try client.authenticate();
        },
    }

    return client;
}

fn authenticate(self: *Client) !void {
    try self.transition(.{ .authenticator = .send_startup_message });
    try self.transition(.{ .authenticator = .read_authentication });

    switch (self.state) {
        .authenticator => |authenticator| {
            switch (authenticator.state) {
                .received_sasl => {
                    try self.transition(.{ .authenticator = .send_sasl_initial_response });
                    try self.transition(.{ .authenticator = .read_sasl_continue });
                    try self.transition(.{ .authenticator = .send_sasl_response });
                    try self.transition(.{ .authenticator = .read_sasl_final });
                    try self.transition(.{ .authenticator = .read_authentication_ok });
                    try self.transition(.{ .authenticator = .read_param_statuses_until_ready });
                },
                .received_clear_text_password => {
                    try self.transition(.{ .authenticator = .send_password_message });
                    try self.transition(.{ .authenticator = .read_authentication_ok });
                    try self.transition(.{ .authenticator = .read_param_statuses_until_ready });
                },
                .received_md5_password => {
                    try self.transition(.{ .authenticator = .send_password_message });
                    try self.transition(.{ .authenticator = .read_authentication_ok });
                    try self.transition(.{ .authenticator = .read_param_statuses_until_ready });
                },
                // TODO: Add support for other authentication paths
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn close(self: *Client) void {
    self.protocol.close();
    self.state = .{ .closed = undefined };
}

pub fn query(self: *Client, statement: []const u8) !*DataReader {
    assert(self.state == .ready);

    self.state = .{
        .querying = Query.init(
            self.data_reader_state_machine(),
            self.copy_in_state_machine(),
            self.copy_out_state_machine(),
        ),
    };

    try self.transition(.{ .querying = .{ .send_query = statement } });
    try self.transition(.{ .querying = .{ .read_row_description = undefined } });
    try self.transition(.{ .querying = .{ .read_data_reader = undefined } });

    switch (self.state) {
        .data_reader => |*dr| return dr,
        else => unreachable,
    }
}

pub fn prepare(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !*DataReader {
    assert(self.state == .ready);

    self.state = .{
        .querying = Query.init(
            self.dataReaderStateMachine(),
            self.copyInStateMachine(),
            self.copyOutStateMachine(),
        ),
    };

    try self.transition(.{ .querying = .{ .send_parse = statement } });
    try self.transition(.{ .querying = .send_describe });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_parse_complete });
    try self.transition(.{ .querying = .read_parameter_description });
    try self.transition(.{ .querying = .read_row_description });
    try self.transition(.{ .querying = .read_ready_for_query });
    try self.transition(.{ .querying = .{ .send_bind = parameters } });
    try self.transition(.{ .querying = .send_execute });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_bind_complete });
    try self.transition(.{ .querying = .read_data_reader });

    switch (self.state) {
        .data_reader => |data_reader| return data_reader,
        else => unreachable,
    }
}

pub fn copyIn(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !*CopyIn {
    assert(self.state == .ready);

    self.state = .{
        .querying = Query.init(
            self.dataReaderStateMachine(),
            self.copyInStateMachine(),
            self.copyOutStateMachine(),
        ),
    };

    try self.transition(.{ .querying = .{ .send_parse = statement } });
    try self.transition(.{ .querying = .send_describe });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_parse_complete });
    try self.transition(.{ .querying = .read_parameter_description });
    try self.transition(.{ .querying = .read_row_description });
    try self.transition(.{ .querying = .read_ready_for_query });
    try self.transition(.{ .querying = .{ .send_bind = parameters } });
    try self.transition(.{ .querying = .send_execute });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_bind_complete });
    try self.transition(.{ .querying = .read_copy_in });

    switch (self.state) {
        .copy_in => |cp_in| return cp_in,
        else => unreachable,
    }
}

pub fn copyOut(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !*CopyOut {
    assert(self.state == .ready);

    self.state = .{
        .querying = Query.init(
            self.dataReaderStateMachine(),
            self.copyInStateMachine(),
            self.copyOutStateMachine(),
        ),
    };

    try self.transition(.{ .querying = .{ .send_parse = statement } });
    try self.transition(.{ .querying = .send_describe });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_parse_complete });
    try self.transition(.{ .querying = .read_parameter_description });
    try self.transition(.{ .querying = .read_row_description });
    try self.transition(.{ .querying = .read_ready_for_query });
    try self.transition(.{ .querying = .{ .send_bind = parameters } });
    try self.transition(.{ .querying = .send_execute });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_bind_complete });
    try self.transition(.{ .querying = .read_copy_out });

    switch (self.state) {
        .copy_out => |cp_out| return cp_out,
        else => unreachable,
    }
}

pub fn execute(self: *Client, statement: []const u8, parameters: []?[]const u8) !void {
    var data_reader = try self.prepare(statement, parameters);
    defer data_reader.deinit();

    try data_reader.drain();
}

fn transition(self: *Client, event: Event) !void {
    switch (event) {
        .authenticator => |auth_event| {
            switch (self.state) {
                .authenticator => |*authenticator| {
                    try authenticator.transition(
                        &self.protocol,
                        auth_event,
                    );

                    switch (authenticator.state) {
                        .authenticated => {
                            self.state = (.{ .ready = undefined });
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .querying => |query_event| {
            switch (self.state) {
                .querying => |*querier| {
                    try querier.transition(
                        &self.protocol,
                        query_event,
                    );

                    switch (querier.state) {
                        .data_reader => |dr| {
                            self.state = .{ .data_reader = dr };
                        },
                        .copy_in => |ci| {
                            self.state = .{ .copy_in = ci };
                        },
                        .copy_out => |co| {
                            self.state = .{ .copy_out = co };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .data_reading => |data_reader_event| {
            switch (self.state) {
                .data_reader => |dr| {
                    try dr.transition(
                        &self.protocol,
                        data_reader_event,
                    );

                    switch (dr.state) {
                        .complete => {
                            self.state = .{ .ready = undefined };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .copying_in => |copy_in_event| {
            switch (self.state) {
                .copy_in => |cp| {
                    try cp.transition(&self.protocol, copy_in_event);

                    switch (cp.state) {
                        .complete => {
                            self.state = .{ .ready = undefined };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .copying_out => |copy_out_event| {
            switch (self.state) {
                .copy_out => |cp| {
                    try cp.transition(&self.protocol, copy_out_event);

                    switch (cp.state) {
                        .complete => {
                            self.state = .{ .ready = undefined };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
    }
}

fn dataReaderStateMachine(self: *Client) StateMachine(DataReader.Event) {
    return StateMachine(DataReader.Event){
        .context = @ptrCast(self),
        .fn_transition = &dataReaderStateMachineFn,
    };
}

fn copyInStateMachine(self: *Client) StateMachine(CopyIn.Event) {
    return StateMachine(CopyIn.Event){
        .context = @ptrCast(self),
        .fn_transition = &copyInStateMachineFn,
    };
}

fn copyOutStateMachine(self: *Client) StateMachine(CopyOut.Event) {
    return StateMachine(CopyOut.Event){
        .context = @ptrCast(self),
        .fn_transition = &copyOutStateMachineFn,
    };
}

fn dataReaderStateMachineFn(ptr: *anyopaque, event: DataReader.Event) anyerror!void {
    var client: *Client = @alignCast(@ptrCast(ptr));
    try client.transition(.{ .data_reading = event });
}

fn copyInStateMachineFn(ptr: *anyopaque, event: CopyIn.Event) anyerror!void {
    var client: *Client = @alignCast(@ptrCast(ptr));
    try client.transition(.{ .copying_in = event });
}

fn copyOutStateMachineFn(ptr: *anyopaque, event: CopyOut.Event) anyerror!void {
    var client: *Client = @alignCast(@ptrCast(ptr));
    try client.transition(.{ .copying_out = event });
}
