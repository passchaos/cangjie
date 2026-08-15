//! COLR v1 variation-index reference and sequence validation.

const std = @import("std");

const glyphs = @import("../../validate/glyphs.zig");
const types = @import("../../types.zig");
const variation = @import("../root.zig");

test "COLR v1 variable ClipBoxes own varIndexBase bytes" {
    var bytes: [176]u8 = .{0} ** 176;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 140 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 22, 34); // ClipListOffset.
    writeU32Test(&bytes, colr_offset + 30, 82); // ItemVariationStoreOffset.

    const clip_list = colr_offset + 34;
    bytes[clip_list] = 1; // ClipList format 1.
    writeU32Test(&bytes, clip_list + 1, 2);
    writeU16Test(&bytes, clip_list + 5, 0);
    writeU16Test(&bytes, clip_list + 7, 0);
    writeU24Test(&bytes, clip_list + 9, 19); // First ClipBoxFormat2 at byte 89.
    writeU16Test(&bytes, clip_list + 12, 1);
    writeU16Test(&bytes, clip_list + 14, 1);
    writeU24Test(&bytes, clip_list + 16, 32); // Second ClipBoxFormat2 starts exactly after the first.

    const first_box = clip_list + 19;
    bytes[first_box] = 2; // ClipBoxFormat2 includes a trailing varIndexBase.
    writeI16Test(&bytes, first_box + 1, 0);
    writeI16Test(&bytes, first_box + 3, 0);
    writeI16Test(&bytes, first_box + 5, 10);
    writeI16Test(&bytes, first_box + 7, 10);
    writeU32Test(&bytes, first_box + 9, 0);

    const second_box = clip_list + 32;
    bytes[second_box] = 2;
    writeI16Test(&bytes, second_box + 1, 20);
    writeI16Test(&bytes, second_box + 3, 20);
    writeI16Test(&bytes, second_box + 5, 30);
    writeI16Test(&bytes, second_box + 7, 30);
    writeU32Test(&bytes, second_box + 9, 0);

    writeItemVariationStoreWithItems(&bytes, colr_offset + 82, 4);
    try variation.validate(&bytes, colr, 1, 2);
    try glyphs.validate(&bytes, colr, 2);

    var var_payload_overlap = bytes;
    writeU24Test(&var_payload_overlap, clip_list + 16, 28); // Header starts inside the first ClipBox varIndexBase.
    const overlapping_box = clip_list + 28;
    var_payload_overlap[overlapping_box] = 2;
    writeI16Test(&var_payload_overlap, overlapping_box + 1, 0);
    writeI16Test(&var_payload_overlap, overlapping_box + 3, 0);
    writeI16Test(&var_payload_overlap, overlapping_box + 5, 10);
    writeI16Test(&var_payload_overlap, overlapping_box + 7, 10);
    writeU32Test(&var_payload_overlap, overlapping_box + 9, 0);
    try std.testing.expectError(error.BadSfnt, glyphs.validate(&var_payload_overlap, colr, 2));
}

test "COLR v1 variable paints reference valid variation data" {
    var bytes: [128]u8 = .{0} ** 128;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 92 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarSolid at BaseGlyphList + 10.
    bytes[colr_offset + 44] = 3;
    writeU16Test(&bytes, colr_offset + 45, 0);
    writeF2Dot14Test(&bytes, colr_offset + 47, 1.0);
    writeU32Test(&bytes, colr_offset + 49, 0); // varIndexBase.

    var missing_store = bytes;
    try std.testing.expectError(error.BadSfnt, variation.validate(&missing_store, colr, 1, 2));

    writeU32Test(&bytes, colr_offset + 30, 53); // ItemVariationStoreOffset.
    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 53);
    try variation.validate(&bytes, colr, 1, 2);

    var bad_implicit_var_index = bytes;
    writeU32Test(&bad_implicit_var_index, colr_offset + 49, 1); // outer 0, inner 1; item 0 has one row.
    try std.testing.expectError(error.BadSfnt, variation.validate(&bad_implicit_var_index, colr, 1, 2));

    var bad_map = bytes;
    writeU32Test(&bad_map, colr_offset + 26, 53); // VarIndexMapOffset.
    writeU32Test(&bad_map, colr_offset + 30, 58); // ItemVariationStoreOffset follows the map.
    bad_map[colr_offset + 53] = 0; // DeltaSetIndexMap format 0.
    bad_map[colr_offset + 54] = 0; // one-byte entries, one inner-index bit.
    writeU16Test(&bad_map, colr_offset + 55, 1); // one mapping entry.
    bad_map[colr_offset + 57] = 1; // outer 0, inner 1; outside the single item row.
    writeItemVariationStoreWithOneItem(&bad_map, colr_offset + 58);
    try std.testing.expectError(error.BadSfnt, variation.validate(&bad_map, colr, 1, 2));
}

test "COLR v1 variable gradients validate paint and stop variation indexes" {
    var bytes: [180]u8 = .{0} ** 180;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 144 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 30, 90); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarLinearGradient at BaseGlyphList + 10.

    bytes[colr_offset + 44] = 5; // PaintVarLinearGradient.
    writeU24Test(&bytes, colr_offset + 45, 20); // VarColorLine starts immediately after the paint.
    writeI16Test(&bytes, colr_offset + 48, 0); // x0.
    writeI16Test(&bytes, colr_offset + 50, 0); // y0.
    writeI16Test(&bytes, colr_offset + 52, 100); // x1.
    writeI16Test(&bytes, colr_offset + 54, 0); // y1.
    writeI16Test(&bytes, colr_offset + 56, 0); // x2.
    writeI16Test(&bytes, colr_offset + 58, 100); // y2.
    writeU32Test(&bytes, colr_offset + 60, 0); // geometry varIndexBase covers six coordinate deltas.

    const color_line = colr_offset + 64;
    bytes[color_line] = 0; // ExtendMode.pad.
    writeU16Test(&bytes, color_line + 1, 2);
    writeF2Dot14Test(&bytes, color_line + 3, 0.0);
    writeU16Test(&bytes, color_line + 5, 0);
    writeF2Dot14Test(&bytes, color_line + 7, 1.0);
    writeU32Test(&bytes, color_line + 9, 0); // stop/alpha varIndexBase covers two deltas.
    writeF2Dot14Test(&bytes, color_line + 13, 1.0);
    writeU16Test(&bytes, color_line + 15, 0);
    writeF2Dot14Test(&bytes, color_line + 17, 1.0);
    writeU32Test(&bytes, color_line + 19, 0);

    writeItemVariationStoreWithItems(&bytes, colr_offset + 90, 6);
    try variation.validate(&bytes, colr, 1, 2);

    var missing_store = bytes;
    writeU32Test(&missing_store, colr_offset + 30, 0);
    try std.testing.expectError(error.BadSfnt, variation.validate(&missing_store, colr, 1, 2));

    var bad_geometry_index = bytes;
    writeU32Test(&bad_geometry_index, colr_offset + 60, 1); // Sequence 1..6 exceeds the six-row item data.
    try std.testing.expectError(error.BadSfnt, variation.validate(&bad_geometry_index, colr, 1, 2));

    var bad_stop_index = bytes;
    writeU32Test(&bad_stop_index, color_line + 19, 5); // VarColorStop needs rows 5 and 6.
    try std.testing.expectError(error.BadSfnt, variation.validate(&bad_stop_index, colr, 1, 2));
}

test "COLR v1 variable transform paints validate variation indexes" {
    var bytes: [180]u8 = .{0} ** 180;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 134 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 30, 90); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarTransform at BaseGlyphList + 10.

    bytes[colr_offset + 44] = 13; // PaintVarTransform.
    writeU24Test(&bytes, colr_offset + 45, 35); // Child PaintSolid after the matrix.
    writeU24Test(&bytes, colr_offset + 48, 7); // VarAffine2x3 follows the seven-byte paint header.
    writeF16Dot16Test(&bytes, colr_offset + 51, 1.0); // xx.
    writeF16Dot16Test(&bytes, colr_offset + 55, 0.0); // yx.
    writeF16Dot16Test(&bytes, colr_offset + 59, 0.0); // xy.
    writeF16Dot16Test(&bytes, colr_offset + 63, 1.0); // yy.
    writeF16Dot16Test(&bytes, colr_offset + 67, 0.0); // dx.
    writeF16Dot16Test(&bytes, colr_offset + 71, 0.0); // dy.
    writeU32Test(&bytes, colr_offset + 75, 0); // varIndexBase covers the six matrix scalars.
    bytes[colr_offset + 79] = 2; // PaintSolid child.
    writeU16Test(&bytes, colr_offset + 80, 0);
    writeF2Dot14Test(&bytes, colr_offset + 82, 1.0);

    writeItemVariationStoreWithItems(&bytes, colr_offset + 90, 6);
    try variation.validate(&bytes, colr, 1, 2);

    var missing_store = bytes;
    writeU32Test(&missing_store, colr_offset + 30, 0);
    try std.testing.expectError(error.BadSfnt, variation.validate(&missing_store, colr, 1, 2));

    var bad_matrix_index = bytes;
    writeU32Test(&bad_matrix_index, colr_offset + 75, 1); // Matrix deltas need rows 1 through 6.
    try std.testing.expectError(error.BadSfnt, variation.validate(&bad_matrix_index, colr, 1, 2));
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24Test(bytes: []u8, offset: usize, value: u32) void {
    std.debug.assert(value <= 0x00ff_ffff);
    bytes[offset] = @intCast(value >> 16);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeF2Dot14Test(bytes: []u8, offset: usize, value: f32) void {
    writeI16Test(bytes, offset, @intFromFloat(@round(value * 16384.0)));
}

fn writeF16Dot16Test(bytes: []u8, offset: usize, value: f32) void {
    std.mem.writeInt(i32, bytes[offset..][0..4], @intFromFloat(@round(value * 65536.0)), .big);
}

fn writeItemVariationStoreWithOneItem(bytes: []u8, offset: usize) void {
    writeItemVariationStoreWithItems(bytes, offset, 1);
}

fn writeItemVariationStoreWithItems(bytes: []u8, offset: usize, item_count: u16) void {
    writeU16Test(bytes, offset, 1);
    writeU32Test(bytes, offset + 2, 12);
    writeU16Test(bytes, offset + 6, 1);
    writeU32Test(bytes, offset + 8, 24);

    writeU16Test(bytes, offset + 12, 1);
    writeU16Test(bytes, offset + 14, 1);
    writeF2Dot14Test(bytes, offset + 16, -1.0);
    writeF2Dot14Test(bytes, offset + 18, 0.0);
    writeF2Dot14Test(bytes, offset + 20, 1.0);

    writeU16Test(bytes, offset + 24, item_count);
    writeU16Test(bytes, offset + 26, 1);
    writeU16Test(bytes, offset + 28, 1);
    writeU16Test(bytes, offset + 30, 0);
    for (0..item_count) |index| {
        writeI16Test(bytes, offset + 32 + index * 2, 7);
    }
}
