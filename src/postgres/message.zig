const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap([]const u8);
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Stream = std.net.Stream;
const base_64_decoder = std.base64.standard.Decoder;
const base_64_encoder = std.base64.standard.Encoder;
const startsWith = std.mem.startsWith;

const Message = union(enum) {
    authentication_ok: AuthenticationOk,
    // authentiation_kerberos_v5: AuthenticationKerberosV5,
    // authentication_clear_text_password: AuthenticationClearTextPassword,
    // authentication_md5_password: AuthenticationMD5Password,
    // authentication_gss: AuthenticationGSS,
    // authentication_gss_continue: AuthenticationGSSContinue,
    // authentication_sspi: AuthenticationSSPI,
    authentication_sasl: AuthenticationSASL,
    authentication_sasl_continue: AuthenticationSASLContinue,
    authentication_sasl_final: AuthenticationSASLFinal,
    // backend_key_data: BackendKeyData,
    // bind: Bind,
    // bind_complete: BindComplete,
    // cancel_request: CancelRequest,
    // close: Close,
    // close_complete: CloseComplete,
    command_complete: CommandComplete,
    // copy_data: CopyData,
    // copy_done: CopyDone,
    // copy_fail: CopyFail,
    // copy_in_response: CopyInResponse,
    // copy_out_response: CopyOutResponse,
    // copy_both_response: CopyBothResponse,
    // data_row: DataRow, // Shouldn't be exposed by message needs connection pointer
    // describe: Describe,
    // empty_query_response: EmptyQueryResponse,
    error_response: ErrorResponse,
    // execute: Execute,
    // flush: Flush,
    // function_call: FunctionCall,
    // function_call_response: FunctionCallResponse,
    // gssenc_request: GSSENCRequest,
    // gss_response: gss_response,
    // negotiate_protocol_version: NegotiateProtocolVersion,
    // no_data: NoData,
    // notice_response: NoticeResponse,
    // notification_response: NotificationResponse,
    // parameter_description: ParameterDescription,
    parameter_status: ParameterStatus,
    // parse: Parse,
    // parse_complete: ParseComplete,
    // password_message: PasswordMessage,
    query: Query,
    // ready_for_query: ReadyForQuery,
    row_description: RowDescription,
    sasl_initial_response: SASLInitialResponse,
    sasl_response: SASLResponse,
    // ssl_request: SSLRequest,
    startup_message: StartupMessage,
    // sync: Sync,
    // terminate: Terminate,
};

pub const AuthenticationOk = struct {};

pub const AuthenticationSASL = struct {
    mechanism: Mechanism,
};

pub const AuthenticationSASLContinue = struct {
    nonce: []u8, // Might be safe to use [32]u8
    salt: []u8,
    iteration: i32,
    response: []u8,
    client_message: []u8,
};

pub const StartupMessage = struct {
    user: []const u8,
    database: []const u8,
    application_name: []const u8,
    options: StringHashMap = undefined,
};

pub const ErrorResponse = struct {
    code: u8,
    response: []u8,
};

pub const ParameterStatus = struct {
    key: []u8,
    value: []u8,
};

pub const SASLInitialResponse = struct {
    allocator: Allocator,
    mechanism: Mechanism,
    client_message: []u8,

    pub fn init(allocator: Allocator, mechanism: Mechanism) !SASLInitialResponse {
        var nonce: [18]u8 = undefined;
        var encoded_nonce: [24]u8 = undefined;

        std.crypto.random.bytes(&nonce);
        _ = base_64_encoder.encode(&encoded_nonce, &nonce);

        std.log.debug("Len: {d}", .{encoded_nonce.len});

        const client_message = try std.fmt.allocPrint(
            allocator,
            "n,,n=,r={s}",
            .{encoded_nonce},
        );

        return SASLInitialResponse{
            .allocator = allocator,
            .mechanism = mechanism,
            .client_message = client_message,
        };
    }

    pub fn deinit(self: SASLInitialResponse) void {
        self.allocator.free(self.client_message);
    }
};

pub const SASLResponse = struct {
    nonce: []u8,
    salt: []u8,
    iteration: i32,
    response: []u8,
    password: []const u8,
    client_first_message: []u8,
};

pub const AuthenticationSASLFinal = struct {
    response: []u8,
};

pub const Query = struct {
    statement: []const u8,
};

pub const RowDescription = struct {
    allocator: Allocator,
    fields: i16,
    columns: []ColumnDescription,

    pub fn deinit(self: RowDescription) void {
        for (self.columns) |col| col.deinit();
        self.allocator.free(self.columns);
    }
};

pub const ColumnDescription = struct {
    allocator: Allocator,
    field_name: []u8,
    object_id: i32,
    attribute_id: i16,
    data_type_id: i32,
    data_type_size: i16,
    data_type_modifier: i32,
    format_code: i16,

    pub fn deinit(self: ColumnDescription) void {
        self.allocator.free(self.field_name);
    }
};

pub const CommandComplete = struct {
    command: CommandType,
    rows: i32,
};

pub const CommandType = enum {
    insert,
    delete,
    update,
    merge,
    select,
    move,
    fetch,
    copy,
};

pub const AuthenticationType = enum(i32) {
    ok = 0,
    kerberosV5 = 2,
    clear_text_password = 3,
    md5_password = 5,
    gss = 7,
    gss_continue = 8,
    sspi = 9,
    sasl = 10,
    sasl_continue = 11,
    sasl_final = 12,
};

const Mechanism = enum {
    scram_sha_256,
    scram_sha_256_plus,

    pub fn from_string(str: []u8) ?Mechanism {
        if (startsWith(u8, str, "SCRAM-SHA-256")) return .scram_sha_256;
        if (startsWith(u8, str, "SCRAM-SHA-256-PLUS")) return .scram_sha_256_plus;

        return null;
    }

    pub fn to_string(self: Mechanism, allocator: Allocator) ![]u8 {
        return switch (self) {
            .scram_sha_256 => {
                return try allocator.dupe(u8, "SCRAM-SHA-256");
            },
            .scram_sha_256_plus => {
                return try allocator.dupe(u8, "SCRAM-SHA-256-PLUS");
            },
        };
    }
};

pub fn read(allocator: Allocator, reader: AnyReader) !Message {
    const message_type = try reader.readByte();

    switch (message_type) {
        // No idea why its R for anything authentication related
        'R' => {
            // R means we are expecting something todo with authentication
            const size_of_message = try reader.readInt(i32, .big);
            const auth_type = try reader.readInt(i32, .big);

            switch (@as(AuthenticationType, @enumFromInt(auth_type))) {
                .ok => {
                    if (auth_type != 0) @panic("Authentication message confirmation byte is not 0");

                    return Message{
                        .authentication_ok = AuthenticationOk{},
                    };
                },
                .kerberosV5 => {
                    @panic("Not yet implemented");
                },
                .clear_text_password => {
                    @panic("Not yet implemented");
                },
                .md5_password => {
                    @panic("Not yet implemented");
                },
                .gss => {
                    @panic("Not yet implemented");
                },
                .gss_continue => {
                    @panic("Not yet implemented");
                },
                .sspi => {
                    @panic("Not yet implemented");
                },
                // R (Byte1) + Length of message (i32) + 10 (i32) + String + Null byte
                .sasl => {
                    // There are only two current possible values SCRAM-SHA-256 and SCRAM-SHA-256-PLUS
                    // To avoid allocating will presume type based of length
                    // Len = 13 -> SCRAM-SHA-256
                    // Len = 18 -> SCRAM-SHA-256-PLUS
                    const size_of_buffer = size_of_message - 8; // Subtract message length and auth type

                    // Will read the null terminator for the string and the end null byte
                    _ = try reader.skipBytes(@intCast(size_of_buffer), .{});

                    // Note this includes the null bytes at the end
                    switch (size_of_buffer) {
                        15 => {
                            return Message{
                                .authentication_sasl = AuthenticationSASL{
                                    .mechanism = .scram_sha_256,
                                },
                            };
                        },
                        20 => {
                            return Message{
                                .authentication_sasl = AuthenticationSASL{
                                    .mechanism = .scram_sha_256_plus,
                                },
                            };
                        },
                        else => @panic("Expected message to return a valid mechanism"),
                    }
                },
                // R (Byte1) + Length of message (i32) + 11 (i32) + Byte (N)
                // Format of bytes r={nonce},s={encoded_salt},i={iterations}
                // Not sure if this should be update to be able to handle any order
                // At the moment it presumes it is always in the formatted order
                .sasl_continue => {
                    const size_of_buffer = size_of_message - 8; // Subtract message length and auth type
                    const buff = try allocator.alloc(u8, @intCast(size_of_buffer));

                    std.log.debug("size of buffer: {d}", .{size_of_buffer});

                    _ = try reader.readAtLeast(buff, @intCast(size_of_buffer));

                    var fixed_buffer = std.io.fixedBufferStream(buff);
                    var buffer_reader = fixed_buffer.reader();

                    const nonce_buffer = try buffer_reader.readUntilDelimiterAlloc(allocator, ',', 256);
                    defer allocator.free(nonce_buffer);

                    const encoded_salt = try buffer_reader.readUntilDelimiterAlloc(allocator, ',', 256);
                    defer allocator.free(encoded_salt);

                    const iteration_buffer = try buffer_reader.readAllAlloc(allocator, 256);
                    defer allocator.free(iteration_buffer);

                    const size_of_salt = try base_64_decoder.calcSizeForSlice(encoded_salt[2..]);
                    const salt = try allocator.alloc(u8, size_of_salt);
                    const nonce = try allocator.dupe(u8, nonce_buffer[2..]);
                    const iteration = try std.fmt.parseInt(i32, iteration_buffer[2..], 10);

                    // Decode the salt and fill the salt buffer
                    try base_64_decoder.decode(salt, encoded_salt[2..]);

                    return Message{
                        .authentication_sasl_continue = AuthenticationSASLContinue{
                            .response = buff,
                            .nonce = nonce,
                            .salt = salt,
                            .iteration = iteration,
                            .client_message = undefined,
                        },
                    };
                },
                // R (Byte1) + Length of message (i32) + 12 (i32) + Byte (N)
                .sasl_final => {
                    const size_of_buffer = size_of_message - 8; // Subtract message length and auth type
                    const buff = try allocator.alloc(u8, @intCast(size_of_buffer));

                    _ = try reader.readAtLeast(buff, @intCast(size_of_buffer));

                    return Message{
                        .authentication_sasl_final = AuthenticationSASLFinal{
                            .response = buff,
                        },
                    };
                },
            }
        },
        'E' => {
            const size_of_message = try reader.readInt(i32, .big);
            const code = try reader.readByte();

            // If zero treat it as the null terminate for the message
            if (code == 0) return Message{
                .error_response = ErrorResponse{
                    .code = code,
                    .response = "",
                },
            };

            const size_of_buffer: usize = @intCast(size_of_message - 5); // Subtract message length and 1 byte for code
            const response = try allocator.alloc(u8, size_of_buffer);

            _ = try reader.readAtLeast(response, size_of_buffer);

            return Message{
                .error_response = ErrorResponse{
                    .code = code,
                    .response = response,
                },
            };
        },
        'S' => {
            const size_of_message = try reader.readInt(i32, .big);

            // TODO: Add PortalSuspended
            if (size_of_message == 4) @panic("Not yet implemented");

            // Otherwise we are a ParameterStatus message
            const key = try reader.readUntilDelimiterAlloc(allocator, '\x00', @intCast(size_of_message));
            const value = try reader.readUntilDelimiterAlloc(allocator, '\x00', @intCast(size_of_message));

            return Message{
                .parameter_status = ParameterStatus{
                    .key = key,
                    .value = value,
                },
            };
        },
        'T' => {
            _ = try reader.readInt(i32, .big);
            const fields = try reader.readInt(i16, .big);
            const columns = try allocator.alloc(ColumnDescription, @intCast(fields));
            const upper_bound: usize = @intCast(fields);

            for (0..upper_bound) |index| {
                const field_name = try reader.readUntilDelimiterAlloc(allocator, '\x00', 1024);
                const object_id = try reader.readInt(i32, .big);
                const attribute_id = try reader.readInt(i16, .big);
                const data_type_id = try reader.readInt(i32, .big);
                const data_type_size = try reader.readInt(i16, .big);
                const data_type_modifier = try reader.readInt(i32, .big);
                const format_code = try reader.readInt(i16, .big);

                const column = ColumnDescription{
                    .allocator = allocator,
                    .field_name = field_name,
                    .object_id = object_id,
                    .attribute_id = attribute_id,
                    .data_type_id = data_type_id,
                    .data_type_size = data_type_size,
                    .data_type_modifier = data_type_modifier,
                    .format_code = format_code,
                };

                columns[index] = column;
            }

            return Message{
                .row_description = RowDescription{
                    .allocator = allocator,
                    .fields = fields,
                    .columns = columns,
                },
            };
        },
        else => @panic("Unexpected message type"),
    }
}

pub fn write(allocator: Allocator, message: Message, writer: AnyWriter) !void {
    switch (message) {
        // Length of message (i32) + Protocol version (i32) + List of String String
        .startup_message => |startup_message| {
            var payload_len: usize = 9;
            const user_key = "user\x00";
            const database_key = "database\x00";
            const application_key = "application_name\x00";

            payload_len += user_key.len;
            payload_len += database_key.len;
            payload_len += application_key.len;
            payload_len += startup_message.user.len + 1;
            payload_len += startup_message.database.len + 1;
            payload_len += startup_message.application_name.len + 1;

            var iter = startup_message.options.iterator();

            while (iter.next()) |entry| {
                payload_len += entry.key_ptr.len + entry.value_ptr.len + 2;
            }

            try writer.writeInt(u32, @intCast(payload_len), .big);
            try writer.writeInt(i32, 196608, .big);
            _ = try writer.write(user_key);
            _ = try writer.write(startup_message.user);
            _ = try writer.write("\x00");
            _ = try writer.write(database_key);
            _ = try writer.write(startup_message.database);
            _ = try writer.write("\x00");
            _ = try writer.write(application_key);
            _ = try writer.write(startup_message.application_name);
            _ = try writer.write("\x00");
            _ = try writer.write("\x00");
        },
        .sasl_response => |sasl_response| {
            // TODO: Tidy this up and document wtf is going on
            const unproved = try std.fmt.allocPrint(
                allocator,
                "c=biws,r={s}",
                .{sasl_response.nonce},
            );
            defer allocator.free(unproved);

            const auth_message = try std.fmt.allocPrint(
                allocator,
                "{s},{s},{s}",
                .{
                    sasl_response.client_first_message[3..],
                    sasl_response.response,
                    unproved,
                },
            );
            defer allocator.free(auth_message);

            const salted_password = blk: {
                var buf: [32]u8 = undefined;
                try std.crypto.pwhash.pbkdf2(
                    &buf,
                    sasl_response.password,
                    sasl_response.salt,
                    @intCast(sasl_response.iteration),
                    std.crypto.auth.hmac.sha2.HmacSha256,
                );
                break :blk buf;
            };

            const proof = blk: {
                var client_key: [32]u8 = undefined;
                std.crypto.auth.hmac.sha2.HmacSha256.create(&client_key, "Client Key", &salted_password);

                var stored_key: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(&client_key, &stored_key, .{});

                var client_signature: [32]u8 = undefined;
                std.crypto.auth.hmac.sha2.HmacSha256.create(&client_signature, auth_message, &stored_key);

                var proof: [32]u8 = undefined;
                for (client_key, client_signature, 0..) |ck, cs, i| {
                    proof[i] = ck ^ cs;
                }

                var encoded_proof: [44]u8 = undefined;
                _ = base_64_encoder.encode(&encoded_proof, &proof);
                break :blk encoded_proof;
            };

            const str = try std.fmt.allocPrint(allocator, "{s},p={s}", .{ unproved, proof });
            defer allocator.free(str);

            try writer.writeByte('p');
            try writer.writeInt(i32, @intCast(str.len + 4), .big);
            _ = try writer.write(str);
        },
        .sasl_initial_response => |sasl_initial_response| {
            var payload_len: usize = 9;

            const mechanism = try sasl_initial_response.mechanism.to_string(allocator);
            defer allocator.free(mechanism);

            payload_len += mechanism.len;
            payload_len += sasl_initial_response.client_message.len;

            _ = try writer.writeByte('p');
            try writer.writeInt(u32, @intCast(payload_len), .big);
            _ = try writer.write(mechanism);
            try writer.writeByte(0);
            try writer.writeInt(u32, @intCast(sasl_initial_response.client_message.len), .big);
            _ = try writer.write(sasl_initial_response.client_message);
        },
        .query => |query| {
            const payload_len = query.statement.len + 5; // 4 bytes for the len

            try writer.writeByte('Q');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(query.statement);
            try writer.writeByte(0);
        },
        else => @panic("Either not implemented or not valid"),
    }
}
