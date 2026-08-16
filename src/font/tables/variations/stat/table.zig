//! STAT header, design-axis directory, and AxisValue offset grammar.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub fn info(data: []const u8, record: sfnt.Record) Error!types.Info {
    if (record.offset > data.len or record.length > data.len - record.offset or
        record.length < 20)
    {
        return error.BadSfnt;
    }
    const major = try bin.readU16At(data, record.offset);
    const minor = try bin.readU16At(data, record.offset + 2);
    if (major != 1 or minor > 2) return error.BadSfnt;

    const design_axis_size: usize =
        @intCast(try bin.readU16At(data, record.offset + 4));
    const design_axis_count: usize =
        @intCast(try bin.readU16At(data, record.offset + 6));
    const design_axes_offset: usize =
        @intCast(try bin.readU32At(data, record.offset + 8));
    const axis_value_count: usize =
        @intCast(try bin.readU16At(data, record.offset + 12));
    const axis_value_offsets_offset: usize =
        @intCast(try bin.readU32At(data, record.offset + 14));

    if (design_axis_size < 8) return error.BadSfnt;
    if (design_axis_count != 0) {
        if (design_axes_offset < 20 or design_axes_offset > record.length or
            design_axis_count >
                (record.length - design_axes_offset) / design_axis_size)
        {
            return error.BadSfnt;
        }
    } else if (design_axes_offset != 0 and design_axes_offset < 20) {
        return error.BadSfnt;
    }

    if (axis_value_count != 0) {
        if (axis_value_offsets_offset < 20 or
            axis_value_offsets_offset > record.length or
            axis_value_count >
                (record.length - axis_value_offsets_offset) / 2)
        {
            return error.BadSfnt;
        }
    } else if (axis_value_offsets_offset != 0 and
        axis_value_offsets_offset < 20)
    {
        return error.BadSfnt;
    }

    return .{
        .minor_version = minor,
        .design_axis_size = design_axis_size,
        .design_axis_count = design_axis_count,
        .design_axes_offset = design_axes_offset,
        .axis_value_count = axis_value_count,
        .axis_value_offsets_offset = axis_value_offsets_offset,
    };
}

pub fn designAxisOffset(
    record: sfnt.Record,
    layout: types.Info,
    index: usize,
) usize {
    std.debug.assert(index < layout.design_axis_count);
    return record.offset +
        layout.design_axes_offset +
        index * layout.design_axis_size;
}

pub fn axisValueOffset(
    data: []const u8,
    record: sfnt.Record,
    layout: types.Info,
    index: usize,
) Error!usize {
    if (index >= layout.axis_value_count) return error.BadSfnt;
    const entry = record.offset + layout.axis_value_offsets_offset + index * 2;
    const relative: usize = @intCast(try bin.readU16At(data, entry));
    if (relative > record.length - layout.axis_value_offsets_offset) {
        return error.BadSfnt;
    }
    const offset = layout.axis_value_offsets_offset + relative;
    if (offset < 20 or offset > record.length - 4) return error.BadSfnt;
    return offset;
}
