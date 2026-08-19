//! OpenType CBLC/EBLC indexes and CBDT/EBDT bitmap payloads.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const glyph = @import("../../../../glyph.zig");
const types = @import("../types.zig");
const cblc_data = @import("data.zig");
const cblc_types = @import("types.zig");
const cblc_index = @import("index.zig");

pub const Strike = cblc_types.Strike;
pub const GlyphLocation = cblc_types.GlyphLocation;

pub const glyphLocation = cblc_index.glyphLocation;
pub const imageLocation = cblc_index.imageLocation;
pub const glyphLocationFormat1Or3 = cblc_index.glyphLocationFormat1Or3;
pub const glyphLocationFormat2 = cblc_index.glyphLocationFormat2;
pub const glyphLocationFormat4 = cblc_index.glyphLocationFormat4;
pub const glyphLocationFormat5 = cblc_index.glyphLocationFormat5;
pub const checkedImageStart = cblc_index.checkedImageStart;
pub const checkedImageEnd = cblc_index.checkedImageEnd;

pub fn strikeCount(
    data: []const u8,
    location_table: types.Table,
) types.Error!usize {
    if (location_table.length < 8) return error.BadSfnt;
    const major = try bin.readU16At(data, location_table.offset);
    const minor = try bin.readU16At(data, location_table.offset + 2);
    if ((major != 2 and major != 3) or minor != 0) return error.BadSfnt;
    const count = try bin.readU32At(data, location_table.offset + 4);
    if (@as(usize, count) * 48 > location_table.length - 8) {
        return error.BadSfnt;
    }
    return @intCast(count);
}

pub fn strike(
    data: []const u8,
    location_table: types.Table,
    glyph_count: u16,
    strike_index: usize,
) types.Error!Strike {
    const strike_count = try strikeCount(data, location_table);
    if (strike_index >= strike_count) return error.BadSfnt;
    const offset = location_table.offset + 8 + strike_index * 48;
    const index_array_offset = try bin.readU32At(data, offset);
    const index_tables_size = try bin.readU32At(data, offset + 4);
    const table_count = try bin.readU32At(data, offset + 8);
    const minimum_index_array_offset = 8 + strike_count * 48;
    // IndexSubTableArray is strike payload, not table-directory metadata.
    if (index_array_offset < minimum_index_array_offset) return error.BadSfnt;
    if (index_array_offset > location_table.length) return error.BadSfnt;
    if (index_tables_size > location_table.length - index_array_offset) {
        return error.BadSfnt;
    }
    if (@as(usize, table_count) * 8 > index_tables_size) {
        return error.BadSfnt;
    }
    const start_glyph = try bin.readU16At(data, offset + 40);
    const end_glyph = try bin.readU16At(data, offset + 42);
    const bit_depth = data[offset + 46];
    if (start_glyph > end_glyph or end_glyph >= glyph_count) {
        return error.BadSfnt;
    }
    if (bit_depth != 1 and bit_depth != 2 and bit_depth != 4 and
        bit_depth != 8 and bit_depth != 32)
    {
        return error.BadSfnt;
    }
    return .{
        .ppem = data[offset + 44],
        .ppi = 0,
        .bit_depth = bit_depth,
        .offset = location_table.offset + index_array_offset,
        .index_tables_size = index_tables_size,
        .table_count = table_count,
        .start_glyph = start_glyph,
        .end_glyph = end_glyph,
    };
}

pub fn glyphInfo(
    data: []const u8,
    location_table: types.Table,
    data_table: types.Table,
    glyph_count: u16,
    glyph_id: glyph.GlyphId,
    size_px: f32,
    source: types.StrikeSource,
) types.Error!?types.GlyphInfo {
    var best: ?types.GlyphInfo = null;
    const strike_count = try strikeCount(data, location_table);
    for (0..strike_count) |strike_index| {
        const current =
            try strike(data, location_table, glyph_count, strike_index);
        const location =
            (try glyphLocation(data, current, glyph_id)) orelse continue;
        if (try cblc_data.glyphInfo(
            data,
            data_table,
            current,
            location,
            glyph_id,
            source,
        )) |info| {
            types.recordBestGlyphInfo(info, size_px, &best);
        }
    }
    return best;
}

pub fn glyphPng(
    data: []const u8,
    location_table: types.Table,
    data_table: types.Table,
    glyph_count: u16,
    glyph_id: glyph.GlyphId,
    size_px: f32,
    source: types.StrikeSource,
) types.Error!?types.GlyphPng {
    const strike_count = try strikeCount(data, location_table);
    var best: ?types.GlyphPng = null;
    for (0..strike_count) |strike_index| {
        const current =
            try strike(data, location_table, glyph_count, strike_index);
        if (glyph_id < current.start_glyph or glyph_id > current.end_glyph) {
            continue;
        }
        const location =
            (try glyphLocation(data, current, glyph_id)) orelse continue;
        const candidate = (try cblc_data.glyphPng(
            data,
            data_table,
            current,
            location,
            source,
        )) orelse continue;
        if (best == null or
            types.ppemIsPreferred(candidate.ppem, best.?.ppem, size_px))
        {
            best = candidate;
        }
    }
    return best;
}

pub fn glyphMask(
    data: []const u8,
    location_table: types.Table,
    data_table: types.Table,
    glyph_count: u16,
    glyph_id: glyph.GlyphId,
    size_px: f32,
    source: types.StrikeSource,
) types.Error!?types.GlyphMask {
    const strike_count = try strikeCount(data, location_table);
    var best: ?types.GlyphMask = null;
    for (0..strike_count) |strike_index| {
        const current =
            try strike(data, location_table, glyph_count, strike_index);
        const location =
            (try glyphLocation(data, current, glyph_id)) orelse continue;
        const candidate = (try cblc_data.glyphMask(
            data,
            data_table,
            current,
            location,
            source,
        )) orelse continue;
        if (best == null or
            types.ppemIsPreferred(candidate.ppem, best.?.ppem, size_px))
        {
            best = candidate;
        }
    }
    return best;
}

pub fn validate(
    data: []const u8,
    location_table: types.Table,
    data_table: types.Table,
    glyph_count: u16,
) types.Error!void {
    const strike_count = try strikeCount(data, location_table);
    for (0..strike_count) |strike_index| {
        const current =
            try strike(data, location_table, glyph_count, strike_index);
        for (current.start_glyph..@as(usize, current.end_glyph) + 1) |index| {
            const location =
                (try glyphLocation(data, current, @intCast(index))) orelse
                continue;
            try cblc_data.validate(
                data,
                data_table,
                location,
                current.bit_depth,
                glyph_count,
            );
        }
    }
}

pub fn validateGlyphData(
    data: []const u8,
    data_table: types.Table,
    location: GlyphLocation,
    bit_depth: u8,
    glyph_count: u16,
) types.Error!void {
    return try cblc_data.validate(
        data,
        data_table,
        location,
        bit_depth,
        glyph_count,
    );
}

test "CBLC fixed-size index formats validate dense and sparse invariants" {
    const selected_strike = Strike{
        .ppem = 16,
        .ppi = 0,
        .bit_depth = 1,
        .offset = 0,
        .index_tables_size = 32,
        .table_count = 1,
        .start_glyph = 1,
        .end_glyph = 3,
    };

    var format2: [12]u8 = .{0} ** 12;
    writeU32(&format2, 0, 9); // One fixed-size image-format-17 CBDT payload.
    format2[4] = 7;
    format2[5] = 9;
    format2[6] = @bitCast(@as(i8, -2));
    format2[7] = 6;
    format2[8] = 10;
    const dense_location = (try glyphLocationFormat2(&format2, selected_strike, 0, 1, 3, 2, 17, 0)).?;
    try std.testing.expectEqual(@as(usize, 18), dense_location.offset);
    try std.testing.expectEqual(@as(usize, 9), dense_location.length);
    try std.testing.expectEqual(@as(i8, -2), dense_location.shared_metrics.?.bearing_x);
    try std.testing.expectEqual(@as(i8, 6), dense_location.shared_metrics.?.bearing_y);

    writeU32(&format2, 0, 0);
    try std.testing.expectError(error.BadSfnt, glyphLocationFormat2(&format2, selected_strike, 0, 1, 3, 0, 17, 0));

    var data: [121]u8 = .{0} ** 121;
    writeU16(&data, 0, 2); // CBLC major version.
    writeU16(&data, 2, 0); // CBLC minor version.
    writeU32(&data, 4, 1); // One bitmapSizeTable.
    writeU32(&data, 8, 56); // IndexSubTableArray immediately after the strike directory.
    writeU32(&data, 12, 38); // One array record plus one format-5 subtable.
    writeU32(&data, 16, 1); // One IndexSubTableArray record.
    writeU16(&data, 48, 1); // startGlyphIndex.
    writeU16(&data, 50, 3); // endGlyphIndex.
    data[52] = 16; // ppem.
    data[54] = 1; // bitDepth.

    writeU16(&data, 56, 1); // firstGlyphIndex.
    writeU16(&data, 58, 3); // lastGlyphIndex.
    writeU32(&data, 60, 8); // Subtable starts after the array record.
    writeU16(&data, 64, 5); // indexFormat 5: sparse fixed-size images.
    writeU16(&data, 66, 1); // imageFormat 1: byte-aligned bitmap payloads.
    writeU32(&data, 68, 0); // imageDataOffset.
    writeU32(&data, 72, 9); // imageSize.
    data[76] = 7;
    data[77] = 9;
    data[78] = @bitCast(@as(i8, -2));
    data[79] = 6;
    data[80] = 10;
    writeU32(&data, 84, 3); // Three glyph codes follow.
    writeU16(&data, 88, 1);
    writeU16(&data, 90, 3);
    writeU16(&data, 92, 2); // Out of order; must be caught before lookup succeeds.

    const cblc = types.Table{ .offset = 0, .length = 94 };
    const cbdt = types.Table{ .offset = 94, .length = 27 };
    try std.testing.expectError(error.BadSfnt, validate(&data, cblc, cbdt, 4));

    writeU16(&data, 90, 2);
    writeU16(&data, 92, 3);
    try validate(&data, cblc, cbdt, 4);
    const sparse_location = (try glyphLocation(&data, try strike(&data, cblc, 4, 0), 2)).?;
    try std.testing.expectEqual(@as(i8, -2), sparse_location.shared_metrics.?.bearing_x);
    try std.testing.expectEqual(@as(i8, 6), sparse_location.shared_metrics.?.bearing_y);

    writeU16(&data, 92, 4); // Outside the subtable's declared 1...3 range.
    try std.testing.expectError(error.BadSfnt, validate(&data, cblc, cbdt, 4));
}

test "CBLC strike glyph ranges stay within maxp glyph count" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16(&bytes, 0, 2); // major version.
    writeU16(&bytes, 2, 0); // minor version.
    writeU32(&bytes, 4, 1); // one strike.
    writeU32(&bytes, 8, 56); // indexSubTableArrayOffset at end: empty index array.
    writeU32(&bytes, 12, 0);
    writeU32(&bytes, 16, 0);
    writeU16(&bytes, 48, 0); // startGlyphIndex.
    writeU16(&bytes, 50, 2); // endGlyphIndex exceeds a two-glyph font's max glyph id.
    bytes[52] = 16;

    const cblc = types.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, strike(&bytes, cblc, 2, 0));
}

test "CBLC index arrays cannot overlap the strike directory" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16(&bytes, 0, 2); // major version.
    writeU16(&bytes, 2, 0); // minor version.
    writeU32(&bytes, 4, 1); // one bitmapSizeTable.
    writeU32(&bytes, 8, 8); // Points back into the bitmapSizeTable.
    writeU32(&bytes, 12, 48);
    writeU32(&bytes, 16, 1);
    writeU16(&bytes, 48, 1);
    writeU16(&bytes, 50, 1);
    bytes[52] = 16;

    const cblc = types.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, strike(&bytes, cblc, 2, 0));
}

test "CBDT non-PNG image formats are skipped by PNG lookup" {
    var bytes: [80]u8 = .{0} ** 80;
    writeU16(&bytes, 0, 2); // CBLC major version.
    writeU16(&bytes, 2, 0);
    writeU32(&bytes, 4, 1); // one bitmapSizeTable.

    writeU32(&bytes, 8, 56); // IndexSubTableArray follows the strike directory.
    writeU32(&bytes, 12, 20);
    writeU32(&bytes, 16, 1);
    writeU16(&bytes, 48, 1);
    writeU16(&bytes, 50, 1);
    bytes[52] = 16;
    bytes[54] = 1;

    writeU16(&bytes, 56, 1);
    writeU16(&bytes, 58, 1);
    writeU32(&bytes, 60, 8);

    writeU16(&bytes, 64, 3); // IndexSubTable format 3.
    writeU16(&bytes, 66, 1); // CBDT image format 1 is not PNG data.
    writeU32(&bytes, 68, 0);
    writeU16(&bytes, 72, 0);
    writeU16(&bytes, 74, 4);

    const cblc = types.Table{ .offset = 0, .length = 76 };
    const cbdt = types.Table{ .offset = 76, .length = 4 };
    try std.testing.expectEqual(@as(?types.GlyphPng, null), try glyphPng(&bytes, cblc, cbdt, 2, 1, 16, .cblc_cbdt));
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
