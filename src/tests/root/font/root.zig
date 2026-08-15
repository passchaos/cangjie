//! Font integration-test group.

test {
    _ = @import("bitmap_and_cmap_tables.zig");
    _ = @import("containers_and_caches.zig");
    _ = @import("font_database.zig");
    _ = @import("font_metadata_tables.zig");
    _ = @import("font_validation.zig");
    _ = @import("math_aat_variation_tables.zig");
}
