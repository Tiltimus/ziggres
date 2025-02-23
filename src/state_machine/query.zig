const std = @import("std");
const DataReader = @import("data_reader.zig");
const CopyIn = @import("copy_in.zig");
const CopyOut = @import("copy_out.zig");
const Protocol = @import("../protocol.zig");
const StateMachine = @import("../state_machine.zig").StateMachine;
const Frontend = Protocol.Frontend;
const Backend = Protocol.Backend;
const assert = std.debug.assert;

const Query = @This();

state: State,
row_description: ?Backend.RowDescription,
data_reader_state_machine: StateMachine(DataReader.Event),
copy_in_state_machine: StateMachine(CopyIn.Event),
copy_out_state_machine: StateMachine(CopyOut.Event),

pub const State = union(enum) {
    ready: void,
    sent_query: void,
    sent_parse: void,
    sent_describe: void,
    sent_sync: void,
    sent_execute: void,
    sent_bind: void,
    received_row_description: Backend.RowDescription,
    received_parse_complete: void,
    received_parameter_description: void,
    received_ready_for_query: void,
    received_bind_complete: void,
    received_no_data: void,
    data_reader: *DataReader,
    copy_in: *CopyIn,
    copy_out: *CopyOut,
};

pub const Event = union(enum) {
    send_query: []const u8,
    send_parse: []const u8,
    send_describe: void,
    send_bind: []?[]const u8,
    send_execute: void,
    send_sync: void,
    read_row_description: void,
    read_parse_complete: void,
    read_parameter_description: void,
    read_ready_for_query: void,
    read_bind_complete: void,
    read_data_reader: void,
    read_copy_in: void,
    read_copy_out: void,
};

pub fn init(
    drsm: StateMachine(DataReader.Event),
    cism: StateMachine(CopyIn.Event),
    cosm: StateMachine(CopyOut.Event),
) Query {
    return Query{
        .state = .{ .ready = undefined },
        .row_description = null,
        .data_reader_state_machine = drsm,
        .copy_in_state_machine = cism,
        .copy_out_state_machine = cosm,
    };
}

pub fn transition(self: *Query, protocol: *Protocol, event: Event) !void {
    switch (event) {
        .send_query => |statement| {
            const message = Frontend.Query{
                .statement = statement,
            };

            try protocol.write(.{ .query = message });

            self.state = .{ .sent_query = undefined };
        },
        .send_parse => |statement| {
            const message = Frontend.Parse{
                .name = "",
                .statement = statement,
            };

            try protocol.write(.{ .parse = message });

            self.state = .{ .sent_parse = undefined };
        },
        .send_describe => {
            const message = Frontend.Describe{
                .name = "",
                .target = .statement,
            };

            try protocol.write(.{ .describe = message });

            self.state = .{ .sent_describe = undefined };
        },
        .send_bind => |bind| {
            const message = Frontend.Bind{
                .format = .text,
                .parameters = bind,
                .portal_name = "",
                .statement_name = "",
            };

            try protocol.write(.{ .bind = message });

            self.state = .{ .sent_bind = undefined };
        },
        .send_execute => {
            const message = Frontend.Execute{
                .portal_name = "",
                .rows = 0,
            };

            try protocol.write(.{ .execute = message });

            self.state = .{ .sent_execute = undefined };
        },
        .send_sync => {
            const message = Frontend.Sync{};

            try protocol.write(.{ .sync = message });

            self.state = .{ .sent_sync = undefined };
        },
        .read_row_description => {
            const message = try protocol.read();

            switch (message) {
                .row_description => |rd| {
                    self.row_description = rd;
                    self.state = .{ .received_row_description = rd };
                },
                .no_data => {
                    self.state = .{ .received_no_data = undefined };
                },
                else => unreachable,
            }
        },
        .read_parse_complete => {
            const message = try protocol.read();

            switch (message) {
                .parse_complete => {
                    self.state = .{ .received_parse_complete = undefined };
                },
                else => unreachable,
            }
        },
        .read_parameter_description => {
            const message = try protocol.read();

            switch (message) {
                .parameter_description => |pd| {
                    pd.deinit();

                    self.state = .{ .received_parameter_description = undefined };
                },
                else => unreachable,
            }
        },
        .read_ready_for_query => {
            const message = try protocol.read();

            switch (message) {
                .ready_for_query => {
                    self.state = .{ .received_ready_for_query = undefined };
                },
                else => unreachable,
            }
        },
        .read_bind_complete => {
            const message = try protocol.read();

            switch (message) {
                .bind_complete => {
                    self.state = .{ .received_bind_complete = undefined };
                },
                else => unreachable,
            }
        },
        .read_data_reader => {
            self.state = .{
                .data_reader = try DataReader.init(
                    protocol.allocator,
                    self.row_description,
                    self.data_reader_state_machine,
                ),
            };
        },
        .read_copy_in => {
            const message = try protocol.read();

            switch (message) {
                .copy_in_response => |cir| {
                    // TODO: May use CIR for different formats later
                    defer cir.deinit();
                    self.state = .{
                        .copy_in = try CopyIn.init(
                            protocol.allocator,
                            self.copy_in_state_machine,
                        ),
                    };
                },
                else => unreachable,
            }
        },
        .read_copy_out => {
            const message = try protocol.read();

            switch (message) {
                .copy_out_response => |cor| {
                    // TODO: May use CIR for different formats later
                    defer cor.deinit();
                    self.state = .{
                        .copy_out = try CopyOut.init(
                            protocol.allocator,
                            self.copy_out_state_machine,
                        ),
                    };
                },
                else => unreachable,
            }
        },
    }
}
