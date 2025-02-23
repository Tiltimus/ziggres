const std = @import("std");
const Protocol = @import("../protocol.zig");
const StateMachine = @import("../state_machine.zig").StateMachine;
const Frontend = Protocol.Frontend;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

allocator: Allocator,
state: State,
state_machine: StateMachine(Event),

pub const CopyIn = @This();

pub const State = enum {
    idle,
    writing,
    flushed,
    complete,
};

pub const Event = union(enum) {
    write: []const u8,
    done: void,
};

pub fn init(allocator: Allocator, state_machine: StateMachine(Event)) !*CopyIn {
    var copy_in = try allocator.create(CopyIn);

    copy_in.allocator = allocator;
    copy_in.state_machine = state_machine;

    return copy_in;
}

pub fn deinit(self: *CopyIn) void {
    self.allocator.destroy(self);
}

pub fn transition(self: *CopyIn, protocol: *Protocol, event: Event) !void {
    switch (event) {
        .write => |bytes| {
            const copy_data = Frontend.CopyData{
                .data = bytes,
            };

            try protocol.write(.{ .copy_data = copy_data });

            self.state = .writing;
        },
        .done => {
            const copy_done = Frontend.CopyDone{};
            const sync = Frontend.Sync{};

            try protocol.write(.{ .copy_done = copy_done });
            try protocol.write(.{ .sync = sync });

            const message = try protocol.read();

            switch (message) {
                .command_complete => {
                    const next_message = try protocol.read();

                    switch (next_message) {
                        .ready_for_query => {
                            self.state = .complete;
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
    }
}

pub fn write(self: *CopyIn, bytes: []const u8) !void {
    try self.state_machine.transition(.{ .write = bytes });
}

pub fn done(self: *CopyIn) !void {
    try self.state_machine.transition(.{ .done = undefined });
}
