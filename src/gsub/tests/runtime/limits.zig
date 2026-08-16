//! GSUB run-budget scaling and attachment contracts.

const std = @import("std");
const runtime = @import("../../runtime/root.zig");

test "GSUB run limits preserve minimums and scale large runs" {
    const empty = try runtime.Limits.init(0);
    try std.testing.expectEqual(@as(usize, 65536), empty.operations_left);
    try std.testing.expectEqual(@as(usize, 65536), empty.max_glyph_count);

    const large = try runtime.Limits.init(300);
    try std.testing.expectEqual(@as(usize, 300 * 4096), large.operations_left);
    try std.testing.expectEqual(@as(usize, 300 * 256), large.max_glyph_count);
}

test "GSUB run limits reject scaling overflow and attach to concrete options" {
    try std.testing.expectError(
        error.ShapingLimitExceeded,
        runtime.Limits.init(std.math.maxInt(usize)),
    );

    var limits = try runtime.Limits.init(1);
    var options = struct {
        operations_left: ?*usize = null,
        max_glyph_count: ?usize = null,
    }{};
    limits.applyTo(&options);

    try std.testing.expect(options.operations_left == &limits.operations_left);
    try std.testing.expectEqual(
        @as(?usize, limits.max_glyph_count),
        options.max_glyph_count,
    );
}
