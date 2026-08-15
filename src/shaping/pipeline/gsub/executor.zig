//! Shared GSUB feature-plan execution across script-specific stages.

const std = @import("std");

const cache = @import("../../context/cache/root.zig");
const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const gsub = @import("../../../gsub.zig");
const shaping_sections = @import("../../../shaping_sections.zig");
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;

/// Minimal execution resources shared by every script shaper.
///
/// This deliberately excludes the layout/output buffer. GSUB stages only need
/// allocation and immutable lookup-plan caching, which lets script modules use
/// the executor without importing paragraph or positioning state.
pub const Context = struct {
    allocator: std.mem.Allocator,
    lookup_selection_cache: ?*cache.LookupSelectionCache,
};

pub fn apply(
    font: *const Font,
    context: Context,
    table_proved: bool,
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
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
        return try font.applyGsubFeatureLookupPlanUsingGdefAfterProof(
            plan,
            glyph_ids,
            context.allocator,
            options,
            gdef_metadata,
        );
    }
    if (table_proved) {
        return try font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(
            applications,
            glyph_ids,
            context.allocator,
            options,
            gdef_metadata,
        );
    }
    return try font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(
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
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
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
    return try font.applyGsubFeatureLookupPlanUsingGdefAfterRunProof(
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
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
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
        try font.gsubMergedFeatureLookupPlanForShaping(
            context.allocator,
            applications,
            options,
            gdef_metadata,
        );
    defer if (!table_proved or context.lookup_selection_cache == null) {
        var mutable_plan = plan;
        mutable_plan.deinit(context.allocator);
    };
    return try font.applyGsubMergedFeatureLookupPlanUsingGdefAfterProof(
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
    applications: []const gsub.FeatureApplication,
    glyph_ids: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
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
        try font.gsubMergedFeatureLookupPlanForShaping(
            context.allocator,
            applications,
            options,
            gdef_metadata,
        );
    defer if (context.lookup_selection_cache == null) {
        var mutable_plan = plan;
        mutable_plan.deinit(context.allocator);
    };
    return try font.applyGsubMergedFeatureLookupPlanUsingGdefAfterRunProof(
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
    options: gsub.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
) linksection(shaping_sections.isolated_hotpaths) !void {
    if (try font.applyGsubCachedLookupSelectionUsingGdefAfterRunProof(
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    )) return;
    return try font.applyGsubWithOptionsUsingGdefAfterProof(
        glyph_ids,
        context.allocator,
        options,
        gdef_metadata,
    );
}
