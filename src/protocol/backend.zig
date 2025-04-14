const std = @import("std");
const Mechanism = @import("mechanism.zig").Mechanism;
const Allocator = std.mem.Allocator;
const Tuple = std.meta.Tuple;
const Endian = std.builtin.Endian;
const GenericReader = std.io.GenericReader;
const base_64_decoder = std.base64.standard.Decoder;
const eql = std.mem.eql;
const parseInt = std.fmt.parseInt;
const stringToEnum = std.meta.stringToEnum;
const startsWith = std.mem.startsWith;
const memReadInt = std.mem.readInt;
const assert = std.debug.assert;

pub const Backend = union(enum) {
    authentication: Authentication,
    parameter_status: ParameterStatus,
    ready_for_query: ReadyForQuery,
    error_response: ErrorResponse,
    backend_key_data: BackendKeyData,
    row_description: RowDescription,
    data_row: DataRow,
    command_complete: CommandComplete,
    parse_complete: ParseComplete,
    parameter_description: ParameterDescription,
    bind_complete: BindComplete,
    no_data: NoData,
    notice_response: NoticeResponse,
    copy_in_response: CopyInResponse,
    copy_out_response: CopyOutResponse,
    copy_data: CopyData,
    copy_done: CopyDone,
    portal_suspended: PortalSuspended,

    pub const BufferReader = struct {
        buffer: []const u8,
        pos: usize,

        const Self = @This();

        pub const ReadError = error{
            EndOfStream,
            UnexpectedValue,
            OutOfBounds,
        };

        pub fn read(self: *Self, dest: []u8) !usize {
            const size = @min(dest.len, self.buffer.len - self.pos);
            const end = self.pos + size;

            @memcpy(dest[0..size], self.buffer[self.pos..end]);
            self.pos = end;

            return size;
        }

        pub fn readByte(self: *Self) !u8 {
            var result: [1]u8 = undefined;
            const amt_read = try self.read(result[0..]);
            if (amt_read < 1) return ReadError.EndOfStream;
            return result[0];
        }

        pub fn readCstr(self: *Self) ![]const u8 {
            const start = self.pos;
            var byte = try self.readByte();

            while (byte != 0 and self.pos != self.buffer.len) {
                byte = try self.readByte();
            }

            return self.buffer[start .. self.pos - 1];
        }

        pub fn expect(self: *Self, expected: []const u8) !void {
            const actual = self.buffer[self.pos .. self.pos + expected.len];

            if (eql(u8, expected, actual)) {
                self.pos += actual.len;
                return;
            }

            return error.UnexpectedValue;
        }

        pub fn readUntil(self: *Self, char: u21) ![]const u8 {
            const start = self.pos;
            var byte = try self.readByte();

            while (byte != char) {
                byte = try self.readByte();
            }

            return self.buffer[start .. self.pos - 1];
        }

        pub fn readUntilEnd(self: *Self) []const u8 {
            const buffer = self.buffer[self.pos..self.buffer.len];

            self.pos = self.buffer.len;

            return buffer;
        }

        pub fn readAtleast(self: *Self, size: usize) ![]const u8 {
            if (self.pos + size > self.buffer.len) return error.OutOfBounds;

            const bytes = self.buffer[self.pos .. self.pos + size];

            self.pos += size;

            return bytes;
        }

        pub fn readInt(
            self: *Self,
            comptime T: type,
            endian: Endian,
        ) anyerror!T {
            var buffer: [@divExact(@typeInfo(T).int.bits, 8)]u8 = undefined;
            _ = try self.read(&buffer);
            return memReadInt(T, &buffer, endian);
        }

        pub fn reset(self: *Self) void {
            self.pos = 0;
        }

        pub fn bufferReader(buffer: []const u8) BufferReader {
            return .{ .buffer = buffer, .pos = 0 };
        }
    };

    pub const Authentication = union(enum) {
        pub const TAG = 'R';

        ok: Ok,
        sasl: SASL,
        clear_text_password: ClearTextPassword,
        // kerberos_v5: AuthenticationKerberosV5,
        md5_password: MD5Password,
        // gss: AuthenticationGSS,
        // gss_continue: AuthenticationGSSContinue,
        // sspi: AuthenticationSSPI,
        sasl_continue: SASLContinue,
        sasl_final: SASLFinal,

        pub const Type = enum(i32) {
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

        pub const Ok = void;

        pub const SASL = struct {
            allocator: Allocator,
            mechanisms: [2]Mechanism,
            buffer: []const u8,

            pub fn read(allocator: Allocator, buffer: []const u8) !SASL {
                var reader = BufferReader.bufferReader(buffer);
                var mechanisms: [2]Mechanism = undefined;
                var i: u8 = 0;

                while (reader.pos != reader.buffer.len - 1) {
                    const mechanism_str = try reader.readCstr();
                    const mechanism = Mechanism.fromString(mechanism_str) orelse @panic("Failed to parse mechanism");

                    mechanisms[i] = mechanism;

                    i += 1;
                }
                return SASL{
                    .allocator = allocator,
                    .mechanisms = mechanisms,
                    .buffer = buffer,
                };
            }

            pub fn get_first_mechanism(self: SASL) Mechanism {
                var mechanism: Mechanism = undefined;

                for (self.mechanisms) |mech| {
                    if (mech == .scram_sha_256) mechanism = mech;
                }

                return mechanism;
            }

            pub fn deinit(self: SASL) void {
                self.allocator.free(self.buffer);
            }
        };

        pub const SASLContinue = struct {
            allocator: Allocator,
            nonce: []const u8,
            salt: []const u8,
            iteration: u32,
            data: []const u8,

            pub fn read(allocator: Allocator, buffer: []const u8) !SASLContinue {
                var reader = BufferReader.bufferReader(buffer);

                try reader.expect("r=");
                const nonce = try reader.readUntil(',');
                try reader.expect("s=");
                const encoded_salt = try reader.readUntil(',');

                const size_of_uncoded_salt = try base_64_decoder.calcSizeForSlice(encoded_salt);
                const salt = try allocator.alloc(u8, size_of_uncoded_salt);

                _ = try base_64_decoder.decode(salt, encoded_salt);

                try reader.expect("i=");
                const iteration_str = reader.readUntilEnd();
                const interation = try parseInt(u32, iteration_str, 10);

                return SASLContinue{
                    .allocator = allocator,
                    .nonce = nonce,
                    .salt = salt,
                    .iteration = interation,
                    .data = buffer,
                };
            }

            pub fn deinit(self: SASLContinue) void {
                self.allocator.free(self.data);
                self.allocator.free(self.salt);
            }
        };

        pub const SASLFinal = struct {
            allocator: Allocator,
            additional_data: []const u8,

            pub fn read(allocator: Allocator, buffer: []const u8) !SASLFinal {
                return SASLFinal{
                    .allocator = allocator,
                    .additional_data = buffer,
                };
            }

            pub fn deinit(self: SASLFinal) void {
                self.allocator.free(self.additional_data);
            }
        };

        pub const ClearTextPassword = struct {};

        pub const MD5Password = struct {
            salt: [4]u8,

            pub fn read(buffer: []const u8) !MD5Password {
                var reader = BufferReader.bufferReader(buffer);

                var salt: [4]u8 = undefined;

                _ = try reader.read(&salt);

                return MD5Password{
                    .salt = salt,
                };
            }
        };

        pub fn read(allocator: Allocator, reader: anytype) !Authentication {
            const message_length = try reader.readInt(i32, .big);
            const auth_type = try reader.readInt(i32, .big);

            switch (@as(Type, @enumFromInt(auth_type))) {
                .ok => {
                    assert(auth_type == 0);

                    return .{ .ok = undefined };
                },
                .kerberosV5 => {
                    @panic("Not yet implemented");
                },
                .clear_text_password => {
                    return Authentication{
                        .clear_text_password = ClearTextPassword{},
                    };
                },
                .md5_password => {
                    const buffer = try allocator.alloc(u8, @intCast(message_length - 8));
                    defer allocator.free(buffer);

                    _ = try reader.read(buffer);

                    const md5 = try MD5Password.read(buffer);

                    return Authentication{
                        .md5_password = md5,
                    };
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
                .sasl => {
                    const buffer = try allocator.alloc(u8, @intCast(message_length - 8));

                    _ = try reader.read(buffer);

                    const sasl = try SASL.read(
                        allocator,
                        buffer,
                    );

                    return Authentication{ .sasl = sasl };
                },
                .sasl_continue => {
                    const buffer = try allocator.alloc(u8, @intCast(message_length - 8));

                    _ = try reader.read(buffer);

                    const sasl_continue = try SASLContinue.read(
                        allocator,
                        buffer,
                    );

                    return Authentication{
                        .sasl_continue = sasl_continue,
                    };
                },
                .sasl_final => {
                    const buffer = try allocator.alloc(u8, @intCast(message_length - 8));

                    _ = try reader.read(buffer);

                    const sasl_final = try SASLFinal.read(
                        allocator,
                        buffer,
                    );

                    return Authentication{ .sasl_final = sasl_final };
                },
            }
        }

        pub fn deinit(self: Authentication) void {
            switch (self) {
                .sasl => |sasl| sasl.deinit(),
                .sasl_continue => |sasl_continue| sasl_continue.deinit(),
                .sasl_final => |sasl_final| sasl_final.deinit(),
                else => {},
            }
        }
    };

    pub const ParameterStatus = struct {
        pub const TAG = 'S';

        allocator: Allocator,
        name: []const u8,
        value: []const u8,
        buffer: []const u8,

        pub fn read(allocator: Allocator, reader: anytype) !ParameterStatus {
            const message_length = try reader.readInt(i32, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_length - 4));

            _ = try reader.read(buffer);

            var bufferReader = BufferReader.bufferReader(buffer);

            const name = try bufferReader.readCstr();
            const value = try bufferReader.readCstr();

            return ParameterStatus{
                .allocator = allocator,
                .name = name,
                .value = value,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: ParameterStatus) void {
            self.allocator.free(self.buffer);
        }
    };

    pub const ReadyForQuery = struct {
        pub const TAG = 'Z';

        pub const StatusIndicator = enum(u8) {
            I,
            T,
            E,
        };

        status_indicator: StatusIndicator,

        pub fn read(reader: anytype) !ReadyForQuery {
            _ = try reader.readInt(i32, .big);
            const byte = try reader.readByte();

            if (stringToEnum(StatusIndicator, &[1]u8{byte})) |status_indicator| {
                return ReadyForQuery{
                    .status_indicator = status_indicator,
                };
            }

            @panic("Unexpected status indicator from ready query");
        }
    };

    pub const ErrorResponse = struct {
        pub const TAG = 'E';

        allocator: Allocator,
        buffer: []const u8,

        pub const KeyValue = Tuple(&[_]type{ u8, []const u8 });

        pub const Iterator = struct {
            index: u32,
            buffer: []const u8,

            pub fn next(self: *Iterator) !?KeyValue {
                if (self.buffer.len == self.index) return null;

                var reader = BufferReader.bufferReader(self.buffer);

                // Get the last position
                reader.pos = self.index;

                const key = try reader.readByte();
                const value = try reader.readCstr();

                // Set the new postion
                self.index = @intCast(reader.pos);

                return .{ key, value };
            }
        };

        pub fn iterator(self: ErrorResponse) Iterator {
            return Iterator{
                .index = 0,
                .buffer = self.buffer,
            };
        }

        pub fn read(allocator: Allocator, reader: anytype) !ErrorResponse {
            const message_length = try reader.readInt(i32, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_length - 4));

            _ = try reader.read(buffer);

            std.log.err("Buffer: {s}", .{buffer});

            return ErrorResponse{
                .allocator = allocator,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: ErrorResponse) void {
            self.allocator.free(self.buffer);
        }
    };

    pub const BackendKeyData = struct {
        pub const TAG = 'K';

        process_id: i32,
        secret_key: i32,

        pub fn read(reader: anytype) !BackendKeyData {
            _ = try reader.readInt(i32, .big);

            const process_id = try reader.readInt(i32, .big);
            const secret_key = try reader.readInt(i32, .big);

            return BackendKeyData{
                .process_id = process_id,
                .secret_key = secret_key,
            };
        }
    };

    pub const RowDescription = struct {
        pub const TAG = 'T';

        allocator: Allocator,
        fields: i16,
        buffer: []const u8,

        pub const Iterator = struct {
            index: u32,
            buffer: []const u8,

            pub fn next(self: *Iterator) !?ColumnDescription {
                if (self.buffer.len == self.index) return null;
                var reader = BufferReader.bufferReader(self.buffer);

                reader.pos = self.index;

                const field_name = try reader.readCstr();
                const object_id = try reader.readInt(i32, .big);
                const attribute_id = try reader.readInt(i16, .big);
                const data_type_id = try reader.readInt(i32, .big);
                const data_type_size = try reader.readInt(i16, .big);
                const data_type_modifier = try reader.readInt(i32, .big);
                const format_code = try reader.readInt(i16, .big);

                self.index = @intCast(reader.pos);

                return ColumnDescription{
                    .field_name = field_name,
                    .object_id = object_id,
                    .attribute_id = attribute_id,
                    .data_type_id = data_type_id,
                    .data_type_size = data_type_size,
                    .data_type_modifier = data_type_modifier,
                    .format_code = format_code,
                };
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

        pub fn iterator(self: RowDescription) Iterator {
            return Iterator{
                .index = 0,
                .buffer = self.buffer,
            };
        }

        pub fn read(allocator: Allocator, reader: anytype) !RowDescription {
            const message_len = try reader.readInt(i32, .big);
            const fields = try reader.readInt(i16, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_len - 6));

            _ = try reader.read(buffer);

            return RowDescription{
                .allocator = allocator,
                .fields = fields,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: RowDescription) void {
            self.allocator.free(self.buffer);
        }
    };

    pub const DataRow = struct {
        pub const TAG = 'D';

        allocator: Allocator,
        size: i32,
        columns: i16,
        buffer: []const u8,
        cursor: u16,

        pub fn get(self: *DataRow) ![]const u8 {
            const opt = try self.optional();

            if (opt) |value| {
                return value;
            } else {
                return error.UnexpectedNull;
            }
        }

        pub fn optional(self: *DataRow) !?[]const u8 {
            errdefer self.allocator.free(self.buffer);
            if (self.cursor == self.buffer.len) return error.OutOfBounds;

            var reader = BufferReader.bufferReader(self.buffer);

            reader.pos = self.cursor;

            const length = try reader.readInt(i32, .big);
            var value: ?[]const u8 = null;

            if (length != -1) {
                value = try reader.readAtleast(@intCast(length));
            }

            self.cursor = @intCast(reader.pos);

            return value;
        }

        pub fn deinit(self: DataRow) void {
            self.allocator.free(self.buffer);
        }

        pub fn read(allocator: Allocator, reader: anytype) !DataRow {
            const message_len = try reader.readInt(i32, .big);
            const columns = try reader.readInt(i16, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_len - 6));

            _ = try reader.read(buffer);

            return DataRow{
                .allocator = allocator,
                .columns = columns,
                .buffer = buffer,
                .size = message_len,
                .cursor = 0,
            };
        }
    };

    pub const CommandComplete = struct {
        pub const TAG = 'C';

        command: Command,
        rows: i32,
        oid: i32,

        pub const Command = enum {
            insert,
            delete,
            update,
            merge,
            select,
            move,
            fetch,
            copy,
            listen,
            create_table,
            other,

            pub fn fromStr(str: []const u8) Command {
                if (startsWith(u8, str, "INSERT")) return .insert;
                if (startsWith(u8, str, "DELETE")) return .delete;
                if (startsWith(u8, str, "UPDATE")) return .update;
                if (startsWith(u8, str, "MERGE")) return .merge;
                if (startsWith(u8, str, "SELECT")) return .select;
                if (startsWith(u8, str, "MOVE")) return .move;
                if (startsWith(u8, str, "FETCH")) return .fetch;
                if (startsWith(u8, str, "COPY")) return .copy;
                if (startsWith(u8, str, "LISTEN")) return .listen;
                if (startsWith(u8, str, "CREATE TABLE")) return .create_table;

                return .other;
            }
        };

        pub fn read(allocator: Allocator, reader: anytype) !CommandComplete {
            const message_len = try reader.readInt(i32, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_len - 4));
            const SPACE: u21 = 32;

            _ = try reader.read(buffer);

            var bufferReader = BufferReader.bufferReader(buffer);
            defer allocator.free(buffer);

            switch (Command.fromStr(buffer)) {
                .insert => {
                    _ = try bufferReader.readUntil(SPACE);
                    const oid_str = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const oid = try parseInt(i32, oid_str, 10);
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .insert,
                        .rows = rows,
                        .oid = oid,
                    };
                },
                .select => {
                    _ = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .insert,
                        .rows = rows,
                        .oid = 0,
                    };
                },
                .delete => {
                    _ = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .delete,
                        .rows = rows,
                        .oid = 0,
                    };
                },
                .create_table => {
                    return CommandComplete{
                        .command = .create_table,
                        .rows = 0,
                        .oid = 0,
                    };
                },
                .copy => {
                    _ = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .copy,
                        .rows = rows,
                        .oid = 0,
                    };
                },
                .update => {
                    _ = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .update,
                        .rows = rows,
                        .oid = 0,
                    };
                },
                .merge => {
                    _ = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .merge,
                        .rows = rows,
                        .oid = 0,
                    };
                },
                .fetch => {
                    _ = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .fetch,
                        .rows = rows,
                        .oid = 0,
                    };
                },
                .move => {
                    _ = try bufferReader.readUntil(SPACE);
                    const rows_str = try bufferReader.readCstr();
                    const rows = try parseInt(i32, rows_str, 10);

                    return CommandComplete{
                        .command = .move,
                        .rows = rows,
                        .oid = 0,
                    };
                },
                .listen => {
                    return CommandComplete{
                        .command = .listen,
                        .rows = 0,
                        .oid = 0,
                    };
                },
                .other => {
                    return CommandComplete{
                        .command = .other,
                        .rows = 0,
                        .oid = 0,
                    };
                },
            }
        }
    };

    pub const ParseComplete = struct {
        pub const TAG = '1';

        pub fn read(reader: anytype) !ParseComplete {
            _ = try reader.readInt(i32, .big);

            return ParseComplete{};
        }
    };

    pub const ParameterDescription = struct {
        pub const TAG = 't';

        allocator: Allocator,
        object_ids: []i32,

        pub fn read(allocator: Allocator, reader: anytype) !ParameterDescription {
            _ = try reader.readInt(i32, .big);
            const parameter_count = try reader.readInt(i16, .big);
            const object_ids = try allocator.alloc(i32, @intCast(parameter_count));

            for (0..@intCast(parameter_count)) |index| {
                object_ids[index] = try reader.readInt(i32, .big);
            }

            return ParameterDescription{
                .allocator = allocator,
                .object_ids = object_ids,
            };
        }

        pub fn deinit(self: ParameterDescription) void {
            self.allocator.free(self.object_ids);
        }
    };

    pub const BindComplete = struct {
        pub const TAG = '2';

        pub fn read(reader: anytype) !BindComplete {
            _ = try reader.readInt(i32, .big);

            return BindComplete{};
        }
    };

    pub const NoData = struct {
        pub const TAG = 'n';

        pub fn read(reader: anytype) !NoData {
            _ = try reader.readInt(i32, .big);

            return NoData{};
        }
    };

    pub const NoticeResponse = struct {
        pub const TAG = 'N';

        allocator: Allocator,
        buffer: []const u8,

        pub const KeyValue = Tuple(&[_]type{ u8, []const u8 });

        pub const Iterator = struct {
            index: u32,
            buffer: []const u8,

            pub fn next(self: *Iterator) !?KeyValue {
                if (self.buffer.len == self.index) return null;

                var reader = BufferReader.bufferReader(self.buffer);

                // Get the last position
                reader.pos = self.index;

                const key = try reader.readByte();
                const value = try reader.readCstr();

                // Set the new postion
                self.index = @intCast(reader.pos);

                return .{ key, value };
            }
        };

        pub fn iterator(self: NoticeResponse) Iterator {
            return Iterator{
                .index = 0,
                .buffer = self.buffer,
            };
        }

        pub fn read(allocator: Allocator, reader: anytype) !NoticeResponse {
            const message_length = try reader.readInt(i32, .big);
            const buffer = try allocator.alloc(u8, @intCast(message_length - 4));

            _ = try reader.read(buffer);

            return NoticeResponse{
                .allocator = allocator,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: NoticeResponse) void {
            self.allocator.free(self.buffer);
        }
    };

    pub const CopyInResponse = struct {
        pub const TAG = 'G';

        allocator: Allocator,
        format: i8,
        columns: i16,
        codes: []i16,

        pub fn deinit(self: CopyInResponse) void {
            self.allocator.free(self.codes);
        }

        pub fn read(allocator: Allocator, reader: anytype) !CopyInResponse {
            _ = try reader.readInt(i32, .big);
            const format = try reader.readInt(i8, .big);
            const columns = try reader.readInt(i16, .big);
            const codes = try allocator.alloc(i16, @intCast(columns));

            for (0..@intCast(columns)) |index| {
                codes[index] = try reader.readInt(i16, .big);
            }

            return CopyInResponse{
                .allocator = allocator,
                .format = format,
                .columns = columns,
                .codes = codes,
            };
        }
    };

    pub const CopyOutResponse = struct {
        pub const TAG = 'H';

        allocator: Allocator,
        format: i8,
        columns: i16,
        codes: []i16,

        pub fn deinit(self: CopyOutResponse) void {
            self.allocator.free(self.codes);
        }

        pub fn read(allocator: Allocator, reader: anytype) !CopyOutResponse {
            _ = try reader.readInt(i32, .big);
            const format = try reader.readInt(i8, .big);
            const columns = try reader.readInt(i16, .big);
            const codes = try allocator.alloc(i16, @intCast(columns));

            for (0..@intCast(columns)) |index| {
                codes[index] = try reader.readInt(i16, .big);
            }

            return CopyOutResponse{
                .allocator = allocator,
                .format = format,
                .columns = columns,
                .codes = codes,
            };
        }
    };

    pub const CopyData = struct {
        pub const TAG = 'd';

        allocator: Allocator,
        data: []const u8,

        pub fn deinit(self: CopyData) void {
            self.allocator.free(self.data);
        }

        pub fn read(allocator: Allocator, reader: anytype) !CopyData {
            const message_len = try reader.readInt(i32, .big);

            const buffer = try allocator.alloc(u8, @intCast(message_len - 4));

            _ = try reader.read(buffer);

            return CopyData{
                .allocator = allocator,
                .data = buffer,
            };
        }
    };

    pub const CopyDone = struct {
        pub const TAG = 'c';

        pub fn read(reader: anytype) !CopyDone {
            _ = try reader.readInt(i32, .big);

            return CopyDone{};
        }
    };

    pub const PortalSuspended = struct {
        pub const TAG = 's';

        pub fn read(reader: anytype) !PortalSuspended {
            _ = try reader.readInt(i32, .big);

            return PortalSuspended{};
        }
    };

    pub fn read(allocator: Allocator, reader: anytype) !Backend {
        const message_type = try reader.readByte();

        switch (message_type) {
            Authentication.TAG => {
                const auth = try Authentication.read(
                    allocator,
                    reader,
                );

                return Backend{
                    .authentication = auth,
                };
            },
            ParameterStatus.TAG => {
                const ps = try ParameterStatus.read(
                    allocator,
                    reader,
                );

                return Backend{
                    .parameter_status = ps,
                };
            },
            ReadyForQuery.TAG => {
                const rfq = try ReadyForQuery.read(reader);

                return Backend{
                    .ready_for_query = rfq,
                };
            },
            ErrorResponse.TAG => {
                const er = try ErrorResponse.read(
                    allocator,
                    reader,
                );

                return Backend{
                    .error_response = er,
                };
            },
            BackendKeyData.TAG => {
                const bkd = try BackendKeyData.read(reader);

                return Backend{
                    .backend_key_data = bkd,
                };
            },
            RowDescription.TAG => {
                const rd = try RowDescription.read(allocator, reader);

                return Backend{
                    .row_description = rd,
                };
            },
            DataRow.TAG => {
                const dr = try DataRow.read(allocator, reader);

                return Backend{
                    .data_row = dr,
                };
            },
            CommandComplete.TAG => {
                const cc = try CommandComplete.read(allocator, reader);

                return Backend{
                    .command_complete = cc,
                };
            },
            ParseComplete.TAG => {
                const pc = try ParseComplete.read(reader);

                return Backend{
                    .parse_complete = pc,
                };
            },
            ParameterDescription.TAG => {
                const pd = try ParameterDescription.read(allocator, reader);

                return Backend{
                    .parameter_description = pd,
                };
            },
            BindComplete.TAG => {
                const bc = try BindComplete.read(reader);

                return Backend{
                    .bind_complete = bc,
                };
            },
            NoData.TAG => {
                const nd = try NoData.read(reader);

                return Backend{
                    .no_data = nd,
                };
            },
            NoticeResponse.TAG => {
                const nr = try NoticeResponse.read(allocator, reader);

                return Backend{
                    .notice_response = nr,
                };
            },
            CopyInResponse.TAG => {
                const cir = try CopyInResponse.read(allocator, reader);

                return Backend{
                    .copy_in_response = cir,
                };
            },
            CopyOutResponse.TAG => {
                const cor = try CopyOutResponse.read(allocator, reader);

                return Backend{
                    .copy_out_response = cor,
                };
            },
            CopyData.TAG => {
                const cd = try CopyData.read(allocator, reader);

                return Backend{
                    .copy_data = cd,
                };
            },
            CopyDone.TAG => {
                const cd = try CopyDone.read(reader);

                return Backend{
                    .copy_done = cd,
                };
            },
            PortalSuspended.TAG => {
                const ps = try PortalSuspended.read(reader);

                return Backend{
                    .portal_suspended = ps,
                };
            },
            else => {
                std.log.err("Message type: {c}", .{message_type});
                @panic("Unexpected protocol message type");
            },
        }
    }

    pub fn deinit(self: Backend) void {
        switch (self) {
            .authentication => |auth| auth.deinit(),
            else => unreachable,
        }
    }
};
