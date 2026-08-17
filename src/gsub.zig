const std = @import("std");
const accelerator_root = @import("gsub/accelerator/root.zig");
const accelerator_model = accelerator_root.model;
const feature_domain = @import("gsub/feature/root.zig");
const direct_alternate = @import("gsub/execution/direct/alternate/root.zig");
const direct_ligature = @import("gsub/execution/direct/ligature/root.zig");
const direct_multiple = @import("gsub/execution/direct/multiple/root.zig");
const direct_reverse = @import("gsub/execution/direct/reverse/root.zig");
const direct_single = @import("gsub/execution/direct/single/root.zig");
const contextual_context =
    @import("gsub/execution/contextual/context/root.zig");
const contextual_chaining_class =
    @import("gsub/execution/contextual/chaining/class/root.zig");
const contextual_chaining_coverage =
    @import("gsub/execution/contextual/chaining/coverage/root.zig");
const contextual_chaining_glyph =
    @import("gsub/execution/contextual/chaining/glyph/root.zig");
const contextual_chaining_lookup =
    @import("gsub/execution/contextual/chaining/lookup/root.zig");
const contextual_nested =
    @import("gsub/execution/contextual/nested/root.zig");
const contextual_model = @import("gsub/execution/contextual/model.zig");
const contextual_records =
    @import("gsub/execution/contextual/records/root.zig");
const contextual_safety =
    @import("gsub/execution/contextual/safety.zig");
const lookup_execution = @import("gsub/execution/lookup/root.zig");
const GlyphId = @import("glyph.zig").GlyphId;
const ligature_provenance = @import("ligature_provenance.zig");
pub const runtime = @import("gsub/runtime/root.zig");
const runtime_prefilter = @import("gsub/runtime/prefilter/root.zig");
const table_core = @import("gsub/table/root.zig");
const validation = @import("gsub/validation/root.zig");
const shaping_sections = @import("shaping_sections.zig");
const unicode = @import("unicode.zig");

/// Staged feature planning and application surface.
///
/// Low-level whole-table execution remains at the GSUB root. Script shapers
/// use this domain for explicit feature stages, source masks, and cached plan
/// ownership instead of depending on a growing flat list of GSUB declarations.
pub const feature = struct {
    pub const Application = feature_domain.Application;
    pub const LookupPlanEntry = feature_domain.LookupPlanEntry;
    pub const MergedLookup = feature_domain.MergedLookup;
    pub const MergedLookupPlan = feature_domain.MergedLookupPlan;
    pub const LookupPlan = feature_domain.LookupPlan;
    pub const source_mask_marker = feature_domain.source_mask_marker;
    pub const sourceMaskForTag = feature_domain.sourceMaskForTag;
    pub const random_value = feature_domain.random_value;

    pub const selectedLookupIndices = selectedFeatureLookupIndicesForOptions;
    pub const applySelectedSource = applySelectedSourceFeatureWithOptions;
    pub const applySource = applySourceFeatureWithOptions;
    pub const apply = applyFeatureWithOptions;
    pub const applySequence = applyFeatureSequenceWithOptions;
    pub const buildLookupPlan = buildFeatureLookupPlan;
    pub const buildMergedLookupPlan = buildMergedFeatureLookupPlan;
    pub const applyLookupPlan = applyFeatureLookupPlanWithOptions;
    pub const applyLookupPlanAfterMetadataProof =
        applyFeatureLookupPlanWithOptionsAfterMetadataProof;
    pub const applyMergedLookupPlan = applyMergedFeatureLookupPlanWithOptions;
    pub const applyMergedLookupPlanAfterMetadataProof =
        applyMergedFeatureLookupPlanWithOptionsAfterMetadataProof;
};

/// Parsed lookup sidecars retained by shaping caches.
pub const acceleration = struct {
    pub const Lookup = accelerator_root.Lookup;

    pub const build = accelerator_root.build.lookup.build;
    pub const deinit = accelerator_root.ownership.deinit;
    pub const hasRandomFeature = accelerator_root.feature_index.hasRandomFeature;
};

/// GSUB parsing is table-driven and intentionally tolerant of unsupported
/// lookup types: unknown lookups are skipped, while malformed supported lookup
/// data reports BadGsub/UnsupportedGsub.
pub const GsubError = error{
    BadGsub,
    InvalidShapingInput,
    ShapingLimitExceeded,
    UnsupportedGsub,
    EndOfStream,
};

const Table = table_core.View;

const FeatureSelection = feature_domain.selection.Item;

const LookupOptions = runtime.Options;

const LookupAccelerator = acceleration.Lookup;
const FastSingleRecord = accelerator_model.FastSingleRecord;
const ChainingSubtableGroup = accelerator_model.ChainingGroup;
const ChainingSubtablePair = accelerator_model.ChainingPair;
const ChainingPairSubtableGroup = accelerator_model.ChainingPairGroup;
const ChainingPairSubtablePair = accelerator_model.ChainingPairEntry;
const FeatureLookupPlanEntry = feature.LookupPlanEntry;
const MergedFeatureLookup = feature.MergedLookup;
const MergedFeatureLookupPlan = feature.MergedLookupPlan;
const FeatureLookupPlan = feature.LookupPlan;
const NestedGlyphChange = contextual_model.Change;
const markUnsafeContextMatch = contextual_safety.markInput;

/// Apply default or explicitly enabled substitution features to the glyph
/// stream in place. The input and output are glyph ids; source text metadata is
/// handled by the caller because GSUB itself has no Unicode context.
pub fn apply(data: []const u8, offset: usize, length: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)!void {
    return try applyWithOptions(data, offset, length, glyphs, allocator, .{});
}

pub fn applyWithOptions(data: []const u8, offset: usize, length: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    return runtime.run.apply(
        ContextualRecordExecutor,
        data,
        offset,
        length,
        glyphs,
        allocator,
        options,
    );
}

/// Apply a non-empty cached lookup selection after the layout shaper proved the
/// borrowed table and constructed a valid glyph/source-parallel run.
///
/// This intentionally has a narrow, fallible fast-path contract. `false` means
/// no glyph was touched and the caller must use `applyWithOptions`; in
/// particular, empty selections retain its FeatureList/topology semantics, and
/// absent or foreign accelerators retain all defensive validation. An exact
/// accelerator was built by walking every LookupList entry in this same table,
/// so its length and offsets are an immutable lookup plan for the cache
/// lifetime. Validate the complete selected index set before applying its first
/// lookup so a stale/corrupt selection can never produce a partially mutated
/// run before falling back.
pub noinline fn applyCachedLookupSelectionWithOptionsAfterMetadataProof(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) linksection(shaping_sections.isolated_hotpaths) (GsubError || std.mem.Allocator.Error)!bool {
    return runtime.run.cached.apply(
        ContextualRecordExecutor,
        data,
        offset,
        length,
        glyphs,
        allocator,
        options,
    );
}

pub fn selectedLookupIndicesForOptions(data: []const u8, offset: usize, length: usize, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)![]u16 {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return try allocator.alloc(u16, 0);
    var lookups = try selectedLookupIndices(table, allocator, options);
    return try lookups.toOwnedSlice(allocator);
}

/// Return one feature's active LookupList indexes for a selected Script/LangSys.
///
/// This selection API supports the rare ranged-feature layer without adding
/// range state to `LookupOptions`. The ordinary hot path continues to cache and
/// apply its complete global plan unchanged.
fn selectedFeatureLookupIndicesForOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    feature_tag: u32,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)![]u16 {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = options.assume_validated,
    };
    if (try readU16(table, 0) != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return allocator.alloc(u16, 0);
    var items = try feature_domain.plan.selection.collectForRun(
        table,
        allocator,
        options,
    );
    defer items.deinit(allocator);
    return feature_domain.plan.selection.selectedLookups(
        table,
        feature_tag,
        items.items,
        try feature_domain.plan.selection.context(table),
        allocator,
        options,
    );
}

/// Apply a preselected lookup list to sources carrying `source_feature`.
///
/// Source metadata is already stable across GSUB cardinality changes. Keeping
/// range assignment outside this function lets callers reuse one selection for
/// every distinct feature value without widening the ordinary lookup options.
fn applySelectedSourceFeatureWithOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    selected_lookups: []const u16,
    source_feature: u32,
    feature_value: u32,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    if (selected_lookups.len == 0 or feature_value == 0) return;
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    var scoped_options = options;
    scoped_options.selected_lookups = selected_lookups;
    scoped_options.active_source_feature = source_feature;
    scoped_options.active_feature_value = feature_value;
    try runtime.metadata.validate(scoped_options, glyphs.items.len);
    var mutation_generation: usize = 0;
    const shaping_options = runtime.state.withDigestGeneration(
        scoped_options,
        &mutation_generation,
    );
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = shaping_options.assume_validated,
    };
    if (try readU16(table, 0) != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return;
    const lookup_list_offset = try table_core.service.requiredLookupList(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    var run_digest_cache = runtime_prefilter.Cache.init();
    try feature_domain.plan.apply.shared.indices(
        ContextualRecordExecutor,
        table,
        lookup_list_offset,
        lookup_count,
        selected_lookups,
        glyphs,
        allocator,
        shaping_options,
        &run_digest_cache,
    );
}

pub fn hasFeature(data: []const u8, offset: usize, length: usize, feature_tag: u32) GsubError!bool {
    return table_core.service.hasFeature(
        try table_core.service.view(data, offset, length, true),
        feature_tag,
    );
}

pub fn isEmptyTable(data: []const u8, offset: usize, length: usize) GsubError!bool {
    return table_core.service.isEmpty(
        try table_core.service.view(data, offset, length, false),
    );
}

/// Apply one Script/LangSys feature to the source positions carrying its tag.
///
/// This is primarily used by cursive joining (`isol`/`init`/`medi`/`fina`),
/// but the mechanism is deliberately feature-agnostic. The source assignment
/// remains stable when earlier GSUB stages change glyph cardinality because
/// `glyph_source_indices` is already maintained alongside the glyph stream.
fn applySourceFeatureWithOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    feature_tag: u32,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    return try applyFeatureSequenceWithOptions(data, offset, length, &.{.{ .tag = feature_tag, .source_scoped = true }}, glyphs, allocator, options);
}

/// Apply exactly one feature from the active Script/LangSys to the full glyph
/// stream. Higher-level shapers use this to preserve script-defined feature
/// ordering when some stages (for example Arabic joining forms) require
/// position-scoped application between otherwise global features.
fn applyFeatureWithOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    feature_tag: u32,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    return try applyFeatureSequenceWithOptions(data, offset, length, &.{.{ .tag = feature_tag }}, glyphs, allocator, options);
}

/// Apply an ordered feature plan after validating and preparing the GSUB table
/// once. This avoids repeating table validation and caller-side GDEF expansion
/// for scripts whose shaping plan has multiple explicit stages.
fn applyFeatureSequenceWithOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    applications: []const feature.Application,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = options.assume_validated,
    };
    if (try readU16(table, 0) != 1) return error.UnsupportedGsub;
    return feature_domain.plan.apply.sequence.apply(
        ContextualRecordExecutor,
        table,
        applications,
        glyphs,
        allocator,
        options,
    );
}

fn buildFeatureLookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    applications: []const feature.Application,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!feature.LookupPlan {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = options.assume_validated,
    };
    if (try readU16(table, 0) != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) {
        return .{ .entries = try allocator.alloc(FeatureLookupPlanEntry, 0) };
    }
    return feature_domain.plan.build.lookupPlan(
        table,
        applications,
        allocator,
        options,
    );
}

fn buildMergedFeatureLookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    applications: []const feature.Application,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!feature.MergedLookupPlan {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = options.assume_validated,
    };
    if (try readU16(table, 0) != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) {
        return .{
            .lookups = try allocator.alloc(MergedFeatureLookup, 0),
            .lookup_offsets = try allocator.alloc(usize, 0),
        };
    }
    return feature_domain.plan.build.mergedPlan(
        table,
        applications,
        allocator,
        options,
    );
}

fn applyFeatureLookupPlanWithOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.LookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    return applyFeatureLookupPlan(
        data,
        offset,
        length,
        plan,
        glyphs,
        allocator,
        options,
        true,
    );
}

fn applyFeatureLookupPlanWithOptionsAfterMetadataProof(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.LookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    return applyFeatureLookupPlan(
        data,
        offset,
        length,
        plan,
        glyphs,
        allocator,
        options,
        false,
    );
}

fn applyFeatureLookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.LookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
    prove_metadata: bool,
) (GsubError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = options.assume_validated,
    };
    if (try readU16(table, 0) != 1) return error.UnsupportedGsub;
    return feature_domain.plan.apply.cached.staged(
        ContextualRecordExecutor,
        table,
        plan,
        glyphs,
        allocator,
        options,
        prove_metadata,
    );
}

fn applyMergedFeatureLookupPlanWithOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.MergedLookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    return applyMergedFeatureLookupPlan(
        data,
        offset,
        length,
        plan,
        glyphs,
        allocator,
        options,
        true,
    );
}

fn applyMergedFeatureLookupPlanWithOptionsAfterMetadataProof(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.MergedLookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    return applyMergedFeatureLookupPlan(
        data,
        offset,
        length,
        plan,
        glyphs,
        allocator,
        options,
        false,
    );
}

fn applyMergedFeatureLookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.MergedLookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
    prove_metadata: bool,
) (GsubError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = options.assume_validated,
    };
    if (try readU16(table, 0) != 1) return error.UnsupportedGsub;
    return feature_domain.plan.apply.cached.merged(
        ContextualRecordExecutor,
        table,
        plan,
        glyphs,
        allocator,
        options,
        prove_metadata,
    );
}

/// Validate GSUB glyph references that are meaningful at font-load time.
///
/// Runtime shaping only reaches records whose lookup and coverage match the
/// current glyph stream. A dangling glyph id in an unused alternate, ligature,
/// reverse-chain substitute, or contextual coverage can therefore remain latent
/// until a later shaping path tries to feed it into metrics or outline code.
/// This pass walks every supported lookup with maxp.numGlyphs attached to the
/// table, preserving the shaping path's "skip unsupported lookup types" policy
/// while rejecting malformed supported subtables and out-of-range glyph ids.
pub fn validateGlyphBounds(data: []const u8, offset: usize, length: usize, glyph_count: u16) GsubError!void {
    return validation.table.glyphBounds(
        ContextualRecordExecutor,
        data,
        offset,
        length,
        glyph_count,
        .strict,
    );
}

pub fn validateGlyphBoundsForShaping(data: []const u8, offset: usize, length: usize, glyph_count: u16) GsubError!void {
    return validation.table.glyphBounds(
        ContextualRecordExecutor,
        data,
        offset,
        length,
        glyph_count,
        .shaping,
    );
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    return feature_domain.run_selection.lookupIndices(
        table,
        allocator,
        options,
    );
}

fn applyLookup(table: Table, lookup_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    try applyLookupWithIndex(table, lookup_offset, null, glyphs, allocator, options, null);
}

fn applyLookupWithIndex(table: Table, lookup_offset: usize, lookup_index: ?u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions, run_digest_cache: ?*runtime_prefilter.Cache) (GsubError || std.mem.Allocator.Error)!void {
    // The cached Font path overwhelmingly dispatches predecoded ligature and
    // chaining lookups. Keep those cases outside the generic function below:
    // its support for every lookup kind, nested contextual mutation, and
    // profiling windows otherwise forces a roughly 10 KiB stack frame on each
    // tiny lookup invocation even when none of that state is used.
    if ((options.shape_profile == null or options.profile_fast_path) and table.assume_validated) {
        if (try lookup_execution.accelerated.apply(
            ContextualRecordExecutor,
            table,
            lookup_offset,
            lookup_index,
            glyphs,
            allocator,
            options,
            run_digest_cache,
        )) return;
    }
    return applyLookupWithIndexGeneric(
        table,
        lookup_offset,
        lookup_index,
        glyphs,
        allocator,
        options,
        run_digest_cache,
    );
}

noinline fn applyLookupWithIndexGeneric(table: Table, lookup_offset: usize, lookup_index: ?u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions, run_digest_cache: ?*runtime_prefilter.Cache) (GsubError || std.mem.Allocator.Error)!void {
    return lookup_execution.generic.apply(
        ContextualRecordExecutor,
        table,
        lookup_offset,
        lookup_index,
        glyphs,
        allocator,
        options,
        run_digest_cache,
    );
}

fn extensionSubtablePayload(table: Table, subtable_offset: usize, expected_lookup_type: u16) GsubError!usize {
    return accelerator_root.build.lookup.extension.payload(
        table,
        subtable_offset,
        expected_lookup_type,
    );
}

fn applyExtensionSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 7) return error.UnsupportedGsub;
    const extension_subtable = try checkedExtensionSubtablePayloadOffset(table, subtable_offset, try readU32(table, subtable_offset + 4));
    // Extension subtables only move the payload past 16-bit offset limits; the
    // wrapper lookup still owns LookupFlag filtering for the enclosed lookup.
    switch (extension_lookup_type) {
        1 => try direct_single.subtable(table, extension_subtable, glyphs, lookup_flag, options),
        2 => try direct_multiple.subtable(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        3 => try direct_alternate.subtable(table, extension_subtable, glyphs, lookup_flag, options),
        4 => try direct_ligature.subtable(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        5 => try contextual_context.subtable(
            ContextualRecordExecutor,
            table,
            extension_subtable,
            glyphs,
            allocator,
            lookup_flag,
            options,
        ),
        6 => try contextual_chaining_lookup.subtable(
            ContextualRecordExecutor,
            table,
            extension_subtable,
            glyphs,
            allocator,
            lookup_flag,
            options,
        ),
        8 => try direct_reverse.subtable(
            table,
            extension_subtable,
            glyphs,
            lookup_flag,
            options,
        ),
        else => {},
    }
}

const ContextualRecordExecutor = struct {
    pub fn applyLookup(
        table: Table,
        lookup_offset: usize,
        lookup_index: u16,
        glyphs: *std.ArrayList(GlyphId),
        allocator: std.mem.Allocator,
        options: LookupOptions,
        run_digest_cache: *runtime_prefilter.Cache,
    ) (GsubError || std.mem.Allocator.Error)!void {
        return applyLookupWithIndex(
            table,
            lookup_offset,
            lookup_index,
            glyphs,
            allocator,
            options,
            run_digest_cache,
        );
    }

    pub fn applyExtensionSubtable(
        table: Table,
        subtable_offset: usize,
        glyphs: *std.ArrayList(GlyphId),
        allocator: std.mem.Allocator,
        lookup_flag: u16,
        options: LookupOptions,
    ) (GsubError || std.mem.Allocator.Error)!void {
        return applyExtensionSubstitution(
            table,
            subtable_offset,
            glyphs,
            allocator,
            lookup_flag,
            options,
        );
    }

    pub fn applyExtensionChainingLookup(
        table: Table,
        lookup_offset: usize,
        subtable_count: u16,
        glyphs: *std.ArrayList(GlyphId),
        allocator: std.mem.Allocator,
        lookup_flag: u16,
        options: LookupOptions,
    ) (GsubError || std.mem.Allocator.Error)!void {
        return contextual_chaining_lookup.applyExtension(
            ContextualRecordExecutor,
            table,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            options,
        );
    }

    pub fn applyChainingLookup(
        table: Table,
        lookup_offset: usize,
        subtable_count: u16,
        glyphs: *std.ArrayList(GlyphId),
        allocator: std.mem.Allocator,
        lookup_flag: u16,
        options: LookupOptions,
        accelerator: ?*const LookupAccelerator,
    ) (GsubError || std.mem.Allocator.Error)!void {
        return contextual_chaining_lookup.apply(
            ContextualRecordExecutor,
            table,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            options,
            accelerator,
        );
    }

    pub fn applyNested(
        table: Table,
        glyphs: *std.ArrayList(GlyphId),
        glyph_index: usize,
        lookup_index: u16,
        allocator: std.mem.Allocator,
        options: LookupOptions,
    ) (GsubError || std.mem.Allocator.Error)!NestedGlyphChange {
        return contextual_nested.apply(
            ContextualRecordExecutor,
            table,
            glyphs,
            glyph_index,
            lookup_index,
            allocator,
            options,
        );
    }

    pub fn validateNested(
        table: Table,
        lookup_offset: usize,
    ) GsubError!void {
        if (table.glyph_count != null) {
            _ = try validation.lookup.header.validate(table, lookup_offset);
        } else {
            _ = try validation.lookup.validateHeader(
                ContextualRecordExecutor,
                table,
                lookup_offset,
            );
        }
    }
};

fn applySubstitutionRecordsMapped(
    table: Table,
    glyphs: *std.ArrayList(GlyphId),
    records_offset: usize,
    record_count: usize,
    input_indices: []const usize,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    return contextual_records.apply(
        ContextualRecordExecutor,
        table,
        glyphs,
        records_offset,
        record_count,
        input_indices,
        allocator,
        options,
    );
}

fn checkedExtensionSubtablePayloadOffset(table: Table, extension_offset: usize, relative_offset: u32) GsubError!usize {
    return table_core.offset.extensionPayload(table, extension_offset, relative_offset);
}

fn isEmptyGsubTopology(table: Table) GsubError!bool {
    return table_core.service.isEmpty(table);
}

fn readU16(table: Table, relative: usize) GsubError!u16 {
    return table.readU16(relative);
}

fn readU32(table: Table, relative: usize) GsubError!u32 {
    return table.readU32(relative);
}

test "GSUB context substitution can apply nested multiple substitution" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1(&bytes, context + 22, 1);

    writeU16Test(&bytes, 52, 2);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const multiple = 60;
    writeU16Test(&bytes, multiple + 0, 1);
    writeU16Test(&bytes, multiple + 2, 8);
    writeU16Test(&bytes, multiple + 4, 1);
    writeU16Test(&bytes, multiple + 6, 14);
    writeCoverage1(&bytes, multiple + 8, 2);
    const sequence = multiple + 14;
    writeU16Test(&bytes, sequence + 0, 2);
    writeU16Test(&bytes, sequence + 2, 20);
    writeU16Test(&bytes, sequence + 4, 21);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 20, 21, 3 }, glyphs.items);
}

test "GSUB multiple substitution makes a later sequence index valid" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 124;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 118); // Empty ScriptList.
    writeU16Test(&bytes, 6, 120); // Empty FeatureList.
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 10); // Context lookup at 20.
    writeU16Test(&bytes, 14, 52); // Multiple lookup at 62.
    writeU16Test(&bytes, 16, 88); // Single lookup at 98.
    writeU16Test(&bytes, 118, 0);
    writeU16Test(&bytes, 120, 0);

    writeU16Test(&bytes, 20, 5);
    writeU16Test(&bytes, 24, 1);
    writeU16Test(&bytes, 26, 8);
    const context = 28;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 28);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);
    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeU16Test(&bytes, rule + 10, 2); // Initially past GlyphCount.
    writeU16Test(&bytes, rule + 12, 2);
    writeCoverage1(&bytes, context + 28, 1);

    writeU16Test(&bytes, 62, 2);
    writeU16Test(&bytes, 66, 1);
    writeU16Test(&bytes, 68, 8);
    const multiple = 70;
    writeU16Test(&bytes, multiple + 0, 1);
    writeU16Test(&bytes, multiple + 2, 8);
    writeU16Test(&bytes, multiple + 4, 1);
    writeU16Test(&bytes, multiple + 6, 14);
    writeCoverage1(&bytes, multiple + 8, 1);
    const sequence = multiple + 14;
    writeU16Test(&bytes, sequence + 0, 2);
    writeU16Test(&bytes, sequence + 2, 10);
    writeU16Test(&bytes, sequence + 4, 11);

    writeSingleDeltaLookup(&bytes, 98, 2, 10);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try validateGlyphBounds(&bytes, 0, bytes.len, 32);
    try applyLookup(table, 20, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 11, 12 }, glyphs.items);
}

test "GSUB contextual records skip deleted input sequence targets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 160;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 4);
    writeU16Test(&bytes, 12, 10);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 92);
    writeU16Test(&bytes, 18, 124);

    writeU16Test(&bytes, 20, 5);
    writeU16Test(&bytes, 24, 1);
    writeU16Test(&bytes, 26, 8);

    const context = 28;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 34);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 3);
    writeU16Test(&bytes, rule + 2, 3);
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 3);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 1);
    writeU16Test(&bytes, rule + 12, 0);
    writeU16Test(&bytes, rule + 14, 2);
    writeU16Test(&bytes, rule + 16, 1);
    writeU16Test(&bytes, rule + 18, 3);
    writeCoverage1(&bytes, context + 34, 1);

    writeU16Test(&bytes, 70, 2);
    writeU16Test(&bytes, 74, 1);
    writeU16Test(&bytes, 76, 8);
    const delete_multiple = 78;
    writeU16Test(&bytes, delete_multiple + 0, 1);
    writeU16Test(&bytes, delete_multiple + 2, 8);
    writeU16Test(&bytes, delete_multiple + 4, 1);
    writeU16Test(&bytes, delete_multiple + 6, 14);
    writeCoverage1(&bytes, delete_multiple + 8, 1);
    writeU16Test(&bytes, delete_multiple + 14, 0);

    writeSingleDeltaLookup(&bytes, 102, 2, 10);
    writeSingleDeltaLookup(&bytes, 134, 2, 20);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 20, &glyphs, allocator, .{});

    // The second record repeats sequenceIndex 0 after the first record deletes
    // that input glyph. It must be skipped rather than applied to glyph 2 after
    // glyph 2 shifts into the deleted glyph's buffer slot.
    try std.testing.expectEqualSlices(GlyphId, &.{ 22, 3 }, glyphs.items);
}

test "GSUB context nested lookup can apply ligature substitution" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 2);
    // A nested LigatureSubst must see the real run after sequenceIndex 0.
    // Running the nested lookup on a one-glyph scratch buffer cannot match
    // component glyph 2 and leaves the contextual ligature unapplied.
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1(&bytes, context + 22, 1);

    writeU16Test(&bytes, 52, 4);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const lig_subst = 60;
    writeU16Test(&bytes, lig_subst + 0, 1);
    writeU16Test(&bytes, lig_subst + 2, 18);
    writeU16Test(&bytes, lig_subst + 4, 1);
    writeU16Test(&bytes, lig_subst + 6, 8);
    const ligature_set = lig_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 1);
    writeU16Test(&bytes, ligature_set + 2, 4);
    const ligature = ligature_set + 4;
    writeU16Test(&bytes, ligature + 0, 40);
    writeU16Test(&bytes, ligature + 2, 2);
    writeU16Test(&bytes, ligature + 4, 2);
    writeCoverage1(&bytes, lig_subst + 18, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 40, 3 }, glyphs.items);
}

test "GSUB chaining resumes after a nested ligature's adjusted match end" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 88;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6); // Lookup 0 at 16.
    writeU16Test(&bytes, 14, 46); // Lookup 1 at 56.

    writeU16Test(&bytes, 16, 6); // ChainingContextSubst.
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);
    const chain = 24;
    writeU16Test(&bytes, chain + 0, 1);
    writeU16Test(&bytes, chain + 2, 26);
    writeU16Test(&bytes, chain + 4, 1);
    writeU16Test(&bytes, chain + 6, 8);
    const set = chain + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 0); // BacktrackGlyphCount.
    writeU16Test(&bytes, rule + 2, 2); // InputGlyphCount.
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 0); // LookAheadGlyphCount.
    writeU16Test(&bytes, rule + 8, 1); // SubstCount.
    writeU16Test(&bytes, rule + 10, 0);
    writeU16Test(&bytes, rule + 12, 1);
    writeCoverage1(&bytes, chain + 26, 1);

    writeU16Test(&bytes, 56, 4); // LigatureSubst.
    writeU16Test(&bytes, 60, 1);
    writeU16Test(&bytes, 62, 8);
    const ligature_subst = 64;
    writeU16Test(&bytes, ligature_subst + 0, 1);
    writeU16Test(&bytes, ligature_subst + 2, 18);
    writeU16Test(&bytes, ligature_subst + 4, 1);
    writeU16Test(&bytes, ligature_subst + 6, 8);
    const ligature_set = ligature_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 1);
    writeU16Test(&bytes, ligature_set + 2, 4);
    const ligature = ligature_set + 4;
    writeU16Test(&bytes, ligature + 0, 10);
    writeU16Test(&bytes, ligature + 2, 2);
    writeU16Test(&bytes, ligature + 4, 2);
    writeCoverage1(&bytes, ligature_subst + 18, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 1, 2 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    // The first ligature shrinks the run, moving the second candidate to index
    // one. Resuming at the pre-substitution match end would skip it.
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 10 }, glyphs.items);
}

test "GSUB context nested extension ligature uses real glyph run" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 100;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1(&bytes, context + 22, 1);

    writeU16Test(&bytes, 52, 7);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const extension = 60;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 4);
    writeU32Test(&bytes, extension + 4, 8);

    const lig_subst = extension + 8;
    writeU16Test(&bytes, lig_subst + 0, 1);
    writeU16Test(&bytes, lig_subst + 2, 18);
    writeU16Test(&bytes, lig_subst + 4, 1);
    writeU16Test(&bytes, lig_subst + 6, 8);
    const ligature_set = lig_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 1);
    writeU16Test(&bytes, ligature_set + 2, 4);
    const ligature = ligature_set + 4;
    writeU16Test(&bytes, ligature + 0, 40);
    writeU16Test(&bytes, ligature + 2, 2);
    writeU16Test(&bytes, ligature + 4, 2);
    writeCoverage1(&bytes, lig_subst + 18, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    // Contextual extension lookups must not fall back to a one-glyph scratch
    // run when the wrapped subtable is LigatureSubst: the ligature needs to see
    // and consume the following component in the original glyph buffer.
    try std.testing.expectEqualSlices(GlyphId, &.{ 40, 3 }, glyphs.items);
}

test "GSUB context nested chaining lookup sees real lookahead" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10); // LookupList.
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 8); // Lookup 0: parent ContextSubst at 18.
    writeU16Test(&bytes, 14, 48); // Lookup 1: nested ChainingContextSubst at 58.
    writeU16Test(&bytes, 16, 98); // Lookup 2: nested SingleSubst at 108.

    const parent_lookup = 18;
    writeU16Test(&bytes, parent_lookup + 0, 5);
    writeU16Test(&bytes, parent_lookup + 2, 0);
    writeU16Test(&bytes, parent_lookup + 4, 1);
    writeU16Test(&bytes, parent_lookup + 6, 8);

    const parent_context = 26;
    writeU16Test(&bytes, parent_context + 0, 1);
    writeU16Test(&bytes, parent_context + 2, 22);
    writeU16Test(&bytes, parent_context + 4, 1);
    writeU16Test(&bytes, parent_context + 6, 8);
    const set = parent_context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeCoverage1(&bytes, parent_context + 22, 1);

    const nested_lookup = 58;
    writeU16Test(&bytes, nested_lookup + 0, 6);
    writeU16Test(&bytes, nested_lookup + 2, 0);
    writeU16Test(&bytes, nested_lookup + 4, 1);
    writeU16Test(&bytes, nested_lookup + 6, 8);

    const chain = nested_lookup + 8;
    writeU16Test(&bytes, chain + 0, 3);
    writeU16Test(&bytes, chain + 2, 0); // BacktrackGlyphCount.
    writeU16Test(&bytes, chain + 4, 1); // InputGlyphCount.
    writeU16Test(&bytes, chain + 6, 22);
    writeU16Test(&bytes, chain + 8, 1); // LookAheadGlyphCount.
    writeU16Test(&bytes, chain + 10, 28);
    writeU16Test(&bytes, chain + 12, 1); // SubstCount.
    writeU16Test(&bytes, chain + 14, 0);
    writeU16Test(&bytes, chain + 16, 2);
    writeCoverage1(&bytes, chain + 22, 1);
    writeCoverage1(&bytes, chain + 28, 2);

    writeSingleDeltaLookup(&bytes, 108, 1, 10);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, parent_lookup, &glyphs, allocator, .{});

    // A direct nested ChainingContextSubst must run at the real glyph-buffer
    // position. A one-glyph scratch buffer cannot see lookahead glyph 2 and
    // leaves glyph 1 unchanged.
    try std.testing.expectEqualSlices(GlyphId, &.{ 11, 2, 3 }, glyphs.items);
}

test "GSUB contextual records extend positions across extension multiple substitution" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 132;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 8);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 100);

    writeU16Test(&bytes, 18, 5);
    writeU16Test(&bytes, 22, 1);
    writeU16Test(&bytes, 24, 8);

    const context = 26;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 32);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 3);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 3);
    writeU16Test(&bytes, rule + 8, 1);
    writeU16Test(&bytes, rule + 10, 1);
    writeU16Test(&bytes, rule + 12, 2);
    writeU16Test(&bytes, rule + 14, 2);
    writeCoverage1(&bytes, context + 32, 1);

    writeU16Test(&bytes, 70, 7);
    writeU16Test(&bytes, 74, 1);
    writeU16Test(&bytes, 76, 8);
    const extension = 78;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 2);
    writeU32Test(&bytes, extension + 4, 8);

    const multiple = extension + 8;
    writeU16Test(&bytes, multiple + 0, 1);
    writeU16Test(&bytes, multiple + 2, 12);
    writeU16Test(&bytes, multiple + 4, 1);
    writeU16Test(&bytes, multiple + 6, 18);
    writeCoverage1(&bytes, multiple + 12, 2);
    const sequence = multiple + 18;
    writeU16Test(&bytes, sequence + 0, 2);
    writeU16Test(&bytes, sequence + 2, 20);
    writeU16Test(&bytes, sequence + 4, 21);

    writeSingleDeltaLookup(&bytes, 110, 21, 10);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 18, &glyphs, allocator, .{});

    // The first record inserts an extra glyph through ExtensionSubst wrapping
    // MultipleSubst. Context application extends its mutable match-position
    // array immediately after sequenceIndex 1, so the next record's
    // sequenceIndex 2 names the newly inserted replacement glyph 21.
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 20, 31, 3 }, glyphs.items);
}

test "GSUB contextual ligature compacts positions before a later multiple substitution" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 92;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10); // LookupList.
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6); // Ligature lookup at 16.
    writeU16Test(&bytes, 14, 40); // Multiple lookup at 50.

    writeU16Test(&bytes, 16, 4);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);
    const ligature_subst = 24;
    writeU16Test(&bytes, ligature_subst + 0, 1);
    writeU16Test(&bytes, ligature_subst + 2, 18);
    writeU16Test(&bytes, ligature_subst + 4, 1);
    writeU16Test(&bytes, ligature_subst + 6, 8);
    const ligature_set = ligature_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 1);
    writeU16Test(&bytes, ligature_set + 2, 4);
    const ligature = ligature_set + 4;
    writeU16Test(&bytes, ligature + 0, 10);
    writeU16Test(&bytes, ligature + 2, 2);
    writeU16Test(&bytes, ligature + 4, 2);
    writeCoverage1(&bytes, ligature_subst + 18, 1);

    writeU16Test(&bytes, 50, 2);
    writeU16Test(&bytes, 54, 1);
    writeU16Test(&bytes, 56, 8);
    const multiple_subst = 58;
    writeU16Test(&bytes, multiple_subst + 0, 1);
    writeU16Test(&bytes, multiple_subst + 2, 12);
    writeU16Test(&bytes, multiple_subst + 4, 1);
    writeU16Test(&bytes, multiple_subst + 6, 18);
    writeCoverage1(&bytes, multiple_subst + 12, 3);
    const sequence = multiple_subst + 18;
    writeU16Test(&bytes, sequence + 0, 2);
    writeU16Test(&bytes, sequence + 2, 3);
    writeU16Test(&bytes, sequence + 4, 4);

    const records = 84;
    writeU16Test(&bytes, records + 0, 0);
    writeU16Test(&bytes, records + 2, 0);
    writeU16Test(&bytes, records + 4, 1);
    writeU16Test(&bytes, records + 6, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    const input_indices = [_]usize{ 0, 1, 2 };
    try applySubstitutionRecordsMapped(
        .{ .data = &bytes, .offset = 0, .length = bytes.len },
        &glyphs,
        records,
        2,
        &input_indices,
        allocator,
        .{},
    );

    // The first nested lookup consumes input position one into a ligature.
    // SequenceIndex one in the next record therefore names the former input
    // position two, whose MultipleSubst expansion must remain in the result.
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 3, 4 }, glyphs.items);
}

test "GSUB contextual ligature remaps records across ignored components" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 8);
    writeU16Test(&bytes, 14, 50);
    writeU16Test(&bytes, 16, 82);

    writeU16Test(&bytes, 18, 5);
    writeU16Test(&bytes, 22, 1);
    writeU16Test(&bytes, 24, 8);

    const context = 26;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 28);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 3);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 99);
    writeU16Test(&bytes, rule + 6, 2);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 1);
    writeU16Test(&bytes, rule + 12, 2);
    writeU16Test(&bytes, rule + 14, 2);
    writeCoverage1(&bytes, context + 28, 1);

    writeU16Test(&bytes, 60, 4);
    writeU16Test(&bytes, 62, 0x0008);
    writeU16Test(&bytes, 64, 1);
    writeU16Test(&bytes, 66, 8);
    const lig_subst = 68;
    writeU16Test(&bytes, lig_subst + 0, 1);
    writeU16Test(&bytes, lig_subst + 2, 18);
    writeU16Test(&bytes, lig_subst + 4, 1);
    writeU16Test(&bytes, lig_subst + 6, 8);
    const ligature_set = lig_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 1);
    writeU16Test(&bytes, ligature_set + 2, 4);
    const ligature = ligature_set + 4;
    writeU16Test(&bytes, ligature + 0, 40);
    writeU16Test(&bytes, ligature + 2, 2);
    writeU16Test(&bytes, ligature + 4, 2);
    writeCoverage1(&bytes, lig_subst + 18, 1);

    writeU16Test(&bytes, 92, 1);
    writeU16Test(&bytes, 96, 1);
    writeU16Test(&bytes, 98, 8);
    const single = 100;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 6);
    writeI16Test(&bytes, single + 4, 1);
    writeCoverage1(&bytes, single + 6, 40);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 99, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });

    var ligature_components = ligature_provenance.Store{};
    defer ligature_components.deinit(allocator);
    try ligature_components.infos.resize(allocator, 3);
    @memset(ligature_components.infos.items, .{});

    var glyph_classes = [_]u16{0} ** 100;
    glyph_classes[99] = 3;
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 18, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
        .glyph_source_indices = &sources,
        .ligature_components = &ligature_components,
    });

    // HarfBuzz models a one-glyph contraction by removing the logical
    // position immediately after SequenceIndex zero. The old position two
    // shifts to one, so a later SequenceIndex two is now out of range even
    // though the nested ligature physically skipped the mark between inputs.
    try std.testing.expectEqualSlices(GlyphId, &.{ 40, 99 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sources.items);
    try std.testing.expectEqual(@as(u8, 2), ligature_components.infos.items[0].component_count);
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 2 },
        ligature_components.componentSources(ligature_components.infos.items[0]).?,
    );
    try std.testing.expectEqual(@as(u8, 1), ligature_components.infos.items[1].component_count);
}

test "GSUB source syllable matching can target selected lookup indexes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 46;

    writeU16Test(&bytes, 0, 8);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const reverse = 8;
    writeU16Test(&bytes, reverse + 0, 1);
    writeU16Test(&bytes, reverse + 2, 20);
    writeU16Test(&bytes, reverse + 4, 1);
    writeU16Test(&bytes, reverse + 6, 26);
    writeU16Test(&bytes, reverse + 8, 0);
    writeU16Test(&bytes, reverse + 10, 1);
    writeU16Test(&bytes, reverse + 12, 9);
    writeCoverage1(&bytes, reverse + 20, 2);
    writeCoverage1(&bytes, reverse + 26, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    const source_syllables = [_]u8{ 1, 2 };
    const matched_lookups = [_]u16{0};

    try applyLookupWithIndex(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, 0, &glyphs, allocator, .{
        .glyph_source_indices = &sources,
        .source_syllables = &source_syllables,
        .match_source_syllable_lookups = &matched_lookups,
    }, null);

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
}

fn writeSingleDeltaLookup(bytes: []u8, lookup_offset: usize, glyph: GlyphId, delta: i16) void {
    writeU16Test(bytes, lookup_offset + 0, 1);
    writeU16Test(bytes, lookup_offset + 4, 1);
    writeU16Test(bytes, lookup_offset + 6, 8);
    const subtable = lookup_offset + 8;
    writeU16Test(bytes, subtable + 0, 1);
    writeU16Test(bytes, subtable + 2, 6);
    writeI16Test(bytes, subtable + 4, delta);
    writeCoverage1(bytes, subtable + 6, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, glyph);
}

/// Static test bindings let integration suites exercise root orchestration
/// without widening the production API or paying for runtime callbacks.
const topologyTestHasFeature = hasFeature;

const FeatureIntegrationTestBindings = struct {
    pub const apply = applyWithOptions;
    pub const selectedLookups = selectedLookupIndicesForOptions;
    pub const selectedFeatureLookups =
        selectedFeatureLookupIndicesForOptions;
    pub const applySelectedSource =
        applySelectedSourceFeatureWithOptions;
    pub const applySource = applySourceFeatureWithOptions;
    pub const applyFeature = applyFeatureWithOptions;
    pub const applySequence = applyFeatureSequenceWithOptions;
    pub const buildPlan = buildFeatureLookupPlan;
    pub const applyPlan = applyFeatureLookupPlanWithOptions;
    pub const buildMergedPlan = buildMergedFeatureLookupPlan;
    pub const applyMergedPlan = applyMergedFeatureLookupPlanWithOptions;
    pub const validate = validateGlyphBounds;
};

const CacheIntegrationTestBindings = struct {
    pub const applyLookup = ContextualRecordExecutor.applyLookup;
    pub const applyCachedSelection =
        applyCachedLookupSelectionWithOptionsAfterMetadataProof;
};

const filteringTestApplyLookup = applyLookup;
const filteringTestApplyLookupWithIndex = applyLookupWithIndex;

const FilteringIntegrationTestBindings = struct {
    pub const applyLookup = filteringTestApplyLookup;
    pub const applyLookupWithIndex = filteringTestApplyLookupWithIndex;
};

const MetadataIntegrationTestBindings = struct {
    pub const apply = applyWithOptions;
};

const ExtensionIntegrationTestBindings = struct {
    pub const payload = extensionSubtablePayload;
    pub fn validate(table: Table, subtable_offset: usize) GsubError!void {
        return validation.lookup.extension.validate(
            ContextualRecordExecutor,
            table,
            subtable_offset,
        );
    }
    pub const apply = applyExtensionSubstitution;
    pub fn applyNested(
        table: Table,
        subtable_offset: usize,
        glyphs: *std.ArrayList(GlyphId),
        glyph_index: usize,
        allocator: std.mem.Allocator,
        lookup_flag: u16,
        options: LookupOptions,
    ) (GsubError || std.mem.Allocator.Error)!?NestedGlyphChange {
        return contextual_nested.extension.applyAt(
            ContextualRecordExecutor,
            table,
            subtable_offset,
            glyphs,
            glyph_index,
            allocator,
            lookup_flag,
            options,
        );
    }
};

const DirectValidationIntegrationTestBindings = struct {
    pub const applySingle = direct_single.subtable;
    pub const validateMultiple = validation.direct.set_sequence.multiple;
    pub const applyMultiple = direct_multiple.subtable;
    pub const validateAlternate = validation.direct.set_sequence.alternate;
    pub const applyAlternate = direct_alternate.subtable;
    pub const validateLigature = validation.direct.ligature.validate;
    pub const applyLigature = direct_ligature.subtable;
    pub const applyNestedLigature = contextual_nested.direct.ligature;
    pub const validateTable = validateGlyphBounds;
};

const ContextValidationIntegrationTestBindings = struct {
    pub const Executor = ContextualRecordExecutor;
    pub const validateTable = validateGlyphBounds;
};

const contextTestApplyLookup = applyLookup;

const ContextExecutionIntegrationTestBindings = struct {
    pub const Executor = ContextualRecordExecutor;
    pub const applyLookup = contextTestApplyLookup;
};

const chainingTestApplyLookup = applyLookup;
const chainingTestApplyLookupWithIndex = applyLookupWithIndex;

const ChainingExecutionIntegrationTestBindings = struct {
    pub const applyLookup = chainingTestApplyLookup;
    pub const applyLookupWithIndex = chainingTestApplyLookupWithIndex;
    pub const validateTable = validateGlyphBounds;
};

const GlyphBoundsTestBindings = struct {
    pub const validate = validateGlyphBounds;
    pub const validateForShaping = validateGlyphBoundsForShaping;
};

const TopologyTestBindings = struct {
    pub const apply = applyWithOptions;
    pub const validate = validateGlyphBounds;
    pub const isEmpty = isEmptyTable;
    pub const hasFeature = topologyTestHasFeature;
    pub const selectedLookups = selectedLookupIndicesForOptions;
    pub const buildPlan = buildFeatureLookupPlan;
    pub const applyPlan = applyFeatureLookupPlanWithOptions;
    pub const buildMergedPlan = buildMergedFeatureLookupPlan;
    pub const applyMergedPlan = applyMergedFeatureLookupPlanWithOptions;
};

test {
    _ = @import("gsub/tests/accelerator/root.zig");
    _ = @import("gsub/tests/execution/root.zig");
    _ = @import("gsub/tests/execution/contextual/atomicity/root.zig")
        .lookupSuite(ChainingExecutionIntegrationTestBindings);
    _ = @import("gsub/tests/execution/contextual/atomicity/root.zig")
        .nestedSuite(ChainingExecutionIntegrationTestBindings);
    _ = @import("gsub/tests/execution/contextual/atomicity/root.zig")
        .recordsSuite(ChainingExecutionIntegrationTestBindings);
    _ = @import("gsub/tests/execution/contextual/chaining/integration.zig")
        .suite(ChainingExecutionIntegrationTestBindings);
    _ = @import("gsub/tests/execution/contextual/context/integration.zig")
        .suite(ContextExecutionIntegrationTestBindings);
    _ = @import("gsub/tests/execution/contextual/context/accelerator_integration.zig")
        .suite(ContextExecutionIntegrationTestBindings);
    _ = @import("gsub/tests/execution/lookup/atomicity.zig")
        .suite(FilteringIntegrationTestBindings);
    _ = @import("gsub/tests/feature/root.zig");
    _ = @import("gsub/tests/feature/integration/root.zig")
        .applicationSuite(FeatureIntegrationTestBindings);
    _ = @import("gsub/tests/feature/integration/root.zig")
        .selectionSuite(FeatureIntegrationTestBindings);
    _ = @import("gsub/tests/runtime/cache_integration.zig")
        .suite(CacheIntegrationTestBindings);
    _ = @import("gsub/tests/runtime/filtering/integration.zig")
        .suite(FilteringIntegrationTestBindings);
    _ = @import("gsub/tests/runtime/metadata_integration.zig")
        .suite(MetadataIntegrationTestBindings);
    _ = @import("gsub/tests/runtime/root.zig");
    _ = @import("gsub/tests/table/root.zig");
    _ = @import("gsub/tests/validation/direct/integration.zig")
        .suite(DirectValidationIntegrationTestBindings);
    _ = @import("gsub/tests/validation/contextual/integration.zig")
        .suite(ContextValidationIntegrationTestBindings);
    _ = @import("gsub/tests/validation/table/glyph_bounds.zig")
        .suite(GlyphBoundsTestBindings);
    _ = @import("gsub/tests/validation/lookup/extension_integration.zig")
        .suite(ExtensionIntegrationTestBindings);
    _ = @import("gsub/tests/validation/table/topology.zig")
        .suite(TopologyTestBindings);
    _ = @import("gsub/tests/validation/root.zig");
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    writeU16Test(bytes, offset, @bitCast(value));
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
