const std = @import("std");
const Message = @import("./message.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Address = std.net.Address;
const Stream = std.net.Stream;
const Allocator = std.mem.Allocator;

context: *anyopaque,
read_fn: *const fn (context: *anyopaque, buffer: []u8) anyerror!usize,
write_fn: *const fn (context: *anyopaque, bytes: []const u8) anyerror!usize,
connect_fn: *const fn (allocator: Allocator, name: []const u8, port: u16) anyerror!Protocol,
close_fn: *const fn (context: *anyopaque) void,

const Protocol = @This();

pub fn connect(self: Protocol, allocator: Allocator, name: []const u8, port: u16) !Protocol {
    const protocol = try self.connect_fn(allocator, name, port);

    return protocol;
}

pub fn close(self: Protocol) void {
    self.close_fn(self.context);
}

pub fn read_message(self: Protocol, arena_allocator: *ArenaAllocator) !Message {
    const reader = self.any_reader();

    return try Message.read(reader, arena_allocator);
}

pub fn write_message(self: Protocol, message: Message) !void {
    const writer = self.any_writer();

    return try Message.write(message, writer);
}

pub fn any_reader(self: *Protocol) AnyReader {
    return AnyReader{
        .context = @ptrCast(self),
        .readFn = &protocol_read,
    };
}

pub fn any_writer(self: *Protocol) AnyWriter {
    return AnyWriter{
        .context = @ptrCast(self),
        .writeFn = &protocol_write,
    };
}

fn protocol_read(context: *anyopaque, buffer: []u8) !usize {
    const protocol: *Protocol = @ptrCast(@alignCast(context));
    return try protocol.read_fn(protocol.context, buffer);
}

fn protocol_write(context: *anyopaque, bytes: []const u8) !usize {
    const protocol: *Protocol = @ptrCast(@alignCast(context));

    return try protocol.write_fn(protocol.context, bytes);
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
        .read_fn = &read_net_stream,
        .close_fn = &close_net_stream,
        .write_fn = &write_net_stream,
    };
}

pub fn connect_net_stream(allocator: Allocator, name: []const u8, port: u16) !Protocol {
    var stream = try std.net.tcpConnectToHost(allocator, name, port);
    errdefer stream.close();
    std.log.debug("CONNECT: {any}", .{stream});

    return Protocol{
        .context = @ptrCast(&stream),
        .connect_fn = &connect_net_stream,
        .read_fn = &read_net_stream,
        .close_fn = &close_net_stream,
        .write_fn = &write_net_stream,
    };
}

fn read_net_stream(context: *anyopaque, buffer: []u8) anyerror!usize {
    const stream: *Stream = @ptrCast(@alignCast(context));
    return try stream.read(buffer);
}

fn write_net_stream(context: *anyopaque, bytes: []const u8) anyerror!usize {
    const stream: *Stream = @ptrCast(@alignCast(context));
    std.log.debug("{any}", .{stream});
    return stream.write(bytes);
}

fn close_net_stream(context: *anyopaque) void {
    const stream: *Stream = @ptrCast(@alignCast(context));
    stream.close();
}
