//! Public cmap lookups revalidate caller-owned SFNT directory and table bytes.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;

test "cmap format 14 SFNT fixture rejects aliased variation payloads" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
    const variation_offset = readU32(bytes, cmap_offset + 16);

    // The default and non-default UVS arrays are independently owned
    // variable-length payloads. Aliasing them would make two incompatible
    // formats interpret the same bytes.
    sfnt_fixture.writeU32(
        bytes,
        cmap_offset + variation_offset + 17,
        21,
    );
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "cmap format 14 public lookup revalidates borrowed SFNT bytes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectVariationGlyph(&font);

    const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
    const variation_offset = readU32(bytes, cmap_offset + 16);

    // Font borrows the caller-owned buffer. A post-parse mutation must not let
    // either variation API return a glyph outside maxp.numGlyphs.
    sfnt_fixture.writeU16(
        bytes,
        cmap_offset + variation_offset + 36,
        4,
    );
    try expectVariationLookupError(&font, error.BadSfnt);
}

// Format-14 UVS lookup uses cached cmap directory entries because it is reached
// through a separate public API from ordinary glyphIndex(). Keep that lazy path
// under the same ownership contract as scalar lookup.
test "cmap format 14 public lookup revalidates cached subtable length" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectVariationGlyph(&font);

    const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
    const cmap_data = (try font.tableData(.{ 'c', 'm', 'a', 'p' })).?;
    const variation_offset = readU32(bytes, cmap_offset + 16);
    sfnt_fixture.writeU32(
        bytes,
        cmap_offset + variation_offset + 2,
        @intCast(cmap_data.len - variation_offset + 1),
    );
    try expectVariationLookupError(&font, error.BadSfnt);
}

test "cmap public lookup revalidates cached encoding record offsets" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildSingleCodepointTtf(allocator, 'A');
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectEqual(
            @as(GlyphId, 1),
            try font.glyphIndex('A'),
        );

        const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
        const format4_offset = readU32(bytes, cmap_offset + 8);
        // The cached subtable still targets the old bytes; changing only its
        // EncodingRecord parent must invalidate public lookup.
        sfnt_fixture.writeU32(
            bytes,
            cmap_offset + 8,
            @intCast(format4_offset + 2),
        );
        try std.testing.expectError(error.BadSfnt, font.glyphIndex('A'));
    }

    {
        const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try expectVariationGlyph(&font);

        const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
        const variation_offset = readU32(bytes, cmap_offset + 16);
        sfnt_fixture.writeU32(
            bytes,
            cmap_offset + 16,
            @intCast(variation_offset + 2),
        );
        try expectVariationLookupError(&font, error.BadSfnt);
    }
}

test "cmap public lookup revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildSingleCodepointTtf(allocator, 'A');
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectEqual(
            @as(GlyphId, 1),
            try font.glyphIndex('A'),
        );

        const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
        const format4_offset = readU32(bytes, cmap_offset + 8);
        // Keep cmap structurally valid and maxp-compatible while changing the
        // result to glyph 0. Checksum revalidation must still reject it.
        sfnt_fixture.writeI16(
            bytes,
            cmap_offset + format4_offset + 24,
            -@as(i16, @intCast('A')),
        );
        try std.testing.expectError(error.BadSfnt, font.glyphIndex('A'));
    }

    {
        const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try expectVariationGlyph(&font);

        const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
        const variation_offset = readU32(bytes, cmap_offset + 16);
        sfnt_fixture.writeU16(
            bytes,
            cmap_offset + variation_offset + 36,
            1,
        );
        try expectVariationLookupError(&font, error.BadSfnt);
    }
}

test "cmap public APIs reject invalid Unicode scalar inputs" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectError(
        error.InvalidCodepoint,
        font.glyphIndex(0xd800),
    );
    try std.testing.expectError(
        error.InvalidCodepoint,
        font.variationGlyphIndex(0xd800, 0xfe0f),
    );
    try std.testing.expectError(
        error.InvalidCodepoint,
        font.glyphIndexWithVariation(0xd800, 0xfe0f),
    );
    try std.testing.expectError(
        error.InvalidCodepoint,
        font.variationGlyphIndex('A', 'x'),
    );
    try std.testing.expectError(
        error.InvalidCodepoint,
        font.glyphIndexWithVariation('A', 'x'),
    );
    try expectVariationGlyph(&font);
}

test "cmap public glyph lookup revalidates borrowed glyph ids" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildSingleCodepointTtf(allocator, 'A');
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(
        @as(GlyphId, 1),
        try font.glyphIndex('A'),
    );

    const cmap_offset = try sfnt_fixture.tableOffset(bytes, "cmap");
    const format4_offset = readU32(bytes, cmap_offset + 8);
    // The same cached bytes now map U+0041 to glyph 2, while maxp declares only
    // glyph IDs 0 and 1. Public lookup must re-check that cross-table contract.
    sfnt_fixture.writeI16(
        bytes,
        cmap_offset + format4_offset + 24,
        @as(i16, 2) - @as(i16, @bitCast(@as(u16, 'A'))),
    );
    try std.testing.expectError(error.BadSfnt, font.glyphIndex('A'));
}

fn expectVariationGlyph(font: *const Font) !void {
    try std.testing.expectEqual(
        @as(?GlyphId, 3),
        try font.variationGlyphIndex('A', 0xfe0f),
    );
}

fn expectVariationLookupError(
    font: *const Font,
    expected: anyerror,
) !void {
    try std.testing.expectError(
        expected,
        font.variationGlyphIndex('A', 0xfe0f),
    );
    try std.testing.expectError(
        expected,
        font.glyphIndexWithVariation('A', 0xfe0f),
    );
}

fn readU32(bytes: []const u8, offset: usize) usize {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}
