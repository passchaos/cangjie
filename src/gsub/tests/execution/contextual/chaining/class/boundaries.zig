//! Backtrack ordering, filtering, syllable, and safety contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const chaining_class =
    @import("../../../../../execution/contextual/chaining/class/root.zig");
const class_context =
    @import("../../../../../../opentype/class_context.zig");
const cluster_safety =
    @import("../../../../../../shaping/cluster_safety.zig");
const support = @import("support.zig");

test "accelerated chaining class preserves backtrack order syllables and safety" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 0, 7, 6, 2 });
    const classes = [_]u16{
        2,                                             6, 7,
        accelerator.index.class_first.sorted_encoding, 1, 0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 1,
        .lookahead_count = 1,
        .hash = class_context.sequenceHash(classes[0..3]),
        .order = 0,
        .lookup_index = 0,
        .classes_start = 0,
        .backtrack_count = 2,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 1,
        .max_input_count = 1,
        .max_lookahead_count = 1,
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 3,
        .backtrack_class_def = 0,
        .input_class_def = 0,
        .lookahead_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 4, 9, 5, 1, 8, 3 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3, 4, 5 });
    const byte_starts = [_]usize{ 0, 1, 2, 3, 4, 5 };
    var boundaries: cluster_safety.SourceBoundaries = .{};
    defer boundaries.deinit(allocator);
    boundaries.reset(0, 6, &byte_starts);
    var glyph_classes = [_]u16{0} ** 10;
    glyph_classes[8] = 3;
    glyph_classes[9] = 3;

    const split_syllables = [_]u8{ 1, 1, 2, 2, 2, 2 };
    var result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        3,
        allocator,
        0x0008,
        .{
            .glyph_classes = &glyph_classes,
            .glyph_source_indices = &sources,
            .source_boundaries = &boundaries,
            .source_syllables = &split_syllables,
            .match_source_syllable = true,
        },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expect(!boundaries.isUnsafeBeforeByte(3));

    const one_syllable = [_]u8{2} ** 6;
    result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        3,
        allocator,
        0x0008,
        .{
            .glyph_classes = &glyph_classes,
            .glyph_source_indices = &sources,
            .source_boundaries = &boundaries,
            .source_syllables = &one_syllable,
            .match_source_syllable = true,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 4, 9, 5, 11, 8, 3 }, glyphs.items);
    for (1..6) |boundary| {
        try std.testing.expect(boundaries.isUnsafeBeforeByte(boundary));
    }
}

test "accelerated chaining class uses physical adjacency proof" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 5, 3, 7 });
    const classes = [_]u16{
        5,                                             5, 7,
        accelerator.index.class_first.sorted_encoding, 2, 0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 2,
        .lookahead_count = 1,
        .hash = class_context.sequenceHash(classes[0..3]),
        .order = 0,
        .lookup_index = 2,
        .classes_start = 0,
        .backtrack_count = 1,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 1,
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 3,
        .backtrack_class_def = 0,
        .input_class_def = 0,
        .lookahead_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 1, 3 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3 });
    // Supplying no source codepoint sidecar exercises the proof path rather
    // than making its result depend on the generic Unicode classifier. The
    // physical-adjacency path must nevertheless retain Indic syllable scope.
    const split_syllables = [_]u8{ 1, 1, 2, 2 };
    var result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        1,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .run_has_default_ignorables = false,
            .source_syllables = &split_syllables,
            .match_source_syllable = true,
        },
    );
    try std.testing.expect(!result.matched);

    const one_syllable = [_]u8{1} ** 4;
    result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        1,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .run_has_default_ignorables = false,
            .source_syllables = &one_syllable,
            .match_source_syllable = true,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 14, 1, 3 }, glyphs.items);
}

test "physical adjacency fast path preserves reversed backtrack order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 2, 6, 3, 7 });
    const classes = [_]u16{
        6,                                             2, 7,
        accelerator.index.class_first.sorted_encoding, 3, 0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 1,
        .lookahead_count = 1,
        .hash = class_context.sequenceHash(classes[0..3]),
        .order = 0,
        .lookup_index = 0,
        .classes_start = 0,
        .backtrack_count = 2,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 1,
        .max_input_count = 1,
        .max_lookahead_count = 1,
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 3,
        .backtrack_class_def = 0,
        .input_class_def = 0,
        .lookahead_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3, 4 });

    const result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        2,
        allocator,
        0,
        .{ .run_has_default_ignorables = false },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 13, 4 }, glyphs.items);
}
