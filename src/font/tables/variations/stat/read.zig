//! Owned STAT design-axis and AxisValue decoding.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const table = @import("table.zig");
const types = @import("types.zig");

pub const Error = table.Error || std.mem.Allocator.Error;

pub fn elidedFallbackNameId(
    data: []const u8,
    record: sfnt.Record,
) Error!?u16 {
    const layout = try table.info(data, record);
    return if (layout.minor_version >= 1)
        try bin.readU16At(data, record.offset + 18)
    else
        null;
}

pub fn designAxes(
    allocator: std.mem.Allocator,
    data: []const u8,
    record: sfnt.Record,
) Error![]types.DesignAxis {
    const layout = try table.info(data, record);
    const axes = try allocator.alloc(types.DesignAxis, layout.design_axis_count);
    errdefer allocator.free(axes);
    for (axes, 0..) |*axis, index| {
        const offset = table.designAxisOffset(record, layout, index);
        axis.* = .{
            .tag = try bin.readTagAt(data, offset),
            .name_id = try bin.readU16At(data, offset + 4),
            .ordering = try bin.readU16At(data, offset + 6),
        };
    }
    return axes;
}

pub fn axisValues(
    allocator: std.mem.Allocator,
    data: []const u8,
    record: sfnt.Record,
) Error![]types.AxisValue {
    const layout = try table.info(data, record);
    const values = try allocator.alloc(types.AxisValue, layout.axis_value_count);
    errdefer allocator.free(values);
    var initialized: usize = 0;
    errdefer freeInitialized(allocator, values[0..initialized]);

    for (values, 0..) |*value, index| {
        const offset = try table.axisValueOffset(data, record, layout, index);
        value.* = try readAxisValue(allocator, data, record, offset);
        initialized += 1;
    }
    return values;
}

pub fn freeAxisValues(
    allocator: std.mem.Allocator,
    values: []types.AxisValue,
) void {
    freeInitialized(allocator, values);
    allocator.free(values);
}

fn freeInitialized(
    allocator: std.mem.Allocator,
    values: []types.AxisValue,
) void {
    for (values) |value| allocator.free(value.coordinates);
}

fn readAxisValue(
    allocator: std.mem.Allocator,
    data: []const u8,
    record: sfnt.Record,
    offset: usize,
) Error!types.AxisValue {
    const absolute = record.offset + offset;
    const format = try bin.readU16At(data, absolute);
    return switch (format) {
        1 => .{
            .format = format,
            .axis_index = try bin.readU16At(data, absolute + 2),
            .flags = try bin.readU16At(data, absolute + 4),
            .name_id = try bin.readU16At(data, absolute + 6),
            .value = fixed16_16ToF32(
                try bin.readI32At(data, absolute + 8),
            ),
        },
        2 => .{
            .format = format,
            .axis_index = try bin.readU16At(data, absolute + 2),
            .flags = try bin.readU16At(data, absolute + 4),
            .name_id = try bin.readU16At(data, absolute + 6),
            .nominal_value = fixed16_16ToF32(
                try bin.readI32At(data, absolute + 8),
            ),
            .range_min_value = fixed16_16ToF32(
                try bin.readI32At(data, absolute + 12),
            ),
            .range_max_value = fixed16_16ToF32(
                try bin.readI32At(data, absolute + 16),
            ),
        },
        3 => .{
            .format = format,
            .axis_index = try bin.readU16At(data, absolute + 2),
            .flags = try bin.readU16At(data, absolute + 4),
            .name_id = try bin.readU16At(data, absolute + 6),
            .value = fixed16_16ToF32(
                try bin.readI32At(data, absolute + 8),
            ),
            .linked_value = fixed16_16ToF32(
                try bin.readI32At(data, absolute + 12),
            ),
        },
        4 => value: {
            const count: usize =
                @intCast(try bin.readU16At(data, absolute + 2));
            const coordinates =
                try allocator.alloc(types.AxisValueCoordinate, count);
            errdefer allocator.free(coordinates);
            for (coordinates, 0..) |*coordinate, index| {
                const axis_record = absolute + 8 + index * 6;
                coordinate.* = .{
                    .axis_index = try bin.readU16At(data, axis_record),
                    .value = fixed16_16ToF32(
                        try bin.readI32At(data, axis_record + 2),
                    ),
                };
            }
            break :value .{
                .format = format,
                .flags = try bin.readU16At(data, absolute + 4),
                .name_id = try bin.readU16At(data, absolute + 6),
                .coordinates = coordinates,
            };
        },
        else => error.BadSfnt,
    };
}

fn fixed16_16ToF32(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}
