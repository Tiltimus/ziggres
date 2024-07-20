const std = @import("std");
const Message = @import("./message.zig");
const ConnectInfo = @import("./connect_info.zig");
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const SASLInitialResponse = Message.SASLInitialResponse;

const Authenticator = @This();

state: State,
connect_info: ConnectInfo,

pub fn init(connect_info: ConnectInfo) Authenticator {
    return Authenticator{
        .state = .{ .startup = undefined },
        .connect_info = connect_info,
    };
}

pub fn transition(self: *Authenticator, reader: AnyReader, writer: AnyWriter) !void {
    switch (self.state) {
        .startup => {
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

        .received_authentication => {
            const message = try Message.read(reader);

            switch (message) {
                .authentication_sasl => |authentication_sasl| {
                    self.state = .{ .received_sasl = authentication_sasl };
                },
                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => @panic("Unexpected message."),
            }
        },

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
        .sent_sasl_initial_response => |sasl_initial_response| {
            const message = try Message.read(reader);

            switch (message) {
                .authentication_sasl_continue => |sasl_continue| {
                    var new_sasl_continue = sasl_continue;

                    new_sasl_continue.client_message = sasl_initial_response.client_message;

                    self.state = .{ .received_sasl_continue = new_sasl_continue };
                },
                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => @panic("Unexpected message."),
            }
        },
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
        .sent_sasl_response => |_| {
            const message = try Message.read(reader);

            switch (message) {
                .authentication_sasl_final => |final| {
                    self.state = .{ .received_sasl_final = final };
                },
                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => @panic("Unexpected message."),
            }
        },
        .received_sasl_final => |_| {
            const message = try Message.read(reader);

            switch (message) {
                .authentication_ok => |ok| {
                    self.state = .{ .received_ok = ok };
                },
                .error_response => |error_response| {
                    self.state = .{ .error_response = error_response };
                },
                else => @panic("Unexpected message."),
            }
        },
        .received_ok => |_| {
            // TODO: After the auth ok a bunch of meta data gets sent atm I don't care about it but needs to be added in ?
            var buffer: [1024]u8 = undefined;

            _ = try reader.readAtLeast(&buffer, 1);

            self.state = .{ .authenticated = undefined };
        },

        else => @panic("Not yet implemented."),
    }
}

// TODO: Look into encoding style DDD ?
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

    pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
        const tag_name = @tagName(self);
        try writer.print("{s}", .{tag_name});
    }
};
