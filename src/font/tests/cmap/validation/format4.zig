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

test "cmap format 4 parser rejects malformed segment metadata" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 44,
    };

    var valid: [44]u8 = .{0} ** 44;
    support.writeFormat4Header(&valid, valid.len - 12);
    support.writeFormat4Segment(&valid, 0, 'A', 'A', @as(i16, 1) - @as(i16, @bitCast(@as(u16, 'A'))), 0);
    support.writeFormat4Segment(&valid, 1, 0xffff, 0xffff, 1, 0);
    const subtables = try cmap_mod.parse(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var nonzero_reserved_pad = valid;
    fixture.writeU16(&nonzero_reserved_pad, 30, 1);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &nonzero_reserved_pad, cmap, 512));

    var odd_range_offset = valid;
    support.writeFormat4Segment(&odd_range_offset, 0, 'A', 'A', 0, 1);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &odd_range_offset, cmap, 512));

    var unsorted = valid;
    support.writeFormat4Segment(&unsorted, 1, 0x0040, 0xffff, 1, 0);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &unsorted, cmap, 512));

    var missing_sentinel = valid;
    support.writeFormat4Segment(&missing_sentinel, 1, 'Z', 'Z', 1, 0);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &missing_sentinel, cmap, 512));

    var sentinel_maps_real_glyph = valid;
    support.writeFormat4Segment(&sentinel_maps_real_glyph, 1, 0xffff, 0xffff, 2, 0);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &sentinel_maps_real_glyph, cmap, 512));

    var sentinel_uses_glyph_array = valid;
    support.writeFormat4Segment(&sentinel_uses_glyph_array, 1, 0xffff, 0xffff, 0, 2);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &sentinel_uses_glyph_array, cmap, 512));

    var bad_search_range = valid;
    fixture.writeU16(&bad_search_range, 20, 2);
    const bad_search_range_subtables = try cmap_mod.parse(allocator, &bad_search_range, cmap, 512);
    allocator.free(bad_search_range_subtables);

    var bad_entry_selector = valid;
    fixture.writeU16(&bad_entry_selector, 22, 0);
    const bad_entry_selector_subtables = try cmap_mod.parse(allocator, &bad_entry_selector, cmap, 512);
    allocator.free(bad_entry_selector_subtables);

    var bad_range_shift = valid;
    fixture.writeU16(&bad_range_shift, 24, 2);
    const bad_range_shift_subtables = try cmap_mod.parse(allocator, &bad_range_shift, cmap, 512);
    allocator.free(bad_range_shift_subtables);
}

test "cmap format 4 parser validates full idRangeOffset segment span" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 48,
    };

    var bytes: [48]u8 = .{0} ** 48;
    support.writeFormat4Header(&bytes, 36); // Declared subtable ends before the glyph array for 'C'.
    support.writeFormat4Segment(&bytes, 0, 'A', 'C', 0, 4);
    support.writeFormat4Segment(&bytes, 1, 0xffff, 0xffff, 1, 0);
    fixture.writeU16(&bytes, 44, 7); // Glyph for 'A' would fit.
    fixture.writeU16(&bytes, 46, 9); // Glyph for 'B' would fit; 'C' would not.

    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &bytes, cmap, 512));
}
