//! Nested PosLookupRecord test group.

test {
    _ = @import("basic.zig");
    _ = @import("extension/root.zig");
    _ = @import("flags.zig");
    _ = @import("targets/root.zig");
}
