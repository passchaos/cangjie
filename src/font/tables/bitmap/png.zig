//! PNG datastream validation for OpenType embedded bitmap payloads.

const std = @import("std");

const bin = @import("../../../binary.zig");
const types = @import("types.zig");

pub const Dimensions = struct {
    width: u32,
    height: u32,
};

pub fn isPayload(data: []const u8) bool {
    return data.len >= signature.len and
        std.mem.eql(u8, data[0..signature.len], &signature);
}

pub fn validate(data: []const u8) types.Error!Dimensions {
    if (data.len < signature.len + 12) return error.BadSfnt;
    if (!std.mem.eql(u8, data[0..signature.len], &signature)) {
        return error.BadSfnt;
    }

    // OpenType bitmap tables embed a full PNG datastream. Validate enough of
    // the container grammar to reject signature-like arbitrary bytes and to
    // catch truncated or checksum-corrupt images before exposing dimensions.
    var offset: usize = signature.len;
    var saw_ihdr = false;
    var saw_idat = false;
    var dimensions = Dimensions{ .width = 0, .height = 0 };
    while (true) {
        if (data.len - offset < 12) return error.BadSfnt;
        const chunk_start = offset;
        const data_len = try bin.readU32At(data, offset);
        offset += 4;
        const chunk_type = try bin.readTagAt(data, offset);
        offset += 4;
        if (data_len > data.len - offset - 4) return error.BadSfnt;
        const chunk_data = data[offset .. offset + data_len];
        offset += data_len;
        const declared_crc = try bin.readU32At(data, offset);
        offset += 4;
        const computed_crc =
            std.hash.Crc32.hash(data[chunk_start + 4 .. offset - 4]);
        if (computed_crc != declared_crc) return error.BadSfnt;

        if (bin.tagEq(chunk_type, "IHDR")) {
            if (saw_ihdr or data_len != 13) return error.BadSfnt;
            dimensions = .{
                .width = try bin.readU32At(chunk_data, 0),
                .height = try bin.readU32At(chunk_data, 4),
            };
            if (dimensions.width == 0 or dimensions.height == 0) {
                return error.BadSfnt;
            }
            saw_ihdr = true;
        } else {
            if (!saw_ihdr) return error.BadSfnt;
            if (bin.tagEq(chunk_type, "IDAT")) saw_idat = true;
            if (bin.tagEq(chunk_type, "IEND")) {
                if (data_len != 0 or !saw_idat or offset != data.len) {
                    return error.BadSfnt;
                }
                return dimensions;
            }
        }
    }
}

pub fn glyph(
    data: []const u8,
    source: types.StrikeSource,
    ppem: u16,
    ppi: u16,
    origin_offset_x: i16,
    origin_offset_y: i16,
) types.Error!types.GlyphPng {
    const dimensions = try validate(data);
    return .{
        .source = source,
        .ppem = ppem,
        .ppi = ppi,
        .origin_offset_x = origin_offset_x,
        .origin_offset_y = origin_offset_y,
        .width = dimensions.width,
        .height = dimensions.height,
        .data = data,
    };
}

const signature = [_]u8{
    0x89,
    'P',
    'N',
    'G',
    0x0d,
    0x0a,
    0x1a,
    0x0a,
};

test "PNG bitmap payload validation checks signature chunks and CRCs" {
    const valid_png = [_]u8{
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
        0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xd0,
        0x00, 0x00, 0x04, 0x81, 0x01, 0x80, 0x2c, 0x55, 0xce, 0xb0, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    };

    const dimensions = try validate(&valid_png);
    try std.testing.expectEqual(@as(u32, 1), dimensions.width);
    try std.testing.expectEqual(@as(u32, 1), dimensions.height);

    var bad_signature = valid_png;
    bad_signature[0] = 0;
    try std.testing.expectError(error.BadSfnt, validate(&bad_signature));

    var bad_crc = valid_png;
    bad_crc[19] = 2; // Width byte changes but IHDR CRC remains the original value.
    try std.testing.expectError(error.BadSfnt, validate(&bad_crc));

    var trailing = valid_png ++ [_]u8{0};
    try std.testing.expectError(error.BadSfnt, validate(&trailing));
}
