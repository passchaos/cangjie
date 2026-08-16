//! Run-specific GSUB feature-policy and canonicalization contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const unicode = @import("../../../unicode.zig");

test "run selection enables only shaping defaults" {
    try std.testing.expect(
        feature.run_selection.defaultEnabled(unicode.tag("liga")),
    );
    try std.testing.expect(
        feature.run_selection.defaultEnabled(unicode.tag("ccmp")),
    );
    try std.testing.expect(
        !feature.run_selection.defaultEnabled(unicode.tag("ordn")),
    );
    try std.testing.expect(
        !feature.run_selection.defaultEnabled(unicode.tag("sups")),
    );
}

test "run selection applies direction vertical and explicit policy" {
    try std.testing.expect(feature.run_selection.enabled(
        unicode.tag("rtlm"),
        .{ .text_direction = .rtl },
    ));
    try std.testing.expect(!feature.run_selection.enabled(
        unicode.tag("rtlm"),
        .{ .text_direction = .ltr },
    ));
    try std.testing.expect(feature.run_selection.enabled(
        unicode.tag("vert"),
        .{ .vertical = true },
    ));
    try std.testing.expect(!feature.run_selection.enabled(
        unicode.tag("liga"),
        .{
            .features = &.{
                .{ .tag = unicode.tag("liga"), .enabled = false },
            },
        },
    ));
}

test "run selection preserves explicit and random feature values" {
    try std.testing.expectEqual(
        @as(u32, 7),
        feature.run_selection.featureValue(
            unicode.tag("salt"),
            .{
                .features = &.{
                    .{
                        .tag = unicode.tag("salt"),
                        .enabled = true,
                        .value = 7,
                    },
                },
            },
        ),
    );
    try std.testing.expectEqual(
        feature.random_value,
        feature.run_selection.featureValue(unicode.tag("rand"), .{}),
    );
}

test "run selection sorts and deduplicates lookup indexes" {
    var lookups = std.ArrayList(u16).empty;
    defer lookups.deinit(std.testing.allocator);
    try lookups.appendSlice(
        std.testing.allocator,
        &.{ 3, 1, 3, 2, 1 },
    );

    feature.run_selection.sortUniqueIndices(&lookups);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, lookups.items);
}
