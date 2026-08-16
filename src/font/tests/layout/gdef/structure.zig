//! GDEF child-table ownership and variation-store contracts.

const std = @import("std");
const gdef = @import("../../../tables/layout/gdef/root.zig");
const sfnt = @import("../../../sfnt/root.zig");
const fixture = @import("../../fixtures/sfnt.zig");

const GlyphClass = gdef.GlyphClass;
const Record = sfnt.Record;

test "GDEF parse validation rejects class and mark-set glyph ids past maxp" {
    var valid_classdef: [22]u8 = .{0} ** 22;
    fixture.writeU16(&valid_classdef, 0, 1); // GDEF major.
    fixture.writeU16(&valid_classdef, 2, 0); // GDEF 1.0 header.
    fixture.writeU16(&valid_classdef, 4, 12); // GlyphClassDef follows the header.
    fixture.writeU16(&valid_classdef, 12, 1); // ClassDef format 1.
    fixture.writeU16(&valid_classdef, 14, 2); // startGlyphID.
    fixture.writeU16(&valid_classdef, 16, 2); // Covers glyphs 2 and 3 in a four-glyph font.
    fixture.writeU16(&valid_classdef, 18, @intFromEnum(GlyphClass.mark));
    fixture.writeU16(&valid_classdef, 20, @intFromEnum(GlyphClass.mark));
    try gdef.validateBasic(&valid_classdef, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = valid_classdef.len }, 4);

    var classdef_past_maxp = valid_classdef;
    fixture.writeU16(&classdef_past_maxp, 16, 3); // Would cover glyph 4, outside maxp.numGlyphs.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&classdef_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = classdef_past_maxp.len }, 4));

    var child_offset_overlap = valid_classdef;
    fixture.writeU16(&child_offset_overlap, 4, 4); // Reinterprets GDEF header bytes as ClassDef data.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&child_offset_overlap, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = child_offset_overlap.len }, 4));

    var class_value_past_enum = valid_classdef;
    fixture.writeU16(&class_value_past_enum, 18, 5); // GlyphClassDef has only classes 0..4.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&class_value_past_enum, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = class_value_past_enum.len }, 4));

    var format2_class_value_past_enum: [22]u8 = .{0} ** 22;
    fixture.writeU16(&format2_class_value_past_enum, 0, 1); // GDEF major.
    fixture.writeU16(&format2_class_value_past_enum, 2, 0);
    fixture.writeU16(&format2_class_value_past_enum, 4, 12);
    fixture.writeU16(&format2_class_value_past_enum, 12, 2); // ClassDef format 2.
    fixture.writeU16(&format2_class_value_past_enum, 14, 1);
    fixture.writeU16(&format2_class_value_past_enum, 16, 2);
    fixture.writeU16(&format2_class_value_past_enum, 18, 3);
    fixture.writeU16(&format2_class_value_past_enum, 20, 5);
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&format2_class_value_past_enum, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = format2_class_value_past_enum.len }, 4));

    var mark_set_past_maxp: [30]u8 = .{0} ** 30;
    fixture.writeU16(&mark_set_past_maxp, 0, 1); // GDEF major.
    fixture.writeU16(&mark_set_past_maxp, 2, 2); // GDEF 1.2 includes MarkGlyphSetsDef.
    fixture.writeU16(&mark_set_past_maxp, 12, 14); // MarkGlyphSetsDef follows the v1.2 header.
    fixture.writeU16(&mark_set_past_maxp, 14, 1); // MarkGlyphSetsDef format 1.
    fixture.writeU16(&mark_set_past_maxp, 16, 1);
    fixture.writeU32(&mark_set_past_maxp, 18, 8); // Coverage starts after the set offset array.
    fixture.writeU16(&mark_set_past_maxp, 22, 1); // Coverage format 1.
    fixture.writeU16(&mark_set_past_maxp, 24, 2);
    fixture.writeU16(&mark_set_past_maxp, 26, 1);
    fixture.writeU16(&mark_set_past_maxp, 28, 4); // Invalid for maxp.numGlyphs == 4.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&mark_set_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = mark_set_past_maxp.len }, 4));
}

test "GDEF parse validation walks AttachList child tables" {
    var valid_attach: [30]u8 = .{0} ** 30;
    fixture.writeU16(&valid_attach, 0, 1); // GDEF major.
    fixture.writeU16(&valid_attach, 2, 0);
    fixture.writeU16(&valid_attach, 6, 12); // AttachList follows the GDEF 1.0 header.

    fixture.writeU16(&valid_attach, 12, 6); // Coverage offset, relative to AttachList.
    fixture.writeU16(&valid_attach, 14, 1); // One covered glyph and one AttachPoint.
    fixture.writeU16(&valid_attach, 16, 12); // AttachPoint offset, relative to AttachList.
    fixture.writeU16(&valid_attach, 18, 1); // Coverage format 1.
    fixture.writeU16(&valid_attach, 20, 1);
    fixture.writeU16(&valid_attach, 22, 3);
    fixture.writeU16(&valid_attach, 24, 2); // AttachPoint: two sorted point indices.
    fixture.writeU16(&valid_attach, 26, 4);
    fixture.writeU16(&valid_attach, 28, 7);
    try gdef.validateBasic(&valid_attach, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = valid_attach.len }, 4);

    var attach_offset_aliases_header = valid_attach;
    fixture.writeU16(&attach_offset_aliases_header, 16, 2); // Would reinterpret AttachList glyphCount as pointCount.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&attach_offset_aliases_header, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = attach_offset_aliases_header.len }, 4));

    var unsorted_points = valid_attach;
    fixture.writeU16(&unsorted_points, 28, 4); // Duplicate/decreasing point order is not canonical.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&unsorted_points, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = unsorted_points.len }, 4));

    var coverage_past_maxp = valid_attach;
    fixture.writeU16(&coverage_past_maxp, 22, 4); // Invalid for maxp.numGlyphs == 4.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&coverage_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = coverage_past_maxp.len }, 4));

    var mismatched_coverage: [34]u8 = .{0} ** 34;
    fixture.writeU16(&mismatched_coverage, 0, 1);
    fixture.writeU16(&mismatched_coverage, 2, 0);
    fixture.writeU16(&mismatched_coverage, 6, 12);
    fixture.writeU16(&mismatched_coverage, 12, 8); // Coverage starts after two AttachPoint offsets.
    fixture.writeU16(&mismatched_coverage, 14, 2); // Two AttachPoint offsets advertised.
    fixture.writeU16(&mismatched_coverage, 16, 14);
    fixture.writeU16(&mismatched_coverage, 18, 18);
    fixture.writeU16(&mismatched_coverage, 20, 1); // Coverage format 1, but only one glyph.
    fixture.writeU16(&mismatched_coverage, 22, 1);
    fixture.writeU16(&mismatched_coverage, 24, 1);
    fixture.writeU16(&mismatched_coverage, 26, 1);
    fixture.writeU16(&mismatched_coverage, 28, 4);
    fixture.writeU16(&mismatched_coverage, 30, 1);
    fixture.writeU16(&mismatched_coverage, 32, 7);
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&mismatched_coverage, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = mismatched_coverage.len }, 4));
}

test "GDEF parse validation walks LigCaretList child tables" {
    var valid_lig_caret: [42]u8 = .{0} ** 42;
    fixture.writeU16(&valid_lig_caret, 0, 1); // GDEF major.
    fixture.writeU16(&valid_lig_caret, 2, 0);
    fixture.writeU16(&valid_lig_caret, 8, 12); // LigCaretList follows the GDEF 1.0 header.

    fixture.writeU16(&valid_lig_caret, 12, 6); // Coverage offset, relative to LigCaretList.
    fixture.writeU16(&valid_lig_caret, 14, 1); // One covered ligature glyph and one LigGlyph.
    fixture.writeU16(&valid_lig_caret, 16, 12); // LigGlyph offset, relative to LigCaretList.
    fixture.writeU16(&valid_lig_caret, 18, 1); // Coverage format 1.
    fixture.writeU16(&valid_lig_caret, 20, 1);
    fixture.writeU16(&valid_lig_caret, 22, 3);
    fixture.writeU16(&valid_lig_caret, 24, 1); // LigGlyph: one CaretValue offset.
    fixture.writeU16(&valid_lig_caret, 26, 4);
    fixture.writeU16(&valid_lig_caret, 28, 1); // CaretValue format 1.
    fixture.writeI16(&valid_lig_caret, 30, 120);
    try gdef.validateBasic(&valid_lig_caret, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = valid_lig_caret.len }, 4);

    var lig_glyph_offset_aliases_header = valid_lig_caret;
    fixture.writeU16(&lig_glyph_offset_aliases_header, 16, 2); // Would reinterpret LigGlyphCount as CaretCount.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&lig_glyph_offset_aliases_header, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = lig_glyph_offset_aliases_header.len }, 4));

    var caret_offset_aliases_array = valid_lig_caret;
    fixture.writeU16(&caret_offset_aliases_array, 26, 2); // Would reinterpret the CaretValue offset array as a CaretValue.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&caret_offset_aliases_array, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = caret_offset_aliases_array.len }, 4));

    var coverage_past_maxp = valid_lig_caret;
    fixture.writeU16(&coverage_past_maxp, 22, 4); // Invalid for maxp.numGlyphs == 4.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&coverage_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = coverage_past_maxp.len }, 4));

    var mismatched_coverage = valid_lig_caret;
    fixture.writeU16(&mismatched_coverage, 20, 0); // Coverage count no longer matches LigGlyphCount.
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&mismatched_coverage, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = mismatched_coverage.len }, 4));

    var format3_caret = valid_lig_caret;
    fixture.writeU16(&format3_caret, 28, 3); // CaretValue format 3.
    fixture.writeI16(&format3_caret, 30, 120);
    fixture.writeU16(&format3_caret, 32, 6); // Device table offset, relative to CaretValue.
    fixture.writeU16(&format3_caret, 34, 12); // Device StartSize.
    fixture.writeU16(&format3_caret, 36, 13); // Device EndSize.
    fixture.writeU16(&format3_caret, 38, 1); // Two 2-bit deltas need one uint16 word.
    fixture.writeU16(&format3_caret, 40, 0);
    try gdef.validateBasic(&format3_caret, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = format3_caret.len }, 4);

    var truncated_device = format3_caret;
    try std.testing.expectError(error.BadSfnt, gdef.validateBasic(&truncated_device, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = truncated_device.len - 1 }, 4));
}

test "GDEF v1.3 validates ItemVariationStore payload" {
    const gdef_offset: usize = 0;
    const item_store_offset: usize = 20;
    var bytes: [item_store_offset + 34]u8 =
        .{0} ** (item_store_offset + 34);

    fixture.writeU16(&bytes, gdef_offset + 0, 1); // GDEF major.
    fixture.writeU16(&bytes, gdef_offset + 2, 3); // GDEF 1.3 adds ItemVariationStoreOffset.
    fixture.writeU32(&bytes, gdef_offset + 14, item_store_offset);
    writeItemVariationStore(&bytes, gdef_offset + item_store_offset);

    const record = Record{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = gdef_offset, .length = bytes.len - gdef_offset };
    try gdef.validate(&bytes, record, 4, 1);

    // A GDEF ItemVariationStore is meaningful only in the fvar variation-axis
    // coordinate system. Keeping that dependency explicit prevents a table that
    // merely fits in the GDEF byte range from being accepted as usable
    // variation data.
    try std.testing.expectError(error.BadSfnt, gdef.validate(&bytes, record, 4, null));

    var bad_store_format = bytes;
    fixture.writeU16(&bad_store_format, gdef_offset + item_store_offset, 2);
    try std.testing.expectError(error.BadSfnt, gdef.validate(&bad_store_format, record, 4, 1));

    var axis_mismatch = bytes;
    fixture.writeU16(&axis_mismatch, gdef_offset + item_store_offset + 12, 2); // VariationRegionList axisCount.
    try std.testing.expectError(error.BadSfnt, gdef.validate(&axis_mismatch, record, 4, 1));
}

fn writeItemVariationStore(bytes: []u8, offset: usize) void {
    fixture.writeU16(bytes, offset, 1);
    fixture.writeU32(bytes, offset + 2, 12);
    fixture.writeU16(bytes, offset + 6, 1);
    fixture.writeU32(bytes, offset + 8, 24);

    fixture.writeU16(bytes, offset + 12, 1);
    fixture.writeU16(bytes, offset + 14, 1);
    fixture.writeI16(bytes, offset + 16, -0x4000);
    fixture.writeI16(bytes, offset + 18, 0);
    fixture.writeI16(bytes, offset + 20, 0x4000);

    fixture.writeU16(bytes, offset + 24, 1);
    fixture.writeU16(bytes, offset + 26, 1);
    fixture.writeU16(bytes, offset + 28, 1);
    fixture.writeU16(bytes, offset + 30, 0);
    fixture.writeI16(bytes, offset + 32, 7);
}
