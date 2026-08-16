//! Public `maxp` metadata and outline-format integration tests.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "maxp metadata exposes TrueType and compact CFF profiles" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const profile = try font.maxpInfo();
        try std.testing.expectEqual(@as(u32, 0x00010000), profile.version);
        try std.testing.expectEqual(@as(u16, 2), profile.glyph_count);
        try std.testing.expectEqual(@as(?u16, 3), profile.max_points);
        try std.testing.expectEqual(@as(?u16, 2), profile.max_zones);
        try std.testing.expectEqual(
            @as(?u16, 0),
            profile.max_component_depth,
        );

        const maxp_offset = try sfnt_fixture.tableOffset(bytes, "maxp");
        // maxZones=1 remains semantically accepted, isolating checksum
        // revalidation from the table grammar.
        sfnt_fixture.writeU16(bytes, maxp_offset + 14, 1);
        try std.testing.expectError(error.BadSfnt, font.maxpInfo());
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const profile = try font.maxpInfo();
        try std.testing.expectEqual(@as(u32, 0x00005000), profile.version);
        try std.testing.expectEqual(@as(u16, 2), profile.glyph_count);
        try std.testing.expectEqual(@as(?u16, null), profile.max_points);
        try std.testing.expectEqual(@as(?u16, null), profile.max_zones);
    }
}

test "maxp version and length match the selected outline format" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfnt_fixture.tableOffset(bytes, "maxp");
        sfnt_fixture.writeU32(bytes, maxp_offset, 0x00005000);
        try sfnt_fixture.updateTableChecksum(bytes, "maxp");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try sfnt_fixture.setTableLength(bytes, "maxp", 6);
        try sfnt_fixture.updateTableChecksum(bytes, "maxp");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const original = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(original);
        const bytes = try allocator.alloc(u8, original.len + 4);
        defer allocator.free(bytes);
        @memcpy(bytes[0..original.len], original);
        @memset(bytes[original.len..], 0);
        try sfnt_fixture.setTableLength(bytes, "maxp", 33);
        try sfnt_fixture.updateTableChecksum(bytes, "maxp");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfnt_fixture.tableOffset(bytes, "maxp");
        sfnt_fixture.writeU32(bytes, maxp_offset, 0x00010000);
        try sfnt_fixture.updateTableChecksum(bytes, "maxp");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const original = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(original);
        const bytes = try allocator.alloc(u8, original.len + 4);
        defer allocator.free(bytes);
        @memcpy(bytes[0..original.len], original);
        @memset(bytes[original.len..], 0);
        try sfnt_fixture.setTableLength(bytes, "maxp", 7);
        try sfnt_fixture.updateTableChecksum(bytes, "maxp");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }
}

test "TrueType maxZones remains compatibility metadata" {
    const allocator = std.testing.allocator;

    inline for (.{ 0, 1, 2, 3 }) |max_zones| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfnt_fixture.tableOffset(bytes, "maxp");
        // HarfBuzz and FreeType tolerate shaping-only subsets with stale
        // hinting maxima, so maxZones remains visible without rejecting a face.
        sfnt_fixture.writeU16(bytes, maxp_offset + 14, max_zones);
        try sfnt_fixture.updateTableChecksum(bytes, "maxp");

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectEqual(
            @as(?u16, max_zones),
            (try font.maxpInfo()).max_zones,
        );
    }
}
