//! Vertical paragraph integration-test group.

test {
    _ = @import("vertical_paragraph/single.zig");
    _ = @import("vertical_paragraph/columns.zig");
    _ = @import("vertical_paragraph/retained.zig");
    _ = @import("vertical_paragraph/interaction.zig");
    _ = @import("vertical_paragraph/bidi.zig");
    _ = @import("vertical_paragraph/bidi_integration.zig");
    _ = @import("vertical_paragraph/bidi_atoms.zig");
    _ = @import("vertical_paragraph/styled.zig");
    _ = @import("vertical_paragraph/wrapping.zig");
    _ = @import("vertical_paragraph/wrapping_policy.zig");
    _ = @import("vertical_paragraph/ranged_policy.zig");
    _ = @import("vertical_paragraph/dictionary.zig");
    _ = @import("vertical_paragraph/dictionary_integration.zig");
    _ = @import("vertical_paragraph/soft_hyphen.zig");
    _ = @import("vertical_paragraph/soft_hyphen_integration.zig");
    _ = @import("vertical_paragraph/automatic_hyphen.zig");
    _ = @import("vertical_paragraph/automatic_hyphen_integration.zig");
    _ = @import("vertical_paragraph/balanced.zig");
    _ = @import("vertical_paragraph/balanced_integration.zig");
    _ = @import("vertical_paragraph/whitespace.zig");
    _ = @import("vertical_paragraph/flow_spacing.zig");
    _ = @import("vertical_paragraph/negative_spacing.zig");
    _ = @import("vertical_paragraph/negative_spacing_integration.zig");
    _ = @import("vertical_paragraph/tabs.zig");
    _ = @import("vertical_paragraph/tab_integration.zig");
    _ = @import("vertical_paragraph/inline_objects.zig");
    _ = @import("vertical_paragraph/inline_object_integration.zig");
    _ = @import("vertical_paragraph/alignment.zig");
    _ = @import("vertical_paragraph/alignment_integration.zig");
    _ = @import("vertical_paragraph/out_of_flow.zig");
    _ = @import("vertical_paragraph/out_of_flow_integration.zig");
    _ = @import("vertical_paragraph/max_lines.zig");
    _ = @import("vertical_paragraph/max_lines_integration.zig");
    _ = @import("vertical_paragraph/ellipsis.zig");
    _ = @import("vertical_paragraph/ellipsis_integration.zig");
    _ = @import("vertical_paragraph/custom_out_of_flow.zig");
}
