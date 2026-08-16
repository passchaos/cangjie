//! HVAR/VVAR/MVAR ItemVariationStore and map ownership contracts.

const std = @import("std");
const validation = @import("../../../tables/variations/metrics/root.zig");
const sfnt = @import("../../../sfnt/root.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("support.zig");
const variations = @import("../support.zig");

const Record = sfnt.Record;

test "VariationStore data validates axis and region indexes" {
    var bytes: [54]u8 = .{0} ** 54;
    support.writeHvarWithOneItem(&bytes);
    const hvar = Record{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validation.validateHvar(&bytes, hvar, 1);

    var axis_mismatch = bytes;
    fixture.writeU16(&axis_mismatch, 32, 2); // VariationRegionList axisCount.
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&axis_mismatch, hvar, 1));

    var bad_region_index = bytes;
    fixture.writeU16(&bad_region_index, 50, 1); // Only region index 0 is declared.
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&bad_region_index, hvar, 1));

    var with_map: [59]u8 = .{0} ** 59;
    @memcpy(with_map[0..bytes.len], &bytes);
    fixture.writeU32(&with_map, 8, 54); // AdvanceWidthMappingOffset follows the store.
    with_map[54] = 0; // DeltaSetIndexMap format 0.
    with_map[55] = 0; // one-byte entries, one inner-index bit.
    fixture.writeU16(&with_map, 56, 1); // mapCount.
    with_map[58] = 0; // outerIndex 0, innerIndex 0.
    const hvar_with_map = Record{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = with_map.len };
    try validation.validateHvar(&with_map, hvar_with_map, 1);

    var map_aliases_store = with_map;
    fixture.writeU32(&map_aliases_store, 8, 20); // A map must not reinterpret ItemVariationStore bytes.
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&map_aliases_store, hvar_with_map, 1));

    var maps_alias_each_other = with_map;
    fixture.writeU32(&maps_alias_each_other, 12, 54); // Duplicate DeltaSetIndexMap payload.
    try validation.validateHvar(&maps_alias_each_other, hvar_with_map, 1);

    var peak_outside_normalized_space = bytes;
    fixture.writeI16(&peak_outside_normalized_space, 38, 0x4001);
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&peak_outside_normalized_space, hvar, 1));

    var reversed_region = bytes;
    variations.writeF2Dot14(&reversed_region, 36, 0.5); // regionStartCoord > peakCoord.
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&reversed_region, hvar, 1));
}

test "VariationStore child payloads do not alias each other" {
    var bytes: [64]u8 = .{0} ** 64;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0);
    fixture.writeU32(&bytes, 4, 20); // ItemVariationStore offset.

    fixture.writeU16(&bytes, 20, 1); // ItemVariationStore format.
    fixture.writeU32(&bytes, 22, 16); // VariationRegionList follows both ItemVariationData offsets.
    fixture.writeU16(&bytes, 26, 2); // itemVariationDataCount.
    fixture.writeU32(&bytes, 28, 28); // First ItemVariationData.
    fixture.writeU32(&bytes, 32, 38); // Second ItemVariationData is adjacent to the first.

    fixture.writeU16(&bytes, 36, 1); // axisCount.
    fixture.writeU16(&bytes, 38, 1); // regionCount.
    variations.writeF2Dot14(&bytes, 40, -1.0);
    variations.writeF2Dot14(&bytes, 42, 0.0);
    variations.writeF2Dot14(&bytes, 44, 1.0);

    fixture.writeU16(&bytes, 48, 1); // itemCount.
    fixture.writeU16(&bytes, 50, 1); // wordDeltaCount.
    fixture.writeU16(&bytes, 52, 1); // regionIndexCount.
    fixture.writeU16(&bytes, 54, 0); // regionIndexes[0].
    fixture.writeI16(&bytes, 56, 7); // delta row.

    fixture.writeU16(&bytes, 58, 0); // Empty second ItemVariationData is adjacent and valid.
    fixture.writeU16(&bytes, 60, 0);
    fixture.writeU16(&bytes, 62, 0);

    const hvar = Record{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validation.validateHvar(&bytes, hvar, 1);

    var item_data_alias = bytes;
    fixture.writeU32(&item_data_alias, 32, 28); // Duplicate ItemVariationData offset.
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&item_data_alias, hvar, 1));

    var region_alias: [42]u8 = .{0} ** 42;
    fixture.writeU16(&region_alias, 0, 1);
    fixture.writeU16(&region_alias, 2, 0);
    fixture.writeU32(&region_alias, 4, 20); // ItemVariationStore offset.
    fixture.writeU16(&region_alias, 20, 1); // ItemVariationStore format.
    fixture.writeU32(&region_alias, 22, 16); // Empty VariationRegionList.
    fixture.writeU16(&region_alias, 26, 1); // itemVariationDataCount.
    fixture.writeU32(&region_alias, 28, 16); // ItemVariationData aliases the region-list header.
    const hvar_zero_axis = Record{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = region_alias.len };
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&region_alias, hvar_zero_axis, 0));
}

test "VariationStore permits zero-region data with zero-width rows" {
    var bytes: [42]u8 = .{0} ** 42;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0);
    fixture.writeU32(&bytes, 4, 20); // ItemVariationStore offset.

    fixture.writeU16(&bytes, 20, 1); // ItemVariationStore format.
    fixture.writeU32(&bytes, 22, 12); // Empty VariationRegionList.
    fixture.writeU16(&bytes, 26, 1); // itemVariationDataCount.
    fixture.writeU32(&bytes, 28, 16); // ItemVariationData follows region list.

    fixture.writeU16(&bytes, 32, 0); // axisCount.
    fixture.writeU16(&bytes, 34, 0); // regionCount.

    fixture.writeU16(&bytes, 36, 3); // itemCount with zero-width delta rows.
    fixture.writeU16(&bytes, 38, 0); // wordDeltaCount.
    fixture.writeU16(&bytes, 40, 0); // regionIndexCount.

    const hvar = Record{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validation.validateHvar(&bytes, hvar, 0);
}

test "Metric variation DeltaSetIndexMaps own disjoint top-level payloads" {
    var hvar_bytes: [62]u8 = .{0} ** 62;
    support.writeMetricHeader(&hvar_bytes, 20, 28);
    support.writeItemStoreOne(&hvar_bytes, 28);
    const hvar = Record{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = hvar_bytes.len };
    try validation.validateHvar(&hvar_bytes, hvar, 1);

    var map_aliases_store = hvar_bytes;
    fixture.writeU32(&map_aliases_store, 8, 28); // advanceWidthMappingOffset aliases ItemVariationStore.
    try std.testing.expectError(error.BadSfnt, validation.validateHvar(&map_aliases_store, hvar, 1));

    var duplicate_maps = hvar_bytes;
    fixture.writeU32(&duplicate_maps, 12, 20); // lsbMappingOffset reuses advanceWidthMappingOffset.
    try validation.validateHvar(&duplicate_maps, hvar, 1);

    var vvar_bytes: [66]u8 = .{0} ** 66;
    fixture.writeU16(&vvar_bytes, 0, 1);
    fixture.writeU16(&vvar_bytes, 2, 0);
    fixture.writeU32(&vvar_bytes, 4, 32); // ItemVariationStore offset.
    fixture.writeU32(&vvar_bytes, 20, 24); // VVAR-only vorgMappingOffset.
    support.writeMap(&vvar_bytes, 24);
    support.writeItemStoreOne(&vvar_bytes, 32);
    const vvar = Record{ .tag = .{ 'V', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = vvar_bytes.len };
    try validation.validateVvar(&vvar_bytes, vvar, 1);

    var fourth_map_aliases_store = vvar_bytes;
    fixture.writeU32(&fourth_map_aliases_store, 20, 32); // vorgMappingOffset aliases ItemVariationStore.
    try std.testing.expectError(error.BadSfnt, validation.validateVvar(&fourth_map_aliases_store, vvar, 1));
}

test "MVAR value records reference existing ItemVariationData items" {
    var bytes: [54]u8 = .{0} ** 54;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0);
    fixture.writeU16(&bytes, 6, 8); // valueRecordSize.
    fixture.writeU16(&bytes, 8, 1); // one value record.
    fixture.writeU16(&bytes, 10, 20); // ItemVariationStore offset.
    @memcpy(bytes[12..16], "hasc");
    fixture.writeU16(&bytes, 16, 0); // outerIndex.
    fixture.writeU16(&bytes, 18, 0); // innerIndex.
    support.writeItemStoreOne(&bytes, 20);

    const mvar = Record{ .tag = .{ 'M', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validation.validateMvar(&bytes, mvar, 1);

    var bad_inner_index = bytes;
    fixture.writeU16(&bad_inner_index, 18, 1);
    try std.testing.expectError(error.BadSfnt, validation.validateMvar(&bad_inner_index, mvar, 1));
}
