// -----------------------------------------------------------------------------
// File         : parser.zig
// Author       : Warrick Pardoe
// Date         : April 12, 2024
// Description  : This module provides a utility for parsing byte sequences,
//                offering methods for data extraction and manipulation.
// License      : This code is distributed under the MIT License. See the LICENSE
//                file for details.
// Contact      : For questions or feedback, please contact Warrick Pardoe at
//                warrick.pardoe2@hotmail.co.uk.
// Dependencies : This module depends on the `std.unicode` module for UTF-8
//                encoding and decoding.
//
// Usage:
// - Initialize a parser with the `init` function, passing a byte slice as input.
// - Use various methods such as `take`, `skip`, `peek`, `number`, etc., to
//   manipulate and extract data from the input.
// -----------------------------------------------------------------------------

const std = @import("std");

/// Parser represents a utility for parsing byte sequences, providing various methods
/// for extracting and manipulating data.
///
/// The parser maintains an internal state including the current position within
/// the input buffer and an iterator for processing UTF-8 encoded data.
///
/// # Example
///
/// ```
/// const parser = try Parser.init("hello world");
///
/// const sliced = parser.take(5); // Returns "hello"
/// const nextChar = parser.char(); // Returns ' '
/// ```
///
/// # Safety
///
/// The `Parser` struct assumes that the input byte slice is a valid UTF-8 encoded
/// sequence. Incorrectly encoded data may lead to unexpected behavior.
pub const Parser = struct {
    buf: []const u8,
    pos: usize = 0,
    iter: std.unicode.Utf8Iterator = undefined,

    /// Initializes a new parser instance with the provided input byte slice.
    ///
    /// # Errors
    ///
    /// Returns an error if the input byte slice cannot be converted into a valid UTF-8 view.
    ///
    /// # Example
    ///
    /// ```
    /// const parser = try Parser.init("hello world");
    /// ```
    pub fn init(input: []const u8) !Parser {
        const view = try std.unicode.Utf8View.init(input);

        return Parser{
            .buf = input,
            .iter = view.iterator(),
        };
    }

    /// This function retrieves a slice of bytes from the input buffer starting from
    /// the current position of the parser and extending `size` bytes forward. The
    /// parser's internal position is updated accordingly. Not if the size goes past the
    /// length of the buffer input it will consume the rest of the input.
    ///
    /// # Example
    ///
    /// ```
    /// const parser = try Parser.init("hello world");
    /// const slice = parser.take(5); // hello
    /// ```
    pub fn take(self: *Parser, size: usize) []const u8 {
        const upper = self.pos + size;

        if (upper <= self.buf.len) {
            const buf = self.buf[self.pos..upper];
            self.iter.i += size;
            self.pos += size;
            return buf;
        }

        return self.buf[self.pos..self.buf.len];
    }

    /// Skips `amount` elements in the parser's iteration and updates the position accordingly.
    ///
    /// - Parameter amount: The number of elements to skip.
    ///
    /// # Example
    ///
    /// ```
    /// const parser = try Parser.init("hello world");
    /// const slice = parser.skip(6);
    /// const take_slice = parser.take(5); // world
    /// ```
    pub fn skip(self: *Parser, amount: usize) void {
        self.pos = self.pos + amount;
        self.iter.i = self.iter.i + amount;
    }

    /// Returns the n-th next character or null if that's past the end
    ///
    /// # Example
    ///
    /// ```
    /// const parser = try Parser.init("hello world");
    /// const peeked = parser.peek(0); // e;
    /// ```
    pub fn peek(self: *Parser, n: usize) ?u21 {
        const original_i = self.iter.i;
        defer self.iter.i = original_i;

        var i: usize = 0;
        var code_point: ?u21 = null;
        while (i <= n) : (i += 1) {
            code_point = self.iter.nextCodepoint();
            if (code_point == null) return null;
        }
        return code_point;
    }

    /// Returns a decimal number or null if the current character is not a digit
    ///
    /// # Example
    ///
    /// ```
    /// const parser = try Parser.init("100-000");
    /// const number = parser.number(); // 100
    /// ```
    pub fn number(self: *Parser) ?usize {
        var r: ?usize = null;

        while (self.peek(0)) |code_point| {
            switch (code_point) {
                '0'...'9' => {
                    if (r == null) r = 0;
                    r.? *= 10;
                    r.? += code_point - '0';
                },
                else => break,
            }
            _ = self.iter.nextCodepoint();
        }

        return r;
    }

    /// Returns a substring of the input starting from the current position
    /// and ending where `ch` is found or until the end if not found
    ///
    /// # Example
    ///
    /// ```
    /// const parser = Parser.init("100-100-100");
    /// const slice = parser.unitl('-') // "100"
    /// ```
    pub fn until(self: *Parser, ch: u21) []const u8 {
        const start_position = self.pos;
        var end_position = self.pos;

        while (self.peek(0)) |code_point| {
            if (code_point == ch) break; // Break when we first hit the character we want
            if (end_position == self.buf.len) break; // Break if we hit the end of the input

            end_position += 1;
            self.pos += 1;
            self.iter.i += 1;
        }

        return self.buf[start_position..end_position];
    }

    /// Returns one character, if available
    ///
    /// # Example
    ///
    /// ```
    /// const parser = Parser.init("hello world");
    /// const char = parser.char(); // 'h'
    /// ```
    pub fn char(self: *Parser) ?u21 {
        if (self.iter.nextCodepoint()) |code_point| {
            self.pos = self.iter.i;
            return code_point;
        }
        return null;
    }
    /// Checks if the next character in the parser's iteration matches the specified value,
    /// consuming it if it does.
    ///
    /// This function peeks at the next character in the parser's iteration and compares it
    /// with the provided value `val`. If the next character matches `val`, it consumes
    /// the character and returns `true`. Otherwise, it returns `false`.
    ///
    /// # Parameters
    ///
    /// - `val`: The character value to compare against the next character in the iteration.
    ///
    /// # Returns
    ///
    /// Returns `true` if the next character matches `val` and is consumed; otherwise, returns `false`.
    ///
    /// # Example
    ///
    /// ```
    /// var parser = try Parser.init("100-100-100");
    ///
    /// // Check if the next character is '1' and consume it
    /// if (parser.maybe('1')) {
    ///     // Character '1' was found and consumed
    /// } else {
    ///     // Character '1' was not found
    /// }
    /// ```
    pub fn maybe(self: *Parser, val: u21) bool {
        if (self.peek(0) == val) {
            _ = self.iter.nextCodepoint();
            self.pos = self.iter.i;
            return true;
        }
        return false;
    }
};

test "take" {
    var parser = try Parser.init("hello world");

    try std.testing.expectEqualSlices(u8, "hello", parser.take(5));
    try std.testing.expectEqual(5, parser.pos);
    try std.testing.expectEqual(5, parser.iter.i);
    try std.testing.expectEqualSlices(u8, " world", parser.take(100));
}

test "skip" {
    var parser = try Parser.init("hello world");

    parser.skip(6);

    try std.testing.expectEqualSlices(u8, "world", parser.take(5));
}

test "peek" {
    var parser = try Parser.init("100-100-100");
    const peeked = parser.peek(1);

    try std.testing.expectEqual('0', peeked);
}

test "number" {
    var parser = try Parser.init("100-100-100");

    try std.testing.expectEqual(100, parser.number());
}

test "unitl" {
    var parser = try Parser.init("100-100-100");

    try std.testing.expectEqualSlices(u8, "100", parser.until('-'));
    try std.testing.expectEqualSlices(u8, "-", parser.take(1));
    try std.testing.expectEqualSlices(u8, "100", parser.until('-'));
    try std.testing.expectEqualSlices(u8, "-", parser.take(1));
    try std.testing.expectEqualSlices(u8, "100", parser.until('-'));
}

test "char" {
    var parser = try Parser.init("100-100-100");

    try std.testing.expectEqual('1', parser.char());
    try std.testing.expectEqualSlices(u8, "00", parser.take(2));
    try std.testing.expectEqual('-', parser.char());
    try std.testing.expectEqualSlices(u8, "100", parser.until('-'));
}

test "maybe" {
    var parser = try Parser.init("100-100-100");

    try std.testing.expect(parser.maybe('1'));
    try std.testing.expect(parser.maybe('0'));
}
