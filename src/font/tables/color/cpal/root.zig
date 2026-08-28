//! OpenType `CPAL` validation and palette reads.

const std = @import("std");

const name = @import("../../../../opentype/name.zig");
const read = @import("read.zig");
const validate_mod = @import("validate.zig");
const types = @import("types.zig");

pub const Error = types.Error;
pub const Table = types.Table;
pub const Color = types.Color;
pub const Palette = types.Palette;
pub const Layout = types.Layout;

pub fn validate(
    data: []const u8,
    table: Table,
    name_table: ?name.Table,
) Error!Layout {
    const layout = try validate_mod.structure(data, table);
    try validate_mod.nameReferences(data, table, layout, name_table);
    return layout;
}

pub fn validateStructure(
    data: []const u8,
    table: Table,
) Error!Layout {
    return try validate_mod.structure(data, table);
}

pub fn validateNameReferences(
    data: []const u8,
    table: Table,
    name_table: ?name.Table,
) Error!void {
    const layout = try validate_mod.structure(data, table);
    return try validate_mod.nameReferences(
        data,
        table,
        layout,
        name_table,
    );
}

pub fn color(
    data: []const u8,
    table: Table,
    layout: Layout,
    palette_index: u16,
    color_index: u16,
) Error!?Color {
    return try read.color(
        data,
        table,
        layout,
        palette_index,
        color_index,
    );
}

pub fn colorAfterProof(
    data: []const u8,
    table: Table,
    layout: Layout,
    palette_index: u16,
    color_index: u16,
) ?Color {
    if (palette_index >= layout.palette_count or
        color_index >= layout.palette_entries)
    {
        return null;
    }
    const palette_record = table.offset + 12 +
        @as(usize, palette_index) * 2;
    const first_color_index = std.mem.readInt(
        u16,
        data[palette_record..][0..2],
        .big,
    );
    const record = table.offset + layout.color_records_offset +
        (@as(usize, first_color_index) + color_index) * 4;
    const bgra = data[record..][0..4];
    return .{
        .blue = bgra[0],
        .green = bgra[1],
        .red = bgra[2],
        .alpha = bgra[3],
    };
}

pub fn colors(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: Table,
    layout: Layout,
    palette_index: u16,
) Error![]Color {
    return try read.colors(
        allocator,
        data,
        table,
        layout,
        palette_index,
    );
}

pub fn palettes(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: Table,
    layout: Layout,
) Error![]Palette {
    return try read.palettes(allocator, data, table, layout);
}

pub fn entryLabels(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: Table,
    layout: Layout,
) Error![]?u16 {
    return try read.entryLabels(allocator, data, table, layout);
}

test "palette slices are ordered and non-overlapping" {
    var bytes: [32]u8 = .{0} ** 32;
    writeU16(&bytes, 0, 0);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 4);
    writeU32(&bytes, 8, 16);
    writeU16(&bytes, 12, 0);
    writeU16(&bytes, 14, 2);
    const table = Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(u16, 2),
        (try validateStructure(&bytes, table)).palette_entries,
    );

    var duplicate_start = bytes;
    writeU16(&duplicate_start, 14, 0);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(&duplicate_start, table),
    );

    var overlapping_slice = bytes;
    writeU16(&overlapping_slice, 14, 1);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(&overlapping_slice, table),
    );

    var out_of_order = bytes;
    writeU16(&out_of_order, 12, 2);
    writeU16(&out_of_order, 14, 0);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(&out_of_order, table),
    );
}

test "color records follow palette metadata and contain every entry" {
    var header_overlap: [20]u8 = .{0} ** 20;
    writeU16(&header_overlap, 0, 0);
    writeU16(&header_overlap, 2, 1);
    writeU16(&header_overlap, 4, 2);
    writeU16(&header_overlap, 6, 1);
    writeU32(&header_overlap, 8, 14);
    writeU16(&header_overlap, 12, 0);
    writeU16(&header_overlap, 14, 0);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(
            &header_overlap,
            .{ .offset = 0, .length = header_overlap.len },
        ),
    );

    var truncated_palette: [18]u8 = .{0} ** 18;
    writeU16(&truncated_palette, 0, 0);
    writeU16(&truncated_palette, 2, 2);
    writeU16(&truncated_palette, 4, 1);
    writeU16(&truncated_palette, 6, 1);
    writeU32(&truncated_palette, 8, 14);
    writeU16(&truncated_palette, 12, 0);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(
            &truncated_palette,
            .{ .offset = 0, .length = truncated_palette.len },
        ),
    );
}

test "v1 labels resolve through the name table" {
    var bytes: [54]u8 = .{0} ** 54;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 1);
    writeU32(&bytes, 8, 30);
    writeU16(&bytes, 12, 0);
    writeU32(&bytes, 14, 0);
    writeU32(&bytes, 18, 26);
    writeU32(&bytes, 22, 28);
    writeU16(&bytes, 26, 256);
    writeU16(&bytes, 28, 0xffff);
    bytes[30] = 10;
    bytes[31] = 20;
    bytes[32] = 30;
    bytes[33] = 40;

    const name_offset = 34;
    writeU16(&bytes, name_offset, 0);
    writeU16(&bytes, name_offset + 2, 1);
    writeU16(&bytes, name_offset + 4, 18);
    writeUtf16NameRecord(&bytes, name_offset + 6, 256, 2, 0);
    bytes[name_offset + 19] = 'P';

    const table = Table{ .offset = 0, .length = name_offset };
    const name_table = name.Table{
        .offset = name_offset,
        .length = bytes.len - name_offset,
    };
    try validateNameReferences(&bytes, table, name_table);

    var missing_palette_label = bytes;
    writeU16(&missing_palette_label, 26, 257);
    try std.testing.expectError(
        error.InvalidName,
        validateNameReferences(&missing_palette_label, table, name_table),
    );

    var missing_entry_label = bytes;
    writeU16(&missing_entry_label, 28, 257);
    try std.testing.expectError(
        error.InvalidName,
        validateNameReferences(&missing_entry_label, table, name_table),
    );
    try std.testing.expectError(
        error.InvalidName,
        validateNameReferences(&bytes, table, null),
    );
}

test "v1 rejects reserved palette type bits and aliased payload arrays" {
    var bytes: [38]u8 = .{0} ** 38;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 1);
    writeU32(&bytes, 8, 34);
    writeU16(&bytes, 12, 0);
    writeU32(&bytes, 14, 26);
    writeU32(&bytes, 18, 30);
    writeU32(&bytes, 22, 32);
    writeU32(&bytes, 26, 0x0000_0003);
    writeU16(&bytes, 30, 0xffff);
    writeU16(&bytes, 32, 0xffff);
    bytes[34] = 10;
    bytes[35] = 20;
    bytes[36] = 30;
    bytes[37] = 40;
    const table = Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(u16, 1),
        (try validateStructure(&bytes, table)).palette_entries,
    );

    var reserved_type = bytes;
    writeU32(&reserved_type, 26, 0x0000_0004);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(&reserved_type, table),
    );

    var label_alias = bytes;
    writeU32(&label_alias, 22, 30);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(&label_alias, table),
    );

    var color_alias = bytes;
    writeU32(&color_alias, 8, 28);
    writeU32(&color_alias, 26, 0);
    try std.testing.expectError(
        error.BadSfnt,
        validateStructure(&color_alias, table),
    );
}

test "validated layout drives color palette and label reads" {
    var bytes: [38]u8 = .{0} ** 38;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 1);
    writeU32(&bytes, 8, 34);
    writeU16(&bytes, 12, 0);
    writeU32(&bytes, 14, 26);
    writeU32(&bytes, 18, 30);
    writeU32(&bytes, 22, 32);
    writeU32(&bytes, 26, 3);
    writeU16(&bytes, 30, 256);
    writeU16(&bytes, 32, 257);
    bytes[34] = 10;
    bytes[35] = 20;
    bytes[36] = 30;
    bytes[37] = 40;

    const table = Table{ .offset = 0, .length = bytes.len };
    const layout = try validateStructure(&bytes, table);
    const selected = (try color(&bytes, table, layout, 0, 0)).?;
    try std.testing.expectEqual(@as(u8, 30), selected.red);
    try std.testing.expectEqual(@as(u8, 20), selected.green);
    try std.testing.expectEqual(@as(u8, 10), selected.blue);
    try std.testing.expectEqual(@as(u8, 40), selected.alpha);

    const palette_list = try palettes(
        std.testing.allocator,
        &bytes,
        table,
        layout,
    );
    defer std.testing.allocator.free(palette_list);
    try std.testing.expectEqual(@as(u32, 3), palette_list[0].palette_type);
    try std.testing.expectEqual(@as(?u16, 256), palette_list[0].label_name_id);

    const labels = try entryLabels(
        std.testing.allocator,
        &bytes,
        table,
        layout,
    );
    defer std.testing.allocator.free(labels);
    try std.testing.expectEqual(@as(?u16, 257), labels[0]);
}

fn writeUtf16NameRecord(
    bytes: []u8,
    offset: usize,
    name_id: u16,
    length: u16,
    storage_offset: u16,
) void {
    writeU16(bytes, offset, 3);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, 0x0409);
    writeU16(bytes, offset + 6, name_id);
    writeU16(bytes, offset + 8, length);
    writeU16(bytes, offset + 10, storage_offset);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
