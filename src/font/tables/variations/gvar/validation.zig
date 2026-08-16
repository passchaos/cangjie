//! gvar table validation plus cross-table glyf point-target validation.

const std = @import("std");
const gvar = @import("../../../../opentype/gvar.zig");
const sfnt = @import("../../../sfnt/root.zig");
const truetype = @import("../../truetype/root.zig");

pub const Error = gvar.Error || truetype.loca.Error;

pub const TargetContext = struct {
    loca: sfnt.Record,
    glyf: sfnt.Record,
    index_to_loc_format: i16,
};

pub const targetCount = targetCountForGlyph;

pub fn validate(
    data: []const u8,
    record: sfnt.Record,
    glyph_count: u16,
    axis_count: usize,
    target_context: ?TargetContext,
) Error!void {
    // The existing gvar parser proves table/header/tuple grammar. This adapter
    // adds only the cross-table constraint: explicit point IDs and all-points
    // delta counts must fit each glyph's real points/components plus phantoms.
    try gvar.validate(
        data,
        record.offset,
        record.length,
        glyph_count,
        axis_count,
    );
    const parsed = try gvar.info(
        data,
        record.offset,
        record.length,
        glyph_count,
        axis_count,
    );
    const table = data[record.offset .. record.offset + record.length];
    for (0..glyph_count) |glyph_index| {
        const glyph = (try gvar.glyphInfo(
            data,
            record.offset,
            record.length,
            glyph_count,
            axis_count,
            glyph_index,
        )) orelse continue;
        const target_count: ?usize = if (target_context) |context|
            try targetCountForGlyph(data, context, @intCast(glyph_index))
        else
            null;

        const glyph_end = glyph.data_offset + glyph.data_length;
        var tuple_data_cursor = glyph.data_offset + glyph.tuple_data_offset;
        const shared_points: ?gvar.PointNumbersInfo =
            if (glyph.uses_shared_point_numbers) blk: {
                const points = try gvar.packedPointNumbersInfo(
                    table,
                    tuple_data_cursor,
                    glyph_end,
                );
                tuple_data_cursor += points.bytes_consumed;
                break :blk points;
            } else null;

        for (0..glyph.tuple_count) |tuple_index| {
            const tuple = (try gvar.tupleInfo(
                data,
                record.offset,
                record.length,
                glyph_count,
                axis_count,
                glyph_index,
                tuple_index,
            )) orelse return error.BadSfnt;
            try validateTupleCoordinates(table, parsed, tuple);

            if (tuple.variation_data_size > glyph_end - tuple_data_cursor) {
                return error.BadSfnt;
            }
            const tuple_end = tuple_data_cursor + tuple.variation_data_size;
            var payload_cursor = tuple_data_cursor;
            const points = if (tuple.private_point_numbers) blk: {
                const private = try gvar.packedPointNumbersInfo(
                    table,
                    payload_cursor,
                    tuple_end,
                );
                payload_cursor += private.bytes_consumed;
                break :blk private;
            } else shared_points orelse gvar.PointNumbersInfo{
                .all_points = true,
                .count = 0,
                .max_point = 0,
                .bytes_consumed = 0,
            };

            const delta_count: ?usize = if (points.all_points)
                target_count
            else blk: {
                if (target_count) |count| {
                    if (points.count != 0 and points.max_point >= count) {
                        return error.BadSfnt;
                    }
                }
                break :blk points.count;
            };
            if (delta_count) |count| {
                const x = try gvar.packedDeltasInfo(
                    table,
                    payload_cursor,
                    tuple_end,
                    count,
                );
                payload_cursor += x.bytes_consumed;
                const y = try gvar.packedDeltasInfo(
                    table,
                    payload_cursor,
                    tuple_end,
                    count,
                );
                payload_cursor += y.bytes_consumed;
                if (payload_cursor != tuple_end) return error.BadSfnt;
            }
            tuple_data_cursor = tuple_end;
        }
    }
}

fn validateTupleCoordinates(
    table: []const u8,
    parsed: gvar.Info,
    tuple: gvar.TupleInfo,
) Error!void {
    const shared_index = tuple.shared_tuple_index;
    for (0..parsed.axis_count) |axis_index| {
        const peak_offset = if (tuple.embedded_peak_tuple)
            tuple.header_offset + 4 + axis_index * 2
        else
            parsed.shared_tuple_offset +
                @as(usize, shared_index orelse return error.BadSfnt) *
                    @as(usize, parsed.axis_count) * 2 +
                axis_index * 2;
        const peak = try normalizedCoordinate(table, peak_offset);
        if (!tuple.intermediate_region) continue;

        var intermediate = tuple.header_offset + 4;
        if (tuple.embedded_peak_tuple) {
            intermediate += @as(usize, parsed.axis_count) * 2;
        }
        const start = try normalizedCoordinate(
            table,
            intermediate + axis_index * 2,
        );
        const end = try normalizedCoordinate(
            table,
            intermediate + @as(usize, parsed.axis_count) * 2 + axis_index * 2,
        );
        // Keep malformed support regions out of the parsed face instead of
        // silently treating them as an inactive tuple during interpolation.
        if (start > peak or peak > end) return error.BadSfnt;
        if (start < 0 and end > 0 and peak != 0) return error.BadSfnt;
    }
}

fn normalizedCoordinate(data: []const u8, offset: usize) Error!i16 {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    const value = std.mem.readInt(i16, data[offset..][0..2], .big);
    if (value < -0x4000 or value > 0x4000) return error.BadSfnt;
    return value;
}

fn targetCountForGlyph(
    data: []const u8,
    context: TargetContext,
    glyph_id: u16,
) Error!usize {
    const start = try truetype.loca.offset(
        data,
        context.loca,
        context.index_to_loc_format,
        glyph_id,
    );
    const end = try truetype.loca.offset(
        data,
        context.loca,
        context.index_to_loc_format,
        @as(usize, glyph_id) + 1,
    );
    if (end == start) return 4;
    if (end < start or end > context.glyf.length) return error.InvalidLoca;
    const glyph_data =
        data[context.glyf.offset + start .. context.glyf.offset + end];
    return (try gvar.glyfVariationPointCount(glyph_data)) + 4;
}
