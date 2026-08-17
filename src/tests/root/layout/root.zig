//! Layout integration-test group.

test {
    _ = @import("inline_objects.zig");
    _ = @import("layout_interaction.zig");
    _ = @import("paragraph_reflow.zig");
    _ = @import("paragraph_retained.zig");
    _ = @import("text_geometry.zig");
    _ = @import("text_geometry_interaction.zig");
}
