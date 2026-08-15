//! OpenType COLR v0 base-glyph and layer-record directories.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const glyph = @import("../../../../glyph.zig");

pub const Error = error{BadSfnt} ||
    std.mem.Allocator.Error ||
    error{EndOfStream};

pub const Table = struct {
    offset: usize,
    length: usize,
};

pub const Layer = struct {
    glyph_id: glyph.GlyphId,
    palette_index: u16,
};

pub const Layout = struct {
    base_count: u16,
    base_offset: usize,
    layer_count: u16,
    layer_offset: usize,
};

const Range = struct {
    start: usize,
    end: usize,
};

pub fn validate(
    data: []const u8,
    table: Table,
    glyph_count: u16,
    palette_entries: ?u16,
) Error!Layout {
    const layout = try structuralLayout(data, table);
    try validateGlyphReferences(data, table, layout, glyph_count);
    try validatePaletteReferences(data, table, layout, palette_entries);
    return layout;
}

pub fn validateGlyphs(
    data: []const u8,
    table: Table,
    glyph_count: u16,
) Error!Layout {
    const layout = try structuralLayout(data, table);
    try validateGlyphReferences(data, table, layout, glyph_count);
    return layout;
}

pub fn validatePalettes(
    data: []const u8,
    table: Table,
    palette_entries: ?u16,
) Error!Layout {
    const layout = try structuralLayout(data, table);
    try validatePaletteReferences(data, table, layout, palette_entries);
    return layout;
}

fn validateGlyphReferences(
    data: []const u8,
    table: Table,
    layout: Layout,
    glyph_count: u16,
) Error!void {
    var previous_base_glyph: ?glyph.GlyphId = null;
    var previous_layer_slice_end: ?u16 = null;
    for (0..layout.base_count) |index| {
        const record = table.offset + layout.base_offset + index * 6;
        const base_glyph = try bin.readU16At(data, record);
        try validateBaseGlyphOrder(base_glyph, &previous_base_glyph);
        try validateGlyphId(base_glyph, glyph_count);
        const first_layer = try bin.readU16At(data, record + 2);
        const layer_count = try bin.readU16At(data, record + 4);
        if (first_layer > layout.layer_count or
            layer_count > layout.layer_count - first_layer)
        {
            return error.BadSfnt;
        }
        try validateLayerSliceOrder(
            first_layer,
            layer_count,
            &previous_layer_slice_end,
        );
    }

    for (0..layout.layer_count) |index| {
        const record = table.offset + layout.layer_offset + index * 4;
        try validateGlyphId(try bin.readU16At(data, record), glyph_count);
    }
}

fn validatePaletteReferences(
    data: []const u8,
    table: Table,
    layout: Layout,
    palette_entries: ?u16,
) Error!void {
    for (0..layout.layer_count) |index| {
        const record = table.offset + layout.layer_offset + index * 4;
        try validatePaletteIndex(
            try bin.readU16At(data, record + 2),
            palette_entries,
        );
    }
}

pub fn layers(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: Table,
    layout: Layout,
    glyph_id: glyph.GlyphId,
) Error![]Layer {
    for (0..layout.base_count) |index| {
        const record = table.offset + layout.base_offset + index * 6;
        if (try bin.readU16At(data, record) != glyph_id) continue;
        const first_layer = try bin.readU16At(data, record + 2);
        const layer_count = try bin.readU16At(data, record + 4);
        const result = try allocator.alloc(Layer, layer_count);
        errdefer allocator.free(result);
        for (result, 0..) |*layer, layer_index| {
            const layer_record = table.offset +
                layout.layer_offset +
                (@as(usize, first_layer) + layer_index) * 4;
            layer.* = .{
                .glyph_id = try bin.readU16At(data, layer_record),
                .palette_index = try bin.readU16At(data, layer_record + 2),
            };
        }
        return result;
    }
    return try allocator.alloc(Layer, 0);
}

pub fn structuralLayout(
    data: []const u8,
    table: Table,
) Error!Layout {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 14) return error.BadSfnt;
    if (try bin.readU16At(data, table.offset) != 0) return error.BadSfnt;

    const layout = Layout{
        .base_count = try bin.readU16At(data, table.offset + 2),
        .base_offset = @intCast(try bin.readU32At(data, table.offset + 4)),
        .layer_offset = @intCast(try bin.readU32At(data, table.offset + 8)),
        .layer_count = try bin.readU16At(data, table.offset + 12),
    };
    const base = try topLevelRange(
        table,
        layout.base_offset,
        layout.base_count,
        6,
    );
    const layer = try topLevelRange(
        table,
        layout.layer_offset,
        layout.layer_count,
        4,
    );

    // These independently typed arrays may not alias. Otherwise one sequence
    // of bytes could be interpreted as both base-glyph ownership and layers.
    if (rangesOverlap(base, layer)) return error.BadSfnt;
    return layout;
}

fn topLevelRange(
    table: Table,
    offset: usize,
    count: u16,
    record_size: usize,
) Error!Range {
    if (offset > table.length) return error.BadSfnt;
    if (count == 0) return .{ .start = offset, .end = offset };
    if (offset < 14) return error.BadSfnt;
    const byte_len = @as(usize, count) * record_size;
    if (byte_len > table.length - offset) return error.BadSfnt;
    return .{ .start = offset, .end = offset + byte_len };
}

fn validateBaseGlyphOrder(
    base_glyph: glyph.GlyphId,
    previous_base_glyph: *?glyph.GlyphId,
) Error!void {
    if (previous_base_glyph.*) |previous| {
        // BaseGlyphRecords are binary-search records keyed by glyph ID.
        if (base_glyph <= previous) return error.BadSfnt;
    }
    previous_base_glyph.* = base_glyph;
}

fn validateLayerSliceOrder(
    first_layer: u16,
    layer_count: u16,
    previous_layer_slice_end: *?u16,
) Error!void {
    if (previous_layer_slice_end.*) |previous_end| {
        // Slices follow BaseGlyphRecord order and cannot share mutable layer
        // metadata with an earlier color glyph.
        if (first_layer < previous_end) return error.BadSfnt;
    }
    previous_layer_slice_end.* = first_layer + layer_count;
}

fn validateGlyphId(glyph_id: glyph.GlyphId, glyph_count: u16) Error!void {
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

fn validatePaletteIndex(
    palette_index: u16,
    palette_entries: ?u16,
) Error!void {
    if (palette_index == 0xffff) return;
    const entries = palette_entries orelse return error.BadSfnt;
    if (palette_index >= entries) return error.BadSfnt;
}

fn rangesOverlap(lhs: Range, rhs: Range) bool {
    return lhs.start < rhs.end and rhs.start < lhs.end;
}

test "top-level arrays cannot alias the header or each other" {
    var bytes: [34]u8 = .{0} ** 34;
    writeU16(&bytes, 0, 0);
    writeU16(&bytes, 2, 1);
    writeU32(&bytes, 4, 14);
    writeU32(&bytes, 8, 20);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0);
    writeU16(&bytes, 18, 1);
    writeU16(&bytes, 20, 1);
    writeU16(&bytes, 22, 0);
    const table = Table{ .offset = 0, .length = 24 };
    _ = try structuralLayout(&bytes, table);

    var header_alias = bytes;
    writeU32(&header_alias, 4, 8);
    try std.testing.expectError(
        error.BadSfnt,
        structuralLayout(&header_alias, table),
    );

    var array_alias = bytes;
    writeU32(&array_alias, 8, 16);
    try std.testing.expectError(
        error.BadSfnt,
        structuralLayout(&array_alias, table),
    );
}

test "validation checks ordering ownership glyphs and palette entries" {
    var bytes: [42]u8 = .{0} ** 42;
    writeU16(&bytes, 0, 0);
    writeU16(&bytes, 2, 2);
    writeU32(&bytes, 4, 14);
    writeU32(&bytes, 8, 26);
    writeU16(&bytes, 12, 4);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0);
    writeU16(&bytes, 18, 2);
    writeU16(&bytes, 20, 2);
    writeU16(&bytes, 22, 2);
    writeU16(&bytes, 24, 2);
    for (0..4) |index| {
        writeU16(&bytes, 26 + index * 4, @intCast(index));
        writeU16(&bytes, 28 + index * 4, 0);
    }
    const table = Table{ .offset = 0, .length = bytes.len };
    _ = try validate(&bytes, table, 4, 1);

    var unordered = bytes;
    writeU16(&unordered, 20, 1);
    try std.testing.expectError(
        error.BadSfnt,
        validate(&unordered, table, 4, 1),
    );

    var overlapping = bytes;
    writeU16(&overlapping, 22, 1);
    try std.testing.expectError(
        error.BadSfnt,
        validate(&overlapping, table, 4, 1),
    );

    var decreasing = bytes;
    writeU16(&decreasing, 16, 2);
    writeU16(&decreasing, 18, 1);
    writeU16(&decreasing, 22, 0);
    writeU16(&decreasing, 24, 2);
    // Slices 2..3 and 0..2 are physically disjoint but do not follow the
    // BaseGlyphRecord order.
    try std.testing.expectError(
        error.BadSfnt,
        validate(&decreasing, table, 4, 1),
    );

    var bad_glyph = bytes;
    writeU16(&bad_glyph, 38, 4);
    try std.testing.expectError(
        error.BadSfnt,
        validate(&bad_glyph, table, 4, 1),
    );

    var bad_palette = bytes;
    writeU16(&bad_palette, 28, 1);
    try std.testing.expectError(
        error.BadSfnt,
        validate(&bad_palette, table, 4, 1),
    );
    writeU16(&bad_palette, 28, 0xffff);
    _ = try validate(&bad_palette, table, 4, 1);
}

test "validated layout reads the selected glyph layers" {
    var bytes: [24]u8 = .{0} ** 24;
    writeU16(&bytes, 0, 0);
    writeU16(&bytes, 2, 1);
    writeU32(&bytes, 4, 14);
    writeU32(&bytes, 8, 20);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0);
    writeU16(&bytes, 18, 1);
    writeU16(&bytes, 20, 2);
    writeU16(&bytes, 22, 0);
    const table = Table{ .offset = 0, .length = bytes.len };
    const layout = try validate(&bytes, table, 3, 1);
    const result = try layers(
        std.testing.allocator,
        &bytes,
        table,
        layout,
        1,
    );
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(glyph.GlyphId, 2), result[0].glyph_id);
    try std.testing.expectEqual(@as(u16, 0), result[0].palette_index);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
