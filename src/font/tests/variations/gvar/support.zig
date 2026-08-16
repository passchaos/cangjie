//! Binary fixtures shared by focused gvar validation tests.

const fixture = @import("../../fixtures/sfnt.zig");
const variations = @import("../support.zig");

pub fn writeFvarAxis(bytes: []u8) void {
    variations.writeFvarHeader(bytes, 1);
    variations.writeAxis(bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
}

pub fn writePrivatePointTuple(bytes: []u8, offset: usize) void {
    fixture.writeU16(bytes, offset + 0, 1);
    fixture.writeU16(bytes, offset + 2, 0);
    fixture.writeU16(bytes, offset + 4, 1);
    fixture.writeU16(bytes, offset + 12, 1);
    fixture.writeU32(bytes, offset + 16, 24);
    fixture.writeU16(bytes, offset + 20, 0);
    fixture.writeU16(bytes, offset + 22, 8);

    const glyph = offset + 24;
    fixture.writeU16(bytes, glyph + 0, 1);
    fixture.writeU16(bytes, glyph + 2, 10);
    fixture.writeU16(bytes, glyph + 4, 6);
    fixture.writeU16(bytes, glyph + 6, 0xa000);
    variations.writeF2Dot14(bytes, glyph + 8, 1.0);
    bytes[glyph + 10] = 1;
    bytes[glyph + 11] = 0;
    bytes[glyph + 12] = 0;
    bytes[glyph + 13] = 0x80;
    bytes[glyph + 14] = 0;
    bytes[glyph + 15] = 7;
}

pub fn writeSharedTuple(bytes: []u8, offset: usize, peak: f32) void {
    fixture.writeU16(bytes, offset + 0, 1);
    fixture.writeU16(bytes, offset + 2, 0);
    fixture.writeU16(bytes, offset + 4, 1);
    fixture.writeU16(bytes, offset + 6, 1);
    fixture.writeU32(bytes, offset + 8, 24);
    fixture.writeU16(bytes, offset + 12, 1);
    fixture.writeU32(bytes, offset + 16, 26);
    fixture.writeU16(bytes, offset + 20, 0);
    fixture.writeU16(bytes, offset + 22, 8);
    variations.writeF2Dot14(bytes, offset + 24, peak);

    const glyph = offset + 26;
    fixture.writeU16(bytes, glyph + 0, 1);
    fixture.writeU16(bytes, glyph + 2, 8);
    fixture.writeU16(bytes, glyph + 4, 6);
    fixture.writeU16(bytes, glyph + 6, 0x2000);
    bytes[glyph + 8] = 1;
    bytes[glyph + 9] = 0;
    bytes[glyph + 10] = 0;
    bytes[glyph + 11] = 0x80;
    bytes[glyph + 12] = 0;
    bytes[glyph + 13] = 7;
}

pub fn writeIntermediateTuple(
    bytes: []u8,
    offset: usize,
    start: f32,
    peak: f32,
    end: f32,
) void {
    fixture.writeU16(bytes, offset + 0, 1);
    fixture.writeU16(bytes, offset + 2, 0);
    fixture.writeU16(bytes, offset + 4, 1);
    fixture.writeU16(bytes, offset + 12, 1);
    fixture.writeU32(bytes, offset + 16, 24);
    fixture.writeU16(bytes, offset + 20, 0);
    fixture.writeU16(bytes, offset + 22, 10);

    const glyph = offset + 24;
    fixture.writeU16(bytes, glyph + 0, 1);
    fixture.writeU16(bytes, glyph + 2, 14);
    fixture.writeU16(bytes, glyph + 4, 6);
    fixture.writeU16(bytes, glyph + 6, 0xe000);
    variations.writeF2Dot14(bytes, glyph + 8, peak);
    variations.writeF2Dot14(bytes, glyph + 10, start);
    variations.writeF2Dot14(bytes, glyph + 12, end);
    bytes[glyph + 14] = 1;
    bytes[glyph + 15] = 0;
    bytes[glyph + 16] = 0;
    bytes[glyph + 17] = 0x80;
    bytes[glyph + 18] = 0;
    bytes[glyph + 19] = 7;
}
