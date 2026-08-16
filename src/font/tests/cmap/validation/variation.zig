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

test "cmap format 14 UVS offsets cannot overlap selector records" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 41,
    };

    var valid: [41]u8 = .{0} ** 41;
    support.writeFormat14Header(&valid, 29, 1);
    support.writeU24(&valid, 22, 0x00fe0f); // Variation selector.
    fixture.writeU32(&valid, 25, 21); // Default UVS table starts after the selector record array.
    fixture.writeU32(&valid, 33, 1); // One default UVS range.
    support.writeU24(&valid, 37, 'A');
    valid[40] = 0; // additionalCount.
    const subtables = try cmap_mod.parse(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var default_overlap = valid;
    fixture.writeU32(&default_overlap, 25, 17); // Reinterprets selector-record fields as DefaultUVS data.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &default_overlap, cmap, 512));

    var non_default_overlap = valid;
    fixture.writeU32(&non_default_overlap, 25, 0);
    fixture.writeU32(&non_default_overlap, 29, 17); // Same metadata-overlap issue for NonDefaultUVS.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &non_default_overlap, cmap, 512));
}

test "cmap format 14 validates selectors and UVS Unicode scalar values" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 50,
    };

    var valid: [50]u8 = .{0} ** 50;
    support.writeFormat14Header(&valid, 38, 1);
    support.writeU24(&valid, 22, 0x0e0100); // Supplemental variation selector.
    fixture.writeU32(&valid, 25, 21);
    fixture.writeU32(&valid, 29, 29);
    fixture.writeU32(&valid, 33, 1);
    support.writeU24(&valid, 37, 'A');
    valid[40] = 0;
    fixture.writeU32(&valid, 41, 1);
    support.writeU24(&valid, 45, 'B');
    fixture.writeU16(&valid, 48, 1);
    const subtables = try cmap_mod.parse(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var bad_selector = valid;
    support.writeU24(&bad_selector, 22, 'A');
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &bad_selector, cmap, 512));

    var surrogate_default = valid;
    support.writeU24(&surrogate_default, 37, 0xd800);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &surrogate_default, cmap, 512));

    var spanning_default = valid;
    support.writeU24(&spanning_default, 37, 0xd7ff);
    spanning_default[40] = 1;
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &spanning_default, cmap, 512));

    var surrogate_non_default = valid;
    support.writeU24(&surrogate_non_default, 45, 0xd800);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &surrogate_non_default, cmap, 512));

    var duplicate_sequence = valid;
    support.writeU24(&duplicate_sequence, 45, 'A'); // 'A' is already covered by the DefaultUVS range.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &duplicate_sequence, cmap, 512));

    var overlapping_sets = valid;
    overlapping_sets[40] = 1; // DefaultUVS covers 'A' and 'B'; NonDefaultUVS maps 'B'.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &overlapping_sets, cmap, 512));
}

test "cmap format 14 UVS payloads cannot overlap or alias" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 70,
    };

    var valid: [70]u8 = .{0} ** 70;
    support.writeFormat14Header(&valid, 58, 2);
    support.writeU24(&valid, 22, 0x00fe0e);
    fixture.writeU32(&valid, 25, 32); // Selector 1 DefaultUVS: absolute 44..52.
    support.writeU24(&valid, 33, 0x00fe0f);
    fixture.writeU32(&valid, 40, 40); // Selector 2 NonDefaultUVS: absolute 52..61.
    fixture.writeU32(&valid, 44, 1);
    support.writeU24(&valid, 48, 'A');
    valid[51] = 0;
    fixture.writeU32(&valid, 52, 1);
    support.writeU24(&valid, 56, 'B');
    fixture.writeU16(&valid, 59, 1);
    const subtables = try cmap_mod.parse(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var cross_selector_alias = valid;
    fixture.writeU32(&cross_selector_alias, 40, 32); // Reuses selector 1's DefaultUVS bytes as selector 2 NonDefaultUVS.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &cross_selector_alias, cmap, 512));

    var same_selector_overlap = valid;
    fixture.writeU32(&same_selector_overlap, 29, 36); // Starts inside selector 1's DefaultUVS payload.
    fixture.writeU32(&same_selector_overlap, 48, 1);
    support.writeU24(&same_selector_overlap, 52, 'B');
    fixture.writeU16(&same_selector_overlap, 55, 1);
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &same_selector_overlap, cmap, 512));

    var cross_selector_partial_overlap = same_selector_overlap;
    fixture.writeU32(&cross_selector_partial_overlap, 29, 0);
    fixture.writeU32(&cross_selector_partial_overlap, 36, 36); // Selector 2 DefaultUVS starts inside selector 1's payload.
    try std.testing.expectError(error.BadSfnt, cmap_mod.parse(allocator, &cross_selector_partial_overlap, cmap, 512));
}
