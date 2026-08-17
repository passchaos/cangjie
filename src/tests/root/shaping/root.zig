//! Shaping integration-test group.

test {
    _ = @import("fallback.zig");
    _ = @import("font_contracts.zig");
    _ = @import("gpos_and_aat.zig");
    _ = @import("gpos_attachments.zig");
    _ = @import("gsub.zig");
}
