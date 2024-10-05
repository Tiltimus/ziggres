# Trading Bot Development README

## Goal
The objective of this project is to create a trading bot capable of achieving an average return of 3% per day. For instance, transforming £1000 into £1030.

## Missing Components in Zig
To begin development, several components are missing in the Zig programming language. These include:
- Datetime functionality
- Websockets support
- Database Drivers (Postgres)

While there are existing implementations available for reference, it's crucial to build these functionalities from scratch to gain a deeper understanding of their inner workings.

## Trading Strategy
### Metrics and Indicators
Before implementing the trading logic, it's necessary to decide on the metrics and technical indicators to utilize. Some potential indicators to consider are:
- Moving Average Convergence Divergence (MACD)
- Relative Strength Index (RSI)
- Simple Moving Average (SMA)
- Volume-related indicators

### Trading Logic
Once the indicators are selected, it's essential to determine the conditions for buying and selling based on each indicator's signals.

### Machine Learning Approach
To enhance trading decisions, machine learning techniques will be employed. Initially, XGBoost or Random Forest Tree algorithms will be experimented with.

---

This README provides an overview of the trading bot development project, outlining the goals, missing components in Zig, proposed trading strategy, and the machine learning approach to be adopted.

### Postgres Driver TODOs

- Prepared statements
- Sanitizing inputs for normal queries
- Alternative authentication
- Listen functionality
- Insert commands 
- Properly closing the connection not just force closing
- Correctly drain if in a data_row / data_reader state and another query is called
- Write tests

### DEAD CODE BUT DON'T WANT TO DELETE ###

// const std = @import("std");
// const Datetime = @import("time.zig").Datetime;
// const Allocator = std.mem.Allocator;
// const Client = std.http.Client;
// const json = std.json;
// const Uri = std.Uri;
// const assert = std.debug.assert;
// const GET = std.http.Method.GET;

// const BASE_URL = "https://data.alpaca.markets";

// const BARS_URL = BASE_URL ++ "/v2/stocks/bars?symbols={s}&timeframe=1Min&start=2000-01-03T00%3A00%3A00Z&end=2024-01-04T00%3A00%3A00Z&limit=10000&adjustment=raw&feed=sip&sort=asc&page_token={s}";

// pub const DataProvider = struct {
//     allocator: Allocator,
//     key: []const u8 = "AKNHCS4XLCCXYA42LAC5",
//     secret: []const u8 = "BDdzz9jPzcYvR7Whg6aec2MmLYlc2OunFH0A5C03",
//     http_client: Client = undefined,

//     pub fn init(allocator: Allocator) DataProvider {
//         return DataProvider{
//             .allocator = allocator,
//             .http_client = Client{ .allocator = allocator },
//         };
//     }

//     pub fn deinit(self: *DataProvider) void {
//         self.http_client.deinit();
//     }

//     pub fn candles(self: *DataProvider, options: CandleRequestOptions) !CandleIterator {
//         return CandleIterator{
//             .http_client = &self.http_client,
//             .allocator = self.allocator,
//             .options = options,
//         };
//     }

// pub fn fetch_and_flush_candles(self: *DataProvider, ticker: []const u8, out: []const u8) !void {
//     var file = try std.fs.cwd().openFile(out, .{ .mode = .write_only });
//     defer file.close();

//     var writer = std.json.writeStreamArbitraryDepth(self.allocator, file.writer(), .{});
//     defer writer.deinit();

//     var next_page: ?[]const u8 = null;

//     try writer.beginArray();

//     request_loop: while (true) {
//         var request = try self.http_get_candles(ticker, next_page);
//         defer request.deinit();

//         var reader = std.json.reader(self.allocator, request.reader());
//         defer reader.deinit();

//         // Just used the next_page free to then check if there is a next one
//         if (next_page) |page| self.allocator.free(page);

//         next_page = try parse_candles(self.allocator, &reader, &writer);

//         if (next_page != null) continue :request_loop;

//         break;
//     }

//     try writer.endArray();
// }

// fn http_get_candles(self: *DataProvider, ticker: []const u8, page: ?[]const u8) !std.http.Client.Request {
//     var server_header_buffer: [16 * 1024]u8 = undefined;

//     const headers = [_]std.http.Header{
//         .{ .name = "APCA-API-KEY-ID", .value = self.key },
//         .{ .name = "APCA-API-SECRET-KEY", .value = self.secret },
//         .{ .name = "accept", .value = "application/json" },
//     };

//     const request_options = std.http.Client.RequestOptions{
//         .extra_headers = &headers,
//         .server_header_buffer = &server_header_buffer,
//     };

//     const url = try std.fmt.allocPrint(
//         self.allocator,
//         BARS_URL,
//         .{ ticker, page orelse "" },
//     );
//     defer self.allocator.free(url);

//     self.uri = try std.Uri.parse(url);

//     var request = try self.http_client.open(
//         GET,
//         self.uri,
//         request_options,
//     );

//     try request.send();
//     try request.finish();
//     try request.wait();

//     return request;
// }

// fn parse_candles(allocator: Allocator, reader: anytype, writer: anytype) !?[]const u8 {
//     while (try reader.*.peekNextTokenType() != .end_of_document) {
//         const nextToken = try reader.*.next();

//         switch (nextToken) {
//             .string => |value| {
//                 if (std.mem.eql(u8, value, "next_page_token")) {
//                     const pageToken = try reader.*.next();

//                     switch (pageToken) {
//                         .string => |pageValue| {
//                             return try allocator.dupe(u8, pageValue);
//                         },
//                         else => return null,
//                     }
//                 }
//             },

//             .array_begin => {
//                 candle_loop: while (true) {
//                     if (try reader.*.peekNextTokenType() == .array_end) break;

//                     const candle = try std.json.innerParse(
//                         Candle,
//                         allocator,
//                         reader,
//                         .{ .ignore_unknown_fields = true, .max_value_len = 1024 * 100 },
//                     );

//                     try writer.*.write(candle);
//                     continue :candle_loop;
//                 }
//             },
//             else => {},
//         }
//     }

//     return null;
// }
// };

// pub const Reader = std.json.Reader(std.json.default_buffer_size, std.http.Client.Request.Reader);

// pub const CandleIterator = struct {
//     http_client: *Client,
//     request: ?CandleRequest = null,
//     reader: ?Reader = null,
//     allocator: Allocator,
//     request_count: u8 = 0,
//     candle_count: usize = 0,
//     options: CandleRequestOptions,
//     state: State = .start,

//     const State = enum {
//         start,
//         ready_to_parse,
//         end,
//     };

//     pub fn next(self: *CandleIterator) !?Candle {
//         switch (self.state) {
//             .start => {
//                 var request = try CandleRequest.send(self.allocator, self.http_client, self.options);
//                 var reader = std.json.reader(self.allocator, request.reader());

//                 // Move the reader to start parsing candles
//                 find_start_array: while (true) {
//                     const token = try reader.next();

//                     switch (token) {
//                         .array_begin => break,
//                         else => continue :find_start_array,
//                     }
//                 }

//                 self.request = request;
//                 self.reader = reader;
//                 self.request_count += 1;
//                 self.state = .ready_to_parse;
//                 self.candle_count += 1;

//                 return try Candle.parse(self.allocator, &reader);
//             },

//             .ready_to_parse => {
//                 assert(self.reader != null);

//                 if (self.reader) |*reader| {
//                     // Check we are not at the end of the array
//                     const peeked = try reader.peekNextTokenType();

//                     if (peeked == .array_end) {
//                         // Look for next_page entry if no next page then we are done
//                         next_page_token_loop: while (true) {
//                             const token = try reader.next();

//                             switch (token) {
//                                 .string => |value| {
//                                     if (std.mem.eql(u8, value, "next_page_token")) {
//                                         const page_token = try reader.next();

//                                         switch (page_token) {
//                                             .string => |next_page| {
//                                                 // Copy the next_page as we are going to be doing another request
//                                                 // The clean up will wipe the next_page if we don't dupe
//                                                 self.options.next_page = try self.allocator.dupe(u8, next_page);

//                                                 // Cleanup previous request and reader to allow do new reader
//                                                 if (self.request) |*request| request.deinit();
//                                                 reader.deinit();

//                                                 var request = try CandleRequest.send(self.allocator, self.http_client, self.options);
//                                                 var next_reader = std.json.reader(self.allocator, request.reader());

//                                                 // Move the reader to start parsing candles
//                                                 find_start_array: while (true) {
//                                                     const inner_token = try next_reader.next();

//                                                     switch (inner_token) {
//                                                         .array_begin => break,
//                                                         else => continue :find_start_array,
//                                                     }
//                                                 }

//                                                 self.request = request;
//                                                 self.reader = next_reader;
//                                                 self.request_count += 1;
//                                                 self.state = .ready_to_parse;
//                                                 self.candle_count += 1;

//                                                 return try Candle.parse(self.allocator, &next_reader);
//                                             },
//                                             .partial_string => |partial_page| {
//                                                 const next_partial_string = try reader.next();

//                                                 switch (next_partial_string) {
//                                                     .string => |rest| {
//                                                         // Copy the next_page as we are going to be doing another request
//                                                         // The clean up will wipe the next_page if we don't dupe
//                                                         self.options.next_page = try self.allocator.dupe(u8, try std.mem.concat(self.allocator, u8, &[_][]const u8{ partial_page, rest }));

//                                                         // Cleanup previous request and reader to allow do new reader
//                                                         if (self.request) |*request| request.deinit();
//                                                         reader.deinit();

//                                                         var request = try CandleRequest.send(self.allocator, self.http_client, self.options);
//                                                         var next_reader = std.json.reader(self.allocator, request.reader());

//                                                         // Move the reader to start parsing candles
//                                                         find_start_array: while (true) {
//                                                             const inner_token = try next_reader.next();

//                                                             switch (inner_token) {
//                                                                 .array_begin => break,
//                                                                 else => continue :find_start_array,
//                                                             }
//                                                         }

//                                                         self.request = request;
//                                                         self.reader = next_reader;
//                                                         self.request_count += 1;
//                                                         self.state = .ready_to_parse;
//                                                         self.candle_count += 1;

//                                                         return try Candle.parse(self.allocator, &next_reader);
//                                                     },
//                                                     else => unreachable,
//                                                 }
//                                             },

//                                             // There is no next page thus we are done
//                                             .null => {
//                                                 self.state = .end;
//                                                 return null;
//                                             },
//                                             else => unreachable,
//                                         }
//                                     }
//                                 },
//                                 else => continue :next_page_token_loop,
//                             }
//                         }
//                     }

//                     self.candle_count += 1;
//                     return try Candle.parse(self.allocator, reader);
//                 }

//                 unreachable;
//             },
//             .end => {
//                 // Dealloc request ?
//                 return null;
//             },
//         }
//     }
// };

// pub const CandleRequest = struct {
//     request: std.http.Client.Request,
//     reader: std.http.Client.Request.Reader,
//     uri: Uri,

//     pub fn deinit(self: *CandleRequest) void {
//         self.request.deinit();
//     }

//     pub fn reader(self: *CandleRequest) std.http.Client.Request.Reader {
//         return self.reader;
//     }

//     pub fn send(allocator: Allocator, client: *Client, options: CandleRequestOptions) !CandleRequest {
//         var server_header_buffer: [16 * 1024]u8 = undefined;

//         const headers = [_]std.http.Header{
//             .{ .name = "APCA-API-KEY-ID", .value = options.key },
//             .{ .name = "APCA-API-SECRET-KEY", .value = options.secret },
//             .{ .name = "accept", .value = "application/json" },
//         };

//         const request_options = std.http.Client.RequestOptions{
//             .extra_headers = &headers,
//             .server_header_buffer = &server_header_buffer,
//         };

//         const url = try std.fmt.allocPrint(
//             allocator,
//             BARS_URL,
//             .{ options.symbol, options.next_page orelse "" },
//         );
//         defer allocator.free(url);

//         const uri = try std.Uri.parse(url);

//         var request = try client.*.open(
//             GET,
//             uri,
//             request_options,
//         );

//         try request.send();
//         try request.finish();
//         try request.wait();

//         return CandleRequest{
//             .uri = uri,
//             .request = request,
//             .reader = request.reader(),
//         };
//     }
// };

// const Candle = struct {
//     c: f32,
//     h: f32,
//     l: f32,
//     n: f32,
//     o: f32,
//     t: Datetime,
//     v: u64,
//     vw: f32,

//     fn parse(allocator: Allocator, reader: anytype) !Candle {
//         return try std.json.innerParse(
//             Candle,
//             allocator,
//             reader,
//             .{
//                 .ignore_unknown_fields = true,
//                 .max_value_len = 1024 * 50,
//             },
//         );
//     }
// };

// const TimeFrame = union {
//     minute: u16,
//     hour: u16,
//     day: void,
//     week: void,
//     month: u16,
// };

// const Sort = enum {
//     asc,
//     desc,
// };

// pub const CandleRequestOptions = struct {
//     symbol: []const u8,
//     timeframe: TimeFrame = TimeFrame{ .minute = 1 },
//     start_date: ?Datetime = null,
//     end_date: ?Datetime = null,
//     limit: u16 = 10000,
//     sort: Sort = .asc,
//     secret: []const u8,
//     key: []const u8,
//     next_page: ?[]const u8 = null,
// };

const std = @import("std");
const Datetime = @import("datetime.zig").Datetime;
const Timeframe = @import("datetime.zig").Timeframe;
const Allocator = std.mem.Allocator;
const Client = std.http.Client;
const Uri = std.Uri;
const GET = std.http.Method.GET;

const Sort = enum {
    ASC,
    DESC,
};

pub const CandleRequestOptions = struct {
    symbol: []const u8,
    timeframe: Timeframe = .{ .minute = 1 },
    start_date: Datetime,
    end_date: Datetime,
    limit: u16 = 10000,
    sort: Sort = .ASC,
    secret: []const u8,
    key: []const u8,
    next_page: ?[]const u8 = null,
};

const CandleService = struct {
    context: *const anyopaque,
    sendFn: *const fn (context: *const anyopaque, args: i32) anyerror!i32,

    pub const Error = anyerror;

    pub fn send(self: CandleService, args: i32) anyerror!i32 {
        return self.sendFn(self.context, args);
    }
};

const ExampleService = struct {
    service: CandleService,
};

// const CandleRequest = union(enum) {
//     alpaca: AlpacaCandleRequest,

//     pub fn send()

// };

// const AlpacaCandleRequest = struct {
//     request: std.http.Client.Request,
//     reader: std.http.Client.Request.Reader,
//     uri: Uri,

//     const BASE_URL = "https://data.alpaca.markets";
//     const BARS_URL = BASE_URL ++ "/v2/stocks/bars?symbols={s}&timeframe=1Min&start=2000-01-03T00%3A00%3A00Z&end=2024-01-04T00%3A00%3A00Z&limit=10000&adjustment=raw&feed=sip&sort=asc&page_token={s}";

//     pub fn deinit(self: *CandleRequest) void {
//         self.request.deinit();
//     }

//     pub fn reader(self: *CandleRequest) std.http.Client.Request.Reader {
//         return self.reader;
//     }

//     pub fn send(allocator: Allocator, client: *Client, options: CandleRequestOptions) !CandleRequest {
//         var server_header_buffer: [16 * 1024]u8 = undefined;

//         const headers = [_]std.http.Header{
//             .{ .name = "APCA-API-KEY-ID", .value = options.key },
//             .{ .name = "APCA-API-SECRET-KEY", .value = options.secret },
//             .{ .name = "accept", .value = "application/json" },
//         };

//         const request_options = std.http.Client.RequestOptions{
//             .extra_headers = &headers,
//             .server_header_buffer = &server_header_buffer,
//         };

//         const url = try std.fmt.allocPrint(
//             allocator,
//             BARS_URL,
//             .{ options.symbol, options.next_page orelse "" },
//         );
//         defer allocator.free(url);

//         const uri = try std.Uri.parse(url);

//         var request = try client.*.open(
//             GET,
//             uri,
//             request_options,
//         );

//         try request.send();
//         try request.finish();
//         try request.wait();

//         return CandleRequest{
//             .uri = uri,
//             .request = request,
//             .reader = request.reader(),
//         };
//     }
// };

// pub const CandleRequest = struct {
//     request: std.http.Client.Request,
//     reader: std.http.Client.Request.Reader,
//     uri: Uri,

//     pub fn deinit(self: *CandleRequest) void {
//         self.request.deinit();
//     }

//     pub fn reader(self: *CandleRequest) std.http.Client.Request.Reader {
//         return self.reader;
//     }

//     pub fn send(allocator: Allocator, client: *Client, options: CandleRequestOptions) !CandleRequest {
//         var server_header_buffer: [16 * 1024]u8 = undefined;

//         const headers = [_]std.http.Header{
//             .{ .name = "APCA-API-KEY-ID", .value = options.key },
//             .{ .name = "APCA-API-SECRET-KEY", .value = options.secret },
//             .{ .name = "accept", .value = "application/json" },
//         };

//         const request_options = std.http.Client.RequestOptions{
//             .extra_headers = &headers,
//             .server_header_buffer = &server_header_buffer,
//         };

//         const url = try std.fmt.allocPrint(
//             allocator,
//             BARS_URL,
//             .{ options.symbol, options.next_page orelse "" },
//         );
//         defer allocator.free(url);

//         const uri = try std.Uri.parse(url);

//         var request = try client.*.open(
//             GET,
//             uri,
//             request_options,
//         );

//         try request.send();
//         try request.finish();
//         try request.wait();

//         return CandleRequest{
//             .uri = uri,
//             .request = request,
//             .reader = request.reader(),
//         };
//     }
// };
