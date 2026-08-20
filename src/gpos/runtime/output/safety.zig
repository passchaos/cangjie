//! Unsafe-to-break output marking for GPOS relationships.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");
const runtime_options = @import("../options.zig");

pub const Adjustment = positioning.Adjustment;
pub const Options = runtime_options.Options;

pub inline fn markPair(
    allocator: std.mem.Allocator,
    options: *const Options,
    first_glyph: usize,
    second_glyph: usize,
) std.mem.Allocator.Error!void {
    if (options.unsafe_glyphs) |unsafe_glyphs| {
        if (unsafe_glyphs.markRange(
            @min(first_glyph, second_glyph),
            @max(first_glyph, second_glyph) +| 1,
        )) return;
    }
    const metadata = options.run_metadata;
    const safety = metadata.source_boundaries orelse return;
    const sources = metadata.glyph_source_indices orelse return;
    try safety.markGlyphPair(
        allocator,
        sources,
        first_glyph,
        second_glyph,
    );
}

pub fn markPairApplication(
    allocator: std.mem.Allocator,
    options: *const Options,
    glyph_count: usize,
    first_glyph: usize,
    second_glyph: usize,
    first_value: Adjustment,
    second_value: Adjustment,
    has_second_value_record: bool,
) std.mem.Allocator.Error!void {
    const applied = hasEffectiveNumericDelta(
        first_value,
        options.vertical,
    ) or hasEffectiveNumericDelta(
        second_value,
        options.vertical,
    );
    if (!applied and !has_second_value_record) return;
    const unsafe_end =
        if (has_second_value_record and second_glyph + 1 < glyph_count)
            second_glyph + 1
        else
            second_glyph;
    try markPair(allocator, options, first_glyph, unsafe_end);
}

pub fn markContext(
    allocator: std.mem.Allocator,
    options: *const Options,
    glyph_indices: []const usize,
) std.mem.Allocator.Error!void {
    if (glyph_indices.len >= 2) {
        if (options.unsafe_glyphs) |unsafe_glyphs| {
            var first = glyph_indices[0];
            var last = first;
            for (glyph_indices[1..]) |index| {
                first = @min(first, index);
                last = @max(last, index);
            }
            if (unsafe_glyphs.markRange(first, last +| 1)) return;
        }
    }
    const metadata = options.run_metadata;
    const safety = metadata.source_boundaries orelse return;
    const sources = metadata.glyph_source_indices orelse return;
    try safety.markMatchedGlyphs(allocator, sources, glyph_indices);
}

pub fn markChainingContext(
    allocator: std.mem.Allocator,
    options: *const Options,
    backtrack: []const usize,
    input: []const usize,
    lookahead: []const usize,
) std.mem.Allocator.Error!void {
    if (options.unsafe_glyphs) |unsafe_glyphs| {
        var first: ?usize = null;
        var last: usize = 0;
        for ([_][]const usize{ backtrack, input, lookahead }) |region| {
            for (region) |index| {
                first = if (first) |value| @min(value, index) else index;
                last = @max(last, index);
            }
        }
        if (first) |start| {
            if (unsafe_glyphs.markRange(start, last +| 1)) return;
        }
    }
    const metadata = options.run_metadata;
    const safety = metadata.source_boundaries orelse return;
    const sources = metadata.glyph_source_indices orelse return;
    try safety.markMatchedRegions(
        allocator,
        sources,
        backtrack,
        input,
        lookahead,
    );
}

fn hasEffectiveNumericDelta(value: Adjustment, vertical: bool) bool {
    return (!vertical and value.x_advance != 0) or
        value.x_placement != 0 or
        value.y_placement != 0 or
        (vertical and value.y_advance != 0);
}
