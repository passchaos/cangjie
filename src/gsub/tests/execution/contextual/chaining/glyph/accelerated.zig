//! Bounded format-1 sidecar execution contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const glyph_chaining =
    @import("../../../../../execution/contextual/chaining/glyph/root.zig");
const model = @import("../../../../../execution/contextual/model.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const cluster_safety = @import("../../../../../../shaping/cluster_safety.zig");
const table = @import("../../../../../table/root.zig");

const Executor = struct {
    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        allocator: std.mem.Allocator,
        _: Options,
    ) !model.Change {
        return switch (lookup_index) {
            1 => change: {
                glyphs.items[target] += 10;
                break :change .{};
            },
            2 => change: {
                try glyphs.replaceRange(allocator, target, 1, &.{ 20, 21 });
                break :change .{ .removed_len = 1, .inserted_len = 2 };
            },
            else => error.BadGsub,
        };
    }
};

test "accelerated glyph chaining resolves logical input and lookahead" {
    const allocator = std.testing.allocator;
    const rules = [_]accelerator.model.ChainingGlyphRule{.{
        .first = 1,
        .second = 2,
        .lookahead = 0,
        .nested_lookup = 1,
    }};
    const subtable = accelerator.model.ChainingGlyphSubtable{
        .rules = &rules,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 9, 2, 9, 0 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3, 4 });
    const classes = [_]u16{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 };
    const byte_starts = [_]usize{ 0, 1, 2, 3, 4 };
    var boundaries: cluster_safety.SourceBoundaries = .{};
    defer boundaries.deinit(allocator);
    boundaries.reset(0, 5, &byte_starts);

    const result = try glyph_chaining.acceleratedAt(
        Executor,
        emptyView(),
        subtable,
        &glyphs,
        0,
        allocator,
        0x0008,
        .{
            .glyph_classes = &classes,
            .glyph_source_indices = &sources,
            .source_boundaries = &boundaries,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 11, 9, 2, 9, 0 }, glyphs.items);
    for (1..5) |offset| {
        try std.testing.expect(boundaries.isUnsafeBeforeByte(offset));
    }
}

test "accelerated glyph chaining skips default ignorables and respects syllables" {
    const allocator = std.testing.allocator;
    const rules = [_]accelerator.model.ChainingGlyphRule{.{
        .first = 1,
        .second = 2,
        .nested_lookup = 1,
    }};
    const subtable = accelerator.model.ChainingGlyphSubtable{
        .rules = &rules,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 9, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });

    var result = try glyph_chaining.acceleratedAt(
        Executor,
        emptyView(),
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &.{ 'A', 0x034f, 'B' },
            .run_has_default_ignorables = true,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 11, 9, 2 }, glyphs.items);

    glyphs.items[0] = 1;
    result = try glyph_chaining.acceleratedAt(
        Executor,
        emptyView(),
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_syllables = &.{ 1, 1, 2 },
            .match_source_syllable = true,
            .source_codepoints = &.{ 'A', 0x034f, 'B' },
            .run_has_default_ignorables = true,
        },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 9, 2 }, glyphs.items);
}

test "accelerated glyph chaining preserves transparent lookup cursors" {
    const allocator = std.testing.allocator;
    const rules = [_]accelerator.model.ChainingGlyphRule{.{
        .first = 9,
        .second = 2,
        .nested_lookup = 1,
    }};
    const subtable = accelerator.model.ChainingGlyphSubtable{
        .rules = &rules,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 9, 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });

    const result = try glyph_chaining.acceleratedAt(
        Executor,
        emptyView(),
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &.{ 0x034f, 'A', 'B' },
            .run_has_default_ignorables = true,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 9, 11, 2 }, glyphs.items);
}

test "accelerated glyph chaining keeps input and context visibility distinct" {
    const allocator = std.testing.allocator;
    const rules = [_]accelerator.model.ChainingGlyphRule{.{
        .first = 1,
        .second = 2,
        .lookahead = 3,
        .nested_lookup = 1,
    }};
    const subtable = accelerator.model.ChainingGlyphSubtable{
        .rules = &rules,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3 });
    const run = Options{
        .glyph_source_indices = &sources,
        .source_codepoints = &.{ 'A', 'B', 0x200d, 'C' },
        .run_has_default_ignorables = true,
        .active_auto_zwj = false,
    };

    // A manual ZWJ remains authored input but is transparent to lookahead.
    try glyphs.appendSlice(allocator, &.{ 1, 2, 8, 3 });
    var result = try glyph_chaining.acceleratedAt(
        Executor,
        emptyView(),
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        run,
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 11, 2, 8, 3 }, glyphs.items);

    glyphs.items[0] = 1;
    glyphs.items[1] = 8;
    glyphs.items[2] = 2;
    result = try glyph_chaining.acceleratedAt(
        Executor,
        emptyView(),
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &.{ 'A', 0x200d, 'B', 'C' },
            .run_has_default_ignorables = true,
            .active_auto_zwj = false,
        },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 8, 2, 3 }, glyphs.items);
}

test "accelerated glyph lookup preserves subtable order and mutation resume" {
    const allocator = std.testing.allocator;
    const first_rules = [_]accelerator.model.ChainingGlyphRule{.{
        .first = 1,
        .second = 2,
        .nested_lookup = 2,
    }};
    const later_rules = [_]accelerator.model.ChainingGlyphRule{.{
        .first = 1,
        .second = 2,
        .nested_lookup = 1,
    }};
    const subtables = [_]accelerator.model.ChainingGlyphSubtable{
        .{ .rules = &first_rules },
        .{ .rules = &later_rules },
    };
    const sidecar = accelerator.Lookup{
        .subtable_count = subtables.len,
        .chaining_glyph_subtables = &subtables,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 1, 2 });

    try glyph_chaining.acceleratedLookup(
        Executor,
        emptyView(),
        &glyphs,
        allocator,
        0,
        .{},
        &sidecar,
    );
    // Expansion at sequence zero advances the old match end by one, leaving
    // the following original candidate reachable. The first subtable wins at
    // both cursors; the later visible-delta alternative never cascades.
    try std.testing.expectEqualSlices(
        u16,
        &.{ 20, 21, 2, 20, 21, 2 },
        glyphs.items,
    );
}

fn emptyView() table.View {
    return .{
        .data = &.{},
        .offset = 0,
        .length = 0,
        .assume_validated = true,
    };
}
