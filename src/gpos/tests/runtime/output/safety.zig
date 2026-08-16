//! GPOS unsafe-to-break output contracts.

const std = @import("std");
const output = @import("../../../runtime/output/root.zig");
const cluster_safety = @import("../../../../shaping/cluster_safety.zig");
const run_metadata = @import("../../../../shaping/run_metadata.zig");

test "pair output marks only effective or semantic positioning" {
    var unsafe_glyphs: run_metadata.UnsafeGlyphs = .{};
    const options = output.safety.Options{ .unsafe_glyphs = &unsafe_glyphs };

    try output.safety.markPairApplication(
        std.testing.allocator,
        &options,
        3,
        0,
        1,
        .{ .index = 0 },
        .{ .index = 1 },
        false,
    );
    try std.testing.expectEqual(@as(u64, 0), unsafe_glyphs.inline_mask);

    // A second ValueRecord consumes the pair even when both records are
    // numerically empty, so the following boundary is unsafe as well.
    try output.safety.markPairApplication(
        std.testing.allocator,
        &options,
        3,
        0,
        1,
        .{ .index = 0 },
        .{ .index = 1 },
        true,
    );
    try std.testing.expect(unsafe_glyphs.isUnsafeBefore(1));
    try std.testing.expect(unsafe_glyphs.isUnsafeBefore(2));
}

test "context output spans all matched regions in inline glyph space" {
    var unsafe_glyphs: run_metadata.UnsafeGlyphs = .{};
    const options = output.safety.Options{ .unsafe_glyphs = &unsafe_glyphs };

    try output.safety.markContext(
        std.testing.allocator,
        &options,
        &.{ 0, 2 },
    );
    try std.testing.expect(unsafe_glyphs.isUnsafeBefore(1));
    try std.testing.expect(unsafe_glyphs.isUnsafeBefore(2));

    unsafe_glyphs = .{};
    try output.safety.markChainingContext(
        std.testing.allocator,
        &options,
        &.{0},
        &.{2},
        &.{4},
    );
    for (1..5) |boundary| {
        try std.testing.expect(unsafe_glyphs.isUnsafeBefore(boundary));
    }
}

test "long output relationships fall back to stable source boundaries" {
    const allocator = std.testing.allocator;
    var unsafe_glyphs: run_metadata.UnsafeGlyphs = .{};
    var boundaries: cluster_safety.SourceBoundaries = .{};
    defer boundaries.deinit(allocator);

    var source_starts: [65]usize = undefined;
    var sources: [65]usize = undefined;
    for (0..65) |index| {
        source_starts[index] = index;
        sources[index] = index;
    }
    boundaries.reset(0, 65, &source_starts);
    const metadata = run_metadata.Positioning{
        .glyph_source_indices = &sources,
        .source_boundaries = &boundaries,
    };
    const options = output.safety.Options{
        .unsafe_glyphs = &unsafe_glyphs,
        .run_metadata = &metadata,
    };

    try output.safety.markPair(allocator, &options, 0, 64);
    // The inline glyph mask cannot represent this span, but the immutable
    // source-byte recorder covers both the early and final boundaries.
    try std.testing.expectEqual(@as(u64, 0), unsafe_glyphs.inline_mask);
    try std.testing.expect(boundaries.isUnsafeBeforeByte(1));
    try std.testing.expect(boundaries.isUnsafeBeforeByte(64));
}
