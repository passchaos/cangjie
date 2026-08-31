//! GSUB accelerator concrete-layout and default-state contracts.

const std = @import("std");
const acceleration = @import("../../accelerator/root.zig");

test "GSUB lookup accelerator is a concrete empty sidecar by default" {
    const lookup = acceleration.Lookup{};

    try std.testing.expectEqual(@as(usize, 0), lookup.lookup_offset);
    try std.testing.expectEqual(@as(u16, 0), lookup.lookup_type);
    try std.testing.expectEqual(@as(?u16, null), lookup.mark_filtering_set);
    try std.testing.expectEqual(@as(usize, 0), lookup.single_subst_entries.len);
    try std.testing.expectEqual(@as(usize, 0), lookup.chaining_subtables.len);
    try std.testing.expectEqual(
        @as(usize, 0),
        lookup.chaining_glyph_subtables.len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        lookup.reverse_chaining_exact_contexts.len,
    );
    try std.testing.expectEqual(@as(?*const acceleration.model.FeatureIndex, null), lookup.feature_index);
}

test "GSUB chaining glyph lookup preserves optional zero lookahead" {
    const rules = [_]acceleration.model.ChainingGlyphRule{
        .{ .first = 0, .second = 4, .lookahead = 0, .nested_lookup = 2 },
        .{ .first = 7, .second = 8, .nested_lookup = 3 },
    };
    const subtable = acceleration.model.ChainingGlyphSubtable{
        .subtable_offset = 12,
        .rules = &rules,
    };

    try std.testing.expectEqual(@as(?u16, 0), subtable.find(0).?.lookahead);
    try std.testing.expectEqual(@as(?u16, null), subtable.find(7).?.lookahead);
    try std.testing.expect(subtable.find(6) == null);
}

test "GSUB ligature accelerator compact range does not widen its sidecar" {
    const model = acceleration.model;
    const WithoutRequiredSecondRange = struct {
        sets: []const model.LigatureSet = &.{},
        set_slots: []const u16 = &.{},
        definitions: []const model.LigatureDefinition = &.{},
        components: []const u16 = &.{},
        first_component_digest: @import("../../../glyph_digest.zig").GlyphDigest = .{},
        prefilter_second: bool = false,
    };

    try std.testing.expectEqual(
        @sizeOf(WithoutRequiredSecondRange),
        @sizeOf(model.LigatureSubstitution),
    );
}
