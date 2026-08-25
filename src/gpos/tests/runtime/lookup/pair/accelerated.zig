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

test "dense format 1 PairPos narrows search to one first glyph" {
    const lookup = pair.accelerated.Lookup{
        .pair_pos_records = &.{
            .{ .first = 5, .second = 7, .x_advance = -10 },
            .{ .first = 5, .second = 9, .x_advance = -20 },
            .{ .first = 7, .second = 8, .x_advance = -30 },
        },
        .pair_pos_coverage_classes = &.{
            .{ .glyph = 0, .class = 2 },
            .{ .glyph = 0, .class = 0 },
            .{ .glyph = 2, .class = 1 },
        },
    };
    const subtable = pair.accelerated.Subtable{
        .kind = .format_1_dense_x_advance,
        .coverage_start = 0,
        .coverage_len = 3,
        .class_2_start = 5,
    };

    try std.testing.expectEqual(
        @as(i16, -20),
        pair.accelerated.findDenseFormat1Record(
            &lookup,
            subtable,
            5,
            9,
        ).?.x_advance,
    );
    try std.testing.expect(pair.accelerated.findDenseFormat1Record(
        &lookup,
        subtable,
        6,
        9,
    ) == null);
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

test "accelerated PairPos switches adjacency only with an ignorable proof" {
    const lookup = pair.accelerated.Lookup{
        .coverage_groups = &.{
            .{ .glyph = 5, .subtable_indices = &.{0} },
        },
        .pair_pos_subtables = &.{.{
            .kind = .format_1_x_advance,
            .record_start = 0,
            .record_len = 1,
        }},
        .pair_pos_records = &.{.{
            .first = 5,
            .second = 7,
            .x_advance = -25,
        }},
    };
    const bytes = [_]u8{0} ** 8;
    const view = @import("../../../../table/root.zig").View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    var adjustments =
        std.ArrayList(pair.accelerated.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try pair.accelerated.collectLookup(
        view,
        0,
        1,
        &lookup,
        &.{ 5, 7 },
        &adjustments,
        std.testing.allocator,
        0,
        .{ .run_has_default_ignorables = false },
    );
    try std.testing.expectEqual(@as(i16, -25), adjustments.items[0].x_advance);

    adjustments.clearRetainingCapacity();
    const sources = [_]usize{ 0, 1, 2 };
    const codepoints = [_]u21{ 'A', 0x034f, 'B' };
    try pair.accelerated.collectLookup(
        view,
        0,
        1,
        &lookup,
        &.{ 5, 9, 7 },
        &adjustments,
        std.testing.allocator,
        0,
        .{
            .run_has_default_ignorables = true,
            .run_metadata = &.{
                .glyph_source_indices = &sources,
                .source_codepoints = &codepoints,
                .glyph_substituted = &.{ false, false, false },
            },
        },
    );
    try std.testing.expectEqual(@as(i16, -25), adjustments.items[0].x_advance);
}
