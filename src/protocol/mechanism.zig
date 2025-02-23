const std = @import("std");
const eql = std.mem.eql;

pub const Mechanism = enum {
    scram_sha_256,
    scram_sha_256_plus,

    pub const SCRAM_SHA_256 = "SCRAM-SHA-256";
    pub const SCRAM_SHA_256_PLUS = "SCRAM-SHA-256-PLUS";

    pub fn fromString(str: []const u8) ?Mechanism {
        if (eql(u8, str, SCRAM_SHA_256)) return .scram_sha_256;
        if (eql(u8, str, SCRAM_SHA_256_PLUS)) return .scram_sha_256_plus;

        return null;
    }

    pub fn toString(self: Mechanism) *const []const u8 {
        return switch (self) {
            .scram_sha_256 => {
                return &"SCRAM-SHA-256";
            },
            .scram_sha_256_plus => {
                return &"SCRAM-SHA-256-PLUS";
            },
        };
    }
};
