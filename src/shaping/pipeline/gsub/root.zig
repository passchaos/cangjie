//! Shared GSUB pipeline infrastructure.

pub const executor = @import("executor.zig");
pub const features = @import("features.zig");
pub const fraction = @import("fraction.zig");
pub const hangul = @import("hangul.zig");
pub const shapers = struct {
    pub const arabic = @import("shapers/arabic/root.zig");
};
