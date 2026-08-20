//! PostScript Type2 hint-program model.

pub const program = @import("program.zig");
pub const fixed = @import("fixed.zig");
pub const params = @import("params.zig");
pub const map = @import("map.zig");
pub const Instance = @import("instance.zig").Instance;
pub const Error = @import("instance.zig").Error;
pub const Axis = program.Axis;
pub const Mask = program.Mask;
pub const MaskKind = program.MaskKind;
pub const Program = program.Program;
pub const Stem = program.Stem;
pub const Params = params.Params;

test {
    _ = program;
    _ = fixed;
    _ = params;
    _ = map;
    _ = @import("instance.zig");
}
