//! Vertical paragraph integration-test group.

test {
    _ = @import("vertical_paragraph/single.zig");
    _ = @import("vertical_paragraph/columns.zig");
    _ = @import("vertical_paragraph/retained.zig");
    _ = @import("vertical_paragraph/interaction.zig");
    _ = @import("vertical_paragraph/styled.zig");
    _ = @import("vertical_paragraph/wrapping.zig");
    _ = @import("vertical_paragraph/wrapping_policy.zig");
    _ = @import("vertical_paragraph/ranged_policy.zig");
    _ = @import("vertical_paragraph/whitespace.zig");
    _ = @import("vertical_paragraph/flow_spacing.zig");
    _ = @import("vertical_paragraph/tabs.zig");
    _ = @import("vertical_paragraph/tab_integration.zig");
    _ = @import("vertical_paragraph/inline_objects.zig");
    _ = @import("vertical_paragraph/inline_object_integration.zig");
    _ = @import("vertical_paragraph/alignment.zig");
    _ = @import("vertical_paragraph/alignment_integration.zig");
    _ = @import("vertical_paragraph/out_of_flow.zig");
    _ = @import("vertical_paragraph/out_of_flow_integration.zig");
}
