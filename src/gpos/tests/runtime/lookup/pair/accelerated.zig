//! Accelerated PairPos runtime contracts.

const std = @import("std");
const pair = @import("../../../../runtime/lookup/pair/root.zig");

test "dense PairPos accelerator distinguishes coverage holes" {
    const lookup = pair.accelerated.Lookup{
        .pair_pos_coverage_classes = &.{
            .{ .glyph = 5, .class = 1 },
            .{ .glyph = 6, .class = std.math.maxInt(u16) },
            .{ .glyph = 7, .class = 0 },
        },
        .pair_pos_class_entries = &.{
            .{ .glyph = 9, .class = 1 },
            .{ .glyph = 10, .class = 0 },
            .{ .glyph = 11, .class = 1 },
        },
        .pair_pos_class_matrix = &.{ -10, -20, -30, -12 },
    };
    const subtable = pair.accelerated.Subtable{
        .kind = .format_2_dense_x_advance,
        .record_start = 5,
        .record_len = 9,
        .coverage_start = 0,
        .coverage_len = 3,
        .class_2_start = 0,
        .class_2_len = 3,
        .class_1_count = 2,
        .class_2_count = 2,
        .matrix_start = 0,
    };

    try std.testing.expectEqual(
        @as(?i16, -12),
        pair.accelerated.denseClassAdvance(&lookup, subtable, 5, 9),
    );
    try std.testing.expectEqual(
        @as(?i16, null),
        pair.accelerated.denseClassAdvance(&lookup, subtable, 6, 9),
    );
    try std.testing.expectEqual(
        @as(?i16, -20),
        pair.accelerated.denseClassAdvance(&lookup, subtable, 7, 11),
    );
}

test "PairPos native data detection ignores generic sidecars" {
    try std.testing.expect(!pair.accelerated.hasNativeData(&.{
        .{ .kind = .generic },
    }));
    try std.testing.expect(pair.accelerated.hasNativeData(&.{
        .{ .kind = .generic },
        .{ .kind = .format_1_x_advance },
    }));
}
