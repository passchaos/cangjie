//! Binary fixtures shared by focused STAT grammar tests.

const name = @import("../../../../opentype/name.zig");
const sfnt = @import("../../../sfnt/root.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const variation_support = @import("../support.zig");

pub const Coordinate = struct {
    axis_index: u16,
    value: f32,
};

pub fn record(offset: usize, length: usize) sfnt.Record {
    return .{
        .tag = .{ 'S', 'T', 'A', 'T' },
        .checksum = 0,
        .offset = offset,
        .length = length,
    };
}

pub fn names(ids: []const u16) name.NameIdIndex {
    return name.NameIdIndex.initForTest(ids);
}

pub fn writeHeader(
    bytes: []u8,
    offset: usize,
    design_axis_count: u16,
    axis_value_count: u16,
    axis_value_offsets_offset: u32,
) void {
    fixture.writeU16(bytes, offset + 0, 1);
    fixture.writeU16(bytes, offset + 2, 1);
    fixture.writeU16(bytes, offset + 4, 8);
    fixture.writeU16(bytes, offset + 6, design_axis_count);
    fixture.writeU32(bytes, offset + 8, 20);
    fixture.writeU16(bytes, offset + 12, axis_value_count);
    fixture.writeU32(bytes, offset + 14, axis_value_offsets_offset);
    fixture.writeU16(bytes, offset + 18, 2);
}

pub fn writeAxis(
    bytes: []u8,
    offset: usize,
    comptime tag: *const [4]u8,
    name_id: u16,
    ordering: u16,
) void {
    @memcpy(bytes[offset..][0..4], tag);
    fixture.writeU16(bytes, offset + 4, name_id);
    fixture.writeU16(bytes, offset + 6, ordering);
}

pub fn writeFormat1Default(
    bytes: []u8,
    offset: usize,
    axis_index: u16,
) void {
    writeFormat1(bytes, offset, axis_index, 258, 400.0);
}

pub fn writeFormat1(
    bytes: []u8,
    offset: usize,
    axis_index: u16,
    name_id: u16,
    value: f32,
) void {
    fixture.writeU16(bytes, offset + 0, 1);
    fixture.writeU16(bytes, offset + 2, axis_index);
    fixture.writeU16(bytes, offset + 4, 0);
    fixture.writeU16(bytes, offset + 6, name_id);
    variation_support.writeF16Dot16(bytes, offset + 8, value);
}

pub fn writeFormat2(
    bytes: []u8,
    offset: usize,
    axis_index: u16,
    name_id: u16,
    nominal: f32,
    minimum: f32,
    maximum: f32,
) void {
    fixture.writeU16(bytes, offset + 0, 2);
    fixture.writeU16(bytes, offset + 2, axis_index);
    fixture.writeU16(bytes, offset + 4, 0);
    fixture.writeU16(bytes, offset + 6, name_id);
    variation_support.writeF16Dot16(bytes, offset + 8, nominal);
    variation_support.writeF16Dot16(bytes, offset + 12, minimum);
    variation_support.writeF16Dot16(bytes, offset + 16, maximum);
}

pub fn writeFormat3(
    bytes: []u8,
    offset: usize,
    axis_index: u16,
    name_id: u16,
    value: f32,
    linked_value: f32,
) void {
    fixture.writeU16(bytes, offset + 0, 3);
    fixture.writeU16(bytes, offset + 2, axis_index);
    fixture.writeU16(bytes, offset + 4, 0);
    fixture.writeU16(bytes, offset + 6, name_id);
    variation_support.writeF16Dot16(bytes, offset + 8, value);
    variation_support.writeF16Dot16(bytes, offset + 12, linked_value);
}

pub fn writeFormat4(
    bytes: []u8,
    offset: usize,
    name_id: u16,
    coordinates: []const Coordinate,
) void {
    fixture.writeU16(bytes, offset + 0, 4);
    fixture.writeU16(bytes, offset + 2, @intCast(coordinates.len));
    fixture.writeU16(bytes, offset + 4, 0);
    fixture.writeU16(bytes, offset + 6, name_id);
    for (coordinates, 0..) |coordinate, index| {
        const axis = offset + 8 + index * 6;
        fixture.writeU16(bytes, axis, coordinate.axis_index);
        variation_support.writeF16Dot16(bytes, axis + 2, coordinate.value);
    }
}

pub fn writeFvarAxis(
    bytes: []u8,
    offset: usize,
    comptime tag: *const [4]u8,
) void {
    variation_support.writeAxis(
        bytes,
        offset,
        tag,
        100.0,
        400.0,
        900.0,
        256,
    );
}
