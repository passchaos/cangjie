//! Reverse context visibility, source scope, and exact-key contracts.

const std = @import("std");
const reverse = @import("../../../../execution/direct/reverse/root.zig");
const fixture = @import("fixture.zig");
const feature = @import("../../../../feature/root.zig");
const table = @import("../../../../table/root.zig");

test "reverse context stops at source syllable boundaries" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    fixture.writeReverse(&bytes, 0, 2, 9, &.{1}, &.{});
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });

    const split = [_]u8{ 1, 2 };
    try std.testing.expect(!try reverse.at(
        view(&bytes),
        0,
        &glyphs,
        1,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_syllables = &split,
            .match_source_syllable = true,
        },
    ));
    try std.testing.expectEqualSlices(u16, &.{ 1, 2 }, glyphs.items);

    const joined = [_]u8{ 1, 1 };
    try std.testing.expect(try reverse.at(
        view(&bytes),
        0,
        &glyphs,
        1,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_syllables = &joined,
            .match_source_syllable = true,
        },
    ));
    try std.testing.expectEqualSlices(u16, &.{ 1, 9 }, glyphs.items);
}

test "reverse target honors source feature scope" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    fixture.writeReverse(&bytes, 0, 2, 9, &.{1}, &.{});
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    const active = feature.sourceMaskForTag(0x63616c74).?;
    const source_features = [_]u32{ active, 0 };

    try std.testing.expect(!try reverse.at(
        view(&bytes),
        0,
        &glyphs,
        1,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_features = &source_features,
            .active_source_feature_mask = active,
        },
    ));
    try std.testing.expectEqualSlices(u16, &.{ 1, 2 }, glyphs.items);
}

test "exact reverse key skips context glyphs and respects syllables" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4, 5 });
    const classes = [_]u16{ 0, 0, 0, 0, 3, 3 };
    const glyphs = [_]u16{ 1, 4, 2, 5, 3, 6 };

    const key = reverse.exactContextKey(
        &glyphs,
        2,
        0x0008,
        .{
            .glyph_classes = &classes,
            .glyph_source_indices = &sources,
        },
    ).?;
    try std.testing.expectEqual(@as(u16, 2), key.target);
    try std.testing.expectEqual(@as(u16, 1), key.backtrack);
    try std.testing.expectEqual(@as(u16, 3), key.lookahead_0);
    try std.testing.expectEqual(@as(u16, 6), key.lookahead_1);

    const syllables = [_]u8{ 1, 1, 1, 1, 1, 2 };
    try std.testing.expect(reverse.exactContextKey(
        &glyphs,
        2,
        0x0008,
        .{
            .glyph_classes = &classes,
            .glyph_source_indices = &sources,
            .source_syllables = &syllables,
            .match_source_syllable = true,
        },
    ) == null);
}

fn view(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
