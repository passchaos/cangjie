//! Layout integration-test group.

test {
    _ = @import("inline_objects.zig");
    _ = @import("line_regions.zig");
    _ = @import("layout_interaction.zig");
    _ = @import("out_of_flow.zig");
    _ = @import("paragraph_breaker.zig");
    _ = @import("paragraph_line_break_policy.zig");
    _ = @import("paragraph_reflow.zig");
    _ = @import("paragraph_exclusions.zig");
    _ = @import("paragraph_retained.zig");
    _ = @import("paragraph_retained/direct_bidi_l2.zig");
    _ = @import("paragraph_styled_retained.zig");
    _ = @import("paragraph_tab_alignment.zig");
    _ = @import("paragraph_tabs.zig");
    _ = @import("styled_bidi.zig");
    _ = @import("text_geometry.zig");
    _ = @import("text_geometry_interaction.zig");
    _ = @import("vertical_paragraph.zig");
}
