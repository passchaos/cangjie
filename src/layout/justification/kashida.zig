//! Transactional Arabic Kashida insertion and line-local reshaping.
//!
//! A retained `safe_to_insert_tatweel` flag nominates a UTF-8 source boundary;
//! it is not a glyph insertion point. This module constructs temporary source
//! text containing real U+0640 scalars, asks the caller-owned shaper to shape
//! the complete logical line, and adopts only candidates that make monotone
//! progress without exceeding the selected line's target measure.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const geometry = @import("../line_break/reflow/geometry.zig");
const line_transaction = @import("line_transaction.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");

const tatweel_utf8 = "\xd9\x80";
const width_epsilon: f32 = 0.001;

pub const Boundary = struct {
    byte_offset: usize,
    font: *const @import("../../font.zig").Font,
};

/// Shape pending justified lines through a concrete recipe.
///
/// `recipe.shapeLine(buffer, temporary_text, original_start, original_len)`
/// must clear `buffer` and shape the supplied text in logical order. After
/// cluster normalization, `recipe.finishLine(buffer)` applies recipe-specific
/// source spacing without assigning it to generated U+0640 glyphs.
pub fn apply(
    buffer: anytype,
    text: []const u8,
    options: anytype,
    recipe: anytype,
) !void {
    if (options.alignment != .justify or
        !options.kashida.enabled or
        options.kashida.max_insertions_per_line == 0 or
        buffer.lines.items.len == 0)
    {
        return;
    }

    var work = @TypeOf(buffer.*).init(buffer.allocator);
    defer work.deinit();
    var temporary_text = std.ArrayList(u8).empty;
    defer temporary_text.deinit(buffer.allocator);
    var insertion_boundaries = std.ArrayList(Boundary).empty;
    defer insertion_boundaries.deinit(buffer.allocator);
    var adopted_glyphs = std.ArrayList(GlyphPosition).empty;
    defer adopted_glyphs.deinit(buffer.allocator);
    var adopted_runs = std.ArrayList(run_types.CascadeRun).empty;
    defer adopted_runs.deinit(buffer.allocator);
    var adopted_variation_coords = std.ArrayList(f32).empty;
    defer adopted_variation_coords.deinit(buffer.allocator);

    var line_index: usize = 0;
    while (line_index < buffer.lines.items.len) : (line_index += 1) {
        const line = buffer.lines.items[line_index];
        const target = line.justification_target orelse continue;
        if (line.glyph_len == 0 or
            lineContainsSynthetic(buffer.glyphs.items, line))
        {
            continue;
        }
        const source_range = visibleSourceRange(
            buffer.glyphs.items,
            line,
        ) orelse continue;
        try collectBoundaries(
            &insertion_boundaries,
            buffer.allocator,
            buffer.glyphs.items,
            buffer.runs.items,
            line,
            recipe,
        );
        if (insertion_boundaries.items.len == 0) continue;

        adopted_glyphs.clearRetainingCapacity();
        adopted_runs.clearRetainingCapacity();
        adopted_variation_coords.clearRetainingCapacity();
        var adopted_width = geometry.lineWidth(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        );
        var insertion_count: usize = 0;
        while (insertion_count < options.kashida.max_insertions_per_line) {
            insertion_count += 1;
            try buildTemporaryLine(
                &temporary_text,
                buffer.allocator,
                text[source_range.start..source_range.end],
                source_range.start,
                insertion_boundaries.items,
                insertion_count,
            );
            try recipe.shapeLine(
                &work,
                temporary_text.items,
                source_range.start,
                source_range.end - source_range.start,
                insertion_boundaries.items,
                insertion_count,
            );
            try normalizeTemporaryClusters(
                work.glyphs.items,
                source_range.start,
                source_range.end - source_range.start,
                insertion_boundaries.items,
                insertion_count,
            );
            try recipe.finishLine(&work);

            const candidate_width = geometry.lineWidth(work.glyphs.items);
            if (candidate_width <= adopted_width + width_epsilon) continue;
            // OpenType substitutions can make width non-monotone as more
            // Tatweels are introduced. Reject this candidate but keep the
            // bounded search alive rather than assuming every later shape is
            // wider as well.
            if (candidate_width > target + width_epsilon) continue;

            adopted_glyphs.clearRetainingCapacity();
            adopted_runs.clearRetainingCapacity();
            adopted_variation_coords.clearRetainingCapacity();
            try adopted_glyphs.appendSlice(
                buffer.allocator,
                work.glyphs.items,
            );
            try adopted_runs.appendSlice(
                buffer.allocator,
                work.runs.items,
            );
            try adopted_variation_coords.appendSlice(
                buffer.allocator,
                work.variation_coords.items,
            );
            try recipe.saveCandidate();
            adopted_width = candidate_width;
            if (target - adopted_width <= width_epsilon) break;
        }

        if (adopted_glyphs.items.len == 0) continue;
        try recipe.prepareCommit(
            line.glyph_start,
            line.glyph_len,
            adopted_glyphs.items.len,
        );
        try line_transaction.replace(
            buffer,
            line_index,
            adopted_glyphs.items,
            adopted_runs.items,
            adopted_variation_coords.items,
            adopted_width,
        );
        recipe.commit(
            line.glyph_start,
            line.glyph_len,
            adopted_glyphs.items.len,
        );
    }
}

pub fn collectBoundaries(
    boundaries: *std.ArrayList(Boundary),
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    line: paragraph_types.ParagraphLine,
    recipe: anytype,
) !void {
    return collectBoundariesForKind(
        boundaries,
        allocator,
        glyphs,
        runs,
        line,
        recipe,
        .kashida,
    );
}

pub fn collectJstfExtenderBoundaries(
    boundaries: *std.ArrayList(Boundary),
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    line: paragraph_types.ParagraphLine,
    recipe: anytype,
) !void {
    return collectBoundariesForKind(
        boundaries,
        allocator,
        glyphs,
        runs,
        line,
        recipe,
        .jstf_extender,
    );
}

const BoundaryKind = enum { kashida, jstf_extender };

fn collectBoundariesForKind(
    boundaries: *std.ArrayList(Boundary),
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    line: paragraph_types.ParagraphLine,
    recipe: anytype,
    comptime kind: BoundaryKind,
) !void {
    boundaries.clearRetainingCapacity();
    const line_end = line.glyph_start + line.glyph_len;
    for (
        glyphs[line.glyph_start..line_end],
        line.glyph_start..,
    ) |glyph, glyph_index| {
        if (!glyph.isSafeToInsertTatweel()) continue;
        if (glyph.cluster <= line.byte_start or glyph.cluster >= line.byteEnd()) {
            continue;
        }
        const accepted = switch (kind) {
            .kashida => recipe.acceptKashidaBoundary(glyph.cluster),
            .jstf_extender => recipe.acceptJstfExtenderBoundary(glyph.cluster),
        };
        if (!accepted) continue;
        const font = fontForGlyphIndex(runs, glyph_index) orelse continue;
        for (boundaries.items) |boundary| {
            if (boundary.byte_offset == glyph.cluster) break;
        } else {
            try boundaries.append(allocator, .{
                .byte_offset = glyph.cluster,
                .font = font,
            });
        }
    }
    std.sort.heap(Boundary, boundaries.items, {}, boundaryLessThan);
}

fn boundaryLessThan(_: void, lhs: Boundary, rhs: Boundary) bool {
    return lhs.byte_offset < rhs.byte_offset;
}

fn fontForGlyphIndex(
    runs: []const run_types.CascadeRun,
    glyph_index: usize,
) ?*const @import("../../font.zig").Font {
    for (runs) |run| {
        if (glyph_index < run.glyph_start or
            glyph_index >= run.glyph_start + run.glyph_len)
        {
            continue;
        }
        return run_types.fontForBackend(run);
    }
    return null;
}

pub fn buildTemporaryLine(
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    line_text: []const u8,
    line_byte_start: usize,
    boundaries: []const Boundary,
    insertion_count: usize,
) !void {
    output.clearRetainingCapacity();
    try output.ensureTotalCapacity(
        allocator,
        line_text.len + insertion_count * tatweel_utf8.len,
    );
    var source_cursor: usize = 0;
    for (boundaries, 0..) |boundary, boundary_index| {
        const count = insertionCountAtBoundary(
            insertion_count,
            boundaries.len,
            boundary_index,
        );
        if (count == 0) continue;
        const local = boundary.byte_offset - line_byte_start;
        if (local > source_cursor) {
            output.appendSliceAssumeCapacity(line_text[source_cursor..local]);
            source_cursor = local;
        }
        for (0..count) |_| output.appendSliceAssumeCapacity(tatweel_utf8);
    }
    output.appendSliceAssumeCapacity(line_text[source_cursor..]);
}

pub fn normalizeTemporaryClusters(
    glyphs: []GlyphPosition,
    line_byte_start: usize,
    original_byte_len: usize,
    boundaries: []const Boundary,
    insertion_count: usize,
) !void {
    for (glyphs) |*glyph| {
        const temporary_start = glyph.cluster;
        const temporary_end = temporary_start + glyph.source_byte_len;
        const original_start = try originalByteForTemporaryBoundary(
            temporary_start,
            line_byte_start,
            original_byte_len,
            boundaries,
            insertion_count,
        );
        const original_end = try originalByteForTemporaryBoundary(
            temporary_end,
            line_byte_start,
            original_byte_len,
            boundaries,
            insertion_count,
        );
        if (original_end < original_start) return error.InvalidKashidaMap;
        glyph.cluster = original_start;
        glyph.source_byte_len = original_end - original_start;
        if (glyph.source_byte_len == 0 and temporary_end > temporary_start) {
            glyph.flags.safe_to_insert_tatweel = false;
            glyph.flags.kashida = true;
        }
    }
}

/// Map one byte boundary in a temporary Tatweel-expanded line back to the
/// caller's original paragraph byte space.
///
/// Every boundary inside an inserted U+0640 span collapses onto its nominated
/// original source boundary. This keeps both shaped Tatweel output and any
/// ligature spanning it from claiming bytes that do not exist in caller text.
pub fn originalByteForTemporaryBoundary(
    temporary_offset: usize,
    line_byte_start: usize,
    original_byte_len: usize,
    boundaries: []const Boundary,
    insertion_count: usize,
) !usize {
    var inserted_before: usize = 0;
    for (boundaries, 0..) |boundary, boundary_index| {
        const count = insertionCountAtBoundary(
            insertion_count,
            boundaries.len,
            boundary_index,
        );
        if (count == 0) continue;
        const original_local = boundary.byte_offset - line_byte_start;
        const temporary_start = original_local + inserted_before;
        const inserted_len = count * tatweel_utf8.len;
        if (temporary_offset < temporary_start) break;
        if (temporary_offset <= temporary_start + inserted_len) {
            return line_byte_start + original_local;
        }
        inserted_before += inserted_len;
    }
    if (temporary_offset < inserted_before) return error.InvalidKashidaMap;
    const original = temporary_offset - inserted_before;
    if (original > original_byte_len) return error.InvalidKashidaMap;
    return line_byte_start + original;
}

pub fn insertionCountAtBoundary(
    insertion_count: usize,
    boundary_count: usize,
    boundary_index: usize,
) usize {
    return insertion_count / boundary_count +
        @intFromBool(boundary_index < insertion_count % boundary_count);
}

pub fn lineContainsSynthetic(
    glyphs: []const GlyphPosition,
    line: paragraph_types.ParagraphLine,
) bool {
    const end = line.glyph_start + line.glyph_len;
    for (glyphs[line.glyph_start..end]) |glyph| {
        if (glyph.isInlineObject() or glyph.isDiscretionaryHyphen()) {
            return true;
        }
        if (glyph.isTab() or
            switch (@import("../../unicode.zig").lineBreakClassForCodepoint(
                glyph.codepoint,
            )) {
                .mandatory, .carriage_return, .line_feed, .next_line => true,
                else => false,
            })
        {
            return true;
        }
    }
    return false;
}

pub const SourceRange = struct {
    start: usize,
    end: usize,
};

pub fn visibleSourceRange(
    glyphs: []const GlyphPosition,
    line: paragraph_types.ParagraphLine,
) ?SourceRange {
    var start: usize = std.math.maxInt(usize);
    var end: usize = 0;
    for (glyphs[line.glyph_start .. line.glyph_start + line.glyph_len]) |glyph| {
        if (glyph.isKashida() or glyph.isAutomaticHyphen()) continue;
        start = @min(start, glyph.cluster);
        end = @max(end, glyph.sourceByteEnd());
    }
    if (start == std.math.maxInt(usize) or start >= end) return null;
    return .{ .start = start, .end = end };
}

test "temporary Tatweel byte ranges collapse to original source boundaries" {
    const boundaries = [_]Boundary{
        .{ .byte_offset = 2, .font = undefined },
        .{ .byte_offset = 7, .font = undefined },
    };
    // Original "بب بب" occupies bytes 0...9. One insertion at each nominated
    // boundary yields temporary ranges 2...4 and 9...11.
    try std.testing.expectEqual(
        @as(usize, 2),
        try originalByteForTemporaryBoundary(
            2,
            0,
            9,
            &boundaries,
            2,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        try originalByteForTemporaryBoundary(
            4,
            0,
            9,
            &boundaries,
            2,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 7),
        try originalByteForTemporaryBoundary(
            9,
            0,
            9,
            &boundaries,
            2,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 7),
        try originalByteForTemporaryBoundary(
            11,
            0,
            9,
            &boundaries,
            2,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 9),
        try originalByteForTemporaryBoundary(
            13,
            0,
            9,
            &boundaries,
            2,
        ),
    );
}

test "Tatweel distribution is deterministic and balanced" {
    try std.testing.expectEqual(
        @as(usize, 2),
        insertionCountAtBoundary(5, 3, 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        insertionCountAtBoundary(5, 3, 1),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        insertionCountAtBoundary(5, 3, 2),
    );
}
