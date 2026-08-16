//! cmap module boundary and source-level public type contracts.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const cmap = @import("../../tables/cmap/root.zig");

test "public charmap metadata is the concrete cmap module value type" {
    try std.testing.expect(font_mod.CharmapInfo == cmap.Info);

    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();

    const charmaps = try font.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expectEqual(@as(usize, 1), charmaps.len);
    try std.testing.expectEqual(@as(u16, 3), charmaps[0].platform_id);
    try std.testing.expectEqual(@as(u16, 1), charmaps[0].encoding_id);
    try std.testing.expectEqual(@as(u16, 4), charmaps[0].format);
}
