//! CursivePos runtime execution contracts.

const std = @import("std");
const cursive = @import("../../../runtime/lookup/cursive.zig");
const output = @import("../../../runtime/output/root.zig");
const table = @import("../../../table/root.zig");

test "cursive joins preserve placement across overlapping links" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 120, .y = 35 },
        .{ .x = 120, .y = 185 },
        0,
        .ltr,
    );
    try cursive.appendJoin(
        &adjustments,
        allocator,
        1,
        2,
        .{ .x = 268, .y = 139 },
        .{ .x = 0, .y = 0 },
        0,
        .ltr,
    );

    const middle = output.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, 148), middle.x_advance);
    try std.testing.expectEqual(@as(i16, -120), middle.x_placement);
    try std.testing.expect(middle.x_advance_absolute);
}

test "cursive joins reverse existing attachment chains" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 120, .y = 44 },
        .{ .x = 120, .y = 152 },
        0,
        .ltr,
    );
    try cursive.appendJoin(
        &adjustments,
        allocator,
        2,
        1,
        .{ .x = 376, .y = 79 },
        .{ .x = 239, .y = 152 },
        0,
        .ltr,
    );

    const old_parent = output.adjustments.find(adjustments.items, 0).?;
    const middle = output.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(?usize, 1), old_parent.attachment_parent_index);
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.cursive,
        old_parent.attachment_type,
    );
    try std.testing.expectEqual(@as(i16, 108), old_parent.y_placement);
    try std.testing.expectEqual(@as(?usize, 2), middle.attachment_parent_index);
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.cursive,
        middle.attachment_type,
    );
    try std.testing.expectEqual(@as(i16, -73), middle.y_placement);
}

test "later cursive direction replaces a reciprocal attachment" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 218, .y = 40 },
        .{ .x = 82, .y = 184 },
        0x0001,
        .ltr,
    );
    try cursive.appendJoin(
        &adjustments,
        allocator,
        0,
        1,
        .{ .x = 218, .y = 40 },
        .{ .x = 82, .y = 184 },
        0,
        .ltr,
    );

    const first = output.adjustments.find(adjustments.items, 0).?;
    const second = output.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.none,
        first.attachment_type,
    );
    try std.testing.expectEqual(@as(?usize, null), first.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 0), first.y_placement);
    try std.testing.expectEqual(
        output.adjustments.AttachmentType.cursive,
        second.attachment_type,
    );
    try std.testing.expectEqual(@as(?usize, 0), second.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, -144), second.y_placement);
}

test "nested cursive execution targets only one join" {
    var bytes = [_]u8{0} ** 42;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 22);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 30);
    writeU16(&bytes, 10, 36);
    writeU16(&bytes, 12, 0);
    writeCoverage1(&bytes, 22, &.{ 5, 6 });
    writeAnchor1(&bytes, 30, 120, 35);
    writeAnchor1(&bytes, 36, 120, 185);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expect(try cursive.collectAt(
        view,
        0,
        &.{ 5, 6 },
        1,
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    ));
    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expect(!try cursive.collectAt(
        view,
        0,
        &.{ 5, 6 },
        0,
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    ));
}

test "cursive execution skips lookup-flag ignored marks" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    writeCursiveSubtable(&bytes, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    const glyphs = [_]u16{ 10, 11, 12 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[11] = 3;
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.collect(
        view,
        0,
        &glyphs,
        &adjustments,
        allocator,
        0x0008,
        .{ .glyph_classes = &glyph_classes },
    );
    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -20), adjustments.items[1].x_advance);
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[1].y_placement);
}

test "parsed cursive execution reuses owned coverage" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    writeCursiveSubtable(&bytes, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const parsed = try cursive.build(view, 0, allocator);
    defer if (parsed.coverage) |coverage| coverage.deinit(allocator);
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.collectParsed(
        view,
        parsed,
        &.{ 10, 12 },
        &adjustments,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(i16, -20), adjustments.items[1].x_advance);
}

test "cursive execution skips only unsubstituted default ignorables" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    writeCursiveSubtable(&bytes, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    const glyphs = [_]u16{ 10, 11, 12 };
    const sources = [_]usize{ 0, 1, 2 };
    const codepoints = [_]u21{ 'A', 0x034f, 'B' };
    var adjustments = std.ArrayList(cursive.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try cursive.collect(
        view,
        0,
        &glyphs,
        &adjustments,
        allocator,
        0,
        .{ .run_metadata = &.{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
            .glyph_substituted = &.{ false, false, false },
        } },
    );
    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);

    adjustments.clearRetainingCapacity();
    try cursive.collect(
        view,
        0,
        &glyphs,
        &adjustments,
        allocator,
        0,
        .{ .run_metadata = &.{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
            .glyph_substituted = &.{ false, true, false },
        } },
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

fn writeCursiveSubtable(bytes: []u8, offset: usize) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 14);
    writeU16(bytes, offset + 4, 2);
    writeU16(bytes, offset + 6, 0);
    writeU16(bytes, offset + 8, 22);
    writeU16(bytes, offset + 10, 28);
    writeU16(bytes, offset + 12, 0);
    writeCoverage1(bytes, offset + 14, &.{ 10, 12 });
    writeAnchor1(bytes, offset + 22, 100, 30);
    writeAnchor1(bytes, offset + 28, 20, 5);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyphs: []const u16) void {
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
