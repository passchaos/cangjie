//! Mark lookup run-capability and accelerator parity contracts.

const std = @import("std");
const accelerator_core = @import("../../../../accelerator/root.zig");
const dispatcher = @import("../../../../runtime/lookup/dispatcher/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
const positioning = @import("../../../../positioning/root.zig");
const table_core = @import("../../../../table/root.zig");

const Adjustment = positioning.Adjustment;
const LookupAccelerator = accelerator_core.model.Lookup;
const Table = table_core.View;
const buildLookupAccelerator = accelerator_core.build.lookup.one;
const collectLookup = dispatcher.collect;
const collectLookupWithIndex = dispatcher.collectWithIndex;
const deinitLookupAcceleratorContents =
    accelerator_core.build.lookup.deinitContents;

test "GPOS skips direct mark lookups when GDEF classes show no marks" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 56;

    writeU16(&bytes, 0, 4); // MarkBasePos lookup.
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);

    const mark_base = 8;
    writeU16(&bytes, mark_base + 0, 1);
    writeU16(&bytes, mark_base + 2, 12);
    writeU16(&bytes, mark_base + 4, 18);
    writeU16(&bytes, mark_base + 6, 1);
    writeU16(&bytes, mark_base + 8, 24);
    writeU16(&bytes, mark_base + 10, 36);
    writeCoverage1(&bytes, mark_base + 12, 22);
    writeCoverage1(&bytes, mark_base + 18, 20);

    const mark_array = mark_base + 24;
    writeU16(&bytes, mark_array + 0, 1);
    writeU16(&bytes, mark_array + 2, 0);
    writeU16(&bytes, mark_array + 4, 6);
    writeAnchor1(&bytes, mark_array + 6, 10, 15);

    const base_array = mark_base + 36;
    writeU16(&bytes, base_array + 0, 1);
    writeU16(&bytes, base_array + 2, 4);
    writeAnchor1(&bytes, base_array + 4, 100, 120);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    const glyphs = [_]GlyphId{ 20, 22 };

    var fallback_adjustments = std.ArrayList(Adjustment).empty;
    defer fallback_adjustments.deinit(allocator);
    try collectLookup(table, 0, &glyphs, &fallback_adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), fallback_adjustments.items.len);

    const accelerator = try buildLookupAccelerator(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 1), accelerator.mark_to_base_subtables.len);
    try std.testing.expectEqual(@as(?usize, 0), accelerator.mark_to_base_subtables[0].mark_coverage.?.index(22));
    try std.testing.expectEqual(@as(?usize, 0), accelerator.mark_to_base_subtables[0].base_coverage.?.index(20));

    var accelerated_adjustments = std.ArrayList(Adjustment).empty;
    defer accelerated_adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        0,
        &glyphs,
        &accelerated_adjustments,
        allocator,
        .{ .lookup_accelerators = &accelerators },
        null,
    );
    try std.testing.expectEqualSlices(Adjustment, fallback_adjustments.items, accelerated_adjustments.items);

    var glyph_classes = [_]u16{0} ** 24;
    glyph_classes[20] = 1; // Base.
    glyph_classes[22] = 1; // GDEF says this covered glyph is not a mark.
    var classified_adjustments = std.ArrayList(Adjustment).empty;
    defer classified_adjustments.deinit(allocator);
    try collectLookup(table, 0, &glyphs, &classified_adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expectEqual(@as(usize, 0), classified_adjustments.items.len);

    glyph_classes[22] = 3;
    try collectLookup(table, 0, &glyphs, &classified_adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expectEqual(@as(usize, 1), classified_adjustments.items.len);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}
fn writeAnchor1(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16(bytes, offset, 1);
    writeI16(bytes, offset + 2, x);
    writeI16(bytes, offset + 4, y);
}
fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
