//! TrueType embedded-hinting size instances.
//!
//! This first slice executes font- and size-level programs. Glyph point-zone
//! execution is intentionally not exposed until raw glyf point ownership is
//! connected to the same VM. Instances currently represent the default
//! variation location and do not yet apply cvar deltas.

pub const types = @import("types.zig");
pub const Instance = @import("instance.zig").Instance;
pub const Target = types.Target;
pub const Source = types.Source;
pub const Error = types.Error;

test {
    _ = @import("decode.zig");
    _ = @import("program.zig");
    _ = @import("stack.zig");
    _ = @import("types.zig");
    _ = @import("vm.zig");
    _ = @import("instance.zig");
}
