//! Shared runtime decoding context.

const variation = @import("../variation/root.zig");

pub const Context = struct {
    normalized_coords: []const f32,
    variation: ?variation.Context,
};
