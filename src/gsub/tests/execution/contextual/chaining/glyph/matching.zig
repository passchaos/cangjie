//! ChainContextSubst format-1 three-region matching contracts.

const std = @import("std");
const glyph_chaining =
    @import("../../../../../execution/contextual/chaining/glyph/root.zig");
const model = @import("../../../../../execution/contextual/model.zig");
const fixture = @import("fixture.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const cluster_safety = @import("../../../../../../shaping/cluster_safety.zig");
const table = @import("../../../../../table/root.zig");

const Executor = struct {
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        _: std.mem.Allocator,
        _: Options,
    ) !model.Change {
        glyphs.items[target] += lookup_index + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "glyph chaining tries rules in order across ignored glyphs and marks all regions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;
    fixture.writeSubtable(&bytes, 0, 2, &.{
        .{
            .backtrack = &.{1},
            .input = &.{ 2, 8 },
            .lookahead = &.{4},
            .records = &.{.{ .sequence_index = 1, .lookup_index = 1 }},
        },
        .{
            .backtrack = &.{1},
            .input = &.{ 2, 3 },
            .lookahead = &.{4},
            .records = &.{.{ .sequence_index = 1, .lookup_index = 5 }},
        },
    });

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 9, 2, 9, 3, 9, 4 });
    var source_indices = std.ArrayList(usize).empty;
    defer source_indices.deinit(allocator);
    try source_indices.appendSlice(allocator, &.{ 0, 1, 2, 3, 4, 5, 6 });
    const byte_starts = [_]usize{ 0, 1, 2, 3, 4, 5, 6 };
    var boundaries: cluster_safety.SourceBoundaries = .{};
    defer boundaries.deinit(allocator);
    boundaries.reset(0, 7, &byte_starts);
    const classes = [_]u16{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 };

    const result = try glyph_chaining.at(
        Executor,
        fixture.validatedView(&bytes),
        0,
        &glyphs,
        2,
        allocator,
        0x0008,
        .{
            .glyph_classes = &classes,
            .glyph_source_indices = &source_indices,
            .source_boundaries = &boundaries,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 5), result.next_pos);
    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 9, 2, 9, 18, 9, 4 },
        glyphs.items,
    );
    for (1..7) |byte_offset| {
        try std.testing.expect(boundaries.isUnsafeBeforeByte(byte_offset));
    }
}

test "glyph chaining cannot cross a source syllable boundary" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    fixture.writeSubtable(&bytes, 0, 1, &.{
        .{
            .input = &.{ 1, 2 },
            .records = &.{.{ .sequence_index = 0, .lookup_index = 1 }},
        },
    });
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    const result = try glyph_chaining.at(
        Executor,
        fixture.validatedView(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .source_syllables = &.{ 1, 2 },
            .match_source_syllable = true,
        },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2 }, glyphs.items);
}
