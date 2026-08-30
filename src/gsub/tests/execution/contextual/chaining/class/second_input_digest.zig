//! Accelerated second-input class digest execution contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const chaining_class =
    @import("../../../../../execution/contextual/chaining/class/root.zig");
const contextual_model =
    @import("../../../../../execution/contextual/model.zig");
const class_context =
    @import("../../../../../../opentype/class_context.zig");
const limits = @import("../../../../../runtime/limits.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const support = @import("support.zig");
const table = @import("../../../../../table/root.zig");

const BudgetExecutor = struct {
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        _: std.mem.Allocator,
        run: Options,
    ) !contextual_model.Change {
        try limits.consumeNested(run);
        glyphs.items[target] += lookup_index + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

const MutationExecutor = struct {
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        allocator: std.mem.Allocator,
        _: Options,
    ) !contextual_model.Change {
        return switch (lookup_index) {
            0 => change: {
                try glyphs.replaceRange(allocator, target, 1, &.{ 20, 21 });
                break :change .{ .removed_len = 1, .inserted_len = 2 };
            },
            1 => change: {
                glyphs.items[target] += 10;
                break :change .{};
            },
            else => error.InvalidShapingInput,
        };
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "accelerated chaining class prefilters the logical second input class" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5 });
    const classes = [_]u16{
        5,
        accelerator.index.class_first.sorted_encoding,
        1,
        0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 2,
        .lookahead_count = 0,
        .hash = class_context.sequenceHash(classes[0..1]),
        .order = 0,
        .lookup_index = 2,
        .classes_start = 0,
    }};
    var groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 0,
        .second_input_class_digest = support.classDigestBit(5),
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 1,
        .input_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    var operations_left: usize = 1;
    var result = try chaining_class.acceleratedAt(
        BudgetExecutor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        allocator,
        0,
        .{ .operations_left = &operations_left },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 0), operations_left);
    try std.testing.expectEqualSlices(u16, &.{ 13, 2 }, glyphs.items);

    // The exact first-glyph index still hits, but class five cannot satisfy
    // this necessary condition. No action (or operation-budget charge) may
    // occur on the cheap rejection path.
    glyphs.items[0] = 1;
    groups[0].second_input_class_digest = support.classDigestBit(6);
    operations_left = 1;
    result = try chaining_class.acceleratedAt(
        BudgetExecutor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        allocator,
        0,
        .{ .operations_left = &operations_left },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expectEqual(@as(usize, 1), operations_left);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2 }, glyphs.items);
}

test "accelerated chaining class digest skips a transparent cursor glyph" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 0, 3, 5 });
    const classes = [_]u16{
        5,
        accelerator.index.class_first.sorted_encoding,
        2,
        0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 2,
        .lookahead_count = 0,
        .hash = class_context.sequenceHash(classes[0..1]),
        .order = 0,
        .lookup_index = 2,
        .classes_start = 0,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 0,
        .second_input_class_digest = support.classDigestBit(5),
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 1,
        .input_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 2, 2, 3 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });

    // CGJ at the lookup cursor is eligible as an anchor but transparent to
    // contextual input traversal. The digest must therefore classify glyph
    // three, which is logical input[1], rather than the physical neighbor.
    const result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
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
    try std.testing.expectEqualSlices(u16, &.{ 2, 14, 3 }, glyphs.items);
}

test "accelerated chaining class digest follows mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5, 0, 0, 0, 0, 0, 6 });
    const classes = [_]u16{
        5,
        accelerator.index.class_first.sorted_encoding,
        1,
        0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 2,
        .lookahead_count = 0,
        .hash = class_context.sequenceHash(classes[0..1]),
        .order = 0,
        .lookup_index = 2,
        .classes_start = 0,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 0,
        .second_input_class_digest = support.classDigestBit(5),
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 1,
        .input_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 8, 2 });
    var glyph_classes = [_]u16{0} ** 9;
    glyph_classes[8] = 3;
    var attach_classes = [_]u16{0} ** 9;
    attach_classes[8] = 1;

    // IgnoreMarks skips the physical middle glyph, so both the digest and the
    // exact matcher must classify glyph two as logical input[1].
    var result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        allocator,
        0x0008,
        .{ .glyph_classes = &glyph_classes },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 13, 8, 2 }, glyphs.items);

    // A mismatched attachment class skips the same mark under different
    // LookupFlag semantics.
    glyphs.items[0] = 1;
    result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        allocator,
        0x0200,
        .{
            .glyph_classes = &glyph_classes,
            .mark_attach_classes = &attach_classes,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 13, 8, 2 }, glyphs.items);

    // A mark in the requested attachment class remains visible. Its class is
    // six rather than five, so the digest must reject instead of skipping it.
    glyphs.items[0] = 1;
    attach_classes[8] = 2;
    result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        allocator,
        0x0200,
        .{
            .glyph_classes = &glyph_classes,
            .mark_attach_classes = &attach_classes,
        },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 8, 2 }, glyphs.items);
}

test "accelerated chaining class zero digest preserves one-input fallback" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{3});
    const classes = [_]u16{
        accelerator.index.class_first.sorted_encoding, 1, 0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 1,
        .lookahead_count = 0,
        .hash = class_context.sequenceHash(&.{}),
        .order = 0,
        .lookup_index = 2,
        .classes_start = 0,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 1,
        .max_input_count = 1,
        .max_lookahead_count = 0,
        .second_input_class_digest = 0,
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 0,
        .input_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    const result = try chaining_class.acceleratedAt(
        support.Executor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{13}, glyphs.items);
}

test "accelerated chaining class digest miss does not block a later subtable" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5 });
    const classes = [_]u16{
        5,
        accelerator.index.class_first.sorted_encoding,
        1,
        0,
    };
    const first_rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 2,
        .lookahead_count = 0,
        .hash = class_context.sequenceHash(classes[0..1]),
        .order = 0,
        .lookup_index = 7,
        .classes_start = 0,
    }};
    const second_rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 2,
        .lookahead_count = 0,
        .hash = class_context.sequenceHash(classes[0..1]),
        .order = 0,
        .lookup_index = 2,
        .classes_start = 0,
    }};
    const first_groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 0,
        .second_input_class_digest = support.classDigestBit(6),
    }};
    const second_groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 0,
        .second_input_class_digest = support.classDigestBit(5),
    }};
    const subtables = [_]accelerator.model.ChainingClassSubtable{
        .{
            .first_index_start = 1,
            .input_class_def = 0,
            .rules = &first_rules,
            .classes = &classes,
            .groups = &first_groups,
        },
        .{
            .first_index_start = 1,
            .input_class_def = 0,
            .rules = &second_rules,
            .classes = &classes,
            .groups = &second_groups,
        },
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    // Nested dispatch probes subtables in authored order through `at`. A
    // digest miss is a no-match for only the current subtable, so the later
    // matching alternative must still be applied.
    for (subtables) |parsed| {
        const result = try chaining_class.acceleratedAt(
            support.Executor,
            support.validatedView(&bytes),
            parsed,
            &glyphs,
            0,
            allocator,
            0,
            .{},
        );
        if (result.matched) break;
    }
    try std.testing.expectEqualSlices(u16, &.{ 13, 2 }, glyphs.items);
}

test "accelerated chaining class digest preserves authored mutation order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5 });
    // Expanding input zero inserts a new logical slot. The later authored
    // SequenceIndex two then addresses that inserted glyph, proving that the
    // digest gate leaves the record-map mutation semantics untouched.
    std.mem.writeInt(u16, bytes[32..34], 0, .big);
    std.mem.writeInt(u16, bytes[34..36], 0, .big);
    std.mem.writeInt(u16, bytes[36..38], 2, .big);
    std.mem.writeInt(u16, bytes[38..40], 1, .big);

    const classes = [_]u16{
        5,
        accelerator.index.class_first.sorted_encoding,
        1,
        0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 2,
        .lookahead_count = 0,
        .hash = class_context.sequenceHash(classes[0..1]),
        .order = 0,
        .lookup_index = 0,
        .classes_start = 0,
        .subst_count = 2,
        .record_list = true,
        .records_offset = 32,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 0,
        .second_input_class_digest = support.classDigestBit(5),
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 1,
        .input_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    const result = try chaining_class.acceleratedAt(
        MutationExecutor,
        support.validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 20, 21, 12 }, glyphs.items);
}
