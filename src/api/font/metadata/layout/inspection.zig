//! OpenType and cross-platform layout-table inspection.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");
const glyph = @import("../../../../glyph.zig");

pub const View = struct {
    face: *const face_mod.Face,

    fn implementation(self: View) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn baseline(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.BaseInfo {
        return self.implementation().baseInfo(allocator);
    }

    pub fn freeBaseline(
        self: View,
        allocator: std.mem.Allocator,
        info: font.BaseInfo,
    ) void {
        self.implementation().freeBaseInfo(allocator, info);
    }

    pub fn glyphClass(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!font.GlyphClass {
        return self.implementation().glyphClass(glyph_id);
    }

    pub fn glyphsInClass(
        self: View,
        allocator: std.mem.Allocator,
        class: font.GlyphClass,
    ) font.FontError![]glyph.GlyphId {
        return self.implementation().glyphsInClass(allocator, class);
    }

    pub fn markAttachClass(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!u16 {
        return self.implementation().markAttachClass(glyph_id);
    }

    pub fn attachmentPoints(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
    ) font.FontError![]font.AttachmentPoint {
        return self.implementation().attachmentPoints(allocator, glyph_id);
    }

    pub fn ligatureCarets(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError![]font.LigatureCaret {
        // This is the same defensive read exposed on `Face.glyphs()`, kept
        // here so layout-table inspection remains a complete GDEF surface.
        return self.implementation().ligatureCarets(
            allocator,
            glyph_id,
            normalized_coords,
        );
    }

    pub fn markGlyphSetCount(self: View) font.FontError!usize {
        return self.implementation().markGlyphSetCount();
    }

    pub fn markGlyphSet(
        self: View,
        allocator: std.mem.Allocator,
        set_index: usize,
    ) font.FontError![]glyph.GlyphId {
        return self.implementation().markGlyphSet(allocator, set_index);
    }

    pub fn kerning(
        self: View,
        left: glyph.GlyphId,
        right: glyph.GlyphId,
    ) font.FontError!i16 {
        return self.implementation().kerning(left, right);
    }

    pub fn kern(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.KernInfo {
        return self.implementation().kernInfo(allocator);
    }

    pub fn freeKern(
        self: View,
        allocator: std.mem.Allocator,
        info: font.KernInfo,
    ) void {
        self.implementation().freeKernInfo(allocator, info);
    }

    pub fn justification(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.JstfInfo {
        return self.implementation().jstfInfo(allocator);
    }

    pub fn freeJustification(
        self: View,
        allocator: std.mem.Allocator,
        info: font.JstfInfo,
    ) void {
        self.implementation().freeJstfInfo(allocator, info);
    }

    pub fn cff2(self: View) font.FontError!?font.Cff2Info {
        return self.implementation().cff2Info();
    }

    pub fn cff2FontDictionary(
        self: View,
        index: usize,
    ) font.FontError!?font.Cff2FontDictInfo {
        return self.implementation().cff2FontDictInfo(index);
    }

    pub fn cff2FontDictionaryForGlyph(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?u16 {
        return self.implementation().cff2FontDictIndex(glyph_id);
    }

    pub fn cff2CharString(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?[]const u8 {
        return self.implementation().cff2CharStringData(glyph_id);
    }

    pub fn cff2CharStringScan(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?font.Cff2CharStringScanInfo {
        return self.implementation().cff2CharStringScanInfo(glyph_id);
    }

    pub fn cff2CharStringBounds(
        self: View,
        glyph_id: glyph.GlyphId,
        normalized_coords: []const f32,
    ) font.FontError!?font.Cff2CharStringBoundsInfo {
        return self.implementation().cff2CharStringBoundsInfoAtCoords(
            glyph_id,
            normalized_coords,
        );
    }

    pub fn languageTags(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError![]font.LtagRecordInfo {
        return self.implementation().ltagRecords(allocator);
    }
};

pub fn inspect(face: *const face_mod.Face) View {
    return .{ .face = face };
}
