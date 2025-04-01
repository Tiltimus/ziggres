const std = @import("std");
pub const Protocol = @import("protocol.zig");
pub const ConnectInfo = @import("protocol/connect_info.zig");
const Backend = @import("protocol/backend.zig").Backend;
const Frontend = @import("protocol/frontend.zig").Frontend;
const Format = Frontend.Format;
const Target = Frontend.Target;
const Allocator = std.mem.Allocator;
const Tuple = std.meta.Tuple;
const Certificate = std.crypto.Certificate;
const TlsClient = std.crypto.tls.Client;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

pub const UNNAMED = "";

const Client = @This();

state: State,
protocol: Protocol,
connect_info: ConnectInfo,

pub const State = enum(u8) {
    authenticating,
    querying,
    data_reading,
    copying_in,
    copying_out,
    ready,
    closed,
};

pub fn connect(allocator: Allocator, connect_info: ConnectInfo) !Client {
    const protocol = Protocol.init(allocator);

    var client = Client{
        .protocol = protocol,
        .connect_info = connect_info,
        .state = .authenticating,
    };

    var authenticator = Authenticator.init(&client);

    try client.protocol.connect(connect_info);
    try authenticator.authenticate();

    client.state = .ready;

    return client;
}

pub fn close(self: *Client) void {
    self.protocol.close();
    self.state = .closed;
}

pub fn simple(self: *Client, statement: []const u8) !SimpleReader {
    assert(self.state == .ready);

    self.state = .querying;

    var querying = Query.init(self);

    try querying.transition(.{ .send_query = statement });

    self.state = .data_reading;

    return SimpleReader{
        .index = 0,
        .client = self,
        .state = .idle,
    };
}

pub fn extended(
    self: *Client,
    settings: ExtendedQuery,
) !DataReader {
    assert(self.state == .ready);

    self.state = .querying;

    var querying = Query.init(self);
    const bind = settings.bind();
    const exe = settings.execute();
    const parse = settings.parse();
    const describe = settings.describe(.statement);

    try querying.transition(.{ .send_parse = parse });
    try querying.transition(.{ .send_bind = bind });
    try querying.transition(.{ .send_describe = describe });
    try querying.transition(.{ .send_execute = exe });
    try querying.transition(.send_sync);
    try querying.transition(.read_parse_complete);
    try querying.transition(.read_bind_complete);
    try querying.transition(.read_parameter_description);
    try querying.transition(.read_row_description);

    self.state = .data_reading;

    return DataReader{
        .index = 0,
        .client = self,
        .state = .idle,
        .row_description = querying.row_description,
        .next_row_description = null,
        .command_complete = null,
        .limit = settings.rows,
    };
}

pub fn prepare(
    self: *Client,
    name: []const u8,
    statement: []const u8,
    parameters: []?[]const u8,
) !DataReader {
    const settings = ExtendedQuery{
        .statement = statement,
        .parameters = parameters,
        .statement_name = name,
    };

    return self.extended(settings);
}

pub fn execute(
    self: *Client,
    name: []const u8,
    statement: []const u8,
    parameters: []?[]const u8,
) !void {
    var data_reader = try self.prepare(
        name,
        statement,
        parameters,
    );
    defer data_reader.deinit();

    try data_reader.drain();
}

pub fn copyIn(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !CopyIn {
    const settings = ExtendedQuery{
        .statement = statement,
        .parameters = parameters,
    };

    var data_reader = try self.extended(settings);
    defer data_reader.deinit();

    self.state = .copying_in;

    return CopyIn{
        .client = self,
        .state = .idle,
    };
}

pub fn copyOut(
    self: *Client,
    statement: []const u8,
    parameters: []?[]const u8,
) !CopyOut {
    const settings = ExtendedQuery{
        .statement = statement,
        .parameters = parameters,
    };

    var data_reader = try self.extended(settings);
    defer data_reader.deinit();

    self.state = .copying_out;

    return CopyOut{
        .client = self,
        .state = .idle,
        .buffer = ArrayList(u8).init(self.protocol.allocator),
    };
}

pub const ExtendedQuery = struct {
    statement: []const u8,
    portal_name: []const u8 = "",
    statement_name: []const u8 = "",
    parameter_format: Format = .text,
    result_format: Format = .text,
    parameters: []?[]const u8 = &.{},
    rows: i32 = 0,

    pub fn bind(self: ExtendedQuery) Frontend.Bind {
        return Frontend.Bind{
            .parameter_format = self.parameter_format,
            .result_format = self.result_format,
            .parameters = self.parameters,
            .portal_name = self.portal_name,
            .statement_name = self.statement_name,
        };
    }

    pub fn execute(self: ExtendedQuery) Frontend.Execute {
        return Frontend.Execute{
            .portal_name = self.portal_name,
            .rows = self.rows,
        };
    }

    pub fn parse(self: ExtendedQuery) Frontend.Parse {
        return Frontend.Parse{
            .name = self.statement_name,
            .statement = self.statement,
        };
    }

    pub fn describe(self: ExtendedQuery, target: Target) Frontend.Describe {
        const name = if (target == .statement)
            self.statement_name
        else
            self.portal_name;

        return Frontend.Describe{
            .name = name,
            .target = target,
        };
    }
};

const Authenticator = struct {
    client: *Client,
    state: Authenticator.State,

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

    pub fn authenticate(self: *Authenticator) !void {
        switch (self.client.connect_info.tls) {
            .tls => {
                try self.transition(.send_tls_request);
                try self.transition(.read_supports_tls_byte);
                try self.transition(.tls_handshake);
            },
            .no_tls => {},
        }

        try self.transition(.send_startup_message);
        try self.transition(.read_authentication);

        switch (self.state) {
            .received_sasl => {
                try self.transition(.send_sasl_initial_response);
                try self.transition(.read_sasl_continue);
                try self.transition(.send_sasl_response);
                try self.transition(.read_sasl_final);
                try self.transition(.read_authentication_ok);
                try self.transition(.read_param_statuses_until_ready);
            },
            .received_clear_text_password => {
                try self.transition(.send_password_message);
                try self.transition(.read_authentication_ok);
                try self.transition(.read_param_statuses_until_ready);
            },
            .received_md5_password => {
                try self.transition(.send_password_message);
                try self.transition(.read_authentication_ok);
                try self.transition(.read_param_statuses_until_ready);
            },
            // TODO: Add support for other authentication paths
            else => unreachable,
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
    };

    pub const Event = union(enum) {
        send_query: []const u8,
        send_parse: Frontend.Parse,
        send_describe: Frontend.Describe,
        send_bind: Frontend.Bind,
        send_execute: Frontend.Execute,
        send_sync: void,
        read_row_description: void,
        read_parse_complete: void,
        read_parameter_description: void,
        read_ready_for_query: void,
        read_bind_complete: void,
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
            .send_parse => |parse| {
                try self.client.protocol.write(.{ .parse = parse });

                self.state = .{ .sent_parse = undefined };
            },
            .send_describe => |describe| {
                try self.client.protocol.write(.{ .describe = describe });

                self.state = .{ .sent_describe = undefined };
            },
            .send_bind => |bind| {
                try self.client.protocol.write(.{ .bind = bind });

                self.state = .{ .sent_bind = undefined };
            },
            .send_execute => |exe| {
                try self.client.protocol.write(.{ .execute = exe });

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
                        return;
                    },
                    .no_data => {
                        self.state = .{ .received_no_data = undefined };
                        return;
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
        }
    }
};

pub const DataReader = struct {
    index: usize,
    client: *Client,
    state: DataReader.State,
    row_description: ?Backend.RowDescription,
    command_complete: ?Backend.CommandComplete,
    next_row_description: ?Backend.RowDescription,
    limit: i32,

    pub const State = union(enum) {
        idle: void,
        row: Backend.DataRow,
        suspended: void,
        complete: void,
    };

    pub const Event = enum {
        next,
    };

    pub fn deinit(self: *DataReader) void {
        if (self.row_description) |rd| {
            rd.deinit();
        }
    }

    pub fn transition(self: *DataReader, event: DataReader.Event) !void {
        switch (event) {
            .next => {
                switch (self.state) {
                    .idle => {
                        const message = try self.client.protocol.read();

                        to_complete: switch (message) {
                            .data_row => |data_row| {
                                self.state = .{ .row = data_row };
                                return;
                            },
                            .row_description => |rd| {
                                self.row_description = rd;
                                continue :to_complete try self.client.protocol.read();
                            },
                            .command_complete => |command_complete| {
                                self.state = .complete;
                                self.command_complete = command_complete;

                                continue :to_complete try self.client.protocol.read();
                            },
                            .ready_for_query => {
                                self.client.state = .ready;
                                return;
                            },
                            else => unreachable,
                        }
                    },
                    .row => {
                        const message = try self.client.protocol.read();

                        to_complete: switch (message) {
                            .data_row => |data_row| {
                                self.state = .{ .row = data_row };
                                self.index += 1;
                                return;
                            },
                            .command_complete => |command_complete| {
                                self.state = .complete;
                                self.command_complete = command_complete;

                                continue :to_complete try self.client.protocol.read();
                            },
                            .portal_suspended => {
                                self.state = .suspended;

                                const exe = Frontend.Execute{
                                    .portal_name = "",
                                    .rows = self.limit,
                                };

                                try self.client.protocol.write(.{ .execute = exe });
                                try self.client.protocol.write(.{ .sync = Frontend.Sync{} });

                                continue :to_complete try self.client.protocol.read();
                            },
                            .ready_for_query => {
                                switch (self.state) {
                                    .suspended => {
                                        continue :to_complete try self.client.protocol.read();
                                    },
                                    else => {
                                        self.client.state = .ready;
                                        return;
                                    },
                                }
                            },
                            .row_description => |rd| {
                                self.next_row_description = rd;
                                return;
                            },
                            else => unreachable,
                        }
                    },
                    .complete => unreachable,
                    .suspended => unreachable,
                }
            },
        }
    }

    pub fn next(self: *DataReader) !?*Backend.DataRow {
        try self.transition(.next);

        switch (self.state) {
            .row => |*dr| return dr,
            .complete => return null,
            else => unreachable,
        }
    }

    pub fn drain(self: *DataReader) !void {
        while (try self.next()) |dr| dr.deinit();
    }

    pub fn rows(self: DataReader) i32 {
        if (self.command_complete) |cc| cc.rows else 0;
    }
};

pub const SimpleReader = struct {
    index: i32,
    state: SimpleReader.State,
    client: *Client,

    pub const State = union(enum) {
        idle: void,
        data_reader: DataReader,
        complete: void,
    };

    pub const Event = enum {
        next,
    };

    pub fn transition(self: *SimpleReader, event: SimpleReader.Event) !void {
        switch (event) {
            .next => {
                switch (self.state) {
                    .idle => {
                        const data_reader = DataReader{
                            .index = 0,
                            .client = self.client,
                            .state = .idle,
                            .row_description = null,
                            .next_row_description = null,
                            .command_complete = null,
                            .limit = 0,
                        };

                        self.state = .{ .data_reader = data_reader };
                    },
                    .data_reader => |data_reader| {
                        if (data_reader.next_row_description) |next_rd| {
                            const next_data_reader = DataReader{
                                .index = 0,
                                .client = self.client,
                                .state = .idle,
                                .row_description = next_rd,
                                .next_row_description = null,
                                .command_complete = null,
                                .limit = 0,
                            };

                            self.state = .{ .data_reader = next_data_reader };
                            self.index += 1;
                            return;
                        }

                        self.state = .complete;
                        return;
                    },
                    .complete => unreachable,
                }
            },
        }
    }

    pub fn next(self: *SimpleReader) !?*DataReader {
        try self.transition(.next);

        switch (self.state) {
            .data_reader => |*dr| return dr,
            .complete => return null,
            else => unreachable,
        }
    }
};

pub const CopyIn = struct {
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
        write_done: void,
        read_copy_in_response: void,
        read_command_complete: void,
    };

    pub const empty: CopyIn = .{
        .client = undefined,
        .state = .idle,
    };

    pub fn transition(self: *CopyIn, event: CopyIn.Event) !void {
        switch (event) {
            .write => |bytes| {
                const copy_data = Frontend.CopyData{
                    .data = bytes,
                };

                try self.client.protocol.write(.{ .copy_data = copy_data });

                self.state = .writing;
            },
            .write_done => {
                const copy_done = Frontend.CopyDone{};
                const sync = Frontend.Sync{};

                try self.client.protocol.write(.{ .copy_done = copy_done });
                try self.client.protocol.write(.{ .sync = sync });
            },
            .read_copy_in_response => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .copy_in_response => |copy_in_response| copy_in_response.deinit(),
                    else => unreachable,
                }
            },
            .read_command_complete => {
                const message = try self.client.protocol.read();

                switch (message) {
                    .command_complete => {
                        const next_message = try self.client.protocol.read();

                        switch (next_message) {
                            .ready_for_query => {
                                self.state = .complete;
                                self.client.state = .ready;
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
        try self.transition(.{ .write = bytes });
    }

    pub fn done(self: *CopyIn) !void {
        try self.transition(.{ .write_done = undefined });
        try self.transition(.{ .read_copy_in_response = undefined });
        try self.transition(.{ .read_command_complete = undefined });
    }
};

pub const CopyOut = struct {
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

    pub const empty: CopyOut = .{
        .client = undefined,
        .state = .idle,
        .buffer = undefined,
    };

    pub fn deinit(self: *CopyOut) void {
        self.buffer.deinit();
    }

    pub fn transition(self: *CopyOut, event: CopyOut.Event) !void {
        switch (event) {
            .read => {
                const message = try self.client.protocol.read();

                to_complete: switch (message) {
                    .copy_data => |cd| {
                        self.state = .{ .reading = cd };
                        return;
                    },
                    .copy_done => {
                        continue :to_complete try self.client.protocol.read();
                    },
                    .copy_out_response => |copy_out_response| {
                        copy_out_response.deinit();
                        continue :to_complete try self.client.protocol.read();
                    },
                    .command_complete => {
                        continue :to_complete try self.client.protocol.read();
                    },
                    .ready_for_query => {
                        self.state = .complete;
                        self.client.state = .ready;
                    },
                    else => unreachable,
                }
            },
        }
    }

    pub fn read(self: *CopyOut) !?Backend.CopyData {
        try self.transition(.read);

        switch (self.state) {
            .reading => |data| return data,
            .complete => return null,
            else => unreachable,
        }
    }
};
