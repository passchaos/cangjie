//! PairPos runtime test group.

test {
    _ = @import("accelerated.zig");
    _ = @import("accelerator_direct.zig");
    _ = @import("accelerator_extension.zig");
    _ = @import("generic.zig");
    _ = @import("semantics.zig");
}
