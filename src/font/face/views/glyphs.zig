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
        return font_mod.immutable_face_backend.glyphIndex(
            self.implementation,
            codepoint,
        );
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

    /// Create a lightweight outline-decoding session for immutable face bytes.
    ///
    /// `Face.parse` already proves whole-table grammar and checksums. The
    /// ordinary `outline` methods deliberately repeat those borrowed-byte
    /// checks so post-parse mutation is reported. A session instead reuses the
    /// parse proof for atlas construction and other trusted, repeated outline
    /// reads. The caller must keep both the face and its borrowed source bytes
    /// alive and unchanged for the complete session lifetime.
    pub fn session(self: View) Session {
        return .{ .implementation = self.implementation };
    }

    pub fn name(
        self: View,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!?[]const u8 {
        return self.implementation.glyphName(glyph_id);
    }

    /// Return a usable glyph name from post, CFF1, or `gidNNN` synthesis.
    ///
    /// Names borrowed from the face ignore `out`; synthesized names live in
    /// `out` and remain valid until the caller reuses that storage. Use `name`
    /// when the nullable, raw post-table result is specifically required.
    pub fn resolvedName(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        out: []u8,
    ) font_mod.FontError![]const u8 {
        return font_mod.immutable_face_backend.resolvedGlyphName(
            self.implementation,
            glyph_id,
            out,
        );
    }

    /// Return the resolved name together with its chosen source.
    pub fn resolvedNameInfo(
        self: View,
        glyph_id: glyph_mod.GlyphId,
        out: []u8,
    ) font_mod.FontError!font_mod.ResolvedGlyphName {
        return font_mod.immutable_face_backend.resolvedGlyphNameInfo(
            self.implementation,
            glyph_id,
            out,
        );
    }

    pub fn inClass(
        self: View,
        allocator: std.mem.Allocator,
        class: font_mod.GlyphClass,
    ) font_mod.FontError![]glyph_mod.GlyphId {
        return self.implementation.glyphsInClass(allocator, class);
    }

    /// Return allocator-owned GDEF attachment contour-point indexes.
    pub fn attachmentPoints(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError![]font_mod.AttachmentPoint {
        return self.implementation.attachmentPoints(allocator, glyph_id);
    }

    /// Return allocator-owned GDEF ligature caret positions in design units.
    ///
    /// An empty slice means the glyph is uncovered or its authored contour
    /// point/order cannot be resolved safely at this variation instance.
    pub fn ligatureCarets(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError![]font_mod.LigatureCaret {
        return self.implementation.ligatureCarets(
            allocator,
            glyph_id,
            normalized_coords,
        );
    }
};

/// Borrowed parsed-face proof for repeated outline decoding.
pub const Session = struct {
    implementation: *const font_mod.Font,

    pub fn outline(
        self: Session,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) font_mod.FontError!glyph_mod.GlyphOutline {
        return font_mod.raster_backend.glyphOutline(
            self.implementation,
            allocator,
            glyph_id,
        );
    }

    pub fn outlineAt(
        self: Session,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) font_mod.FontError!glyph_mod.GlyphOutline {
        return font_mod.raster_backend.glyphOutlineAtCoords(
            self.implementation,
            allocator,
            glyph_id,
            normalized_coords,
        );
    }
};
