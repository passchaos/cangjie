//! OpenType JSTF ExtenderGlyph source insertion.
//!
//! `ExtenderGlyph` stores glyph ids, not Unicode scalars or insertion points.
//! Cangjie therefore uses only the existing SAFE_TO_INSERT_TATWEEL source
//! boundaries, inserts a real U+0640 scalar, runs the complete shaper, and
//! accepts the candidate only when a zero-source-byte output glyph belongs to
//! the selected script's ExtenderGlyph set. A font whose extender set is not
//! reachable through U+0640 is skipped rather than receiving a fabricated
//! positioned glyph.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const geometry = @import("../../line_break/reflow/geometry.zig");
const kashida = @import("../kashida.zig");
const line_transaction = @import("../line_transaction.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const run_types = @import("../../types/runs.zig");
const shared = @import("shared.zig");

pub fn apply(
    buffer: anytype,
    text: []const u8,
    options: anytype,
    recipe: anytype,
) !void {
    if (options.alignment != .justify or
        !options.jstf.enabled or
        options.jstf.max_extender_insertions_per_line == 0 or
        buffer.lines.items.len == 0)
    {
        return;
    }

    var work = @TypeOf(buffer.*).init(buffer.allocator);
    defer work.deinit();
    shared.inheritShapeCaches(buffer, &work);
    var temporary_text = std.ArrayList(u8).empty;
    defer temporary_text.deinit(buffer.allocator);
    var boundaries = std.ArrayList(kashida.Boundary).empty;
    defer boundaries.deinit(buffer.allocator);
    var adopted_glyphs = std.ArrayList(GlyphPosition).empty;
    defer adopted_glyphs.deinit(buffer.allocator);
    var adopted_runs = std.ArrayList(run_types.CascadeRun).empty;
    defer adopted_runs.deinit(buffer.allocator);
    var adopted_variation_coords = std.ArrayList(f32).empty;
    defer adopted_variation_coords.deinit(buffer.allocator);

    var line_index: usize = 0;
    while (line_index < buffer.lines.items.len) : (line_index += 1) {
        const line = buffer.lines.items[line_index];
        const target = line.justification_target orelse continue;
        if (line.glyph_len == 0 or
            kashida.lineContainsSynthetic(buffer.glyphs.items, line))
        {
            continue;
        }
        const source_range = kashida.visibleSourceRange(
            buffer.glyphs.items,
            line,
        ) orelse continue;
        const run = shared.singleOwningRun(buffer.runs.items, line) orelse
            continue;
        const font = run_types.fontForBackend(run);
        const info = (try font.jstfInfo(buffer.allocator)) orelse continue;
        defer font.freeJstfInfo(buffer.allocator, info);
        const extender_glyphs = extendersForRange(
            info,
            recipe,
            source_range,
        ) orelse continue;

        // The current safety sidecar proves only U+0640 insertion. Require that
        // the nominal Tatweel mapping itself is one of the authored extenders;
        // later GSUB may still replace it with another listed extender.
        const tatweel_glyph = try font.glyphIndex(0x0640);
        if (!glyphInSortedSet(extender_glyphs, tatweel_glyph)) continue;
        try kashida.collectJstfExtenderBoundaries(
            &boundaries,
            buffer.allocator,
            buffer.glyphs.items,
            buffer.runs.items,
            line,
            recipe,
        );
        if (boundaries.items.len == 0) continue;

        adopted_glyphs.clearRetainingCapacity();
        adopted_runs.clearRetainingCapacity();
        adopted_variation_coords.clearRetainingCapacity();
        var adopted_width = geometry.lineWidth(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        );
        var insertion_count: usize = 0;
        while (insertion_count <
            options.jstf.max_extender_insertions_per_line)
        {
            insertion_count += 1;
            try kashida.buildTemporaryLine(
                &temporary_text,
                buffer.allocator,
                text[source_range.start..source_range.end],
                source_range.start,
                boundaries.items,
                insertion_count,
            );
            try recipe.shapeLine(
                &work,
                temporary_text.items,
                source_range.start,
                source_range.end - source_range.start,
                boundaries.items,
                insertion_count,
            );
            try kashida.normalizeTemporaryClusters(
                work.glyphs.items,
                source_range.start,
                source_range.end - source_range.start,
                boundaries.items,
                insertion_count,
            );
            try recipe.finishLine(&work);
            if (!containsInsertedExtender(work.glyphs.items, extender_glyphs)) {
                continue;
            }

            const candidate_width = geometry.lineWidth(work.glyphs.items);
            if (candidate_width <= adopted_width + shared.width_epsilon or
                candidate_width > target + shared.width_epsilon)
            {
                continue;
            }
            adopted_glyphs.clearRetainingCapacity();
            adopted_runs.clearRetainingCapacity();
            adopted_variation_coords.clearRetainingCapacity();
            try adopted_glyphs.appendSlice(
                buffer.allocator,
                work.glyphs.items,
            );
            try adopted_runs.appendSlice(
                buffer.allocator,
                work.runs.items,
            );
            try adopted_variation_coords.appendSlice(
                buffer.allocator,
                work.variation_coords.items,
            );
            try recipe.saveCandidate();
            adopted_width = candidate_width;
            if (target - adopted_width <= shared.width_epsilon) break;
        }

        if (adopted_glyphs.items.len == 0) continue;
        try recipe.prepareCommit(
            line.glyph_start,
            line.glyph_len,
            adopted_glyphs.items.len,
        );
        try line_transaction.replace(
            buffer,
            line_index,
            adopted_glyphs.items,
            adopted_runs.items,
            adopted_variation_coords.items,
            adopted_width,
        );
        recipe.commit(
            line.glyph_start,
            line.glyph_len,
            adopted_glyphs.items.len,
        );
    }
}

fn extendersForRange(
    info: font_mod.JstfInfo,
    recipe: anytype,
    source_range: kashida.SourceRange,
) ?[]const @import("../../../glyph.zig").GlyphId {
    const tags = recipe.jstfTags(source_range.start, source_range.end);
    const tag = tagBytes(@intFromEnum(tags.script));
    for (info.scripts) |script| {
        if (!std.mem.eql(u8, &script.tag, &tag)) continue;
        if (script.extender_glyphs.len == 0) return null;
        return script.extender_glyphs;
    }
    return null;
}

fn containsInsertedExtender(
    glyphs: []const GlyphPosition,
    extenders: []const @import("../../../glyph.zig").GlyphId,
) bool {
    for (glyphs) |glyph| {
        if (!glyph.isKashida() or glyph.source_byte_len != 0) continue;
        if (glyphInSortedSet(extenders, glyph.glyph_id)) return true;
    }
    return false;
}

fn glyphInSortedSet(
    glyphs: []const @import("../../../glyph.zig").GlyphId,
    needle: @import("../../../glyph.zig").GlyphId,
) bool {
    var low: usize = 0;
    var high = glyphs.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (glyphs[middle] < needle) low = middle + 1 else high = middle;
    }
    return low < glyphs.len and glyphs[low] == needle;
}

fn tagBytes(value: u32) [4]u8 {
    return .{
        @intCast(value >> 24),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    };
}

test "extender lookup requires inserted zero-source output" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 7,
            .codepoint = 0x0640,
            .cluster = 2,
            .source_byte_len = 0,
            .x_advance = 5,
            .flags = .{ .kashida = true },
        },
        .{
            .glyph_id = 8,
            .codepoint = 0x0640,
            .cluster = 3,
            .source_byte_len = 2,
            .x_advance = 5,
        },
    };
    try std.testing.expect(containsInsertedExtender(&glyphs, &.{7}));
    try std.testing.expect(!containsInsertedExtender(&glyphs, &.{8}));
}
