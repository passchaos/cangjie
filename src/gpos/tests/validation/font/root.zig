//! Complete GPOS font-table validation test group.

test {
    _ = @import("activation.zig");
    _ = @import("lookup_children.zig");
    _ = @import("top_level.zig");
}
