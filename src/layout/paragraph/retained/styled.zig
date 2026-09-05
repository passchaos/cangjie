//! Owning, width-independent styled paragraphs and reusable visual reflow.

const std = @import("std");

const face_mod = @import("../../../font/face/root.zig");
const Font = @import("../../../font.zig").Font;
const glyph_position = @import("../../glyph_position.zig");
const inline_object = @import("../../inline_object/root.zig");
const line_break_analysis = @import("../../line_break/analysis.zig");
const line_break_opportunity = @import("../../line_break/opportunity.zig");
const content_widths = @import("../content_widths.zig");
const paragraph_options = @import("../options.zig");
const styled_layout = @import("../styled.zig");
const vertical_columns = @import("../vertical_columns.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const run_types = @import("../../types/runs.zig");
const styled_buffer = @import("../../styled_buffer.zig");
const styled_paragraph = @import("../../styled_paragraph.zig");
const context_output = @import("../../../shaping/context/output.zig");
const font_fallback = @import("../../../shaping/fallback/font/root.zig");
const shaping_plan = @import("../../../shaping/plan/root.zig");
const segmentation = @import("../../../text/segmentation/root.zig");
const unicode = @import("../../../unicode.zig");

pub const Layout = struct {
    layout: paragraph_types.ParagraphLayout,
    glyph_metadata: []const styled_buffer.Metadata,
};

/// Width-independent, owning attributed paragraph content.
///
/// Text, spans (including their face-pointer, feature, and variation slices),
/// pristine glyph/run/metadata streams, and Unicode analysis are copied. The
/// referenced `Face` values and optional dictionaries remain borrowed and must
/// outlive this value and every reflow that uses it.
pub const ShapedParagraph = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    spans: []const styled_paragraph.Span,
    glyphs: []const glyph_position.GlyphPosition,
    runs: []const run_types.CascadeRun,
    normalized_variation_coords: []const f32,
    glyph_metadata: []const styled_buffer.Metadata,
    grapheme_clusters: []const unicode.GraphemeCluster,
    line_breaks: []const line_break_opportunity.Opportunity,
    inline_object_indexes: []const usize,
    /// Original fallback cascade used by spans with `faces = null`.
    cascade_fonts: []const *const Font,
    cascade_locations: font_fallback.OwnedLocations,
    /// Stable public run-index namespace: base cascade followed by unique
    /// style-local faces.
    font_index_fonts: []const *const Font,
    word_break_dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
    default_font_size: f32,
    shape_key: shaping_plan.ShapePlanKey,
    needs_bidi_reorder: bool,
    bidi_paragraph: ?unicode.BidiParagraph,

    pub fn deinit(self: *ShapedParagraph) void {
        if (self.bidi_paragraph) |*paragraph| paragraph.deinit();
        self.allocator.free(self.font_index_fonts);
        self.cascade_locations.deinit();
        self.allocator.free(self.cascade_fonts);
        self.allocator.free(self.inline_object_indexes);
        self.allocator.free(self.line_breaks);
        self.allocator.free(self.grapheme_clusters);
        self.allocator.free(self.glyph_metadata);
        self.allocator.free(self.normalized_variation_coords);
        self.allocator.free(self.runs);
        self.allocator.free(self.glyphs);
        freeSpans(self.allocator, self.spans);
        self.allocator.free(self.text);
        self.* = undefined;
    }

    pub fn shapedText(self: *const ShapedParagraph) run_types.ShapedText {
        return .{
            .glyphs = self.glyphs,
            .runs = self.runs,
            .normalized_variation_coords = self.normalized_variation_coords,
        };
    }

    /// Rebuild final lines and glyph-parallel style metadata without repeating
    /// whole-paragraph shaping. Returned slices borrow `reflow` until reuse.
    pub fn layout(
        self: *const ShapedParagraph,
        reflow: *ReflowBuffer,
        options: paragraph_options.Options,
    ) !Layout {
        try self.validateLayoutOptions(options);
        try reflow.restore(self);
        errdefer reflow.clear();
        const paragraph = try styled_layout.reflow(.{
            .cascade = font_fallback.Cascade.initWithLocations(
                self.cascade_fonts,
                self.cascade_locations.slices,
            ),
            .font_index_cascade = font_fallback.Cascade.init(
                self.font_index_fonts,
            ),
            .buffer = &reflow.buffer,
            .styled = &reflow.styled,
            .scratch = &reflow.scratch,
            .text = self.text,
            .default_font_size = self.default_font_size,
            .spans = self.spans,
            .options = options,
            .grapheme_clusters = self.grapheme_clusters,
            .line_breaks = self.line_breaks,
            .needs_bidi_reorder = self.needs_bidi_reorder,
            .bidi_paragraph = self.bidi_paragraph,
        });
        return .{
            .layout = paragraph,
            .glyph_metadata = reflow.styled.glyphMetadata(),
        };
    }

    /// Calculate styled intrinsic inline-size bounds from retained shaping.
    pub fn contentWidths(
        self: *const ShapedParagraph,
        options: paragraph_options.Options,
    ) !paragraph_types.ContentWidths {
        try self.validateLayoutOptions(options);
        const ranges = try styled_paragraph.resolveLineBreakPolicyRanges(
            self.allocator,
            self.text.len,
            self.spans,
            options,
        );
        defer self.allocator.free(ranges);
        var resolved = options;
        resolved.line_break_policy_ranges = ranges;
        if (resolved.writing_mode.isVertical()) {
            return vertical_columns.contentWidths(
                self.allocator,
                self.text,
                self.glyphs,
                self.runs,
                self.normalized_variation_coords,
                self.grapheme_clusters,
                self.line_breaks,
                resolved,
            );
        }
        return content_widths.calculate(
            self.allocator,
            self.text,
            self.glyphs,
            self.runs,
            self.grapheme_clusters,
            self.line_breaks,
            resolved,
        );
    }

    fn validateLayoutOptions(
        self: *const ShapedParagraph,
        options: paragraph_options.Options,
    ) !void {
        try paragraph_options.validateForText(self.text, options);
        try inline_object.validateRetained(
            self.inline_object_indexes,
            options.inline_objects,
        );
        if (options.word_break_dictionary != self.word_break_dictionary or
            options.hyphenation.dictionary != self.hyphenation_dictionary or
            !matchesShapeOptions(self, options))
        {
            return error.ParagraphShapingOptionsChanged;
        }
    }
};

fn matchesShapeOptions(
    paragraph: *const ShapedParagraph,
    options: paragraph_options.Options,
) bool {
    const candidate = styled_layout.shapeKey(paragraph.text, options);
    // Both vertical modes use the same OpenType shaping orientation. Physical
    // right-to-left versus left-to-right column progression remains a reflow
    // choice and therefore does not invalidate the retained glyph stream.
    return candidate.direction == paragraph.shape_key.direction and
        candidate.reorder_bidi == paragraph.shape_key.reorder_bidi and
        candidate.native_direction_shaping ==
            paragraph.shape_key.native_direction_shaping and
        candidate.writing_mode == paragraph.shape_key.writing_mode and
        candidate.text_orientation == paragraph.shape_key.text_orientation and
        candidate.script_tag == paragraph.shape_key.script_tag and
        candidate.language_tag == paragraph.shape_key.language_tag and
        candidate.script_position == paragraph.shape_key.script_position and
        candidate.beginning_of_text == paragraph.shape_key.beginning_of_text and
        candidate.end_of_text == paragraph.shape_key.end_of_text and
        candidate.not_found_variation_selector_glyph ==
            paragraph.shape_key.not_found_variation_selector_glyph and
        candidate.remove_default_ignorables ==
            paragraph.shape_key.remove_default_ignorables and
        candidate.cluster_level == paragraph.shape_key.cluster_level;
}

/// Mutable storage shared by repeated layouts of an immutable styled owner.
pub const ReflowBuffer = struct {
    buffer: context_output.Buffer,
    styled: styled_buffer.Buffer,
    scratch: styled_layout.ReflowScratch = .{},

    pub fn init(allocator: std.mem.Allocator) ReflowBuffer {
        return .{
            .buffer = context_output.Buffer.init(allocator),
            .styled = styled_buffer.Buffer.init(allocator),
        };
    }

    pub fn deinit(self: *ReflowBuffer) void {
        const allocator = self.buffer.allocator;
        self.scratch.deinit(allocator);
        self.styled.deinit();
        self.buffer.deinit();
        self.* = undefined;
    }

    fn clear(self: *ReflowBuffer) void {
        self.scratch.clear();
        self.styled.clear();
        self.buffer.clear();
    }

    fn restore(
        self: *ReflowBuffer,
        paragraph: *const ShapedParagraph,
    ) !void {
        self.clear();
        try self.buffer.variation_coords.ensureTotalCapacity(
            self.buffer.allocator,
            paragraph.normalized_variation_coords.len,
        );
        try self.buffer.glyphs.ensureTotalCapacity(
            self.buffer.allocator,
            paragraph.glyphs.len,
        );
        try self.buffer.runs.ensureTotalCapacity(
            self.buffer.allocator,
            paragraph.runs.len,
        );
        try self.buffer.inline_objects.ensureTotalCapacity(
            self.buffer.allocator,
            paragraph.inline_object_indexes.len,
        );
        try self.styled.metadata.ensureTotalCapacity(
            self.styled.allocator,
            paragraph.glyph_metadata.len,
        );
        errdefer self.clear();
        self.buffer.variation_coords.appendSliceAssumeCapacity(
            paragraph.normalized_variation_coords,
        );
        self.buffer.glyphs.appendSliceAssumeCapacity(paragraph.glyphs);
        self.buffer.runs.appendSliceAssumeCapacity(paragraph.runs);
        self.styled.metadata.appendSliceAssumeCapacity(
            paragraph.glyph_metadata,
        );
    }
};

/// Build the owning snapshot from the engine's reusable shaping buffers.
pub fn prepare(
    allocator: std.mem.Allocator,
    cascade: font_fallback.Cascade,
    buffer: *context_output.Buffer,
    styled: *styled_buffer.Buffer,
    text: []const u8,
    default_font_size: f32,
    spans: []const styled_paragraph.Span,
    options: paragraph_options.Options,
) !ShapedParagraph {
    // Retained line-local reshaping needs one stable public font-index
    // namespace. Extend the caller's paragraph cascade with every unique
    // style-local face instead of narrowing the existing one-shot API.
    try styled_layout.validate(.{
        .cascade = cascade,
        .buffer = buffer,
        .styled = styled,
        .text = text,
        .default_font_size = default_font_size,
        .spans = spans,
        .options = options,
        .compute_content_widths = false,
    });
    const union_fonts = try buildUnionCascade(allocator, cascade, spans);
    errdefer allocator.free(union_fonts);
    const retained_cascade = font_fallback.Cascade.init(union_fonts);
    var bidi_paragraph = try styled_layout.prepare(.{
        .cascade = cascade,
        .font_index_cascade = retained_cascade,
        .buffer = buffer,
        .styled = styled,
        .text = text,
        .default_font_size = default_font_size,
        .spans = spans,
        .options = options,
        .compute_content_widths = false,
    });
    errdefer if (bidi_paragraph) |*paragraph| paragraph.deinit();

    const owned_text = try allocator.dupe(u8, text);
    errdefer allocator.free(owned_text);
    const owned_spans = try cloneSpans(allocator, spans);
    errdefer freeSpans(allocator, owned_spans);
    const owned_glyphs = try allocator.dupe(
        glyph_position.GlyphPosition,
        buffer.glyphs.items,
    );
    errdefer allocator.free(owned_glyphs);
    const owned_runs = try allocator.dupe(run_types.CascadeRun, buffer.runs.items);
    errdefer allocator.free(owned_runs);
    const owned_coords = try allocator.dupe(f32, buffer.variation_coords.items);
    errdefer allocator.free(owned_coords);
    const owned_metadata = try allocator.dupe(
        styled_buffer.Metadata,
        styled.metadata.items,
    );
    errdefer allocator.free(owned_metadata);
    const graphemes = try unicode.itemizeGraphemeClusters(allocator, owned_text);
    errdefer allocator.free(graphemes);
    const line_breaks = try line_break_analysis.itemizeWithHyphenation(
        allocator,
        owned_text,
        graphemes,
        options.word_break_dictionary,
        options.hyphenation.dictionary,
        .{
            .wrap_mode = .word,
            .word_break = .normal,
            .overflow_wrap = .break_word,
        },
        &.{},
    );
    errdefer allocator.free(line_breaks);
    const object_indexes = try allocator.alloc(usize, options.inline_objects.len);
    errdefer allocator.free(object_indexes);
    for (object_indexes, options.inline_objects) |*index, object| {
        index.* = object.byte_index;
    }
    const cascade_fonts = try allocator.dupe(*const Font, cascade.fonts);
    errdefer allocator.free(cascade_fonts);
    var cascade_locations = try font_fallback.OwnedLocations.init(
        allocator,
        cascade.normalized_variation_locations,
    );
    errdefer cascade_locations.deinit();
    return .{
        .allocator = allocator,
        .text = owned_text,
        .spans = owned_spans,
        .glyphs = owned_glyphs,
        .runs = owned_runs,
        .normalized_variation_coords = owned_coords,
        .glyph_metadata = owned_metadata,
        .grapheme_clusters = graphemes,
        .line_breaks = line_breaks,
        .inline_object_indexes = object_indexes,
        .cascade_fonts = cascade_fonts,
        .cascade_locations = cascade_locations,
        .font_index_fonts = union_fonts,
        .word_break_dictionary = options.word_break_dictionary,
        .hyphenation_dictionary = options.hyphenation.dictionary,
        .default_font_size = default_font_size,
        .shape_key = styled_layout.shapeKey(owned_text, options),
        .needs_bidi_reorder = bidi_paragraph != null,
        .bidi_paragraph = bidi_paragraph,
    };
}

/// Preserve `faces = null` as inheritance from the original paragraph
/// cascade while preparation uses the larger union only as a stable run-index
/// namespace. Otherwise fonts contributed by a different explicit style span
/// could incorrectly become fallback candidates for an inheriting span.
fn buildUnionCascade(
    allocator: std.mem.Allocator,
    base: font_fallback.Cascade,
    spans: []const styled_paragraph.Span,
) ![]const *const Font {
    var fonts = std.ArrayList(*const Font).empty;
    defer fonts.deinit(allocator);
    try fonts.appendSlice(allocator, base.fonts);
    for (spans) |span| {
        const faces = span.faces orelse continue;
        for (faces) |face| {
            const font = face_mod.backend.font(face);
            var found = false;
            for (fonts.items) |existing| {
                if (existing == font) {
                    found = true;
                    break;
                }
            }
            if (!found) try fonts.append(allocator, font);
        }
    }
    return fonts.toOwnedSlice(allocator);
}

fn cloneSpans(
    allocator: std.mem.Allocator,
    source: []const styled_paragraph.Span,
) ![]const styled_paragraph.Span {
    const spans = try allocator.alloc(styled_paragraph.Span, source.len);
    errdefer allocator.free(spans);
    var initialized: usize = 0;
    errdefer freeSpanContents(allocator, spans[0..initialized]);
    for (source, spans) |input, *output| {
        output.* = input;
        output.features = &.{};
        output.normalized_variation_coords = &.{};
        output.normalized_variation_locations = null;
        output.faces = null;
        if (input.faces) |faces| {
            output.faces = try allocator.dupe(*const face_mod.Face, faces);
        }
        errdefer if (output.faces) |faces| allocator.free(faces);
        output.features = try allocator.dupe(unicode.FeatureOverride, input.features);
        errdefer if (output.features.len != 0) allocator.free(output.features);
        output.normalized_variation_coords = try allocator.dupe(
            f32,
            input.normalized_variation_coords,
        );
        if (input.normalized_variation_locations) |locations| {
            const owned_locations = try cloneVariationLocations(
                allocator,
                locations,
            );
            output.normalized_variation_locations = owned_locations;
        }
        initialized += 1;
    }
    return spans;
}

fn freeSpans(
    allocator: std.mem.Allocator,
    spans: []const styled_paragraph.Span,
) void {
    freeSpanContents(allocator, spans);
    allocator.free(spans);
}

fn freeSpanContents(
    allocator: std.mem.Allocator,
    spans: []const styled_paragraph.Span,
) void {
    for (spans) |span| {
        if (span.faces) |faces| allocator.free(faces);
        allocator.free(span.features);
        allocator.free(span.normalized_variation_coords);
        if (span.normalized_variation_locations) |locations| {
            freeVariationLocations(allocator, locations);
        }
    }
}

fn cloneVariationLocations(allocator: std.mem.Allocator, source: []const []const f32) ![]const []const f32 {
    const result = try allocator.alloc([]const f32, source.len);
    errdefer allocator.free(result);
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |location| allocator.free(location);
    for (source, result) |location, *owned| {
        owned.* = try allocator.dupe(f32, location);
        initialized += 1;
    }
    return result;
}

fn freeVariationLocations(allocator: std.mem.Allocator, locations: []const []const f32) void {
    for (locations) |location| allocator.free(location);
    allocator.free(locations);
}
