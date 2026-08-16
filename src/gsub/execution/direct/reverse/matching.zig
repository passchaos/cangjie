//! ReverseChainSingleSubst context matching.

const accelerator = @import("../../../accelerator/root.zig");
const context_traversal = @import("../../support/context_traversal.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const ContextKey = accelerator.model.ReverseChainingContextKey;
const Error = table.coverage.Error;
const Parsed = accelerator.model.ReverseChainingSingleSubtable;
const View = table.View;

const max_context_glyphs = 64;

pub fn contextsMatch(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    return try sequenceMatches(
        view,
        subtable,
        glyphs,
        position,
        subtable.backtrack_offsets_pos,
        subtable.backtrack_count,
        .backtrack,
        lookup_flag,
        run,
    ) and try sequenceMatches(
        view,
        subtable,
        glyphs,
        position,
        subtable.lookahead_offsets_pos,
        subtable.lookahead_count,
        .lookahead,
        lookup_flag,
        run,
    );
}

/// Build the fixed one-backtrack/two-lookahead key used by the exact-context
/// accelerator. Returning null means the run cannot satisfy that shape.
pub fn exactKey(
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) ?ContextKey {
    if (position >= glyphs.len) return null;
    const backtrack = context_traversal.previousGlyph(
        glyphs,
        position,
        lookup_flag,
        run,
        true,
        position,
    ) orelse return null;
    const lookahead_0_index = context_traversal.nextIndex(
        glyphs,
        position + 1,
        lookup_flag,
        run,
        true,
        position,
    ) orelse return null;
    const lookahead_1_index = context_traversal.nextIndex(
        glyphs,
        lookahead_0_index + 1,
        lookup_flag,
        run,
        true,
        position,
    ) orelse return null;
    return .{
        .target = glyphs[position],
        .backtrack = backtrack,
        .lookahead_0 = glyphs[lookahead_0_index],
        .lookahead_1 = glyphs[lookahead_1_index],
    };
}

const SequenceKind = enum { backtrack, lookahead };

fn sequenceMatches(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    position: usize,
    offsets_pos: usize,
    count: usize,
    comptime kind: SequenceKind,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    var indices_buffer: [max_context_glyphs]usize = undefined;
    if (count > indices_buffer.len) return error.UnsupportedGsub;
    const indices = indices_buffer[0..count];
    const available = switch (kind) {
        .backtrack => context_traversal.collectBacktrack(
            glyphs,
            position,
            lookup_flag,
            run,
            indices,
            true,
            position,
        ),
        .lookahead => context_traversal.collectForward(
            glyphs,
            position + 1,
            lookup_flag,
            run,
            indices,
            true,
            position,
        ),
    };
    if (!available) return false;

    for (indices, 0..) |glyph_index, context_index| {
        const coverage_offset = try table.offset.required16(
            view,
            subtable.subtable_offset,
            try view.readU16(offsets_pos + context_index * 2),
        );
        if (try table.coverage.index(
            view,
            coverage_offset,
            glyphs[glyph_index],
        ) == null) return false;
    }
    return true;
}
