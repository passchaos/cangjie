//! Vertical paragraph integration-test group.

test {
    _ = @import("vertical_paragraph/single.zig");
    _ = @import("vertical_paragraph/columns.zig");
    _ = @import("vertical_paragraph/retained.zig");
    _ = @import("vertical_paragraph/interaction.zig");
    _ = @import("vertical_paragraph/styled.zig");
    _ = @import("vertical_paragraph/wrapping.zig");
    _ = @import("vertical_paragraph/wrapping_policy.zig");
}
