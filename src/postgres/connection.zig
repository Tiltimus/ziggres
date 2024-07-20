const std = @import("std");
const Authenticator = @import("./authenticator.zig");
const Query = @import("./query.zig");
const Message = @import("./message.zig");
const ConnectInfo = @import("./connect_info.zig");
const DataReader = @import("./data_reader.zig");
const Network = std.net;
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;
const parseIp = std.net.Address.parseIp;

const Connection = @This();

allocator: Allocator,
state: State,
stream: Network.Stream,
connect_info: ConnectInfo,

fn stream_read(context: *const anyopaque, buffer: []u8) anyerror!usize {
    const ptr: *const Network.Stream = @alignCast(@ptrCast(context));
    return Network.Stream.read(ptr.*, buffer);
}

fn stream_write(context: *const anyopaque, bytes: []const u8) anyerror!usize {
    const ptr: *const Network.Stream = @alignCast(@ptrCast(context));
    return Network.Stream.write(ptr.*, bytes);
}

pub fn connect(allocator: Allocator, connect_info: ConnectInfo) !Connection {
    const stream = try Network.tcpConnectToHost(allocator, connect_info.host, connect_info.port);
    errdefer stream.close();

    const authenticator = Authenticator.init(allocator, connect_info);
    const initial_state = State{ .authenticating = authenticator };

    var connection = Connection{
        .stream = stream,
        .state = initial_state,
        .allocator = allocator,
        .connect_info = connect_info,
    };

    // TODO: Add checks to ensure it doesn't lock in loop
    while (true) {
        try connection.transition();

        switch (connection.state) {
            .ready => break,
            else => continue,
        }
    }

    return connection;
}

pub fn query(self: *Connection, statement: []const u8) !DataReader {
    switch (self.state) {
        .ready => {
            const query_state = Query.init(self.allocator, statement);

            self.state = .{ .querying = query_state };

            while (true) {
                try self.transition();

                switch (self.state) {
                    .querying => |current_query| {
                        switch (current_query.state) {
                            .data_reader => |data_reader| return data_reader,
                            else => {},
                        }
                    },
                    .ready => break,
                    .error_response => break,
                    else => @panic("Fucks sake"),
                }
            }
        },
        else => @panic("Protocol is not in the ready state."),
    }

    @panic("Protocol is not in the ready state.");
}

fn transition(self: *Connection) !void {
    const reader = AnyReader{
        .context = @ptrCast(&self.stream),
        .readFn = &stream_read,
    };

    const writer = AnyWriter{
        .context = @ptrCast(&self.stream),
        .writeFn = &stream_write,
    };

    switch (self.state) {
        .authenticating => |*authenticator| {
            try authenticator.transition(
                reader,
                writer,
            );

            switch (authenticator.state) {
                .authenticated => self.state = (.{ .ready = undefined }),
                .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                else => {},
            }
        },
        .querying => |*current_query| {
            try current_query.transition(
                reader,
                writer,
            );

            switch (current_query.state) {
                .done => self.state = (.{ .ready = undefined }),
                .error_response => |error_response| self.state = (.{ .error_response = error_response }),
                else => {},
            }
        },
        .ready => self.state = self.state, // Ready is an end state
        .error_response => self.state = self.state, // Error response is an end state
    }
}

pub const State = union(enum) {
    authenticating: Authenticator,
    querying: Query,
    ready: void,
    error_response: Message.ErrorResponse,

    pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
        const tag_name = @tagName(self);

        try writer.print("{s}", .{tag_name});

        switch (self) {
            .error_response => |error_response| {
                try writer.print(" {s}", .{error_response.response});
            },

            .authenticating => |authenticator| {
                const auth_tag_name = @tagName(authenticator.state);
                try writer.print(" {s}", .{auth_tag_name});
            },

            .querying => |current_query| {
                const query_tag_name = @tagName(current_query);
                try writer.print(" {s}", .{query_tag_name});
            },
            else => {},
        }
    }
};

// const Connection = GenericConnection(Stream);

// pub fn connect(allocator: Allocator, connect_info: ConnectInfo) !Connection {
//     return Connection.init(allocator, connect_info);
// }

// fn GenericConnection(comptime Context: type) type {
//     comptime {
//         const has_any_stream = @hasDecl(Context, "any_stream");
//         const has_open = @hasDecl(Context, "open");
//         const has_close = @hasDecl(Context, "close");

//         if (!has_any_stream and !has_open and !has_close) @compileError("Context for connection must have open, close and any_stream functions");
//     }

//     return struct {
//         allocator: Allocator,
//         stream: Context,

//         const Self = @This();

//         pub fn init(allocator: Allocator, connect_info: ConnectInfo) !Self {
//             const stream = try Context.open(allocator, connect_info);
//             errdefer stream.close();

//             return Self{
//                 .allocator = allocator,
//                 .stream = stream,
//             };
//         }
//     };
// }

// // Default implementation swapped out for testing
// const Stream = struct {
//     stream: Network.Stream,

//     pub fn open(allocator: Allocator, connect_info: ConnectInfo) !Stream {
//         const stream = try Network.tcpConnectToHost(allocator, connect_info.host, connect_info.port);
//         errdefer stream.close();

//         return .{
//             .stream = stream,
//         };
//     }

//     pub fn close(self: Stream) !void {
//         return self.close();
//     }

//     fn write(self: *const anyopaque, bytes: []const u8) !usize {
//         const ptr: *const Stream = @alignCast(@ptrCast(self));
//         return ptr.stream.write(bytes);
//     }

//     fn read(self: *const anyopaque, buffer: []u8) !usize {
//         const ptr: *const Stream = @alignCast(@ptrCast(self));
//         return ptr.stream.read(buffer);
//     }

//     pub fn any_reader(self: *const Stream) AnyReader {
//         return .{
//             .context = @ptrCast(self),
//             .readFn = &Stream.read,
//         };
//     }

//     pub fn any_writer(self: *const Stream) AnyWriter {
//         return .{
//             .context = @ptrCast(self),
//             .writeFn = &Stream.write,
//         };
//     }
// };

//     // Start authentication
//     while (true) {
//         try connection.transition();

//         switch (connection.state) {
//             .ready => break,
//             else => continue,
//         }
//     }

//     return connection;
// }

// pub fn close(self: Connection) void {
//     self.stream.close();
// }

// pub fn query(self: *Connection, statement: []const u8) !DataReader {
//     switch (self.state) {
//         .ready => {
//             self.state = State{
//                 .querying = .{
//                     .start_query = statement,
//                 },
//             };

//             try self.transition();

//             while (true) {
//                 try self.transition();

//                 switch (self.state) {
//                     .querying => |q| {
//                         switch (q) {
//                             .data_reader_ready => |data_reader| {
//                                 self.state = .{
//                                     .querying = .{
//                                         .reading_data = data_reader,
//                                     },
//                                 };

//                                 return data_reader;
//                             },
//                             else => {},
//                         }
//                     },
//                     .ready => break,
//                     .error_response => break,
//                     else => @panic("Fucks sake"),
//                 }
//             }
//         },
//         else => @panic("Protocol is not in the ready state."),
//     }

//     @panic("Protocol is not in the ready state.");
// }

// fn transition(self: *Connection) !void {
//     switch (self.state) {
//         .idle => {
//             self.state = (.{ .startup = undefined });
//         },
//         .startup => {
//             const startup_message = Message.StartupMessage{
//                 .user = self.connect_info.username,
//                 .database = self.connect_info.database,
//                 .application_name = "zig",
//             };

//             try Message.write(
//                 self.allocator,
//                 .{ .startup_message = startup_message },
//                 self.writer,
//             );

//             self.state = (.{ .authenticating = undefined });
//         },
//         .authenticating => |authenticator| {
//             const new_authenticator = try self.transition_authenticator(
//                 authenticator,
//             );

//             switch (new_authenticator) {
//                 .transition_authenticatord => self.state = (.{ .ready = undefined }),
//                 .error_response => |error_response| self.state = (.{ .error_response = error_response }),
//                 else => self.state = (.{ .authenticating = new_authenticator }),
//             }
//         },
//         .querying => |old_query| {
//             const new_query = try self.transition_query(
//                 old_query,
//             );

//             switch (new_query) {
//                 .done => self.state = (.{ .ready = undefined }),
//                 .error_response => |error_response| self.state = (.{ .error_response = error_response }),
//                 else => self.state = (.{ .querying = new_query }),
//             }
//         },
//         .ready => self.state = self.state, // Ready is an end state
//         .error_response => self.state = self.state, // Error response is an end state
//     }
// }

// fn transition_authenticator(self: *Connection, authenticator: Authenticator) !Authenticator {
//     switch (authenticator) {
//         .received_authentication => {
//             const message = try Message.read(
//                 self.allocator,
//                 self.reader,
//             );

//             switch (message) {
//                 .authentication_sasl => |authentication_sasl| {
//                     return .{ .received_sasl = authentication_sasl };
//                 },
//                 .error_response => |error_response| {
//                     return .{ .error_response = error_response };
//                 },
//                 else => @panic("Unexpected message."),
//             }
//         },

//         .received_sasl => |authentication_sasl| {
//             const sasl_initial_response = try Message.SASLInitialResponse.init(
//                 self.allocator,
//                 authentication_sasl.mechanism,
//             );

//             try Message.write(
//                 self.allocator,
//                 .{ .sasl_initial_response = sasl_initial_response },
//                 self.writer,
//             );

//             return .{ .sent_sasl_initial_response = sasl_initial_response };
//         },
//         .sent_sasl_initial_response => |sasl_initial_response| {
//             const message = try Message.read(
//                 self.allocator,
//                 self.reader,
//             );

//             switch (message) {
//                 .authentication_sasl_continue => |sasl_continue| {
//                     var new_sasl_continue = sasl_continue;

//                     new_sasl_continue.client_message = sasl_initial_response.client_message;

//                     return .{ .received_sasl_continue = new_sasl_continue };
//                 },
//                 .error_response => |error_response| {
//                     return .{ .error_response = error_response };
//                 },
//                 else => @panic("Unexpected message."),
//             }
//         },
//         .received_sasl_continue => |sasl_continue| {
//             const sasl_response = Message.SASLResponse{
//                 .nonce = sasl_continue.nonce,
//                 .salt = sasl_continue.salt,
//                 .iteration = sasl_continue.iteration,
//                 .response = sasl_continue.response,
//                 .password = self.connect_info.password,
//                 .client_first_message = sasl_continue.client_message,
//             };

//             try Message.write(
//                 self.allocator,
//                 .{ .sasl_response = sasl_response },
//                 self.writer,
//             );

//             return .{ .sent_sasl_response = sasl_response };
//         },
//         .sent_sasl_response => |sasl_response| {
//             self.allocator.free(sasl_response.nonce);
//             self.allocator.free(sasl_response.salt);
//             self.allocator.free(sasl_response.response);
//             self.allocator.free(sasl_response.client_first_message);

//             const message = try Message.read(
//                 self.allocator,
//                 self.reader,
//             );

//             switch (message) {
//                 .authentication_sasl_final => |final| {
//                     return .{ .received_sasl_final = final };
//                 },
//                 .error_response => |error_response| {
//                     return .{ .error_response = error_response };
//                 },
//                 else => @panic("Unexpected message."),
//             }
//         },
//         .received_sasl_final => |sasl_final| {
//             self.allocator.free(sasl_final.response);

//             const message = try Message.read(
//                 self.allocator,
//                 self.reader,
//             );

//             switch (message) {
//                 .authentication_ok => |ok| {
//                     return .{ .received_ok = ok };
//                 },
//                 .error_response => |error_response| {
//                     return .{ .error_response = error_response };
//                 },
//                 else => @panic("Unexpected message."),
//             }
//         },
//         .received_ok => |_| {
//             // TODO: After the auth ok a bunch of meta data gets sent atm I don't care about it but needs to be added in
//             const buffer = try self.allocator.alloc(u8, 1024);
//             defer self.allocator.free(buffer);

//             _ = try self.reader.readAtLeast(buffer, 1);

//             return .{ .transition_authenticatord = undefined };
//         },

//         else => @panic("Not yet implemented."),
//     }
// }

// fn transition_query(self: *Connection, state: Query) !Query {
//     switch (state) {
//         .start_query => |statement| {
//             const message = Message.Query{
//                 .statement = statement,
//             };

//             try Message.write(
//                 self.allocator,
//                 .{ .query = message },
//                 self.writer,
//             );

//             return .{ .received_query_response = undefined };
//         },
//         .received_query_response => {
//             const message = try Message.read(
//                 self.allocator,
//                 self.reader,
//             );

//             switch (message) {
//                 .row_description => |row_description| {
//                     return .{ .received_row_description = row_description };
//                 },

//                 .error_response => |error_response| {
//                     return .{ .error_response = error_response };
//                 },
//                 else => @panic("Unexpected message."),
//             }
//         },
//         .received_row_description => |row_description| {
//             std.log.debug("Row Desc: {any}", .{row_description});
//             row_description.deinit();

//             const data_reader = DataReader{
//                 .connection = self,
//                 .data_row = null,
//             };

//             return .{ .data_reader_ready = data_reader };
//         },
//         else => @panic("Not yet implemented."),
//     }
// }

// pub const ConnectInfo = struct {
//     host: []const u8,
//     port: u16,
//     username: []const u8,
//     database: []const u8,
//     password: []const u8,
// };

// pub const State = union(enum) {
//     idle: void,
//     startup: void,
//     authenticating: Authenticator,
//     querying: Query,
//     ready: void,
//     error_response: Message.ErrorResponse,

//     pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
//         const tag_name = @tagName(self);

//         try writer.print("{s}", .{tag_name});

//         switch (self) {
//             .error_response => |error_response| {
//                 try writer.print(" {s}", .{error_response.response});
//             },

//             .authenticating => |authenticator| {
//                 const auth_tag_name = @tagName(authenticator);
//                 try writer.print(" {s}", .{auth_tag_name});
//             },

//             .querying => |q| {
//                 const query_tag_name = @tagName(q);
//                 try writer.print(" {s}", .{query_tag_name});
//             },
//             else => {},
//         }
//     }
// };

// pub const Authenticator = union(enum) {
//     received_authentication: void,
//     received_kerberosV5: void,
//     received_clear_text_password: void,
//     received_md5_password: void,
//     received_gss: void,
//     received_sspi: void,
//     received_sasl: Message.AuthenticationSASL,
//     received_sasl_continue: Message.AuthenticationSASLContinue,
//     received_sasl_final: Message.AuthenticationSASLFinal,
//     received_ok: Message.AuthenticationOk,
//     sent_sasl_response: Message.SASLResponse,
//     sent_sasl_initial_response: Message.SASLInitialResponse,
//     transition_authenticatord: void,
//     error_response: Message.ErrorResponse,

//     pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
//         const tag_name = @tagName(self);
//         try writer.print("{s}", .{tag_name});
//     }
// };

// pub const Query = union(enum) {
//     start_query: []const u8,
//     received_query_response: void,
//     received_row_description: Message.RowDescription,
//     data_reader_ready: DataReader,
//     reading_data: DataReader,
//     error_response: Message.ErrorResponse,
//     done: void,

//     pub fn format(self: State, _: anytype, _: anytype, writer: anytype) !void {
//         const tag_name = @tagName(self);
//         try writer.print("{s}", .{tag_name});
//     }
// };

// pub const DataReader = struct {
//     connection: *Connection,
//     data_row: ?DataRow,

//     pub const State = struct {};

//     pub fn init(connection: *Connection) DataReader {
//         return DataReader{
//             .connection = connection,
//         };
//     }

//     pub fn drain(self: *DataReader) void {
//         const reader = self.connection.stream.reader().any();

//         var buffer: [256]u8 = undefined;
//         _ = reader.read(&buffer) catch return;

//         std.log.debug("HERE MUTHERFUCKER: {any}", .{buffer});
//     }

//     // returns rows affect (Not sure if it should drain too)
//     pub fn return_rows(_: *DataReader) i64 {}

//     pub fn next(self: *DataReader) !?*DataRow {
//         const reader = self.connection.stream.reader().any();

//         // Check message type
//         switch (try reader.readByte()) {
//             'D' => {
//                 const message_len = try reader.readInt(i32, .big);
//                 const columns: i16 = try reader.readInt(i16, .big);

//                 self.data_row = DataRow{
//                     .length = message_len,
//                     .columns = columns,
//                     .data_reader = self,
//                     .cursor = 0,
//                 };

//                 return &self.data_row.?;
//             },

//             else => {
//                 self.data_row = null;
//                 return null;
//             },
//         }
//     }
// };

// pub const DataRow = struct {
//     length: i32,
//     columns: i16,
//     cursor: i32,
//     data_reader: *DataReader,

//     pub fn readInt(self: *DataRow, comptime T: type) !T {
//         const reader = self.data_reader.connection.stream.reader().any();
//         const length = try reader.readInt(i32, .big);
//         const buffer = try self.data_reader.connection.allocator.alloc(u8, @intCast(length));
//         defer self.data_reader.connection.allocator.free(buffer);

//         _ = try reader.read(buffer);

//         self.cursor = self.cursor + length + 4;

//         return try std.fmt.parseInt(T, buffer, 10);
//     }

//     pub fn read(self: *DataRow, allocator: Allocator) ![]u8 {
//         const reader = self.data_reader.connection.stream.reader().any();

//         const length = try reader.readInt(i32, .big);
//         const buffer = try allocator.alloc(u8, @intCast(length));

//         _ = try reader.readAtLeast(buffer, @intCast(length));

//         self.cursor = self.cursor + length;

//         return buffer;
//     }
// };
