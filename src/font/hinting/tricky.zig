//! FreeType-compatible classification of legacy "tricky" TrueType faces.
//!
//! These fonts depend on classic grid fitting and therefore bypass v40
//! backward-compatibility suppression. The list mirrors FreeType's current
//! family-name patterns and cvt/fpgm/prep signatures.

const std = @import("std");

pub const TableId = struct {
    checksum: u32,
    length: usize,
};

pub fn familyMatches(family: []const u8) bool {
    const untagged = if (family.len > 7 and
        family[6] == '+' and
        allAsciiUpper(family[0..6]))
        family[7..]
    else
        family;
    for (family_patterns) |pattern| {
        if (std.mem.indexOf(u8, untagged, pattern) != null) return true;
    }
    return false;
}

pub fn sfntIdsMatch(ids: [3]?TableId) bool {
    for (sfnt_ids) |candidate| {
        var matched = true;
        for (ids, candidate) |actual, expected| {
            if (actual) |value| {
                if (value.checksum != expected.checksum or
                    value.length != expected.length)
                {
                    matched = false;
                    break;
                }
            } else if (expected.length != 0) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

fn allAsciiUpper(value: []const u8) bool {
    for (value) |byte| {
        if (byte < 'A' or byte > 'Z') return false;
    }
    return true;
}

const family_patterns = [_][]const u8{
    "cpop",
    "DFGirl-W6-WIN-BF",
    "DFGothic-EB",
    "DFGyoSho-Lt",
    "DFHei",
    "DFHSGothic-W5",
    "DFHSMincho-W3",
    "DFHSMincho-W7",
    "DFKaiSho-SB",
    "DFKaiShu",
    "DFKai-SB",
    "DFMing",
    "DLC",
    "HuaTianKaiTi?",
    "HuaTianSongTi?",
    "Ming(for ISO10646)",
    "MingLiU",
    "MingMedium",
    "PMingLiU",
    "MingLi43",
};

const sfnt_ids = [_][3]TableId{
    .{
        .{ .checksum = 0x05bcf058, .length = 0x2e4 },
        .{ .checksum = 0x28233bf1, .length = 0x87c4 },
        .{ .checksum = 0xa344a1ea, .length = 0x1e1 },
    },
    .{
        .{ .checksum = 0x05bcf058, .length = 0x2e4 },
        .{ .checksum = 0x28233bf1, .length = 0x87c4 },
        .{ .checksum = 0xa344a1eb, .length = 0x1e1 },
    },
    .{
        .{ .checksum = 0x12c3ebb2, .length = 0x350 },
        .{ .checksum = 0xb680ee64, .length = 0x87a7 },
        .{ .checksum = 0xce939563, .length = 0x758 },
    },
    .{
        .{ .checksum = 0x11e5ead4, .length = 0x350 },
        .{ .checksum = 0xce5956e9, .length = 0xbc85 },
        .{ .checksum = 0x8272f416, .length = 0x45 },
    },
    .{
        .{ .checksum = 0x1257eb46, .length = 0x350 },
        .{ .checksum = 0xf699d160, .length = 0x715f },
        .{ .checksum = 0xd222f568, .length = 0x3bc },
    },
    .{
        .{ .checksum = 0x1262eb4e, .length = 0x350 },
        .{ .checksum = 0xe86a5d64, .length = 0x7940 },
        .{ .checksum = 0x7850f729, .length = 0x5ff },
    },
    .{
        .{ .checksum = 0x122deb0a, .length = 0x350 },
        .{ .checksum = 0x3d16328a, .length = 0x859b },
        .{ .checksum = 0xa93fc33b, .length = 0x2cb },
    },
    .{
        .{ .checksum = 0x125feb26, .length = 0x350 },
        .{ .checksum = 0xa5acc982, .length = 0x7ee1 },
        .{ .checksum = 0x90999196, .length = 0x41f },
    },
    .{
        .{ .checksum = 0x11e5ead4, .length = 0x350 },
        .{ .checksum = 0x5a30ca3b, .length = 0x9063 },
        .{ .checksum = 0x13a42602, .length = 0x7e },
    },
    .{
        .{ .checksum = 0x11e5ead4, .length = 0x350 },
        .{ .checksum = 0xa6e78c01, .length = 0x8998 },
        .{ .checksum = 0x13a42602, .length = 0x7e },
    },
    .{
        .{ .checksum = 0x11e5ead4, .length = 0x360 },
        .{ .checksum = 0x9db282b2, .length = 0xc06e },
        .{ .checksum = 0x53e6d7ca, .length = 0x82 },
    },
    .{
        .{ .checksum = 0x1243eb18, .length = 0x350 },
        .{ .checksum = 0xba0a8c30, .length = 0x74ad },
        .{ .checksum = 0xf3d83409, .length = 0x37b },
    },
    .{
        .{ .checksum = 0x07dcf546, .length = 0x308 },
        .{ .checksum = 0x40fe7c90, .length = 0x8e2a },
        .{ .checksum = 0x608174b5, .length = 0x7a },
    },
    .{
        .{ .checksum = 0xeb891238, .length = 0x308 },
        .{ .checksum = 0xd2e4dcd4, .length = 0x676f },
        .{ .checksum = 0x8ea5f293, .length = 0x3b8 },
    },
    .{
        .{ .checksum = 0xfffbfffc, .length = 8 },
        .{ .checksum = 0x9c9e48b8, .length = 0xbea2 },
        .{ .checksum = 0x70020112, .length = 8 },
    },
    .{
        .{ .checksum = 0xfffbfffc, .length = 8 },
        .{ .checksum = 0x0a5a0483, .length = 0x17c39 },
        .{ .checksum = 0x70020112, .length = 8 },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x40c92555, .length = 0xe5 },
        .{ .checksum = 0xa39b58e3, .length = 0x117c },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x33c41652, .length = 0xe5 },
        .{ .checksum = 0x26d6c52a, .length = 0xf6a },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x6db1651d, .length = 0x19d },
        .{ .checksum = 0x6c6e4b03, .length = 0x2492 },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x40c92555, .length = 0xe5 },
        .{ .checksum = 0xde51fad0, .length = 0x117c },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x85e47664, .length = 0xe5 },
        .{ .checksum = 0xa6c62831, .length = 0x1caa },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x2d891cfd, .length = 0x19d },
        .{ .checksum = 0xa0604633, .length = 0x1de8 },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x40aa774c, .length = 0x1cb },
        .{ .checksum = 0x9b5caa96, .length = 0x1f9a },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x0d3de9cb, .length = 0x141 },
        .{ .checksum = 0xd4127766, .length = 0x2280 },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x4a692698, .length = 0x1f0 },
        .{ .checksum = 0x340d4346, .length = 0x1fca },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0xcd34c604, .length = 0x166 },
        .{ .checksum = 0x6cf31046, .length = 0x22b0 },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0x5da75315, .length = 0x19d },
        .{ .checksum = 0x40745a5f, .length = 0x22e0 },
    },
    .{
        .{ .checksum = 0, .length = 0 },
        .{ .checksum = 0xf055fc48, .length = 0x1c2 },
        .{ .checksum = 0x3900ded3, .length = 0x1e18 },
    },
    .{
        .{ .checksum = 0x00170003, .length = 0x60 },
        .{ .checksum = 0xdbb4306e, .length = 0x58aa },
        .{ .checksum = 0xd643482a, .length = 0x35 },
    },
    .{
        .{ .checksum = 0x1269eb58, .length = 0x350 },
        .{ .checksum = 0x5cd5957a, .length = 0x6a4e },
        .{ .checksum = 0xf758323a, .length = 0x380 },
    },
    .{
        .{ .checksum = 0x122feb0b, .length = 0x350 },
        .{ .checksum = 0x7f10919a, .length = 0x70a9 },
        .{ .checksum = 0x7cd7e7b7, .length = 0x25c },
    },
};

test "FreeType tricky identity recognizes names and complete signatures" {
    try std.testing.expectEqual(@as(usize, 20), family_patterns.len);
    try std.testing.expectEqual(@as(usize, 31), sfnt_ids.len);
    try std.testing.expect(familyMatches("ABCDEF+MingLiU"));
    try std.testing.expect(!familyMatches("Cangjie Sans"));
    try std.testing.expect(sfntIdsMatch(.{
        .{ .checksum = 0x05bcf058, .length = 0x2e4 },
        .{ .checksum = 0x28233bf1, .length = 0x87c4 },
        .{ .checksum = 0xa344a1ea, .length = 0x1e1 },
    }));
}
