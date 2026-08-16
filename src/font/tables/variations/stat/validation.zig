//! Top-level STAT validation and fvar/name cross-table contracts.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const name = @import("../../../../opentype/name.zig");
const sfnt = @import("../../../sfnt/root.zig");
const fvar = @import("../fvar/root.zig");
const axis_values = @import("axis_values.zig");
const table = @import("table.zig");

pub const Error = axis_values.Error || std.mem.Allocator.Error;

pub fn validate(
    allocator: std.mem.Allocator,
    data: []const u8,
    record: sfnt.Record,
    fvar_record: ?sfnt.Record,
    name_index: ?*const name.NameIdIndex,
) Error!void {
    const layout = try table.info(data, record);
    if (layout.minor_version >= 1) {
        try name.validateIdReference(
            name_index,
            try bin.readU16At(data, record.offset + 18),
        );
    }

    for (0..layout.design_axis_count) |index| {
        const offset = table.designAxisOffset(record, layout, index);
        const tag = try bin.readTagAt(data, offset);
        try sfnt.validateTag(tag);
        try validateDesignAxisOrder(
            data,
            record,
            fvar_record,
            layout,
            index,
            &tag,
        );
        try name.validateIdReference(
            name_index,
            try bin.readU16At(data, offset + 4),
        );
    }

    const values =
        try allocator.alloc(axis_values.Summary, layout.axis_value_count);
    defer allocator.free(values);
    for (values, 0..) |*value, index| {
        value.* = try axis_values.validate(
            data,
            record,
            layout,
            try table.axisValueOffset(data, record, layout, index),
            name_index,
        );
    }
    try axis_values.validateSet(data, record, values);
}

fn validateDesignAxisOrder(
    data: []const u8,
    record: sfnt.Record,
    fvar_record: ?sfnt.Record,
    layout: @import("types.zig").Info,
    axis_index: usize,
    axis_tag: *const [4]u8,
) Error!void {
    const axis = table.designAxisOffset(record, layout, axis_index);
    const ordering = try bin.readU16At(data, axis + 6);
    for (0..axis_index) |previous_index| {
        const previous =
            table.designAxisOffset(record, layout, previous_index);
        const previous_tag = try bin.readTagAt(data, previous);
        if (std.mem.eql(u8, axis_tag, &previous_tag) and
            !try duplicateAxisTagsAllowedByFvar(
                data,
                fvar_record,
                previous_index,
                axis_index,
            ))
        {
            return error.BadSfnt;
        }
        // AxisOrdering is STAT's canonical presentation key. Duplicate values
        // leave style UIs without a deterministic axis order.
        if (ordering == try bin.readU16At(data, previous + 6)) {
            return error.BadSfnt;
        }
    }
}

fn duplicateAxisTagsAllowedByFvar(
    data: []const u8,
    fvar_record: ?sfnt.Record,
    previous_index: usize,
    axis_index: usize,
) Error!bool {
    const record = fvar_record orelse return false;
    const layout = try fvar.info(data, record);
    if (previous_index >= layout.axis_count or axis_index >= layout.axis_count) {
        return false;
    }
    const previous = fvar.axisOffset(record, layout, previous_index);
    const axis = fvar.axisOffset(record, layout, axis_index);
    const previous_flags = try bin.readU16At(data, previous + 16);
    const flags = try bin.readU16At(data, axis + 16);
    return (previous_flags & 0x0001) != 0 or (flags & 0x0001) != 0;
}
