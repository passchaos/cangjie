//! CFF/maxp integration, subset, and borrowed-outline contracts.

const std = @import("std");
const font_mod = @import("../../font.zig");
const cff = @import("../../cff.zig");
const test_font = @import("../../test_font.zig");
const fixture = @import("fixtures/sfnt.zig");

const Font = font_mod.Font;
const FontFormat = font_mod.FontFormat;

test "CFF CharStrings INDEX count must match maxp glyph count" {
    const allocator = std.testing.allocator;
    inline for (.{
        @as(u16, 1),
        @as(u16, 3),
    }) |glyph_count| {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);

        const hhea_offset = try fixture.tableOffset(bytes, "hhea");
        const maxp_offset = try fixture.tableOffset(bytes, "maxp");
        // Keep hmtx structurally valid for both altered glyph counts so this
        // regression reaches the CFF/maxp cross-table check rather than failing
        // earlier in generic horizontal-metrics validation.
        fixture.writeU16(bytes, hhea_offset + 34, 1);
        fixture.writeU16(bytes, maxp_offset + 4, glyph_count);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "OpenType layout-only subsets do not require CFF outlines for shaping" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLayoutOnlyOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(FontFormat.opentype_cff, font.format);
    try std.testing.expect(!font.hasOutlineData());
    try std.testing.expectError(error.MissingTable, font.glyphOutline(allocator, 1));
}

test "OpenType CFF table rejects malformed CFF header fields at parse time" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const cff_offset = try fixture.tableOffset(bytes, "CFF ");
        bytes[cff_offset] = 2;
        try std.testing.expectError(error.BadCff, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const cff_offset = try fixture.tableOffset(bytes, "CFF ");
        bytes[cff_offset + 2] = 3;
        try std.testing.expectError(error.BadCff, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const cff_offset = try fixture.tableOffset(bytes, "CFF ");
        bytes[cff_offset + 3] = 0;
        try std.testing.expectError(error.BadCff, Font.parse(allocator, bytes));
    }
}

test "CFF glyph outlines revalidate borrowed CharStrings count" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const cff_offset = try fixture.tableOffset(bytes, "CFF ");
    const cff_length = try fixture.tableLength(bytes, "CFF ");
    const info = try cff.parseInfo(bytes[cff_offset .. cff_offset + cff_length]);

    // Mutate only the borrowed CFF payload after Font.parse. Glyph 0 still has
    // a valid charstring, so this regression exercises full-table revalidation
    // rather than per-request bounds checking in cff.appendGlyphOutline.
    fixture.writeU16(bytes, cff_offset + info.charstrings_offset, 1);

    try std.testing.expectError(error.BadSfnt, font.glyphOutline(allocator, 0));
}
