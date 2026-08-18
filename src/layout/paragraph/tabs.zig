//! Explicit paragraph tab rulers and repeating fallback stops.
//!
//! Stop positions are advances from the selected line fragment's logical
//! inline start. The scalar distance is therefore direction-neutral: per-line
//! bidi later maps the same logical geometry to the physical left or right.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;

/// Alignment of the field following a tab marker.
///
/// Alignment is resolved in logical source order before line-level bidi maps
/// that geometry to physical coordinates.
pub const Alignment = enum {
    start,
    center,
    end,
    decimal,
};

/// One absolute stop in paragraph layout units.
///
/// Stops must be finite, positive, and strictly increasing. A tab whose
/// current logical advance precedes a stop moves exactly to the first such
/// stop. After the last explicit stop, the paragraph's repeating `tab_width`
/// grid remains the fallback.
pub const Stop = struct {
    position: f32,
    alignment: Alignment = .start,
    /// Scalar terminating the leading side of a `.decimal` field.
    ///
    /// The first matching source atom is used. If no atom matches, decimal
    /// alignment falls back to `.end`.
    decimal_point: u21 = '.',
};

pub fn marker(byte_index: usize) GlyphPosition {
    return .{
        .glyph_id = 0,
        .codepoint = '\t',
        .cluster = byte_index,
        .source_byte_len = 1,
        .x_advance = 0,
        .flags = .{ .tab = true },
    };
}

pub fn validate(stops: []const Stop) !void {
    var previous: f32 = 0;
    for (stops) |stop| {
        if (!std.math.isFinite(stop.position) or
            stop.position <= previous)
        {
            return error.InvalidParagraphOptions;
        }
        if (!std.unicode.utf8ValidCodepoint(stop.decimal_point)) {
            return error.InvalidParagraphOptions;
        }
        switch (stop.alignment) {
            .start, .center, .end, .decimal => {},
        }
        previous = stop.position;
    }
}

pub const Field = struct {
    total_width: f32,
    before_decimal_width: ?f32,
};

pub fn advance(
    current_advance: f32,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
    field: Field,
) f32 {
    for (stops) |stop| {
        if (stop.position > current_advance) {
            const aligned_start = switch (stop.alignment) {
                .start => stop.position,
                .center => stop.position - field.total_width / 2,
                .end => stop.position - field.total_width,
                .decimal => stop.position -
                    (field.before_decimal_width orelse field.total_width),
            };
            return @max(0, aligned_start - current_advance);
        }
    }
    if (!std.math.isFinite(current_advance) or
        !std.math.isFinite(fallback_interval) or
        fallback_interval <= 0)
    {
        return @max(0, fallback_advance);
    }
    const fallback_origin = if (stops.len == 0)
        0
    else
        stops[stops.len - 1].position;
    const distance_from_origin = @max(0, current_advance - fallback_origin);
    const intervals_passed =
        @floor(distance_from_origin / fallback_interval);
    const next_stop =
        fallback_origin + (intervals_passed + 1) * fallback_interval;
    const result = next_stop - current_advance;
    // At very large f32 magnitudes, adding one interval can round back to the
    // current value. Preserve forward progress with one ordinary space.
    if (!std.math.isFinite(result) or result <= 0) {
        return @max(0, fallback_advance);
    }
    // Preserve the historical uniform-grid contract when no explicit ruler
    // exists: a tab never advances less than one ordinary space. Explicit
    // rulers use exact positions, including close successive stops.
    return if (stops.len == 0)
        @max(@max(0, fallback_advance), result)
    else
        result;
}

/// Recompute tab advances after a wrap changes the logical line origin.
///
/// Non-tab advances already contain shaping and paragraph spacing. Only tabs
/// are mutable here, so repeated calls are idempotent.
pub fn recomputeRange(
    glyphs: []GlyphPosition,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    return recomputeRangeWithTerminal(
        glyphs,
        stops,
        fallback_interval,
        fallback_advance,
        0,
    );
}

pub fn recomputeRangeWithTerminal(
    glyphs: []GlyphPosition,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
    terminal_advance: f32,
) f32 {
    var width: f32 = 0;
    for (glyphs, 0..) |*glyph, glyph_index| {
        if (glyph.isActiveTab()) {
            glyph.x_advance = resolvedAdvance(
                glyphs,
                glyph_index,
                width,
                stops,
                fallback_interval,
                fallback_advance,
                terminal_advance,
            );
        }
        width += glyph.x_advance;
    }
    return width + terminal_advance;
}

/// Recompute tabs already visited in a line prefix while measuring their
/// complete following fields from the full remaining line source.
pub fn recomputePrefix(
    glyphs: []GlyphPosition,
    prefix_len: usize,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    var width: f32 = 0;
    const end = @min(prefix_len, glyphs.len);
    for (glyphs[0..end], 0..) |*glyph, glyph_index| {
        if (glyph.isActiveTab()) {
            glyph.x_advance = resolvedAdvance(
                glyphs,
                glyph_index,
                width,
                stops,
                fallback_interval,
                fallback_advance,
                0,
            );
        }
        width += glyph.x_advance;
    }
    return width;
}

pub fn measureRange(
    glyphs: []const GlyphPosition,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    return measureRangeWithTerminal(
        glyphs,
        stops,
        fallback_interval,
        fallback_advance,
        0,
    );
}

pub fn measureRangeWithTerminal(
    glyphs: []const GlyphPosition,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
    terminal_advance: f32,
) f32 {
    var width: f32 = 0;
    for (glyphs, 0..) |glyph, glyph_index| {
        const glyph_advance = if (glyph.isActiveTab())
            resolvedAdvance(
                glyphs,
                glyph_index,
                width,
                stops,
                fallback_interval,
                fallback_advance,
                terminal_advance,
            )
        else
            glyph.x_advance;
        width += glyph_advance;
    }
    return width + terminal_advance;
}

fn resolvedAdvance(
    glyphs: []const GlyphPosition,
    glyph_index: usize,
    current_advance: f32,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
    terminal_advance: f32,
) f32 {
    const stop = nextExplicitStop(current_advance, stops);
    return advance(
        current_advance,
        stops,
        fallback_interval,
        fallback_advance,
        measureField(
            glyphs,
            glyph_index + 1,
            if (stop) |item| item.decimal_point else '.',
            terminal_advance,
        ),
    );
}

pub fn contains(glyphs: []const GlyphPosition) bool {
    for (glyphs) |glyph| {
        if (glyph.isActiveTab()) return true;
    }
    return false;
}

pub fn nextExplicitStop(
    current_advance: f32,
    stops: []const Stop,
) ?Stop {
    for (stops) |stop| {
        if (stop.position > current_advance) return stop;
    }
    return null;
}

pub fn measureField(
    glyphs: []const GlyphPosition,
    start: usize,
    decimal_point: u21,
    terminal_advance: f32,
) Field {
    var total: f32 = 0;
    var before_decimal: ?f32 = null;
    var index = start;
    while (index < glyphs.len) : (index += 1) {
        const glyph = glyphs[index];
        if (glyph.isActiveTab() or isMandatoryBreak(glyph.codepoint)) break;
        if (before_decimal == null and glyph.codepoint == decimal_point) {
            before_decimal = total;
        }
        total += glyph.x_advance;
    }
    if (index == glyphs.len) total += terminal_advance;
    return .{
        .total_width = total,
        .before_decimal_width = before_decimal,
    };
}

fn isMandatoryBreak(codepoint: u21) bool {
    return switch (@import("../../unicode.zig").lineBreakClassForCodepoint(
        codepoint,
    )) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

test "explicit stops precede the repeating fallback grid" {
    const stops = [_]Stop{
        .{ .position = 40 },
        .{ .position = 90 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 24),
        advance(16, &stops, 32, 16, .{
            .total_width = 0,
            .before_decimal_width = null,
        }),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 34),
        advance(56, &stops, 32, 16, .{
            .total_width = 0,
            .before_decimal_width = null,
        }),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 32),
        advance(90, &stops, 32, 16, .{
            .total_width = 0,
            .before_decimal_width = null,
        }),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 22),
        advance(100, &stops, 32, 16, .{
            .total_width = 0,
            .before_decimal_width = null,
        }),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 16),
        advance(31, &.{}, 32, 16, .{
            .total_width = 0,
            .before_decimal_width = null,
        }),
        0.001,
    );
}

test "tab stop validation requires positive strict order" {
    for ([_][]const Stop{
        &.{.{ .position = 0 }},
        &.{.{ .position = std.math.inf(f32) }},
        &.{.{ .position = std.math.nan(f32) }},
        &.{.{
            .position = 20,
            .alignment = .decimal,
            .decimal_point = 0xd800,
        }},
        &.{ .{ .position = 20 }, .{ .position = 20 } },
        &.{ .{ .position = 20 }, .{ .position = 10 } },
    }) |stops| {
        try std.testing.expectError(
            error.InvalidParagraphOptions,
            validate(stops),
        );
    }
    try validate(&.{ .{ .position = 20 }, .{ .position = 40 } });
}

test "field measurement stops at tab and mandatory break" {
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 14 },
        marker(1),
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 2, .x_advance = 16 },
        .{ .glyph_id = 1, .codepoint = '.', .cluster = 3, .x_advance = 8 },
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 4, .x_advance = 16 },
        marker(5),
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 6, .x_advance = 16 },
        .{ .glyph_id = 0, .codepoint = '\n', .cluster = 7, .x_advance = 0 },
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 8, .x_advance = 16 },
    };
    try std.testing.expectEqual(
        Field{ .total_width = 40, .before_decimal_width = 16 },
        measureField(&glyphs, 2, '.', 99),
    );
    try std.testing.expectEqual(
        Field{ .total_width = 16, .before_decimal_width = null },
        measureField(&glyphs, 6, '.', 99),
    );
}

test "range recomputation is idempotent" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 16 },
        marker(1),
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 2, .x_advance = 16 },
    };
    glyphs[1].x_advance = 999;
    try std.testing.expectApproxEqAbs(
        @as(f32, 56),
        recomputeRange(&glyphs, &.{.{ .position = 40 }}, 32, 16),
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 24), glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 56),
        recomputeRange(&glyphs, &.{.{ .position = 40 }}, 32, 16),
        0.001,
    );
}

test "field alignments use shaped widths and decimal fallback" {
    const field = Field{
        .total_width = 30,
        .before_decimal_width = 14,
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 29),
        advance(16, &.{.{
            .position = 60,
            .alignment = .center,
        }}, 32, 16, field),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 14),
        advance(16, &.{.{
            .position = 60,
            .alignment = .end,
        }}, 32, 16, field),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        advance(16, &.{.{
            .position = 60,
            .alignment = .decimal,
        }}, 32, 16, field),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 14),
        advance(16, &.{.{
            .position = 60,
            .alignment = .decimal,
        }}, 32, 16, .{
            .total_width = 30,
            .before_decimal_width = null,
        }),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        advance(32, &.{.{
            .position = 40,
            .alignment = .end,
        }}, 32, 16, .{
            .total_width = 64,
            .before_decimal_width = null,
        }),
        0.001,
    );
}
