//! Named variation instances revalidate fvar and caller-owned name metadata.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");
const support = @import("support.zig");

const Font = font_mod.Font;

test "variation instances report absence without fvar" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const instances = try font.variationInstances(allocator);
    defer font.freeVariationInstances(allocator, instances);
    try std.testing.expectEqual(@as(usize, 0), instances.len);
}

test "variation instances revalidate borrowed instance name references" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectTwoInstances(&font, allocator);

    const name_offset = try sfnt_fixture.tableOffset(bytes, "name");
    const subfamily = try sfnt_fixture.nameRecordOffset(
        bytes,
        name_offset,
        258,
    );
    sfnt_fixture.writeU16(bytes, subfamily + 6, 400);
    try support.expectInstancesError(&font, allocator, error.InvalidName);
}

test "variation instances revalidate borrowed PostScript name references" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectTwoInstances(&font, allocator);

    const name_offset = try sfnt_fixture.tableOffset(bytes, "name");
    const postscript = try sfnt_fixture.nameRecordOffset(
        bytes,
        name_offset,
        259,
    );
    sfnt_fixture.writeU16(bytes, postscript + 6, 400);
    try support.expectInstancesError(&font, allocator, error.InvalidName);
}

test "variation instances revalidate borrowed fvar checksum and metadata" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectTwoInstances(&font, allocator);

    const fvar_offset = try sfnt_fixture.tableOffset(bytes, "fvar");
    // Keep the first instance coordinate within the weight axis range while
    // changing caller-owned fvar metadata after parse.
    support.writeF16Dot16(bytes, fvar_offset + 60, 500.0);
    try support.expectInstancesError(&font, allocator, error.BadSfnt);
}

test "variation instances revalidate every instance record" {
    const allocator = std.testing.allocator;
    var bytes = twoInstanceFvar();
    const font = support.fvarFont(&bytes);

    const instances = try font.variationInstances(allocator);
    defer font.freeVariationInstances(allocator, instances);
    try std.testing.expectEqual(@as(usize, 2), instances.len);
    try std.testing.expectEqual(
        @as(?u16, null),
        instances[0].postscript_name_id,
    );
    try std.testing.expectEqual(
        @as(?u16, null),
        instances[1].postscript_name_id,
    );

    var reserved_flags = bytes;
    sfnt_fixture.writeU16(&reserved_flags, 46, 1);
    const reserved_flags_font = support.fvarFont(&reserved_flags);
    try support.expectInstancesError(
        &reserved_flags_font,
        allocator,
        error.BadSfnt,
    );

    var out_of_range = bytes;
    support.writeF16Dot16(&out_of_range, 48, 950.0);
    const out_of_range_font = support.fvarFont(&out_of_range);
    try support.expectInstancesError(
        &out_of_range_font,
        allocator,
        error.BadSfnt,
    );
}

fn twoInstanceFvar() [52]u8 {
    var bytes: [52]u8 = .{0} ** 52;
    support.writeFvarHeader(&bytes, 1);
    sfnt_fixture.writeU16(&bytes, 12, 2);
    sfnt_fixture.writeU16(&bytes, 14, 8);
    support.writeAxis(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);

    sfnt_fixture.writeU16(&bytes, 36, 258);
    sfnt_fixture.writeU16(&bytes, 38, 0);
    support.writeF16Dot16(&bytes, 40, 400.0);

    sfnt_fixture.writeU16(&bytes, 44, 260);
    sfnt_fixture.writeU16(&bytes, 46, 0);
    support.writeF16Dot16(&bytes, 48, 700.0);
    return bytes;
}

fn expectTwoInstances(font: *const Font, allocator: std.mem.Allocator) !void {
    const instances = try font.variationInstances(allocator);
    defer font.freeVariationInstances(allocator, instances);
    try std.testing.expectEqual(@as(usize, 2), instances.len);
    try std.testing.expectEqual(@as(u16, 258), instances[0].subfamily_name_id);
    try std.testing.expectEqual(
        @as(?u16, 259),
        instances[0].postscript_name_id,
    );
    try std.testing.expectEqual(@as(usize, 2), instances[0].coordinates.len);
}
