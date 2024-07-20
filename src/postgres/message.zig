const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap([]const u8);
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Stream = std.net.Stream;
const LinkedList = std.SinglyLinkedList;
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
    nonce: [48]u8, // Might be safe to use [32]u8
    salt: [16]u8,
    iteration: i32,
    response: [84]u8,
    client_message: [32]u8,
};

pub const StartupMessage = struct {
    user: []const u8,
    database: []const u8,
    application_name: []const u8,
    options: StringHashMap = undefined,
};

// TODO: I think I want to have an iterator style for the
// response or allow the end call to assgin an allocator if and when they get an error
pub const ErrorResponse = struct {
    code: u8,
    // response: []u8,
};

pub const ParameterStatus = struct {
    key: []u8,
    value: []u8,
};

pub const SASLInitialResponse = struct {
    mechanism: Mechanism,
    client_message: [32]u8,

    pub fn init(mechanism: Mechanism) !SASLInitialResponse {
        var nonce: [18]u8 = undefined;
        var encoded_nonce: [24]u8 = undefined;
        var client_message: [32]u8 = undefined;

        std.crypto.random.bytes(&nonce);
        _ = base_64_encoder.encode(&encoded_nonce, &nonce);

        _ = try std.fmt.bufPrint(
            &client_message,
            "n,,n=,r={s}",
            .{encoded_nonce},
        );

        return SASLInitialResponse{
            .mechanism = mechanism,
            .client_message = client_message,
        };
    }
};

pub const SASLResponse = struct {
    nonce: [48]u8,
    salt: [16]u8,
    iteration: i32,
    response: [84]u8,
    password: []const u8,
    client_first_message: [32]u8,
};

pub const AuthenticationSASLFinal = struct {};

pub const Query = struct {
    statement: []const u8,
};

pub const RowDescription = struct {
    fields: i16,
    columns: LinkedList(ColumnDescription),

    pub fn deinit(self: RowDescription) void {
        for (self.columns) |col| col.deinit();
        self.allocator.free(self.columns);
    }
};

pub const ColumnDescription = struct {
    field_name: [64]u8,
    object_id: i32,
    attribute_id: i16,
    data_type_id: i32,
    data_type_size: i16,
    data_type_modifier: i32,
    format_code: i16,
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

pub fn read(reader: AnyReader) !Message {
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

                    // Example value: r=wPQjRfb6FZn3ez5t9gRTVb+G8M+wehfQmvSdbtyW4N0OjVCZ,s=gPc86FtzgE+GNcocleODEQ==,i=4096
                    // r or nonce is the client sent nonce plus the server sent nonce thus
                    // r= will always be 24 * 2 or 48 bytes long
                    // s or encoded salt will always be 24 bytes long 16 decoded
                    // i will always be 4 bytes long or a u32
                    var buff: [84]u8 = undefined;

                    _ = try reader.readAtLeast(&buff, @intCast(size_of_buffer));

                    std.log.debug("size of buffer: {s}", .{buff});

                    var fixed_buffer = std.io.fixedBufferStream(&buff);
                    var buffer_reader = fixed_buffer.reader();

                    var nonce: [48]u8 = undefined;
                    var encoded_salt: [24]u8 = undefined;
                    var iteration_buffer: [4]u8 = undefined;
                    var salt: [16]u8 = undefined;

                    _ = try buffer_reader.skipBytes(2, .{}); // Skip the r=
                    _ = try buffer_reader.read(&nonce);
                    _ = try buffer_reader.skipBytes(1, .{});

                    _ = try buffer_reader.skipBytes(2, .{}); // Skip the s=
                    _ = try buffer_reader.read(&encoded_salt);
                    _ = try buffer_reader.skipBytes(1, .{});

                    _ = try buffer_reader.skipBytes(2, .{}); // Skip the i=
                    _ = try buffer_reader.read(&iteration_buffer);

                    // Decode the salt and fill the salt buffer
                    try base_64_decoder.decode(&salt, &encoded_salt);

                    const iteration = try std.fmt.parseInt(i32, &iteration_buffer, 10);

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

                    _ = try reader.skipBytes(@intCast(size_of_buffer), .{});

                    return Message{
                        .authentication_sasl_final = AuthenticationSASLFinal{},
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
                },
            };

            const size_of_buffer: usize = @intCast(size_of_message - 5); // Subtract message length and 1 byte for code

            _ = try reader.skipBytes(size_of_buffer, .{});

            return Message{
                .error_response = ErrorResponse{
                    .code = code,
                },
            };
        },
        'S' => {
            @panic("Not yet implemented need a better way of reading without allocations");
            // const size_of_message = try reader.readInt(i32, .big);

            // // TODO: Add PortalSuspended
            // if (size_of_message == 4) @panic("Not yet implemented");

            // // Otherwise we are a ParameterStatus message
            // const key = try reader.readUntilDelimiterAlloc(allocator, '\x00', @intCast(size_of_message));
            // const value = try reader.readUntilDelimiterAlloc(allocator, '\x00', @intCast(size_of_message));

            // return Message{
            //     .parameter_status = ParameterStatus{
            //         .key = key,
            //         .value = value,
            //     },
            // };
        },
        'T' => {
            _ = try reader.readInt(i32, .big);
            const fields = try reader.readInt(i16, .big);
            var columns = LinkedList(ColumnDescription){};
            const upper_bound: usize = @intCast(fields);

            for (0..upper_bound) |_| {
                var field_name: [64]u8 = undefined;
                _ = try reader.readUntilDelimiter(&field_name, '\x00');

                const object_id = try reader.readInt(i32, .big);
                const attribute_id = try reader.readInt(i16, .big);
                const data_type_id = try reader.readInt(i32, .big);
                const data_type_size = try reader.readInt(i16, .big);
                const data_type_modifier = try reader.readInt(i32, .big);
                const format_code = try reader.readInt(i16, .big);

                const column = ColumnDescription{
                    .field_name = field_name,
                    .object_id = object_id,
                    .attribute_id = attribute_id,
                    .data_type_id = data_type_id,
                    .data_type_size = data_type_size,
                    .data_type_modifier = data_type_modifier,
                    .format_code = format_code,
                };

                var node = LinkedList(ColumnDescription).Node{
                    .data = column,
                };

                columns.prepend(&node);
            }

            return Message{
                .row_description = RowDescription{
                    .fields = fields,
                    .columns = columns,
                },
            };
        },
        else => @panic("Unexpected message type"),
    }
}

pub fn write(message: Message, writer: AnyWriter) !void {
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
            var unproved: [57]u8 = undefined;

            _ = try std.fmt.bufPrint(
                &unproved,
                "c=biws,r={s}",
                .{sasl_response.nonce},
            );

            const auth_message_len = sasl_response.client_first_message[3..].len + sasl_response.response.len + unproved.len;

            var auth_message: [auth_message_len + 2]u8 = undefined;

            _ = try std.fmt.bufPrint(
                &auth_message,
                "{s},{s},{s}",
                .{
                    sasl_response.client_first_message[3..],
                    sasl_response.response,
                    unproved,
                },
            );

            const salted_password = blk: {
                var buf: [32]u8 = undefined;
                try std.crypto.pwhash.pbkdf2(
                    &buf,
                    sasl_response.password,
                    &sasl_response.salt,
                    @intCast(sasl_response.iteration),
                    std.crypto.auth.hmac.sha2.HmacSha256,
                );
                break :blk buf;
            };

            const proof: [44]u8 = blk: {
                var client_key: [32]u8 = undefined;
                std.crypto.auth.hmac.sha2.HmacSha256.create(&client_key, "Client Key", &salted_password);

                var stored_key: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(&client_key, &stored_key, .{});

                var client_signature: [32]u8 = undefined;
                std.crypto.auth.hmac.sha2.HmacSha256.create(&client_signature, &auth_message, &stored_key);

                var proof: [32]u8 = undefined;
                for (client_key, client_signature, 0..) |ck, cs, i| {
                    proof[i] = ck ^ cs;
                }

                var encoded_proof: [44]u8 = undefined;
                _ = base_64_encoder.encode(&encoded_proof, &proof);
                break :blk encoded_proof;
            };

            var str: [unproved.len + proof.len + 3]u8 = undefined;

            _ = try std.fmt.bufPrint(&str, "{s},p={s}", .{ unproved, proof });

            try writer.writeByte('p');
            try writer.writeInt(i32, @intCast(str.len + 4), .big);
            _ = try writer.write(&str);
        },
        .sasl_initial_response => |sasl_initial_response| {
            var payload_len: usize = 9;

            const mechanism = switch (sasl_initial_response.mechanism) {
                .scram_sha_256 => "SCRAM-SHA-256",
                .scram_sha_256_plus => "SCRAM-SHA-256-PLUS",
            };

            payload_len += mechanism.len;
            payload_len += sasl_initial_response.client_message.len;

            _ = try writer.writeByte('p');
            try writer.writeInt(u32, @intCast(payload_len), .big);
            _ = try writer.write(mechanism);
            try writer.writeByte(0);
            try writer.writeInt(u32, @intCast(sasl_initial_response.client_message.len), .big);
            _ = try writer.write(&sasl_initial_response.client_message);
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
