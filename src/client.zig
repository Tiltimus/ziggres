const std = @import("std");
pub const Protocol = @import("protocol.zig");
pub const ConnectInfo = @import("protocol/connect_info.zig");
const Backend = @import("protocol/backend.zig").Backend;
const Frontend = @import("protocol/frontend.zig").Frontend;
const Allocator = std.mem.Allocator;
const Tuple = std.meta.Tuple;
const Certificate = std.crypto.Certificate;
const TlsClient = std.crypto.tls.Client;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Client = @This();

state: State,
protocol: Protocol,
connect_info: ConnectInfo,

pub const State = union(enum) {
    init: void,
    authenticator: Authenticator,
    querying: Query,
    data_reader: *DataReader,
    copy_in: *CopyIn,
    copy_out: *CopyOut,
    ready: void,
    closed: void,
    error_response: Backend.ErrorResponse,
};

pub const Event = union(enum) {
    authenticator: Authenticator.Event,
    querying: Query.Event,
    data_reading: DataReader.Event,
    copying_in: CopyIn.Event,
    copying_out: CopyOut.Event,
};

pub fn connect(allocator: Allocator, connect_info: ConnectInfo) !Client {
    const protocol = Protocol.init(allocator);

    var client = Client{
        .protocol = protocol,
        .connect_info = connect_info,
        .state = .init,
    };

    client.state = .{ .authenticator = Authenticator.init(&client) };

    try client.protocol.connect(connect_info);

    switch (connect_info.tls) {
        .no_tls => try client.authenticate(),
        .tls => {
            try client.transition(.{ .authenticator = .send_tls_request });
            try client.transition(.{ .authenticator = .read_supports_tls_byte });
            try client.transition(.{ .authenticator = .tls_handshake });
            try client.authenticate();
        },
    }

    return client;
}

fn authenticate(self: *Client) !void {
    try self.transition(.{ .authenticator = .send_startup_message });
    try self.transition(.{ .authenticator = .read_authentication });

    switch (self.state) {
        .authenticator => |authenticator| {
            switch (authenticator.state) {
                .received_sasl => {
                    try self.transition(.{ .authenticator = .send_sasl_initial_response });
                    try self.transition(.{ .authenticator = .read_sasl_continue });
                    try self.transition(.{ .authenticator = .send_sasl_response });
                    try self.transition(.{ .authenticator = .read_sasl_final });
                    try self.transition(.{ .authenticator = .read_authentication_ok });
                    try self.transition(.{ .authenticator = .read_param_statuses_until_ready });
                },
                .received_clear_text_password => {
                    try self.transition(.{ .authenticator = .send_password_message });
                    try self.transition(.{ .authenticator = .read_authentication_ok });
                    try self.transition(.{ .authenticator = .read_param_statuses_until_ready });
                },
                .received_md5_password => {
                    try self.transition(.{ .authenticator = .send_password_message });
                    try self.transition(.{ .authenticator = .read_authentication_ok });
                    try self.transition(.{ .authenticator = .read_param_statuses_until_ready });
                },
                // TODO: Add support for other authentication paths
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn close(self: *Client) void {
    self.protocol.close();
    self.state = .{ .closed = undefined };
}

pub fn query(self: *Client, statement: []const u8) !*DataReader {
    assert(self.state == .ready);

    self.state = .{ .querying = Query.init(self) };

    try self.transition(.{ .querying = .{ .send_query = statement } });
    try self.transition(.{ .querying = .{ .read_row_description = undefined } });
    try self.transition(.{ .querying = .{ .read_data_reader = undefined } });

    switch (self.state) {
        .data_reader => |*dr| return dr,
        else => unreachable,
    }
}

pub fn prepare(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !*DataReader {
    assert(self.state == .ready);

    self.state = .{ .querying = Query.init(self) };

    try self.transition(.{ .querying = .{ .send_parse = statement } });
    try self.transition(.{ .querying = .send_describe });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_parse_complete });
    try self.transition(.{ .querying = .read_parameter_description });
    try self.transition(.{ .querying = .read_row_description });
    try self.transition(.{ .querying = .read_ready_for_query });
    try self.transition(.{ .querying = .{ .send_bind = parameters } });
    try self.transition(.{ .querying = .send_execute });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_bind_complete });
    try self.transition(.{ .querying = .read_data_reader });

    switch (self.state) {
        .data_reader => |data_reader| return data_reader,
        else => unreachable,
    }
}

pub fn copyIn(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !*CopyIn {
    assert(self.state == .ready);

    self.state = .{ .querying = Query.init(self) };

    try self.transition(.{ .querying = .{ .send_parse = statement } });
    try self.transition(.{ .querying = .send_describe });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_parse_complete });
    try self.transition(.{ .querying = .read_parameter_description });
    try self.transition(.{ .querying = .read_row_description });
    try self.transition(.{ .querying = .read_ready_for_query });
    try self.transition(.{ .querying = .{ .send_bind = parameters } });
    try self.transition(.{ .querying = .send_execute });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_bind_complete });
    try self.transition(.{ .querying = .read_copy_in });

    switch (self.state) {
        .copy_in => |cp_in| return cp_in,
        else => unreachable,
    }
}

pub fn copyOut(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !*CopyOut {
    assert(self.state == .ready);

    self.state = .{ .querying = Query.init(self) };

    try self.transition(.{ .querying = .{ .send_parse = statement } });
    try self.transition(.{ .querying = .send_describe });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_parse_complete });
    try self.transition(.{ .querying = .read_parameter_description });
    try self.transition(.{ .querying = .read_row_description });
    try self.transition(.{ .querying = .read_ready_for_query });
    try self.transition(.{ .querying = .{ .send_bind = parameters } });
    try self.transition(.{ .querying = .send_execute });
    try self.transition(.{ .querying = .send_sync });
    try self.transition(.{ .querying = .read_bind_complete });
    try self.transition(.{ .querying = .read_copy_out });

    switch (self.state) {
        .copy_out => |cp_out| return cp_out,
        else => unreachable,
    }
}

pub fn execute(self: *Client, statement: []const u8, parameters: []?[]const u8) !void {
    var data_reader = try self.prepare(statement, parameters);
    defer data_reader.deinit();

    try data_reader.drain();
}

fn transition(self: *Client, event: Event) !void {
    switch (event) {
        .authenticator => |auth_event| {
            switch (self.state) {
                .authenticator => |*authenticator| {
                    try authenticator.transition(auth_event);

                    switch (authenticator.state) {
                        .authenticated => {
                            self.state = (.{ .ready = undefined });
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .querying => |query_event| {
            switch (self.state) {
                .querying => |*querier| {
                    try querier.transition(query_event);

                    switch (querier.state) {
                        .data_reader => |dr| {
                            self.state = .{ .data_reader = dr };
                        },
                        .copy_in => |ci| {
                            self.state = .{ .copy_in = ci };
                        },
                        .copy_out => |co| {
                            self.state = .{ .copy_out = co };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .data_reading => |data_reader_event| {
            switch (self.state) {
                .data_reader => |dr| {
                    try dr.transition(data_reader_event);

                    switch (dr.state) {
                        .complete => {
                            self.state = .{ .ready = undefined };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .copying_in => |copy_in_event| {
            switch (self.state) {
                .copy_in => |cp| {
                    try cp.transition(copy_in_event);

                    switch (cp.state) {
                        .complete => {
                            self.state = .{ .ready = undefined };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
        .copying_out => |copy_out_event| {
            switch (self.state) {
                .copy_out => |cp| {
                    try cp.transition(copy_out_event);

                    switch (cp.state) {
                        .complete => {
                            self.state = .{ .ready = undefined };
                        },
                        else => {},
                    }
                },
                else => unreachable,
            }
        },
    }
}

const Authenticator = struct {
    state: Authenticator.State,
    client: *Client,

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

    pub fn init(client: *Client) Authenticator {
        return Authenticator{
            .state = .{ .startup = undefined },
            .client = client,
        };
    }

    pub fn transition(
        self: *Authenticator,
        event: Authenticator.Event,
    ) !void {
        switch (event) {
            .send_tls_request => {
                try self.client.protocol.write(.{ .ssl_request = undefined });

                self.state = .{ .sent_ssl_request = undefined };
            },
            .send_startup_message => {
                var startup_message = try Frontend.StartupMessage.init_connect_info(
                    self.client.protocol.allocator,
                    self.client.connect_info,
                );
                defer startup_message.deinit();

                try startup_message.set_user(self.client.connect_info.username);
                try startup_message.set_database(self.client.connect_info.database);
                try startup_message.set_application_name(self.client.connect_info.application_name);

                try self.client.protocol.write(.{ .startup_message = startup_message });

                self.state = .{ .received_authentication = undefined };
            },
            .send_sasl_initial_response => {
                switch (self.state) {
                    .received_sasl => |sasl| {
                        const mechanism = sasl.get_first_mechanism();

                        const gs2_flag: Frontend.GS2Flag = switch (mechanism) {
                            .scram_sha_256 => .{ .n = undefined },
                            .scram_sha_256_plus => .{ .p = self.client.protocol.tls_client.?.application_cipher },
                        };

                        const sasl_initial_response = try Frontend.SASLInitialResponse.init(
                            self.client.protocol.allocator,
                            mechanism,
                            gs2_flag,
                        );
                        defer sasl.deinit();

                        try self.client.protocol.write(.{ .sasl_initial_response = sasl_initial_response });

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
                            .password = self.client.connect_info.password,
                        };
                        defer {
                            tuple[0].deinit();
                            tuple[1].deinit();
                        }

                        try self.client.protocol.write(.{ .sasl_response = sasl_response });

                        self.state = .{ .sent_sasl_response = sasl_response };
                    },
                    else => unreachable,
                }
            },
            .send_password_message => {
                switch (self.state) {
                    .received_clear_text_password => {
                        const password_message = Frontend.PasswordMessage{
                            .password = self.client.connect_info.password,
                        };

                        try self.client.protocol.write(.{ .password_message = password_message });

                        self.state = .{ .sent_password_message = undefined };
                    },
                    .received_md5_password => |md5_password| {
                        var password_message = Frontend.PasswordMessage{
                            .password = self.client.connect_info.password,
                        };

                        password_message.hash_md5(&md5_password.salt);

                        try self.client.protocol.write(.{ .password_message = password_message });

                        self.state = .{ .sent_password_message = undefined };
                    },
                    else => unreachable,
                }
            },
            .read_supports_tls_byte => {
                const supports = try self.client.protocol.read_supports_tls_byte();

                self.state = .{ .received_supports_tls_bytes = supports };
            },
            .read_authentication => {
                const message = try self.client.protocol.read();

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
                        const message = self.client.protocol.read() catch |err| {
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
                const message = try self.client.protocol.read();

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
                const message = try self.client.protocol.read();

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
                    message = try self.client.protocol.read();

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
                switch (self.client.connect_info.tls) {
                    .tls => |file| {
                        var ca_bundle: Certificate.Bundle = Certificate.Bundle{};
                        defer ca_bundle.deinit(self.client.protocol.allocator);

                        try ca_bundle.addCertsFromFile(self.client.protocol.allocator, file);

                        const tls_client = try TlsClient.init(
                            self.client.protocol.stream,
                            .{
                                .host = .{ .explicit = self.client.connect_info.host },
                                .ca = .{ .bundle = ca_bundle },
                            },
                        );

                        self.client.protocol.tls_client = tls_client;

                        self.state = .{ .tls_handshake_complete = undefined };
                    },
                    .no_tls => unreachable,
                }
            },
        }
    }
};

const Query = struct {
    state: Query.State,
    client: *Client,
    row_description: ?Backend.RowDescription,

    pub const State = union(enum) {
        ready: void,
        sent_query: void,
        sent_parse: void,
        sent_describe: void,
        sent_sync: void,
        sent_execute: void,
        sent_bind: void,
        received_row_description: Backend.RowDescription,
        received_parse_complete: void,
        received_parameter_description: void,
        received_ready_for_query: void,
        received_bind_complete: void,
        received_no_data: void,
        data_reader: *DataReader,
        copy_in: *CopyIn,
        copy_out: *CopyOut,
    };

    pub const Event = union(enum) {
        send_query: []const u8,
        send_parse: []const u8,
        send_describe: void,
        send_bind: []?[]const u8,
        send_execute: void,
        send_sync: void,
        read_row_description: void,
        read_parse_complete: void,
        read_parameter_description: void,
        read_ready_for_query: void,
        read_bind_complete: void,
        read_data_reader: void,
        read_copy_in: void,
        read_copy_out: void,
    };

    pub fn init(client: *Client) Query {
        return Query{
            .state = .{ .ready = undefined },
            .client = client,
            .row_description = null,
        };
    }

    pub fn transition(self: *Query, event: Query.Event) !void {
        switch (event) {
            .send_query => |statement| {
                const message = Frontend.Query{
                    .statement = statement,
                };

                try self.client.protocol.write(.{ .query = message });

                self.state = .{ .sent_query = undefined };
            },
            .send_parse => |statement| {
                const message = Frontend.Parse{
                    .name = "",
                    .statement = statement,
                };

                try self.client.protocol.write(.{ .parse = message });

                self.state = .{ .sent_parse = undefined };
            },
            .send_describe => {
                const message = Frontend.Describe{
                    .name = "",
                    .target = .statement,
                };

                try self.client.protocol.write(.{ .describe = message });

                self.state = .{ .sent_describe = undefined };
            },
            .send_bind => |bind| {
                const message = Frontend.Bind{
                    .format = .text,
                    .parameters = bind,
                    .portal_name = "",
                    .statement_name = "",
                };

                try self.client.protocol.write(.{ .bind = message });

                self.state = .{ .sent_bind = undefined };
            },
            .send_execute => {
                const message = Frontend.Execute{
                    .portal_name = "",
                    .rows = 0,
                };

                try self.client.protocol.write(.{ .execute = message });

                self.state = .{ .sent_execute = undefined };
            },
            .send_sync => {
                const message = Frontend.Sync{};

                try self.client.protocol.write(.{ .sync = message });

                self.state = .{ .sent_sync = undefined };
            },
            .read_row_description => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .row_description => |rd| {
                        self.row_description = rd;
                        self.state = .{ .received_row_description = rd };
                    },
                    .no_data => {
                        self.state = .{ .received_no_data = undefined };
                    },
                    else => unreachable,
                }
            },
            .read_parse_complete => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .parse_complete => {
                        self.state = .{ .received_parse_complete = undefined };
                    },
                    else => unreachable,
                }
            },
            .read_parameter_description => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .parameter_description => |pd| {
                        pd.deinit();

                        self.state = .{ .received_parameter_description = undefined };
                    },
                    else => unreachable,
                }
            },
            .read_ready_for_query => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .ready_for_query => {
                        self.state = .{ .received_ready_for_query = undefined };
                    },
                    else => unreachable,
                }
            },
            .read_bind_complete => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .bind_complete => {
                        self.state = .{ .received_bind_complete = undefined };
                    },
                    else => unreachable,
                }
            },
            .read_data_reader => {
                self.state = .{
                    .data_reader = try DataReader.init(
                        self.client,
                        self.row_description,
                    ),
                };
            },
            .read_copy_in => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .copy_in_response => |cir| {
                        // TODO: May use CIR for different formats later
                        defer cir.deinit();
                        self.state = .{
                            .copy_in = try CopyIn.init(
                                self.client,
                            ),
                        };
                    },
                    else => unreachable,
                }
            },
            .read_copy_out => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .copy_out_response => |cor| {
                        // TODO: May use CIR for different formats later
                        defer cor.deinit();
                        self.state = .{
                            .copy_out = try CopyOut.init(
                                self.client,
                            ),
                        };
                    },
                    else => unreachable,
                }
            },
        }
    }
};

const DataReader = struct {
    index: usize,
    client: *Client,
    state: DataReader.State,
    row_description: ?Backend.RowDescription,

    pub const State = union(enum) {
        idle: void,
        data_row: Backend.DataRow,
        complete: Backend.CommandComplete,
    };

    pub const Event = enum {
        next,
    };

    pub fn init(
        client: *Client,
        row_description: ?Backend.RowDescription,
    ) !*DataReader {
        var data_reader = try client.protocol.allocator.create(DataReader);

        data_reader.index = 0;
        data_reader.client = client;
        data_reader.state = .{ .idle = undefined };
        data_reader.row_description = row_description;

        return data_reader;
    }

    pub fn deinit(self: *DataReader) void {
        if (self.row_description) |rd| {
            rd.deinit();
        }

        self.client.protocol.allocator.destroy(self);
    }

    pub fn transition(self: *DataReader, event: DataReader.Event) !void {
        switch (event) {
            .next => {
                switch (self.state) {
                    .idle => {
                        const message = try self.client.protocol.read();

                        switch (message) {
                            .data_row => |data_row| {
                                self.state = .{ .data_row = data_row };
                            },
                            .command_complete => |command_complete| {
                                const end_message = try self.client.protocol.read();

                                switch (end_message) {
                                    .ready_for_query => {
                                        self.state = .{ .complete = command_complete };
                                    },
                                    else => unreachable,
                                }
                            },
                            else => unreachable,
                        }
                    },
                    .data_row => |_| {
                        const message = try self.client.protocol.read();

                        switch (message) {
                            .data_row => |data_row| {
                                self.state = .{ .data_row = data_row };
                                self.index += 1;
                            },
                            .command_complete => |command_complete| {
                                const end_message = try self.client.protocol.read();

                                switch (end_message) {
                                    .ready_for_query => {
                                        self.state = .{ .complete = command_complete };
                                    },
                                    else => unreachable,
                                }
                            },
                            else => unreachable,
                        }
                    },
                    .complete => unreachable,
                }
            },
        }
    }

    pub fn next(self: *DataReader) !?*Backend.DataRow {
        try self.client.transition(.{ .data_reading = .next });

        switch (self.state) {
            .data_row => |*dr| return dr,
            .complete => return null,
            .idle => unreachable,
        }
    }

    pub fn drain(self: *DataReader) !void {
        while (try self.next()) |dr| dr.deinit();
    }
};

const CopyIn = struct {
    client: *Client,
    state: CopyIn.State,

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

    pub fn init(client: *Client) !*CopyIn {
        var copy_in = try client.protocol.allocator.create(CopyIn);

        copy_in.client = client;

        return copy_in;
    }

    pub fn deinit(self: *CopyIn) void {
        self.client.protocol.allocator.destroy(self);
    }

    pub fn transition(self: *CopyIn, event: CopyIn.Event) !void {
        switch (event) {
            .write => |bytes| {
                const copy_data = Frontend.CopyData{
                    .data = bytes,
                };

                try self.client.protocol.write(.{ .copy_data = copy_data });

                self.state = .writing;
            },
            .done => {
                const copy_done = Frontend.CopyDone{};
                const sync = Frontend.Sync{};

                try self.client.protocol.write(.{ .copy_done = copy_done });
                try self.client.protocol.write(.{ .sync = sync });

                const message = try self.client.protocol.read();

                switch (message) {
                    .command_complete => {
                        const next_message = try self.client.protocol.read();

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
        try self.client.transition(.{ .copying_in = .{ .write = bytes } });
    }

    pub fn done(self: *CopyIn) !void {
        try self.client.transition(.{ .copying_in = .{ .done = undefined } });
    }
};

const CopyOut = struct {
    client: *Client,
    state: CopyOut.State,
    buffer: ArrayList(u8),

    pub const State = union(enum) {
        idle,
        reading: Backend.CopyData,
        complete,
    };

    pub const Event = enum {
        read,
    };

    pub fn init(client: *Client) !*CopyOut {
        var copy_out = try client.protocol.allocator.create(CopyOut);

        copy_out.client = client;
        copy_out.buffer = ArrayList(u8).init(client.protocol.allocator);

        return copy_out;
    }

    pub fn deinit(self: *CopyOut) void {
        self.buffer.deinit();
        self.client.protocol.allocator.destroy(self);
    }

    pub fn transition(self: *CopyOut, event: CopyOut.Event) !void {
        switch (event) {
            .read => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .copy_data => |cd| self.state = .{ .reading = cd },
                    .copy_done => {
                        const next_message = try self.client.protocol.read();

                        switch (next_message) {
                            .command_complete => {
                                const final_message = try self.client.protocol.read();

                                switch (final_message) {
                                    .ready_for_query => {
                                        self.state = .complete;
                                    },
                                    else => unreachable,
                                }
                            },
                            else => unreachable,
                        }
                    },
                    else => unreachable,
                }
            },
        }
    }

    pub fn read(self: *CopyOut) !?Backend.CopyData {
        try self.client.transition(.{ .copying_out = .read });

        switch (self.state) {
            .reading => |data| return data,
            .complete => return null,
            else => unreachable,
        }
    }
};
