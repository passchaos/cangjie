//! GDEF LigCaretList runtime and public inspection contracts.

const std = @import("std");

const face_mod = @import("../../../face/root.zig");
const font_mod = @import("../../../../font.zig");
const gdef = @import("../../../tables/layout/gdef/root.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");

test "GDEF ligature caret format 1 returns authored design coordinates" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildGdefLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var face = try face_mod.Face.parse(allocator, bytes);
    defer face.deinit();

    const carets = try face.glyphs().ligatureCarets(
        allocator,
        2,
        &.{},
    );
    defer allocator.free(carets);
    try std.testing.expectEqual(@as(usize, 1), carets.len);
    try std.testing.expectEqual(@as(f32, 300), carets[0].position);

    const uncovered = try face.glyphs().ligatureCarets(
        allocator,
        1,
        &.{},
    );
    defer allocator.free(uncovered);
    try std.testing.expectEqual(@as(usize, 0), uncovered.len);

    const inspected =
        @import("../../../../api/font/metadata/layout/root.zig")
            .inspect(&face);
    const inspection_carets = try inspected.ligatureCarets(
        allocator,
        2,
        &.{},
    );
    defer allocator.free(inspection_carets);
    try std.testing.expectEqual(
        @as(f32, 300),
        inspection_carets[0].position,
    );
}

test "GDEF ligature caret format 3 applies ItemVariationStore deltas" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildGdefVariableLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const default_carets = try font.ligatureCarets(allocator, 2, &.{0});
    defer allocator.free(default_carets);
    try std.testing.expectEqual(@as(f32, 300), default_carets[0].position);

    const varied_carets = try font.ligatureCarets(allocator, 2, &.{0.5});
    defer allocator.free(varied_carets);
    try std.testing.expectEqual(@as(f32, 307), varied_carets[0].position);
}

test "GDEF ligature caret format 2 resolves contour points" {
    var bytes: [34]u8 = .{0} ** 34;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0);
    fixture.writeU16(&bytes, 8, 12);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 16, 12);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 1);
    fixture.writeU16(&bytes, 22, 2);
    fixture.writeU16(&bytes, 24, 1);
    fixture.writeU16(&bytes, 26, 4);
    fixture.writeU16(&bytes, 28, 2);
    fixture.writeU16(&bytes, 30, 7);

    const Context = struct {
        fn resolve(
            _: *const anyopaque,
            glyph_id: u16,
            point_index: u16,
            normalized_coords: []const f32,
        ) gdef.LigatureCaretError!?f32 {
            if (glyph_id != 2 or
                point_index != 7 or
                normalized_coords.len != 1 or
                normalized_coords[0] != 0.25)
            {
                return error.BadSfnt;
            }
            return 123.5;
        }
    };
    const context: u8 = 0;
    const carets = try gdef.readLigatureCarets(
        std.testing.allocator,
        &bytes,
        12,
        2,
        .{
            .normalized_coords = &.{0.25},
            .contour_context = &context,
            .resolve_contour_point = Context.resolve,
        },
    );
    defer std.testing.allocator.free(carets);
    try std.testing.expectEqual(@as(f32, 123.5), carets[0].position);
}

test "GDEF runtime declines noncanonical resolved caret order" {
    var bytes: [40]u8 = .{0} ** 40;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0);
    fixture.writeU16(&bytes, 8, 12);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 16, 12);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 1);
    fixture.writeU16(&bytes, 22, 2);
    fixture.writeU16(&bytes, 24, 2);
    fixture.writeU16(&bytes, 26, 6);
    fixture.writeU16(&bytes, 28, 10);
    fixture.writeU16(&bytes, 30, 1);
    fixture.writeI16(&bytes, 32, 600);
    fixture.writeU16(&bytes, 34, 1);
    fixture.writeI16(&bytes, 36, 300);

    try std.testing.expectError(
        error.NonCanonicalCaretOrder,
        gdef.readLigatureCarets(
            std.testing.allocator,
            &bytes,
            12,
            2,
            .{},
        ),
    );
}

test "GDEF format 2 can decline an unavailable contour point" {
    var bytes: [34]u8 = .{0} ** 34;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 0);
    fixture.writeU16(&bytes, 8, 12);
    fixture.writeU16(&bytes, 12, 6);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 16, 12);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 1);
    fixture.writeU16(&bytes, 22, 2);
    fixture.writeU16(&bytes, 24, 1);
    fixture.writeU16(&bytes, 26, 4);
    fixture.writeU16(&bytes, 28, 2);
    fixture.writeU16(&bytes, 30, 999);

    const Context = struct {
        fn resolve(
            _: *const anyopaque,
            _: u16,
            _: u16,
            _: []const f32,
        ) gdef.LigatureCaretError!?f32 {
            return null;
        }
    };
    const context: u8 = 0;
    try std.testing.expectError(
        error.UnavailableContourPoint,
        gdef.readLigatureCarets(
            std.testing.allocator,
            &bytes,
            12,
            2,
            .{
                .contour_context = &context,
                .resolve_contour_point = Context.resolve,
            },
        ),
    );
}

test "GDEF ligature caret lazy reads revalidate borrowed bytes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildGdefLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const original = try font.ligatureCarets(allocator, 2, &.{});
    defer allocator.free(original);
    try std.testing.expectEqual(@as(f32, 300), original[0].position);

    const gdef_offset = try fixture.tableOffset(bytes, "GDEF");
    fixture.writeI16(bytes, gdef_offset + 30, 301);
    try std.testing.expectError(
        error.BadSfnt,
        font.ligatureCarets(allocator, 2, &.{}),
    );

    fixture.writeI16(bytes, gdef_offset + 30, 300);
    try fixture.updateTableChecksum(bytes, "GDEF");
    const restored = try font.ligatureCarets(allocator, 2, &.{});
    defer allocator.free(restored);
    try std.testing.expectEqual(@as(f32, 300), restored[0].position);
}
