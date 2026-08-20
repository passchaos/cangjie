//! Vertical paragraph advance refresh shared by layout and intrinsic sizing.
//!
//! Negative letter/word spacing is valid only while every final source atom
//! keeps a nonnegative positive-down advance. The caller applies white-space
//! collapse between `apply` and `validate`: collapsed blanks may legitimately
//! erase an otherwise-negative authored-space advance before wrapping.

const geometry = @import("../line_break/reflow/geometry.zig");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const inline_object = @import("../inline_object/root.zig");
const opportunities = @import("../line_break/reflow/opportunities.zig");
const paragraph_options = @import("options.zig");

pub fn apply(
    glyphs: []GlyphPosition,
    options: paragraph_options.Options,
) !void {
    for (glyphs) |*glyph| {
        if (opportunities.isMandatory(glyph.codepoint)) {
            // Separators own source/caret topology but do not consume column
            // height. Spacing never turns a hard break into visible advance.
            glyph.x_advance = 0;
            glyph.y_advance = 0;
            continue;
        }
        if (glyph.isInlineObject()) {
            const object = inline_object.find(
                options.inline_objects,
                glyph.cluster,
            ) orelse return error.InvalidInlineObjects;
            const in_flow = object.kind == .in_flow;
            glyph.x_advance = if (in_flow) object.width else 0;
            glyph.y_advance = if (in_flow) object.height else 0;
            continue;
        }
        if (glyph.isTab()) {
            // The selected column's tab ruler installs this advance later.
            // Styled and paragraph word/letter spacing never alters a tab.
            glyph.x_advance = 0;
            glyph.y_advance = 0;
            continue;
        }

        glyph.y_advance += geometry.spacingForGlyph(
            glyph.codepoint,
            options,
        );
    }
}

/// Prove the monotone inline-pen invariant after white-space normalization.
pub fn validate(glyphs: []const GlyphPosition) !void {
    for (glyphs) |glyph| {
        if (!@import("std").math.isFinite(glyph.y_advance) or
            glyph.y_advance < 0)
        {
            return error.InvalidParagraphOptions;
        }
    }
}
