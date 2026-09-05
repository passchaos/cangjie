//! Attributed UTF-8 records and standalone attributed layout helpers.

const std = @import("std");

const face_mod = @import("../../../font/face/root.zig");
const paragraph_types = @import("../../../layout/types/paragraph.zig");
const context_output = @import("../../../shaping/context/output.zig");
const font_fallback = @import("../../../shaping/fallback/font/root.zig");
const attributed_model = @import("../../../text/attributed/root.zig");

pub const Text = attributed_model.AttributedText;
pub const Run = attributed_model.AttributedRun;
pub const RunLayout = attributed_model.AttributedRunLayout;
pub const GlyphRun = attributed_model.AttributedGlyphRun;
pub const GlyphRunLayout = attributed_model.AttributedGlyphRunLayout;
pub const ParagraphLayout = attributed_model.AttributedParagraphLayout;
pub const StyleRun = attributed_model.AttributedStyleRun;
pub const DecorationKind = attributed_model.TextDecorationKind;
pub const DecorationSegment = attributed_model.TextDecorationSegment;

pub fn measure(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
    max_width: f32,
) !paragraph_types.TextMetrics {
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    return attributed_model.measureAttributedTextUtf8(
        try internalCascade(cascade),
        &buffer,
        attributed,
        max_width,
    );
}

pub fn measureRuns(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
) !paragraph_types.TextMetrics {
    return attributed_model.measureAttributedRunsUtf8(
        allocator,
        try internalCascade(cascade),
        attributed,
    );
}

pub fn layoutRuns(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
) !RunLayout {
    return attributed_model.layoutAttributedRunsUtf8(
        allocator,
        try internalCascade(cascade),
        attributed,
    );
}

pub fn layoutGlyphRuns(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
) !GlyphRunLayout {
    return attributed_model.layoutAttributedGlyphRunsUtf8(
        allocator,
        try internalCascade(cascade),
        attributed,
    );
}

pub fn layoutParagraph(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
    max_width: f32,
) !ParagraphLayout {
    return attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        try internalCascade(cascade),
        attributed,
        max_width,
    );
}

fn internalCascade(cascade: face_mod.Cascade) !font_fallback.Cascade {
    const result = font_fallback.Cascade.initWithLocations(
        face_mod.backend.fonts(cascade.faces),
        cascade.normalized_variation_locations,
    );
    try result.validateLocations();
    return result;
}
