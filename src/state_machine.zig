const std = @import("std");

pub fn StateMachine(comptime Event: type) type {
    return struct {
        context: *anyopaque,
        fn_transition: *const fn (context: *anyopaque, event: Event) anyerror!void,

        const Self = @This();

        pub fn init(context: *anyopaque, func: *const fn (context: *anyopaque, event: Event) anyerror!void) Self {
            return Self{
                .context = context,
                .fn_transition = func,
            };
        }

        pub fn transition(self: Self, event: Event) !void {
            try self.fn_transition(self.context, event);
        }
    };
}
