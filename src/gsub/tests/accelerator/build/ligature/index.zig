//! LigatureSet exact-index contracts.

const std = @import("std");
const ligature = @import("../../../../accelerator/build/ligature/root.zig");
const model = @import("../../../../accelerator/model.zig");

test "ligature set index preserves hits misses and small fallback" {
    var sets: [ligature.index.min_sets_for_hash]model.LigatureSet = undefined;
    for (&sets, 0..) |*set, set_index| {
        // The slot table is power-of-two sized; this stride exercises linear
        // probing rather than only collision-free placement.
        set.* = .{
            .glyph = @intCast(5 + set_index * 16),
            .definition_start = set_index,
            .definition_len = 1,
        };
    }
    const slots = try ligature.index.build(&sets, std.testing.allocator);
    defer std.testing.allocator.free(slots);
    try std.testing.expect(slots.len >= sets.len * 2);
    for (sets) |expected| {
        try std.testing.expectEqual(
            expected,
            ligature.index.find(&sets, slots, expected.glyph) orelse
                return error.TestUnexpectedResult,
        );
    }
    try std.testing.expect(ligature.index.find(&sets, slots, 4) == null);

    const small_sets = sets[0 .. ligature.index.min_sets_for_hash - 1];
    const small_slots =
        try ligature.index.build(small_sets, std.testing.allocator);
    defer std.testing.allocator.free(small_slots);
    try std.testing.expectEqual(@as(usize, 0), small_slots.len);
    try std.testing.expectEqual(
        small_sets[3],
        ligature.index.find(
            small_sets,
            small_slots,
            small_sets[3].glyph,
        ) orelse return error.TestUnexpectedResult,
    );
}
