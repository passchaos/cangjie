//! Public `head` metadata and parse-time invariant integration tests.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "head metadata exposes concrete values and revalidates borrowed bytes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const header = try font.headInfo();
    try std.testing.expectEqual(@as(u32, 0x00010000), header.table_version);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        header.font_revision,
        0.001,
    );
    try std.testing.expectEqual(@as(u16, 1000), header.units_per_em);
    try std.testing.expectEqual(@as(u16, 8), header.lowest_rec_ppem);
    try std.testing.expectEqual(@as(i16, 0), header.index_to_loc_format);

    const head_offset = try sfnt_fixture.tableOffset(bytes, "head");
    // Changing only the fixed-point revision leaves the head grammar valid.
    // The lazy API must still reject bytes not authenticated during parse.
    bytes[head_offset + 7] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.headInfo());
}

test "head table invariants are validated at parse time" {
    const allocator = std.testing.allocator;

    inline for (.{
        .{ .offset = 0, .value = @as(u32, 0x00020000) },
        .{ .offset = 12, .value = @as(u32, 0) },
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfnt_fixture.tableOffset(bytes, "head");
        sfnt_fixture.writeU32(bytes, head_offset + case.offset, case.value);
        try sfnt_fixture.updateTableChecksum(bytes, "head");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    inline for (.{ @as(u16, 15), @as(u16, 16385) }) |units_per_em| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfnt_fixture.tableOffset(bytes, "head");
        sfnt_fixture.writeU16(bytes, head_offset + 18, units_per_em);
        try sfnt_fixture.updateTableChecksum(bytes, "head");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfnt_fixture.tableOffset(bytes, "head");
        sfnt_fixture.writeI16(bytes, head_offset + 50, 2);
        try sfnt_fixture.updateTableChecksum(bytes, "head");
        try std.testing.expectError(
            error.InvalidLoca,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfnt_fixture.tableOffset(bytes, "head");
        sfnt_fixture.writeI16(bytes, head_offset + 36, 701);
        try sfnt_fixture.updateTableChecksum(bytes, "head");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    inline for (.{
        .{ .field_offset = @as(usize, 44), .value = @as(i16, 0x0080) },
        .{ .field_offset = @as(usize, 46), .value = @as(i16, 0) },
        .{ .field_offset = @as(usize, 48), .value = @as(i16, 3) },
        .{ .field_offset = @as(usize, 52), .value = @as(i16, 1) },
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfnt_fixture.tableOffset(bytes, "head");
        sfnt_fixture.writeI16(
            bytes,
            head_offset + case.field_offset,
            case.value,
        );
        try sfnt_fixture.updateTableChecksum(bytes, "head");
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }
}

test "CFF ignores the glyf-only indexToLocFormat field" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(bytes);

    const head_offset = try sfnt_fixture.tableOffset(bytes, "head");
    sfnt_fixture.writeI16(bytes, head_offset + 50, 2);
    try sfnt_fixture.updateTableChecksum(bytes, "head");

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(
        @as(i16, 2),
        (try font.headInfo()).index_to_loc_format,
    );
}
