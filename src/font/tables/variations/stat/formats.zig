//! STAT AxisValue format-specific structural validation.

const bin = @import("../../../../binary.zig");
const name = @import("../../../../opentype/name.zig");
const sfnt = @import("../../../sfnt/root.zig");
const axis_values = @import("axis_values.zig");
const types = @import("types.zig");

pub const Error = axis_values.Error;

pub fn point(
    data: []const u8,
    record: sfnt.Record,
    layout: types.Info,
    offset: usize,
    name_index: ?*const name.NameIdIndex,
    format: u16,
    length: usize,
) Error!axis_values.Summary {
    if (length > record.length - offset) return error.BadSfnt;
    const absolute = record.offset + offset;
    const axis_index = try bin.readU16At(data, absolute + 2);
    if (axis_index >= layout.design_axis_count) return error.BadSfnt;
    const flags = try bin.readU16At(data, absolute + 4);
    try axis_values.validateFlags(flags);
    const name_id = try bin.readU16At(data, absolute + 6);
    try name.validateIdReference(name_index, name_id);
    return .{
        .offset = offset,
        .length = length,
        .kind = .{ .point = .{
            .axis_index = axis_index,
            .value = try bin.readI32At(data, absolute + 8),
            .flags = flags,
            .name_id = name_id,
            .format = format,
        } },
    };
}

pub fn range(
    data: []const u8,
    record: sfnt.Record,
    layout: types.Info,
    offset: usize,
    name_index: ?*const name.NameIdIndex,
) Error!axis_values.Summary {
    const length: usize = 20;
    if (length > record.length - offset) return error.BadSfnt;
    const absolute = record.offset + offset;
    const axis_index = try bin.readU16At(data, absolute + 2);
    if (axis_index >= layout.design_axis_count) return error.BadSfnt;
    const flags = try bin.readU16At(data, absolute + 4);
    try axis_values.validateFlags(flags);
    const name_id = try bin.readU16At(data, absolute + 6);
    try name.validateIdReference(name_index, name_id);
    const nominal = try bin.readI32At(data, absolute + 8);
    const min = try bin.readI32At(data, absolute + 12);
    const max = try bin.readI32At(data, absolute + 16);
    if (min > nominal or nominal > max) return error.BadSfnt;
    return .{
        .offset = offset,
        .length = length,
        .kind = .{ .range = .{
            .axis_index = axis_index,
            .nominal = nominal,
            .min = min,
            .max = max,
            .flags = flags,
            .name_id = name_id,
        } },
    };
}

pub fn multiAxis(
    data: []const u8,
    record: sfnt.Record,
    layout: types.Info,
    offset: usize,
    name_index: ?*const name.NameIdIndex,
) Error!axis_values.Summary {
    if (offset + 8 > record.length) return error.BadSfnt;
    const absolute = record.offset + offset;
    const axis_count: usize =
        @intCast(try bin.readU16At(data, absolute + 2));
    if (axis_count == 0 or
        axis_count > (record.length - offset - 8) / 6)
    {
        return error.BadSfnt;
    }
    const flags = try bin.readU16At(data, absolute + 4);
    try axis_values.validateFlags(flags);
    const name_id = try bin.readU16At(data, absolute + 6);
    try name.validateIdReference(name_index, name_id);
    for (0..axis_count) |axis_record_index| {
        const axis_record = absolute + 8 + axis_record_index * 6;
        const axis_index = try bin.readU16At(data, axis_record);
        if (axis_index >= layout.design_axis_count) return error.BadSfnt;
        for (0..axis_record_index) |previous_index| {
            const previous = absolute + 8 + previous_index * 6;
            if (axis_index == try bin.readU16At(data, previous)) {
                return error.BadSfnt;
            }
        }
    }

    const length = 8 + axis_count * 6;
    if (axis_count == 1) {
        const coordinate = try axis_values.readCoordinate(data, record, offset, 0);
        // A one-coordinate format 4 has no compound specificity. Treat it as
        // a point so duplicate or range-ambiguous labels do not depend on table
        // order merely because the producer selected another encoding format.
        return .{
            .offset = offset,
            .length = length,
            .kind = .{ .point = .{
                .axis_index = coordinate.axis_index,
                .value = coordinate.value,
                .flags = flags,
                .name_id = name_id,
                .format = 4,
            } },
        };
    }
    return .{
        .offset = offset,
        .length = length,
        .kind = .{ .multi_axis = .{ .axis_count = axis_count } },
    };
}
