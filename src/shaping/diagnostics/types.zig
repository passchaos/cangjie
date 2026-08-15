//! Stable renderer-free shaping diagnostic records.

const std = @import("std");

const GlyphId = @import("../../glyph.zig").GlyphId;
const unicode = @import("../../unicode.zig");

pub const FontFallbackDecision = struct {
    byte_start: usize,
    byte_len: usize,
    codepoint: u21,
    variation_selector: ?u21 = null,
    font_index: usize,
    glyph_id: GlyphId,
    used_variation_mapping: bool = false,

    pub fn missingGlyph(self: FontFallbackDecision) bool {
        return self.glyph_id == 0;
    }
};

pub const MissingGlyphDiagnostic = struct {
    byte_start: usize,
    byte_len: usize,
    codepoint: u21,
    variation_selector: ?u21 = null,
    font_index: usize,
    glyph_id: GlyphId,
};

pub const ShapeQualityFontRunDiagnostic = struct {
    font_index: usize,
    glyph_start: usize,
    glyph_len: usize,
    byte_start: usize,
    byte_len: usize,
    missing_glyph_count: usize,
    zero_advance_glyph_count: usize,
    horizontal_advance: f32,
    vertical_advance: f32,
};

pub const ShapeQualityScriptRunDiagnostic = struct {
    script: unicode.Script,
    script_tag: unicode.OpenTypeScriptTag,
    language_tag: unicode.OpenTypeLanguageTag,
    glyph_start: usize,
    glyph_len: usize,
    byte_start: usize,
    byte_len: usize,
    font_run_count: usize,
    missing_glyph_count: usize,
    fallback_glyph_count: usize,
    zero_advance_glyph_count: usize,
    horizontal_advance: f32,
    vertical_advance: f32,
};

pub const ShapeQualityReport = struct {
    glyph_count: usize,
    font_run_count: usize,
    missing_glyph_count: usize,
    variation_selector_count: usize,
    fallback_glyph_count: usize,
    zero_advance_glyph_count: usize,
    horizontal_advance: f32,
    vertical_advance: f32,
    missing_glyphs: []MissingGlyphDiagnostic,
    font_runs: []ShapeQualityFontRunDiagnostic,
    script_runs: []ShapeQualityScriptRunDiagnostic,

    pub fn deinit(self: *ShapeQualityReport, allocator: std.mem.Allocator) void {
        allocator.free(self.script_runs);
        allocator.free(self.font_runs);
        allocator.free(self.missing_glyphs);
        self.* = undefined;
    }
};

pub const ClusterCaretIssueKind = enum {
    glyph_cluster_out_of_bounds,
    glyph_source_end_out_of_bounds,
    empty_source_span,
    cluster_not_utf8_boundary,
    source_end_not_utf8_boundary,
    leading_caret_roundtrip_mismatch,
    trailing_caret_roundtrip_mismatch,
    grapheme_boundary_roundtrip_mismatch,
};

pub const ClusterCaretDiagnostic = struct {
    kind: ClusterCaretIssueKind,
    glyph_index: ?usize = null,
    cluster: usize = 0,
    source_end: usize = 0,
    expected_byte_offset: usize = 0,
    actual_byte_offset: usize = 0,
};

pub const ClusterCaretConsistencyReport = struct {
    glyph_count: usize,
    caret_boundary_count: usize,
    grapheme_boundary_count: usize,
    issue_count: usize,
    issues: []ClusterCaretDiagnostic,

    pub fn deinit(
        self: *ClusterCaretConsistencyReport,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.issues);
        self.* = undefined;
    }
};
