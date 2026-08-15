//! Owned and scalar reads from a structurally validated CPAL layout.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const types = @import("types.zig");

pub fn color(
    data: []const u8,
    table: types.Table,
    layout: types.Layout,
    palette_index: u16,
    color_index: u16,
) types.Error!?types.Color {
    if (palette_index >= layout.palette_count or
        color_index >= layout.palette_entries)
    {
        return null;
    }
    const first_color_index = try bin.readU16At(
        data,
        table.offset + 12 + @as(usize, palette_index) * 2,
    );
    return try readColor(
        data,
        table,
        layout,
        @as(usize, first_color_index) + color_index,
    );
}

pub fn colors(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: types.Table,
    layout: types.Layout,
    palette_index: u16,
) types.Error![]types.Color {
    if (palette_index >= layout.palette_count) {
        return try allocator.alloc(types.Color, 0);
    }
    const result = try allocator.alloc(types.Color, layout.palette_entries);
    errdefer allocator.free(result);
    const first_color_index = try bin.readU16At(
        data,
        table.offset + 12 + @as(usize, palette_index) * 2,
    );
    for (result, 0..) |*entry, color_index| {
        entry.* = try readColor(
            data,
            table,
            layout,
            @as(usize, first_color_index) + color_index,
        );
    }
    return result;
}

pub fn palettes(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: types.Table,
    layout: types.Layout,
) types.Error![]types.Palette {
    const result = try allocator.alloc(types.Palette, layout.palette_count);
    errdefer allocator.free(result);
    for (result, 0..) |*palette, index| {
        palette.* = .{
            .first_color_index = try bin.readU16At(
                data,
                table.offset + 12 + index * 2,
            ),
            .color_count = layout.palette_entries,
            .palette_type = if (layout.palette_types_offset != 0)
                try bin.readU32At(
                    data,
                    table.offset + layout.palette_types_offset + index * 4,
                )
            else
                0,
            .label_name_id = if (layout.palette_labels_offset != 0) label: {
                const name_id = try bin.readU16At(
                    data,
                    table.offset + layout.palette_labels_offset + index * 2,
                );
                break :label optionalNameId(name_id);
            } else null,
        };
    }
    return result;
}

pub fn entryLabels(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: types.Table,
    layout: types.Layout,
) types.Error![]?u16 {
    const labels = try allocator.alloc(?u16, layout.palette_entries);
    errdefer allocator.free(labels);
    @memset(labels, null);
    if (layout.palette_entry_labels_offset == 0) return labels;

    for (labels, 0..) |*label, index| {
        label.* = optionalNameId(try bin.readU16At(
            data,
            table.offset + layout.palette_entry_labels_offset + index * 2,
        ));
    }
    return labels;
}

fn readColor(
    data: []const u8,
    table: types.Table,
    layout: types.Layout,
    record_index: usize,
) types.Error!types.Color {
    const record =
        table.offset + layout.color_records_offset + record_index * 4;
    // `validate.structure` proved the entire ColorRecordsArray range and each
    // palette slice. This helper intentionally consumes that proof rather than
    // re-running partial checks that could drift from validation semantics.
    return .{
        .blue = data[record],
        .green = data[record + 1],
        .red = data[record + 2],
        .alpha = data[record + 3],
    };
}

fn optionalNameId(value: u16) ?u16 {
    return if (value == 0xffff) null else value;
}
