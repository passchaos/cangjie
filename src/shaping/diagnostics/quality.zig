//! Pure aggregation over already-shaped runs and fallback decisions.

const std = @import("std");

const GlyphPosition = @import("../../layout/glyph_position.zig").GlyphPosition;
const run_types = @import("../../layout/types/runs.zig");
const types = @import("types.zig");

pub fn summarize(
    allocator: std.mem.Allocator,
    scripted: run_types.ScriptedText,
    fallback: []const types.FontFallbackDecision,
) !types.ShapeQualityReport {
    var missing = std.ArrayList(types.MissingGlyphDiagnostic).empty;
    errdefer missing.deinit(allocator);
    var font_run_diagnostics =
        std.ArrayList(types.ShapeQualityFontRunDiagnostic).empty;
    errdefer font_run_diagnostics.deinit(allocator);
    var script_run_diagnostics =
        std.ArrayList(types.ShapeQualityScriptRunDiagnostic).empty;
    errdefer script_run_diagnostics.deinit(allocator);

    var variation_selector_count: usize = 0;
    for (fallback) |decision| {
        if (decision.variation_selector != null) {
            variation_selector_count += 1;
        }
        if (!decision.missingGlyph()) continue;
        try missing.append(allocator, .{
            .byte_start = decision.byte_start,
            .byte_len = decision.byte_len,
            .codepoint = decision.codepoint,
            .variation_selector = decision.variation_selector,
            .font_index = decision.font_index,
            .glyph_id = decision.glyph_id,
        });
    }

    var fallback_glyph_count: usize = 0;
    for (scripted.font_runs) |run| {
        if (run.font_index != 0) fallback_glyph_count += run.glyph_len;
        try font_run_diagnostics.append(
            allocator,
            fontRun(run, scripted.glyphs),
        );
    }

    var zero_advance_glyph_count: usize = 0;
    var horizontal_advance: f32 = 0;
    var vertical_advance: f32 = 0;
    for (scripted.glyphs) |glyph| {
        if (glyph.x_advance == 0 and glyph.y_advance == 0) {
            zero_advance_glyph_count += 1;
        }
        horizontal_advance += glyph.x_advance;
        vertical_advance += glyph.y_advance;
    }

    for (scripted.script_runs) |script_run| {
        try script_run_diagnostics.append(
            allocator,
            scriptRun(script_run, scripted),
        );
    }

    const missing_glyphs = try missing.toOwnedSlice(allocator);
    errdefer allocator.free(missing_glyphs);
    const font_runs = try font_run_diagnostics.toOwnedSlice(allocator);
    errdefer allocator.free(font_runs);
    const script_runs = try script_run_diagnostics.toOwnedSlice(allocator);
    return .{
        .glyph_count = scripted.glyphs.len,
        .font_run_count = scripted.font_runs.len,
        .missing_glyph_count = missing_glyphs.len,
        .variation_selector_count = variation_selector_count,
        .fallback_glyph_count = fallback_glyph_count,
        .zero_advance_glyph_count = zero_advance_glyph_count,
        .horizontal_advance = horizontal_advance,
        .vertical_advance = vertical_advance,
        .missing_glyphs = missing_glyphs,
        .font_runs = font_runs,
        .script_runs = script_runs,
    };
}

fn fontRun(
    run: run_types.CascadeRun,
    glyphs: []const GlyphPosition,
) types.ShapeQualityFontRunDiagnostic {
    const run_glyphs =
        glyphs[run.glyph_start .. run.glyph_start + run.glyph_len];
    var byte_start: usize = 0;
    var byte_end: usize = 0;
    var missing_glyph_count: usize = 0;
    var zero_advance_glyph_count: usize = 0;
    var horizontal_advance: f32 = 0;
    var vertical_advance: f32 = 0;

    if (run_glyphs.len != 0) {
        byte_start = run_glyphs[0].cluster;
        byte_end = sourceEnd(run_glyphs[0]);
    }
    for (run_glyphs) |glyph| {
        byte_start = @min(byte_start, glyph.cluster);
        byte_end = @max(byte_end, sourceEnd(glyph));
        if (glyph.glyph_id == 0) missing_glyph_count += 1;
        if (glyph.x_advance == 0 and glyph.y_advance == 0) {
            zero_advance_glyph_count += 1;
        }
        horizontal_advance += glyph.x_advance;
        vertical_advance += glyph.y_advance;
    }

    return .{
        .font_index = run.font_index,
        .glyph_start = run.glyph_start,
        .glyph_len = run.glyph_len,
        .byte_start = byte_start,
        .byte_len = byte_end - byte_start,
        .missing_glyph_count = missing_glyph_count,
        .zero_advance_glyph_count = zero_advance_glyph_count,
        .horizontal_advance = horizontal_advance,
        .vertical_advance = vertical_advance,
    };
}

fn scriptRun(
    run: run_types.ScriptedRun,
    scripted: run_types.ScriptedText,
) types.ShapeQualityScriptRunDiagnostic {
    const glyph_end = run.glyph_start + run.glyph_len;
    var font_run_count: usize = 0;
    var missing_glyph_count: usize = 0;
    var fallback_glyph_count: usize = 0;
    var zero_advance_glyph_count: usize = 0;
    var horizontal_advance: f32 = 0;
    var vertical_advance: f32 = 0;

    for (scripted.glyphs[run.glyph_start..glyph_end]) |glyph| {
        if (glyph.glyph_id == 0) missing_glyph_count += 1;
        if (glyph.x_advance == 0 and glyph.y_advance == 0) {
            zero_advance_glyph_count += 1;
        }
        horizontal_advance += glyph.x_advance;
        vertical_advance += glyph.y_advance;
    }

    for (scripted.font_runs) |font_run| {
        const font_glyph_start = font_run.glyph_start;
        const font_glyph_end = font_run.glyph_start + font_run.glyph_len;
        const overlap_start = @max(run.glyph_start, font_glyph_start);
        const overlap_end = @min(glyph_end, font_glyph_end);
        if (overlap_start >= overlap_end) continue;
        font_run_count += 1;
        if (font_run.font_index != 0) {
            fallback_glyph_count += overlap_end - overlap_start;
        }
    }

    return .{
        .script = run.script,
        .script_tag = run.script_tag,
        .language_tag = run.language_tag,
        .glyph_start = run.glyph_start,
        .glyph_len = run.glyph_len,
        .byte_start = run.byte_start,
        .byte_len = run.byte_len,
        .font_run_count = font_run_count,
        .missing_glyph_count = missing_glyph_count,
        .fallback_glyph_count = fallback_glyph_count,
        .zero_advance_glyph_count = zero_advance_glyph_count,
        .horizontal_advance = horizontal_advance,
        .vertical_advance = vertical_advance,
    };
}

fn sourceEnd(glyph: GlyphPosition) usize {
    return glyph.sourceByteEnd();
}
