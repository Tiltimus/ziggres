const std = @import("std");
const Datetime = @import("datetime.zig");
const AnyWriter = std.io.AnyWriter;

const Diagnostics = @This();

pub fn init() Diagnostics {
    return Diagnostics{};
}

pub fn log(_: Diagnostics, args: anytype) !void {
    const stdout = std.io.getStdOut();
    const writer = stdout.writer().any();
    const datetime = Datetime.now();

    return try writer.print("[{}]{s}\n", .{datetime} ++ args);
}
