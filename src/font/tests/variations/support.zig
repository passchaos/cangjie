//! Shared binary fixtures for fvar/avar public API integration tests.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");
const table_only = @import("../fixtures/table_only.zig");

pub const Font = font_mod.Font;

pub fn fvarFont(data: []const u8) Font {
    var font = table_only.init(Font, data, 2, 2);
    font.fvar = table_only.record(
        data,
        .{ 'f', 'v', 'a', 'r' },
        0,
        data.len,
    );
    return font;
}

pub fn avarFont(data: []const u8) Font {
    var font = table_only.init(Font, data, 2, 2);
    font.avar = table_only.record(
        data,
        .{ 'a', 'v', 'a', 'r' },
        0,
        data.len,
    );
    return font;
}

pub fn fvarAvarFont(data: []const u8, fvar_length: usize) Font {
    var font = table_only.init(Font, data, 2, 2);
    font.fvar = table_only.record(
        data,
        .{ 'f', 'v', 'a', 'r' },
        0,
        fvar_length,
    );
    font.avar = table_only.record(
        data,
        .{ 'a', 'v', 'a', 'r' },
        fvar_length,
        data.len - fvar_length,
    );
    return font;
}

pub fn writeFvarHeader(bytes: []u8, axis_count: u16) void {
    sfnt_fixture.writeU32(bytes, 0, 0x00010000);
    sfnt_fixture.writeU16(bytes, 4, 16);
    sfnt_fixture.writeU16(bytes, 6, 2);
    sfnt_fixture.writeU16(bytes, 8, axis_count);
    sfnt_fixture.writeU16(bytes, 10, 20);
}

pub fn writeAxis(
    bytes: []u8,
    offset: usize,
    comptime tag: *const [4]u8,
    minimum: f32,
    default: f32,
    maximum: f32,
    name_id: u16,
) void {
    @memcpy(bytes[offset..][0..4], tag);
    writeF16Dot16(bytes, offset + 4, minimum);
    writeF16Dot16(bytes, offset + 8, default);
    writeF16Dot16(bytes, offset + 12, maximum);
    sfnt_fixture.writeU16(bytes, offset + 16, 0);
    sfnt_fixture.writeU16(bytes, offset + 18, name_id);
}

pub fn writeF16Dot16(bytes: []u8, offset: usize, value: f32) void {
    const fixed: i32 = @intFromFloat(value * 65536.0);
    std.mem.writeInt(i32, bytes[offset..][0..4], fixed, .big);
}

pub fn writeF2Dot14(bytes: []u8, offset: usize, value: f32) void {
    const fixed: i16 = @intFromFloat(value * 16384.0);
    std.mem.writeInt(i16, bytes[offset..][0..2], fixed, .big);
}
