//! Accelerator rule ordering, filtering, and safety contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const chaining_class =
    @import("../../../../../execution/contextual/chaining/class/root.zig");
const class_context =
    @import("../../../../../../opentype/class_context.zig");
const support = @import("support.zig");

test "accelerated chaining class tries shorter authored rule first" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5, 7 });
    const classes = [_]u16{
        5, 7, // Short: one extra input and one lookahead.
        5,                                             7, 7, // Long: three extra inputs.
        accelerator.index.class_first.sorted_encoding, 1, 0,
    };
    const rules = [_]class_context.Rule{
        .{
            .class_set = 3,
            .input_count = 2,
            .lookahead_count = 1,
            .hash = class_context.sequenceHash(classes[0..2]),
            .order = 0,
            .lookup_index = 2,
            .classes_start = 0,
        },
        .{
            .class_set = 3,
            .input_count = 4,
            .lookahead_count = 0,
            .hash = class_context.sequenceHash(classes[2..5]),
            .order = 1,
            .lookup_index = 9,
            .classes_start = 2,
        },
    };
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = rules.len,
        .max_input_count = 4,
        .max_lookahead_count = 1,
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 5,
        .input_class_def = 0,
        .lookahead_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

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
    try std.testing.expectEqual(@as(usize, 2), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 13, 2, 3 }, glyphs.items);
}

test "accelerated chaining class extends cached class prefixes across rules" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5, 7, 9 });
    const classes = [_]u16{
        5, 6, // First rule fails after decoding one input and lookahead.
        5,                                             7, 9, // Second extends both prefixes and matches.
        accelerator.index.class_first.sorted_encoding, 1, 0,
    };
    const rules = [_]class_context.Rule{
        .{
            .class_set = 3,
            .input_count = 2,
            .lookahead_count = 1,
            .hash = class_context.sequenceHash(classes[0..2]),
            .order = 0,
            .lookup_index = 2,
            .classes_start = 0,
        },
        .{
            .class_set = 3,
            .input_count = 3,
            .lookahead_count = 1,
            .hash = class_context.sequenceHash(classes[2..5]),
            .order = 1,
            .lookup_index = 9,
            .classes_start = 2,
        },
    };
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = rules.len,
        .max_input_count = 3,
        .max_lookahead_count = 1,
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 5,
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
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 20, 2, 3, 4 }, glyphs.items);
}

test "accelerated chaining class applies complete multi-record actions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5 });
    // Apply lookup 2 to the second input first, then lookup 4 to the anchor.
    // A compact single-lookup action cannot represent either the authored
    // order or the nonzero first sequence index.
    std.mem.writeInt(u16, bytes[32..34], 1, .big);
    std.mem.writeInt(u16, bytes[34..36], 2, .big);
    std.mem.writeInt(u16, bytes[36..38], 0, .big);
    std.mem.writeInt(u16, bytes[38..40], 4, .big);

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
        .max_input_count = 2,
        .max_lookahead_count = 0,
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
    try std.testing.expectEqual(@as(usize, 2), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 15, 14 }, glyphs.items);
}

test "accelerated chaining class ignores unprofitable hash metadata" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    support.writeClassDef1(&bytes, 0, 1, &.{ 3, 5, 7 });
    const classes = [_]u16{
        5,                                             7,
        accelerator.index.class_first.sorted_encoding, 1,
        0,
    };
    const rules = [_]class_context.Rule{
        .{
            .class_set = 3,
            .input_count = 2,
            .lookahead_count = 1,
            .hash = class_context.sequenceHash(classes[0..2]),
            .order = 0,
            .lookup_index = 2,
            .classes_start = 0,
        },
    };
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = rules.len,
        .max_input_count = 2,
        .max_lookahead_count = 1,
        // The builder may sort a large overall group, but it deliberately
        // leaves isolated shapes on the cheaper exact-match path.
        .hash_sorted = true,
        .max_shape_len = 1,
    }};
    const parsed = accelerator.model.ChainingClassSubtable{
        .first_index_start = 2,
        .input_class_def = 0,
        .lookahead_class_def = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

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
    try std.testing.expectEqualSlices(u16, &.{ 13, 2, 3 }, glyphs.items);
}
