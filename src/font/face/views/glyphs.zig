//! Character mapping, glyph geometry, and outline access.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const glyph_mod = @import("../../../glyph.zig");

pub const View = struct {
    /// Borrowed source-level view backing; use the methods below.
    implementation: *const font_mod.Font,

    pub fn index(
        self: View,
        codepoint: u21,
    ) font_mod.FontError!glyph_mod.GlyphId {
        return self.implementation.glyphIndex(codepoint);
    }

    pub fn indexForVariation(
        self: View,
        codepoint: u21,
        selector: u21,
    ) font_mod.FontError!glyph_mod.GlyphId {
        return self.implementation.glyphIndexWithVariation(
            codepoint,
            selector,
        );
    }

    pub fn variationKind(
        self: View,
        codepoint: u21,
        selector: u21,
    ) font_mod.FontError!?font_mod.VariationSequenceKind {
        return self.implementation.variationSequenceKind(
            codepoint,
            selector,
        );
    }

    pub fn hasOutlines(self: View) bool {
        return self.implementation.hasOutlineData();
    }

    pub fn bounds(
        self: View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!glyph_mod.Bounds {
        return self.implementation.glyphBounds(glyph_id);
    }

    /// Read bounds using the validation proof established by Face.parse.
    ///
    /// The face's source bytes must remain unchanged for its complete lifetime.
    /// Font services and retained rendering scenes satisfy that contract; code
    /// that permits post-parse byte mutation must use `bounds` instead.
    pub fn boundsTrusted(
        self: View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!glyph_mod.Bounds {
        return font_mod.immutable_face_backend.glyphBounds(
            self.implementation,
            glyph_id,
        );
    }

    pub fn boundsAt(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!glyph_mod.Bounds {
        return self.implementation.glyphBoundsAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn outline(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!glyph_mod.GlyphOutline {
        return self.implementation.glyphOutline(allocator, glyph_id);
    }

    pub fn outlineAt(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!glyph_mod.GlyphOutline {
        return self.implementation.glyphOutlineAtCoords(
            allocator,
            glyph_id,
            normalized_coords,
        );
    }

    pub fn name(
        self: View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?[]const u8 {
        return self.implementation.glyphName(glyph_id);
    }
};
