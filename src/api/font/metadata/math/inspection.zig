//! OpenType MATH table inspection for formula layout engines.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");
const glyph = @import("../../../../glyph.zig");

pub const View = struct {
    face: *const face_mod.Face,

    fn implementation(self: View) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn table(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.MathInfo {
        return self.implementation().mathInfo(allocator);
    }

    pub fn freeTable(
        self: View,
        allocator: std.mem.Allocator,
        info: font.MathInfo,
    ) void {
        self.implementation().freeMathInfo(allocator, info);
    }

    pub fn constant(
        self: View,
        selector: font.MathConstant,
    ) font.FontError!?i32 {
        return self.implementation().mathConstantRaw(selector);
    }

    pub fn italicsCorrection(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?font.MathValueRecordInfo {
        return self.implementation().mathItalicsCorrection(glyph_id);
    }

    pub fn topAccentAttachment(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!?font.MathValueRecordInfo {
        return self.implementation().mathTopAccentAttachment(glyph_id);
    }

    pub fn isExtendedShape(
        self: View,
        glyph_id: glyph.GlyphId,
    ) font.FontError!bool {
        return self.implementation().mathIsExtendedShape(glyph_id);
    }

    pub fn variants(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        vertical: bool,
    ) font.FontError!?[]font.MathVariantRecordInfo {
        return self.implementation().mathGlyphVariants(
            allocator,
            glyph_id,
            vertical,
        );
    }

    pub fn freeVariants(
        self: View,
        allocator: std.mem.Allocator,
        variants_value: []font.MathVariantRecordInfo,
    ) void {
        self.implementation().freeMathGlyphVariants(
            allocator,
            variants_value,
        );
    }

    pub fn assemblyParts(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        vertical: bool,
    ) font.FontError!?[]font.MathPartRecordInfo {
        return self.implementation().mathGlyphAssemblyParts(
            allocator,
            glyph_id,
            vertical,
        );
    }

    pub fn freeAssemblyParts(
        self: View,
        allocator: std.mem.Allocator,
        parts: []font.MathPartRecordInfo,
    ) void {
        self.implementation().freeMathGlyphAssemblyParts(allocator, parts);
    }

    pub fn assemblyItalicsCorrection(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        vertical: bool,
    ) font.FontError!?font.MathValueRecordInfo {
        return self.implementation().mathGlyphAssemblyItalicsCorrection(
            allocator,
            glyph_id,
            vertical,
        );
    }

    pub fn kernValue(
        self: View,
        allocator: std.mem.Allocator,
        glyph_id: glyph.GlyphId,
        corner: font.MathKernCorner,
        correction_height: i16,
    ) font.FontError!?i16 {
        return self.implementation().mathKernValue(
            allocator,
            glyph_id,
            corner,
            correction_height,
        );
    }
};

pub fn inspect(face: *const face_mod.Face) View {
    return .{ .face = face };
}
