//! Paired hhea/hmtx and vhea/vmtx validation and compressed record access.

const bin = @import("../../../binary.zig");
const sfnt = @import("../../sfnt/root.zig");
const header = @import("header.zig");
const types = @import("types.zig");

pub const Error = header.Error;

pub fn validateHorizontal(
    data: []const u8,
    hhea: sfnt.Record,
    hmtx: sfnt.Record,
    glyph_count: u16,
) Error!types.Header {
    const result = try header.validate(data, hhea, .horizontal);
    try validatePayloadLength(
        hmtx,
        glyph_count,
        result.long_metric_count,
    );
    return result;
}

pub fn validateVertical(
    data: []const u8,
    glyph_count: u16,
    maybe_vhea: ?sfnt.Record,
    maybe_vmtx: ?sfnt.Record,
) Error!?types.Header {
    if (maybe_vhea == null and maybe_vmtx == null) return null;
    const vhea = maybe_vhea orelse return error.InvalidMetrics;
    const vmtx = maybe_vmtx orelse return error.InvalidMetrics;

    // vmtx uses the same compressed-record layout as hmtx: remaining glyphs
    // reuse the last full advance and store only a top side bearing.
    const result = try header.validate(data, vhea, .vertical);
    try validatePayloadLength(
        vmtx,
        glyph_count,
        result.long_metric_count,
    );
    return result;
}

pub fn horizontal(
    data: []const u8,
    hmtx: sfnt.Record,
    metric_count: u16,
    glyph_id: u16,
) Error!types.Horizontal {
    // Direct module callers may not have retained the preceding pair proof.
    // Reject zero before the compressed branch subtracts one from the count.
    if (metric_count == 0) return error.InvalidMetrics;
    if (glyph_id < metric_count) {
        const offset = hmtx.offset + @as(usize, glyph_id) * 4;
        return .{
            .advance_width = try bin.readU16At(data, offset),
            .left_side_bearing = try bin.readI16At(data, offset + 2),
        };
    }
    const last_offset = hmtx.offset + (@as(usize, metric_count) - 1) * 4;
    const bearing_offset =
        hmtx.offset +
        @as(usize, metric_count) * 4 +
        (@as(usize, glyph_id) - metric_count) * 2;
    return .{
        .advance_width = try bin.readU16At(data, last_offset),
        .left_side_bearing = try bin.readI16At(data, bearing_offset),
    };
}

pub fn vertical(
    data: []const u8,
    vmtx: sfnt.Record,
    metric_count: u16,
    glyph_id: u16,
) Error!types.Vertical {
    if (metric_count == 0) return error.InvalidMetrics;
    if (glyph_id < metric_count) {
        const offset = vmtx.offset + @as(usize, glyph_id) * 4;
        return .{
            .advance_height = try bin.readU16At(data, offset),
            .top_side_bearing = try bin.readI16At(data, offset + 2),
        };
    }
    const last_offset = vmtx.offset + (@as(usize, metric_count) - 1) * 4;
    const bearing_offset =
        vmtx.offset +
        @as(usize, metric_count) * 4 +
        (@as(usize, glyph_id) - metric_count) * 2;
    return .{
        .advance_height = try bin.readU16At(data, last_offset),
        .top_side_bearing = try bin.readI16At(data, bearing_offset),
    };
}

pub fn requiredLength(
    glyph_count: u16,
    metric_count: u16,
) Error!usize {
    if (metric_count == 0 or metric_count > glyph_count) {
        return error.InvalidMetrics;
    }
    return @as(usize, metric_count) * 4 +
        @as(usize, glyph_count - metric_count) * 2;
}

fn validatePayloadLength(
    table: sfnt.Record,
    glyph_count: u16,
    metric_count: u16,
) Error!void {
    const required = try requiredLength(glyph_count, metric_count);
    if (table.length < required) return error.InvalidMetrics;
}
