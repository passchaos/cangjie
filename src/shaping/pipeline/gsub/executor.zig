//! Shared GSUB feature-plan execution across script-specific stages.

const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;

const cache = @import("../../context/cache/root.zig");
const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const gsub = @import("../../../gsub.zig");
const shaping_sections = @import("../../../shaping_sections.zig");
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;
const ranges = @import("../../features/ranged_gsub/ranges.zig");
const unicode = @import("../../../unicode.zig");

/// Minimal execution resources shared by every script shaper.
///
/// This deliberately excludes the layout/output buffer. GSUB stages only need
/// allocation and immutable lookup-plan caching, which lets script modules use
/// the executor without importing paragraph or positioning state.
pub const Context = struct {
    allocator: std.mem.Allocator,
    lookup_selection_cache: ?*cache.LookupSelectionCache,
    feature_ranges: []const ranges.Range = &.{},
    feature_overrides: []const unicode.FeatureOverride = &.{},
    source_byte_starts: []const usize = &.{},
    user_feature_values: ?*std.ArrayList(u32) = null,
};

pub inline fn applyPlanAfterRunProofWithRanges(
    font: *const Font,
    context: Context,
    plan: gsub.feature.LookupPlan,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (context.feature_ranges.len == 0) {
        // Script shapers invoke this boundary several times per source run.
        // Inline the overwhelmingly common no-range branch so the caller can
        // enter the cached plan executor directly instead of copying Context,
        // Options, and GDEF metadata through another call frame.
        return applyPlanAfterRunProof(
            font,
            context,
            plan,
            glyph_ids,
            options,
            gdef_metadata,
        );
    }
    for (plan.entries) |entry| {
        var selected = options;
        var user_feature: gsub.runtime.UserFeature = undefined;
        if (ranges.hasTag(context.feature_ranges, entry.application.tag)) {
            const values = context.user_feature_values orelse
                return error.InvalidShapingInput;
            try values.resize(
                context.allocator,
                context.source_byte_starts.len,
            );
            if (!ranges.fillEffectiveValues(
                values.items,
                context.source_byte_starts,
                context.feature_ranges,
                context.feature_overrides,
                entry.application.tag,
            )) return error.InvalidShapingInput;
            user_feature = .{
                .values = values.items,
                .tag = entry.application.tag,
                .value = entry.application.value,
                .include_script_candidates = entry.application.source_scoped,
            };
            selected.user_feature = &user_feature;
            selected.use_user_feature_at_cursor = true;
        }
        const one = gsub.feature.LookupPlan{
            .entries = @constCast((&entry)[0..1]),
        };
        try applyPlanAfterRunProof(
            font,
            context,
            one,
            glyph_ids,
            selected,
            gdef_metadata,
        );
    }
}

pub fn apply(
    font: *const Font,
    context: Context,
    table_proved: bool,
    applications: []const gsub.feature.Application,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (applications.len == 0) return;
    if (table_proved and context.lookup_selection_cache != null) {
        const plan =
            try context.lookup_selection_cache.?.gsubFeatureLookupPlan(
                font,
                applications,
                options,
                gdef_metadata,
            );
        return try font_shaping.applyGsubFeatureLookupPlanUsingGdefAfterProof(
            font,
            plan,
            glyph_ids,
            context.allocator,
            options,
            gdef_metadata,
        );
    }
    if (table_proved) {
        return try font_shaping.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(
            font,
            applications,
            glyph_ids,
            context.allocator,
            options,
            gdef_metadata,
        );
    }
    return try font_shaping.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(
        font,
        applications,
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    );
}

pub fn applyAfterRunProof(
    font: *const Font,
    context: Context,
    table_proved: bool,
    applications: []const gsub.feature.Application,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (!table_proved or context.lookup_selection_cache == null) {
        return try apply(
            font,
            context,
            table_proved,
            applications,
            glyph_ids,
            options,
            gdef_metadata,
        );
    }
    if (applications.len == 0) return;
    const plan = try context.lookup_selection_cache.?.gsubFeatureLookupPlan(
        font,
        applications,
        options,
        gdef_metadata,
    );
    return try font_shaping.applyGsubFeatureLookupPlanUsingGdefAfterRunProof(
        font,
        plan,
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    );
}

pub fn applyPlanAfterRunProof(
    font: *const Font,
    context: Context,
    plan: gsub.feature.LookupPlan,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
) !void {
    return font_shaping.applyGsubFeatureLookupPlanUsingGdefAfterRunProof(
        font,
        plan,
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    );
}

pub fn applyMerged(
    font: *const Font,
    context: Context,
    table_proved: bool,
    applications: []const gsub.feature.Application,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (applications.len == 0) return;
    const plan = if (table_proved and context.lookup_selection_cache != null)
        try context.lookup_selection_cache.?.gsubMergedFeatureLookupPlan(
            font,
            applications,
            options,
            gdef_metadata,
        )
    else
        try font_shaping.gsubMergedFeatureLookupPlanForShaping(
            font,
            context.allocator,
            applications,
            options,
            gdef_metadata,
        );
    defer if (!table_proved or context.lookup_selection_cache == null) {
        var mutable_plan = plan;
        mutable_plan.deinit(context.allocator);
    };
    return try font_shaping.applyGsubMergedFeatureLookupPlanUsingGdefAfterProof(
        font,
        plan,
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    );
}

pub fn applyMergedAfterRunProof(
    font: *const Font,
    context: Context,
    table_proved: bool,
    applications: []const gsub.feature.Application,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
) !void {
    if (!table_proved) {
        return try applyMerged(
            font,
            context,
            table_proved,
            applications,
            glyph_ids,
            options,
            gdef_metadata,
        );
    }
    if (applications.len == 0) return;
    const plan = if (context.lookup_selection_cache) |selection_cache|
        try selection_cache.gsubMergedFeatureLookupPlan(
            font,
            applications,
            options,
            gdef_metadata,
        )
    else
        try font_shaping.gsubMergedFeatureLookupPlanForShaping(
            font,
            context.allocator,
            applications,
            options,
            gdef_metadata,
        );
    defer if (context.lookup_selection_cache == null) {
        var mutable_plan = plan;
        mutable_plan.deinit(context.allocator);
    };
    return try font_shaping.applyGsubMergedFeatureLookupPlanUsingGdefAfterRunProof(
        font,
        plan,
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    );
}

// Keep the cache-contract branch outside the generic-script caller's hot frame.
pub noinline fn applyGenericAfterTableProof(
    font: *const Font,
    context: Context,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    gdef_metadata: GdefLookupMetadata,
) linksection(shaping_sections.isolated_hotpaths) !void {
    if (try font_shaping.applyGsubCachedLookupSelectionUsingGdefAfterRunProof(
        font,
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    )) return;
    return try font_shaping.applyGsubWithOptionsUsingGdefAfterProof(
        font,
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    );
}
