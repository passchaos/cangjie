//! Font integration-test group.

test {
    _ = @import("../../../font/tests/cff.zig");
    _ = @import("bitmap_and_cmap_tables.zig");
    _ = @import("color/root.zig");
    _ = @import("containers_and_caches.zig");
    _ = @import("font_database.zig");
    _ = @import("font_metadata_tables.zig");
    _ = @import("font_validation.zig");
    _ = @import("math_aat_variation_tables.zig");
    _ = @import("../../../font/tests/bitmap/root.zig");
    _ = @import("../../../font/tests/cmap/root.zig");
    _ = @import("../../../font/tests/core/root.zig");
    _ = @import("../../../font/tests/kerning/root.zig");
    _ = @import("../../../font/tests/layout/root.zig");
    _ = @import("../../../font/tests/metadata/root.zig");
    _ = @import("../../../font/tests/sfnt/root.zig");
    _ = @import("../../../font/tests/system.zig");
    _ = @import("../../../font/tests/truetype/root.zig");
    _ = @import("../../../font/tests/variations/root.zig");
}
