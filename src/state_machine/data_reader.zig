const std = @import("std");
const Protocol = @import("../protocol.zig");
const StateMachine = @import("../state_machine.zig").StateMachine;
const Backend = Protocol.Backend;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const DataReader = @This();

index: usize,
allocator: Allocator,
state: State,
row_description: ?Backend.RowDescription,
state_machine: StateMachine(Event),

pub const State = union(enum) {
    idle: void,
    data_row: Backend.DataRow,
    complete: Backend.CommandComplete,
};

pub const Event = enum {
    next,
};

pub fn init(
    allocator: Allocator,
    row_description: ?Backend.RowDescription,
    state_machine: StateMachine(Event),
) !*DataReader {
    var data_reader = try allocator.create(DataReader);

    data_reader.index = 0;
    data_reader.state = .{ .idle = undefined };
    data_reader.row_description = row_description;
    data_reader.state_machine = state_machine;
    data_reader.allocator = allocator;

    return data_reader;
}

pub fn deinit(self: *DataReader) void {
    if (self.row_description) |rd| {
        rd.deinit();
    }

    self.allocator.destroy(self);
}

pub fn transition(self: *DataReader, protocol: *Protocol, event: Event) !void {
    switch (event) {
        .next => {
            switch (self.state) {
                .idle => {
                    const message = try protocol.read();

                    switch (message) {
                        .data_row => |data_row| {
                            self.state = .{ .data_row = data_row };
                        },
                        .command_complete => |command_complete| {
                            const end_message = try protocol.read();

                            switch (end_message) {
                                .ready_for_query => {
                                    self.state = .{ .complete = command_complete };
                                },
                                else => unreachable,
                            }
                        },
                        else => unreachable,
                    }
                },
                .data_row => |_| {
                    const message = try protocol.read();

                    switch (message) {
                        .data_row => |data_row| {
                            self.state = .{ .data_row = data_row };
                            self.index += 1;
                        },
                        .command_complete => |command_complete| {
                            const end_message = try protocol.read();

                            switch (end_message) {
                                .ready_for_query => {
                                    self.state = .{ .complete = command_complete };
                                },
                                else => unreachable,
                            }
                        },
                        else => unreachable,
                    }
                },
                .complete => unreachable,
            }
        },
    }
}

pub fn next(self: *DataReader) !?*Backend.DataRow {
    try self.state_machine.transition(.next);

    switch (self.state) {
        .data_row => |*dr| return dr,
        .complete => return null,
        .idle => unreachable,
    }
}

pub fn drain(self: *DataReader) !void {
    while (try self.next()) |dr| dr.deinit();
}
