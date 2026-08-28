//! Stable source-level API for parsed faces and common capability views.
//!
//! `Face` is a concrete Zig type rather than an ABI-oriented hidden handle.
//! Its focused method set still keeps parser-only operations out of normal
//! application completion lists.

const std = @import("std");

const font_mod = @import("../../font.zig");
const Font = font_mod.Font;
const attributes_mod = @import("attributes.zig");

pub const Attributes = attributes_mod.Attributes;
pub const Stretch = attributes_mod.Stretch;
pub const Style = attributes_mod.Style;
pub const Weight = attributes_mod.Weight;

pub const Properties = @import("properties.zig").Properties;

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

    /// Return classification attributes for the default font instance.
    pub fn attributes(self: *const Face) font_mod.FontError!Attributes {
        return attributes_mod.readImmutableFace(&self.implementation);
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

    /// Bind one normalized variable-font location to all common glyph views.
    ///
    /// The location and face are borrowed. This removes repeated coordinate
    /// plumbing across bounds, outlines, metrics, origins, and color paints
    /// while keeping raw Face views available for callers that vary per glyph.
    pub fn at(
        self: *const Face,
        normalized_coords: []const f32,
    ) Instance {
        return .{
            .face = self,
            .normalized_coords = normalized_coords,
        };
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

    /// Execute TrueType size programs with explicit interpreter semantics.
    pub fn hintingInstanceWithOptions(
        self: *const Face,
        allocator: std.mem.Allocator,
        ppem: u16,
        options: font_mod.TrueTypeHintingOptions,
    ) (font_mod.FontError || @import("../hinting/root.zig").Error)!font_mod.TrueTypeHintingInstance {
        return self.implementation.hintingInstanceWithOptions(
            allocator,
            ppem,
            options,
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

    /// Execute size programs at a location and explicit interpreter mode.
    pub fn hintingInstanceAtWithOptions(
        self: *const Face,
        allocator: std.mem.Allocator,
        ppem: u16,
        options: font_mod.TrueTypeHintingOptions,
        normalized_coords: []const f32,
    ) (font_mod.FontError || @import("../hinting/root.zig").Error)!font_mod.TrueTypeHintingInstance {
        return self.implementation.hintingInstanceAtWithOptions(
            allocator,
            ppem,
            options,
            normalized_coords,
        );
    }

    /// Decode a simple or compound glyf into raw 26.6 point state.
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

    /// Construct a reusable CFF/CFF2 stem-hinting instance for one PPEM.
    pub fn type2HintingInstance(
        self: *const Face,
        ppem: u16,
    ) font_mod.Type2HintingError!font_mod.Type2HintingInstance {
        return self.implementation.type2HintingInstance(ppem);
    }

    /// Decode and grid-fit one CFF/CFF2 outline at the requested location.
    pub fn type2HintedOutline(
        self: *const Face,
        allocator: std.mem.Allocator,
        instance: *const font_mod.Type2HintingInstance,
        glyph_id: @import("../../glyph.zig").GlyphId,
        normalized_coords: []const f32,
    ) (font_mod.FontError || font_mod.Type2HintingError)!font_mod.TrueTypePixelOutline {
        return self.implementation.type2HintedOutline(
            allocator,
            instance,
            glyph_id,
            normalized_coords,
        );
    }
};

pub const Instance = struct {
    face: *const Face,
    normalized_coords: []const f32,

    pub fn glyphs(self: Instance) InstanceGlyphs {
        return .{ .instance = self };
    }

    pub fn metrics(self: Instance) InstanceMetrics {
        return .{ .instance = self };
    }

    pub fn color(self: Instance) InstanceColor {
        return .{ .instance = self };
    }
};

pub const InstanceGlyphs = struct {
    instance: Instance,

    pub fn bounds(self: InstanceGlyphs, glyph_id: @import("../../glyph.zig").GlyphId) font_mod.FontError!@import("../../glyph.zig").Bounds {
        return self.instance.face.glyphs().boundsAt(
            glyph_id,
            self.instance.normalized_coords,
        );
    }

    pub fn extents(self: InstanceGlyphs, glyph_id: @import("../../glyph.zig").GlyphId) font_mod.FontError!@import("../../glyph.zig").Extents {
        return self.instance.face.glyphs().extentsAt(
            glyph_id,
            self.instance.normalized_coords,
        );
    }

    pub fn outline(
        self: InstanceGlyphs,
        allocator: std.mem.Allocator,
        glyph_id: @import("../../glyph.zig").GlyphId,
    ) font_mod.FontError!@import("../../glyph.zig").GlyphOutline {
        return self.instance.face.glyphs().outlineAt(
            allocator,
            glyph_id,
            self.instance.normalized_coords,
        );
    }
};

pub const InstanceMetrics = struct {
    instance: Instance,

    pub fn horizontal(self: InstanceMetrics, glyph_id: @import("../../glyph.zig").GlyphId) font_mod.FontError!font_mod.HorizontalMetricInfo {
        return self.instance.face.metrics().horizontalAt(
            glyph_id,
            self.instance.normalized_coords,
        );
    }

    pub fn vertical(self: InstanceMetrics, glyph_id: @import("../../glyph.zig").GlyphId) font_mod.FontError!?font_mod.VerticalMetrics {
        return self.instance.face.metrics().verticalAt(
            glyph_id,
            self.instance.normalized_coords,
        );
    }

    pub fn shapingVerticalOrigin(self: InstanceMetrics, glyph_id: @import("../../glyph.zig").GlyphId) font_mod.FontError!i32 {
        return self.instance.face.metrics().shapingVerticalOrigin(
            glyph_id,
            self.instance.normalized_coords,
        );
    }
};

pub const InstanceColor = struct {
    instance: Instance,

    pub fn paint(self: InstanceColor, glyph_id: @import("../../glyph.zig").GlyphId) font_mod.FontError!?font_mod.ColorPaint {
        return self.instance.face.color().paint(
            glyph_id,
            self.instance.normalized_coords,
        );
    }

    pub fn clip(self: InstanceColor, glyph_id: @import("../../glyph.zig").GlyphId) font_mod.FontError!?font_mod.ColorClipBox {
        return self.instance.face.color().clip(
            glyph_id,
            self.instance.normalized_coords,
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
pub const GlyphSession = @import("views/glyphs.zig").Session;
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
