//! OpenType JSTF shrinkage candidates for greedy line selection.
//!
//! The line breaker calls this only after the current source atom has overflowed
//! its measure and before selecting a soft/emergency break. Every priority is
//! shaped from the untouched source range. A fitting candidate atomically
//! replaces that still-uncommitted glyph prefix, allowing greedy selection to
//! continue with the next source atom instead of wrapping prematurely.

const geometry = @import("../../line_break/reflow/geometry.zig");
const line_transaction = @import("../line_transaction.zig");
const pipeline_types = @import("../../../shaping/pipeline/types.zig");
const run_types = @import("../../types/runs.zig");
const shared = @import("shared.zig");

pub const Result = struct {
    applied: bool = false,
    glyph_len: usize = 0,
    width: f32 = 0,
};

pub fn tryFit(
    buffer: anytype,
    recipe: anytype,
    glyph_start: usize,
    glyph_end: usize,
    target_width: f32,
) !Result {
    if (target_width <= 0 or glyph_start >= glyph_end) return .{};
    const source_range = shared.reusableSourceRangeForGlyphs(
        buffer.glyphs.items,
        glyph_start,
        glyph_end,
    ) orelse return .{};
    if (!recipe.canShrinkSourceRange(source_range.start, source_range.end)) {
        return .{};
    }
    const run = shared.singleOwningRunForGlyphs(
        buffer.runs.items,
        glyph_start,
        glyph_end,
    ) orelse return .{};
    const font = run_types.fontForBackend(run);
    const info = (try font.jstfInfo(buffer.allocator)) orelse return .{};
    defer font.freeJstfInfo(buffer.allocator, info);
    const tags = recipe.jstfTags(source_range.start, source_range.end);
    const language = shared.selectLanguage(
        info,
        tags.script,
        tags.language,
    ) orelse return .{};

    var work = @TypeOf(buffer.*).init(buffer.allocator);
    defer work.deinit();
    var modified = @TypeOf(buffer.*).init(buffer.allocator);
    defer modified.deinit();
    shared.inheritShapeCaches(buffer, &work);
    shared.inheritShapeCaches(buffer, &modified);

    for (language.priorities) |priority| {
        var lookup_offsets_stack: [32]usize = undefined;
        if (priority.shrinkage_max.len > lookup_offsets_stack.len) continue;
        for (
            priority.shrinkage_max,
            lookup_offsets_stack[0..priority.shrinkage_max.len],
        ) |lookup, *offset| {
            offset.* = lookup.offset;
        }
        const lookup_offsets =
            lookup_offsets_stack[0..priority.shrinkage_max.len];
        const modifications = pipeline_types.JstfModifications{
            .gsub_enable = priority.shrinkage_enable_gsub.indices,
            .gsub_disable = priority.shrinkage_disable_gsub.indices,
            .gpos_enable = priority.shrinkage_enable_gpos.indices,
            .gpos_disable = priority.shrinkage_disable_gpos.indices,
        };
        if (shared.allEmpty(modifications) and lookup_offsets.len == 0) {
            continue;
        }

        // Shape the priority's enable/disable plan first. Embedded JstfMax
        // values describe the optional interval from this modified baseline to
        // the priority's authored maximum, not from the paragraph's original
        // geometry when the modification lists also change glyph selection.
        try recipe.shapeRangeWithJstfPriority(
            &modified,
            source_range.start,
            source_range.end - source_range.start,
            font,
            run.font_index,
            modifications,
            &.{},
        );
        const modified_width = geometry.lineWidth(modified.glyphs.items);
        if (modified_width <= target_width + shared.width_epsilon) {
            return try commit(
                buffer,
                recipe,
                glyph_start,
                glyph_end - glyph_start,
                modified,
                modified_width,
            );
        }
        if (lookup_offsets.len == 0) continue;

        try recipe.shapeRangeWithJstfPriority(
            &work,
            source_range.start,
            source_range.end - source_range.start,
            font,
            run.font_index,
            modifications,
            lookup_offsets,
        );
        const maximum_width = geometry.lineWidth(work.glyphs.items);
        if (maximum_width >= modified_width - shared.width_epsilon) continue;

        if (maximum_width < target_width - shared.width_epsilon) {
            // JstfMax permits any amount from zero to the authored maximum.
            // Preserve the modified glyph structure and solve exactly to the
            // line measure whenever those endpoint structures agree.
            if (!shared.sameStructure(modified, work)) continue;
            const fraction = @min(
                @as(f32, 1),
                @max(
                    @as(f32, 0),
                    (modified_width - target_width) /
                        (modified_width - maximum_width),
                ),
            );
            shared.interpolateGlyphGeometry(
                modified.glyphs.items,
                work.glyphs.items,
                fraction,
            );
        }
        const final_width = geometry.lineWidth(work.glyphs.items);
        if (final_width > target_width + shared.width_epsilon or
            final_width >= modified_width - shared.width_epsilon)
        {
            continue;
        }
        return try commit(
            buffer,
            recipe,
            glyph_start,
            glyph_end - glyph_start,
            work,
            final_width,
        );
    }
    return .{};
}

fn commit(
    buffer: anytype,
    recipe: anytype,
    glyph_start: usize,
    old_glyph_len: usize,
    candidate: anytype,
    width: f32,
) !Result {
    try recipe.prepareCommit(
        glyph_start,
        old_glyph_len,
        candidate.glyphs.items.len,
    );
    _ = try line_transaction.replaceRange(
        buffer,
        glyph_start,
        old_glyph_len,
        candidate.glyphs.items,
        candidate.runs.items,
        candidate.variation_coords.items,
    );
    recipe.commit(
        glyph_start,
        old_glyph_len,
        candidate.glyphs.items.len,
    );
    return .{
        .applied = true,
        .glyph_len = candidate.glyphs.items.len,
        .width = width,
    };
}
