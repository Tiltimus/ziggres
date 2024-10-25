const std = @import("std");
const Message = @import("message.zig");
const ConnectInfo = @import("connect_info.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const SASLInitialResponse = Message.SASLInitialResponse;
const expect = std.testing.expect;

state: State,
connect_info: ConnectInfo,

const Authenticator = @This();

pub const Event = enum {
    send_startup_message,
    send_sasl_initial_response,
    send_sasl_response,
    read_authentication,
    read_sasl_continue,
    read_sasl_final,
    read_authentication_ok,
};

pub const State = union(enum) {
    startup: void,
    received_authentication: void,
    received_kerberosV5: void,
    received_clear_text_password: void,
    received_md5_password: void,
    received_gss: void,
    received_sspi: void,
    received_sasl: Message.AuthenticationSASL,
    received_sasl_continue: Message.AuthenticationSASLContinue,
    received_sasl_final: Message.AuthenticationSASLFinal,
    received_ok: Message.AuthenticationOk,
    sent_sasl_response: Message.SASLResponse,
    sent_sasl_initial_response: Message.SASLInitialResponse,
    authenticated: void,
    error_response: Message.ErrorResponse,
};

pub fn init(connect_info: ConnectInfo) Authenticator {
    return Authenticator{
        .state = .{ .startup = undefined },
        .connect_info = connect_info,
    };
}

pub fn transition(
    self: *Authenticator,
    arena_allocator: *ArenaAllocator,
    event: Event,
    reader: AnyReader,
    writer: AnyWriter,
) !void {
    switch (event) {
        .send_startup_message => {
            const startup_message = Message.StartupMessage{
                .user = self.connect_info.username,
                .database = self.connect_info.database,
                .application_name = self.connect_info.application_name,
            };

            try Message.write(
                .{ .startup_message = startup_message },
                writer,
            );

            self.state = .{ .received_authentication = undefined };
        },
        .read_authentication => {
            const message = try Message.read(reader, arena_allocator);

            switch (message) {
                .authentication_sasl => |authentication_sasl| {
                    self.state = .{ .received_sasl = authentication_sasl };
                },
                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => unreachable,
            }
        },
        .send_sasl_initial_response => {
            switch (self.state) {
                .received_sasl => |authentication_sasl| {
                    const sasl_initial_response = try SASLInitialResponse.init(
                        authentication_sasl.mechanism,
                    );

                    try Message.write(
                        .{ .sasl_initial_response = sasl_initial_response },
                        writer,
                    );

                    self.state = .{ .sent_sasl_initial_response = sasl_initial_response };
                },
                else => unreachable,
            }
        },
        .read_sasl_continue => {
            switch (self.state) {
                .sent_sasl_initial_response => |sasl_initial_response| {
                    const message = try Message.read(reader, arena_allocator);

                    switch (message) {
                        .authentication_sasl_continue => |sasl_continue| {
                            var new_sasl_continue = sasl_continue;

                            new_sasl_continue.client_message = sasl_initial_response.client_message;

                            self.state = .{ .received_sasl_continue = new_sasl_continue };
                        },
                        .error_response => |error_response| {
                            self.state = .{ .error_response = error_response };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .send_sasl_response => {
            switch (self.state) {
                .received_sasl_continue => |sasl_continue| {
                    const sasl_response = Message.SASLResponse{
                        .nonce = sasl_continue.nonce,
                        .salt = sasl_continue.salt,
                        .iteration = sasl_continue.iteration,
                        .response = sasl_continue.response,
                        .password = self.connect_info.password,
                        .client_first_message = sasl_continue.client_message,
                    };

                    try Message.write(
                        .{ .sasl_response = sasl_response },
                        writer,
                    );

                    self.state = .{ .sent_sasl_response = sasl_response };
                },
                else => unreachable,
            }
        },
        .read_sasl_final => {
            switch (self.state) {
                .sent_sasl_response => |_| {
                    const message = try Message.read(reader, arena_allocator);

                    switch (message) {
                        .authentication_sasl_final => |final| {
                            self.state = .{ .received_sasl_final = final };
                        },
                        .error_response => |error_response| {
                            self.state = .{ .error_response = error_response };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .read_authentication_ok => {
            switch (self.state) {
                .received_sasl_final => |_| {
                    const message = try Message.read(reader, arena_allocator);

                    switch (message) {
                        .authentication_ok => |_| {
                            while (try Message.read(reader, arena_allocator) != .ready_for_query) {}

                            self.state = .{ .authenticated = undefined };
                        },
                        .error_response => |error_response| {
                            self.state = .{ .error_response = error_response };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
    }
}

test "simple test" {
    try expect(1 == 1);
}
