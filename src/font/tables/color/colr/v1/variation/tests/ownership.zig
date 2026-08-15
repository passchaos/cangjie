//! COLR v1 variation-table and typed-payload ownership validation.

const std = @import("std");

const support = @import("support.zig");
const types = @import("../../types.zig");
const variation = @import("../root.zig");

const writeF2Dot14Test = support.writeF2Dot14;
const writeI16Test = support.writeI16;
const writeItemVariationStoreWithOneItem =
    support.writeItemVariationStoreWithOneItem;
const writeU16Test = support.writeU16;
const writeU24Test = support.writeU24;
const writeU32Test = support.writeU32;

test "COLR v1 variation map and store subtables cannot overlap" {
    var bytes: [128]u8 = .{0} ** 128;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 92 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 26, 84); // VarIndexMapOffset overlaps the store's ItemVariationData.
    writeU32Test(&bytes, colr_offset + 30, 53); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarSolid at BaseGlyphList + 10.
    bytes[colr_offset + 44] = 3;
    writeU16Test(&bytes, colr_offset + 45, 0);
    writeF2Dot14Test(&bytes, colr_offset + 47, 1.0);
    writeU32Test(&bytes, colr_offset + 49, 0); // varIndexBase resolves through the map.

    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 53);

    // These bytes are still part of the ItemVariationStore payload, but they
    // can also be decoded as a valid one-entry DeltaSetIndexMap unless the
    // top-level COLR variation subtables are checked for aliasing.
    bytes[colr_offset + 86] = 0; // Delta row low byte; doubles as mapCount high byte.
    bytes[colr_offset + 87] = 1; // First byte after the store; doubles as mapCount low byte.
    bytes[colr_offset + 88] = 0; // Map entry: outer 0, inner 0.

    try std.testing.expectError(error.BadSfnt, variation.validate(&bytes, colr, 1, 2));
}

test "COLR v1 variation subtables cannot alias optional structural tables" {
    var bytes: [160]u8 = .{0} ** 160;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 124 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 18, 53); // LayerListOffset aliases VarIndexMapOffset below.
    writeU32Test(&bytes, colr_offset + 26, 53); // VarIndexMapOffset.
    writeU32Test(&bytes, colr_offset + 30, 70); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarSolid at BaseGlyphList + 10.
    bytes[colr_offset + 44] = 3;
    writeU16Test(&bytes, colr_offset + 45, 0);
    writeF2Dot14Test(&bytes, colr_offset + 47, 1.0);
    writeU32Test(&bytes, colr_offset + 49, 0); // varIndexBase resolves through the aliased map.

    // These bytes describe a one-entry LayerList (paint offset 12) but also
    // decode as a valid format-0 DeltaSetIndexMap with one one-byte entry.
    // The table must be rejected for aliasing before both interpretations can
    // reach downstream paint and variation validators.
    bytes[colr_offset + 53] = 0; // DeltaSetIndexMap format 0; LayerList count high byte.
    bytes[colr_offset + 54] = 0; // one-byte entries, one inner-index bit.
    writeU16Test(&bytes, colr_offset + 55, 1); // mapCount; LayerList count low bytes.
    writeU32Test(&bytes, colr_offset + 57, 12); // first layer paint offset; map entry byte is zero.
    bytes[colr_offset + 65] = 2; // PaintSolid reachable through the LayerList interpretation.
    writeU16Test(&bytes, colr_offset + 66, 0);
    writeF2Dot14Test(&bytes, colr_offset + 68, 1.0);
    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 70);

    try std.testing.expectError(error.BadSfnt, variation.validate(&bytes, colr, 1, 2));

    writeU32Test(&bytes, colr_offset + 26, 0); // Removing the map makes the remaining structure valid.
    try variation.validate(&bytes, colr, 1, 2);

    var store_alias = bytes;
    writeU32Test(&store_alias, colr_offset + 18, 70); // LayerListOffset aliases the ItemVariationStore.
    writeU32Test(&store_alias, colr_offset + 26, 0);
    try std.testing.expectError(error.BadSfnt, variation.validate(&store_alias, colr, 1, 2));
}

test "COLR v1 variation subtables cannot alias ClipBox payloads" {
    var bytes: [140]u8 = .{0} ** 140;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 104 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 22, 34); // ClipListOffset.
    writeU32Test(&bytes, colr_offset + 30, 55); // ItemVariationStoreOffset aliases the ClipBox varIndexBase.

    const clip_list = colr_offset + 34;
    bytes[clip_list] = 1; // ClipList format 1.
    writeU32Test(&bytes, clip_list + 1, 1);
    writeU16Test(&bytes, clip_list + 5, 0);
    writeU16Test(&bytes, clip_list + 7, 0);
    writeU24Test(&bytes, clip_list + 9, 12); // ClipBoxFormat2 starts immediately after the ClipRecord.

    const clip_box = clip_list + 12;
    bytes[clip_box] = 2;
    writeI16Test(&bytes, clip_box + 1, 0);
    writeI16Test(&bytes, clip_box + 3, 0);
    writeI16Test(&bytes, clip_box + 5, 10);
    writeI16Test(&bytes, clip_box + 7, 10);

    // The ItemVariationStore starts where ClipBoxFormat2 stores varIndexBase.
    // Both structures are individually decodable, but those four bytes still
    // belong to the ClipBox payload and must not become a top-level COLR table.
    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 55);
    try std.testing.expectError(error.BadSfnt, variation.validate(&bytes, colr, 1, 1));
}

test "COLR v1 variation subtables cannot alias paint payloads" {
    var bytes: [180]u8 = .{0} ** 180;
    const colr_offset: usize = 36;
    const colr = types.Table{ .offset = colr_offset, .length = 144 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 30, 90); // Non-overlapping ItemVariationStoreOffset for the control case.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintLinearGradient at BaseGlyphList + 10.

    bytes[colr_offset + 44] = 4; // PaintLinearGradient.
    writeU24Test(&bytes, colr_offset + 45, 20); // ColorLine starts immediately after the paint header.
    writeI16Test(&bytes, colr_offset + 48, 0); // x0.
    writeI16Test(&bytes, colr_offset + 50, 0); // y0.
    writeI16Test(&bytes, colr_offset + 52, 100); // x1.
    writeI16Test(&bytes, colr_offset + 54, 0); // y1.
    writeI16Test(&bytes, colr_offset + 56, 0); // x2.
    writeI16Test(&bytes, colr_offset + 58, 100); // y2.

    const color_line = colr_offset + 64;
    bytes[color_line] = 0; // ExtendMode.pad.
    writeU16Test(&bytes, color_line + 1, 2);
    writeF2Dot14Test(&bytes, color_line + 3, 0.0);
    writeU16Test(&bytes, color_line + 5, 0);
    writeF2Dot14Test(&bytes, color_line + 7, 1.0);
    writeF2Dot14Test(&bytes, color_line + 9, 1.0);
    writeU16Test(&bytes, color_line + 11, 1);
    writeF2Dot14Test(&bytes, color_line + 13, 1.0);

    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 90);
    try variation.validate(&bytes, colr, 1, 2);

    var color_line_alias = bytes;
    writeU32Test(&color_line_alias, colr_offset + 30, 69); // ItemVariationStoreOffset aliases first ColorStop bytes.
    writeItemVariationStoreWithOneItem(&color_line_alias, colr_offset + 69);
    try std.testing.expectError(error.BadSfnt, variation.validate(&color_line_alias, colr, 1, 2));
}
