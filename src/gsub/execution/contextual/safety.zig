//! Source-boundary safety marking for contextual GSUB matches.

const std = @import("std");
const Options = @import("../../runtime/options.zig").Options;

pub fn markInput(
    allocator: std.mem.Allocator,
    run: Options,
    glyph_indices: []const usize,
) std.mem.Allocator.Error!void {
    const safety = run.source_boundaries orelse return;
    const sources = run.glyph_source_indices orelse return;
    try safety.markMatchedGlyphs(
        allocator,
        sources.items,
        glyph_indices,
    );
}

pub fn markRegions(
    allocator: std.mem.Allocator,
    run: Options,
    backtrack: []const usize,
    input: []const usize,
    lookahead: []const usize,
) std.mem.Allocator.Error!void {
    const safety = run.source_boundaries orelse return;
    const sources = run.glyph_source_indices orelse return;
    try safety.markMatchedRegions(
        allocator,
        sources.items,
        backtrack,
        input,
        lookahead,
    );
}
