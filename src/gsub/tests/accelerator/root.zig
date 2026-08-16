//! GSUB accelerator-model test group.

test {
    _ = @import("build/root.zig");
    _ = @import("feature_index.zig");
    _ = @import("index/root.zig");
    _ = @import("model.zig");
    _ = @import("ownership.zig");
}
