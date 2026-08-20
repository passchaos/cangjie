//! Whole-run GPOS orchestration contracts.

const std = @import("std");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const ligature_provenance = @import("../../../ligature_provenance.zig");
const run = @import("../../runtime/run.zig");

test "GPOS run validates source metadata cardinality before traversal" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU16(&bytes, 0, 1);

    const glyphs = [_]GlyphId{ 1, 2 };
    const sources = [_]usize{0};
    var adjustments = std.ArrayList(run.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(
        error.InvalidShapingInput,
        run.collect(
            &bytes,
            0,
            bytes.len,
            &glyphs,
            &adjustments,
            allocator,
            .{ .run_metadata = &.{ .glyph_source_indices = &sources } },
        ),
    );
}

test "GPOS run validates normalized variation coordinates" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU32(&bytes, 0, 0x00010000);
    var adjustments = std.ArrayList(run.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(
        error.InvalidShapingInput,
        run.collect(
            &bytes,
            0,
            bytes.len,
            &.{1},
            &adjustments,
            allocator,
            .{ .normalized_variation_coords = &.{std.math.nan(f32)} },
        ),
    );
    try std.testing.expectError(
        error.InvalidShapingInput,
        run.collect(
            &bytes,
            0,
            bytes.len,
            &.{1},
            &adjustments,
            allocator,
            .{ .normalized_variation_coords = &.{1.01} },
        ),
    );
}

test "GPOS run validates ligature component source order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU16(&bytes, 0, 1);

    const glyphs = [_]GlyphId{10};
    var ligature_components = ligature_provenance.Store{};
    defer ligature_components.deinit(allocator);
    try ligature_components.sources.appendSlice(allocator, &.{ 3, 2 });
    try ligature_components.infos.append(
        allocator,
        .{ .component_count = 2 },
    );
    var adjustments = std.ArrayList(run.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(
        error.InvalidShapingInput,
        run.collect(
            &bytes,
            0,
            bytes.len,
            &glyphs,
            &adjustments,
            allocator,
            .{
                .run_metadata = &.{
                    .ligature_components = &ligature_components,
                },
            },
        ),
    );
}

test "GPOS run traverses caller-selected LookupList indexes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    writeU32(&bytes, 0, 0x00010000);
    writeU16(&bytes, 4, 38); // Empty ScriptList.
    writeU16(&bytes, 6, 40); // Empty FeatureList.
    writeU16(&bytes, 8, 10); // LookupList.
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 4);
    writeSinglePositionLookup(&bytes, 14, 5, 27);
    writeU16(&bytes, 38, 0);
    writeU16(&bytes, 40, 0);

    var adjustments = std.ArrayList(run.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try run.collect(
        &bytes,
        0,
        bytes.len,
        &.{5},
        &adjustments,
        allocator,
        .{ .selected_lookups = &.{0} },
    );

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 27), adjustments.items[0].x_placement);
}

fn writeSinglePositionLookup(
    bytes: []u8,
    lookup_offset: usize,
    glyph: GlyphId,
    placement: i16,
) void {
    writeU16(bytes, lookup_offset, 1);
    writeU16(bytes, lookup_offset + 4, 1);
    writeU16(bytes, lookup_offset + 6, 8);
    const subtable = lookup_offset + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 8);
    writeU16(bytes, subtable + 4, 0x0001);
    writeI16(bytes, subtable + 6, placement);
    writeU16(bytes, subtable + 8, 1);
    writeU16(bytes, subtable + 10, 1);
    writeU16(bytes, subtable + 12, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
