//! GSUB lookup selection and source-value application for ranged features.

const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;

const Font = @import("../../../font.zig").Font;
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;
const gsub = @import("../../../gsub.zig");
const ranges_mod = @import("ranges.zig");
const source_buffer = @import("source_buffer.zig");
const unicode = @import("../../../unicode.zig");

pub fn apply(
    font: *const Font,
    allocator: std.mem.Allocator,
    ranges: []const ranges_mod.Range,
    global_overrides: []const unicode.FeatureOverride,
    sources: *source_buffer.Buffer,
    options: gsub.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
) !void {
    try sources.source_features.resize(
        allocator,
        sources.source_byte_starts.items.len,
    );
    sources.tag_values.clearRetainingCapacity();
    try sources.tag_values.resize(allocator, ranges.len * 2);
    const value_count = ranges_mod.appendDistinctEffectiveValues(
        sources.tag_values.items,
        ranges,
        global_overrides,
    );
    sources.tag_values.shrinkRetainingCapacity(value_count);
    var selection_options = options;
    // The ordinary pass replaces every ranged tag with a disabling override.
    // Lookup discovery must ignore that transformed slice: selecting one
    // feature is a topology query, while its source values are enforced below.
    selection_options.features = &.{};

    var value_index: usize = 0;
    while (value_index < sources.tag_values.items.len) {
        const tag = sources.tag_values.items[value_index].tag;
        const lookups = try font_shaping.selectGsubFeatureLookupsAfterProof(
            font,
            allocator,
            tag,
            selection_options,
            gdef_metadata,
        );
        defer allocator.free(lookups);

        if (lookups.len != 0) {
            for (sources.tag_values.items) |tag_value| {
                if (tag_value.tag != tag or tag_value.value == 0) continue;
                markSourcesForValue(
                    sources.source_features.items,
                    sources.source_byte_starts.items,
                    ranges,
                    global_overrides,
                    tag_value,
                );
                var scoped_options = options;
                scoped_options.features = &.{};
                scoped_options.selected_lookups = null;
                scoped_options.source_features = sources.source_features.items;
                try font_shaping.applyGsubSelectedSourceFeatureAfterProof(
                    font,
                    lookups,
                    tag,
                    tag_value.value,
                    &sources.glyph_ids,
                    allocator,
                    scoped_options,
                    gdef_metadata,
                );
            }
        }

        value_index += 1;
        while (value_index < sources.tag_values.items.len and
            sources.tag_values.items[value_index].tag == tag)
        {
            value_index += 1;
        }
    }
}

fn markSourcesForValue(
    source_features: []u32,
    source_byte_starts: []const usize,
    ranges: []const ranges_mod.Range,
    global_overrides: []const unicode.FeatureOverride,
    tag_value: ranges_mod.TagValue,
) void {
    @memset(source_features, 0);
    for (source_byte_starts, source_features) |byte, *active| {
        if (ranges_mod.effectiveValueAt(
            ranges,
            global_overrides,
            tag_value.tag,
            byte,
        ) == tag_value.value) {
            active.* = tag_value.tag;
        }
    }
}
