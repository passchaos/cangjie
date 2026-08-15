//! Public rendering facade over the internal CPU rasterizer.
//!
//! The wrapper accepts opaque font faces and public shaping results. Internal
//! paint traversal and parsed-font fast paths stay in `raster.zig`.

const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const glyph_mod = @import("../../glyph.zig");
const layout = @import("../../layout.zig");
const raster = @import("../../raster.zig");

pub const Rasterizer = opaque {
    pub fn init(allocator: std.mem.Allocator) !*Rasterizer {
        const implementation = try allocator.create(raster.Rasterizer);
        implementation.* = raster.Rasterizer.init(allocator);
        return @ptrCast(implementation);
    }

    pub fn deinit(self: *Rasterizer) void {
        const implementation = impl(self);
        const allocator = implementation.allocator;
        allocator.destroy(implementation);
    }

    pub fn setSampling(self: *Rasterizer, samples_per_axis: u8) void {
        impl(self).samples_per_axis = samples_per_axis;
    }

    pub fn setHintSize(self: *Rasterizer, size_px: ?f32) void {
        impl(self).hint_size_px = size_px;
    }

    pub fn setSmallGlyphEmboldening(
        self: *Rasterizer,
        enabled: bool,
    ) void {
        impl(self).embolden_small_glyphs = enabled;
    }

    pub fn prepare(
        self: *Rasterizer,
        outline: *const glyph_mod.GlyphOutline,
        x: f32,
        baseline_y: f32,
        font_size: f32,
        units_per_em: u16,
    ) !*Prepared {
        const implementation = impl(self);
        const prepared = try implementation.allocator.create(PreparedImpl);
        errdefer implementation.allocator.destroy(prepared);
        prepared.* = .{
            .allocator = implementation.allocator,
            .glyph = try implementation.prepareGlyph(
                outline,
                x,
                baseline_y,
                font_size,
                units_per_em,
            ),
        };
        return @ptrCast(prepared);
    }

    pub fn drawPrepared(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        prepared: *const Prepared,
    ) !void {
        return impl(self).renderPreparedGlyph(
            target,
            &preparedImpl(prepared).glyph,
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
        return impl(self).renderGlyph(
            target,
            outline,
            x,
            baseline_y,
            font_size,
            units_per_em,
        );
    }

    pub fn drawRun(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        run: layout.GlyphRun,
        x: f32,
        baseline_y: f32,
    ) !void {
        return impl(self).renderRun(target, run, x, baseline_y);
    }

    pub fn drawRunAt(
        self: *Rasterizer,
        target: *raster.RenderTarget,
        run: layout.GlyphRun,
        x: f32,
        baseline_y: f32,
        normalized_coords: []const f32,
    ) !void {
        return impl(self).renderRunAtCoords(
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
        shaped: layout.ShapedText,
        x: f32,
        baseline_y: f32,
    ) !void {
        return impl(self).renderShapedText(
            target,
            shaped,
            x,
            baseline_y,
        );
    }

    pub fn drawColorRun(
        self: *Rasterizer,
        target: *raster.ColorRenderTarget,
        run: layout.GlyphRun,
        x: f32,
        baseline_y: f32,
        palette_index: u16,
    ) !void {
        return impl(self).renderColorRun(
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
        return impl(self).renderColorGlyph(
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
        return impl(self).renderColorGlyphAtCoords(
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

pub const Prepared = opaque {
    pub fn recommendedForRepeatedRendering(self: *const Prepared) bool {
        return preparedImpl(self).glyph.recommendedForRepeatedRendering();
    }

    pub fn deinit(self: *Prepared) void {
        const implementation = preparedImplMut(self);
        const allocator = implementation.allocator;
        implementation.glyph.deinit();
        allocator.destroy(implementation);
    }
};

fn impl(rasterizer_value: *Rasterizer) *raster.Rasterizer {
    return @ptrCast(@alignCast(rasterizer_value));
}

const PreparedImpl = struct {
    /// Prepared geometry can outlive the rasterizer that created it. Retaining
    /// the allocator here gives the handle an independent ownership contract.
    allocator: std.mem.Allocator,
    glyph: raster.PreparedGlyph,
};

fn preparedImpl(prepared: *const Prepared) *const PreparedImpl {
    return @ptrCast(@alignCast(prepared));
}

fn preparedImplMut(prepared: *Prepared) *PreparedImpl {
    return @ptrCast(@alignCast(prepared));
}
