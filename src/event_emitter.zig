const std = @import("std");

pub fn EventEmitter(comptime Event: type) type {
    return struct {
        context: *anyopaque,
        send_event: *const fn (context: *anyopaque, event: Event) anyerror!void,

        const Emitter = @This();

        pub fn init(context: anytype, func: *const fn (context: *anyopaque, event: Event) anyerror!void) Emitter {
            return Emitter{
                .context = @ptrCast(context),
                .send_event = func,
            };
        }

        pub fn emit(self: Emitter, event: Event) !void {
            try self.send_event(self.context, event);
        }
    };
}
