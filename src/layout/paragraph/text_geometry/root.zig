//! Platform-neutral paragraph text-run geometry.

const build_impl = @import("build.zig");
const types = @import("types.zig");

pub const Direction = types.Direction;
pub const FontRun = types.FontRun;
pub const Grapheme = types.Grapheme;
pub const Span = types.Span;
pub const TextGeometry = types.TextGeometry;
pub const Options = build_impl.Options;

pub const build = build_impl.build;
pub const buildStyled = build_impl.buildStyled;
