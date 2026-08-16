//! Binary ItemVariationStore and DeltaSetIndexMap fixtures.

const fixture = @import("../../fixtures/sfnt.zig");
const variations = @import("../support.zig");

pub fn writeHvarWithOneItem(bytes: []u8) void {
    fixture.writeU16(bytes, 0, 1);
    fixture.writeU16(bytes, 2, 0);
    fixture.writeU32(bytes, 4, 20);
    writeItemStoreWithItems(bytes, 20, 1);
}

pub fn writeMetricHeader(
    bytes: []u8,
    map_offset: usize,
    store_offset: usize,
) void {
    fixture.writeU16(bytes, 0, 1);
    fixture.writeU16(bytes, 2, 0);
    fixture.writeU32(bytes, 4, @intCast(store_offset));
    fixture.writeU32(bytes, 8, @intCast(map_offset));
    writeMap(bytes, map_offset);
}

pub fn writeMap(bytes: []u8, offset: usize) void {
    bytes[offset] = 0;
    bytes[offset + 1] = 0;
    fixture.writeU16(bytes, offset + 2, 1);
    bytes[offset + 4] = 0;
}

pub fn writeItemStoreOne(bytes: []u8, offset: usize) void {
    writeItemStoreWithItems(bytes, offset, 1);
}

pub fn writeItemStoreWithItems(
    bytes: []u8,
    offset: usize,
    item_count: u16,
) void {
    fixture.writeU16(bytes, offset, 1);
    fixture.writeU32(bytes, offset + 2, 12);
    fixture.writeU16(bytes, offset + 6, 1);
    fixture.writeU32(bytes, offset + 8, 24);
    fixture.writeU16(bytes, offset + 12, 1);
    fixture.writeU16(bytes, offset + 14, 1);
    variations.writeF2Dot14(bytes, offset + 16, -1.0);
    variations.writeF2Dot14(bytes, offset + 18, 0.0);
    variations.writeF2Dot14(bytes, offset + 20, 1.0);
    fixture.writeU16(bytes, offset + 24, item_count);
    fixture.writeU16(bytes, offset + 26, 1);
    fixture.writeU16(bytes, offset + 28, 1);
    fixture.writeU16(bytes, offset + 30, 0);
    for (0..item_count) |index| {
        fixture.writeI16(bytes, offset + 32 + index * 2, 7);
    }
}
