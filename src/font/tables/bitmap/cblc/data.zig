//! CBDT/EBDT image payload validation and materialization.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const glyph = @import("../../../../glyph.zig");
const png = @import("../png.zig");
const types = @import("../types.zig");
const cblc_types = @import("types.zig");

const GlyphLocation = cblc_types.GlyphLocation;
const Strike = cblc_types.Strike;

pub fn validate(
    data: []const u8,
    data_table: types.Table,
    location: GlyphLocation,
    bit_depth: u8,
    glyph_count: u16,
) types.Error!void {
    if (location.offset > data_table.length or
        location.length > data_table.length - location.offset)
    {
        return error.BadSfnt;
    }
    if (location.image_format == 19 and location.shared_metrics == null) {
        return error.BadSfnt;
    }

    // Every non-empty location must be structurally safe even when Cangjie
    // does not render that bitmap format. This prevents an unused strike from
    // hiding an out-of-bounds payload.
    const start = data_table.offset + location.offset;
    const image = data[start .. start + location.length];
    switch (location.image_format) {
        1 => return try validateBitmapPayload(image, 5, bit_depth, true, null),
        2 => return try validateBitmapPayload(image, 5, bit_depth, false, null),
        5 => return try validateBitmapPayload(image, 0, bit_depth, false, location.shared_metrics),
        6 => return try validateBitmapPayload(image, 8, bit_depth, true, null),
        7 => return try validateBitmapPayload(image, 8, bit_depth, false, null),
        8 => return try validateCompoundPayload(image, 5, glyph_count),
        9 => return try validateCompoundPayload(image, 8, glyph_count),
        17 => return try validateEmbeddedDataPayload(image, 5),
        18 => return try validateEmbeddedDataPayload(image, 8),
        19 => return try validateEmbeddedDataPayload(image, 0),
        else => return,
    }
}

pub fn glyphInfo(
    data: []const u8,
    data_table: types.Table,
    selected_strike: Strike,
    location: GlyphLocation,
    glyph_id: glyph.GlyphId,
    source: types.StrikeSource,
) types.Error!?types.GlyphInfo {
    if (location.offset > data_table.length or
        location.length > data_table.length - location.offset)
    {
        return error.BadSfnt;
    }
    const start = data_table.offset + location.offset;
    const image = data[start .. start + location.length];
    const metrics_len: usize = switch (location.image_format) {
        1, 2, 17 => 5,
        5 => 0,
        6, 7, 18 => 8,
        19 => 0,
        8 => 5,
        9 => 8,
        else => return null,
    };
    const needs_embedded_length = switch (location.image_format) {
        17, 18, 19 => true,
        else => false,
    };
    if (image.len <
        metrics_len + if (needs_embedded_length) @as(usize, 4) else 0)
    {
        return error.BadSfnt;
    }
    const metrics = switch (location.image_format) {
        1, 2, 17 => types.readSmallMetrics(image, 0) catch unreachable,
        5 => location.shared_metrics orelse return error.BadSfnt,
        6, 7, 18 => types.readBigMetrics(image, 0) catch unreachable,
        19 => location.shared_metrics orelse return error.BadSfnt,
        8 => types.readSmallMetrics(image, 0) catch unreachable,
        9 => types.readBigMetrics(image, 0) catch unreachable,
        else => unreachable,
    };
    const payload = switch (location.image_format) {
        1, 2, 5, 6, 7 => image[metrics_len..],
        8, 9 => image[metrics_len..],
        17, 18, 19 => payload: {
            const data_len = try bin.readU32At(image, metrics_len);
            if (data_len > image.len - metrics_len - 4) return error.BadSfnt;
            break :payload image[metrics_len + 4 .. metrics_len + 4 + data_len];
        },
        else => unreachable,
    };
    // Only formats 17/18/19 carry PNG. Sniffing a raw 32-bpp payload would
    // misclassify a perfectly valid BGRA image whose first pixels happen to
    // equal the PNG signature.
    const is_png = needs_embedded_length;
    const dimensions = if (is_png)
        try png.validate(payload)
    else
        png.Dimensions{ .width = metrics.width, .height = metrics.height };
    return .{
        .source = source,
        .glyph_id = glyph_id,
        .ppem = selected_strike.ppem,
        .ppi = selected_strike.ppi,
        .origin_offset_x = metrics.bearing_x,
        .origin_offset_y = metrics.bearing_y,
        .width = dimensions.width,
        .height = dimensions.height,
        .image_format = location.image_format,
        .bit_depth = selected_strike.bit_depth,
        .row_byte_aligned = location.image_format == 1 or
            location.image_format == 6,
        .advance = metrics.advance,
        .data_offset = @intFromPtr(payload.ptr) - @intFromPtr(data.ptr),
        .data_length = payload.len,
        .is_png = is_png,
    };
}

pub fn glyphPng(
    data: []const u8,
    data_table: types.Table,
    selected_strike: Strike,
    location: GlyphLocation,
    source: types.StrikeSource,
) types.Error!?types.GlyphPng {
    if (location.offset > data_table.length or
        location.length > data_table.length - location.offset)
    {
        return error.BadSfnt;
    }
    switch (location.image_format) {
        17, 18, 19 => {},
        // This API is deliberately PNG-only; other valid CBDT image formats
        // are represented by GlyphInfo but are not returned here.
        else => return null,
    }
    const start = data_table.offset + location.offset;
    const image = data[start .. start + location.length];
    const metrics_len: usize = switch (location.image_format) {
        17 => 5,
        18 => 8,
        19 => 0,
        else => unreachable,
    };
    if (image.len < metrics_len + 4) return error.BadSfnt;
    const metrics = switch (location.image_format) {
        17 => types.readSmallMetrics(image, 0) catch unreachable,
        18 => types.readBigMetrics(image, 0) catch unreachable,
        19 => location.shared_metrics orelse return error.BadSfnt,
        else => unreachable,
    };
    const data_len = try bin.readU32At(image, metrics_len);
    if (data_len > image.len - metrics_len - 4) return error.BadSfnt;
    const payload = image[metrics_len + 4 .. metrics_len + 4 + data_len];
    return try png.glyph(
        payload,
        source,
        selected_strike.ppem,
        selected_strike.ppi,
        metrics.bearing_x,
        metrics.bearing_y,
    );
}

/// Return uncompressed premultiplied BGRA pixels from a 32-bpp strike.
///
/// This follows Skrifa's `BitmapData::Bgra` boundary: 32-bit content is
/// surfaced only for byte-aligned image formats 1 and 6. `read-fonts` reports
/// formats 2/5/7 as bit-aligned and Skrifa deliberately declines them even
/// though 32 happens to divide evenly into bytes.
pub fn glyphBgra(
    data: []const u8,
    data_table: types.Table,
    selected_strike: Strike,
    location: GlyphLocation,
    source: types.StrikeSource,
) types.Error!?types.GlyphBgra {
    if (selected_strike.bit_depth != 32) return null;
    const metrics_len: usize = switch (location.image_format) {
        1 => 5,
        6 => 8,
        else => return null,
    };
    if (location.offset > data_table.length or
        location.length > data_table.length - location.offset)
    {
        return error.BadSfnt;
    }
    const image_start = data_table.offset + location.offset;
    const image = data[image_start .. image_start + location.length];
    if (image.len < metrics_len) return error.BadSfnt;
    const metrics = switch (location.image_format) {
        1 => try types.readSmallMetrics(image, 0),
        6 => try types.readBigMetrics(image, 0),
        else => unreachable,
    };
    const pixel_count = std.math.mul(
        usize,
        metrics.width,
        metrics.height,
    ) catch return error.BadSfnt;
    const byte_count = std.math.mul(usize, pixel_count, 4) catch
        return error.BadSfnt;
    if (byte_count > image.len - metrics_len) return error.BadSfnt;
    return .{
        .source = source,
        .ppem = selected_strike.ppem,
        .ppi = selected_strike.ppi,
        .origin_offset_x = metrics.bearing_x,
        .origin_offset_y = metrics.bearing_y,
        .width = metrics.width,
        .height = metrics.height,
        .data = image[metrics_len .. metrics_len + byte_count],
    };
}

pub fn glyphData(
    data: []const u8,
    data_table: types.Table,
    selected_strike: Strike,
    location: GlyphLocation,
    source: types.StrikeSource,
) types.Error!?types.GlyphData {
    if (try glyphPng(
        data,
        data_table,
        selected_strike,
        location,
        source,
    )) |png_glyph| return .{ .png = png_glyph };
    if (try glyphBgra(
        data,
        data_table,
        selected_strike,
        location,
        source,
    )) |bgra_glyph| return .{ .bgra = bgra_glyph };
    if (try glyphMask(
        data,
        data_table,
        selected_strike,
        location,
        source,
    )) |mask_glyph| return .{ .mask = mask_glyph };
    return null;
}

pub const Compound = struct {
    metrics: types.Metrics,
    components: []const u8,

    pub fn count(self: Compound) usize {
        return self.components.len / 4;
    }

    pub fn component(self: Compound, index: usize) types.Error!types.CompoundComponent {
        if (index >= self.count()) return error.BadSfnt;
        const offset = index * 4;
        return .{
            .glyph_id = try bin.readU16At(self.components, offset),
            .x_offset = @bitCast(self.components[offset + 2]),
            .y_offset = @bitCast(self.components[offset + 3]),
        };
    }
};

pub fn compound(
    data: []const u8,
    data_table: types.Table,
    location: GlyphLocation,
) types.Error!?Compound {
    const metrics_len: usize = switch (location.image_format) {
        8 => 5,
        9 => 8,
        else => return null,
    };
    if (location.offset > data_table.length or
        location.length > data_table.length - location.offset)
    {
        return error.BadSfnt;
    }
    const image_start = data_table.offset + location.offset;
    const image = data[image_start .. image_start + location.length];
    const components_start = metrics_len + if (location.image_format == 8) @as(usize, 3) else 2;
    if (image.len < components_start) return error.BadSfnt;
    const metrics = if (location.image_format == 8)
        try types.readSmallMetrics(image, 0)
    else
        try types.readBigMetrics(image, 0);
    const count_offset = metrics_len + if (location.image_format == 8) @as(usize, 1) else 0;
    const component_count = try bin.readU16At(image, count_offset);
    const component_bytes = std.math.mul(usize, component_count, 4) catch
        return error.BadSfnt;
    if (component_bytes > image.len - components_start) return error.BadSfnt;
    return .{
        .metrics = metrics,
        .components = image[components_start .. components_start + component_bytes],
    };
}

/// Return one raw monochrome embedded bitmap payload.
///
/// The selected strike owns bit depth, while image format determines whether
/// rows are byte-aligned. Metrics are excluded from the borrowed `data` slice.
pub fn glyphMask(
    data: []const u8,
    data_table: types.Table,
    selected_strike: Strike,
    location: GlyphLocation,
    source: types.StrikeSource,
) types.Error!?types.GlyphMask {
    if (selected_strike.bit_depth != 1 and
        selected_strike.bit_depth != 2 and
        selected_strike.bit_depth != 4 and
        selected_strike.bit_depth != 8)
    {
        return null;
    }
    const metrics_len: usize = switch (location.image_format) {
        1, 2 => 5,
        5 => 0,
        6, 7 => 8,
        else => return null,
    };
    if (location.offset > data_table.length or
        location.length > data_table.length - location.offset)
    {
        return error.BadSfnt;
    }
    const image_start = data_table.offset + location.offset;
    const image = data[image_start .. image_start + location.length];
    if (image.len < metrics_len) return error.BadSfnt;
    const metrics = switch (location.image_format) {
        1, 2 => try types.readSmallMetrics(image, 0),
        5 => location.shared_metrics orelse return error.BadSfnt,
        6, 7 => try types.readBigMetrics(image, 0),
        else => unreachable,
    };
    const payload = image[metrics_len..];
    return .{
        .source = source,
        .ppem = selected_strike.ppem,
        .ppi = selected_strike.ppi,
        .origin_offset_x = metrics.bearing_x,
        .origin_offset_y = metrics.bearing_y,
        .width = metrics.width,
        .height = metrics.height,
        .bit_depth = selected_strike.bit_depth,
        .row_byte_aligned = location.image_format == 1 or
            location.image_format == 6,
        .data = payload,
    };
}

fn validateBitmapPayload(
    data: []const u8,
    metrics_len: usize,
    bit_depth: u8,
    byte_aligned_rows: bool,
    shared_metrics: ?types.Metrics,
) types.Error!void {
    if (data.len < metrics_len) return error.BadSfnt;
    if (bit_depth != 1 and bit_depth != 2 and bit_depth != 4 and
        bit_depth != 8 and bit_depth != 32)
    {
        return error.BadSfnt;
    }

    const metrics = switch (metrics_len) {
        0 => shared_metrics orelse return error.BadSfnt,
        5 => try types.readSmallMetrics(data, 0),
        8 => try types.readBigMetrics(data, 0),
        else => unreachable,
    };
    const row_bits = @as(usize, metrics.width) * bit_depth;
    const bitmap_len = if (byte_aligned_rows)
        @as(usize, metrics.height) * ((row_bits + 7) / 8)
    else
        (@as(usize, metrics.height) * row_bits + 7) / 8;
    if (bitmap_len > data.len - metrics_len) return error.BadSfnt;
}

fn validateCompoundPayload(
    data: []const u8,
    metrics_len: usize,
    glyph_count: u16,
) types.Error!void {
    const components_start = metrics_len + 3;
    if (data.len < components_start) return error.BadSfnt;
    switch (metrics_len) {
        5 => _ = try types.readSmallMetrics(data, 0),
        8 => _ = try types.readBigMetrics(data, 0),
        else => unreachable,
    }

    // Compound bitmaps recursively reference glyph IDs through a compact
    // component array. Prove the complete array at parse time.
    const component_count = try bin.readU16At(data, metrics_len + 1);
    if (@as(usize, component_count) > (data.len - components_start) / 4) {
        return error.BadSfnt;
    }
    for (0..component_count) |component_index| {
        const component = components_start + component_index * 4;
        const component_glyph = try bin.readU16At(data, component);
        if (component_glyph >= glyph_count) return error.BadSfnt;
    }
}

fn validateEmbeddedDataPayload(
    data: []const u8,
    metrics_len: usize,
) types.Error!void {
    if (data.len < metrics_len + 4) return error.BadSfnt;
    const data_len = try bin.readU32At(data, metrics_len);
    if (data_len > data.len - metrics_len - 4) return error.BadSfnt;
    _ = try png.validate(data[metrics_len + 4 .. metrics_len + 4 + data_len]);
}

test "32-bpp byte-aligned formats expose premultiplied BGRA bytes" {
    const pixels = [_]u8{ 7, 13, 64, 128, 10, 20, 30, 255 };
    const strike = Strike{
        .ppem = 16,
        .ppi = 0,
        .bit_depth = 32,
        .offset = 0,
        .index_tables_size = 0,
        .table_count = 0,
        .start_glyph = 1,
        .end_glyph = 1,
    };
    const shared = types.Metrics{
        .height = 1,
        .width = 2,
        .bearing_x = 2,
        .bearing_y = 13,
        .advance = 12,
    };
    const Case = struct { format: u16, metrics_len: usize };
    const cases = [_]Case{
        .{ .format = 1, .metrics_len = 5 },
        .{ .format = 6, .metrics_len = 8 },
    };
    for (cases) |case| {
        var data: [16]u8 = .{0} ** 16;
        if (case.metrics_len == 5) {
            data[0] = shared.height;
            data[1] = shared.width;
            data[2] = @bitCast(shared.bearing_x);
            data[3] = @bitCast(shared.bearing_y);
            data[4] = shared.advance;
        } else if (case.metrics_len == 8) {
            data[0] = shared.height;
            data[1] = shared.width;
            data[2] = @bitCast(shared.bearing_x);
            data[3] = @bitCast(shared.bearing_y);
            data[4] = shared.advance;
        }
        @memcpy(data[case.metrics_len..][0..pixels.len], &pixels);
        const length = case.metrics_len + pixels.len;
        const bitmap = (try glyphBgra(
            &data,
            .{ .offset = 0, .length = length },
            strike,
            .{
                .image_format = case.format,
                .offset = 0,
                .length = length,
                .shared_metrics = null,
            },
            .cblc_cbdt,
        )) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualSlices(u8, &pixels, bitmap.data);
    }
}

test "32-bpp bit-aligned formats match Skrifa's unsupported boundary" {
    const strike = Strike{
        .ppem = 16,
        .ppi = 0,
        .bit_depth = 32,
        .offset = 0,
        .index_tables_size = 0,
        .table_count = 0,
        .start_glyph = 1,
        .end_glyph = 1,
    };
    var data: [16]u8 = .{0} ** 16;
    for ([_]u16{ 2, 5, 7 }) |format| {
        try std.testing.expect((try glyphBgra(
            &data,
            .{ .offset = 0, .length = data.len },
            strike,
            .{
                .image_format = format,
                .offset = 0,
                .length = data.len,
            },
            .cblc_cbdt,
        )) == null);
    }
}

test "32-bpp BGRA extraction rejects truncated data" {
    var data = [_]u8{ 1, 2, 0, 1, 3, 7, 13, 64 };
    try std.testing.expectError(
        error.BadSfnt,
        validate(
            &data,
            .{ .offset = 0, .length = data.len },
            .{ .image_format = 1, .offset = 0, .length = data.len },
            32,
            2,
        ),
    );
}

test "CBDT format 19 requires shared index-subtable metrics" {
    const metrics = types.Metrics{
        .height = 7,
        .width = 9,
        .bearing_x = -2,
        .bearing_y = 6,
        .advance = 10,
    };
    const valid = GlyphLocation{
        .image_format = 19,
        .offset = 0,
        .length = 4,
        .shared_metrics = metrics,
    };
    var data: [4]u8 = .{0} ** 4;
    const cbdt = types.Table{ .offset = 0, .length = data.len };

    // The empty PNG length is structurally readable; this focused test is for
    // the location-level metrics contract, before full PNG validation.
    var missing = valid;
    missing.shared_metrics = null;
    try std.testing.expectError(error.BadSfnt, validate(&data, cbdt, missing, 32, 1));
}
