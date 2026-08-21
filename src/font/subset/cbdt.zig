//! Bounded preserve-GID serialization for CBDT PNG strikes.
//!
//! Image format 19 stores shared metrics in CBLC. The subset normalizes those
//! records to self-contained format 18 images, allowing every retained strike
//! to keep one dense, constant-time format-1 index even when selected GIDs are
//! sparse. Empty offsets ensure removed glyphs are never advertised.

const std = @import("std");

const bitmap = @import("../tables/bitmap/root.zig");
const glyph_mod = @import("../../glyph.zig");

const GlyphId = glyph_mod.GlyphId;

pub const Pair = struct {
    cbdt: []u8,
    cblc: []u8,
};

const Strike = struct {
    source: bitmap.cblc.Strike,
    images: []?[]const u8,
    image_format: u16,

    fn deinit(self: *Strike, allocator: std.mem.Allocator) void {
        for (self.images) |image| if (image) |bytes| allocator.free(bytes);
        allocator.free(self.images);
        self.* = undefined;
    }
};

pub fn buildAlloc(
    allocator: std.mem.Allocator,
    cblc_data: []const u8,
    cbdt_data: []const u8,
    retained: []const bool,
) !Pair {
    const location_table = bitmap.Table{ .offset = 0, .length = cblc_data.len };
    const strike_count = try bitmap.cblc.strikeCount(cblc_data, location_table);
    const strikes = try allocator.alloc(Strike, strike_count);
    var built: usize = 0;
    defer {
        for (strikes[0..built]) |*strike| strike.deinit(allocator);
        allocator.free(strikes);
    }

    for (strikes, 0..) |*output, strike_index| {
        const strike = try bitmap.cblc.strike(
            cblc_data,
            location_table,
            @intCast(retained.len),
            strike_index,
        );
        const images = try allocator.alloc(?[]const u8, retained.len);
        @memset(images, null);
        output.* = .{ .source = strike, .images = images, .image_format = 0 };
        built += 1;

        for (retained, 0..) |keep, glyph_index| {
            if (!keep) continue;
            const location = (try bitmap.cblc.glyphLocationInStrike(
                cblc_data,
                strike,
                @intCast(glyph_index),
            )) orelse continue;
            if (location.image_format != 17 and
                location.image_format != 18 and
                location.image_format != 19)
            {
                return error.UnsupportedFontSubset;
            }
            if (location.offset > cbdt_data.len or
                location.length > cbdt_data.len - location.offset)
            {
                return error.InvalidFontSubset;
            }

            // Format 18 is the self-contained BigGlyphMetrics equivalent of
            // format 19. This normalization preserves every metric and avoids
            // an index-format-2/5 sparsity trade-off in the generated font.
            const output_format: u16 = if (location.image_format == 19) 18 else location.image_format;
            if (output.image_format != 0 and output.image_format != output_format) {
                return error.UnsupportedFontSubset;
            }
            output.image_format = output_format;
            const prefix_len: usize = if (location.image_format == 19) 8 else 0;
            const image_len = try addChecked(prefix_len, location.length);
            const image = try allocator.alloc(u8, image_len);
            errdefer allocator.free(image);
            if (location.image_format == 19) {
                try writeBigMetrics(
                    image,
                    0,
                    location.shared_metrics orelse return error.InvalidFontSubset,
                );
            }
            @memcpy(
                image[prefix_len..],
                cbdt_data[location.offset .. location.offset + location.length],
            );
            output.images[glyph_index] = image;
        }
    }

    return serializeAlloc(allocator, strikes);
}

fn serializeAlloc(allocator: std.mem.Allocator, strikes: []const Strike) !Pair {
    var cbdt_len: usize = 4;
    var output_strike_count: usize = 0;
    var cblc_payload_len: usize = 0;
    for (strikes) |strike| {
        const bounds = imageBounds(strike.images) orelse continue;
        output_strike_count = try addChecked(output_strike_count, 1);
        for (strike.images[bounds.first .. @as(usize, bounds.last) + 1]) |image| {
            if (image) |bytes| cbdt_len = try addChecked(cbdt_len, bytes.len);
        }
        const range_len = @as(usize, bounds.last - bounds.first) + 1;
        const offsets_len = std.math.mul(usize, range_len + 1, 4) catch
            return error.FontSubsetOutputLimitExceeded;
        cblc_payload_len = try addChecked(
            cblc_payload_len,
            try addChecked(16, offsets_len),
        );
    }
    if (cbdt_len > std.math.maxInt(u32))
        return error.FontSubsetOutputLimitExceeded;

    const directory_len = std.math.mul(usize, output_strike_count, 48) catch
        return error.FontSubsetOutputLimitExceeded;
    const header_len = try addChecked(8, directory_len);
    const cblc_len = try addChecked(header_len, cblc_payload_len);
    if (cblc_len > std.math.maxInt(u32))
        return error.FontSubsetOutputLimitExceeded;

    const cbdt = try allocator.alloc(u8, cbdt_len);
    errdefer allocator.free(cbdt);
    @memset(cbdt, 0);
    writeU16(cbdt, 0, 3);
    const cblc = try allocator.alloc(u8, cblc_len);
    errdefer allocator.free(cblc);
    @memset(cblc, 0);
    writeU16(cblc, 0, 3);
    writeU32(cblc, 4, @intCast(output_strike_count));

    var cbdt_cursor: usize = 4;
    var cblc_cursor = header_len;
    var output_strike_index: usize = 0;
    for (strikes) |strike| {
        const bounds = imageBounds(strike.images) orelse continue;
        const range_len = @as(usize, bounds.last - bounds.first) + 1;
        const strike_index_len = 16 + (range_len + 1) * 4;
        const size = 8 + output_strike_index * 48;
        writeU32(cblc, size, @intCast(cblc_cursor));
        writeU32(cblc, size + 4, @intCast(strike_index_len));
        writeU32(cblc, size + 8, 1);
        // `bitmap.cblc.Strike` intentionally exposes only validated scalar
        // fields. Empty line-metric records remain conforming and avoid
        // retaining offsets into the source table.
        writeU16(cblc, size + 40, bounds.first);
        writeU16(cblc, size + 42, bounds.last);
        cblc[size + 44] = @intCast(strike.source.ppem_x);
        cblc[size + 45] = @intCast(strike.source.ppem);
        cblc[size + 46] = strike.source.bit_depth;
        cblc[size + 47] = strike.source.flags;

        const record = cblc_cursor;
        writeU16(cblc, record, bounds.first);
        writeU16(cblc, record + 2, bounds.last);
        writeU32(cblc, record + 4, 8);
        const subtable = record + 8;
        writeU16(cblc, subtable, 1);
        writeU16(cblc, subtable + 2, strike.image_format);
        writeU32(cblc, subtable + 4, @intCast(cbdt_cursor));
        var image_offset: usize = 0;
        for (strike.images[bounds.first .. @as(usize, bounds.last) + 1], 0..) |image, local_index| {
            writeU32(cblc, subtable + 8 + local_index * 4, @intCast(image_offset));
            if (image) |bytes| {
                @memcpy(cbdt[cbdt_cursor..][0..bytes.len], bytes);
                cbdt_cursor += bytes.len;
                image_offset += bytes.len;
            }
        }
        writeU32(cblc, subtable + 8 + range_len * 4, @intCast(image_offset));
        cblc_cursor += strike_index_len;
        output_strike_index += 1;
    }
    if (cbdt_cursor != cbdt.len or cblc_cursor != cblc.len) {
        return error.InvalidFontSubset;
    }
    return .{ .cbdt = cbdt, .cblc = cblc };
}

const ImageBounds = struct { first: GlyphId, last: GlyphId };

fn imageBounds(images: []const ?[]const u8) ?ImageBounds {
    var first: ?GlyphId = null;
    var last: GlyphId = 0;
    for (images, 0..) |image, glyph_index| {
        if (image == null) continue;
        if (first == null) first = @intCast(glyph_index);
        last = @intCast(glyph_index);
    }
    return if (first) |value| .{ .first = value, .last = last } else null;
}

fn writeBigMetrics(bytes: []u8, offset: usize, metrics: bitmap.types.Metrics) !void {
    bytes[offset] = metrics.height;
    bytes[offset + 1] = metrics.width;
    bytes[offset + 2] = @bitCast(metrics.bearing_x);
    bytes[offset + 3] = @bitCast(metrics.bearing_y);
    bytes[offset + 4] = metrics.advance;
    bytes[offset + 5] = @bitCast(metrics.vertical_bearing_x orelse
        return error.InvalidFontSubset);
    bytes[offset + 6] = @bitCast(metrics.vertical_bearing_y orelse
        return error.InvalidFontSubset);
    bytes[offset + 7] = metrics.vertical_advance orelse
        return error.InvalidFontSubset;
}

fn addChecked(a: usize, b: usize) !usize {
    return std.math.add(usize, a, b) catch
        error.FontSubsetOutputLimitExceeded;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
