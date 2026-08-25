//! TrueType outline APIs revalidate caller-owned loca and glyf bytes.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;
const Face = @import("../../face/root.zig").Face;

test "glyph outline API revalidates borrowed loca and glyf bytes" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const loca_offset = try sfnt_fixture.tableOffset(bytes, "loca");
        // Glyph 0's short loca entry now decreases before glyph 1.
        sfnt_fixture.writeU16(bytes, loca_offset, 7);
        try expectOutlineError(&font, allocator, error.BadSfnt);
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const glyf_offset = try sfnt_fixture.tableOffset(bytes, "glyf");
        // Glyph 0 is not requested. The whole borrowed table must still be
        // authenticated before returning glyph 1 bounds or outline data.
        sfnt_fixture.writeI16(bytes, glyf_offset, 1);
        try expectOutlineError(&font, allocator, error.BadSfnt);
    }
}

test "glyph outline API revalidates borrowed glyf checksum" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var outline = try font.glyphOutline(allocator, 1);
    outline.deinit();

    const glyf_offset = try sfnt_fixture.tableOffset(bytes, "glyf");
    const glyph_one = glyf_offset + 12;
    // Keep the glyph grammar valid while changing its borrowed bounding box.
    // Lazy outline loading must reject bytes no longer covered by the checksum
    // accepted during Font.parse.
    sfnt_fixture.writeI16(bytes, glyph_one + 6, 600);
    try expectOutlineError(&font, allocator, error.BadSfnt);
}

test "glyph outline session matches strict output and documents trust boundary" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var face = try Face.parse(allocator, bytes);
    defer face.deinit();
    const glyphs = face.glyphs();
    const session = glyphs.session();

    var strict = try glyphs.outline(allocator, 2);
    defer strict.deinit();
    var trusted = try session.outline(allocator, 2);
    defer trusted.deinit();
    try expectSameOutline(strict, trusted);

    var strict_varied = try glyphs.outlineAt(allocator, 2, &.{1});
    defer strict_varied.deinit();
    var trusted_varied = try session.outlineAt(allocator, 2, &.{1});
    defer trusted_varied.deinit();
    try expectSameOutline(strict_varied, trusted_varied);

    const glyf_offset = try sfnt_fixture.tableOffset(bytes, "glyf");
    // Mutate an unrelated borrowed glyph. Strict reads authenticate the entire
    // table and reject it; the explicitly trusted session keeps serving the
    // requested still-valid glyph from the parse-time structural proof.
    sfnt_fixture.writeI16(bytes, glyf_offset, 1);
    try std.testing.expectError(error.BadSfnt, glyphs.outline(allocator, 2));
    var after_mutation = try session.outline(allocator, 2);
    defer after_mutation.deinit();
    try expectSameOutline(trusted, after_mutation);
}

test "glyph outline session reuses caller-owned command and compound scratch" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var face = try Face.parse(allocator, bytes);
    defer face.deinit();
    const session = face.glyphs().session();
    var buffer = @import("../../../glyph.zig").GlyphOutlineBuffer.init(allocator);
    defer buffer.deinit();

    var owning = try session.outline(allocator, 2);
    defer owning.deinit();
    const first = try session.outlineInto(&buffer, 2);
    try expectSameOutline(owning, first.*);
    const command_storage = first.commands.items.ptr;
    const command_capacity = first.commands.capacity;

    // A second decode of the same compound glyph must reuse the allocation
    // retained by the caller-owned buffer rather than transferring ownership
    // to the borrowed result.
    const second = try session.outlineInto(&buffer, 2);
    try expectSameOutline(owning, second.*);
    try std.testing.expectEqual(command_storage, second.commands.items.ptr);
    try std.testing.expectEqual(command_capacity, second.commands.capacity);

    // Errors invalidate the borrowed result but retain its storage for a later
    // successful call. This makes recovery deterministic and leak-free.
    try std.testing.expectError(
        error.InvalidGlyph,
        session.outlineInto(&buffer, face.properties().glyph_count),
    );
    try std.testing.expectEqual(@as(usize, 0), buffer.current().commands.items.len);
    const recovered = try session.outlineInto(&buffer, 2);
    try expectSameOutline(owning, recovered.*);
    try std.testing.expectEqual(command_storage, recovered.commands.items.ptr);
}

fn expectSameOutline(
    expected: @import("../../../glyph.zig").GlyphOutline,
    actual: @import("../../../glyph.zig").GlyphOutline,
) !void {
    try std.testing.expectEqual(expected.glyph_id, actual.glyph_id);
    try std.testing.expectEqual(expected.bounds, actual.bounds);
    try std.testing.expectEqual(expected.advance_width, actual.advance_width);
    try std.testing.expectEqual(
        expected.left_side_bearing,
        actual.left_side_bearing,
    );
    try std.testing.expectEqualSlices(
        @import("../../../glyph.zig").PathCommand,
        expected.commands.items,
        actual.commands.items,
    );
}

fn expectOutlineError(
    font: *const Font,
    allocator: std.mem.Allocator,
    expected: anyerror,
) !void {
    try std.testing.expectError(expected, font.glyphBounds(1));
    try std.testing.expectError(expected, font.glyphOutline(allocator, 1));
}
