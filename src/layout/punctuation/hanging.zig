//! Optical line-end punctuation hanging.
//!
//! Hanging changes occupied line measure without changing shaped advances,
//! source spans, or caret positions. Eligibility is intentionally based on
//! Unicode line-break class plus the generated East Asian property rather than an
//! application-specific language guess.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const geometry = @import("../line_break/reflow/geometry.zig");
const unicode = @import("../../unicode.zig");
const line_break_properties =
    @import("../../unicode/line_break/properties.zig");

/// Return the advance that can be ignored for line fitting/justification at
/// the logical inline end. Reflow still retains the full glyph advance.
pub fn logicalEndAmount(
    glyphs: []const GlyphPosition,
    glyph_start: usize,
    glyph_end: usize,
    fraction: f32,
) f32 {
    if (fraction <= 0 or glyph_end <= glyph_start + 1) return 0;
    const glyph = glyphs[glyph_end - 1];
    if (!isEligible(glyph)) return 0;
    return @max(0, glyph.x_advance) * fraction;
}

/// Recompute physical hanging sides after bidi and truncation have established
/// each line's final visual edge.
pub fn apply(buffer: anytype, options: anytype) void {
    const fraction = options.punctuation.end_hanging_fraction;
    if (buffer.lines.items.len == 0) return;
    const max_width = if (options.max_width > 0)
        options.max_width
    else
        std.math.inf(f32);
    const alignment = geometry.resolvedAlignment(options);
    for (buffer.lines.items) |*line| {
        // Recompute from the full advance sum. This makes the operation
        // idempotent and also repairs the occupied width after ellipsis or
        // another post-reflow glyph-tail transformation.
        const line_end = line.glyph_start + line.glyph_len;
        const full_width = geometry.lineWidth(
            buffer.glyphs.items[line.glyph_start..line_end],
        );
        line.hang_start = 0;
        line.hang_end = 0;
        var amount: f32 = 0;
        if (fraction > 0 and line_end > line.glyph_start + 1) {
            const glyph_index = if (options.direction == .rtl)
                line.glyph_start
            else
                line_end - 1;
            const glyph = buffer.glyphs.items[glyph_index];
            if (isEligible(glyph)) {
                amount = @max(0, glyph.x_advance) * fraction;
                if (options.direction == .rtl) {
                    line.hang_start = amount;
                } else {
                    line.hang_end = amount;
                }
            }
        }
        line.width = @max(0, full_width - amount);
        const available_width = geometry.lineWidthLimitForIndent(
            max_width,
            line.indent,
        );
        const occupied_x = line.indent + geometry.alignedLineX(
            line.width,
            available_width,
            alignment,
        );
        // `line.x` remains the origin of the first physical glyph. The occupied
        // measure starts after any punctuation protruding from the left edge.
        line.x = occupied_x - line.hang_start;
    }
}

fn isEligible(glyph: GlyphPosition) bool {
    if (glyph.isInlineObject() or glyph.isDiscretionaryHyphen()) return false;
    if (!line_break_properties.lookup(glyph.codepoint).east_asian) return false;
    return switch (unicode.lineBreakClassForCodepoint(glyph.codepoint)) {
        .close_punctuation,
        .close_parenthesis,
        .exclamation,
        .nonstarter,
        => true,
        else => false,
    };
}

test "eligible East Asian punctuation excludes ordinary Latin punctuation" {
    try std.testing.expect(isEligible(.{
        .glyph_id = 1,
        .codepoint = 0x3002,
        .cluster = 0,
        .x_advance = 10,
    }));
    try std.testing.expect(!isEligible(.{
        .glyph_id = 1,
        .codepoint = '.',
        .cluster = 0,
        .x_advance = 10,
    }));
    try std.testing.expect(!isEligible(.{
        .glyph_id = 1,
        .codepoint = 0x4e00,
        .cluster = 0,
        .x_advance = 10,
    }));
}
