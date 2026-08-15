//! Domain-grouped package integration tests.

test {
    _ = @import("font/root.zig");
    _ = @import("text/root.zig");
    _ = @import("render/root.zig");
    _ = @import("layout/root.zig");
    _ = @import("shaping/root.zig");
}
