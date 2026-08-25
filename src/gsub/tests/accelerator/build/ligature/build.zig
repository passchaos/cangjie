//! LigatureSubst owned-model builder contracts.

const std = @import("std");
const ligature = @import("../../../../accelerator/build/ligature/root.zig");
const table = @import("../../../../table/root.zig");

test "ligature builder preserves authored definition preference" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 34);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);

    writeU16(&bytes, 8, 2);
    writeU16(&bytes, 10, 6);
    writeU16(&bytes, 12, 14);
    writeU16(&bytes, 14, 40);
    writeU16(&bytes, 16, 2);
    writeU16(&bytes, 18, 2);
    writeU16(&bytes, 22, 50);
    writeU16(&bytes, 24, 3);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 3);
    writeCoverage1(&bytes, 34, 1);

    const result = try ligature.build(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer {
        allocator.free(result.components);
        allocator.free(result.definitions);
        allocator.free(result.set_slots);
        allocator.free(result.sets);
    }

    try std.testing.expectEqual(@as(usize, 1), result.sets.len);
    try std.testing.expectEqual(@as(usize, 2), result.definitions.len);
    try std.testing.expectEqual(@as(u16, 40), result.definitions[0].ligature);
    try std.testing.expectEqualSlices(u16, &.{ 2, 2, 3 }, result.components);
    try std.testing.expect(result.first_component_digest.mayHave(1));
    try std.testing.expectEqual(
        result.sets[0],
        ligature.index.find(result.sets, result.set_slots, 1).?,
    );
}

test "required second range rejects stale bounds" {
    try std.testing.expectEqual(
        @as(usize, 0),
        ligature.requiredSecondComponents(.{
            .components = &.{ 1, 2 },
            .required_second_start = 2,
            .required_second_len = 1,
        }).len,
    );
}

test "required second digest survives compact component storage" {
    const digest = ligature.requiredSecondDigest(.{
        .components = &.{
            0x0001, 0, 0, 0,
            0x0004, 0, 0, 0,
            0x0001, 0, 0, 0,
        },
        .required_second_start = 0,
        .required_second_len = 0x800c,
    }).?;
    try std.testing.expect(digest.mayHave(2));
    try std.testing.expect(!digest.mayHave(3));
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
