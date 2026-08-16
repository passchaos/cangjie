//! GSUB accelerator builders grouped by substitution kind.

pub const context_coverage = @import("context_coverage.zig");
pub const chaining_coverage = @import("chaining_coverage/root.zig");
pub const class_context = @import("class_context/root.zig");
pub const ligature = @import("ligature/root.zig");
pub const multiple = @import("multiple.zig");
pub const reverse = @import("reverse.zig");
pub const single = @import("single.zig");
