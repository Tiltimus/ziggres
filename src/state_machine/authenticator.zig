const std = @import("std");
const Protocol = @import("../protocol.zig");
const Frontend = Protocol.Frontend;
const Backend = Protocol.Backend;
const ConnectInfo = Protocol.ConnectInfo;
const Tuple = std.meta.Tuple;
const Certificate = std.crypto.Certificate;
const Client = std.crypto.tls.Client;
const assert = std.debug.assert;

state: State,
connect_info: ConnectInfo,

const Authenticator = @This();

pub const Event = enum {
    send_tls_request,
    send_startup_message,
    send_sasl_initial_response,
    send_sasl_response,
    send_password_message,
    read_supports_tls_byte,
    read_authentication,
    read_sasl_continue,
    read_sasl_final,
    read_authentication_ok,
    read_param_statuses_until_ready,
    tls_handshake,
};

pub const State = union(enum) {
    startup: void,
    received_supports_tls_bytes: Protocol.SupportsTls,
    received_authentication: Backend.Authentication,
    received_kerberosV5: void,
    received_clear_text_password: void,
    received_md5_password: Backend.Authentication.MD5Password,
    received_gss: void,
    received_sspi: void,
    received_sasl: Backend.Authentication.SASL,
    received_sasl_continue: Tuple(&[_]type{ Frontend.SASLInitialResponse, Backend.Authentication.SASLContinue }),
    received_sasl_final: void,
    received_ok: void,
    received_parameter_statuses: void,
    sent_ssl_request: void,
    sent_sasl_response: Frontend.SASLResponse,
    sent_sasl_initial_response: Frontend.SASLInitialResponse,
    sent_password_message: void,
    tls_handshake_complete: void,
    authenticated: void,
    error_response: Backend.ErrorResponse,
};

pub fn init(connect_info: ConnectInfo) Authenticator {
    return Authenticator{
        .state = .{ .startup = undefined },
        .connect_info = connect_info,
    };
}

pub fn transition(
    self: *Authenticator,
    protocol: *Protocol,
    event: Event,
) !void {
    switch (event) {
        .send_tls_request => {
            try protocol.write(.{ .ssl_request = undefined });

            self.state = .{ .sent_ssl_request = undefined };
        },
        .send_startup_message => {
            var startup_message = try Frontend.StartupMessage.init_connect_info(
                protocol.allocator,
                self.connect_info,
            );
            defer startup_message.deinit();

            try startup_message.set_user(self.connect_info.username);
            try startup_message.set_database(self.connect_info.database);
            try startup_message.set_application_name(self.connect_info.application_name);

            try protocol.write(.{ .startup_message = startup_message });

            self.state = .{ .received_authentication = undefined };
        },
        .send_sasl_initial_response => {
            switch (self.state) {
                .received_sasl => |sasl| {
                    const mechanism = sasl.get_first_mechanism();

                    const gs2_flag: Frontend.GS2Flag = switch (mechanism) {
                        .scram_sha_256 => .{ .n = undefined },
                        .scram_sha_256_plus => .{ .p = protocol.tls_client.?.application_cipher },
                    };

                    const sasl_initial_response = try Frontend.SASLInitialResponse.init(
                        protocol.allocator,
                        mechanism,
                        gs2_flag,
                    );
                    defer sasl.deinit();

                    try protocol.write(.{ .sasl_initial_response = sasl_initial_response });

                    self.state = .{ .sent_sasl_initial_response = sasl_initial_response };
                },
                else => unreachable,
            }
        },
        .send_sasl_response => {
            switch (self.state) {
                .received_sasl_continue => |tuple| {
                    const sasl_response = Frontend.SASLResponse{
                        .client_first_message = tuple[0],
                        .server_first_message = tuple[1],
                        .password = self.connect_info.password,
                    };
                    defer {
                        tuple[0].deinit();
                        tuple[1].deinit();
                    }

                    try protocol.write(.{ .sasl_response = sasl_response });

                    self.state = .{ .sent_sasl_response = sasl_response };
                },
                else => unreachable,
            }
        },
        .send_password_message => {
            switch (self.state) {
                .received_clear_text_password => {
                    const password_message = Frontend.PasswordMessage{
                        .password = self.connect_info.password,
                    };

                    try protocol.write(.{ .password_message = password_message });

                    self.state = .{ .sent_password_message = undefined };
                },
                .received_md5_password => |md5_password| {
                    var password_message = Frontend.PasswordMessage{
                        .password = self.connect_info.password,
                    };

                    password_message.hash_md5(&md5_password.salt);

                    try protocol.write(.{ .password_message = password_message });

                    self.state = .{ .sent_password_message = undefined };
                },
                else => unreachable,
            }
        },
        .read_supports_tls_byte => {
            const supports = try protocol.read_supports_tls_byte();

            self.state = .{ .received_supports_tls_bytes = supports };
        },
        .read_authentication => {
            const message = try protocol.read();

            switch (message) {
                .authentication => |authentication| {
                    switch (authentication) {
                        .sasl => |sasl| {
                            self.state = .{ .received_sasl = sasl };
                        },
                        .clear_text_password => {
                            self.state = .{ .received_clear_text_password = undefined };
                        },
                        .md5_password => |md5_password| {
                            self.state = .{ .received_md5_password = md5_password };
                        },
                        else => unreachable,
                    }
                },
                .error_response => |er| self.state = .{ .error_response = er },
                else => unreachable,
            }
        },
        .read_sasl_continue => {
            switch (self.state) {
                .sent_sasl_initial_response => |sasl_initial_response| {
                    const message = protocol.read() catch |err| {
                        sasl_initial_response.deinit();
                        return err;
                    };

                    switch (message) {
                        .authentication => |auth| {
                            switch (auth) {
                                .sasl_continue => |sasl_continue| {
                                    self.state = .{
                                        .received_sasl_continue = .{ sasl_initial_response, sasl_continue },
                                    };
                                },
                                else => unreachable,
                            }
                        },
                        .error_response => |er| {
                            self.state = .{ .error_response = er };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .read_sasl_final => {
            const message = try protocol.read();

            switch (message) {
                .authentication => |auth| {
                    switch (auth) {
                        .sasl_final => |sasl_final| {
                            sasl_final.deinit();

                            self.state = .{ .received_sasl_final = undefined };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .read_authentication_ok => {
            const message = try protocol.read();

            switch (message) {
                .authentication => |auth| {
                    switch (auth) {
                        .ok => {
                            self.state = .{ .received_ok = undefined };
                        },
                        else => unreachable,
                    }
                },
                else => unreachable,
            }
        },
        .read_param_statuses_until_ready => {
            var message: Backend = undefined;

            while (true) {
                message = try protocol.read();

                switch (message) {
                    .parameter_status => |ps| {
                        ps.deinit();
                    },
                    .ready_for_query => {
                        self.state = .{ .authenticated = undefined };
                        return;
                    },
                    .backend_key_data => {},
                    else => unreachable,
                }
            }
        },
        .tls_handshake => {
            switch (self.connect_info.tls) {
                .tls => |file| {
                    var ca_bundle: Certificate.Bundle = Certificate.Bundle{};
                    defer ca_bundle.deinit(protocol.allocator);

                    try ca_bundle.addCertsFromFile(protocol.allocator, file);

                    const tls_client = try Client.init(
                        protocol.stream,
                        .{
                            .host = .{ .explicit = self.connect_info.host },
                            .ca = .{ .bundle = ca_bundle },
                        },
                    );

                    protocol.tls_client = tls_client;

                    self.state = .{ .tls_handshake_complete = undefined };
                },
                .no_tls => unreachable,
            }
        },
    }
}
