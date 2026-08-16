//! Binary fixture helpers for focused OpenType name tests.

const name = @import("../../../../opentype/name.zig");
const fixture = @import("../../fixtures/sfnt.zig");

pub fn table(length: usize) name.Table {
    return .{ .offset = 0, .length = length };
}

pub fn writeRecord(
    bytes: []u8,
    offset: usize,
    platform_id: u16,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    length: u16,
    storage_offset: u16,
) void {
    fixture.writeU16(bytes, offset + 0, platform_id);
    fixture.writeU16(bytes, offset + 2, encoding_id);
    fixture.writeU16(bytes, offset + 4, language_id);
    fixture.writeU16(bytes, offset + 6, name_id);
    fixture.writeU16(bytes, offset + 8, length);
    fixture.writeU16(bytes, offset + 10, storage_offset);
}

pub fn writeUtf16Record(
    bytes: []u8,
    offset: usize,
    name_id: u16,
    length: u16,
    storage_offset: u16,
) void {
    writeRecord(
        bytes,
        offset,
        3,
        1,
        0x0409,
        name_id,
        length,
        storage_offset,
    );
}
