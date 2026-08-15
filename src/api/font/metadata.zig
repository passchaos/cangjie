//! Typed records returned by font inspection APIs, grouped by responsibility.

pub const core = @import("metadata/core/root.zig");
pub const metrics = @import("metadata/metrics/root.zig");
pub const variations = @import("metadata/variations/root.zig");
pub const color = @import("metadata/color/root.zig");
pub const layout = @import("metadata/layout/root.zig");
pub const math = @import("metadata/math/root.zig");
pub const incremental = @import("metadata/incremental/root.zig");
