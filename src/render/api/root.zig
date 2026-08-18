//! Public rendering facade over the internal CPU rasterizer.
//!
//! The wrapper accepts public font faces and shaping results. These are concrete
//! Zig source-level types; internal paint traversal stays in `raster.zig`.

const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const hinting_outline = @import("../../font/hinting/outline.zig");
const glyph_mod = @import("../../glyph.zig");
const run_types = @import("../../layout/types/runs.zig");
const raster = @import("../../raster.zig");

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
