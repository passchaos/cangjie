//! GDEF AttachList runtime and public borrowed-byte contracts.

const std = @import("std");

const face_mod = @import("../../../face/root.zig");
const font_mod = @import("../../../../font.zig");
const gdef = @import("../../../tables/layout/gdef/root.zig");
const table_only = @import("../../fixtures/table_only.zig");
const fixture = @import("../../fixtures/sfnt.zig");

test "GDEF attachment points read covered glyphs and both coverage formats" {
    const allocator = std.testing.allocator;
    var bytes = attachListTable(false);
    const format1 = try gdef.readAttachmentPoints(
        allocator,
        &bytes,
        12,
        3,
    );
    defer allocator.free(format1);
    try expectPointIndexes(&.{ 4, 7 }, format1);

    const uncovered = try gdef.readAttachmentPoints(
        allocator,
        &bytes,
        12,
        2,
    );
    defer allocator.free(uncovered);
    try std.testing.expectEqual(@as(usize, 0), uncovered.len);

    bytes = attachListTable(true);
    const format2 = try gdef.readAttachmentPoints(
        allocator,
        &bytes,
        12,
        3,
    );
    defer allocator.free(format2);
    try expectPointIndexes(&.{ 4, 7 }, format2);
}

test "public GDEF attachment points revalidate borrowed bytes" {
    const allocator = std.testing.allocator;
    var bytes = attachListTable(false);
    var font = tableOnlyFont(&bytes);
    defer font.deinit();
    const face = face_mod.backend.face(&font);

    const points = try face.glyphs().attachmentPoints(allocator, 3);
    defer allocator.free(points);
    try expectPointIndexes(&.{ 4, 7 }, points);

    const inspected =
        @import("../../../../api/font/metadata/layout/root.zig")
            .inspect(face);
    const inspection_points = try inspected.attachmentPoints(allocator, 3);
    defer allocator.free(inspection_points);
    try expectPointIndexes(&.{ 4, 7 }, inspection_points);

    fixture.writeU16(&bytes, 28, 4);
    try std.testing.expectError(
        error.BadSfnt,
        font.attachmentPoints(allocator, 3),
    );
}

test "public attachment points define missing and invalid glyph behavior" {
    const allocator = std.testing.allocator;
    const inert: [1]u8 = .{0};
    var no_gdef = table_only.init(font_mod.Font, &inert, 4, 1);
    defer no_gdef.deinit();

    const empty = try no_gdef.attachmentPoints(allocator, 1);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expectError(
        error.InvalidGlyph,
        no_gdef.attachmentPoints(allocator, 4),
    );
}

fn attachListTable(format2: bool) [36]u8 {
    var bytes: [36]u8 = .{0} ** 36;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0);
    fixture.writeU16(&bytes, 6, 12);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 16, if (format2) 16 else 12);
    if (format2) {
        fixture.writeU16(&bytes, 18, 2);
        fixture.writeU16(&bytes, 20, 1);
        fixture.writeU16(&bytes, 22, 3);
        fixture.writeU16(&bytes, 24, 3);
        fixture.writeU16(&bytes, 26, 0);
        fixture.writeU16(&bytes, 28, 2);
        fixture.writeU16(&bytes, 30, 4);
        fixture.writeU16(&bytes, 32, 7);
    } else {
        fixture.writeU16(&bytes, 18, 1);
        fixture.writeU16(&bytes, 20, 1);
        fixture.writeU16(&bytes, 22, 3);
        fixture.writeU16(&bytes, 24, 2);
        fixture.writeU16(&bytes, 26, 4);
        fixture.writeU16(&bytes, 28, 7);
    }
    return bytes;
}

fn tableOnlyFont(data: []const u8) font_mod.Font {
    var font = table_only.init(font_mod.Font, data, 4, 1);
    font.gdef = table_only.record(
        data,
        .{ 'G', 'D', 'E', 'F' },
        0,
        data.len,
    );
    return font;
}

fn expectPointIndexes(
    expected: []const u16,
    actual: []const font_mod.AttachmentPoint,
) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |value, point| {
        try std.testing.expectEqual(value, point.point_index);
    }
}
