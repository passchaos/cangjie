//! Unified attributed paragraph shaping, metadata, reflow, and bidi.

const std = @import("std");

const face_mod = @import("../../font/face/root.zig");
const bidi_reorder = @import("../bidi/reorder/root.zig");
const inline_object = @import("../inline_object/root.zig");
const font_expansion = @import("../justification/font_expansion.zig");
const jstf_justification = @import("../justification/jstf.zig");
const jstf_extender = @import("../justification/jstf/extender.zig");
const kashida_justification = @import("../justification/kashida.zig");
const paragraph_reflow = @import("../line_break/reflow/root.zig");
const styled_reshape = @import("reshape/styled.zig");
const punctuation_compression = @import("../punctuation/compression.zig");
const punctuation_hanging = @import("../punctuation/hanging.zig");
const paragraph_options = @import("options.zig");
const content_widths = @import("content_widths.zig");
const line_break_analysis = @import("../line_break/analysis.zig");
const source_items = @import("source_items.zig");
const tabs = @import("tabs.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");
const styled_bidi = @import("../styled_bidi.zig");
const styled_buffer = @import("../styled_buffer.zig");
const styled_paragraph = @import("../styled_paragraph.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const fallback_segment = @import("../../shaping/fallback/segment.zig");
const plan_bidi = @import("../../shaping/plan/bidi.zig");
const plan_validation = @import("../../shaping/plan/validation.zig");
const segment_pipeline = @import("../../shaping/pipeline/segment.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const unicode = @import("../../unicode.zig");

pub const Input = struct {
    cascade: font_fallback.Cascade,
    buffer: *context_output.Buffer,
    styled: *styled_buffer.Buffer,
    text: []const u8,
    default_font_size: f32,
    spans: []const styled_paragraph.Span,
    options: paragraph_options.Options,
};

pub fn layout(input: Input) !paragraph_types.ParagraphLayout {
    try paragraph_options.validate(input.options);
    try plan_validation.utf8(input.text);
    try plan_validation.fontSize(input.default_font_size);
    if (input.cascade.fonts.len == 0) return error.EmptyFontCascade;
    try inline_object.validate(input.text, input.options.inline_objects);

    input.buffer.clear();
    input.styled.clear();
    var driver = Driver{
        .cascade = input.cascade,
        .buffer = input.buffer,
        .styled = input.styled,
        .text = input.text,
        .default_font_size = input.default_font_size,
        .options = input.options,
    };
    try styled_paragraph.layout(&driver, input.text, input.spans);
    return input.buffer.paragraphLayout();
}

const Driver = struct {
    cascade: font_fallback.Cascade,
    buffer: *context_output.Buffer,
    styled: *styled_buffer.Buffer,
    text: []const u8,
    default_font_size: f32,
    options: paragraph_options.Options,
    pen: fallback_segment.Pen = .{},

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return self.buffer.allocator;
    }

    pub fn validateSpan(_: *@This(), span: styled_paragraph.Span) !void {
        try plan_validation.fontSize(span.font_size);
        if (span.faces) |faces| {
            if (faces.len == 0) return error.EmptyFontCascade;
        }
        try plan_validation.features(span.features);
        try plan_validation.variationCoords(
            span.normalized_variation_coords,
        );
        if (!std.math.isFinite(span.letter_spacing) or
            !std.math.isFinite(span.word_spacing))
        {
            return error.InvalidStyleSpans;
        }
        if (span.minimum_line_height) |height| {
            if (!std.math.isFinite(height) or height <= 0) {
                return error.InvalidStyleSpans;
            }
        }
    }

    pub fn shapeItem(
        self: *@This(),
        byte_start: usize,
        byte_end: usize,
        inferred_script: unicode.Script,
        span: styled_paragraph.Span,
    ) !void {
        const item_cascade = font_fallback.Cascade.init(
            if (span.faces) |faces|
                face_mod.backend.fonts(faces)
            else
                self.cascade.fonts,
        );
        const run_start = self.buffer.runs.items.len;
        var items = source_items.Cursor.init(
            self.text,
            self.options.inline_objects,
            byte_start,
            byte_end,
        );
        while (items.next()) |item| {
            switch (item) {
                .text => |range| {
                    try self.shapeTextRange(
                        item_cascade,
                        range.start,
                        range.end,
                        inferred_script,
                        span,
                    );
                },
                .object => |object| {
                    const object_advance =
                        if (object.kind == .in_flow) object.width else 0;
                    try self.buffer.glyphs.append(self.buffer.allocator, .{
                        .glyph_id = 0,
                        .codepoint = inline_object.object_replacement_character,
                        .cluster = object.byte_index,
                        .source_byte_len = inline_object.object_replacement_utf8.len,
                        .x_advance = object_advance,
                        .flags = .{ .inline_object = true },
                    });
                    self.pen.x += object_advance;
                },
                .tab => |tab_index| {
                    try self.buffer.glyphs.append(
                        self.buffer.allocator,
                        tabs.marker(tab_index),
                    );
                },
            }
        }
        if (span.faces != null) self.normalizeNewRunFontIndices(run_start);
    }

    fn shapeTextRange(
        self: *@This(),
        cascade: font_fallback.Cascade,
        byte_start: usize,
        byte_end: usize,
        inferred_script: unicode.Script,
        span: styled_paragraph.Span,
    ) !void {
        const item_text = self.text[byte_start..byte_end];
        var segment_context = SegmentContext{
            .buffer = self.buffer,
            .font_size = span.font_size,
            .lookup_options = .{
                .lookup = .{
                    .script = inferred_script,
                    .script_tag = span.script_tag orelse
                        unicode.openTypeScriptTag(inferred_script),
                    .script_tag_explicit = span.script_tag != null,
                    .language_tag = span.language_tag orelse
                        unicode.inferOpenTypeLanguageTag(item_text),
                    .direction = self.options.direction,
                    .reorder_bidi = false,
                    .native_direction_shaping = true,
                    .features = span.features,
                    .normalized_variation_coords = span.normalized_variation_coords,
                    .context_before = self.text[0..byte_start],
                    .context_after = self.text[byte_end..],
                    .beginning_of_text = byte_start == 0,
                    .end_of_text = byte_end == self.text.len,
                },
                .all_ascii = fallback_segment.isAscii(item_text),
            },
        };
        self.pen = try fallback_segment.shape(&segment_context, .{
            .cascade = cascade,
            .text = item_text,
            .cluster_base = byte_start,
            .pen = self.pen,
        });
    }

    pub fn finish(
        self: *@This(),
        spans: []const styled_paragraph.Span,
    ) !void {
        try bidi_reorder.normalizeLogical(self.buffer);
        try styled_buffer.rebuild(
            &self.styled.metadata,
            self.styled.allocator,
            self.buffer.glyphs.items,
            spans,
        );
        try styled_buffer.applySpacing(
            self.styled.metadata.items,
            self.buffer.glyphs.items,
        );
        const intrinsic_graphemes = try unicode.itemizeGraphemeClusters(
            self.buffer.allocator,
            self.text,
        );
        defer self.buffer.allocator.free(intrinsic_graphemes);
        const intrinsic_breaks = try line_break_analysis.itemizeWithHyphenation(
            self.buffer.allocator,
            self.text,
            intrinsic_graphemes,
            self.options.word_break_dictionary,
            self.options.hyphenation.dictionary,
            .normal,
            .break_word,
        );
        defer self.buffer.allocator.free(intrinsic_breaks);
        self.styled.content_widths = try content_widths.calculate(
            self.buffer.allocator,
            self.text,
            self.buffer.glyphs.items,
            self.buffer.runs.items,
            intrinsic_graphemes,
            intrinsic_breaks,
            self.options,
        );

        var line_options = self.options;
        // Build the truncated prefix first. Synthetic dots are appended after
        // the sidecar has captured the terminal visible style.
        line_options.ellipsis = false;
        var candidate_metadata =
            std.ArrayList(styled_buffer.Metadata).empty;
        defer candidate_metadata.deinit(self.buffer.allocator);
        var commit_metadata =
            std.ArrayList(styled_buffer.Metadata).empty;
        defer commit_metadata.deinit(self.buffer.allocator);
        var trial_metadata =
            std.ArrayList(styled_buffer.Metadata).empty;
        defer trial_metadata.deinit(self.buffer.allocator);
        const recipe = styled_reshape.Recipe{
            .cascade = self.cascade,
            .allocator = self.buffer.allocator,
            .metadata = &self.styled.metadata,
            .candidate_metadata = &candidate_metadata,
            .commit_metadata = &commit_metadata,
            .trial_metadata = &trial_metadata,
            .text = self.text,
            .spans = spans,
            .options = self.options,
        };
        try paragraph_reflow.buildWithJstfShrinkage(
            self.buffer,
            self.text,
            line_options,
            paragraph_reflow.defaultBaselineMetrics(
                self.cascade.fonts[0],
                self.default_font_size,
            ),
            null,
            null,
            self.options.word_break_dictionary,
            self.options.hyphenation.dictionary,
            recipe,
        );
        try styled_buffer.insertAutomaticHyphenMetadata(
            &self.styled.metadata,
            self.styled.allocator,
            self.buffer.glyphs.items,
            spans,
        );
        const content_omitted =
            self.buffer.lines.items.len != 0 and
            self.buffer.lines.items[
                self.buffer.lines.items.len - 1
            ].byteEnd() < self.text.len;
        if (content_omitted and self.buffer.lines.items.len != 0) {
            // Styled layout suppresses ellipsis during reflow so metadata can
            // be synchronized first. Clear the terminal target here as well:
            // the later styled ellipsis pass must never receive an already
            // justified/Kashida-expanded line.
            self.buffer.lines.items[
                self.buffer.lines.items.len - 1
            ].justification_target = null;
        }
        try styled_buffer.synchronizeAfterTruncation(
            &self.styled.metadata,
            self.buffer.glyphs.items.len,
        );
        try jstf_justification.apply(
            self.buffer,
            self.options,
            recipe,
        );
        try jstf_extender.apply(
            self.buffer,
            self.text,
            self.options,
            recipe,
        );
        try font_expansion.apply(
            self.buffer,
            self.options,
            recipe,
        );
        try kashida_justification.apply(
            self.buffer,
            self.text,
            self.options,
            recipe,
        );
        paragraph_reflow.applyPendingJustification(self.buffer);
        if (self.options.ellipsis and content_omitted and
            self.buffer.glyphs.items.len != 0)
        {
            try styled_buffer.appendEllipsis(
                &self.styled.metadata,
                self.styled.allocator,
                self.buffer,
                if (self.options.max_width > 0)
                    self.options.max_width
                else
                    std.math.inf(f32),
                paragraph_reflow.resolvedAlignment(self.options),
                paragraph_reflow.alignedLineX,
                self.options,
            );
        }
        styled_buffer.applyMinimumLineHeights(
            self.styled.metadata.items,
            self.buffer.glyphs.items.len,
            self.buffer.lines.items,
        );
        try punctuation_compression.apply(self.buffer, self.options);
        if (plan_bidi.paragraphNeedsReorder(
            self.text,
            self.options.direction,
        )) {
            const visual_order = try styled_bidi.visualPermutation(
                self.buffer.allocator,
                self.text,
                self.options.direction == .rtl,
                self.buffer.lines.items,
                self.buffer.glyphs.items,
            );
            defer self.buffer.allocator.free(visual_order);
            try bidi_reorder.applyLines(
                self.buffer,
                self.text,
                self.options.direction == .rtl,
            );
            try styled_buffer.reorderByPermutation(
                &self.styled.metadata,
                self.styled.allocator,
                visual_order,
            );
        }
        punctuation_hanging.apply(self.buffer, self.options);
        bidi_reorder.recomputeRunOffsets(self.buffer);
        try inline_object.position(
            self.buffer,
            self.options.inline_objects,
            self.options.out_of_flow_placements,
        );
    }

    fn normalizeNewRunFontIndices(
        self: *@This(),
        run_start: usize,
    ) void {
        // Style-local cascades record local indexes; the public result uses the
        // union paragraph cascade as one stable diagnostic/render index space.
        for (self.buffer.runs.items[run_start..]) |*run| {
            for (self.cascade.fonts, 0..) |font, font_index| {
                if (font != run_types.fontForBackend(run.*)) continue;
                run.font_index = font_index;
                break;
            }
        }
    }
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
        const glyph_start = self.buffer.glyphs.items.len;
        try segment_pipeline.run(.{
            .font = font,
            .metrics_cache = null,
            .glyph_index_cache = null,
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
