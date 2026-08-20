//! Optical punctuation hanging along the vertical positive-down inline axis.
//!
//! Glyph advances and caret geometry remain untouched. Only the occupied
//! column height and its aligned origin change; the final punctuation ink can
//! therefore protrude below the line box exactly as horizontal punctuation
//! protrudes beyond its occupied width.

const punctuation_hanging = @import("../punctuation/hanging.zig");
const paragraph_options = @import("options.zig");
const vertical_inline_region = @import("vertical_inline_region.zig");

pub fn apply(
    buffer: anytype,
    options: paragraph_options.Options,
) void {
    for (buffer.lines.items) |*line| {
        const glyph_end = line.glyph_start + line.glyph_len;
        const glyphs = buffer.glyphs.items[line.glyph_start..glyph_end];
        var full_height: f32 = 0;
        for (glyphs) |glyph| full_height += glyph.y_advance;

        line.hang_start = 0;
        line.hang_end = punctuation_hanging.verticalVisualEndAmount(
            glyphs,
            options.punctuation.end_hanging_fraction,
        );
        line.height = @max(0, full_height - line.hang_end);
        line.y = vertical_inline_region.origin(
            line.*,
            options,
            line.height,
        );
    }
}
