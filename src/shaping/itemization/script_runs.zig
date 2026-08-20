//! Map a shaped glyph stream back onto Unicode script byte ranges.

const std = @import("std");

const glyph_position = @import("../../layout/glyph_position.zig");
const pipeline_types = @import("../pipeline/types.zig");
const run_types = @import("../../layout/types/runs.zig");
const unicode = @import("../../unicode.zig");

pub fn rebuild(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(run_types.ScriptedRun),
    glyphs: []const glyph_position.GlyphPosition,
    text: []const u8,
    direction: pipeline_types.TextDirection,
    language_tag: ?unicode.OpenTypeLanguageTag,
) !void {
    out.clearRetainingCapacity();
    const script_runs = try unicode.itemizeScriptRuns(allocator, text);
    defer allocator.free(script_runs);

    if (direction == .ltr) {
        for (script_runs) |script_run| {
            try appendForByteRange(
                allocator,
                out,
                glyphs,
                text,
                script_run,
                language_tag,
            );
        }
        return;
    }

    var index = script_runs.len;
    while (index > 0) {
        index -= 1;
        try appendForByteRange(
            allocator,
            out,
            glyphs,
            text,
            script_runs[index],
            language_tag,
        );
    }
}

fn appendForByteRange(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(run_types.ScriptedRun),
    glyphs: []const glyph_position.GlyphPosition,
    text: []const u8,
    script_run: unicode.ScriptRun,
    language_tag: ?unicode.OpenTypeLanguageTag,
) !void {
    const byte_start = script_run.byte_start;
    const byte_end = script_run.byte_start + script_run.byte_len;
    var glyph_start: ?usize = null;
    var glyph_end: usize = 0;
    for (glyphs, 0..) |glyph, index| {
        if (glyph.cluster < byte_start or glyph.cluster >= byte_end) continue;
        if (glyph_start == null) glyph_start = index;
        glyph_end = index + 1;
    }
    if (glyph_start == null) return;

    try out.append(allocator, .{
        .script = script_run.script,
        .script_tag = unicode.openTypeScriptTag(script_run.script),
        .language_tag = language_tag orelse
            unicode.inferOpenTypeLanguageTag(text[byte_start..byte_end]),
        .glyph_start = glyph_start.?,
        .glyph_len = glyph_end - glyph_start.?,
        .byte_start = byte_start,
        .byte_len = script_run.byte_len,
    });
}
