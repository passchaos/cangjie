//! Focused cmap validation contracts.

const std = @import("std");
const cmap_mod = @import("../../../tables/cmap/root.zig");
const glyph = @import("../../../../glyph.zig");
const sfnt = @import("../../../sfnt/root.zig");
const font_mod = @import("../../../../font.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("support.zig");

const Font = font_mod.Font;
const TableRecord = sfnt.Record;

test "Unicode cmap subtables reject surrogate and non-scalar character ranges" {
    const allocator = std.testing.allocator;

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 44,
        };
        var surrogate_format4: [44]u8 = .{0} ** 44;
        support.writeFormat4Header(&surrogate_format4, surrogate_format4.len - 12);
        support.writeFormat4Segment(&surrogate_format4, 0, 0xd7ff, 0xd800, 0x2802, 0);
        support.writeFormat4Segment(&surrogate_format4, 1, 0xffff, 0xffff, 1, 0);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &surrogate_format4, cmap, 512));

        var symbol_format4 = surrogate_format4;
        fixture.writeU16(&symbol_format4, 6, 0); // Windows symbol encoding is not a Unicode-scalar cmap_mod.
        const subtables = try cmap_mod.parse(allocator, &symbol_format4, cmap, 512);
        allocator.free(subtables);
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 24,
        };
        var surrogate_format6: [24]u8 = .{0} ** 24;
        fixture.writeU16(&surrogate_format6, 0, 0);
        fixture.writeU16(&surrogate_format6, 2, 1);
        fixture.writeU16(&surrogate_format6, 4, 3);
        fixture.writeU16(&surrogate_format6, 6, 1);
        fixture.writeU32(&surrogate_format6, 8, 12);
        fixture.writeU16(&surrogate_format6, 12, 6);
        fixture.writeU16(&surrogate_format6, 14, 12);
        fixture.writeU16(&surrogate_format6, 18, 0xd800);
        fixture.writeU16(&surrogate_format6, 20, 1);
        fixture.writeU16(&surrogate_format6, 22, 1);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &surrogate_format6, cmap, 512));
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 40,
        };
        var surrogate_format12: [40]u8 = .{0} ** 40;
        support.writeFormat12Header(&surrogate_format12, surrogate_format12.len - 12, 1);
        support.writeGroup(&surrogate_format12, 28, 0xd7ff, 0xe000, 1);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &surrogate_format12, cmap, 512));

        var nonscalar_format12 = surrogate_format12;
        support.writeGroup(&nonscalar_format12, 28, 0x110000, 0x110000, 1);
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &nonscalar_format12, cmap, 512));
    }
}

test "cmap format 8 validates mixed-width structure and lookup" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 8244,
    };

    var valid: [8244]u8 = .{0} ** 8244;
    support.writeFormat8Header(&valid, valid.len - 12, 2);
    support.setFormat8Is32(&valid, 1, true);
    support.writeGroup(&valid, 8220, 'A', 'A', 5);
    support.writeGroup(&valid, 8232, 0x10000, 0x10001, 6);

    const subtables = try cmap_mod.parse(allocator, &valid, cmap, 16);
    defer allocator.free(subtables);
    try std.testing.expectEqual(@as(glyph.GlyphId, 5), try cmap_mod.glyph(&valid, .{ .platform_id = 0, .encoding_id = 4, .offset = 12, .length = valid.len - 12, .format = 8 }, 'A'));
    try std.testing.expectEqual(@as(glyph.GlyphId, 6), try cmap_mod.glyph(&valid, .{ .platform_id = 0, .encoding_id = 4, .offset = 12, .length = valid.len - 12, .format = 8 }, 0x10000));
    try std.testing.expectEqual(@as(glyph.GlyphId, 7), try cmap_mod.glyph(&valid, .{ .platform_id = 0, .encoding_id = 4, .offset = 12, .length = valid.len - 12, .format = 8 }, 0x10001));
    try std.testing.expectEqual(@as(glyph.GlyphId, 0), try cmap_mod.glyph(&valid, .{ .platform_id = 0, .encoding_id = 4, .offset = 12, .length = valid.len - 12, .format = 8 }, 0x20000));

    var bad_reserved = valid;
    fixture.writeU16(&bad_reserved, 14, 1);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &bad_reserved, cmap, 16));

    var extra_bytes = valid;
    fixture.writeU32(&extra_bytes, 16, valid.len - 10);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &extra_bytes, cmap, 16));

    var missing_is32 = valid;
    support.setFormat8Is32(&missing_is32, 1, false);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &missing_is32, cmap, 16));

    var bmp_marked_32 = valid;
    support.setFormat8Is32(&bmp_marked_32, 'A', true);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &bmp_marked_32, cmap, 16));

    var unsorted = valid;
    support.writeGroup(&unsorted, 8232, 0x40, 0x40, 6);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &unsorted, cmap, 16));

    var bad_glyph = valid;
    support.writeGroup(&bad_glyph, 8232, 0x10000, 0x10001, 15);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &bad_glyph, cmap, 16));
}

test "cmap segmented groups must be sorted and disjoint" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 52,
    };

    var valid: [52]u8 = .{0} ** 52;
    support.writeFormat12Header(&valid, valid.len - 12, 2);
    support.writeGroup(&valid, 28, 0x100, 0x1ff, 4);
    support.writeGroup(&valid, 40, 0x200, 0x200, 0x104);
    const subtables = try cmap_mod.parse(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var unsorted = valid;
    support.writeGroup(&unsorted, 40, 0x050, 0x060, 0x104);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &unsorted, cmap, 512));

    var overlapping = valid;
    support.writeGroup(&overlapping, 40, 0x1ff, 0x200, 0x104);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &overlapping, cmap, 512));

    var extra_bytes: [56]u8 = .{0} ** 56;
    support.writeFormat12Header(&extra_bytes, extra_bytes.len - 12, 2);
    support.writeGroup(&extra_bytes, 28, 0x100, 0x1ff, 4);
    support.writeGroup(&extra_bytes, 40, 0x200, 0x200, 0x104);
    const extra_cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = extra_bytes.len,
    };
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &extra_bytes, extra_cmap, 512));
}

test "cmap extended subtables require a zero reserved field" {
    const allocator = std.testing.allocator;

    {
        var format10: [34]u8 = .{0} ** 34;
        fixture.writeU16(&format10, 0, 0); // cmap version.
        fixture.writeU16(&format10, 2, 1);
        fixture.writeU16(&format10, 4, 0); // Unicode full repertoire.
        fixture.writeU16(&format10, 6, 4);
        fixture.writeU32(&format10, 8, 12);
        fixture.writeU16(&format10, 12, 10);
        fixture.writeU16(&format10, 14, 1); // Reserved UInt16 must remain zero.
        fixture.writeU32(&format10, 16, 22);
        fixture.writeU32(&format10, 24, 0x10000);
        fixture.writeU32(&format10, 28, 1);
        fixture.writeU16(&format10, 32, 1);

        const cmap: TableRecord = .{ .tag = .{ 'c', 'm', 'a', 'p' }, .checksum = 0, .offset = 0, .length = format10.len };
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &format10, cmap, 4));
    }

    {
        var format12: [40]u8 = .{0} ** 40;
        support.writeFormat12Header(&format12, format12.len - 12, 1);
        fixture.writeU16(&format12, 14, 1); // Reserved UInt16 must remain zero.
        support.writeGroup(&format12, 28, 0x100, 0x100, 1);

        const cmap: TableRecord = .{ .tag = .{ 'c', 'm', 'a', 'p' }, .checksum = 0, .offset = 0, .length = format12.len };
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &format12, cmap, 4));
    }

    {
        var format13: [40]u8 = .{0} ** 40;
        fixture.writeU16(&format13, 0, 0); // cmap version.
        fixture.writeU16(&format13, 2, 1);
        fixture.writeU16(&format13, 4, 0); // Unicode last-resort cmap_mod.
        fixture.writeU16(&format13, 6, 6);
        fixture.writeU32(&format13, 8, 12);
        fixture.writeU16(&format13, 12, 13);
        fixture.writeU16(&format13, 14, 1); // Reserved UInt16 must remain zero.
        fixture.writeU32(&format13, 16, 28);
        fixture.writeU32(&format13, 24, 1);
        support.writeGroup(&format13, 28, 0x100, 0x1ff, 1);

        const cmap: TableRecord = .{ .tag = .{ 'c', 'm', 'a', 'p' }, .checksum = 0, .offset = 0, .length = format13.len };
        try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &format13, cmap, 4));

        fixture.writeU16(&format13, 4, 3); // Windows platform.
        fixture.writeU16(&format13, 6, 10); // Unicode full repertoire.
        fixture.writeU16(&format13, 14, 0);
        const subtables = try cmap_mod.parse(allocator, &format13, cmap, 4);
        defer allocator.free(subtables);
        try std.testing.expectEqual(@as(usize, 1), subtables.len);
        try std.testing.expectEqual(@as(u16, 13), subtables[0].format);
    }
}
