//! Attributed UTF-8 records and standalone attributed layout helpers.

const std = @import("std");

const core = @import("../../../core.zig");
const face_mod = @import("../../../font/face/root.zig");
const paragraph_types = @import("../../../layout/types/paragraph.zig");
const context_output = @import("../../../shaping/context/output.zig");
const font_fallback = @import("../../../shaping/fallback/font/root.zig");

pub const Text = core.AttributedText;
pub const Run = core.AttributedRun;
pub const RunLayout = core.AttributedRunLayout;
pub const GlyphRun = core.AttributedGlyphRun;
pub const GlyphRunLayout = core.AttributedGlyphRunLayout;
pub const ParagraphLayout = core.AttributedParagraphLayout;
pub const StyleRun = core.AttributedStyleRun;

pub fn measure(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
    max_width: f32,
) !paragraph_types.TextMetrics {
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    return core.measureAttributedTextUtf8(
        internalCascade(cascade),
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
    return core.measureAttributedRunsUtf8(
        allocator,
        internalCascade(cascade),
        attributed,
    );
}

pub fn layoutRuns(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
) !RunLayout {
    return core.layoutAttributedRunsUtf8(
        allocator,
        internalCascade(cascade),
        attributed,
    );
}

pub fn layoutGlyphRuns(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
) !GlyphRunLayout {
    return core.layoutAttributedGlyphRunsUtf8(
        allocator,
        internalCascade(cascade),
        attributed,
    );
}

pub fn layoutParagraph(
    allocator: std.mem.Allocator,
    cascade: face_mod.Cascade,
    attributed: Text,
    max_width: f32,
) !ParagraphLayout {
    return core.layoutAttributedParagraphUtf8(
        allocator,
        internalCascade(cascade),
        attributed,
        max_width,
    );
}

fn internalCascade(cascade: face_mod.Cascade) font_fallback.Cascade {
    return .init(face_mod.backend.fonts(cascade.faces));
}
