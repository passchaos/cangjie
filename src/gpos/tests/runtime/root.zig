//! GPOS runtime test group.

test {
    _ = @import("dispatch.zig");
    _ = @import("lookup/root.zig");
    _ = @import("matching.zig");
    _ = @import("output/root.zig");
}
