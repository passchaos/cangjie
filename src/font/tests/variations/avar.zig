//! avar coordinate mapping validates caller indexes, inputs, and segment maps.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");
const support = @import("support.zig");

const Font = font_mod.Font;

test "avar public mapping rejects out-of-range axis indexes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try expectMapped(&font, 0, 0.5, 0.25);
    try expectMapped(&font, 1, 0.5, 0.5);
    try std.testing.expectError(
        error.BadSfnt,
        font.mapVariationCoordinate(2, 0.5),
    );
}

test "avar public mapping revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectMapped(&font, 0, 0.5, 0.25);

    const avar_offset = try sfnt_fixture.tableOffset(bytes, "avar");
    // Keep the segment ordered and anchored while changing its midpoint. The
    // borrowed bytes no longer match the checksum authenticated by Font.parse.
    support.writeF2Dot14(bytes, avar_offset + 20, 0.375);
    try std.testing.expectError(
        error.BadSfnt,
        font.mapVariationCoordinate(0, 0.5),
    );
}

test "avar public mapping validates normalized coordinates" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectMapped(&font, 0, -1.0, -1.0);
    try expectMapped(&font, 0, 1.0, 1.0);

    for ([_]f32{
        1.0001,
        -1.0001,
        std.math.inf(f32),
        std.math.nan(f32),
    }) |coordinate| {
        try std.testing.expectError(
            error.BadSfnt,
            font.mapVariationCoordinate(0, coordinate),
        );
    }
}

test "avar public mapping revalidates axis indexes and segment anchors" {
    var header: [64]u8 = .{0} ** 64;
    support.writeFvarHeader(&header, 2);
    support.writeAxis(&header, 16, "wght", 100.0, 400.0, 900.0, 256);
    support.writeAxis(&header, 36, "wdth", 50.0, 100.0, 200.0, 257);

    const avar_offset = 56;
    writeAvarHeader(&header, avar_offset, 0);

    var no_fvar_axis_maps = header;
    sfnt_fixture.writeU16(&no_fvar_axis_maps, avar_offset + 6, 1);
    const no_fvar = support.avarFont(no_fvar_axis_maps[avar_offset..]);
    try std.testing.expectError(
        error.BadSfnt,
        no_fvar.mapVariationCoordinate(0, 0.25),
    );

    var malformed_map: [92]u8 = .{0} ** 92;
    @memcpy(malformed_map[0..header.len], &header);
    writeAvarHeader(&malformed_map, avar_offset, 2);
    writeSegmentMap(
        &malformed_map,
        avar_offset + 8,
        0.25,
    );
    writeSegmentMap(
        &malformed_map,
        avar_offset + 22,
        0.0,
    );

    const font = support.fvarAvarFont(&malformed_map, avar_offset);
    // Every call reparses all borrowed maps, including maps after the requested
    // axis, so a malformed first map cannot be hidden by requesting axis 1.
    try std.testing.expectError(
        error.BadSfnt,
        font.mapVariationCoordinate(1, 0.25),
    );
}

fn writeAvarHeader(bytes: []u8, offset: usize, axis_count: u16) void {
    sfnt_fixture.writeU16(bytes, offset, 1);
    sfnt_fixture.writeU16(bytes, offset + 2, 0);
    sfnt_fixture.writeU16(bytes, offset + 4, 0);
    sfnt_fixture.writeU16(bytes, offset + 6, axis_count);
}

fn writeSegmentMap(bytes: []u8, offset: usize, mapped_zero: f32) void {
    sfnt_fixture.writeU16(bytes, offset, 3);
    support.writeF2Dot14(bytes, offset + 2, -1.0);
    support.writeF2Dot14(bytes, offset + 4, -1.0);
    support.writeF2Dot14(bytes, offset + 6, 0.0);
    support.writeF2Dot14(bytes, offset + 8, mapped_zero);
    support.writeF2Dot14(bytes, offset + 10, 1.0);
    support.writeF2Dot14(bytes, offset + 12, 1.0);
}

fn expectMapped(
    font: *const Font,
    axis_index: usize,
    input: f32,
    expected: f32,
) !void {
    try std.testing.expectApproxEqAbs(
        expected,
        try font.mapVariationCoordinate(axis_index, input),
        0.0001,
    );
}
