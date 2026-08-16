//! Static contracts shared by ExtensionPos execution paths.

const std = @import("std");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const options = @import("../../options.zig");
const positioning = @import("../../../positioning/root.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error =
    table.view.Error ||
    error{ UnsupportedGpos, InvalidShapingInput } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

pub const CollectFn = fn (
    View,
    usize,
    []const GlyphId,
    *std.ArrayList(Adjustment),
    std.mem.Allocator,
    u16,
    Options,
) Error!void;

pub const CollectAtFn = fn (
    View,
    usize,
    []const GlyphId,
    usize,
    *std.ArrayList(Adjustment),
    std.mem.Allocator,
    u16,
    Options,
) Error!bool;

pub const CollectMarkBaseAtFn = fn (
    View,
    usize,
    []const GlyphId,
    usize,
    *std.ArrayList(Adjustment),
    std.mem.Allocator,
    u16,
    Options,
    []const bool,
) Error!bool;
