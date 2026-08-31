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

test "GSUB mutation and nested budgets fail without consuming state" {
    var operations_left: usize = 2;
    const options = runtime.Options{
        .operations_left = &operations_left,
        .max_glyph_count = 8,
    };

    try runtime.limits.consumeNested(options);
    try std.testing.expectEqual(@as(usize, 1), operations_left);
    try runtime.limits.consumeMutation(options, 3, 1, 4);
    try std.testing.expectEqual(@as(usize, 0), operations_left);

    try std.testing.expectError(
        error.ShapingLimitExceeded,
        runtime.limits.consumeMutation(options, 6, 1, 4),
    );
    try std.testing.expectEqual(@as(usize, 0), operations_left);
    try std.testing.expectError(
        error.ShapingLimitExceeded,
        runtime.limits.consumeNested(options),
    );
}

test "GSUB mutation budget rejects invalid removal and count overflow" {
    var operations_left: usize = 1;
    const options = runtime.Options{
        .operations_left = &operations_left,
        .max_glyph_count = std.math.maxInt(usize),
    };
    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.limits.consumeMutation(options, 2, 3, 0),
    );
    try std.testing.expectEqual(@as(usize, 1), operations_left);
    try std.testing.expectError(
        error.ShapingLimitExceeded,
        runtime.limits.consumeMutation(
            options,
            std.math.maxInt(usize),
            0,
            1,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), operations_left);
}

test "GSUB contextual nesting accepts sixteen edges and rejects the next" {
    var operations_left: usize = 3;
    const boundary = runtime.Options{
        .context_depth = runtime.limits.max_context_depth - 1,
        .operations_left = &operations_left,
    };
    const nested = try runtime.limits.enterContext(boundary);
    try std.testing.expectEqual(
        runtime.limits.max_context_depth,
        nested.context_depth,
    );

    try std.testing.expectError(
        error.ShapingLimitExceeded,
        runtime.limits.enterContext(nested),
    );
    // Depth is checked before the separate operation charge at the dispatcher
    // boundary, so rejecting recursion cannot consume the caller's budget.
    try std.testing.expectEqual(@as(usize, 3), operations_left);
}
