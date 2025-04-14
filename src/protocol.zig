const std = @import("std");
pub const ConnectInfo = @import("protocol/connect_info.zig");
pub const Backend = @import("protocol/backend.zig").Backend;
pub const Frontend = @import("protocol/frontend.zig").Frontend;
pub const Errors = @import("protocol/errors.zig");
const GenericWriter = std.io.GenericWriter;
const GenericReader = std.io.GenericReader;
const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;
const Network = std.net;
const TlsClient = std.crypto.tls.Client;
const Certificate = std.crypto.Certificate;
const Endian = std.mem.Endian;
const memWriteInt = std.mem.writeInt;
const stringToEnum = std.meta.stringToEnum;

const Protocol = @This();

allocator: Allocator,
stream: Stream,
tls_client: ?TlsClient = null,

pub const SupportsTls = enum(u1) {
    S,
    N,
};

pub const ReadError = anyerror;
pub const Reader = GenericReader(*Protocol, ReadError, readFn);

pub const WriteError = anyerror;
pub const Writer = GenericWriter(*Protocol, WriteError, writeFn);

pub fn init(allocator: Allocator) Protocol {
    return Protocol{
        .allocator = allocator,
        .stream = undefined,
    };
}

pub fn connect(
    self: *Protocol,
    connect_info: ConnectInfo,
) !void {
    const stream = try Network.tcpConnectToHost(
        self.allocator,
        connect_info.host,
        connect_info.port,
    );
    errdefer stream.close();

    self.stream = stream;
}

pub fn read(self: *Protocol) !Backend {
    const backend = try Backend.read(self.allocator, self.reader());

    switch (backend) {
        .error_response => |er| {
            var iter = er.iterator();
            defer er.deinit();

            while (try iter.next()) |entry| {
                if (entry[0] == 'C') {
                    return Errors.code_to_error(entry[1]);
                }
            }

            @panic("Unable to get SQLSTATE code from error response");
        },
        .notice_response => |nr| {
            defer nr.deinit();

            // TODO: Add option to log and pretty print
            // std.log.warn("Notice Response: {s}", .{nr.buffer});

            return self.read();
        },
        else => return backend,
    }
}

pub fn read_supports_tls_byte(self: *Protocol) !SupportsTls {
    var scribe = self.reader();
    const byte: u8 = try scribe.readByte();

    if (stringToEnum(SupportsTls, &[1]u8{byte})) |supports|
        return supports;

    @panic("Expected supports tls byte to be either S or N");
}

pub fn write(self: *Protocol, frontend: Frontend) !void {
    return Frontend.write(
        frontend,
        self.allocator,
        self.writer(),
    );
}

pub fn close(self: Protocol) void {
    self.stream.close();
}

pub fn reader(self: *Protocol) Reader {
    return Reader{
        .context = self,
    };
}

pub fn writer(self: *Protocol) Writer {
    return Writer{
        .context = self,
    };
}

pub fn readFn(self: *Protocol, buffer: []u8) !usize {
    if (self.tls_client) |*tls_client| {
        return tls_client.read(self.stream, buffer);
    }

    return try self.stream.read(buffer);
}

pub fn writeFn(self: *Protocol, bytes: []const u8) !usize {
    if (self.tls_client) |*tls_client| {
        return tls_client.write(self.stream, bytes);
    }

    return try self.stream.write(bytes);
}
