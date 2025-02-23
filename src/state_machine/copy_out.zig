const std = @import("std");
const Protocol = @import("../protocol.zig");
const StateMachine = @import("../state_machine.zig").StateMachine;
const Frontend = Protocol.Frontend;
const Backend = Protocol.Backend;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

allocator: Allocator,
state: State,
buffer: ArrayList(u8),
state_machine: StateMachine(Event),

pub const CopyOut = @This();

pub const State = union(enum) {
    idle,
    reading: Backend.CopyData,
    complete,
};

pub const Event = enum {
    read,
};

pub fn init(allocator: Allocator, state_machine: StateMachine(Event)) !*CopyOut {
    var copy_out = try allocator.create(CopyOut);

    copy_out.allocator = allocator;
    copy_out.state_machine = state_machine;
    copy_out.buffer = ArrayList(u8).init(allocator);

    return copy_out;
}

pub fn deinit(self: *CopyOut) void {
    self.buffer.deinit();
    self.allocator.destroy(self);
}

pub fn transition(self: *CopyOut, protocol: *Protocol, event: Event) !void {
    switch (event) {
        .read => {
            const message = try protocol.read();

            switch (message) {
                .copy_data => |cd| self.state = .{ .reading = cd },
                .copy_done => {
                    const next_message = try protocol.read();

                    switch (next_message) {
                        .command_complete => {
                            const final_message = try protocol.read();

                            switch (final_message) {
                                .ready_for_query => {
                                    self.state = .complete;
                                },
                                else => unreachable,
                            }
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
    }
}

pub fn read(self: *CopyOut) !?Backend.CopyData {
    try self.state_machine.transition(.read);

    switch (self.state) {
        .reading => |data| return data,
        .complete => return null,
        else => unreachable,
    }
}
