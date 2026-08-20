//! Whole-lookup PairPos strategy selection.

const std = @import("std");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
const options = @import("../../../options.zig");
const pair = @import("../../pair/root.zig");
const positioning = @import("../../../../positioning/root.zig");
const runtime_dispatch = @import("../../../dispatch.zig");
const table = @import("../../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error =
    table.view.Error || error{UnsupportedGpos} || std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn collect(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    if (runtime_dispatch.acceleratorWithCoverage(
        lookup_index,
        run,
    )) |accelerator| {
        if (accelerator.pair_pos_subtables.len == subtable_count and
            pair.accelerated.hasNativeData(accelerator.pair_pos_subtables))
        {
            return pair.accelerated.collectLookup(
                view,
                lookup_offset,
                subtable_count,
                accelerator,
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                run,
            );
        }
    }
    return pair.generic.collectLookup(
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}
