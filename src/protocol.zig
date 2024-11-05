const std = @import("std");
const Message = @import("./message.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Address = std.net.Address;
const Stream = std.net.Stream;

context: *const anyopaque,
read_fn: *const fn (context: *const anyopaque, buffer: []u8) anyerror!usize,
write_fn: *const fn (context: *const anyopaque, bytes: []const u8) anyerror!usize,
connect_fn: *const fn (address: Address) anyerror!Protocol,
close_fn: *const fn (context: *const anyopaque) anyerror!void,

const Protocol = @This();

pub fn connect(self: Protocol, address: Address) !Protocol {
    const protocol = try self.connect_fn(address);

    return protocol;
}

pub fn close(self: Protocol) !void {
    try self.close_fn(self.context);
}

pub fn read_message(self: Protocol, arena_allocator: *ArenaAllocator) !Message {
    const reader = self.any_reader();

    return try Message.read(reader, arena_allocator);
}

pub fn write_message(self: Protocol, message: Message) !void {
    const writer = self.any_writer();

    return try Message.write(message, writer);
}

pub fn any_reader(self: Protocol) AnyReader {
    return AnyReader{
        .context = @alignCast(@ptrCast(self)),
        .readFn = &read,
    };
}

pub fn any_writer(self: Protocol) AnyWriter {
    return AnyWriter{
        .context = @alignCast(@ptrCast(self)),
        .writeFn = &write,
    };
}

pub fn read(self: Protocol, buffer: []u8) !usize {
    return try self.read_fn(self.context, buffer);
}

pub fn write(self: Protocol, bytes: []const u8) !usize {
    return try self.write_fn(self.context, bytes);
}

pub fn net_stream() Protocol {
    return Protocol{
        .context = undefined,
        .connect_fn = &connect_net_stream,
        .read_fn = undefined,
        .close_fn = undefined,
        .write_fn = undefined,
    };
}

fn connect_net_stream(address: Address) !Protocol {
    const stream = try std.net.tcpConnectToAddress(address);
    errdefer stream.close();

    return Protocol{
        .context = @alignCast(@ptrCast(&stream)),
        .connect_fn = &connect_net_stream,
        .read_fn = &read_net_stream,
        .close_fn = &close_net_stream,
        .write_fn = &write_net_stream,
    };
}

fn read_net_stream(context: *const anyopaque, buffer: []u8) anyerror!usize {
    const stream: *const Stream = @ptrCast(@alignCast(context));
    return try stream.stream.read(buffer);
}

fn write_net_stream(context: *const anyopaque, bytes: []const u8) anyerror!usize {
    const stream: *const Stream = @ptrCast(@alignCast(context));
    return try stream.stream.write(bytes);
}

fn close_net_stream(context: *const anyopaque) anyerror!void {
    const stream: *const Stream = @ptrCast(@alignCast(context));
    stream.close();
}
