const std = @import("std");
const Mechanism = @import("mechanism.zig").Mechanism;
const Backend = @import("backend.zig").Backend;
const ConnectInfo = @import("connect_info.zig");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap([]const u8);
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const Sha256 = std.crypto.hash.sha2.Sha256;
const ApplicationCipher = std.crypto.tls.ApplicationCipher;
const base_64_decoder = std.base64.standard.Decoder;
const base_64_encoder = std.base64.standard.Encoder;
const allocPrint = std.fmt.allocPrint;
const pbkdf2 = std.crypto.pwhash.pbkdf2;

pub const Frontend = union(enum) {
    startup_message: StartupMessage,
    sasl_initial_response: SASLInitialResponse,
    sasl_response: SASLResponse,
    ssl_request: void,
    password_message: PasswordMessage,
    query: Query,
    parse: Parse,
    describe: Describe,
    sync: Sync,
    bind: Bind,
    execute: Execute,
    copy_data: CopyData,
    copy_done: CopyDone,

    pub const Target = enum {
        statement,
        portal,
    };

    pub const Format = enum(i16) {
        text = 0,
        binary = 1,
    };

    pub const StartupMessage = struct {
        options: StringHashMap,

        const TAG: i32 = 196608;
        const Iterator = StringHashMap.Iterator;

        pub fn init_connect_info(allocator: Allocator, connect_info: ConnectInfo) !StartupMessage {
            const options = connect_info.options orelse StringHashMap.init(allocator);

            var startup_message = StartupMessage{
                .options = options,
            };

            try startup_message.set_user(connect_info.username);
            try startup_message.set_database(connect_info.database);
            try startup_message.set_application_name(connect_info.application_name);

            return startup_message;
        }

        pub fn write(self: StartupMessage, writer: anytype) !void {
            var payload_len: i32 = 9;

            var len_iterator = self.iterator();

            while (len_iterator.next()) |entry| {
                payload_len += @intCast(entry.key_ptr.len + entry.value_ptr.len + 2);
            }

            try writer.writeInt(i32, @intCast(payload_len), .big);
            try writer.writeInt(i32, TAG, .big);

            var payload_iterator = self.iterator();

            while (payload_iterator.next()) |entry| {
                if (entry.key_ptr.len != 0) {
                    _ = try writer.write(entry.key_ptr.*);
                }

                try writer.writeByte(0);

                if (entry.value_ptr.len != 0) {
                    _ = try writer.write(entry.value_ptr.*);
                }

                try writer.writeByte(0);
            }

            try writer.writeByte(0);
        }

        pub fn set_user(self: *StartupMessage, user: []const u8) !void {
            try self.put("user", user);
        }

        pub fn set_database(self: *StartupMessage, database: []const u8) !void {
            try self.put("database", database);
        }

        pub fn set_application_name(self: *StartupMessage, application_name: []const u8) !void {
            try self.put("application_name", application_name);
        }

        pub fn get_user(self: StartupMessage) ?[]const u8 {
            return self.get("user");
        }

        pub fn get_database(self: StartupMessage) ?[]const u8 {
            return self.get("database");
        }

        pub fn get_application_name(self: StartupMessage) ?[]const u8 {
            return self.get("application_name");
        }

        pub fn put(self: *StartupMessage, key: []const u8, value: []const u8) !void {
            try self.options.put(key, value);
        }

        pub fn get(self: StartupMessage, key: []const u8) ?[]const u8 {
            return self.options.get(key);
        }

        pub fn iterator(self: *const StartupMessage) Iterator {
            return self.options.iterator();
        }

        pub fn deinit(self: *StartupMessage) void {
            self.options.deinit();
        }
    };

    pub const SSLRequest = struct {
        pub fn write(writer: anytype) !void {
            try writer.writeInt(i32, 8, .big);
            try writer.writeInt(i32, 80877103, .big);
        }
    };

    pub const GS2Flag = union(enum) {
        n: void,
        y: void,
        p: ApplicationCipher,
    };

    pub const GS2Header = struct {
        flag: GS2Flag,
        authzid: ?[]const u8,
    };

    pub const SASLInitialResponse = struct {
        allocator: Allocator,
        mechanism: Mechanism,
        gs2_header: GS2Header,
        username: []const u8,
        nonce: []const u8,

        pub fn init(
            allocator: Allocator,
            mechanism: Mechanism,
            flag: GS2Flag,
        ) !SASLInitialResponse {
            var nonce: [18]u8 = undefined;

            std.crypto.random.bytes(&nonce);
            const size = base_64_encoder.calcSize(nonce.len);
            const encoded_nonce: []u8 = try allocator.alloc(u8, size);

            _ = base_64_encoder.encode(encoded_nonce, &nonce);

            return SASLInitialResponse{
                .allocator = allocator,
                .nonce = encoded_nonce,
                .mechanism = mechanism,
                .username = "",
                .gs2_header = GS2Header{
                    .flag = flag,
                    .authzid = null,
                },
            };
        }

        pub fn deinit(self: SASLInitialResponse) void {
            self.allocator.free(self.nonce);
        }

        pub fn clientFirstMessageBare(
            self: SASLInitialResponse,
            allocator: Allocator,
        ) ![]const u8 {
            return try allocPrint(
                allocator,
                "n={s},r={s}",
                .{ self.username, self.nonce },
            );
        }

        pub fn clientFirstMessage(
            self: SASLInitialResponse,
            allocator: Allocator,
        ) ![]const u8 {
            return switch (self.gs2_header.flag) {
                .n => try allocPrint(
                    allocator,
                    "n,,n={s},r={s}",
                    .{ self.username, self.nonce },
                ),
                .y => try allocPrint(
                    allocator,
                    "y,,n={s},r={s}",
                    .{ self.username, self.nonce },
                ),
                .p => try allocPrint(
                    allocator,
                    "p=tls-server-end-point,,n={s},r={s}",
                    .{ self.username, self.nonce },
                ),
            };
        }

        pub fn getSecretFromCipher(ac: ApplicationCipher) []const u8 {
            return switch (ac) {
                .AES_128_GCM_SHA256 => |value| value.server_key,
                .AES_256_GCM_SHA384 => |value| value.server_key,
                .CHACHA20_POLY1305_SHA256 => |value| value.server_key,
                .AEGIS_256_SHA512 => |value| value.server_key,
                .AEGIS_128L_SHA256 => |value| value.server_key,
            };
        }

        pub fn channelBinding(
            self: SASLInitialResponse,
            allocator: Allocator,
        ) ![]const u8 {
            return switch (self.gs2_header.flag) {
                .n => {
                    const encode = "n,,";
                    const size = base_64_encoder.calcSize(encode.len);
                    const result = try allocator.alloc(u8, size);

                    _ = base_64_encoder.encode(result, encode);

                    return result;
                },
                .y => {
                    const encode = "y,,";
                    const size = base_64_encoder.calcSize(encode.len);
                    const result = try allocator.alloc(u8, size);

                    _ = base_64_encoder.encode(result, encode);

                    return result;
                },
                .p => {
                    @panic("SCRAM_SHA_256_PLUS is currently unsupported");
                },
            };
        }

        pub fn write(self: SASLInitialResponse, allocator: Allocator, writer: anytype) !void {
            var payload_len: usize = 9;

            const mechanism = self.mechanism.toString();
            const cfm = try self.clientFirstMessage(allocator);
            defer allocator.free(cfm);

            payload_len += mechanism.len;
            payload_len += cfm.len;

            _ = try writer.writeByte('p');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(mechanism.*);
            try writer.writeByte(0);
            try writer.writeInt(i32, @intCast(cfm.len), .big);
            _ = try writer.write(cfm);
        }
    };

    pub const SASLResponse = struct {
        client_first_message: SASLInitialResponse,
        server_first_message: Backend.Authentication.SASLContinue,
        password: []const u8,

        pub fn write(self: SASLResponse, allocator: Allocator, writer: anytype) !void {
            const mac_length = std.crypto.auth.hmac.sha2.HmacSha256.mac_length;
            const encoded_length = comptime base_64_encoder.calcSize(mac_length);

            var salted_password: [mac_length]u8 = undefined;

            try std.crypto.pwhash.pbkdf2(
                &salted_password,
                self.password,
                self.server_first_message.salt,
                self.server_first_message.iteration,
                std.crypto.auth.hmac.sha2.HmacSha256,
            );

            const client_first_message_bare = try self.client_first_message.clientFirstMessageBare(allocator);
            const server_first_message = self.server_first_message.data;
            const channel_binding = try self.client_first_message.channelBinding(allocator);
            const client_final_message_without_proof = try allocPrint(allocator, "c={s},r={s}", .{ channel_binding, self.server_first_message.nonce });
            const auth_message = try allocPrint(allocator, "{s},{s},{s}", .{ client_first_message_bare, server_first_message, client_final_message_without_proof });
            defer {
                allocator.free(auth_message);
                allocator.free(client_final_message_without_proof);
                allocator.free(client_first_message_bare);
                allocator.free(channel_binding);
            }

            var proof: [encoded_length]u8 = undefined;

            var client_key: [mac_length]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&client_key, "Client Key", &salted_password);

            var stored_key: [mac_length]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(&client_key, &stored_key, .{});

            var client_signature: [mac_length]u8 = undefined;
            std.crypto.auth.hmac.sha2.HmacSha256.create(&client_signature, auth_message, &stored_key);

            var unencoded_proof: [mac_length]u8 = undefined;
            for (client_key, client_signature, 0..) |ck, cs, i| {
                unencoded_proof[i] = ck ^ cs;
            }

            _ = base_64_encoder.encode(&proof, &unencoded_proof);

            const authentication = try allocPrint(allocator, "{s},p={s}", .{ client_final_message_without_proof, proof });
            defer allocator.free(authentication);

            const payload_len = authentication.len + 4;

            try writer.writeByte('p');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(authentication);
        }
    };

    pub const PasswordMessage = struct {
        password: []const u8,

        pub fn hash_md5(self: *PasswordMessage, salt: []const u8) void {
            const digest_length = std.crypto.hash.Md5.digest_length;
            var out: [digest_length]u8 = undefined;

            var hash = std.crypto.hash.Md5.init(.{});
            hash.update(self.password);
            hash.update(salt);

            hash.final(&out);

            self.password = &out;
        }

        pub fn write(self: PasswordMessage, writer: anytype) !void {
            const payload_len = 5 + self.password.len;

            try writer.writeByte('p');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            if (self.password.len != 0) {
                _ = try writer.write(self.password);
            }

            try writer.writeByte(0);
        }
    };

    pub const Query = struct {
        statement: []const u8,

        pub fn write(self: Query, writer: anytype) !void {
            const payload_len = self.statement.len + 5;

            try writer.writeByte('Q');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            if (self.statement.len != 0) {
                _ = try writer.write(self.statement);
            }

            try writer.writeByte(0);
        }
    };

    pub const Parse = struct {
        name: []const u8,
        statement: []const u8,

        pub fn write(self: Parse, writer: anytype) !void {
            const payload_len = 8 + self.name.len + self.statement.len;

            try writer.writeByte('P');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            if (self.name.len != 0) {
                _ = try writer.write(self.name);
            }
            try writer.writeByte(0);

            if (self.statement.len != 0) {
                _ = try writer.write(self.statement);
            }

            try writer.writeByte(0);

            // TODO: At some point i would like to use comptime to compile
            // check object ids from the db and use that
            try writer.writeInt(i16, 0, .big);
        }
    };

    pub const Describe = struct {
        target: Target,
        name: []const u8,

        pub fn write(self: Describe, writer: anytype) !void {
            const payload_len = 6 + self.name.len;

            try writer.writeByte('D');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            switch (self.target) {
                .statement => try writer.writeByte('S'),
                .portal => try writer.writeByte('P'),
            }

            if (self.name.len != 0) {
                _ = try writer.write(self.name);
            }

            try writer.writeByte(0);
        }
    };

    pub const Sync = struct {
        pub fn write(writer: anytype) !void {
            try writer.writeByte('S');
            try writer.writeInt(i32, 4, .big);
        }
    };

    pub const Bind = struct {
        portal_name: []const u8,
        statement_name: []const u8,
        parameter_format: Format,
        result_format: Format,
        parameters: []?[]const u8,

        pub fn write(self: Bind, writer: anytype) !void {
            var payload_len = 16 + self.portal_name.len + self.statement_name.len;

            for (self.parameters) |param| {
                if (param) |value| {
                    payload_len += 4 + value.len;
                } else {
                    payload_len += 4;
                }
            }

            try writer.writeByte('B');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            if (self.portal_name.len != 0) {
                _ = try writer.write(self.portal_name);
            }

            try writer.writeByte(0);

            if (self.statement_name.len != 0) {
                _ = try writer.write(self.statement_name);
            }

            try writer.writeByte(0);

            try writer.writeInt(i16, 1, .big); // Number of parameter format codes
            try writer.writeInt(i16, @intFromEnum(self.parameter_format), .big);
            try writer.writeInt(i16, @intCast(self.parameters.len), .big); // Number of parameter format codes

            // For each param write
            for (self.parameters) |param| {
                // Deal with null we write -1
                if (param) |value| {
                    try writer.writeInt(i32, @intCast(value.len), .big);
                    _ = try writer.write(value);
                } else {
                    try writer.writeInt(i32, -1, .big);
                }
            }

            try writer.writeInt(i16, 1, .big);
            try writer.writeInt(i16, @intFromEnum(self.result_format), .big);
        }
    };

    pub const Execute = struct {
        portal_name: []const u8,
        rows: i32,

        pub fn write(self: Execute, writer: anytype) !void {
            const payload_len = 9 + self.portal_name.len;

            try writer.writeByte('E');
            try writer.writeInt(i32, @intCast(payload_len), .big);

            if (self.portal_name.len != 0) {
                _ = try writer.write(self.portal_name);
            }

            try writer.writeByte(0);
            try writer.writeInt(i32, self.rows, .big);
        }
    };

    pub const CopyData = struct {
        data: []const u8,

        pub fn write(self: CopyData, writer: anytype) !void {
            const payload_len = 4 + self.data.len;

            try writer.writeByte('d');
            try writer.writeInt(i32, @intCast(payload_len), .big);
            _ = try writer.write(self.data);
        }
    };

    pub const CopyDone = struct {
        pub fn write(writer: anytype) !void {
            try writer.writeByte('c');
            try writer.writeInt(i32, 4, .big);
        }
    };

    pub fn write(self: Frontend, allocator: Allocator, writer: anytype) !void {
        switch (self) {
            .startup_message => |startup_message| {
                try startup_message.write(writer);
            },
            .ssl_request => {
                try SSLRequest.write(writer);
            },
            .sasl_initial_response => |sir| {
                try sir.write(allocator, writer);
            },
            .sasl_response => |sr| {
                try sr.write(allocator, writer);
            },
            .password_message => |pm| {
                try pm.write(writer);
            },
            .query => |query| {
                try query.write(writer);
            },
            .parse => |parse| {
                try parse.write(writer);
            },
            .describe => |describe| {
                try describe.write(writer);
            },
            .sync => {
                try Sync.write(writer);
            },
            .execute => |execute| {
                try execute.write(writer);
            },
            .bind => |bind| {
                try bind.write(writer);
            },
            .copy_data => |copy_data| {
                try copy_data.write(writer);
            },
            .copy_done => {
                try CopyDone.write(writer);
            },
        }
    }
};
