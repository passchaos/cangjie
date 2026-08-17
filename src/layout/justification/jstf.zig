//! OpenType JSTF priority application for source-shaped logical lines.
//!
//! Priority levels stand alone. Each candidate starts from original source,
//! applies the priority's extension suggestion, and is accepted transactionally
//! only when it widens the selected line without exceeding the target.

const std = @import("std");

const font_mod = @import("../../font.zig");
const Font = font_mod.Font;
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const geometry = @import("../line_break/reflow/geometry.zig");
const line_transaction = @import("line_transaction.zig");
const paragraph_types = @import("../types/paragraph.zig");
const run_types = @import("../types/runs.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const unicode = @import("../../unicode.zig");

const width_epsilon: f32 = 0.001;

pub fn apply(
    buffer: anytype,
    options: anytype,
    recipe: anytype,
) !void {
    if (options.alignment != .justify or buffer.lines.items.len == 0) return;

    var work = @TypeOf(buffer.*).init(buffer.allocator);
    defer work.deinit();
    var natural = @TypeOf(buffer.*).init(buffer.allocator);
    defer natural.deinit();
    // Temporary candidates are separate output owners, but they shape the
    // same borrowed fonts on the same thread. Reuse the caller's immutable
    // font metadata, proof, and lookup-selection caches so Engine-backed
    // paragraph layout does not silently drop to the uncached path.
    inheritShapeCaches(buffer, &work);
    inheritShapeCaches(buffer, &natural);

    var line_index: usize = 0;
    while (line_index < buffer.lines.items.len) : (line_index += 1) {
        const line = buffer.lines.items[line_index];
        const target = line.justification_target orelse continue;
        const source_range = reusableSourceRange(
            buffer.glyphs.items,
            line,
        ) orelse continue;
        if (!recipe.canExpandSourceRange(source_range.start, source_range.end)) {
            continue;
        }
        const run = singleOwningRun(buffer.runs.items, line) orelse continue;
        const font = run_types.fontForBackend(run);
        const info = (try font.jstfInfo(buffer.allocator)) orelse continue;
        defer font.freeJstfInfo(buffer.allocator, info);
        const tags = recipe.jstfTags(source_range.start, source_range.end);
        const language = selectLanguage(
            info,
            tags.script,
            tags.language,
        ) orelse continue;
        const natural_width = geometry.lineWidth(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        );
        if (target <= natural_width + width_epsilon) continue;

        for (language.priorities) |priority| {
            var lookup_offsets_stack: [32]usize = undefined;
            if (priority.extension_max.len > lookup_offsets_stack.len) continue;
            for (
                priority.extension_max,
                lookup_offsets_stack[0..priority.extension_max.len],
            ) |lookup, *offset| {
                offset.* = lookup.offset;
            }
            const lookup_offsets =
                lookup_offsets_stack[0..priority.extension_max.len];
            const modifications = pipeline_types.JstfModifications{
                .gsub_enable = priority.extension_enable_gsub.indices,
                .gsub_disable = priority.extension_disable_gsub.indices,
                .gpos_enable = priority.extension_enable_gpos.indices,
                .gpos_disable = priority.extension_disable_gpos.indices,
            };
            if (allEmpty(modifications) and lookup_offsets.len == 0) continue;
            try recipe.shapeLineWithJstfPriority(
                &work,
                source_range.start,
                source_range.end - source_range.start,
                font,
                run.font_index,
                modifications,
                lookup_offsets,
            );
            const maximum_width = geometry.lineWidth(work.glyphs.items);
            if (maximum_width <= natural_width + width_epsilon) continue;

            if (maximum_width > target + width_epsilon) {
                try recipe.shapeLineWithJstfPriority(
                    &natural,
                    source_range.start,
                    source_range.end - source_range.start,
                    font,
                    run.font_index,
                    .{},
                    &.{},
                );
                if (!sameStructure(natural, work)) continue;
                const fraction = @min(
                    @as(f32, 1),
                    @max(
                        @as(f32, 0),
                        (target - natural_width) /
                            (maximum_width - natural_width),
                    ),
                );
                interpolateGlyphGeometry(
                    natural.glyphs.items,
                    work.glyphs.items,
                    fraction,
                );
            }
            const final_width = geometry.lineWidth(work.glyphs.items);
            if (final_width <= natural_width + width_epsilon or
                final_width > target + width_epsilon)
            {
                continue;
            }
            try recipe.prepareCommit(
                line.glyph_start,
                line.glyph_len,
                work.glyphs.items.len,
            );
            try line_transaction.replace(
                buffer,
                line_index,
                work.glyphs.items,
                work.runs.items,
                work.variation_coords.items,
                final_width,
            );
            recipe.commit(
                line.glyph_start,
                line.glyph_len,
                work.glyphs.items.len,
            );
            break;
        }
    }
}

fn inheritShapeCaches(source: anytype, destination: anytype) void {
    destination.gdef_metadata_cache = source.gdef_metadata_cache;
    destination.gsub_table_proof_cache = source.gsub_table_proof_cache;
    destination.gpos_table_proof_cache = source.gpos_table_proof_cache;
    destination.lookup_selection_cache = source.lookup_selection_cache;
}

fn allEmpty(
    modifications: pipeline_types.JstfModifications,
) bool {
    return modifications.gsub_enable.len == 0 and
        modifications.gsub_disable.len == 0 and
        modifications.gpos_enable.len == 0 and
        modifications.gpos_disable.len == 0;
}

fn selectLanguage(
    info: font_mod.JstfInfo,
    script_tag: unicode.OpenTypeScriptTag,
    language_tag: unicode.OpenTypeLanguageTag,
) ?font_mod.JstfLanguageInfo {
    const script_bytes = tagBytes(@intFromEnum(script_tag));
    for (info.scripts) |script| {
        if (!std.mem.eql(u8, &script.tag, &script_bytes)) continue;
        const language_bytes = tagBytes(@intFromEnum(language_tag));
        for (script.languages) |candidate| {
            if (candidate.tag != null and
                std.mem.eql(u8, &candidate.tag.?, &language_bytes))
            {
                return candidate;
            }
        }
        return script.default_language;
    }
    return null;
}

fn tagBytes(value: u32) [4]u8 {
    return .{
        @intCast(value >> 24),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    };
}

fn sameStructure(a: anytype, b: anytype) bool {
    if (a.glyphs.items.len != b.glyphs.items.len or
        a.runs.items.len != b.runs.items.len)
    {
        return false;
    }
    for (a.glyphs.items, b.glyphs.items) |lhs, rhs| {
        if (lhs.glyph_id != rhs.glyph_id or
            lhs.cluster != rhs.cluster or
            lhs.source_byte_len != rhs.source_byte_len or
            lhs.codepoint != rhs.codepoint)
        {
            return false;
        }
    }
    return true;
}

fn interpolateGlyphGeometry(
    natural: []const GlyphPosition,
    maximum: []GlyphPosition,
    fraction: f32,
) void {
    for (natural, maximum) |base, *candidate| {
        candidate.x_advance = lerp(base.x_advance, candidate.x_advance, fraction);
        candidate.y_advance = lerp(base.y_advance, candidate.y_advance, fraction);
        candidate.x_offset = lerp(base.x_offset, candidate.x_offset, fraction);
        candidate.y_offset = lerp(base.y_offset, candidate.y_offset, fraction);
    }
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

const SourceRange = struct {
    start: usize,
    end: usize,
};

fn reusableSourceRange(
    glyphs: []const GlyphPosition,
    line: paragraph_types.ParagraphLine,
) ?SourceRange {
    if (line.glyph_len == 0) return null;
    var start: usize = std.math.maxInt(usize);
    var end: usize = 0;
    for (glyphs[line.glyph_start .. line.glyph_start + line.glyph_len]) |glyph| {
        if (glyph.isInlineObject() or
            glyph.isDiscretionaryHyphen() or
            glyph.isKashida() or
            glyph.isAutomaticHyphen() or
            glyph.codepoint == '\t' or
            isMandatoryBreak(glyph.codepoint))
        {
            return null;
        }
        start = @min(start, glyph.cluster);
        end = @max(end, glyph.sourceByteEnd());
    }
    if (start == std.math.maxInt(usize) or start >= end) return null;
    return .{ .start = start, .end = end };
}

fn singleOwningRun(
    runs: []const run_types.CascadeRun,
    line: paragraph_types.ParagraphLine,
) ?run_types.CascadeRun {
    const line_end = line.glyph_start + line.glyph_len;
    var owner: ?run_types.CascadeRun = null;
    for (runs) |run| {
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= line.glyph_start or run.glyph_start >= line_end) continue;
        if (owner != null) return null;
        owner = run;
    }
    const run = owner orelse return null;
    if (run.glyph_start > line.glyph_start or
        run.glyph_start + run.glyph_len < line_end)
    {
        return null;
    }
    return run;
}

fn isMandatoryBreak(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}
