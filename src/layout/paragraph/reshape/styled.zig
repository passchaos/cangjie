//! Styled paragraph recipe for line-local source reshaping.
//!
//! The recipe re-itemizes one temporary line by script and shaping-equivalent
//! style, then rebuilds the glyph-parallel style sidecar transactionally. It is
//! separate from the main styled paragraph driver because candidate shaping
//! has different ownership and source-coordinate rules from initial shaping.

const std = @import("std");

const face_mod = @import("../../../font/face/root.zig");
const bidi_reorder = @import("../../bidi/reorder/root.zig");
const kashida = @import("../../justification/kashida.zig");
const run_types = @import("../../types/runs.zig");
const styled_buffer = @import("../../styled_buffer.zig");
const styled_paragraph = @import("../../styled_paragraph.zig");
const context_output = @import("../../../shaping/context/output.zig");
const font_fallback = @import("../../../shaping/fallback/font/root.zig");
const fallback_segment = @import("../../../shaping/fallback/segment.zig");
const segment_pipeline = @import("../../../shaping/pipeline/segment.zig");
const pipeline_types = @import("../../../shaping/pipeline/types.zig");
const unicode = @import("../../../unicode.zig");
const paragraph_options = @import("../options.zig");
const reshape = @import("../reshape.zig");

pub const Recipe = struct {
    cascade: font_fallback.Cascade,
    /// Optional union used only for public `CascadeRun.font_index` values.
    /// Font selection for inherited spans continues to use `cascade`.
    font_index_cascade: ?font_fallback.Cascade = null,
    allocator: std.mem.Allocator,
    metadata: *std.ArrayList(styled_buffer.Metadata),
    candidate_metadata: *std.ArrayList(styled_buffer.Metadata),
    commit_metadata: *std.ArrayList(styled_buffer.Metadata),
    text: []const u8,
    spans: []const styled_paragraph.Span,
    options: paragraph_options.Options,
    /// Original metadata for a speculative whole-reflow pass.
    trial_metadata: *std.ArrayList(styled_buffer.Metadata),

    /// Save glyph-parallel metadata before a balanced line-count probe.
    ///
    /// The probe may accept JSTF shrinkage and therefore exercise the ordinary
    /// commit callback. The final balanced pass must start from the exact
    /// pristine sidecar that corresponds to the caller's untouched glyphs.
    pub fn beginReflowTrial(self: Recipe) !void {
        self.trial_metadata.clearRetainingCapacity();
        try self.trial_metadata.appendSlice(
            self.allocator,
            self.metadata.items,
        );
    }

    pub fn rollbackReflowTrial(self: Recipe) void {
        std.debug.assert(self.trial_metadata.items.len != 0 or
            self.metadata.items.len == 0);
        self.metadata.clearRetainingCapacity();
        self.metadata.appendSliceAssumeCapacity(
            self.trial_metadata.items,
        );
        self.trial_metadata.clearRetainingCapacity();
    }

    pub fn minimumLineHeight(
        self: Recipe,
        glyph_start: usize,
        glyph_end: usize,
    ) ?f32 {
        if (glyph_start > glyph_end or glyph_end > self.metadata.items.len) {
            return null;
        }
        var result: ?f32 = null;
        for (self.metadata.items[glyph_start..glyph_end]) |item| {
            if (item.minimum_line_height) |minimum| {
                result = if (result) |current|
                    @max(current, minimum)
                else
                    minimum;
            }
        }
        return result;
    }

    /// Expand horizontal line metrics for style-authored physical baseline
    /// offsets. A negative y-down shift raises content and consumes ascent; a
    /// positive shift lowers content and consumes descent.
    pub fn adjustLineInfo(
        self: Recipe,
        runs: []const run_types.CascadeRun,
        glyphs: []const @import("../../glyph_position.zig").GlyphPosition,
        objects: []const @import("../../inline_object/root.zig").Object,
        glyph_start: usize,
        glyph_end: usize,
        input: @import("../../line_break/reflow/geometry.zig").LineRunInfo,
    ) @import("../../line_break/reflow/geometry.zig").LineRunInfo {
        var out = input;
        if (glyph_start > glyph_end or glyph_end > glyphs.len) return out;
        for (glyphs[glyph_start..glyph_end], glyph_start..) |glyph, glyph_index| {
            const span = spanForOutput(self.spans, glyph) orelse continue;
            const extents: BaselineExtents = if (glyph.isInlineObject()) extents: {
                const object = @import("../../inline_object/root.zig").find(objects, glyph.cluster) orelse continue;
                if (object.kind != .in_flow) continue;
                const metrics = @import("../../inline_object/root.zig").verticalMetrics(object);
                break :extents .{ .ascent = metrics.ascent, .descent = metrics.descent };
            } else extents: {
                const run = runForGlyph(runs, glyph_index) orelse continue;
                const metrics = @import("../../line_break/reflow/geometry.zig").defaultBaselineMetrics(
                    run_types.fontForBackend(run),
                    run.font_size,
                );
                break :extents .{ .ascent = metrics.ascent, .descent = metrics.descent };
            };
            out.metrics.ascent = @max(out.metrics.ascent, extents.ascent - span.baseline_shift);
            out.metrics.descent = @max(out.metrics.descent, extents.descent + span.baseline_shift);
        }
        return out;
    }

    pub fn prepareVerticalHyphenMetadata(
        self: Recipe,
        selected: []const @import("../../line_break/reflow/hyphen_insertions.zig").Selected,
    ) !void {
        self.commit_metadata.clearRetainingCapacity();
        if (selected.len == 0) return;
        try self.commit_metadata.appendSlice(
            self.allocator,
            self.metadata.items,
        );
        for (selected, 0..) |item, selected_index| {
            const source_index = item.insert_index + selected_index;
            const span = spanForBoundary(
                self.spans,
                item.glyph.cluster + item.glyph.source_byte_len,
            ) orelse return error.InvalidStyleSpans;
            try self.commit_metadata.insert(self.allocator, source_index, .{
                .style_index = span.style_index,
                .layout_spacing = 0,
                .minimum_line_height = span.minimum_line_height,
                .vertical_align = span.vertical_align,
                .baseline_shift = span.baseline_shift,
            });
        }
    }

    pub fn commitVerticalHyphenMetadata(self: Recipe) void {
        if (self.commit_metadata.items.len == 0) return;
        self.metadata.clearRetainingCapacity();
        self.metadata.appendSliceAssumeCapacity(
            self.commit_metadata.items,
        );
        self.commit_metadata.clearRetainingCapacity();
    }

    /// Resolve synthetic ellipsis ownership from the style that contains the
    /// terminal visible source boundary. This preserves style-local cascades,
    /// font size, variation coordinates, and public paragraph font indexes.
    pub fn ellipsisRun(
        self: Recipe,
        buffer: *context_output.Buffer,
        source_boundary: usize,
        source_run: ?run_types.CascadeRun,
    ) !?run_types.CascadeRun {
        const span = spanForBoundary(
            self.spans,
            source_boundary,
        ) orelse return source_run;
        const item_cascade = if (span.faces) |faces|
            font_fallback.Cascade.initWithLocations(
                face_mod.backend.fonts(faces),
                span.normalized_variation_locations orelse &.{},
            )
        else
            self.cascade;
        const fonts = item_cascade.fonts;
        const local_index = try item_cascade.selectFont('.');
        const font = fonts[local_index];
        const namespace = self.font_index_cascade orelse self.cascade;
        const font_index = for (namespace.fonts, 0..) |candidate, index| {
            if (candidate == font) break index;
        } else if (source_run) |run|
            run.font_index
        else
            local_index;
        const variation_range = try buffer.internVariationCoords(
            item_cascade.locationFor(
                local_index,
                span.normalized_variation_coords,
            ),
        );
        const baseline_metrics = try run_types.baselineMetricsAt(
            font,
            span.font_size,
            item_cascade.locationFor(
                local_index,
                span.normalized_variation_coords,
            ),
        );
        return .{
            .font = face_mod.backend.face(font),
            .font_index = font_index,
            .font_size = span.font_size,
            .glyph_start = buffer.glyphs.items.len,
            .glyph_len = 0,
            .x_offset = 0,
            .y_offset = 0,
            .variation_coord_start = variation_range.start,
            .variation_coord_len = variation_range.len,
            .baseline_ascent = baseline_metrics.ascent,
            .baseline_descent = baseline_metrics.descent,
            .baseline_leading = baseline_metrics.leading,
            .has_baseline_metrics = true,
        };
    }

    pub fn acceptKashidaBoundary(
        self: Recipe,
        boundary: usize,
    ) bool {
        const span = styled_paragraph.spanForCluster(
            self.spans,
            boundary,
        ) orelse return false;
        // A source insertion cannot cross a shaping-style boundary. The
        // preceding scalar and following scalar must belong to one shaping
        // item so U+0640 has an unambiguous font/features recipe.
        return boundary > span.byte_start and boundary < span.byteEnd();
    }

    pub fn canExpandSourceRange(
        self: Recipe,
        start: usize,
        end: usize,
    ) bool {
        const span = styled_paragraph.spanForCluster(
            self.spans,
            start,
        ) orelse return false;
        return end <= span.byteEnd();
    }

    pub fn canShrinkSourceRange(
        self: Recipe,
        start: usize,
        end: usize,
    ) bool {
        if (self.options.alignment != .justify or
            !self.options.jstf.enabled) return false;
        const span = styled_paragraph.spanForCluster(
            self.spans,
            start,
        ) orelse return false;
        return end <= span.byteEnd();
    }

    pub fn jstfTags(
        self: Recipe,
        start: usize,
        end: usize,
    ) struct {
        script: unicode.OpenTypeScriptTag,
        language: unicode.OpenTypeLanguageTag,
    } {
        const line_text = self.text[start..end];
        const span = styled_paragraph.spanForCluster(
            self.spans,
            start,
        ) orelse return .{
            .script = unicode.openTypeScriptTag(
                unicode.inferOpenTypeScript(line_text),
            ),
            .language = unicode.inferOpenTypeLanguageTag(line_text),
        };
        return .{
            .script = span.script_tag orelse unicode.openTypeScriptTag(
                unicode.inferOpenTypeScript(line_text),
            ),
            .language = span.language_tag orelse
                unicode.inferOpenTypeLanguageTag(line_text),
        };
    }

    pub fn acceptJstfExtenderBoundary(
        self: Recipe,
        boundary: usize,
    ) bool {
        return self.acceptKashidaBoundary(boundary);
    }

    pub fn shapeLine(
        self: Recipe,
        buffer: *context_output.Buffer,
        temporary_text: []const u8,
        original_byte_start: usize,
        original_byte_len: usize,
        insertion_boundaries: []const kashida.Boundary,
        insertion_count: usize,
    ) !void {
        buffer.clear();
        const original_byte_end = original_byte_start + original_byte_len;
        const script_runs = try unicode.itemizeScriptRuns(
            buffer.allocator,
            temporary_text,
        );
        defer buffer.allocator.free(script_runs);
        const font_overrides = try reshape.temporaryFontOverrides(
            buffer.allocator,
            insertion_boundaries,
            insertion_count,
            original_byte_start,
        );
        defer buffer.allocator.free(font_overrides);

        var pen = fallback_segment.Pen{};
        for (script_runs) |script_run| {
            const temporary_start = script_run.byte_start;
            const temporary_end =
                temporary_start + script_run.byte_len;
            var cursor = temporary_start;
            while (cursor < temporary_end) {
                const mapping = mapTemporaryByte(
                    temporary_text,
                    original_byte_start,
                    original_byte_len,
                    insertion_boundaries,
                    insertion_count,
                    self.spans,
                    cursor,
                ) orelse return error.InvalidKashidaMap;
                const span = mapping.span;
                var item_end = cursor + mapping.temporary_byte_len;
                while (item_end < temporary_end) {
                    const next = mapTemporaryByte(
                        temporary_text,
                        original_byte_start,
                        original_byte_len,
                        insertion_boundaries,
                        insertion_count,
                        self.spans,
                        item_end,
                    ) orelse break;
                    if (!sameShapingRecipe(span, next.span)) break;
                    item_end += next.temporary_byte_len;
                }
                pen = try self.shapeItem(
                    buffer,
                    temporary_text,
                    original_byte_start,
                    original_byte_end,
                    script_run.script,
                    span,
                    cursor,
                    item_end,
                    font_overrides,
                    pen,
                );
                cursor = item_end;
            }
        }
        try bidi_reorder.normalizeLogical(buffer);
    }

    pub fn shapeLineAtCoords(
        self: Recipe,
        buffer: *context_output.Buffer,
        original_byte_start: usize,
        original_byte_len: usize,
        font: *const @import("../../../font.zig").Font,
        font_index: usize,
        normalized_variation_coords: []const f32,
    ) !void {
        const original_byte_end = original_byte_start + original_byte_len;
        const span = styled_paragraph.spanForCluster(
            self.spans,
            original_byte_start,
        ) orelse return error.InvalidStyleSpans;
        std.debug.assert(span.byteEnd() >= original_byte_end);
        buffer.clear();
        const line_text =
            self.text[original_byte_start..original_byte_end];
        const script = unicode.inferOpenTypeScript(line_text);
        var context = SegmentContext{
            .buffer = buffer,
            .font_size = span.font_size,
            .lookup_options = .{
                .lookup = .{
                    .script = script,
                    .script_tag = span.script_tag orelse
                        unicode.openTypeScriptTag(script),
                    .script_tag_explicit = span.script_tag != null,
                    .language_tag = span.language_tag orelse
                        unicode.inferOpenTypeLanguageTag(line_text),
                    .direction = self.options.direction,
                    .reorder_bidi = false,
                    .native_direction_shaping = true,
                    .writing_mode = normalizedWritingMode(self.options),
                    .text_orientation = self.options.text_orientation,
                    .features = span.features,
                    .normalized_variation_coords = normalized_variation_coords,
                    .context_before = self.text[0..original_byte_start],
                    .context_after = self.text[original_byte_end..],
                    .beginning_of_text = original_byte_start == 0,
                    .end_of_text = original_byte_end == self.text.len,
                },
                .all_ascii = false,
            },
        };
        _ = try context.appendSegment(
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
        try self.saveCandidate();
    }

    pub fn shapeLineWithJstfPriority(
        self: Recipe,
        buffer: *context_output.Buffer,
        original_byte_start: usize,
        original_byte_len: usize,
        font: *const @import("../../../font.zig").Font,
        font_index: usize,
        modifications: pipeline_types.JstfModifications,
        maximum_lookup_offsets: []const usize,
    ) !void {
        const original_byte_end = original_byte_start + original_byte_len;
        const span = styled_paragraph.spanForCluster(
            self.spans,
            original_byte_start,
        ) orelse return error.InvalidStyleSpans;
        std.debug.assert(span.byteEnd() >= original_byte_end);
        buffer.clear();
        const line_text =
            self.text[original_byte_start..original_byte_end];
        const script = unicode.inferOpenTypeScript(line_text);
        var context = SegmentContext{
            .buffer = buffer,
            .font_size = span.font_size,
            .lookup_options = .{
                .lookup = .{
                    .script = script,
                    .script_tag = span.script_tag orelse
                        unicode.openTypeScriptTag(script),
                    .script_tag_explicit = span.script_tag != null,
                    .language_tag = span.language_tag orelse
                        unicode.inferOpenTypeLanguageTag(line_text),
                    .direction = self.options.direction,
                    .reorder_bidi = false,
                    .native_direction_shaping = true,
                    .writing_mode = normalizedWritingMode(self.options),
                    .text_orientation = self.options.text_orientation,
                    .features = span.features,
                    .normalized_variation_coords = span.normalized_variation_coords,
                    .jstf_modifications = modifications,
                    .jstf_max = if (maximum_lookup_offsets.len == 0)
                        null
                    else
                        .{ .lookup_offsets = maximum_lookup_offsets },
                    .context_before = self.text[0..original_byte_start],
                    .context_after = self.text[original_byte_end..],
                    .beginning_of_text = original_byte_start == 0,
                    .end_of_text = original_byte_end == self.text.len,
                },
                .all_ascii = false,
            },
        };
        _ = try context.appendSegment(
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
        try self.saveCandidate();
    }

    pub fn shapeRangeWithJstfPriority(
        self: Recipe,
        buffer: *context_output.Buffer,
        original_byte_start: usize,
        original_byte_len: usize,
        font: *const @import("../../../font.zig").Font,
        font_index: usize,
        modifications: pipeline_types.JstfModifications,
        maximum_lookup_offsets: []const usize,
    ) !void {
        const original_byte_end = original_byte_start + original_byte_len;
        const span = styled_paragraph.spanForCluster(
            self.spans,
            original_byte_start,
        ) orelse return error.InvalidStyleSpans;
        std.debug.assert(span.byteEnd() >= original_byte_end);
        buffer.clear();
        const range_text =
            self.text[original_byte_start..original_byte_end];
        const script = unicode.inferOpenTypeScript(range_text);
        var context = SegmentContext{
            .buffer = buffer,
            .font_size = span.font_size,
            .lookup_options = .{
                .lookup = .{
                    .script = script,
                    .script_tag = span.script_tag orelse
                        unicode.openTypeScriptTag(script),
                    .script_tag_explicit = span.script_tag != null,
                    .language_tag = span.language_tag orelse
                        unicode.inferOpenTypeLanguageTag(range_text),
                    .direction = self.options.direction,
                    .reorder_bidi = false,
                    .native_direction_shaping = true,
                    .writing_mode = normalizedWritingMode(self.options),
                    .text_orientation = self.options.text_orientation,
                    .features = span.features,
                    .normalized_variation_coords = span.normalized_variation_coords,
                    .jstf_modifications = modifications,
                    .jstf_max = if (maximum_lookup_offsets.len == 0)
                        null
                    else
                        .{ .lookup_offsets = maximum_lookup_offsets },
                    .context_before = self.text[0..original_byte_start],
                    .context_after = self.text[original_byte_end..],
                    .beginning_of_text = original_byte_start == 0,
                    .end_of_text = original_byte_end == self.text.len,
                },
                .all_ascii = false,
            },
        };
        _ = try context.appendSegment(
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
        try self.saveCandidate();
    }

    fn shapeItem(
        self: Recipe,
        buffer: *context_output.Buffer,
        temporary_text: []const u8,
        original_byte_start: usize,
        original_byte_end: usize,
        script: unicode.Script,
        span: styled_paragraph.Span,
        item_start: usize,
        item_end: usize,
        font_overrides: []const fallback_segment.FontOverride,
        pen: fallback_segment.Pen,
    ) !fallback_segment.Pen {
        const item_text = temporary_text[item_start..item_end];
        const item_cascade = if (span.faces) |faces|
            font_fallback.Cascade.initWithLocations(
                face_mod.backend.fonts(faces),
                span.normalized_variation_locations orelse &.{},
            )
        else
            self.cascade;
        const run_start = buffer.runs.items.len;
        var context = SegmentContext{
            .buffer = buffer,
            .font_size = span.font_size,
            .lookup_options = .{
                .lookup = .{
                    .script = script,
                    .script_tag = span.script_tag orelse
                        unicode.openTypeScriptTag(script),
                    .script_tag_explicit = span.script_tag != null,
                    .language_tag = span.language_tag orelse
                        unicode.inferOpenTypeLanguageTag(item_text),
                    .direction = self.options.direction,
                    .reorder_bidi = false,
                    .native_direction_shaping = true,
                    .writing_mode = normalizedWritingMode(self.options),
                    .text_orientation = self.options.text_orientation,
                    .features = span.features,
                    .normalized_variation_coords = span.normalized_variation_coords,
                    // Prefer temporary in-line neighbors at style boundaries.
                    // Only physical line edges borrow original paragraph
                    // context, which controls joining but is not emitted.
                    .context_before = if (item_start != 0)
                        temporary_text[0..item_start]
                    else
                        self.text[0..original_byte_start],
                    .context_after = if (item_end != temporary_text.len)
                        temporary_text[item_end..]
                    else
                        self.text[original_byte_end..],
                    .beginning_of_text = item_start == 0 and original_byte_start == 0,
                    .end_of_text = item_end == temporary_text.len and
                        original_byte_end == self.text.len,
                },
                .all_ascii = false,
            },
        };
        const next_pen = try fallback_segment.shape(&context, .{
            .cascade = item_cascade,
            .text = item_text,
            .cluster_base = item_start,
            .pen = pen,
            .font_overrides = font_overrides,
        });
        if (span.faces != null) {
            normalizeRunFontIndices(
                buffer.runs.items[run_start..],
                self.font_index_cascade orelse self.cascade,
            );
        }
        return next_pen;
    }

    pub fn finishLine(
        self: Recipe,
        buffer: *context_output.Buffer,
    ) !void {
        try self.buildCandidateMetadata(buffer);
        for (buffer.glyphs.items, self.candidate_metadata.items) |*glyph, item| {
            glyph.x_advance += item.layout_spacing;
        }
    }

    fn buildCandidateMetadata(
        self: Recipe,
        buffer: *context_output.Buffer,
    ) !void {
        self.candidate_metadata.clearRetainingCapacity();
        try self.candidate_metadata.ensureTotalCapacity(
            buffer.allocator,
            buffer.glyphs.items.len,
        );
        for (buffer.glyphs.items) |*glyph| {
            const span = spanForOutput(self.spans, glyph.*) orelse
                return error.InvalidStyleSpans;
            const spacing = if (glyph.isKashida() or glyph.isInlineObject())
                0
            else if (glyph.isTab())
                0
            else if (glyph.codepoint == ' ')
                span.letter_spacing + span.word_spacing
            else
                span.letter_spacing;
            self.candidate_metadata.appendAssumeCapacity(.{
                .style_index = span.style_index,
                .layout_spacing = spacing,
                .minimum_line_height = span.minimum_line_height,
                .vertical_align = span.vertical_align,
                .baseline_shift = span.baseline_shift,
            });
        }
    }

    pub fn saveCandidate(self: Recipe) !void {
        self.commit_metadata.clearRetainingCapacity();
        try self.commit_metadata.appendSlice(
            self.allocator,
            self.candidate_metadata.items,
        );
    }

    pub fn prepareCommit(
        self: Recipe,
        _: usize,
        _: usize,
        new_glyph_len: usize,
    ) !void {
        if (self.commit_metadata.items.len != new_glyph_len) {
            return error.InvalidStyleSpans;
        }
        try self.metadata.ensureTotalCapacity(
            self.allocator,
            self.metadata.items.len + new_glyph_len,
        );
    }

    pub fn commit(
        self: Recipe,
        glyph_start: usize,
        old_glyph_len: usize,
        _: usize,
    ) void {
        self.metadata.replaceRangeAssumeCapacity(
            glyph_start,
            old_glyph_len,
            self.commit_metadata.items,
        );
    }
};

const BaselineExtents = struct {
    ascent: f32,
    descent: f32,
};

const SegmentContext = struct {
    buffer: *context_output.Buffer,
    font_size: f32,
    lookup_options: pipeline_types.ResolvedLookupOptions,

    pub fn appendSegment(
        self: *@This(),
        cascade: font_fallback.Cascade,
        font_index: usize,
        text: []const u8,
        cluster_base: usize,
        pen: fallback_segment.Pen,
    ) !fallback_segment.Pen {
        const font = cascade.fonts[font_index];
        var lookup_options = self.lookup_options;
        lookup_options.lookup.normalized_variation_coords = cascade.locationFor(
            font_index,
            lookup_options.lookup.normalized_variation_coords,
        );
        const glyph_start = self.buffer.glyphs.items.len;
        _ = try segment_pipeline.run(.{
            .font = font,
            .metrics_cache = null,
            .glyph_index_cache = null,
            .buffer = self.buffer,
            .text = text,
            .font_size = self.font_size,
            .cluster_base = cluster_base,
            .lookup_options = lookup_options,
        });
        const glyph_len = self.buffer.glyphs.items.len - glyph_start;
        if (glyph_len == 0) return pen;

        const variation_range = try self.buffer.internVariationCoords(
            lookup_options.lookup.normalized_variation_coords,
        );
        const baseline_metrics = try run_types.baselineMetricsAt(
            font,
            self.font_size,
            lookup_options.lookup.normalized_variation_coords,
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
            .baseline_ascent = baseline_metrics.ascent,
            .baseline_descent = baseline_metrics.descent,
            .baseline_leading = baseline_metrics.leading,
            .has_baseline_metrics = true,
        });
        var next_pen = pen;
        for (self.buffer.glyphs.items[glyph_start..]) |glyph| {
            next_pen.x += glyph.x_advance;
            next_pen.y += glyph.y_advance;
        }
        return next_pen;
    }
};

fn normalizeRunFontIndices(
    runs: []run_types.CascadeRun,
    paragraph_cascade: font_fallback.Cascade,
) void {
    for (runs) |*run| {
        for (paragraph_cascade.fonts, 0..) |font, font_index| {
            if (font != run_types.fontForBackend(run.*)) continue;
            run.font_index = font_index;
            break;
        }
    }
}

fn normalizedWritingMode(
    options: paragraph_options.Options,
) pipeline_types.WritingMode {
    return if (options.writing_mode.isVertical())
        .vertical_rl
    else
        .horizontal_tb;
}

fn sameShapingRecipe(
    a: styled_paragraph.Span,
    b: styled_paragraph.Span,
) bool {
    if (a.byte_start == b.byte_start and a.byte_len == b.byte_len) {
        return true;
    }
    return styled_paragraph.shapeEquivalent(a, b);
}

const TemporaryMapping = struct {
    span: styled_paragraph.Span,
    temporary_byte_len: usize,
};

fn mapTemporaryByte(
    temporary_text: []const u8,
    original_byte_start: usize,
    original_byte_len: usize,
    insertion_boundaries: []const kashida.Boundary,
    insertion_count: usize,
    spans: []const styled_paragraph.Span,
    temporary_offset: usize,
) ?TemporaryMapping {
    var iterator = std.unicode.Utf8Iterator{
        .bytes = temporary_text,
        .i = temporary_offset,
    };
    const codepoint = iterator.nextCodepoint() orelse return null;
    var original_offset = kashida.originalByteForTemporaryBoundary(
        temporary_offset,
        original_byte_start,
        original_byte_len,
        insertion_boundaries,
        insertion_count,
    ) catch return null;
    if (codepoint == 0x0640 and
        styled_paragraph.spanForCluster(spans, original_offset) == null and
        original_offset > original_byte_start)
    {
        original_offset -= 1;
    }
    return .{
        .span = styled_paragraph.spanForCluster(
            spans,
            original_offset,
        ) orelse return null,
        .temporary_byte_len = iterator.i - temporary_offset,
    };
}

fn spanForOutput(
    spans: []const styled_paragraph.Span,
    glyph: @import("../../glyph_position.zig").GlyphPosition,
) ?styled_paragraph.Span {
    if (styled_paragraph.spanForCluster(spans, glyph.cluster)) |span| {
        return span;
    }
    if (!glyph.isKashida() or glyph.cluster == 0) return null;
    return styled_paragraph.spanForCluster(spans, glyph.cluster - 1);
}

fn spanForBoundary(
    spans: []const styled_paragraph.Span,
    boundary: usize,
) ?styled_paragraph.Span {
    if (spans.len == 0) return null;
    for (spans) |span| {
        if (boundary > span.byte_start and boundary <= span.byteEnd()) {
            return span;
        }
    }
    return styled_paragraph.spanForCluster(spans, boundary);
}

fn runForGlyph(
    runs: []const run_types.CascadeRun,
    glyph_index: usize,
) ?run_types.CascadeRun {
    var low: usize = 0;
    var high = runs.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const run = runs[mid];
        if (glyph_index < run.glyph_start) {
            high = mid;
        } else if (glyph_index >= run.glyph_start + run.glyph_len) {
            low = mid + 1;
        } else {
            return run;
        }
    }
    return null;
}
