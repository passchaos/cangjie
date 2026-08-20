//! Public rendering facade over the internal CPU rasterizer.
//!
//! The wrapper accepts public font faces and shaping results. These are concrete
//! Zig source-level types; internal paint traversal stays in `raster.zig`.

const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const font_mod = @import("../../font.zig");
const hinting_outline = @import("../../font/hinting/outline.zig");
const glyph_mod = @import("../../glyph.zig");
const run_types = @import("../../layout/types/runs.zig");
const raster = @import("../../raster.zig");
const run_geometry = @import("../run_geometry.zig");

pub const Rasterizer = struct {
    /// Source-visible implementation storage; its layout is not API-stable.
    implementation: raster.Rasterizer,

    pub fn init(allocator: std.mem.Allocator) Rasterizer {
        return .{
            .implementation = raster.Rasterizer.init(allocator),
        };
    }

    pub fn deinit(self: *Rasterizer) void {
        self.* = undefined;
    }

    pub fn setSampling(self: *Rasterizer, samples_per_axis: u8) void {
        self.implementation.samples_per_axis = samples_per_axis;
    }

    pub fn setHintSize(self: *Rasterizer, size_px: ?f32) void {
        self.implementation.hint_size_px = size_px;
    }

    pub fn setSmallGlyphEmboldening(
        self: *Rasterizer,
        enabled: bool,
    ) void {
        self.implementation.embolden_small_glyphs = enabled;
    }

    pub fn prepare(
        self: *Rasterizer,
        outline: *const glyph_mod.GlyphOutline,
        x: f32,
        baseline_y: f32,
        font_size: f32,
        units_per_em: u16,
    ) !Prepared {
        const implementation = &self.implementation;
        return .{
            .glyph = try implementation.prepareGlyph(
                outline,
                x,
                baseline_y,
                font_size,
                units_per_em,
            ),
        };
    }

    /// Prepare already-hinted pixel geometry for repeated drawing.
    ///
    /// Only `x` and `baseline_y` placement is applied. The outline must not be
    /// scaled by font size or units-per-em again.
    pub fn preparePixelOutline(
        self: *Rasterizer,
        outline: *const hinting_outline.PixelOutline,
        x: f32,
        baseline_y: f32,
    ) !Prepared {
        return .{
            .glyph = try self.implementation.preparePixelOutline(
                outline,
                x,
                baseline_y,
            ),
        };
    }

    pub fn drawPrepared(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        prepared: *const Prepared,
    ) !void {
        return self.implementation.renderPreparedGlyph(
            target,
            &prepared.glyph,
        );
    }

    pub fn drawOutline(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        outline: *const glyph_mod.GlyphOutline,
        x: f32,
        baseline_y: f32,
        font_size: f32,
        units_per_em: u16,
    ) !void {
        return self.implementation.renderGlyph(
            target,
            outline,
            x,
            baseline_y,
            font_size,
            units_per_em,
        );
    }

    /// Draw already-hinted pixel geometry without a second font-unit scale.
    pub fn drawPixelOutline(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        outline: *const hinting_outline.PixelOutline,
        x: f32,
        baseline_y: f32,
    ) !void {
        return self.implementation.renderPixelOutline(
            target,
            outline,
            x,
            baseline_y,
        );
    }

    /// Decode, execute, and draw one TrueType glyph with a caller-owned PPEM
    /// instance.
    ///
    /// The instance supplies size, target, variation location, and persistent
    /// VM state. Coordinates reconstructed from the transaction are already
    /// pixels, so this path applies only x/baseline placement.
    pub fn drawHintedGlyph(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        face: *const face_mod.Face,
        instance: *font_mod.TrueTypeHintingInstance,
        glyph_id: glyph_mod.GlyphId,
        x: f32,
        baseline_y: f32,
    ) !void {
        var transaction = try face.hintingPointTransaction(
            self.implementation.allocator,
            instance,
            glyph_id,
        );
        defer transaction.deinit();
        try face.executeHintingTransaction(instance, &transaction);
        var outline = try transaction.toPixelOutline();
        defer outline.deinit();
        return self.drawPixelOutline(target, &outline, x, baseline_y);
    }

    /// Decode, Type2-grid-fit, and draw one CFF/CFF2 glyph.
    pub fn drawType2HintedGlyph(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        face: *const face_mod.Face,
        instance: *const font_mod.Type2HintingInstance,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
        x: f32,
        baseline_y: f32,
    ) !void {
        var outline = try face.type2HintedOutline(
            self.implementation.allocator,
            instance,
            glyph_id,
            normalized_coords,
        );
        defer outline.deinit();
        return self.drawPixelOutline(target, &outline, x, baseline_y);
    }

    fn drawHintedGlyphOriented(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        face: *const face_mod.Face,
        instance: *font_mod.TrueTypeHintingInstance,
        glyph_id: glyph_mod.GlyphId,
        x: f32,
        baseline_y: f32,
        orientation: @import("../run_geometry.zig").RasterOrientation,
    ) !void {
        var transaction = try face.hintingPointTransaction(
            self.implementation.allocator,
            instance,
            glyph_id,
        );
        defer transaction.deinit();
        try face.executeHintingTransaction(instance, &transaction);
        var outline = try transaction.toPixelOutline();
        defer outline.deinit();
        return self.implementation.renderPixelOutlineOriented(
            target,
            &outline,
            x,
            baseline_y,
            orientation,
        );
    }

    /// Draw a shaped run using one caller-owned hinting instance.
    ///
    /// Shaping retains ownership of advances and offsets; only outline
    /// geometry is grid-fitted. The run and instance must describe the same
    /// normalized variation location. A run may omit trailing zero axes.
    pub fn drawHintedRun(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        run: run_types.GlyphRun,
        instance: *font_mod.TrueTypeHintingInstance,
        x: f32,
        baseline_y: f32,
    ) !void {
        if (!std.math.isFinite(run.font_size) or
            run.font_size != @as(f32, @floatFromInt(instance.ppem)))
        {
            return error.StaleHintingInstance;
        }
        if (!locationsEquivalent(
            run.normalized_variation_coords,
            instance.normalizedCoordinates(),
        )) {
            return error.StaleHintingInstance;
        }
        var pen = run_geometry.Pen.init(x, baseline_y);
        for (run.glyphs) |position| {
            if (!position.isInlineObject()) {
                const origin = pen.glyphOrigin(position);
                try self.drawHintedGlyphOriented(
                    target,
                    run.font,
                    instance,
                    position.glyph_id,
                    origin.x,
                    origin.baseline_y,
                    run_geometry.rasterOrientation(position),
                );
            }
            pen.advance(position);
        }
    }

    pub fn drawRun(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        run: run_types.GlyphRun,
        x: f32,
        baseline_y: f32,
    ) !void {
        return self.implementation.renderRun(target, run, x, baseline_y);
    }

    pub fn drawRunAt(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        run: run_types.GlyphRun,
        x: f32,
        baseline_y: f32,
        normalized_coords: []const f32,
    ) !void {
        return self.implementation.renderRunAtCoords(
            target,
            run,
            x,
            baseline_y,
            normalized_coords,
        );
    }

    pub fn drawText(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        shaped: run_types.ShapedText,
        x: f32,
        baseline_y: f32,
    ) !void {
        return self.implementation.renderShapedText(
            target,
            shaped,
            x,
            baseline_y,
        );
    }

    pub fn drawColorRun(
        self: *Rasterizer,
        target: *raster.ColorRenderTarget,
        run: run_types.GlyphRun,
        x: f32,
        baseline_y: f32,
        palette_index: u16,
    ) !void {
        return self.implementation.renderColorRun(
            target,
            run,
            x,
            baseline_y,
            palette_index,
        );
    }

    pub fn drawColorGlyph(
        self: *Rasterizer,
        target: *raster.ColorRenderTarget,
        face: *const face_mod.Face,
        glyph_id: glyph_mod.GlyphId,
        font_size: f32,
        x: f32,
        baseline_y: f32,
        palette_index: u16,
    ) !void {
        return self.implementation.renderColorGlyph(
            target,
            face_mod.backend.font(face),
            glyph_id,
            font_size,
            x,
            baseline_y,
            palette_index,
        );
    }

    pub fn drawColorGlyphAt(
        self: *Rasterizer,
        target: *raster.ColorRenderTarget,
        face: *const face_mod.Face,
        glyph_id: glyph_mod.GlyphId,
        font_size: f32,
        x: f32,
        baseline_y: f32,
        palette_index: u16,
        normalized_coords: []const f32,
    ) !void {
        return self.implementation.renderColorGlyphAtCoords(
            target,
            face_mod.backend.font(face),
            glyph_id,
            font_size,
            x,
            baseline_y,
            palette_index,
            normalized_coords,
        );
    }
};

fn locationsEquivalent(first: []const f32, second: []const f32) bool {
    const common = @min(first.len, second.len);
    for (first[0..common], second[0..common]) |a, b| {
        if (@as(u32, @bitCast(a)) != @as(u32, @bitCast(b))) return false;
    }
    for (first[common..]) |value| {
        if (value != 0) return false;
    }
    for (second[common..]) |value| {
        if (value != 0) return false;
    }
    return true;
}

pub const Prepared = struct {
    /// Prepared geometry owns its scanline storage and can outlive the
    /// rasterizer that created it.
    glyph: raster.PreparedGlyph,

    pub fn recommendedForRepeatedRendering(self: *const Prepared) bool {
        return self.glyph.recommendedForRepeatedRendering();
    }

    pub fn deinit(self: *Prepared) void {
        self.glyph.deinit();
        self.* = undefined;
    }
};
