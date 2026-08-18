//! Positive-down tab-field measurement for vertical paragraph columns.
//!
//! The scalar ruler algorithm and public stop records remain in
//! `paragraph/tabs.zig`. This module owns only the y-axis field scan,
//! prospective prefix lookahead, and final mutation needed by vertical flow.

const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const tab_ruler = @import("../tabs.zig");

pub fn recomputeRange(
    glyphs: []GlyphPosition,
    stops: []const tab_ruler.Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    var size: f32 = 0;
    for (glyphs, 0..) |*glyph, glyph_index| {
        if (glyph.isActiveTab()) {
            glyph.y_advance = resolvedAdvance(
                glyphs,
                glyph_index,
                size,
                stops,
                fallback_interval,
                fallback_advance,
            );
        }
        size += glyph.y_advance;
    }
    return size;
}

pub fn measureRange(
    glyphs: []const GlyphPosition,
    stops: []const tab_ruler.Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    return measurePrefix(
        glyphs,
        glyphs.len,
        stops,
        fallback_interval,
        fallback_advance,
    );
}

/// Measure a visited prefix while resolving its tabs against complete
/// following fields in `glyphs`. Overflow scanning needs this lookahead for
/// center/end/decimal stops; final recomputation receives only the committed
/// column range and therefore truncates fields at the chosen boundary.
pub fn measurePrefix(
    glyphs: []const GlyphPosition,
    prefix_len: usize,
    stops: []const tab_ruler.Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    var size: f32 = 0;
    const end = @min(prefix_len, glyphs.len);
    for (glyphs[0..end], 0..) |glyph, glyph_index| {
        const glyph_advance = if (glyph.isActiveTab())
            resolvedAdvance(
                glyphs,
                glyph_index,
                size,
                stops,
                fallback_interval,
                fallback_advance,
            )
        else
            glyph.y_advance;
        size += glyph_advance;
    }
    return size;
}

pub fn contains(glyphs: []const GlyphPosition) bool {
    for (glyphs) |glyph| {
        if (glyph.isActiveTab()) return true;
    }
    return false;
}

fn resolvedAdvance(
    glyphs: []const GlyphPosition,
    glyph_index: usize,
    current_advance: f32,
    stops: []const tab_ruler.Stop,
    fallback_interval: f32,
    fallback_advance: f32,
) f32 {
    const stop = tab_ruler.nextExplicitStop(current_advance, stops);
    return tab_ruler.advance(
        current_advance,
        stops,
        fallback_interval,
        fallback_advance,
        measureField(
            glyphs,
            glyph_index + 1,
            if (stop) |item| item.decimal_point else '.',
        ),
    );
}

fn measureField(
    glyphs: []const GlyphPosition,
    start: usize,
    decimal_point: u21,
) tab_ruler.Field {
    var total: f32 = 0;
    var before_decimal: ?f32 = null;
    var index = start;
    while (index < glyphs.len) : (index += 1) {
        const glyph = glyphs[index];
        if (glyph.isActiveTab() or isMandatoryBreak(glyph.codepoint)) break;
        if (before_decimal == null and glyph.codepoint == decimal_point) {
            before_decimal = total;
        }
        total += glyph.y_advance;
    }
    return .{
        .total_width = total,
        .before_decimal_width = before_decimal,
    };
}

fn isMandatoryBreak(codepoint: u21) bool {
    return switch (@import("../../../unicode.zig").lineBreakClassForCodepoint(
        codepoint,
    )) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

test "vertical field recomputation is idempotent" {
    const std = @import("std");
    var glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .x_advance = 0,
            .y_advance = 20,
        },
        tab_ruler.marker(1),
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 2,
            .x_advance = 0,
            .y_advance = 20,
        },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 80),
        recomputeRange(&glyphs, &.{.{ .position = 60 }}, 40, 20),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        glyphs[1].y_advance,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 80),
        recomputeRange(&glyphs, &.{.{ .position = 60 }}, 40, 20),
        0.001,
    );
}

test "vertical prefix measurement sees complete aligned fields" {
    const std = @import("std");
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .x_advance = 0,
            .y_advance = 20,
        },
        tab_ruler.marker(1),
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 2,
            .x_advance = 0,
            .y_advance = 20,
        },
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 3,
            .x_advance = 0,
            .y_advance = 20,
        },
    };
    // The complete 40-unit field ends at stop 80, so its start is 40 and the
    // visited A+TAB prefix measures 20+20. Measuring only the visited prefix
    // would incorrectly treat the field as empty and produce 80.
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        measurePrefix(
            &glyphs,
            2,
            &.{.{ .position = 80, .alignment = .end }},
            40,
            20,
        ),
        0.001,
    );
}
