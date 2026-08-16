//! Chaining coverage execution test group.

test {
    _ = @import("accelerated.zig");
    _ = @import("fast_single.zig");
    _ = @import("matching.zig");
}
