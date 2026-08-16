//! Font-level GSUB/GPOS validation and borrowed public API contracts.

const std = @import("std");
const font_mod = @import("../../../font.zig");
const gpos = @import("../../../gpos.zig");
const glyph = @import("../../../glyph.zig");
const test_font = @import("../../../test_font.zig");
const fixture = @import("../../../font/tests/fixtures/sfnt.zig");

const Font = font_mod.Font;

test "GPOS glyph ids are validated against maxp glyph count" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalGposTtf(allocator);
        defer allocator.free(bytes);
        const gpos_offset = try fixture.tableOffset(bytes, "GPOS");
        // The fixture declares maxp.numGlyphs == 2, so the PairValueRecord's
        // secondGlyph must be 0 or 1. Runtime shaping might never see this
        // pair, but parse-time validation should reject the dangling glyph id.
        fixture.writeU16(bytes, gpos_offset + 56, 2);
        try std.testing.expectError(error.BadGpos, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
        defer allocator.free(bytes);
        const gpos_offset = try fixture.tableOffset(bytes, "GPOS");
        fixture.writeU16(bytes, gpos_offset + 42, 2); // SinglePos Coverage glyph.
        try std.testing.expectError(error.BadGpos, Font.parse(allocator, bytes));
    }
}

test "GSUB glyph ids are validated against maxp glyph count at parse time" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        const gsub_offset = try fixture.tableOffset(bytes, "GSUB");
        // The fixture declares maxp.numGlyphs == 3. A ligature result glyph of
        // 3 is structurally well-formed GSUB data, but it cannot be shaped into
        // this face because later metrics/outline lookups only cover glyphs 0-2.
        fixture.writeU16(bytes, gsub_offset + 46, 3);
        try std.testing.expectError(error.BadGsub, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildReverseChainingGsubTtf(allocator);
        defer allocator.free(bytes);
        const gsub_offset = try fixture.tableOffset(bytes, "GSUB");
        // ReverseChainSingleSubst substitutes are often applied late and only
        // for matching context. Parse-time validation should still reject a
        // latent out-of-range replacement before shaping exposes it.
        fixture.writeU16(bytes, gsub_offset + 72, 4);
        try std.testing.expectError(error.BadGsub, Font.parse(allocator, bytes));
    }
}

test "GSUB and GPOS public APIs reject out-of-range glyph runs" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.append(allocator, 3); // maxp.numGlyphs is 3; valid ids are 0, 1, and 2.

        try std.testing.expectError(
            error.InvalidGlyph,
            font_mod.shaping.applyGsub(&font, &glyphs, allocator),
        );
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.append(allocator, 2); // No GSUB table is present, but the caller contract still applies.

        try std.testing.expectError(
            error.InvalidGlyph,
            font_mod.shaping.applyGsub(&font, &glyphs, allocator),
        );
    }

    {
        const bytes = try test_font.buildMinimalGposTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph.GlyphId{2}; // maxp.numGlyphs is 2; valid ids are 0 and 1.

        try std.testing.expectError(
            error.InvalidGlyph,
            font_mod.shaping.collectGposAdjustments(
                &font,
                &glyphs,
                &adjustments,
                allocator,
            ),
        );
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph.GlyphId{2}; // No GPOS table is present, but invalid run data is not "no positioning".

        try std.testing.expectError(
            error.InvalidGlyph,
            font_mod.shaping.collectGposAdjustments(
                &font,
                &glyphs,
                &adjustments,
                allocator,
            ),
        );
    }
}

test "GSUB and GPOS public APIs revalidate borrowed table glyph references" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.appendSlice(allocator, &.{ 1, 2 });

        const gsub_offset = try fixture.tableOffset(bytes, "GSUB");
        // Font.parse validated this borrowed GSUB table. Mutating the
        // ligature-result glyph after parse must not be deferred until the
        // substitution path writes a glyph ID that lacks metrics/outlines.
        fixture.writeU16(bytes, gsub_offset + 46, 3);
        try std.testing.expectError(
            error.BadSfnt,
            font_mod.shaping.applyGsub(&font, &glyphs, allocator),
        );
    }

    {
        const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph.GlyphId{1};

        const gpos_offset = try fixture.tableOffset(bytes, "GPOS");
        // The changed coverage glyph is not in the caller's run. The public
        // positioning API still revalidates all supported lookup payloads so an
        // unrelated feature cannot leave corrupted borrowed bytes latent.
        fixture.writeU16(bytes, gpos_offset + 42, 2);
        try std.testing.expectError(
            error.BadSfnt,
            font_mod.shaping.collectGposAdjustments(
                &font,
                &glyphs,
                &adjustments,
                allocator,
            ),
        );
    }
}

test "GSUB and GPOS public APIs revalidate borrowed table checksums" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.appendSlice(allocator, &.{ 1, 2 });

        const gsub_offset = try fixture.tableOffset(bytes, "GSUB");
        // Keep the ligature result inside maxp while changing the borrowed
        // shaping payload after Font.parse. The public API must reject it
        // because GSUB's SFNT checksum no longer matches.
        fixture.writeU16(bytes, gsub_offset + 46, 1);
        try std.testing.expectError(
            error.BadSfnt,
            font_mod.shaping.applyGsub(&font, &glyphs, allocator),
        );
    }

    {
        const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph.GlyphId{1};

        const gpos_offset = try fixture.tableOffset(bytes, "GPOS");
        fixture.writeI16(bytes, gpos_offset + 32, 40);
        try std.testing.expectError(
            error.BadSfnt,
            font_mod.shaping.collectGposAdjustments(
                &font,
                &glyphs,
                &adjustments,
                allocator,
            ),
        );
    }
}
