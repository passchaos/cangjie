//! TrueType embedded-hinting instances and raw pixel-outline ownership.
//!
//! Instances own PPEM, target, interpreter mode, variation coordinates, CVT,
//! storage, twilight points, and retained prep state. Glyph transactions keep
//! point-zone execution atomic and can be reconstructed directly as
//! pixel-space paths.

pub const types = @import("types.zig");
pub const type2 = @import("type2/root.zig");
pub const compound = @import("compound.zig");
pub const Instance = @import("instance.zig").Instance;
pub const outline = @import("outline.zig");
pub const PointTransaction = outline.Transaction;
pub const PixelOutline = outline.PixelOutline;
pub const Target = types.Target;
pub const Interpreter = types.Interpreter;
pub const Options = types.Options;
pub const Source = types.Source;
pub const Error = types.Error;

test {
    _ = @import("decode.zig");
    _ = @import("program.zig");
    _ = @import("stack.zig");
    _ = @import("types.zig");
    _ = @import("compound.zig");
    _ = @import("vm.zig");
    _ = @import("instance.zig");
    _ = @import("outline.zig");
    _ = @import("tricky.zig");
    _ = @import("glyph/compatibility_tests.zig");
    _ = type2;
}
