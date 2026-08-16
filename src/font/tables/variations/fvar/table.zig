//! fvar header, axis-record, and instance-record grammar.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub fn validate(data: []const u8, record: sfnt.Record) Error!void {
    const layout = try info(data, record);

    for (0..layout.axis_count) |axis_index| {
        const offset = axisOffset(record, layout, axis_index);
        const min_value = try bin.readI32At(data, offset + 4);
        const default_value = try bin.readI32At(data, offset + 8);
        const max_value = try bin.readI32At(data, offset + 12);
        if (min_value > default_value or default_value > max_value) {
            return error.BadSfnt;
        }

        // OpenType 1.x defines only HIDDEN_AXIS. Unknown bits must not turn
        // future or corrupted semantics into an ordinary visible UI control.
        const flags = try bin.readU16At(data, offset + 16);
        if ((flags & ~@as(u16, 0x0001)) != 0) return error.BadSfnt;

        const tag = try bin.readTagAt(data, offset);
        try sfnt.validateTag(tag);
        for (0..axis_index) |previous_index| {
            const previous = axisOffset(record, layout, previous_index);
            const previous_tag = try bin.readTagAt(data, previous);
            const previous_flags = try bin.readU16At(data, previous + 16);
            // Hidden duplicate axes occur in deployed fonts. A duplicate pair
            // is ambiguous only when both axes are application-visible.
            if (std.mem.eql(u8, &previous_tag, &tag) and
                (flags & 0x0001) == 0 and
                (previous_flags & 0x0001) == 0)
            {
                return error.BadSfnt;
            }
        }
    }

    for (0..layout.instance_count) |instance_index| {
        const instance = instanceOffset(record, layout, instance_index);
        if (try bin.readU16At(data, instance + 2) != 0) {
            return error.BadSfnt;
        }
        for (0..layout.axis_count) |axis_index| {
            const coordinate =
                try bin.readI32At(data, instance + 4 + axis_index * 4);
            const axis = axisOffset(record, layout, axis_index);
            const min_value = try bin.readI32At(data, axis + 4);
            const max_value = try bin.readI32At(data, axis + 12);
            if (coordinate < min_value or coordinate > max_value) {
                return error.BadSfnt;
            }
        }
    }
}

pub fn info(data: []const u8, record: sfnt.Record) Error!types.Info {
    if (record.offset > data.len or record.length > data.len - record.offset or
        record.length < 16)
    {
        return error.BadSfnt;
    }
    const major = try bin.readU16At(data, record.offset);
    const minor = try bin.readU16At(data, record.offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;

    const axes_array_offset: usize =
        @intCast(try bin.readU16At(data, record.offset + 4));
    const count_size_pairs = try bin.readU16At(data, record.offset + 6);
    const axis_count: usize =
        @intCast(try bin.readU16At(data, record.offset + 8));
    const axis_size: usize =
        @intCast(try bin.readU16At(data, record.offset + 10));
    const instance_count: usize =
        @intCast(try bin.readU16At(data, record.offset + 12));
    const instance_size: usize =
        @intCast(try bin.readU16At(data, record.offset + 14));
    if (count_size_pairs != 2) return error.BadSfnt;

    const required_axis_size: usize = 20;
    const coordinate_only_instance_size: usize = 4 + axis_count * 4;
    // fvar has fixed AxisRecords. Instance records contain exactly the header
    // and coordinates, optionally followed by one PostScript NameID. Reject
    // private padding because no consumer could assign it stable semantics.
    if (axis_size != required_axis_size) return error.BadSfnt;
    if (instance_count == 0) {
        if (instance_size != 0 and
            instance_size != coordinate_only_instance_size and
            instance_size != coordinate_only_instance_size + 2)
        {
            return error.BadSfnt;
        }
    } else if (instance_size != coordinate_only_instance_size and
        instance_size != coordinate_only_instance_size + 2)
    {
        return error.BadSfnt;
    }

    // countSizePairs fixes the header at 16 bytes. Prove both table-local
    // regions before deriving absolute offsets from caller-controlled counts.
    if (axes_array_offset < 16 or axes_array_offset > record.length) {
        return error.BadSfnt;
    }
    if (axis_count > (record.length - axes_array_offset) / axis_size) {
        return error.BadSfnt;
    }
    const instances_array_offset =
        axes_array_offset + axis_count * axis_size;
    if (instance_size != 0 and
        instance_count >
            (record.length - instances_array_offset) / instance_size)
    {
        return error.BadSfnt;
    }

    return .{
        .axes_array_offset = axes_array_offset,
        .axis_count = axis_count,
        .axis_size = axis_size,
        .instance_count = instance_count,
        .instance_size = instance_size,
        .instances_array_offset = instances_array_offset,
        .postscript_name_id_offset = coordinate_only_instance_size,
        .has_postscript_name_id = instance_size >= coordinate_only_instance_size + 2,
    };
}

pub fn axisOffset(
    record: sfnt.Record,
    layout: types.Info,
    index: usize,
) usize {
    std.debug.assert(index < layout.axis_count);
    return record.offset + layout.axes_array_offset + index * layout.axis_size;
}

pub fn instanceOffset(
    record: sfnt.Record,
    layout: types.Info,
    index: usize,
) usize {
    std.debug.assert(index < layout.instance_count);
    return record.offset +
        layout.instances_array_offset +
        index * layout.instance_size;
}
