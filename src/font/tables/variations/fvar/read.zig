//! Owned fvar axis and named-instance decoding.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const table = @import("table.zig");
const types = @import("types.zig");

pub const Error = table.Error || std.mem.Allocator.Error;

pub fn axes(
    allocator: std.mem.Allocator,
    data: []const u8,
    record: sfnt.Record,
) Error![]types.Axis {
    const layout = try table.info(data, record);
    const result = try allocator.alloc(types.Axis, layout.axis_count);
    errdefer allocator.free(result);
    for (result, 0..) |*axis, index| {
        const offset = table.axisOffset(record, layout, index);
        axis.* = .{
            .tag = try bin.readTagAt(data, offset),
            .min_value = fixed16_16ToF32(
                try bin.readI32At(data, offset + 4),
            ),
            .default_value = fixed16_16ToF32(
                try bin.readI32At(data, offset + 8),
            ),
            .max_value = fixed16_16ToF32(
                try bin.readI32At(data, offset + 12),
            ),
            .flags = try bin.readU16At(data, offset + 16),
            .name_id = try bin.readU16At(data, offset + 18),
        };
    }
    return result;
}

pub fn instances(
    allocator: std.mem.Allocator,
    data: []const u8,
    record: sfnt.Record,
) Error![]types.Instance {
    const layout = try table.info(data, record);
    const result = try allocator.alloc(types.Instance, layout.instance_count);
    errdefer allocator.free(result);
    var initialized: usize = 0;
    errdefer freeInitialized(allocator, result[0..initialized]);

    for (result, 0..) |*instance, instance_index| {
        const offset = table.instanceOffset(record, layout, instance_index);
        const coordinates =
            try allocator.alloc(types.Coordinate, layout.axis_count);
        errdefer allocator.free(coordinates);
        for (coordinates, 0..) |*coordinate, axis_index| {
            const axis = table.axisOffset(record, layout, axis_index);
            coordinate.* = .{
                .tag = try bin.readTagAt(data, axis),
                .value = fixed16_16ToF32(
                    try bin.readI32At(
                        data,
                        offset + 4 + axis_index * 4,
                    ),
                ),
            };
        }
        instance.* = .{
            .subfamily_name_id = try bin.readU16At(data, offset),
            .flags = try bin.readU16At(data, offset + 2),
            .postscript_name_id = if (layout.has_postscript_name_id) id: {
                const value = try bin.readU16At(
                    data,
                    offset + layout.postscript_name_id_offset,
                );
                break :id if (value == 0xffff) null else value;
            } else null,
            .coordinates = coordinates,
        };
        initialized += 1;
    }
    return result;
}

pub fn freeInstances(
    allocator: std.mem.Allocator,
    values: []types.Instance,
) void {
    freeInitialized(allocator, values);
    allocator.free(values);
}

fn freeInitialized(
    allocator: std.mem.Allocator,
    values: []types.Instance,
) void {
    for (values) |instance| allocator.free(instance.coordinates);
}

fn fixed16_16ToF32(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}
