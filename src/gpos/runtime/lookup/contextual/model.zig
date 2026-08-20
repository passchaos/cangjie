//! Shared static contracts for contextual lookup execution.

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
pub const Result = struct {
    matched: bool = false,
    next_pos: usize = 0,
};
pub const View = table.View;

/// Static bridge to PosLookupRecord recursion owned by the root dispatcher.
pub const ApplyRecordsFn = fn (
    View,
    usize,
    usize,
    []const usize,
    []const GlyphId,
    *std.ArrayList(Adjustment),
    std.mem.Allocator,
    Options,
) Error!void;

/// Static bridge to one nested lookup named by a PosLookupRecord.
pub const ApplyNestedFn = fn (
    View,
    []const GlyphId,
    usize,
    u16,
    *std.ArrayList(Adjustment),
    std.mem.Allocator,
    Options,
) Error!void;
