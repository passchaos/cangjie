//! MarkLigPos runtime contracts.

const std = @import("std");
const ligature_provenance =
    @import("../../../../../ligature_provenance.zig");
const marks = @import("../../../../runtime/lookup/marks/root.zig");
const output_state = @import("../../../../runtime/output/root.zig");
const table = @import("../../../../table/root.zig");

test "MarkLigPos attaches a mark to a ligature component" {
    var bytes = [_]u8{0} ** 50;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 18);
    writeU16(&bytes, 6, 1);
    writeU16(&bytes, 8, 24);
    writeU16(&bytes, 10, 36);
    writeCoverage1(&bytes, 12, 22);
    writeCoverage1(&bytes, 18, 20);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 6);
    writeAnchor1(&bytes, 30, 10, 15);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 4);
    writeU16(&bytes, 40, 1);
    writeU16(&bytes, 42, 4);
    writeAnchor1(&bytes, 44, 100, 120);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(marks.ligature.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try marks.ligature.collect(
        view,
        0,
        &.{ 20, 22 },
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    );
    const mark = output_state.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, 90), mark.x_placement);
    try std.testing.expectEqual(@as(i16, 105), mark.y_placement);
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);

    adjustments.clearRetainingCapacity();
    writeU16(&bytes, 38, 0);
    try std.testing.expectError(
        error.BadGpos,
        marks.ligature.collect(
            view,
            0,
            &.{ 20, 22 },
            &adjustments,
            std.testing.allocator,
            0,
            .{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "MarkLigPos uses source metadata for component selection" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeMarkLigatureHeader(&bytes, 12, 18, 24, 36);
    writeCoverage1(&bytes, 12, 22);
    writeCoverage1(&bytes, 18, 20);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 6);
    writeAnchor1(&bytes, 30, 10, 15);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 4);
    writeU16(&bytes, 40, 2);
    writeU16(&bytes, 42, 8);
    writeU16(&bytes, 44, 14);
    writeAnchor1(&bytes, 48, 100, 120);
    writeAnchor1(&bytes, 54, 260, 300);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    const info = try components.addLigature(allocator, &.{ 0, 1 });
    try components.infos.appendSlice(allocator, &.{ info, .{} });
    var adjustments = std.ArrayList(marks.ligature.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try marks.ligature.collect(
        view,
        0,
        &.{ 20, 22 },
        &adjustments,
        allocator,
        0,
        .{ .run_metadata = &.{
            .glyph_source_indices = &.{ 0, 2 },
            .ligature_components = &components,
        } },
    );
    const mark = output_state.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, 250), mark.x_placement);
    try std.testing.expectEqual(@as(i16, 285), mark.y_placement);
}

test "MarkLigPos uses last component for a MultipleSubst base" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeMarkLigatureHeader(&bytes, 12, 18, 24, 36);
    writeCoverage1(&bytes, 12, 22);
    writeCoverage1(&bytes, 18, 20);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 6);
    writeAnchor1(&bytes, 30, 10, 15);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 4);
    writeU16(&bytes, 40, 2);
    writeU16(&bytes, 42, 8);
    writeU16(&bytes, 44, 14);
    writeAnchor1(&bytes, 48, 100, 120);
    writeAnchor1(&bytes, 54, 260, 300);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    try components.infos.appendSlice(allocator, &.{
        .{ .flags = .{
            .multiplied = true,
            .multiple_component = 0,
        } },
        .{ .flags = .{
            .multiplied = true,
            .multiple_component = 1,
        } },
        .{},
    });
    var adjustments = std.ArrayList(marks.ligature.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try marks.ligature.collect(
        view,
        0,
        &.{ 20, 21, 22 },
        &adjustments,
        allocator,
        0,
        .{ .run_metadata = &.{
            .ligature_components = &components,
        } },
    );
    const mark = output_state.adjustments.find(adjustments.items, 2).?;
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 250), mark.x_placement);
    try std.testing.expectEqual(@as(i16, 285), mark.y_placement);
}

test "MarkLigPos skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeMarkLigatureHeader(&bytes, 12, 18, 24, 44);
    writeCoverage1(&bytes, 12, 22);
    writeCoverage1(&bytes, 18, 20);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 8);
    writeAnchor1(&bytes, 32, 0, 0);
    writeU16(&bytes, 44, 1);
    writeU16(&bytes, 46, 4);
    writeU16(&bytes, 48, 1);
    writeU16(&bytes, 50, 4);
    writeAnchor1(&bytes, 52, 100, 120);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var glyph_classes = [_]u16{0} ** 23;
    glyph_classes[20] = 2;
    glyph_classes[21] = 1;
    glyph_classes[22] = 3;
    var adjustments = std.ArrayList(marks.ligature.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try marks.ligature.collect(
        view,
        0,
        &.{ 20, 21, 22 },
        &adjustments,
        allocator,
        0x0002,
        .{ .glyph_classes = &glyph_classes },
    );
    const mark = output_state.adjustments.find(adjustments.items, 2).?;
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 100), mark.x_placement);
}

test "MarkLigPos falls back to mark order for component anchors" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    writeMarkLigatureHeader(&bytes, 12, 20, 26, 54);
    writeCoverageList1(&bytes, 12, &.{ 22, 23 });
    writeCoverage1(&bytes, 20, 20);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 0);
    writeU16(&bytes, 30, 10);
    writeU16(&bytes, 32, 0);
    writeU16(&bytes, 34, 16);
    writeAnchor1(&bytes, 36, 0, 0);
    writeAnchor1(&bytes, 42, 0, 0);
    writeU16(&bytes, 54, 1);
    writeU16(&bytes, 56, 4);
    writeU16(&bytes, 58, 2);
    writeU16(&bytes, 60, 6);
    writeU16(&bytes, 62, 12);
    writeAnchor1(&bytes, 64, 100, 110);
    writeAnchor1(&bytes, 70, 300, 330);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var glyph_classes = [_]u16{0} ** 24;
    glyph_classes[20] = 2;
    glyph_classes[22] = 3;
    glyph_classes[23] = 3;
    var adjustments = std.ArrayList(marks.ligature.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try marks.ligature.collect(
        view,
        0,
        &.{ 20, 22, 23 },
        &adjustments,
        allocator,
        0,
        .{ .glyph_classes = &glyph_classes },
    );
    try std.testing.expectEqual(
        @as(i16, 100),
        output_state.adjustments.find(adjustments.items, 1).?.x_placement,
    );
    try std.testing.expectEqual(
        @as(i16, 300),
        output_state.adjustments.find(adjustments.items, 2).?.x_placement,
    );
}

fn writeMarkLigatureHeader(
    bytes: []u8,
    mark_coverage: u16,
    ligature_coverage: u16,
    mark_array: u16,
    ligature_array: u16,
) void {
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, mark_coverage);
    writeU16(bytes, 4, ligature_coverage);
    writeU16(bytes, 6, 1);
    writeU16(bytes, 8, mark_array);
    writeU16(bytes, 10, ligature_array);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeCoverageList1(bytes, offset, &.{glyph});
}

fn writeCoverageList1(bytes: []u8, offset: usize, glyphs: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
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
