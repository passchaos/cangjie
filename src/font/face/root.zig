//! Stable source-level API for parsed faces and common capability views.
//!
//! `Face` is a concrete Zig type rather than an ABI-oriented hidden handle.
//! Its focused method set still keeps parser-only operations out of normal
//! application completion lists.

const std = @import("std");

const font_mod = @import("../../font.zig");
const Font = font_mod.Font;

pub const Properties = struct {
    format: font_mod.FontFormat,
    units_per_em: u16,
    glyph_count: u16,
    ascender: i16,
    descender: i16,
    line_gap: i16,
};

/// A parsed, zero-copy font face.
///
/// The face owns parser bookkeeping but borrows the supplied SFNT/TTC bytes.
/// Those bytes must therefore remain alive and unchanged until `deinit`.
pub const Face = struct {
    /// Source-visible implementation storage, not a stable layout contract.
    /// `Face` deliberately contains it at offset zero so repository pipeline
    /// modules can reinterpret existing borrowed `Font` pointers without
    /// allocating facade objects.
    implementation: Font,

    /// Parse the first face in a standalone SFNT or collection.
    pub fn parse(
        allocator: std.mem.Allocator,
        data: []const u8,
    ) font_mod.FontError!Face {
        return parseIndex(allocator, data, 0);
    }

    /// Parse one zero-based face from a standalone SFNT or collection.
    pub fn parseIndex(
        allocator: std.mem.Allocator,
        data: []const u8,
        face_index: usize,
    ) font_mod.FontError!Face {
        return .{
            .implementation = try Font.parseFace(
                allocator,
                data,
                face_index,
            ),
        };
    }

    pub fn count(data: []const u8) font_mod.FontError!usize {
        return Font.faceCount(data);
    }

    pub fn deinit(self: *Face) void {
        self.implementation.deinit();
    }

    pub fn properties(self: *const Face) Properties {
        const implementation = &self.implementation;
        return .{
            .format = implementation.format,
            .units_per_em = implementation.units_per_em,
            .glyph_count = implementation.glyph_count,
            .ascender = implementation.ascender,
            .descender = implementation.descender,
            .line_gap = implementation.line_gap,
        };
    }

    pub fn glyphs(self: *const Face) Glyphs {
        return .{ .implementation = &self.implementation };
    }

    pub fn metrics(self: *const Face) Metrics {
        return .{ .implementation = &self.implementation };
    }

    pub fn names(self: *const Face) Names {
        return .{ .implementation = &self.implementation };
    }

    pub fn variations(self: *const Face) Variations {
        return .{ .implementation = &self.implementation };
    }

    pub fn color(self: *const Face) Color {
        return .{ .implementation = &self.implementation };
    }

    /// Execute TrueType `fpgm` and `prep` for one PPEM.
    pub fn hintingInstance(
        self: *const Face,
        allocator: std.mem.Allocator,
        ppem: u16,
        target: font_mod.TrueTypeHintingTarget,
    ) (font_mod.FontError || @import("../hinting/root.zig").Error)!font_mod.TrueTypeHintingInstance {
        return self.implementation.hintingInstance(
            allocator,
            ppem,
            target,
        );
    }

    /// Execute TrueType size programs at a complete normalized fvar location.
    pub fn hintingInstanceAt(
        self: *const Face,
        allocator: std.mem.Allocator,
        ppem: u16,
        target: font_mod.TrueTypeHintingTarget,
        normalized_coords: []const f32,
    ) (font_mod.FontError || @import("../hinting/root.zig").Error)!font_mod.TrueTypeHintingInstance {
        return self.implementation.hintingInstanceAt(
            allocator,
            ppem,
            target,
            normalized_coords,
        );
    }

    /// Decode a default-instance simple glyf into raw 26.6 point state.
    ///
    /// Glyph bytecode has not run; use the returned owner as the atomic input
    /// to point-zone execution and pixel-path reconstruction.
    pub fn hintingPointTransaction(
        self: *const Face,
        allocator: std.mem.Allocator,
        instance: *const font_mod.TrueTypeHintingInstance,
        glyph_id: @import("../../glyph.zig").GlyphId,
    ) (font_mod.FontError || @import("../hinting/root.zig").Error)!font_mod.TrueTypePointTransaction {
        return self.implementation.hintingPointTransaction(
            allocator,
            instance,
            glyph_id,
        );
    }

    /// Execute the transaction's glyph bytecode against this PPEM instance.
    ///
    /// The transaction and all mutable instance VM state commit together only
    /// after a successful run.
    pub fn executeHintingTransaction(
        self: *const Face,
        instance: *font_mod.TrueTypeHintingInstance,
        transaction: *font_mod.TrueTypePointTransaction,
    ) @import("../hinting/root.zig").Error!void {
        if (transaction.face_identity != @intFromPtr(&self.implementation)) {
            return error.StaleHintingInstance;
        }
        return instance.executeGlyph(
            transaction,
            .{
                .context = &self.implementation,
                .resolveFn = font_mod.resolveHintingComponentForExecution,
            },
        );
    }
};

/// An ordered fallback list. The slice and every face are borrowed.
pub const Cascade = struct {
    faces: []const *const Face,

    pub fn init(faces: []const *const Face) Cascade {
        return .{ .faces = faces };
    }

    pub fn len(self: Cascade) usize {
        return self.faces.len;
    }

    pub fn isEmpty(self: Cascade) bool {
        return self.faces.len == 0;
    }
};

pub const Glyphs = @import("views/glyphs.zig").View;
pub const Metrics = @import("views/metrics.zig").View;
pub const Names = @import("views/names.zig").View;
pub const Variations = @import("views/variations.zig").View;
pub const Color = @import("views/color.zig").View;

/// Internal conversion boundary shared by shaping, databases, and rendering.
///
/// `Face` is layout-compatible with its single implementation field. Slice
/// casts rewrite only pointer pointee types; no pointed-to bytes move.
pub const backend = struct {
    pub fn font(face_value: *const Face) *const Font {
        return &face_value.implementation;
    }

    pub fn fontMut(face_value: *Face) *Font {
        return &face_value.implementation;
    }

    pub fn face(font_value: *const Font) *const Face {
        return @ptrCast(font_value);
    }

    pub fn faceMut(font_value: *Font) *Face {
        return @ptrCast(font_value);
    }

    pub fn fonts(face_values: []const *const Face) []const *const Font {
        return @as(
            [*]const *const Font,
            @ptrCast(face_values.ptr),
        )[0..face_values.len];
    }

    pub fn faces(font_values: []const *const Font) []const *const Face {
        return @as(
            [*]const *const Face,
            @ptrCast(font_values.ptr),
        )[0..font_values.len];
    }
};

comptime {
    if (@offsetOf(Face, "implementation") != 0 or
        @sizeOf(Face) != @sizeOf(Font) or
        @alignOf(Face) != @alignOf(Font))
    {
        @compileError("Face backend conversions require a zero-offset Font");
    }
}
