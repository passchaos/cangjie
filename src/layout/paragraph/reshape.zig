//! Concrete shaping recipes for post-line-selection source transformations.
//!
//! Retained paragraphs keep enough immutable ownership to construct this value
//! at reflow time. The recipe deliberately shapes into a caller-supplied
//! temporary buffer, so a failed or over-wide candidate cannot mutate the
//! paragraph being laid out.

const std = @import("std");
const face_mod = @import("../../font/face/root.zig");
const cache = @import("../../shaping/context/cache/root.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const fallback_segment = @import("../../shaping/fallback/segment.zig");
const plan_resolution = @import("../../shaping/plan/resolution.zig");
const segment_pipeline = @import("../../shaping/pipeline/segment.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const bidi_reorder = @import("../bidi/reorder/root.zig");
const geometry = @import("../line_break/reflow/geometry.zig");
const kashida = @import("../justification/kashida.zig");
const paragraph_options = @import("options.zig");
const run_types = @import("../types/runs.zig");

pub const Uniform = struct {
    cascade: font_fallback.Cascade,
    fallback_cache: ?*cache.FontFallbackCache = null,
    metrics_cache: ?*cache.GlyphMetricsCache = null,
    glyph_index_cache: ?*cache.GlyphIndexCache = null,
    text: []const u8,
    font_size: f32,
    options: paragraph_options.Options,

    pub fn beginReflowTrial(_: Uniform) !void {}

    pub fn rollbackReflowTrial(_: Uniform) void {}

    pub fn minimumLineHeight(_: Uniform, _: usize, _: usize) ?f32 {
        return null;
    }

    pub fn adjustLineInfo(_: Uniform, _: anytype, _: anytype, _: anytype, _: usize, _: usize, info: geometry.LineRunInfo) geometry.LineRunInfo {
        return info;
    }

    pub fn prepareVerticalHyphenMetadata(
        _: Uniform,
        _: []const @import("../line_break/reflow/hyphen_insertions.zig").Selected,
    ) !void {}

    pub fn commitVerticalHyphenMetadata(_: Uniform) void {}

    /// Resolve synthetic ellipsis ownership through the same uniform cascade
    /// and variation instance as ordinary paragraph source.
    pub fn ellipsisRun(
        self: Uniform,
        buffer: *context_output.Buffer,
        _: usize,
        _: ?run_types.CascadeRun,
    ) !?run_types.CascadeRun {
        const font_index = try self.cascade.selectFont('.');
        const font = self.cascade.fonts[font_index];
        const variation_range = try buffer.internVariationCoords(
            self.options.normalized_variation_coords,
        );
        return .{
            .font = face_mod.backend.face(font),
            .font_index = font_index,
            .font_size = self.font_size,
            .glyph_start = buffer.glyphs.items.len,
            .glyph_len = 0,
            .x_offset = 0,
            .y_offset = 0,
            .variation_coord_start = variation_range.start,
            .variation_coord_len = variation_range.len,
        };
    }

    pub fn acceptKashidaBoundary(_: Uniform, _: usize) bool {
        return true;
    }

    pub fn canExpandSourceRange(_: Uniform, _: usize, _: usize) bool {
        return true;
    }

    pub fn canShrinkSourceRange(
        self: Uniform,
        _: usize,
        _: usize,
    ) bool {
        return self.options.alignment == .justify and
            self.options.jstf.enabled;
    }

    pub fn jstfTags(
        self: Uniform,
        start: usize,
        end: usize,
    ) struct {
        script: @import("../../unicode.zig").OpenTypeScriptTag,
        language: @import("../../unicode.zig").OpenTypeLanguageTag,
    } {
        const unicode_mod = @import("../../unicode.zig");
        const line_text = self.text[start..end];
        return .{
            .script = self.options.script_tag orelse
                unicode_mod.openTypeScriptTag(
                    unicode_mod.inferOpenTypeScript(line_text),
                ),
            .language = self.options.language_tag orelse
                unicode_mod.inferOpenTypeLanguageTag(line_text),
        };
    }

    pub fn acceptJstfExtenderBoundary(
        _: Uniform,
        _: usize,
    ) bool {
        return true;
    }

    pub fn saveCandidate(_: Uniform) !void {}

    pub fn prepareCommit(
        _: Uniform,
        _: usize,
        _: usize,
        _: usize,
    ) !void {}

    pub fn commit(
        _: Uniform,
        _: usize,
        _: usize,
        _: usize,
    ) void {}

    pub fn shapeLine(
        self: Uniform,
        buffer: *context_output.Buffer,
        temporary_text: []const u8,
        original_byte_start: usize,
        original_byte_len: usize,
        insertion_boundaries: []const kashida.Boundary,
        insertion_count: usize,
    ) !void {
        buffer.clear();
        const original_byte_end = original_byte_start + original_byte_len;
        var shape_options = paragraph_options.shapeOptions(self.options);
        shape_options.context_before = self.text[0..original_byte_start];
        shape_options.context_after = self.text[original_byte_end..];
        shape_options.beginning_of_text = original_byte_start == 0;
        shape_options.end_of_text = original_byte_end == self.text.len;
        const lookup_options = plan_resolution.forText(
            temporary_text,
            shape_options,
        );
        var driver = Driver{
            .buffer = buffer,
            .metrics_cache = self.metrics_cache,
            .glyph_index_cache = self.glyph_index_cache,
            .font_size = self.font_size,
            .lookup_options = lookup_options,
        };
        const font_overrides = try temporaryFontOverrides(
            buffer.allocator,
            insertion_boundaries,
            insertion_count,
            original_byte_start,
        );
        defer buffer.allocator.free(font_overrides);
        _ = try fallback_segment.shape(&driver, .{
            .cascade = self.cascade,
            .fallback_cache = self.fallback_cache,
            .glyph_index_cache = self.glyph_index_cache,
            .text = temporary_text,
            .font_overrides = font_overrides,
        });
        try bidi_reorder.normalizeLogical(buffer);
    }

    pub fn shapeLineAtCoords(
        self: Uniform,
        buffer: *context_output.Buffer,
        original_byte_start: usize,
        original_byte_len: usize,
        font: *const @import("../../font.zig").Font,
        font_index: usize,
        normalized_variation_coords: []const f32,
    ) !void {
        buffer.clear();
        const original_byte_end = original_byte_start + original_byte_len;
        var shape_options = paragraph_options.shapeOptions(self.options);
        shape_options.normalized_variation_coords =
            normalized_variation_coords;
        shape_options.context_before = self.text[0..original_byte_start];
        shape_options.context_after = self.text[original_byte_end..];
        shape_options.beginning_of_text = original_byte_start == 0;
        shape_options.end_of_text = original_byte_end == self.text.len;
        const line_text =
            self.text[original_byte_start..original_byte_end];
        const lookup_options = plan_resolution.forText(
            line_text,
            shape_options,
        );
        var driver = Driver{
            .buffer = buffer,
            .metrics_cache = self.metrics_cache,
            .glyph_index_cache = self.glyph_index_cache,
            .font_size = self.font_size,
            .lookup_options = lookup_options,
        };
        _ = try driver.appendSegment(
            font_fallback.Cascade.init(&.{font}),
            0,
            line_text,
            original_byte_start,
            .{},
        );
        if (buffer.runs.items.len != 0) {
            buffer.runs.items[0].font_index = font_index;
        }
        try bidi_reorder.normalizeLogical(buffer);
        try self.finishLine(buffer);
    }

    pub fn shapeLineWithJstfPriority(
        self: Uniform,
        buffer: *context_output.Buffer,
        original_byte_start: usize,
        original_byte_len: usize,
        font: *const @import("../../font.zig").Font,
        font_index: usize,
        modifications: pipeline_types.JstfModifications,
        maximum_lookup_offsets: []const usize,
    ) !void {
        buffer.clear();
        const original_byte_end = original_byte_start + original_byte_len;
        var shape_options = paragraph_options.shapeOptions(self.options);
        shape_options.context_before = self.text[0..original_byte_start];
        shape_options.context_after = self.text[original_byte_end..];
        shape_options.beginning_of_text = original_byte_start == 0;
        shape_options.end_of_text = original_byte_end == self.text.len;
        const line_text =
            self.text[original_byte_start..original_byte_end];
        var lookup_options = plan_resolution.forText(
            line_text,
            shape_options,
        );
        lookup_options.lookup.jstf_modifications = modifications;
        if (maximum_lookup_offsets.len != 0) {
            lookup_options.lookup.jstf_max = .{
                .lookup_offsets = maximum_lookup_offsets,
            };
        }
        var driver = Driver{
            .buffer = buffer,
            .metrics_cache = self.metrics_cache,
            .glyph_index_cache = self.glyph_index_cache,
            .font_size = self.font_size,
            .lookup_options = lookup_options,
        };
        _ = try driver.appendSegment(
            font_fallback.Cascade.init(&.{font}),
            0,
            line_text,
            original_byte_start,
            .{},
        );
        if (buffer.runs.items.len != 0) {
            buffer.runs.items[0].font_index = font_index;
        }
        try bidi_reorder.normalizeLogical(buffer);
        try self.finishLine(buffer);
    }

    /// Rebuild one overflowing source prefix with its JSTF shrinkage plan.
    ///
    /// `finishLine` reapplies the same paragraph spacing already present in the
    /// retained stream so candidate widths and committed geometry stay in one
    /// coordinate system during JstfMax interpolation.
    pub fn shapeRangeWithJstfPriority(
        self: Uniform,
        buffer: *context_output.Buffer,
        original_byte_start: usize,
        original_byte_len: usize,
        font: *const @import("../../font.zig").Font,
        font_index: usize,
        modifications: pipeline_types.JstfModifications,
        maximum_lookup_offsets: []const usize,
    ) !void {
        buffer.clear();
        const original_byte_end = original_byte_start + original_byte_len;
        var shape_options = paragraph_options.shapeOptions(self.options);
        shape_options.context_before = self.text[0..original_byte_start];
        shape_options.context_after = self.text[original_byte_end..];
        shape_options.beginning_of_text = original_byte_start == 0;
        shape_options.end_of_text = original_byte_end == self.text.len;
        const range_text =
            self.text[original_byte_start..original_byte_end];
        var lookup_options = plan_resolution.forText(
            range_text,
            shape_options,
        );
        lookup_options.lookup.jstf_modifications = modifications;
        if (maximum_lookup_offsets.len != 0) {
            lookup_options.lookup.jstf_max = .{
                .lookup_offsets = maximum_lookup_offsets,
            };
        }
        var driver = Driver{
            .buffer = buffer,
            .metrics_cache = self.metrics_cache,
            .glyph_index_cache = self.glyph_index_cache,
            .font_size = self.font_size,
            .lookup_options = lookup_options,
        };
        _ = try driver.appendSegment(
            font_fallback.Cascade.init(&.{font}),
            0,
            range_text,
            original_byte_start,
            .{},
        );
        if (buffer.runs.items.len != 0) {
            buffer.runs.items[0].font_index = font_index;
        }
        try bidi_reorder.normalizeLogical(buffer);
        try self.finishLine(buffer);
    }

    pub fn finishLine(
        self: Uniform,
        buffer: *context_output.Buffer,
    ) !void {
        for (buffer.glyphs.items) |*glyph| {
            if (glyph.isKashida()) continue;
            glyph.x_advance += geometry.spacingForGlyph(
                glyph.codepoint,
                self.options,
            );
        }
    }
};

pub fn temporaryFontOverrides(
    allocator: std.mem.Allocator,
    boundaries: []const kashida.Boundary,
    insertion_count: usize,
    line_byte_start: usize,
) ![]const fallback_segment.FontOverride {
    const used_count = @min(insertion_count, boundaries.len);
    const overrides = try allocator.alloc(
        fallback_segment.FontOverride,
        used_count,
    );
    // The slice is consumed synchronously by fallback segmentation. Shape
    // scratch does not retain it, so callers can free it after `shape` returns.
    var used: usize = 0;
    var inserted_before: usize = 0;
    for (boundaries, 0..) |boundary, boundary_index| {
        const count = kashida.insertionCountAtBoundary(
            insertion_count,
            boundaries.len,
            boundary_index,
        );
        if (count == 0) continue;
        overrides[used] = .{
            .byte_start = boundary.byte_offset - line_byte_start + inserted_before,
            .byte_len = count * 2,
            .font = boundary.font,
        };
        used += 1;
        inserted_before += count * 2;
    }
    std.debug.assert(used == overrides.len);
    return overrides;
}

const Driver = struct {
    buffer: *context_output.Buffer,
    metrics_cache: ?*cache.GlyphMetricsCache,
    glyph_index_cache: ?*cache.GlyphIndexCache,
    font_size: f32,
    lookup_options: pipeline_types.ResolvedLookupOptions,

    pub fn appendSegment(
        self: *Driver,
        cascade: font_fallback.Cascade,
        font_index: usize,
        text: []const u8,
        cluster_base: usize,
        pen: fallback_segment.Pen,
    ) !fallback_segment.Pen {
        const font = cascade.fonts[font_index];
        const glyph_start = self.buffer.glyphs.items.len;
        _ = try segment_pipeline.run(.{
            .font = font,
            .metrics_cache = self.metrics_cache,
            .glyph_index_cache = self.glyph_index_cache,
            .buffer = self.buffer,
            .text = text,
            .font_size = self.font_size,
            .cluster_base = cluster_base,
            .lookup_options = self.lookup_options,
        });
        const glyph_len = self.buffer.glyphs.items.len - glyph_start;
        if (glyph_len == 0) return pen;

        const variation_range = try self.buffer.internVariationCoords(
            self.lookup_options.lookup.normalized_variation_coords,
        );
        try self.buffer.runs.append(self.buffer.allocator, .{
            .font = face_mod.backend.face(font),
            .font_index = font_index,
            .font_size = self.font_size,
            .glyph_start = glyph_start,
            .glyph_len = glyph_len,
            .x_offset = pen.x,
            .y_offset = pen.y,
            .variation_coord_start = variation_range.start,
            .variation_coord_len = variation_range.len,
        });
        var next_pen = pen;
        for (self.buffer.glyphs.items[glyph_start..]) |glyph| {
            next_pen.x += glyph.x_advance;
            next_pen.y += glyph.y_advance;
        }
        return next_pen;
    }
};
