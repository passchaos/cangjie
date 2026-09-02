//! Compact ExtensionPos mark-attachment fixtures shared by runtime tests.

const std = @import("std");
pub const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub const MarkKind = enum(u16) {
    base = 4,
    mark = 6,
};

pub const Fixture = struct {
    lookup_offset: usize,
    payload_offset: usize,
    first_coverage_glyph: usize,
    second_coverage_glyph: usize,
};

/// Write a complete one-lookup GPOS table containing one homogeneous
/// ExtensionPos wrapper around a MarkBasePos or MarkMarkPos payload.
pub fn writeSingleExtensionTable(
    bytes: []u8,
    kind: MarkKind,
) Fixture {
    @memset(bytes, 0);
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, @intCast(bytes.len - 4)); // Empty ScriptList.
    writeU16(bytes, 6, @intCast(bytes.len - 2)); // Empty FeatureList.
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 1);
    writeU16(bytes, 12, 4);

    const lookup = 14;
    writeU16(bytes, lookup, 9);
    writeU16(bytes, lookup + 2, 0);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);

    const wrapper = lookup + 8;
    writeU16(bytes, wrapper, 1);
    writeU16(bytes, wrapper + 2, @intFromEnum(kind));
    writeU32(bytes, wrapper + 4, 8);
    const payload = wrapper + 8;
    writeMarkPayload(bytes, payload, kind, 22, 20, 10, 15, 100, 120);
    writeU16(bytes, bytes.len - 4, 0);
    writeU16(bytes, bytes.len - 2, 0);
    return .{
        .lookup_offset = lookup,
        .payload_offset = payload,
        .first_coverage_glyph = payload + 16,
        .second_coverage_glyph = payload + 22,
    };
}

pub fn writeMarkPayload(
    bytes: []u8,
    offset: usize,
    kind: MarkKind,
    first_glyph: GlyphId,
    second_glyph: GlyphId,
    first_x: i16,
    first_y: i16,
    second_x: i16,
    second_y: i16,
) void {
    _ = kind; // MarkBasePos and MarkMarkPos share this format-1 fixture shape.
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 12);
    writeU16(bytes, offset + 4, 18);
    writeU16(bytes, offset + 6, 1);
    writeU16(bytes, offset + 8, 24);
    writeU16(bytes, offset + 10, 36);
    writeCoverage1(bytes, offset + 12, first_glyph);
    writeCoverage1(bytes, offset + 18, second_glyph);

    const first_array = offset + 24;
    writeU16(bytes, first_array, 1);
    writeU16(bytes, first_array + 2, 0);
    writeU16(bytes, first_array + 4, 6);
    writeAnchor1(bytes, first_array + 6, first_x, first_y);

    const second_array = offset + 36;
    writeU16(bytes, second_array, 1);
    writeU16(bytes, second_array + 2, 4);
    writeAnchor1(bytes, second_array + 4, second_x, second_y);
}

pub fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

pub fn writeAnchor1(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16(bytes, offset, 1);
    writeI16(bytes, offset + 2, x);
    writeI16(bytes, offset + 4, y);
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
