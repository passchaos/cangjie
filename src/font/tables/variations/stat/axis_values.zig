//! STAT AxisValue formats and cross-record ambiguity validation.

const bin = @import("../../../../binary.zig");
const name = @import("../../../../opentype/name.zig");
const sfnt = @import("../../../sfnt/root.zig");
const table = @import("table.zig");
const types = @import("types.zig");
const formats = @import("formats.zig");

pub const Error = table.Error || name.Error;

pub const Summary = struct {
    offset: usize,
    length: usize,
    kind: Kind,
};

const Point = struct {
    axis_index: u16,
    value: i32,
    flags: u16,
    name_id: u16,
    format: u16,
};

const Range = struct {
    axis_index: u16,
    nominal: i32,
    min: i32,
    max: i32,
    flags: u16,
    name_id: u16,
};

const MultiAxis = struct {
    axis_count: usize,
};

const Coordinate = struct {
    axis_index: u16,
    value: i32,
};

const Kind = union(enum) {
    point: Point,
    range: Range,
    multi_axis: MultiAxis,
};

pub fn validate(
    data: []const u8,
    record: sfnt.Record,
    layout: types.Info,
    offset: usize,
    name_index: ?*const name.NameIdIndex,
) Error!Summary {
    const absolute = record.offset + offset;
    if (absolute + 4 > record.offset + record.length) return error.BadSfnt;
    const format = try bin.readU16At(data, absolute);

    // AxisValue offsets identify independent payloads. They cannot alias the
    // DesignAxisRecord array or their own offset array, because either alias
    // would reinterpret table-directory metadata as a style label.
    const design_axes_end = layout.design_axes_offset +
        layout.design_axis_count * layout.design_axis_size;
    if (offset >= layout.design_axes_offset and offset < design_axes_end) {
        return error.BadSfnt;
    }
    const offsets_end =
        layout.axis_value_offsets_offset + layout.axis_value_count * 2;
    if (offset >= layout.axis_value_offsets_offset and offset < offsets_end) {
        return error.BadSfnt;
    }

    return switch (format) {
        1 => try formats.point(
            data,
            record,
            layout,
            offset,
            name_index,
            format,
            12,
        ),
        2 => try formats.range(data, record, layout, offset, name_index),
        3 => try formats.point(
            data,
            record,
            layout,
            offset,
            name_index,
            format,
            16,
        ),
        4 => try formats.multiAxis(
            data,
            record,
            layout,
            offset,
            name_index,
        ),
        else => error.BadSfnt,
    };
}

pub fn validateSet(
    data: []const u8,
    record: sfnt.Record,
    values: []const Summary,
) Error!void {
    for (values, 0..) |value, index| {
        for (values[0..index]) |previous| {
            try validatePair(data, record, previous, value);
        }
    }
}

fn validatePair(
    data: []const u8,
    record: sfnt.Record,
    a: Summary,
    b: Summary,
) Error!void {
    if (a.offset < b.offset + b.length and b.offset < a.offset + a.length) {
        return error.BadSfnt;
    }
    switch (a.kind) {
        .point => |a_point| switch (b.kind) {
            .point => |b_point| try validatePointPair(a_point, b_point),
            .range => |b_range| try validatePointRange(a_point, b_range),
            .multi_axis => {},
        },
        .range => |a_range| switch (b.kind) {
            .point => |b_point| try validatePointRange(b_point, a_range),
            .range => |b_range| try validateRangePair(a_range, b_range),
            .multi_axis => {},
        },
        .multi_axis => |a_multi| switch (b.kind) {
            .point, .range => {},
            .multi_axis => |b_multi| _ = try validateMultiAxisPair(
                data,
                record,
                a,
                a_multi,
                b,
                b_multi,
            ),
        },
    }
}

fn validateMultiAxisPair(
    data: []const u8,
    record: sfnt.Record,
    a: Summary,
    a_multi: MultiAxis,
    b: Summary,
    b_multi: MultiAxis,
) Error!bool {
    if (a_multi.axis_count != b_multi.axis_count) return false;
    // Coordinates are a set, not an ordered tuple. Platform fonts may repeat a
    // set under different labels, so report equality to the caller but retain
    // the existing compatibility policy of accepting that duplicate.
    for (0..a_multi.axis_count) |index| {
        const coordinate = try readCoordinate(data, record, a.offset, index);
        const b_value = try valueForAxis(
            data,
            record,
            b.offset,
            b_multi.axis_count,
            coordinate.axis_index,
        ) orelse return false;
        if (b_value != coordinate.value) return false;
    }
    return true;
}

fn validatePointPair(a: Point, b: Point) Error!void {
    if (a.axis_index == b.axis_index and a.value == b.value) {
        return error.BadSfnt;
    }
}

fn validatePointRange(point: Point, range: Range) Error!void {
    if (point.axis_index != range.axis_index or
        point.value < range.min or point.value > range.max)
    {
        return;
    }
    if (point.format == 3 and
        point.value == range.nominal and
        point.flags == range.flags and
        point.name_id == range.name_id)
    {
        return;
    }
    if (point.value > range.min and point.value < range.max) {
        return error.BadSfnt;
    }
    if (point.value == range.nominal) return error.BadSfnt;
}

fn validateRangePair(a: Range, b: Range) Error!void {
    if (a.axis_index != b.axis_index) return;
    const lower, const upper = if (a.min < b.min or
        (a.min == b.min and a.max <= b.max))
        .{ a, b }
    else
        .{ b, a };
    if (lower.max > upper.min) return error.BadSfnt;
    if (lower.max == upper.min and
        lower.nominal == lower.max and
        upper.nominal == upper.min)
    {
        return error.BadSfnt;
    }
}

pub fn validateFlags(flags: u16) Error!void {
    // STAT currently defines OLDER_SIBLING_FONT_ATTRIBUTE and
    // ELIDABLE_AXIS_VALUE_NAME only.
    if ((flags & ~@as(u16, 0x0003)) != 0) return error.BadSfnt;
}

pub fn readCoordinate(
    data: []const u8,
    record: sfnt.Record,
    offset: usize,
    index: usize,
) Error!Coordinate {
    const axis_record = record.offset + offset + 8 + index * 6;
    return .{
        .axis_index = try bin.readU16At(data, axis_record),
        .value = try bin.readI32At(data, axis_record + 2),
    };
}

fn valueForAxis(
    data: []const u8,
    record: sfnt.Record,
    offset: usize,
    axis_count: usize,
    axis_index: u16,
) Error!?i32 {
    for (0..axis_count) |index| {
        const coordinate = try readCoordinate(data, record, offset, index);
        if (coordinate.axis_index == axis_index) return coordinate.value;
    }
    return null;
}
