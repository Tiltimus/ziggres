const std = @import("std");
const DataRow = @import("./data_row.zig");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap([]const u8);
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const Stream = std.net.Stream;
const ArenaAllocator = std.heap.ArenaAllocator;
const LinkedList = std.SinglyLinkedList;
const ArrayList = std.ArrayList;
const fixedBuffer = std.io.fixedBufferStream;
const base_64_decoder = std.base64.standard.Decoder;
const base_64_encoder = std.base64.standard.Encoder;
const startsWith = std.mem.startsWith;
const test_allocator = std.testing.allocator;
const expect = std.testing.expect;
const eql = std.mem.eql;

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
    backend_key_data: BackendKeyData,
    bind: Bind,
    bind_complete: BindComplete,
    cancel_request: CancelRequest,
    close: Close,
    close_complete: CloseComplete,
    command_complete: CommandComplete,
    copy_data: CopyData,
    copy_done: CopyDone,
    copy_fail: CopyFail,
    copy_in_response: CopyInResponse,
    copy_out_response: CopyOutResponse,
    copy_both_response: CopyBothResponse,
    data_row: DataRow.NoContextDataRow,
    describe: Describe,
    empty_query_response: EmptyQueryResponse,
    error_response: ErrorResponse,
    execute: Execute,
    flush: Flush,
    function_call: FunctionCall,
    function_call_response: FunctionCallResponse,
    gssenc_request: GSSENCRequest,
    gss_response: GssResponse,
    negotiate_protocol_version: NegotiateProtocolVersion,
    no_data: NoData,
    notice_response: NoticeResponse,
    notification_response: NotificationResponse,
    parameter_description: ParameterDescription,
    parameter_status: ParameterStatus,
    parse: Parse,
    parse_complete: ParseComplete,
    password_message: PasswordMessage,
    query: Query,
    ready_for_query: ReadyForQuery,
    row_description: RowDescription,
    sasl_initial_response: SASLInitialResponse,
    sasl_response: SASLResponse,
    ssl_request: SSLRequest,
    startup_message: StartupMessage,
    sync: Sync,
    terminate: Terminate,
};

pub const SSLRequest = struct {};

pub const PasswordMessage = struct {
    password: []const u8,
};

pub const NotificationResponse = struct {
    process_id: i32,
    channel_name: []const u8,
    payload: []const u8,
};

pub const NoticeResponse = struct {
    fields: std.AutoHashMap(u8, []const u8),
};

pub const NegotiateProtocolVersion = struct {
    minor_version: i32,
    options: ArrayList([]const u8),
};

pub const GssResponse = struct {
    message: []const u8,
};

pub const GSSENCRequest = struct {};

pub const FunctionCallResponse = struct {
    value: ?[]const u8,
};

pub const FunctionCall = struct {
    object_id: i32,
    arguments: []?[]const u8,
};

pub const Flush = struct {};

pub const EmptyQueryResponse = struct {};

pub const CopyBothResponse = struct {
    format: i8,
    columns: []const i16,
};

pub const CopyOutResponse = struct {
    format: i8,
    columns: []const i16,
};

pub const CopyInResponse = struct {
    format: i8,
    columns: []const i16,
};

pub const CopyFail = struct {
    message: []const u8,
};

pub const CopyDone = struct {};

pub const CopyData = struct {
    data: []const u8,
};

pub const CloseComplete = struct {};

pub const TargetType = union(enum) {
    statement: []const u8,
    portal: []const u8,
};

pub const Close = struct {
    target: TargetType,
};

pub const CancelRequest = struct {
    process_id: i32,
    secret: i32,
};

pub const BackendKeyData = struct {
    process_id: i32,
    secret: i32,
};

pub const Terminate = struct {};

pub const NoData = struct {};

pub const ParameterDescription = struct {
    object_ids: []i32,
};

pub const BindComplete = struct {};

pub const Describe = struct {
    target: TargetType,
};

pub const ParseComplete = struct {};

pub const Sync = struct {};

pub const Bind = struct {
    portal_name: []const u8,
    statement_name: []const u8,
    parameters: []?[]const u8,
};

pub const Parse = struct {
    name: []const u8,
    query: []const u8,
};

pub const ReadyForQuery = struct {};

pub const AuthenticationOk = struct {};

pub const AuthenticationSASL = struct {
    mechanism: Mechanism,
};

pub const AuthenticationSASLContinue = struct {
    nonce: [48]u8,
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

pub const ErrorResponse = struct {
    code: u8,
    response: ?[]const u8 = null,

    pub fn jsonStringify(self: ErrorResponse, writer: anytype) !void {
        try writer.beginObject();

        try writer.objectField("code");
        try writer.write(self.code);

        try writer.objectField("response");
        try writer.write(self.response);

        try writer.endObject();
    }
};

pub const ParameterStatus = struct {
    key: []const u8,
    value: []const u8,
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

// TODO: Rewrite this to use an array and then allocate
// Will probs switch to using a fixedBuffer allocator
// with an arena possibly
pub const RowDescription = struct {
    fields: i16,
    columns: [](ColumnDescription),

    pub fn jsonStringify(self: RowDescription, writer: anytype) !void {
        try writer.beginObject();

        try writer.objectField("fields");
        try writer.write(self.fields);

        try writer.endObject();
    }
};

pub const ColumnDescription = struct {
    field_name: []const u8,
    object_id: i32,
    attribute_id: i16,
    data_type_id: i32,
    data_type_size: i16,
    data_type_modifier: i32,
    format_code: i16,
};

pub const Execute = struct {
    portal: []const u8,
    rows: i32,
};

pub const CommandComplete = struct {
    command: CommandType,
    rows: i32,
    oid: i32,
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
    listen,
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

pub fn read(reader: AnyReader, arena_allocator: *ArenaAllocator) !Message {
    var allocator = arena_allocator.allocator();
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
            const buffer = try allocator.alloc(u8, size_of_buffer);

            _ = try reader.read(buffer);

            // TODO: Parse the error string a bit better has its own formatting
            // Would help with readability
            return Message{
                .error_response = ErrorResponse{
                    .code = code,
                    .response = buffer,
                },
            };
        },
        'S' => {
            const message_len = try reader.readInt(i32, .big);

            // This means it only includes the length
            // I don't think an empty parameter_status will be sent
            if (message_len == 4) {
                return Message{
                    .sync = undefined,
                };
            }

            const buffer = try allocator.alloc(u8, @intCast(message_len - 2));

            _ = try reader.read(buffer);

            var iter_split = std.mem.splitAny(u8, buffer, "\x00");

            const key = iter_split.next() orelse "";
            const value = iter_split.next() orelse "";

            return Message{
                .parameter_status = ParameterStatus{
                    .key = key,
                    .value = value,
                },
            };
        },
        'T' => {
            // TODO: Fix stack variable
            _ = try reader.readInt(i32, .big);
            const fields = try reader.readInt(i16, .big);
            var columns = try allocator.alloc(ColumnDescription, @intCast(fields));

            for (0..@intCast(fields)) |index| {
                // TODO: Correctly copy the field_name, is stack allocated

                var field_name = ArrayList(u8).init(allocator);
                const writer = field_name.writer().any();

                _ = try reader.streamUntilDelimiter(&writer, '\x00', 64);

                const object_id = try reader.readInt(i32, .big);
                const attribute_id = try reader.readInt(i16, .big);
                const data_type_id = try reader.readInt(i32, .big);
                const data_type_size = try reader.readInt(i16, .big);
                const data_type_modifier = try reader.readInt(i32, .big);
                const format_code = try reader.readInt(i16, .big);

                const column = ColumnDescription{
                    .field_name = field_name.items,
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
                    .fields = fields,
                    .columns = columns,
                },
            };
        },
        'Z' => {
            const message_id = try reader.readInt(i32, .big);

            if (message_id != 5) @panic("Expected type id 5");

            _ = try reader.skipBytes(1, .{});

            return Message{
                .ready_for_query = ReadyForQuery{},
            };
        },
        'C' => {
            // TODO: Update to not use readUntilDelimiter
            // TODO: Rewrite kinda shit could be cleaner
            const message_length = try reader.readInt(i32, .big);
            var buffer: [64]u8 = undefined; // TODO: Change to allocation
            var fixed_buffer = fixedBuffer(&buffer);
            var fixed_reader = fixed_buffer.reader().any();

            for (0..@intCast(message_length - 4)) |index| {
                const byte = try reader.readByte();
                buffer[index] = byte;
            }

            if (startsWith(u8, &buffer, "INSERT")) {
                var oid_buffer: [8]u8 = undefined;
                var rows_buffer: [16]u8 = undefined;
                var end_oid_pos: usize = 0;
                var end_row_pos: usize = 0;

                _ = try fixed_reader.skipBytes(7, .{});
                _ = try fixed_reader.readUntilDelimiter(&oid_buffer, ' ');

                for (0..oid_buffer.len - 1) |index| {
                    if (oid_buffer[index] == 170) break;
                    if (oid_buffer[index] == 32) break;
                    if (rows_buffer[index] == 0) break;

                    end_oid_pos += 1;
                }

                _ = try fixed_reader.read(&rows_buffer);

                for (0..rows_buffer.len - 1) |index| {
                    if (rows_buffer[index] == 170) break;
                    if (rows_buffer[index] == 32) break;
                    if (rows_buffer[index] == 0) break;

                    end_row_pos += 1;
                }

                const oid = try std.fmt.parseInt(i32, oid_buffer[0..end_oid_pos], 10);
                const rows = try std.fmt.parseInt(i32, rows_buffer[0..end_row_pos], 10);

                return Message{
                    .command_complete = CommandComplete{
                        .command = .insert,
                        .oid = oid,
                        .rows = rows,
                    },
                };
            }

            if (startsWith(u8, &buffer, "SELECT")) {
                var rows_buffer: [16]u8 = undefined;
                var end_row_pos: usize = 0;

                _ = try fixed_reader.skipBytes(7, .{});
                _ = try fixed_reader.read(&rows_buffer);

                for (0..rows_buffer.len - 1) |index| {
                    if (rows_buffer[index] == 170) break;
                    if (rows_buffer[index] == 32) break;
                    if (rows_buffer[index] == 0) break;

                    end_row_pos += 1;
                }

                const rows = try std.fmt.parseInt(i32, rows_buffer[0..end_row_pos], 10);

                return Message{
                    .command_complete = CommandComplete{
                        .command = .select,
                        .oid = 0,
                        .rows = rows,
                    },
                };
            }

            if (startsWith(u8, &buffer, "UPDATE")) {
                var rows_buffer: [16]u8 = undefined;
                var end_row_pos: usize = 0;

                _ = try fixed_reader.skipBytes(7, .{});
                _ = try fixed_reader.read(&rows_buffer);

                for (0..rows_buffer.len - 1) |index| {
                    if (rows_buffer[index] == 170) break;
                    if (rows_buffer[index] == 32) break;
                    if (rows_buffer[index] == 0) break;

                    end_row_pos += 1;
                }

                const rows = try std.fmt.parseInt(i32, rows_buffer[0..end_row_pos], 10);

                return Message{
                    .command_complete = CommandComplete{
                        .command = .update,
                        .oid = 0,
                        .rows = rows,
                    },
                };
            }

            if (startsWith(u8, &buffer, "DELETE")) {
                var rows_buffer: [16]u8 = undefined;
                var end_row_pos: usize = 0;

                _ = try fixed_reader.skipBytes(7, .{});
                _ = try fixed_reader.read(&rows_buffer);

                for (0..rows_buffer.len - 1) |index| {
                    if (rows_buffer[index] == 170) break;
                    if (rows_buffer[index] == 32) break;
                    if (rows_buffer[index] == 0) break;

                    end_row_pos += 1;
                }

                const rows = try std.fmt.parseInt(i32, rows_buffer[0..end_row_pos], 10);

                return Message{
                    .command_complete = CommandComplete{
                        .command = .delete,
                        .oid = 0,
                        .rows = rows,
                    },
                };
            }

            if (startsWith(u8, &buffer, "LISTEN")) {
                return Message{
                    .command_complete = CommandComplete{
                        .command = .listen,
                        .oid = 0,
                        .rows = 0,
                    },
                };
            }

            if (startsWith(u8, &buffer, "P")) {
                return Message{
                    .close = Close{
                        .target = .{ .portal = try allocator.dupe(u8, buffer[1..@intCast(message_length - 4)]) },
                    },
                };
            }

            if (startsWith(u8, &buffer, "S")) {
                return Message{
                    .close = Close{
                        .target = .{ .statement = try allocator.dupe(u8, buffer[1..@intCast(message_length - 4)]) },
                    },
                };
            }

            @panic("Probably haven't implemented CommandComplete string type: " ++ buffer);
        },
        'D' => {
            const message_len = try reader.readInt(i32, .big);

            const byte = try reader.readByte();

            switch (byte) {
                'S' => {
                    const buffer = try allocator.alloc(u8, @intCast(message_len - 6));
                    var fixed_buffer = fixedBuffer(buffer);
                    const writer = fixed_buffer.writer();

                    _ = try reader.streamUntilDelimiter(writer, '\x00', null);

                    return Message{
                        .describe = Describe{
                            .target = .{ .statement = buffer },
                        },
                    };
                },
                'P' => {
                    const buffer = try allocator.alloc(u8, @intCast(message_len - 6));
                    var fixed_buffer = fixedBuffer(buffer);
                    const writer = fixed_buffer.writer();

                    _ = try reader.streamUntilDelimiter(writer, '\x00', null);

                    return Message{
                        .describe = Describe{
                            .target = .{ .portal = buffer },
                        },
                    };
                },
                else => {
                    var other_col_bytes: [1]u8 = undefined;

                    _ = try reader.read(&other_col_bytes);

                    const columns_count: [2]u8 = .{byte} ++ other_col_bytes;
                    const columns: i16 = std.mem.readInt(i16, &columns_count, .big);

                    return Message{
                        .data_row = DataRow.NoContextDataRow{
                            .length = message_len,
                            .columns = columns,
                            .reader = reader,
                        },
                    };
                },
            }
        },
        '1' => {
            try reader.skipBytes(4, .{}); // Skip contents

            return Message{
                .parse_complete = ParseComplete{},
            };
        },
        '2' => {
            try reader.skipBytes(4, .{});

            return Message{
                .bind_complete = BindComplete{},
            };
        },
        '3' => {
            try reader.skipBytes(4, .{});

            return Message{
                .close_complete = CloseComplete{},
            };
        },
        't' => {
            _ = try reader.readInt(i32, .big);
            const parameter_count = try reader.readInt(i16, .big);
            const object_ids = try allocator.alloc(i32, @intCast(parameter_count));

            for (0..@intCast(parameter_count)) |index| {
                object_ids[index] = try reader.readInt(i32, .big);
            }

            return Message{
                .parameter_description = ParameterDescription{
                    .object_ids = object_ids,
                },
            };
        },
        'n' => {
            try reader.skipBytes(4, .{});

            return Message{
                .no_data = NoData{},
            };
        },
        'X' => {
            _ = try reader.skipBytes(4, .{});

            return Message{
                .terminate = Terminate{},
            };
        },
        'K' => {
            try reader.skipBytes(4, .{});

            const process_id = try reader.readInt(i32, .big);
            const secret = try reader.readInt(i32, .big);

            return Message{
                .backend_key_data = BackendKeyData{
                    .process_id = process_id,
                    .secret = secret,
                },
            };
        },
        'B' => {
            const message_len = try reader.readInt(i32, .big);
            var buffer = try allocator.alloc(u8, @intCast(message_len));

            var fixed_buffer = fixedBuffer(buffer);
            const writer = fixed_buffer.writer();

            _ = try reader.streamUntilDelimiter(writer, '\x00', null);

            const portal_name_end = fixed_buffer.pos;

            _ = try reader.streamUntilDelimiter(writer, '\x00', null);

            const statement_name_end = fixed_buffer.pos;
            const number_of_parameter_codes = try reader.readInt(i16, .big);

            for (0..@intCast(number_of_parameter_codes)) |_| {
                _ = try reader.skipBytes(2, .{});
            }

            const number_of_parameters = try reader.readInt(i16, .big);
            var parameters = ArrayList(?[]const u8).init(allocator);

            for (0..@intCast(number_of_parameters)) |_| {
                const size_of = try reader.readInt(i32, .big);

                if (size_of == -1) {
                    try parameters.append(null);
                } else {
                    const parameter_buffer = try allocator.alloc(u8, @intCast(size_of));

                    _ = try reader.readAtLeast(parameter_buffer, @intCast(size_of));

                    try parameters.append(parameter_buffer);
                }
            }

            const number_of_parameter_format_codes = try reader.readInt(i16, .big);

            for (0..@intCast(number_of_parameter_format_codes)) |_| {
                try reader.skipBytes(2, .{});
            }

            return Message{
                .bind = Bind{
                    .parameters = parameters.items,
                    .portal_name = buffer[0..portal_name_end],
                    .statement_name = buffer[portal_name_end..statement_name_end],
                },
            };
        },
        'd' => {
            const message_len = try reader.readInt(i32, .big);
            const data = try allocator.alloc(u8, @intCast(message_len - 4));

            _ = try reader.readAtLeast(data, @intCast(message_len - 4));

            return Message{
                .copy_data = CopyData{
                    .data = data,
                },
            };
        },
        'c' => {
            try reader.skipBytes(4, .{});

            return Message{
                .copy_done = CopyDone{},
            };
        },
        'f' => {
            const message_len = try reader.readInt(i32, .big);
            const message = try allocator.alloc(u8, @intCast(message_len - 4));

            _ = try reader.readAtLeast(message, @intCast(message_len - 4));

            return Message{
                .copy_fail = CopyFail{
                    .message = message,
                },
            };
        },
        'F' => {
            _ = try reader.readInt(i32, .big);
            const object_id = try reader.readInt(i32, .big);
            const number_of_format_codes = try reader.readInt(i16, .big);
            const format_codes = try allocator.alloc(i16, @intCast(number_of_format_codes));

            for (0..@intCast(number_of_format_codes)) |index| {
                format_codes[index] = try reader.readInt(i16, .big);
            }

            const number_of_arguments = try reader.readInt(i16, .big);
            var arguments = ArrayList(?[]const u8).init(allocator);

            for (0..@intCast(number_of_arguments)) |_| {
                const size_of = try reader.readInt(i32, .big);

                if (size_of == -1) {
                    try arguments.append(null);
                } else {
                    const parameter_buffer = try allocator.alloc(u8, @intCast(size_of));

                    _ = try reader.readAtLeast(parameter_buffer, @intCast(size_of));

                    try arguments.append(parameter_buffer);
                }
            }

            _ = try reader.readInt(i16, .big);

            return Message{
                .function_call = FunctionCall{
                    .arguments = try allocator.dupe(?[]const u8, arguments.items),
                    .object_id = object_id,
                },
            };
        },
        'G' => {
            _ = try reader.skipBytes(4, .{});

            const format = try reader.readInt(i8, .big);
            const number_of_cols = try reader.readInt(i16, .big);
            const cols = try allocator.alloc(i16, @intCast(number_of_cols));

            for (0..@intCast(number_of_cols)) |index| {
                cols[index] = try reader.readInt(i16, .big);
            }

            return Message{
                .copy_in_response = CopyInResponse{
                    .columns = cols,
                    .format = format,
                },
            };
        },
        'H' => {
            const message_len = try reader.readInt(i32, .big);

            if (message_len == 4) return Message{ .flush = Flush{} };

            const format = try reader.readInt(i8, .big);
            const number_of_cols = try reader.readInt(i16, .big);
            const cols = try allocator.alloc(i16, @intCast(number_of_cols));

            for (0..@intCast(number_of_cols)) |index| {
                cols[index] = try reader.readInt(i16, .big);
            }

            return Message{
                .copy_out_response = CopyOutResponse{
                    .columns = cols,
                    .format = format,
                },
            };
        },
        'W' => {
            _ = try reader.skipBytes(4, .{});

            const format = try reader.readInt(i8, .big);
            const number_of_cols = try reader.readInt(i16, .big);
            const cols = try allocator.alloc(i16, @intCast(number_of_cols));

            for (0..@intCast(number_of_cols)) |index| {
                cols[index] = try reader.readInt(i16, .big);
            }

            return Message{
                .copy_both_response = CopyBothResponse{
                    .columns = cols,
                    .format = format,
                },
            };
        },
        'I' => {
            _ = try reader.skipBytes(4, .{});

            return Message{
                .empty_query_response = EmptyQueryResponse{},
            };
        },
        'V' => {
            try reader.skipBytes(4, .{});

            const value_len = try reader.readInt(i32, .big);

            if (value_len == -1) {
                return Message{
                    .function_call_response = FunctionCallResponse{
                        .value = null,
                    },
                };
            } else {
                const value: []u8 = try allocator.alloc(u8, @intCast(value_len));
                _ = try reader.readAtLeast(value, @intCast(value_len));

                return Message{
                    .function_call_response = FunctionCallResponse{
                        .value = value,
                    },
                };
            }
        },
        'p' => {
            const message_len = try reader.readInt(i32, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_len - 4));

            _ = try reader.read(buffer);

            return Message{
                .gss_response = GssResponse{
                    .message = buffer,
                },
            };
        },
        'v' => {
            const message_len = try reader.readInt(i32, .big);
            const minior_version = try reader.readInt(i32, .big);

            _ = try reader.readInt(i32, .big);

            var options = ArrayList([]const u8).init(allocator);

            const buffer = try allocator.alloc(u8, @intCast(message_len - 12));

            _ = try reader.read(buffer);

            var split_iterator = std.mem.splitAny(u8, buffer, "\x00");

            while (split_iterator.next()) |value| {
                if (!eql(u8, "", value)) try options.append(value);
            }

            return Message{
                .negotiate_protocol_version = NegotiateProtocolVersion{
                    .minor_version = minior_version,
                    .options = options,
                },
            };
        },
        'N' => {
            const message_len = try reader.readInt(i32, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_len - 4));

            _ = try reader.read(buffer);

            var fixed_buffer = fixedBuffer(buffer);
            const buffer_reader = fixed_buffer.reader().any();
            var fields = std.AutoHashMap(u8, []const u8).init(allocator);

            while (fixed_buffer.pos != fixed_buffer.buffer.len) {
                const key = try buffer_reader.readByte();

                if (key == 0) {
                    try fields.put(key, "");
                } else {
                    var arraylist = ArrayList(u8).init(allocator);

                    _ = try buffer_reader.streamUntilDelimiter(arraylist.writer(), '\x00', null);

                    try fields.put(key, try arraylist.toOwnedSlice());
                }
            }

            return Message{
                .notice_response = NoticeResponse{
                    .fields = fields,
                },
            };
        },
        'A' => {
            const message_len = try reader.readInt(i32, .big);
            const process_id = try reader.readInt(i32, .big);

            const buffer = try allocator.alloc(u8, @intCast(message_len - 4));

            _ = try reader.read(buffer);

            var split_iter = std.mem.splitAny(u8, buffer, "\x00");

            const channel_name = split_iter.next() orelse "";
            const payload = split_iter.next() orelse "";

            return Message{
                .notification_response = NotificationResponse{
                    .channel_name = channel_name,
                    .payload = payload,
                    .process_id = process_id,
                },
            };
        },
        'P' => {
            const message_len = try reader.readInt(i32, .big);

            const buffer = try allocator.alloc(u8, @intCast(message_len));
            var fixed_buffer = fixedBuffer(buffer);
            const writer = fixed_buffer.writer().any();

            try reader.streamUntilDelimiter(writer, '\x00', null);

            const name = buffer[0..fixed_buffer.pos];
            const end_name_pos = fixed_buffer.pos;

            try reader.streamUntilDelimiter(writer, '\x00', null);

            const query = buffer[end_name_pos..fixed_buffer.pos];

            const number_of_params = try reader.readInt(i16, .big);

            for (0..@intCast(number_of_params)) |_| {
                try reader.skipBytes(4, .{});
            }

            return Message{
                .parse = Parse{
                    .name = name,
                    .query = query,
                },
            };
        },
        'Q' => {
            const message_len = try reader.readInt(i32, .big);
            const statement = try allocator.alloc(u8, @intCast(message_len - 5));

            _ = try reader.read(statement);

            try reader.skipBytes(1, .{});

            return Message{
                .query = Query{
                    .statement = statement,
                },
            };
        },
        else => {
            // Otherwise it is the message length
            var other_len_bytes: [3]u8 = undefined;

            _ = try reader.read(&other_len_bytes);

            const message_len_str: [4]u8 = .{message_type} ++ other_len_bytes;

            const message_len = std.mem.readInt(i32, &message_len_str, .big);
            const message_sub_type = try reader.readInt(i32, .big);

            switch (message_sub_type) {
                // Startup
                196608 => {
                    const buffer = try allocator.alloc(u8, @intCast(message_len));

                    _ = try reader.read(buffer);

                    var split_iter = std.mem.splitAny(u8, buffer, "\x00");
                    var options = StringHashMap.init(allocator);

                    while (split_iter.next()) |key| {
                        const value = split_iter.next() orelse "";
                        try options.put(key, value);
                    }

                    const application_name = options.get("application_name") orelse "";
                    const database = options.get("database") orelse "";
                    const user = options.get("user") orelse "";

                    return Message{
                        .startup_message = StartupMessage{
                            .application_name = application_name,
                            .database = database,
                            .user = user,
                        },
                    };
                },
                // CancelRequest
                80877102 => {
                    const process_id = try reader.readInt(i32, .big);
                    const secret = try reader.readInt(i32, .big);

                    return Message{
                        .cancel_request = CancelRequest{
                            .process_id = process_id,
                            .secret = secret,
                        },
                    };
                },
                // GSSENCRequest
                80877104 => {
                    return Message{
                        .gssenc_request = GSSENCRequest{},
                    };
                },
                //SSLRequest
                80877103 => {
                    return Message{
                        .ssl_request = SSLRequest{},
                    };
                },
                else => @panic("Unexpected message type"),
            }

            @panic("Unexpected message type, recieved: " ++ .{message_type});
        },
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
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(mechanism);
            try writer.writeByte(0);
            try writer.writeInt(i32, @intCast(sasl_initial_response.client_message.len), .big);
            _ = try writer.write(&sasl_initial_response.client_message);
        },
        .query => |query| {
            const payload_len = query.statement.len + 5; // 4 bytes for the len

            try writer.writeByte('Q');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(query.statement);
            try writer.writeByte(0);
        },
        .execute => |execute| {
            const payload_len = 9 + execute.portal.len;

            try writer.writeByte('E');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(execute.portal);
            try writer.writeByte(0);
            try writer.writeInt(i32, execute.rows, .big);
        },
        .parse => |parse| {
            const payload_len = 4 + parse.name.len + 1 + parse.query.len + 1 + 2;

            try writer.writeByte('P');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(parse.name);
            try writer.writeByte(0);
            _ = try writer.write(parse.query);
            try writer.writeByte(0);
            try writer.writeInt(u16, 0, .big);
        },
        .bind => |bind| {
            var payload_len = 14 + bind.portal_name.len + bind.statement_name.len;

            for (bind.parameters) |param| {
                if (param) |value| {
                    payload_len += 4 + value.len;
                } else {
                    payload_len += 4;
                }
            }

            try writer.writeByte('B');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(bind.portal_name);
            try writer.writeByte(0);
            _ = try writer.write(bind.statement_name);
            try writer.writeByte(0);
            try writer.writeInt(i16, 0, .big); // Number of parameter format codes
            try writer.writeInt(i16, @intCast(bind.parameters.len), .big); // Number of parameter format codes

            // For each param write
            for (bind.parameters) |param| {
                // Deal with null we write -1
                if (param) |value| {
                    try writer.writeInt(i32, @intCast(value.len), .big);
                    _ = try writer.write(value);
                } else {
                    try writer.writeInt(i32, -1, .big);
                }
            }

            try writer.writeInt(i16, 1, .big);
            try writer.writeInt(i16, 0, .big);
        },
        .sync => {
            try writer.writeByte('S');
            try writer.writeInt(i32, 4, .big);
        },
        .describe => |describe| {
            const payload_len = 6 + switch (describe.target) {
                .portal => |portal| portal.len,
                .statement => |statement| statement.len,
            };

            try writer.writeByte('D');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            switch (describe.target) {
                .portal => |portal| {
                    try writer.writeByte('P');
                    _ = try writer.write(portal);
                },
                .statement => |statement| {
                    try writer.writeByte('S');
                    _ = try writer.write(statement);
                },
            }

            try writer.writeByte(0);
        },
        .terminate => {
            try writer.writeByte('X');
            try writer.writeInt(i32, 4, .big);
        },
        .authentication_ok => {
            try writer.writeByte('R');
            try writer.writeInt(i32, 8, .big);
            try writer.writeInt(i32, 0, .big);
        },
        .backend_key_data => |backend_key_data| {
            const payload_len: i32 = 12;

            try writer.writeByte('K');
            try writer.writeInt(i32, payload_len, .big);
            try writer.writeInt(i32, backend_key_data.process_id, .big);
            try writer.writeInt(i32, backend_key_data.secret, .big);
        },
        .cancel_request => |cancel_request| {
            try writer.writeInt(i32, 16, .big);
            try writer.writeInt(i32, 80877102, .big);
            try writer.writeInt(i32, cancel_request.process_id, .big);
            try writer.writeInt(i32, cancel_request.secret, .big);
        },
        .close => |close| {
            const payload_len = 5 + switch (close.target) {
                .portal => |portal| portal.len,
                .statement => |statement| statement.len,
            };

            try writer.writeByte('C');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            switch (close.target) {
                .portal => |portal| {
                    try writer.writeByte('P');
                    _ = try writer.write(portal);
                },
                .statement => |statement| {
                    try writer.writeByte('S');
                    _ = try writer.write(statement);
                },
            }

            try writer.writeByte('\x00');
        },
        .close_complete => {
            try writer.writeByte('3');
            try writer.writeInt(i32, 4, .big);
        },
        .copy_data => |copy_data| {
            const payload_len = copy_data.data.len + 4;

            try writer.writeByte('d');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(copy_data.data);
        },
        .copy_done => {
            try writer.writeByte('c');
            try writer.writeInt(i32, 4, .big);
        },
        .copy_fail => |copy_fail| {
            const payload_len = 4 + copy_fail.message.len;

            try writer.writeByte('f');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(copy_fail.message);
        },
        .copy_in_response => |copy_in_response| {
            const payload_len = 7 + copy_in_response.columns.len * 2;

            try writer.writeByte('G');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i8, copy_in_response.format, .big);
            try writer.writeInt(i16, @intCast(copy_in_response.columns.len), .big);

            for (copy_in_response.columns) |item| {
                try writer.writeInt(i16, item, .big);
            }
        },
        .copy_out_response => |copy_out_response| {
            const payload_len = 7 + copy_out_response.columns.len * 2;

            try writer.writeByte('H');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i8, copy_out_response.format, .big);
            try writer.writeInt(i16, @intCast(copy_out_response.columns.len), .big);

            for (copy_out_response.columns) |item| {
                try writer.writeInt(i16, item, .big);
            }
        },
        .copy_both_response => |copy_both_response| {
            const payload_len = 7 + copy_both_response.columns.len * 2;

            try writer.writeByte('W');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i8, copy_both_response.format, .big);
            try writer.writeInt(i16, @intCast(copy_both_response.columns.len), .big);

            for (copy_both_response.columns) |item| {
                try writer.writeInt(i16, item, .big);
            }
        },
        .empty_query_response => {
            try writer.writeByte('I');
            try writer.writeInt(i32, 4, .big);
        },
        .error_response => |error_response| {
            const payload_len = 5 + if (error_response.response) |response| response.len else 0;

            try writer.writeByte('E');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeByte(error_response.code);
            _ = try writer.write(error_response.response orelse "");
            try writer.writeByte(0);
        },
        .flush => {
            try writer.writeByte('H');
            try writer.writeInt(i32, 4, .big);
        },
        .function_call => |function_call| {
            var payload_len: usize = 14;

            for (function_call.arguments) |param| {
                payload_len += 4;
                payload_len += if (param) |value| value.len else 1;
            }

            try writer.writeByte('F');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i32, function_call.object_id, .big);
            try writer.writeInt(i16, 0, .big);

            try writer.writeInt(i16, @intCast(function_call.arguments.len), .big);

            for (function_call.arguments) |param| {
                // Deal with null we write -1
                if (param) |value| {
                    try writer.writeInt(i32, @intCast(value.len), .big);
                    _ = try writer.write(value);
                } else {
                    try writer.writeInt(i32, -1, .big);
                }
            }

            try writer.writeInt(i16, 0, .big);
        },
        .function_call_response => |function_call_response| {
            const payload_len = 8 + if (function_call_response.value) |value| value.len else 0;

            try writer.writeByte('V');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            if (function_call_response.value) |value| {
                try writer.writeInt(i32, @intCast(value.len), .big);
                _ = try writer.write(value);
            } else {
                try writer.writeInt(i32, -1, .big);
            }
        },
        .gssenc_request => {
            try writer.writeInt(i32, 8, .big);
            try writer.writeInt(i32, 80877104, .big);
        },
        .gss_response => |gss_response| {
            const payload_len: usize = 4 + gss_response.message.len;

            try writer.writeByte('p');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(gss_response.message);
        },
        .negotiate_protocol_version => |npv| {
            var payload_len: usize = 12;

            for (npv.options.items) |option| {
                payload_len += option.len + 1;
            }

            try writer.writeByte('v');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i32, npv.minor_version, .big);
            try writer.writeInt(i32, @intCast(npv.options.items.len), .big);

            for (npv.options.items) |option| {
                _ = try writer.write(option);
                try writer.writeByte(0);
            }
        },
        .no_data => {
            try writer.writeByte('n');
            try writer.writeInt(i32, 4, .big);
        },
        .notice_response => |notice_response| {
            var payload_len: usize = 4;

            var notice_iterator = notice_response.fields.iterator();

            while (notice_iterator.next()) |item| {
                if (item.key_ptr.* == 0) {
                    payload_len += 1; // Just the byte gets added
                } else {
                    payload_len += 2 + item.value_ptr.len;
                }
            }

            try writer.writeByte('N');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            notice_iterator = notice_response.fields.iterator();

            while (notice_iterator.next()) |item| {
                if (item.key_ptr.* == 0) {
                    try writer.writeByte(item.key_ptr.*);
                } else {
                    try writer.writeByte(item.key_ptr.*);
                    _ = try writer.write(item.value_ptr.*);
                    try writer.writeByte(0);
                }
            }
        },
        .notification_response => |notification_response| {
            const payload_len = 10 + notification_response.payload.len + notification_response.payload.len;

            try writer.writeByte('A');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i32, notification_response.process_id, .big);
            _ = try writer.write(notification_response.channel_name);
            try writer.writeByte(0);
            _ = try writer.write(notification_response.payload);
            try writer.writeByte(0);
        },
        .parameter_description => |parameter_description| {
            const payload_len: i32 = 10;

            try writer.writeByte('t');
            try writer.writeInt(i32, payload_len, .big);
            try writer.writeInt(i16, @intCast(parameter_description.object_ids.len), .big);

            for (parameter_description.object_ids) |object_id| {
                try writer.writeInt(i32, object_id, .big);
            }
        },
        .parameter_status => |parameter_status| {
            const payload_len = 4 + parameter_status.key.len + parameter_status.value.len;

            try writer.writeByte('S');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(parameter_status.key);
            try writer.writeByte(0);
            _ = try writer.write(parameter_status.value);
            try writer.writeByte(0);
        },
        .parse_complete => {
            try writer.writeByte('1');
            try writer.writeInt(i32, 4, .big);
        },
        .password_message => |password_message| {
            const payload_len = 5 + password_message.password.len;

            try writer.writeByte('p');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(password_message.password);
            try writer.writeByte(0);
        },
        .ready_for_query => {
            try writer.writeByte('Z');
            try writer.writeInt(i32, 5, .big);
            try writer.writeByte('I');
        },
        .row_description => |row_description| {
            var payload_len: usize = 6;

            for (row_description.columns) |column| {
                payload_len += 18 + column.field_name.len;
            }

            try writer.writeByte('T');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i16, @intCast(row_description.columns.len), .big);

            for (row_description.columns) |column| {
                _ = try writer.write(column.field_name);
                try writer.writeInt(i32, column.object_id, .big);
                try writer.writeInt(i16, column.attribute_id, .big);
                try writer.writeInt(i32, column.data_type_id, .big);
                try writer.writeInt(i16, column.data_type_size, .big);
                try writer.writeInt(i32, column.data_type_modifier, .big);
                try writer.writeInt(i16, column.format_code, .big);
            }
        },
        .ssl_request => {
            try writer.writeInt(i32, 8, .big);
            try writer.writeInt(i32, 80877103, .big);
        },
        else => @panic("Either not implemented or not valid"),
    }
}

test "read write authentication_ok" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .authentication_ok = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .authentication_ok => try std.testing.expect(std.meta.eql(message_out, message)),
        else => try std.testing.expect(false),
    }
}

test "read write terminate" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .terminate = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .terminate => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write sync" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .sync = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .sync => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write startup" {
    var buffer: [128]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_startup = StartupMessage{
        .application_name = "test_app",
        .database = "test_database",
        .user = "test_user",
    };

    const message = Message{ .startup_message = expected_startup };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .startup_message => |actual_startup| {
            try expect(eql(u8, actual_startup.application_name, expected_startup.application_name));
            try expect(eql(u8, actual_startup.database, expected_startup.database));
            try expect(eql(u8, actual_startup.user, expected_startup.user));
        },
        else => try expect(false),
    }
}

test "read write backend_key_data" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .backend_key_data = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .backend_key_data => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write bind" {
    var buffer: [256]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    var parameters = [_]?[]const u8{
        "hello", // A valid string slice
        null, // An empty optional, represented by null
        "world", // Another valid string slice
        null, // Another empty optional
        "zig", // Another valid string slice
    };

    const expected_bind = Bind{
        .parameters = &parameters,
        .portal_name = "portal_name",
        .statement_name = "statement_name",
    };

    const message = Message{ .bind = expected_bind };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .bind => |actual_bind| {
            try expect(eql(u8, actual_bind.portal_name, expected_bind.portal_name));
            try expect(eql(u8, actual_bind.statement_name, expected_bind.statement_name));
            try expect(actual_bind.parameters.len == expected_bind.parameters.len);
        },
        else => try expect(false),
    }
}

test "read write cancel_request" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_cancel_request = CancelRequest{
        .process_id = 10,
        .secret = 7,
    };

    const message = Message{
        .cancel_request = expected_cancel_request,
    };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .cancel_request => |actual_cancel_request| {
            try expect(actual_cancel_request.process_id == expected_cancel_request.process_id);
            try expect(actual_cancel_request.secret == expected_cancel_request.secret);
        },
        else => try expect(false),
    }
}

test "read write close (target = portal)" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_close = Close{
        .target = .{
            .portal = "portal",
        },
    };

    const message = Message{ .close = expected_close };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .close => |actual_close| {
            try expect(eql(u8, actual_close.target.portal, expected_close.target.portal));
        },
        else => try expect(false),
    }
}

test "read write close (target = statement)" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_close = Close{
        .target = .{
            .statement = "statement",
        },
    };

    const message = Message{ .close = expected_close };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .close => |actual_close| {
            try expect(eql(u8, actual_close.target.statement, expected_close.target.statement));
        },
        else => try expect(false),
    }
}

test "read write close_complete" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .close_complete = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .close_complete => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write copy_data" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_copy_data = CopyData{
        .data = "Hello World !",
    };

    const message = Message{ .copy_data = expected_copy_data };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .copy_data => |actual_copy_data| {
            try expect(eql(u8, actual_copy_data.data, expected_copy_data.data));
        },
        else => try expect(false),
    }
}

test "read write copy_done" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .copy_done = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .copy_done => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write copy_fail" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_copy_fail = CopyFail{
        .message = "Failed copy !\x00",
    };

    const message = Message{ .copy_fail = expected_copy_fail };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .copy_fail => |actual_copy_fail| {
            try expect(eql(u8, actual_copy_fail.message, expected_copy_fail.message));
        },
        else => try expect(false),
    }
}

test "read write copy_in_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_copy_in_response = CopyInResponse{
        .columns = &.{ 1, 2, 3, 4, 5 },
        .format = 0,
    };

    const message = Message{
        .copy_in_response = expected_copy_in_response,
    };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .copy_in_response => |actual_copy_in_response| {
            try expect(expected_copy_in_response.format == actual_copy_in_response.format);
            try expect(expected_copy_in_response.columns.len == actual_copy_in_response.columns.len);
        },
        else => try expect(false),
    }
}

test "read write copy_out_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_copy_out_response = CopyOutResponse{
        .columns = &.{ 1, 2, 3, 4, 5 },
        .format = 0,
    };

    const message = Message{
        .copy_out_response = expected_copy_out_response,
    };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .copy_out_response => |actual_copy_out_response| {
            try expect(expected_copy_out_response.format == actual_copy_out_response.format);
            try expect(expected_copy_out_response.columns.len == actual_copy_out_response.columns.len);
        },
        else => try expect(false),
    }
}

test "read write copy_both_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_copy_both_response = CopyBothResponse{
        .columns = &.{ 1, 2, 3, 4, 5 },
        .format = 0,
    };

    const message = Message{
        .copy_both_response = expected_copy_both_response,
    };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .copy_both_response => |actual_copy_both_response| {
            try expect(expected_copy_both_response.format == actual_copy_both_response.format);
            try expect(expected_copy_both_response.columns.len == actual_copy_both_response.columns.len);
        },
        else => try expect(false),
    }
}

test "read write describe (target = portal)" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_describe = Describe{
        .target = .{
            .portal = "portal",
        },
    };

    const message = Message{ .describe = expected_describe };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .describe => |actual_describe| {
            try expect(eql(u8, actual_describe.target.portal, expected_describe.target.portal));
        },
        else => try expect(false),
    }
}

test "read write describe (target = statement)" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_describe = Describe{
        .target = .{
            .statement = "statement",
        },
    };

    const message = Message{ .describe = expected_describe };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .describe => |actual_describe| {
            try expect(eql(u8, actual_describe.target.statement, expected_describe.target.statement));
        },
        else => try expect(false),
    }
}

test "read write empty_query_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .empty_query_response = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .empty_query_response => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write error_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_error_response = ErrorResponse{
        .code = 7,
        .response = "error response !",
    };

    const message = Message{ .error_response = expected_error_response };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .error_response => |actual_error_response| {
            try expect(actual_error_response.code == expected_error_response.code);
            try expect(eql(u8, actual_error_response.response.?, expected_error_response.response.?));
        },
        else => try expect(false),
    }
}

test "read write execute" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const expected_execute = Execute{
        .portal = "portal",
        .rows = 10,
    };

    const message = Message{ .execute = expected_execute };

    try write(message, writer);

    fixed_buffer.reset();

    const message_type = try reader.readByte();

    try expect(message_type == 'E');

    const message_len = try reader.readInt(i32, .big);

    const portal = try allocator.alloc(u8, @intCast(message_len - 9));

    var portal_buffer = fixedBuffer(portal);
    const portal_writer = portal_buffer.writer();

    _ = try reader.streamUntilDelimiter(portal_writer, '\x00', null);

    const rows = try reader.readInt(i32, .big);

    try expect(eql(u8, portal, expected_execute.portal));
    try expect(rows == expected_execute.rows);
}

test "read write flush" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .flush = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .flush => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write function_call" {
    var buffer: [128]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    var parameters = [_]?[]const u8{
        "hello", // A valid string slice
        null, // An empty optional, represented by null
        "world", // Another valid string slice
        null, // Another empty optional
        "zig", // Another valid string slice
    };

    const expected_function_call = FunctionCall{
        .arguments = &parameters,
        .object_id = 10,
    };

    const message = Message{ .function_call = expected_function_call };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .function_call => |actual_function_call| {
            try expect(actual_function_call.arguments.len == expected_function_call.arguments.len);
            try expect(actual_function_call.object_id == expected_function_call.object_id);
        },
        else => try expect(false),
    }
}

test "read write function_call_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expect_function_call_response = FunctionCallResponse{
        .value = "expected_value",
    };

    const message = Message{ .function_call_response = expect_function_call_response };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .function_call_response => |actual_call_response| {
            try expect(eql(u8, expect_function_call_response.value.?, actual_call_response.value.?));
        },
        else => try expect(false),
    }
}

test "read write gssenc_request" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .gssenc_request = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .gssenc_request => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write gss_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_gss_response = GssResponse{
        .message = "Hello World !",
    };

    const message = Message{ .gss_response = expected_gss_response };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .gss_response => |actual_gss_response| {
            try expect(eql(u8, expected_gss_response.message, actual_gss_response.message));
        },
        else => try expect(false),
    }
}
test "read write negotiate_protocol_version" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var options = ArrayList([]const u8).init(allocator);

    _ = try options.append("hello");
    _ = try options.append("world");

    const expected_npv = NegotiateProtocolVersion{
        .minor_version = 101,
        .options = options,
    };

    const message = Message{ .negotiate_protocol_version = expected_npv };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .negotiate_protocol_version => |actual_npv| {
            try expect(actual_npv.minor_version == expected_npv.minor_version);
            try expect(actual_npv.options.items.len == expected_npv.options.items.len);
        },
        else => try expect(false),
    }
}

test "read write no_data" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .no_data = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .no_data => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write notice_response" {
    var buffer: [48]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var fields = std.AutoHashMap(u8, []const u8).init(allocator);

    try fields.put(0, ""); // Keys with 0 should be treated specially
    try fields.put(1, "Hello");
    try fields.put(2, "Worlds");

    const expected_notice_response = NoticeResponse{
        .fields = fields,
    };

    const message = Message{ .notice_response = expected_notice_response };

    try write(message, writer);

    fixed_buffer.reset();

    var message_out = try read(reader, &arena);

    switch (message_out) {
        .notice_response => |*actual_notice_response| {
            try expect(actual_notice_response.fields.count() == expected_notice_response.fields.count());
            try expect(eql(u8, actual_notice_response.fields.get(0).?, expected_notice_response.fields.get(0).?));
            try expect(eql(u8, actual_notice_response.fields.get(1).?, expected_notice_response.fields.get(1).?));
            try expect(eql(u8, actual_notice_response.fields.get(2).?, expected_notice_response.fields.get(2).?));
        },
        else => try expect(false),
    }
}

test "read write notification_response" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_notification_response = NotificationResponse{
        .channel_name = "channel_name",
        .payload = "payload",
        .process_id = 10,
    };

    const message = Message{ .notification_response = expected_notification_response };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .notification_response => |actual_notification_response| {
            try expect(eql(u8, actual_notification_response.channel_name, expected_notification_response.channel_name));
            try expect(eql(u8, actual_notification_response.payload, expected_notification_response.payload));
            try expect(actual_notification_response.process_id == expected_notification_response.process_id);
        },
        else => try expect(false),
    }
}

test "read write parameter_description" {
    var buffer: [128]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    var object_ids = [_]i32{ 1, 2, 3, 4, 5, 6, 7 };

    const expected_parameter_description = ParameterDescription{
        .object_ids = &object_ids,
    };

    const message = Message{ .parameter_description = expected_parameter_description };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .parameter_description => |actual_parameter_description| {
            try expect(eql(i32, actual_parameter_description.object_ids, expected_parameter_description.object_ids));
        },
        else => try expect(false),
    }
}

test "read write parameter_status" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_paramter_status = ParameterStatus{
        .key = "key",
        .value = "value",
    };

    const message = Message{ .parameter_status = expected_paramter_status };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .parameter_status => |actual_parameter_status| {
            try expect(eql(u8, actual_parameter_status.key, expected_paramter_status.key));
            try expect(eql(u8, actual_parameter_status.value, expected_paramter_status.value));
        },
        else => try expect(false),
    }
}

test "read write parse" {
    var buffer: [128]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_parse = Parse{
        .name = "name",
        .query = "SELECT * FROM fake_table",
    };

    const message = Message{ .parse = expected_parse };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .parse => |actual_parse| {
            try expect(eql(u8, actual_parse.name, expected_parse.name));
            try expect(eql(u8, actual_parse.query, expected_parse.query));
        },
        else => try expect(false),
    }
}

test "read write parse_complete" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .parse_complete = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .parse_complete => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}

test "read write password_message" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const expected_password_message = PasswordMessage{
        .password = "password",
    };

    const message = Message{ .password_message = expected_password_message };

    try write(message, writer);

    fixed_buffer.reset();

    const message_type = try reader.readByte();

    try expect(message_type == 'p');

    const message_len = try reader.readInt(i32, .big);

    const password = try allocator.alloc(u8, @intCast(message_len - 5));

    _ = try reader.read(password);

    try expect(eql(u8, password, expected_password_message.password));

    const null_byte = try reader.readByte();

    try expect(null_byte == 0);
}

test "read write query" {
    var buffer: [128]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_query = Query{ .statement = "SELECT * FROM magic_table" };

    const message = Message{ .query = expected_query };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .query => |actual_query| {
            try expect(eql(u8, actual_query.statement, expected_query.statement));
        },
        else => try expect(false),
    }
}

test "read write ready_for_query" {
    var buffer: [256]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    var columns = [_]ColumnDescription{
        ColumnDescription{
            .attribute_id = 0,
            .data_type_id = 1,
            .data_type_modifier = 2,
            .data_type_size = 3,
            .field_name = "field_name",
            .format_code = 1,
            .object_id = 10,
        },
    };

    const expected_row_description = RowDescription{
        .columns = &columns,
        .fields = 3,
    };

    const message = Message{ .row_description = expected_row_description };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .row_description => |actual_row_description| {
            try expect(actual_row_description.columns.len == expected_row_description.columns.len);

            for (actual_row_description.columns, 0..) |actual_column, index| {
                const expected_col = expected_row_description.columns[index];

                try expect(eql(u8, actual_column.field_name, expected_col.field_name));
            }
        },
        else => try expect(false),
    }
}

test "read write sasl_initial_response" {
    var buffer: [128]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const expected_inital_response = try SASLInitialResponse.init(.scram_sha_256);

    const message = Message{ .sasl_initial_response = expected_inital_response };

    try write(message, writer);

    fixed_buffer.reset();

    const message_type = try reader.readByte();

    try expect(message_type == 'p');

    _ = try reader.readInt(i32, .big);

    var mechanism: [13]u8 = undefined;

    _ = try reader.read(&mechanism);

    try expect(Mechanism.from_string(&mechanism) == .scram_sha_256);

    try reader.skipBytes(1, .{});

    const len_of_sasl = try reader.readInt(i32, .big);

    const client_message = try allocator.alloc(u8, @intCast(len_of_sasl));

    _ = try reader.read(client_message);

    try expect(eql(u8, client_message, &expected_inital_response.client_message));
}

test "read write sasl_response" {
    var buffer: [128]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const expected_response = SASLResponse{
        .nonce = .{ 78, 105, 115, 98, 71, 117, 101, 76, 73, 97, 88, 121, 90, 112, 122, 66, 56, 106, 65, 107, 85, 74, 102, 74, 83, 79, 75, 67, 100, 100, 88, 50, 75, 68, 97, 106, 68, 70, 102, 83, 102, 67, 70, 55, 122, 111, 74, 113 },
        .salt = .{ 128, 247, 60, 232, 91, 115, 128, 79, 134, 53, 202, 28, 149, 227, 131, 17 },
        .iteration = 4096,
        .response = .{ 114, 61, 78, 105, 115, 98, 71, 117, 101, 76, 73, 97, 88, 121, 90, 112, 122, 66, 56, 106, 65, 107, 85, 74, 102, 74, 83, 79, 75, 67, 100, 100, 88, 50, 75, 68, 97, 106, 68, 70, 102, 83, 102, 67, 70, 55, 122, 111, 74, 113, 44, 115, 61, 103, 80, 99, 56, 54, 70, 116, 122, 103, 69, 43, 71, 78, 99, 111, 99, 108, 101, 79, 68, 69, 81, 61, 61, 44, 105, 61, 52, 48, 57, 54 },
        .password = "[password]",
        .client_first_message = .{ 110, 44, 44, 110, 61, 44, 114, 61, 78, 105, 115, 98, 71, 117, 101, 76, 73, 97, 88, 121, 90, 112, 122, 66, 56, 106, 65, 107, 85, 74, 102, 74 },
    };

    const message = Message{ .sasl_response = expected_response };

    try write(message, writer);

    fixed_buffer.reset();

    const message_type = try reader.readByte();

    try expect(message_type == 'p');

    const message_len = try reader.readInt(i32, .big);

    try reader.skipBytes(@intCast(message_len - 4), .{});
}

test "read write ssl_request" {
    var buffer: [32]u8 = undefined;
    var fixed_buffer = std.io.fixedBufferStream(&buffer);
    const reader = fixed_buffer.reader().any();
    const writer = fixed_buffer.writer().any();

    var arena = ArenaAllocator.init(test_allocator);
    defer arena.deinit();

    const message = Message{ .ssl_request = undefined };

    try write(message, writer);

    fixed_buffer.reset();

    const message_out = try read(reader, &arena);

    switch (message_out) {
        .ssl_request => try expect(std.meta.eql(message_out, message)),
        else => try expect(false),
    }
}
