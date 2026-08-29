//! Trusted accelerated-dispatch identity and capability contracts.

const std = @import("std");
const acceleration = @import("../../../accelerator/root.zig");
const accelerated = @import("../../../execution/lookup/accelerated.zig");
const class_context = @import("../../../../opentype/class_context.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Binding = struct {
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: accelerated.View,
        _: *std.ArrayList(GlyphId),
        _: usize,
        _: u16,
        _: std.mem.Allocator,
        _: accelerated.Options,
    ) accelerated.Error!@import("../../../execution/contextual/model.zig").Change {
        return error.BadGsub;
    }

    pub fn validateNested(
        _: accelerated.View,
        _: usize,
    ) (@import("../../../table/root.zig").coverage.Error ||
        error{ InvalidShapingInput, ShapingLimitExceeded })!void {
        return error.BadGsub;
    }

    pub fn applyChainingLookup(
        _: accelerated.View,
        _: usize,
        _: u16,
        _: *std.ArrayList(GlyphId),
        _: std.mem.Allocator,
        _: u16,
        _: accelerated.Options,
        _: *const accelerated.Lookup,
    ) accelerated.Error!void {
        return error.BadGsub;
    }
};

test "accelerated GSUB dispatch declines missing and foreign sidecars" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 7);

    const view = accelerated.View{
        .data = &.{},
        .offset = 0,
        .length = 0,
        .assume_validated = true,
    };
    try std.testing.expect(!try accelerated.apply(
        Binding,
        view,
        12,
        0,
        &glyphs,
        allocator,
        .{},
        null,
    ));

    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 24,
        .lookup_type = 4,
        .subtable_count = 1,
    }};
    try std.testing.expect(!try accelerated.apply(
        Binding,
        view,
        12,
        0,
        &glyphs,
        allocator,
        .{ .lookup_accelerators = &sidecars },
        null,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{7}, glyphs.items);
}

test "accelerated GSUB chaining uses a comptime nested binding" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 7);

    // A non-empty approximate digest forces the coverage-chaining path to its
    // statically bound executor. The sentinel error proves this module does
    // not hide recursive dispatch behind an erased runtime callback.
    var digest = @import("../../../../glyph_digest.zig").GlyphDigest.empty();
    digest.add(7);
    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 12,
        .lookup_type = 6,
        .lookup_flag = 0,
        .subtable_count = 1,
        .chaining_coverage_only = true,
        .chaining_input_digest = digest,
    }};
    const view = accelerated.View{
        .data = &.{},
        .offset = 0,
        .length = 0,
        .assume_validated = true,
    };
    try std.testing.expectError(
        error.BadGsub,
        accelerated.apply(
            Binding,
            view,
            12,
            0,
            &glyphs,
            allocator,
            .{ .lookup_accelerators = &sidecars },
            null,
        ),
    );
}

test "accelerated GSUB fast profile records through the profiled path" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 7);
    var digest = @import("../../../../glyph_digest.zig").GlyphDigest.empty();
    digest.add(7);
    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 12,
        .lookup_type = 6,
        .subtable_count = 1,
        .chaining_coverage_only = true,
        .chaining_input_digest = digest,
    }};
    var counters = @import("../../../../shape_profile.zig").ShapeStageProfile{};
    try std.testing.expectError(
        error.BadGsub,
        accelerated.apply(
            Binding,
            .{
                .data = &.{},
                .offset = 0,
                .length = 0,
                .assume_validated = true,
            },
            12,
            0,
            &glyphs,
            allocator,
            .{
                .lookup_accelerators = &sidecars,
                .shape_profile = &counters,
                .profile_fast_path = true,
                .profile_io = std.testing.io,
            },
            null,
        ),
    );
}

test "accelerated GSUB dispatch executes extension-wrapped class sidecars" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 7, 8 });

    // The prepared first-glyph index maps glyph 7 to the sole chaining rule.
    // Its compact action deliberately reaches the sentinel nested binding,
    // proving lookup type 7 was dispatched directly rather than declined.
    const classes = [_]u16{
        acceleration.index.class_first.sorted_encoding,
        7,
        0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 0,
        .input_count = 1,
        .lookahead_count = 0,
        .hash = class_context.sequenceHashEmpty(),
        .order = 0,
        .lookup_index = 3,
        .classes_start = 0,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 0,
        .start = 0,
        .len = 1,
        .max_input_count = 1,
        .max_lookahead_count = 0,
    }};
    const chaining_subtables = [_]acceleration.model.ChainingClassSubtable{.{
        .first_index_start = 0,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    }};
    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 12,
        .lookup_type = 7,
        .subtable_count = 1,
        .extension_lookup_type = 6,
        .chaining_class_subtables = &chaining_subtables,
    }};
    const view = accelerated.View{
        .data = &.{},
        .offset = 0,
        .length = 0,
        .assume_validated = true,
    };
    try std.testing.expectError(
        error.BadGsub,
        accelerated.apply(
            Binding,
            view,
            12,
            0,
            &glyphs,
            allocator,
            .{ .lookup_accelerators = &sidecars },
            null,
        ),
    );
}

test "accelerated GSUB dispatch executes extension-wrapped ligatures" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 7, 8, 9 });

    var first_digest = @import("../../../../glyph_digest.zig").GlyphDigest.empty();
    first_digest.add(7);
    const sets = [_]acceleration.model.LigatureSet{.{
        .glyph = 7,
        .definition_start = 0,
        .definition_len = 1,
    }};
    const definitions = [_]acceleration.model.LigatureDefinition{.{
        .ligature = 42,
        .component_start = 0,
        .component_count = 2,
    }};
    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 12,
        .lookup_type = 7,
        .subtable_count = 1,
        .extension_lookup_type = 4,
        .ligature_subst = .{
            .sets = &sets,
            .definitions = &definitions,
            .components = &.{8},
            .first_component_digest = first_digest,
        },
    }};
    try std.testing.expect(try accelerated.apply(
        Binding,
        .{
            .data = &.{},
            .offset = 0,
            .length = 0,
            .assume_validated = true,
        },
        12,
        0,
        &glyphs,
        allocator,
        .{ .lookup_accelerators = &sidecars },
        null,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{ 42, 9 }, glyphs.items);
}

test "accelerated GSUB dispatch executes extension-wrapped multiple substitution" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u16, bytes[4..6], 2, .big);
    std.mem.writeInt(u16, bytes[6..8], 9, .big);
    std.mem.writeInt(u16, bytes[8..10], 10, .big);
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 7, 8 });
    const entries = [_]acceleration.model.MultipleEntry{.{
        .glyph = 7,
        .sequence_offset = 4,
        .glyph_count = 2,
    }};
    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 12,
        .lookup_type = 7,
        .subtable_count = 1,
        .extension_lookup_type = 2,
        .multiple_subst = .{ .entries = &entries },
    }};
    try std.testing.expect(try accelerated.apply(
        Binding,
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        12,
        0,
        &glyphs,
        allocator,
        .{ .lookup_accelerators = &sidecars },
        null,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{ 9, 10, 8 }, glyphs.items);
}
