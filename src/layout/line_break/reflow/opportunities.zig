//! Streaming UAX #14 opportunities mapped onto retained shaped output.
//!
//! The cursor isolates whether opportunities are streamed or retained. The
//! recorder then enforces HarfBuzz-compatible unsafe-boundary semantics before
//! exposing a greedy-wrap candidate.

const std = @import("std");

const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const discretionary_hyphen = @import("../../discretionary_hyphen.zig");
const geometry = @import("geometry.zig");
const opportunity = @import("../opportunity.zig");
const shaped_boundary = @import("../shaped_boundary.zig");
const unicode = @import("../../../unicode.zig");

pub const Candidate = struct {
    glyph_index: ?usize = null,
    width: f32 = 0,
    hyphen: ?discretionary_hyphen.Candidate = null,
    automatic_hyphen: ?AutomaticHyphen = null,

    pub fn reset(self: *Candidate) void {
        self.* = .{};
    }

    pub fn hasVisibleHyphen(self: Candidate) bool {
        return self.hyphen != null or self.automatic_hyphen != null;
    }
};

pub const AutomaticHyphen = struct {
    byte_offset: usize,
    run_index: usize,
    resolved: discretionary_hyphen.Resolved,
    vertical: bool,
};

pub const Cursor = struct {
    iterator: unicode.LineBreakIterator,
    analyzed: ?[]const opportunity.Opportunity = null,
    analyzed_index: usize = 0,
    pending: ?unicode.LineBreak = null,

    pub fn init(
        text: []const u8,
        analyzed: ?[]const opportunity.Opportunity,
    ) Cursor {
        return .{
            .iterator = unicode.lineBreaksAssumeValid(text),
            .analyzed = analyzed,
        };
    }

    /// Return the next boundary whose source position has already been covered
    /// by shaped glyphs. Retained paragraphs read pre-analyzed opportunities;
    /// one-shot layout uses one-item iterator lookahead without allocating a
    /// complete boundary list.
    pub fn nextThrough(
        self: *Cursor,
        byte_offset: usize,
    ) ?opportunity.Opportunity {
        const candidate = if (self.analyzed) |breaks|
            if (self.analyzed_index < breaks.len)
                breaks[self.analyzed_index]
            else
                return null
        else candidate: {
            if (self.pending == null) self.pending = self.iterator.next();
            break :candidate opportunity.fromUnicode(
                self.pending orelse return null,
            );
        };
        if (candidate.byte_offset > byte_offset) return null;
        if (self.analyzed != null) {
            self.analyzed_index += 1;
        } else {
            self.pending = null;
        }
        return candidate;
    }

    pub fn discardThrough(self: *Cursor, byte_offset: usize) void {
        while (self.nextThrough(byte_offset) != null) {}
    }
};

pub fn recordSoft(
    glyphs: []const GlyphPosition,
    runs: anytype,
    byte_offset: usize,
    index: usize,
    line_start: usize,
    line_width: f32,
    candidate: *Candidate,
    normalized_variation_coords: []const f32,
    automatic_hyphen: bool,
    hyphen_character: ?u21,
) !void {
    if (glyphs.len == 0) return;
    if (shaped_boundary.sourceBoundaryIsUnsafe(
        glyphs,
        byte_offset,
        index,
    )) return;
    const current = glyphs[index];
    if (geometry.isDiscardableBreak(current.codepoint) and
        shaped_boundary.glyphSourceEnd(current) == byte_offset)
    {
        if (index > line_start) {
            candidate.* = .{
                .glyph_index = index,
                .width = line_width - current.x_advance,
            };
        }
        return;
    }
    const current_source_end = shaped_boundary.glyphSourceEnd(current);
    if (byte_offset > current.cluster and byte_offset < current_source_end) {
        // The Unicode opportunity falls inside a source span collapsed by
        // shaping (for example, a GSUB ligature). Reusing the current glyph
        // stream across that boundary would be incorrect.
        return;
    }
    if (byte_offset == current_source_end) {
        // This runs after the last output of the source atom, keeping the
        // overwhelmingly common case O(1) rather than searching the line.
        const break_index = index + 1;
        if (break_index > line_start) {
            if (automatic_hyphen) {
                const resolved = try discretionary_hyphen.resolveForGlyphRun(
                    runs,
                    index,
                    normalized_variation_coords,
                    hyphen_character,
                ) orelse return;
                candidate.* = .{
                    .glyph_index = break_index,
                    .width = line_width + resolved.resolved.x_advance,
                    .automatic_hyphen = .{
                        .byte_offset = byte_offset,
                        .run_index = resolved.run_index,
                        .resolved = resolved.resolved,
                        .vertical = current.vertical,
                    },
                };
            } else {
                const discretionary =
                    discretionary_hyphen.isCandidate(current.codepoint);
                const resolved_hyphen =
                    if (discretionary)
                        try discretionary_hyphen.resolveForGlyph(
                            runs,
                            index,
                            normalized_variation_coords,
                            hyphen_character,
                        )
                    else
                        null;
                // A requested replacement is an exact policy, not a hint.
                // Silently taking the break with an invisible U+00AD would
                // violate line fitting and the caller's visible-line limit.
                if (discretionary and
                    hyphen_character != null and
                    resolved_hyphen == null)
                {
                    return;
                }
                candidate.* = .{
                    .glyph_index = break_index,
                    .width = line_width +
                        if (resolved_hyphen) |resolved|
                            resolved.x_advance
                        else
                            0,
                    .hyphen = if (resolved_hyphen) |resolved| .{
                        .glyph_index = index,
                        .resolved = resolved,
                    } else null,
                };
            }
        }
        return;
    }
    const break_index = shaped_boundary.glyphIndexForSourceBoundary(
        glyphs,
        byte_offset,
        line_start,
        index + 1,
    ) orelse @min(index + 1, glyphs.len);
    if (break_index > line_start) {
        const width = geometry.lineWidth(glyphs[line_start..break_index]);
        if (automatic_hyphen) {
            const owner_index = break_index - 1;
            const resolved = try discretionary_hyphen.resolveForGlyphRun(
                runs,
                owner_index,
                normalized_variation_coords,
                hyphen_character,
            ) orelse return;
            candidate.* = .{
                .glyph_index = break_index,
                .width = width + resolved.resolved.x_advance,
                .automatic_hyphen = .{
                    .byte_offset = byte_offset,
                    .run_index = resolved.run_index,
                    .resolved = resolved.resolved,
                    .vertical = glyphs[owner_index].vertical,
                },
            };
        } else {
            candidate.* = .{
                .glyph_index = break_index,
                .width = width,
            };
        }
    }
}

pub fn isMandatory(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

test "soft opportunity never splits a shaped source atom" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 2,
            .x_advance = 10,
        },
        .{
            .glyph_id = 2,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 2,
            .x_advance = 5,
        },
    };
    var candidate = Candidate{};

    try recordSoft(
        &glyphs,
        &.{},
        1,
        1,
        0,
        15,
        &candidate,
        &.{},
        false,
        null,
    );
    try std.testing.expectEqual(@as(?usize, null), candidate.glyph_index);

    try recordSoft(
        &glyphs,
        &.{},
        2,
        1,
        0,
        15,
        &candidate,
        &.{},
        false,
        null,
    );
    try std.testing.expectEqual(@as(?usize, 2), candidate.glyph_index);
    try std.testing.expectApproxEqAbs(@as(f32, 15), candidate.width, 0.001);
}

test "soft opportunity rejects contextual unsafe boundary" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 1,
            .x_advance = 10,
        },
        .{
            .glyph_id = 2,
            .codepoint = 'B',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 10,
            .flags = .{ .unsafe_to_break_before = true },
        },
    };
    var candidate = Candidate{};
    try recordSoft(
        &glyphs,
        &.{},
        1,
        0,
        0,
        10,
        &candidate,
        &.{},
        false,
        null,
    );
    try std.testing.expectEqual(@as(?usize, null), candidate.glyph_index);

    // Automatic boundaries must take the same shaping-safety path before
    // attempting to resolve or insert a visible hyphen.
    try recordSoft(
        &glyphs,
        &.{},
        1,
        0,
        0,
        10,
        &candidate,
        &.{},
        true,
        null,
    );
    try std.testing.expectEqual(@as(?usize, null), candidate.glyph_index);
}
