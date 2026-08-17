//! OpenType JSTF priority application for source-shaped logical lines.
//!
//! Priority levels stand alone. Each candidate starts from original source,
//! applies the priority's extension suggestion, and is accepted transactionally
//! only when it widens the selected line without exceeding the target.

const geometry = @import("../line_break/reflow/geometry.zig");
const line_transaction = @import("line_transaction.zig");
const run_types = @import("../types/runs.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const shared = @import("jstf/shared.zig");

pub fn apply(
    buffer: anytype,
    options: anytype,
    recipe: anytype,
) !void {
    if (options.alignment != .justify or
        !options.jstf.enabled or
        buffer.lines.items.len == 0)
    {
        return;
    }

    var work = @TypeOf(buffer.*).init(buffer.allocator);
    defer work.deinit();
    var natural = @TypeOf(buffer.*).init(buffer.allocator);
    defer natural.deinit();
    // Temporary candidates are separate output owners, but they shape the
    // same borrowed fonts on the same thread. Reuse the caller's immutable
    // font metadata, proof, and lookup-selection caches so Engine-backed
    // paragraph layout does not silently drop to the uncached path.
    shared.inheritShapeCaches(buffer, &work);
    shared.inheritShapeCaches(buffer, &natural);

    var line_index: usize = 0;
    while (line_index < buffer.lines.items.len) : (line_index += 1) {
        const line = buffer.lines.items[line_index];
        const target = line.justification_target orelse continue;
        const source_range = shared.reusableSourceRange(
            buffer.glyphs.items,
            line,
        ) orelse continue;
        if (!recipe.canExpandSourceRange(source_range.start, source_range.end)) {
            continue;
        }
        const run = shared.singleOwningRun(buffer.runs.items, line) orelse
            continue;
        const font = run_types.fontForBackend(run);
        const info = (try font.jstfInfo(buffer.allocator)) orelse continue;
        defer font.freeJstfInfo(buffer.allocator, info);
        const tags = recipe.jstfTags(source_range.start, source_range.end);
        const language = shared.selectLanguage(
            info,
            tags.script,
            tags.language,
        ) orelse continue;
        const natural_width = geometry.lineWidth(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        );
        if (target <= natural_width + shared.width_epsilon) continue;

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
            if (shared.allEmpty(modifications) and
                lookup_offsets.len == 0)
            {
                continue;
            }
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
            if (maximum_width <= natural_width + shared.width_epsilon) {
                continue;
            }

            if (maximum_width > target + shared.width_epsilon) {
                try recipe.shapeLineWithJstfPriority(
                    &natural,
                    source_range.start,
                    source_range.end - source_range.start,
                    font,
                    run.font_index,
                    .{},
                    &.{},
                );
                if (!shared.sameStructure(natural, work)) continue;
                const fraction = @min(
                    @as(f32, 1),
                    @max(
                        @as(f32, 0),
                        (target - natural_width) /
                            (maximum_width - natural_width),
                    ),
                );
                shared.interpolateGlyphGeometry(
                    natural.glyphs.items,
                    work.glyphs.items,
                    fraction,
                );
            }
            const final_width = geometry.lineWidth(work.glyphs.items);
            if (final_width <= natural_width + shared.width_epsilon or
                final_width > target + shared.width_epsilon)
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
