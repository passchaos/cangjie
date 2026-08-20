//! UAX #50 vertical orientation policy and compatibility presentation forms.

const data = @import("vertical_data.zig");

pub const Orientation = enum {
    upright,
    rotated,
    transformed_upright,
    transformed_rotated,
};

pub const unicode_version = "17.0.0";

/// Return the complete Unicode 17 `Vertical_Orientation` value for one scalar.
///
/// Unicode assigns R by default. The generated table therefore stores only
/// U/Tu/Tr ranges and keeps the common rotated lookup as a compact miss.
pub fn orientation(codepoint: u21) Orientation {
    var low: usize = 0;
    var high: usize = data.ranges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const range = data.ranges[middle];
        if (codepoint < range.start) {
            high = middle;
        } else if (codepoint > range.end) {
            low = middle + 1;
        } else {
            return switch (range.value) {
                .upright => .upright,
                .transformed_upright => .transformed_upright,
                .transformed_rotated => .transformed_rotated,
            };
        }
    }
    return .rotated;
}

pub fn presentationCodepoint(codepoint: u21) ?u21 {
    return switch (codepoint) {
        0x2013 => 0xfe32,
        0x2014 => 0xfe31,
        0x2025 => 0xfe30,
        0x2026 => 0xfe19,
        0x3001 => 0xfe11,
        0x3002 => 0xfe12,
        0x3008 => 0xfe3f,
        0x3009 => 0xfe40,
        0x300a => 0xfe3d,
        0x300b => 0xfe3e,
        0x300c => 0xfe41,
        0x300d => 0xfe42,
        0x300e => 0xfe43,
        0x300f => 0xfe44,
        0x3010 => 0xfe3b,
        0x3011 => 0xfe3c,
        0x3014 => 0xfe39,
        0x3015 => 0xfe3a,
        0x3016 => 0xfe17,
        0x3017 => 0xfe18,
        0xfe4f => 0xfe34,
        0xff01 => 0xfe15,
        0xff08 => 0xfe35,
        0xff09 => 0xfe36,
        0xff0c => 0xfe10,
        0xff1a => 0xfe13,
        0xff1b => 0xfe14,
        0xff1f => 0xfe16,
        else => null,
    };
}

test "Unicode 17 vertical orientation table is ordered and complete" {
    const std = @import("std");

    try std.testing.expectEqual(@as(usize, 2470), data.source_range_count);
    try std.testing.expectEqual(data.explicit_range_count, data.ranges.len);

    var previous_end: ?u21 = null;
    for (data.ranges) |range| {
        try std.testing.expect(range.start <= range.end);
        if (previous_end) |end| {
            try std.testing.expect(end < range.start);
        }
        previous_end = range.end;
    }

    var counts = [_]usize{0} ** 4;
    for (0..0x110000) |raw| {
        const value = orientation(@intCast(raw));
        counts[@intFromEnum(value)] += 1;
    }
    try std.testing.expectEqual(data.upright_count, counts[0]);
    try std.testing.expectEqual(data.rotated_count, counts[1]);
    try std.testing.expectEqual(data.transformed_upright_count, counts[2]);
    try std.testing.expectEqual(data.transformed_rotated_count, counts[3]);
    try std.testing.expectEqual(
        @as(usize, 0x110000),
        counts[0] + counts[1] + counts[2] + counts[3],
    );
}
