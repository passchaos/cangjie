//! Layout integration-test group.

test {
    _ = @import("layout_interaction.zig");
    _ = @import("paragraph_reflow.zig");
    _ = @import("paragraph_retained.zig");
}
