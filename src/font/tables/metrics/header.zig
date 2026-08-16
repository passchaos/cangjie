//! Shared hhea/vhea header decoding and invariant validation.

const bin = @import("../../../binary.zig");
const sfnt = @import("../../sfnt/root.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error || error{ EndOfStream, InvalidMetrics };

pub const Kind = enum {
    horizontal,
    vertical,
};

pub fn read(
    data: []const u8,
    table: sfnt.Record,
) Error!types.Header {
    try sfnt.requireLength(table, 36);
    return .{
        .version = try bin.readU32At(data, table.offset),
        .ascender = try bin.readI16At(data, table.offset + 4),
        .descender = try bin.readI16At(data, table.offset + 6),
        .line_gap = try bin.readI16At(data, table.offset + 8),
        .advance_max = try bin.readU16At(data, table.offset + 10),
        .min_side_bearing = try bin.readI16At(data, table.offset + 12),
        .min_opposite_side_bearing = try bin.readI16At(data, table.offset + 14),
        .max_extent = try bin.readI16At(data, table.offset + 16),
        .caret_slope_rise = try bin.readI16At(data, table.offset + 18),
        .caret_slope_run = try bin.readI16At(data, table.offset + 20),
        .caret_offset = try bin.readI16At(data, table.offset + 22),
        .metric_data_format = try bin.readI16At(data, table.offset + 32),
        .long_metric_count = try bin.readU16At(data, table.offset + 34),
    };
}

pub fn validate(
    data: []const u8,
    table: sfnt.Record,
    kind: Kind,
) Error!types.Header {
    // hhea and vhea are fixed 36-byte tables with no extension payload.
    if (table.length != 36) return error.BadSfnt;
    const result = try read(data, table);

    switch (kind) {
        .horizontal => if (result.version != 0x00010000) {
            return error.InvalidMetrics;
        },
        .vertical => if (result.version != 0x00010000 and
            result.version != 0x00011000)
        {
            return error.InvalidMetrics;
        },
    }

    // This widened expression is the default line advance consumed by layout.
    // Zero or negative values would collapse or invert line boxes.
    if (@as(i32, result.ascender) -
        @as(i32, result.descender) +
        @as(i32, result.line_gap) <= 0)
    {
        return error.InvalidMetrics;
    }

    // Four reserved int16 fields plus metricDataFormat must remain zero. This
    // keeps the final count field unambiguous across all accepted revisions.
    for (0..5) |index| {
        if (try bin.readU16At(data, table.offset + 24 + index * 2) != 0) {
            return error.InvalidMetrics;
        }
    }
    return result;
}
