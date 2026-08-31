//! GPOS contextual recursion limit contracts.

const std = @import("std");
const runtime = @import("../../runtime/root.zig");

test "GPOS contextual nesting accepts sixteen edges and rejects the next" {
    const boundary = runtime.Options{
        .context_depth = runtime.limits.max_context_depth - 1,
    };
    const nested = try runtime.limits.enterContext(boundary);
    try std.testing.expectEqual(
        runtime.limits.max_context_depth,
        nested.context_depth,
    );
    try std.testing.expectError(
        error.UnsupportedGpos,
        runtime.limits.enterContext(nested),
    );
}

test "GPOS contextual nesting rejects hostile depth without overflow" {
    try std.testing.expectError(
        error.UnsupportedGpos,
        runtime.limits.enterContext(.{
            .context_depth = std.math.maxInt(usize),
        }),
    );
}
