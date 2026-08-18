//! Explicit paragraph tab rulers and repeating fallback stops.
//!
//! Stop positions are advances from the selected line fragment's logical
//! inline start. The scalar distance is therefore direction-neutral: per-line
//! bidi later maps the same logical geometry to the physical left or right.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;

/// Alignment of the field following a tab marker.
///
/// The first ruler level intentionally implements only logical start. Keeping
/// alignment in the record now lets later field-measuring modes extend the
/// contract without replacing the stop representation.
pub const Alignment = enum {
    start,
};

/// One absolute stop in paragraph layout units.
///
/// Stops must be finite, positive, and strictly increasing. A tab whose
/// current logical advance precedes a stop moves exactly to the first such
/// stop. The initial public alignment is `.start`; this field is retained in
/// the record so complete following-field alignments can extend it without an
/// API replacement. After the last explicit stop, the paragraph's repeating
/// `tab_width` grid remains the fallback.
pub const Stop = struct {
    position: f32,
    alignment: Alignment = .start,
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
        switch (stop.alignment) {
            .start => {},
        }
        previous = stop.position;
    }
}

pub fn advance(
    current_advance: f32,
    stops: []const Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    for (stops) |stop| {
        if (stop.position > current_advance) {
            return stop.position - current_advance;
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
    var width: f32 = 0;
    for (glyphs) |*glyph| {
        if (glyph.isTab()) {
            glyph.x_advance = advance(
                width,
                stops,
                fallback_interval,
                fallback_advance,
            );
        }
        width += glyph.x_advance;
    }
    return width;
}

pub fn contains(glyphs: []const GlyphPosition) bool {
    for (glyphs) |glyph| {
        if (glyph.isTab()) return true;
    }
    return false;
}

test "explicit stops precede the repeating fallback grid" {
    const stops = [_]Stop{
        .{ .position = 40 },
        .{ .position = 90 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 24),
        advance(16, &stops, 32, 16),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 34),
        advance(56, &stops, 32, 16),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 32),
        advance(90, &stops, 32, 16),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 22),
        advance(100, &stops, 32, 16),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 16),
        advance(31, &.{}, 32, 16),
        0.001,
    );
}

test "tab stop validation requires positive strict order" {
    for ([_][]const Stop{
        &.{.{ .position = 0 }},
        &.{.{ .position = std.math.inf(f32) }},
        &.{.{ .position = std.math.nan(f32) }},
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
