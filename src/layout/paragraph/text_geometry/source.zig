//! Source segmentation, bidi directions, and final font ownership.

const std = @import("std");

const draft = @import("draft.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const styled_paragraph = @import("../../styled_paragraph.zig");
const types = @import("types.zig");
const unicode = @import("../../../unicode.zig");

pub fn validateLayout(
    text: []const u8,
    layout: paragraph_types.ParagraphLayout,
) !void {
    var previous_run_end: usize = 0;
    for (layout.runs) |run| {
        if (run.glyph_start < previous_run_end or
            run.glyph_start > layout.glyphs.len or
            run.glyph_len > layout.glyphs.len - run.glyph_start)
        {
            return error.InvalidParagraphLayout;
        }
        previous_run_end = run.glyph_start + run.glyph_len;
    }

    var previous_glyph_end: usize = 0;
    var previous_byte_end: usize = 0;
    for (layout.lines) |line| {
        if (line.glyph_start < previous_glyph_end or
            line.glyph_start > layout.glyphs.len or
            line.glyph_len > layout.glyphs.len - line.glyph_start or
            line.byte_start < previous_byte_end or
            line.byte_start > text.len or
            line.byte_len > text.len - line.byte_start)
        {
            return error.InvalidParagraphLayout;
        }
        previous_glyph_end = line.glyph_start + line.glyph_len;
        previous_byte_end = line.byteEnd();
    }
}

pub fn buildOwners(
    allocator: std.mem.Allocator,
    layout: paragraph_types.ParagraphLayout,
) ![]draft.SourceOwner {
    var result = std.ArrayList(draft.SourceOwner).empty;
    errdefer result.deinit(allocator);
    for (layout.glyphs, 0..) |glyph, glyph_index| {
        if (glyph.isInlineObject() or glyph.isTab()) continue;
        const source_end = glyph.sourceByteEnd();
        if (source_end <= glyph.cluster) continue;
        const run_index = runIndexForGlyph(layout.runs, glyph_index) orelse
            continue;
        try result.append(allocator, .{
            .byte_start = glyph.cluster,
            .byte_end = source_end,
            .run_index = run_index,
        });
    }
    std.sort.heap(
        draft.SourceOwner,
        result.items,
        {},
        sourceOwnerLessThan,
    );
    return result.toOwnedSlice(allocator);
}

pub fn ownerForRange(
    owners: []const draft.SourceOwner,
    byte_start: usize,
    byte_end: usize,
) ?usize {
    // Find every owner that starts before the grapheme ends, then walk
    // backwards to the closest overlapping shaped source span.
    var low: usize = 0;
    var high = owners.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (owners[mid].byte_start < byte_end) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    var index = low;
    while (index > 0) {
        index -= 1;
        const owner = owners[index];
        if (owner.byte_end <= byte_start) continue;
        return owner.run_index;
    }
    return null;
}

pub fn collectWordStarts(
    allocator: std.mem.Allocator,
    text: []const u8,
) ![]usize {
    var result = std.ArrayList(usize).empty;
    errdefer result.deinit(allocator);
    var iterator = try unicode.wordSegments(text);
    while (iterator.next()) |segment| {
        if (segment.is_word) {
            try result.append(allocator, segment.byte_start);
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn graphemeRangeForLine(
    graphemes: []const unicode.GraphemeCluster,
    byte_start: usize,
    byte_end: usize,
) ?draft.IndexRange {
    if (byte_start > byte_end) return null;
    const start = lowerBoundGrapheme(graphemes, byte_start);
    const end = lowerBoundGrapheme(graphemes, byte_end);
    if (!isGraphemeBoundary(graphemes, start, byte_start) or
        !isGraphemeBoundary(graphemes, end, byte_end)) return null;
    return .{ .start = start, .end = end };
}

pub fn directionForLevels(
    levels: []const u8,
    line_scalar_start: usize,
    grapheme_scalar_start: usize,
    grapheme_scalar_end: usize,
    base_level: u8,
) types.Direction {
    var level = base_level;
    for (levels[grapheme_scalar_start - line_scalar_start .. grapheme_scalar_end - line_scalar_start]) |candidate| {
        // UAX #9 X9 controls have no visual level. A grapheme made entirely
        // from removed controls inherits the paragraph base direction.
        if (candidate == 0xff) continue;
        level = @max(level, candidate);
    }
    return if (level & 1 == 0) .ltr else .rtl;
}

pub fn styleForByte(
    spans: []const styled_paragraph.Span,
    byte_offset: usize,
) ?u32 {
    return (styled_paragraph.spanForCluster(
        spans,
        byte_offset,
    ) orelse return null).style_index;
}

pub fn runIndexForGlyph(
    runs: []const @import("../../types/runs.zig").CascadeRun,
    glyph_index: usize,
) ?usize {
    var low: usize = 0;
    var high = runs.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const run = runs[mid];
        if (glyph_index < run.glyph_start) {
            high = mid;
        } else if (glyph_index >= run.glyph_start + run.glyph_len) {
            low = mid + 1;
        } else {
            return mid;
        }
    }
    return null;
}

fn sourceOwnerLessThan(
    _: void,
    lhs: draft.SourceOwner,
    rhs: draft.SourceOwner,
) bool {
    if (lhs.byte_start != rhs.byte_start) {
        return lhs.byte_start < rhs.byte_start;
    }
    if (lhs.byte_end != rhs.byte_end) return lhs.byte_end < rhs.byte_end;
    return lhs.run_index < rhs.run_index;
}

fn lowerBoundGrapheme(
    graphemes: []const unicode.GraphemeCluster,
    byte_offset: usize,
) usize {
    var low: usize = 0;
    var high = graphemes.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (graphemes[mid].byte_start < byte_offset) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

fn isGraphemeBoundary(
    graphemes: []const unicode.GraphemeCluster,
    index: usize,
    byte_offset: usize,
) bool {
    if (index < graphemes.len) {
        return graphemes[index].byte_start == byte_offset;
    }
    if (graphemes.len == 0) return byte_offset == 0;
    const last = graphemes[graphemes.len - 1];
    return byte_offset == last.byte_start + last.byte_len;
}
