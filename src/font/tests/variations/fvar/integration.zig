//! Parse-time fvar/name and adjacent STAT name-reference integration.

const std = @import("std");
const font_mod = @import("../../../../font.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "fvar and STAT user-facing name IDs resolve through name table" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const fvar_offset = try fixture.tableOffset(bytes, "fvar");
        // No name record labels the weight axis with this NameID.
        fixture.writeU16(bytes, fvar_offset + 34, 400);
        try std.testing.expectError(
            error.InvalidName,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);
        const stat_offset = try fixture.tableOffset(bytes, "STAT");
        fixture.writeU16(bytes, stat_offset + 44, 400); // AxisValue NameID.
        try fixture.updateTableChecksum(bytes, "STAT");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidName,
            font.statAxisValues(allocator),
        );
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        try setTableTag(bytes, "name", "namx");
        try std.testing.expectError(
            error.InvalidName,
            Font.parse(allocator, bytes),
        );
    }
}

fn setTableTag(
    bytes: []u8,
    comptime old_tag: *const [4]u8,
    comptime new_tag: *const [4]u8,
) error{BadSfnt}!void {
    if (bytes.len < 12) return error.BadSfnt;
    const table_count = std.mem.readInt(u16, bytes[4..6], .big);
    if (table_count > (bytes.len - 12) / 16) return error.BadSfnt;
    for (0..table_count) |index| {
        const record = 12 + index * 16;
        if (!std.mem.eql(u8, bytes[record..][0..4], old_tag)) continue;
        @memcpy(bytes[record..][0..4], new_tag);
        return;
    }
    return error.BadSfnt;
}
