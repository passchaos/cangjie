//! GSUB feature-model value and ownership contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const unicode = @import("../../../unicode.zig");

test "source-scoped feature masks are marked, unique, and bounded" {
    const rphf = feature.sourceMaskForTag(unicode.tag("rphf")).?;
    const half = feature.sourceMaskForTag(unicode.tag("half")).?;
    const cfar = feature.sourceMaskForTag(unicode.tag("cfar")).?;

    try std.testing.expect((rphf & feature.source_mask_marker) != 0);
    try std.testing.expect((half & feature.source_mask_marker) != 0);
    try std.testing.expect((cfar & feature.source_mask_marker) != 0);
    try std.testing.expect(rphf != half);
    try std.testing.expect(half != cfar);
    try std.testing.expectEqual(
        @as(?u32, null),
        feature.sourceMaskForTag(unicode.tag("salt")),
    );
}

test "feature plans own and release their lookup storage" {
    const allocator = std.testing.allocator;

    const entries = try allocator.alloc(feature.LookupPlanEntry, 1);
    entries[0] = .{
        .application = .{ .tag = unicode.tag("liga") },
        .lookups = try allocator.dupe(u16, &.{ 1, 3 }),
        .lookup_offsets = try allocator.dupe(usize, &.{ 20, 44 }),
    };
    var plan = feature.LookupPlan{ .entries = entries };
    plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), plan.entries.len);

    var merged = feature.MergedLookupPlan{
        .lookups = try allocator.dupe(feature.MergedLookup, &.{
            .{ .lookup = 2, .source_mask = feature.source_mask_marker | 1 },
        }),
        .lookup_offsets = try allocator.dupe(usize, &.{32}),
    };
    merged.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), merged.lookups.len);
    try std.testing.expectEqual(@as(usize, 0), merged.lookup_offsets.len);
}
