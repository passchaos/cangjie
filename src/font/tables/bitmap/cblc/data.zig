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
        else => unreachable,
    };
    const payload = switch (location.image_format) {
        1, 2, 5, 6, 7 => image[metrics_len..],
        17, 18, 19 => payload: {
            const data_len = try bin.readU32At(image, metrics_len);
            if (data_len > image.len - metrics_len - 4) return error.BadSfnt;
            break :payload image[metrics_len + 4 .. metrics_len + 4 + data_len];
        },
        else => unreachable,
    };
    const is_png = png.isPayload(payload);
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
