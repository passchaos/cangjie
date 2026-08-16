const std = @import("std");
const accelerator_root = @import("gsub/accelerator/root.zig");
const accelerator_model = accelerator_root.model;
const cluster_safety = @import("shaping/cluster_safety.zig");
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
const class_context = @import("opentype/class_context.zig");
pub const runtime = @import("gsub/runtime/root.zig");
const runtime_filtering = @import("gsub/runtime/filtering.zig");
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
const ContextClassSubtableAccelerator = accelerator_model.ContextClassSubtable;
const FastSingleRecord = accelerator_model.FastSingleRecord;
const ChainingSubtableGroup = accelerator_model.ChainingGroup;
const ChainingSubtablePair = accelerator_model.ChainingPair;
const ChainingPairSubtableGroup = accelerator_model.ChainingPairGroup;
const ChainingPairSubtablePair = accelerator_model.ChainingPairEntry;
const deinitLookupAccelerators = accelerator_root.ownership.deinit;
const deinitLookupAcceleratorContents =
    accelerator_root.ownership.deinitContents;

const FeatureApplication = feature.Application;
const FeatureLookupPlanEntry = feature.LookupPlanEntry;
const MergedFeatureLookup = feature.MergedLookup;
const MergedFeatureLookupPlan = feature.MergedLookupPlan;
const FeatureLookupPlan = feature.LookupPlan;
const sourceFeatureMaskForTag = feature.sourceMaskForTag;

const NestedGlyphChange = contextual_model.Change;
const markUnsafeContextMatch = contextual_safety.markInput;

/// HarfBuzz enables `rand` globally with HB_OT_MAP_MAX_VALUE. Keep the sentinel
/// public so explicit script shapers can place the common feature in the same
/// staged lookup plan as their script-specific features.
const random_feature_value = feature.random_value;

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
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
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

test "GSUB ranged feature helper selects and applies only assigned sources" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    writeCachedSingleFeatureGsubTest(&bytes);

    const lookups = try selectedFeatureLookupIndicesForOptions(
        &bytes,
        0,
        bytes.len,
        unicode.tag("liga"),
        allocator,
        .{ .script_tag = .dflt },
    );
    defer allocator.free(lookups);
    try std.testing.expectEqualSlices(u16, &.{0}, lookups);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 10, 10 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 0, 1, 2 });
    const source_features = [_]u32{ unicode.tag("liga"), 0, unicode.tag("liga") };

    try applySelectedSourceFeatureWithOptions(
        &bytes,
        0,
        bytes.len,
        lookups,
        unicode.tag("liga"),
        1,
        &glyphs,
        allocator,
        .{
            .script_tag = .dflt,
            .glyph_source_indices = &sources,
            .glyph_cluster_indices = &clusters,
            .source_features = &source_features,
        },
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 11, 10, 11 }, glyphs.items);
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

test "GSUB staged plans retain random AlternateSubst semantics" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    writeRandomFeatureGsubTest(&bytes);
    const application = [_]FeatureApplication{.{
        .tag = unicode.tag("rand"),
        .value = random_feature_value,
    }};
    const expected = [_]GlyphId{ 30, 20, 20, 30 };

    // Exercise the uncached staged executor as well as both immutable plan
    // representations used by script shapers. A numeric value of 255 without
    // the semantic random bit would make every AlternateSubst a no-op here.
    var direct = std.ArrayList(GlyphId).empty;
    defer direct.deinit(allocator);
    try direct.appendSlice(allocator, &.{ 10, 10, 10, 10 });
    var direct_state: u32 = 1;
    try applyFeatureSequenceWithOptions(
        &bytes,
        0,
        bytes.len,
        &application,
        &direct,
        allocator,
        .{ .script_tag = .dflt, .random_state = &direct_state },
    );
    try std.testing.expectEqualSlices(GlyphId, &expected, direct.items);

    var feature_plan = try buildFeatureLookupPlan(
        &bytes,
        0,
        bytes.len,
        &application,
        allocator,
        .{ .script_tag = .dflt },
    );
    defer feature_plan.deinit(allocator);
    var planned = std.ArrayList(GlyphId).empty;
    defer planned.deinit(allocator);
    try planned.appendSlice(allocator, &.{ 10, 10, 10, 10 });
    var planned_state: u32 = 1;
    try applyFeatureLookupPlanWithOptions(
        &bytes,
        0,
        bytes.len,
        feature_plan,
        &planned,
        allocator,
        .{ .script_tag = .dflt, .random_state = &planned_state },
    );
    try std.testing.expectEqualSlices(GlyphId, &expected, planned.items);

    var merged_plan = try buildMergedFeatureLookupPlan(
        &bytes,
        0,
        bytes.len,
        &application,
        allocator,
        .{ .script_tag = .dflt },
    );
    defer merged_plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), merged_plan.lookups.len);
    try std.testing.expect(merged_plan.lookups[0].random);
    var merged = std.ArrayList(GlyphId).empty;
    defer merged.deinit(allocator);
    try merged.appendSlice(allocator, &.{ 10, 10, 10, 10 });
    var merged_state: u32 = 1;
    try applyMergedFeatureLookupPlanWithOptions(
        &bytes,
        0,
        bytes.len,
        merged_plan,
        &merged,
        allocator,
        .{ .script_tag = .dflt, .random_state = &merged_state },
    );
    try std.testing.expectEqualSlices(GlyphId, &expected, merged.items);
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

test "GSUB run digest cache reuses no-op runs and invalidates on substitution" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1); // SingleSubst format 1.
    writeU16Test(&bytes, 2, 6);
    writeI16Test(&bytes, 4, 1);
    writeCoverage1(&bytes, 6, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    var generation: usize = 0;
    const options = LookupOptions{ .glyph_mutation_generation = &generation };
    var cache = runtime_prefilter.Cache{};

    const first = cache.digestForRun(glyphs.items, 0, options);
    try std.testing.expect(first.mayHave(1));

    // Consecutive no-op contextual lookups reuse the old summary.
    const second = cache.digestForRun(glyphs.items, 0, options);
    try std.testing.expect(second.mayHave(1));
    try std.testing.expectEqual(@as(usize, 1), cache.len);

    // A substitution can introduce the first-input glyph of a later lookup.
    // The actual substitution primitive advances the common mutation epoch,
    // forcing the later lookup to discard the old negative summary.
    try std.testing.expect(try direct_single.at(
        .{ .data = &bytes, .offset = 0, .length = bytes.len },
        0,
        &glyphs,
        0,
        0,
        options,
    ));
    const after_substitution = cache.digestForRun(glyphs.items, 0, options);
    try std.testing.expect(after_substitution.mayHave(2));
    try std.testing.expect(!after_substitution.mayHave(1));
    try std.testing.expectEqual(generation, cache.generation);
}

test "GSUB operation budget bounds repeated contextual expansion" {
    var operations_left: usize = 64;
    const options = LookupOptions{
        .operations_left = &operations_left,
        .max_glyph_count = 128,
    };

    var glyph_count: usize = 3;
    var expansions: usize = 0;
    while (true) {
        runtime.limits.consumeNested(options) catch |err| {
            try std.testing.expectEqual(error.ShapingLimitExceeded, err);
            break;
        };
        runtime.limits.consumeMutation(options, glyph_count, 1, 19) catch |err| {
            try std.testing.expectEqual(error.ShapingLimitExceeded, err);
            break;
        };
        glyph_count += 18;
        expansions += 1;
    }

    try std.testing.expect(expansions > 0);
    try std.testing.expect(glyph_count <= options.max_glyph_count.?);
    // A failed preflight must not consume or mutate the hypothetical run.
    const before = glyph_count;
    try std.testing.expectError(
        error.ShapingLimitExceeded,
        runtime.limits.consumeMutation(options, glyph_count, 1, options.max_glyph_count.?),
    );
    try std.testing.expectEqual(before, glyph_count);
}

test "GSUB ligature run digest activates only when reusable" {
    const allocator = std.testing.allocator;

    var single_lookup_bytes = [_]u8{0} ** 46;
    writeU32Test(&single_lookup_bytes, 0, 0x00010000);
    writeU16Test(&single_lookup_bytes, 8, 10); // LookupList.
    writeU16Test(&single_lookup_bytes, 10, 1);
    writeU16Test(&single_lookup_bytes, 12, 4); // Lookup at 14.
    writeLigatureLookupTest(&single_lookup_bytes, 14, 1, 2, 5);

    const single_accelerators = try accelerator_root.build.lookup.build(
        &single_lookup_bytes,
        0,
        single_lookup_bytes.len,
        allocator,
    );
    defer deinitLookupAccelerators(allocator, single_accelerators);
    try std.testing.expect(!single_accelerators[0].table_uses_run_digest_cache);

    // A lone ligature lookup would build the same whole-run summary that its
    // exact scan is about to consume. Keep mutation-epoch bookkeeping disabled
    // until at least two independent first-component coverages can share it.
    var generation: usize = 0;
    const single_options = runtime.state.withDigestGeneration(
        .{ .lookup_accelerators = single_accelerators },
        &generation,
    );
    try std.testing.expect(single_options.glyph_mutation_generation == null);

    var two_lookup_bytes = [_]u8{0} ** 80;
    writeU32Test(&two_lookup_bytes, 0, 0x00010000);
    writeU16Test(&two_lookup_bytes, 8, 10); // LookupList.
    writeU16Test(&two_lookup_bytes, 10, 2);
    writeU16Test(&two_lookup_bytes, 12, 6); // Lookup 0 at 16.
    writeU16Test(&two_lookup_bytes, 14, 38); // Lookup 1 at 48.
    writeLigatureLookupTest(&two_lookup_bytes, 16, 1, 2, 5);
    writeLigatureLookupTest(&two_lookup_bytes, 48, 5, 3, 9);

    const two_accelerators = try accelerator_root.build.lookup.build(
        &two_lookup_bytes,
        0,
        two_lookup_bytes.len,
        allocator,
    );
    defer deinitLookupAccelerators(allocator, two_accelerators);
    try std.testing.expect(two_accelerators[0].table_uses_run_digest_cache);
    try std.testing.expect(two_accelerators[0].ligature_subst.first_component_digest.mayHave(1));
    try std.testing.expect(two_accelerators[1].ligature_subst.first_component_digest.mayHave(5));

    const two_options = runtime.state.withDigestGeneration(
        .{ .lookup_accelerators = two_accelerators },
        &generation,
    );
    try std.testing.expect(two_options.glyph_mutation_generation != null);
}

test "GSUB ligature run digest invalidates after an earlier ligature" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10); // LookupList.
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6); // Lookup 0 at 16.
    writeU16Test(&bytes, 14, 38); // Lookup 1 at 48.
    writeLigatureLookupTest(&bytes, 16, 1, 2, 5);
    writeLigatureLookupTest(&bytes, 48, 5, 3, 9);

    const accelerators = try accelerator_root.build.lookup.build(&bytes, 0, bytes.len, allocator);
    defer deinitLookupAccelerators(allocator, accelerators);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    var generation: usize = 0;
    const options = LookupOptions{
        .lookup_accelerators = accelerators,
        .glyph_mutation_generation = &generation,
        .assume_validated = true,
    };
    var cache = runtime_prefilter.Cache.init();
    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    // Lookup 0 caches the original {1,2,3} run and produces glyph 5. Lookup 1
    // starts with 5, which was absent from that summary, so it can only form
    // the final ligature if the first edit invalidates the shared digest.
    try applyLookupWithIndex(table, 16, 0, &glyphs, allocator, options, &cache);
    try std.testing.expectEqualSlices(GlyphId, &.{ 5, 3 }, glyphs.items);
    try applyLookupWithIndex(table, 48, 1, &glyphs, allocator, options, &cache);
    try std.testing.expectEqualSlices(GlyphId, &.{9}, glyphs.items);

    // The second ligature advances the epoch after its prefilter read. A later
    // lookup must likewise observe the final glyph rather than retain {5,3}.
    const final_digest = cache.digestForRun(glyphs.items, 0, options);
    try std.testing.expect(final_digest.mayHave(9));
    try std.testing.expect(!final_digest.mayHave(5));
    try std.testing.expectEqual(generation, cache.generation);
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

fn checkedRequiredScriptListOffset(table: Table) GsubError!usize {
    return table_core.service.requiredScriptList(table);
}

fn checkedRequiredFeatureListOffset(table: Table) GsubError!usize {
    return table_core.service.requiredFeatureList(table);
}

fn checkedRequiredLookupListOffset(table: Table) GsubError!usize {
    return table_core.service.requiredLookupList(table);
}

fn checkedRequiredLookupOffset(table: Table, lookup_list_offset: usize, relative_offset: u16) GsubError!usize {
    return table_core.service.requiredLookup(
        table,
        lookup_list_offset,
        relative_offset,
    );
}

fn readU16(table: Table, relative: usize) GsubError!u16 {
    return table.readU16(relative);
}

fn readU32(table: Table, relative: usize) GsubError!u32 {
    return table.readU32(relative);
}

test "GSUB rejects ExtensionSubst payload offsets outside the table during shaping" {
    var bytes = [_]u8{0} ** 8;
    writeU16Test(&bytes, 0, 1); // ExtensionSubst format 1.
    writeU16Test(&bytes, 2, 1); // Wrapped SingleSubst.
    writeU32Test(&bytes, 4, 0xffff_fffe); // Far beyond this table.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 5);

    // These calls intentionally bypass Font.parse/lookup preflight. Extension
    // wrappers are also followed by low-level shaping helpers, so every runtime
    // path must convert a malicious Offset32 into BadGsub before reading the
    // wrapped payload or mutating the glyph stream.
    try std.testing.expectError(error.BadGsub, extensionSubtablePayload(table, 0, 1));
    try std.testing.expectError(error.BadGsub, applyExtensionSubstitution(table, 0, &glyphs, std.testing.allocator, 0, .{}));
    try std.testing.expectError(error.BadGsub, contextual_nested.extension.applyAt(ContextualRecordExecutor, table, 0, &glyphs, 0, std.testing.allocator, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
}

test "GSUB rejects ExtensionSubst payload offsets that alias the wrapper header" {
    var bytes = [_]u8{0} ** 8;
    writeU16Test(&bytes, 0, 1); // ExtensionSubst format 1.
    writeU16Test(&bytes, 2, 1); // Wrapped SingleSubst.
    writeU32Test(&bytes, 4, 4); // Points into the ExtensionOffset field itself.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 5);

    // Offset32 values below the fixed wrapper size are in-range byte addresses,
    // but they do not name a child subtable. Reject them before wrapper fields
    // can be reinterpreted as a nested lookup payload.
    try std.testing.expectError(error.BadGsub, extensionSubtablePayload(table, 0, 1));
    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.extension.validate(
            ContextualRecordExecutor,
            table,
            0,
        ),
    );
    try std.testing.expectError(error.BadGsub, applyExtensionSubstitution(table, 0, &glyphs, std.testing.allocator, 0, .{}));
    try std.testing.expectError(error.BadGsub, contextual_nested.extension.applyAt(ContextualRecordExecutor, table, 0, &glyphs, 0, std.testing.allocator, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
}

test "GSUB FeatureVariations substitute active feature lookups by normalized coordinates" {
    var bytes = [_]u8{0} ** 120;
    writeU32Test(&bytes, 0, 0x00010001);
    writeU16Test(&bytes, 4, 14); // ScriptList.
    writeU16Test(&bytes, 6, 34); // FeatureList.
    writeU16Test(&bytes, 8, 46); // LookupList.
    writeU32Test(&bytes, 10, 72); // FeatureVariations.

    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(&bytes, 20, 8);
    writeU16Test(&bytes, 22, 4);
    writeU16Test(&bytes, 24, 0);
    writeU16Test(&bytes, 26, 0);
    writeU16Test(&bytes, 28, 0xffff);
    writeU16Test(&bytes, 30, 1);
    writeU16Test(&bytes, 32, 0);

    writeU16Test(&bytes, 34, 1);
    writeU32Test(&bytes, 36, unicode.tag("rvrn"));
    writeU16Test(&bytes, 40, 8);
    writeU16Test(&bytes, 42, 0);
    writeU16Test(&bytes, 44, 0);

    writeU16Test(&bytes, 46, 1);
    writeU16Test(&bytes, 48, 4);
    writeU16Test(&bytes, 50, 1);
    writeU16Test(&bytes, 52, 0);
    writeU16Test(&bytes, 54, 1);
    writeU16Test(&bytes, 56, 8);
    writeU16Test(&bytes, 58, 2);
    writeU16Test(&bytes, 60, 8);
    writeU16Test(&bytes, 62, 1);
    writeU16Test(&bytes, 64, 2);
    writeU16Test(&bytes, 66, 1);
    writeU16Test(&bytes, 68, 1);
    writeU16Test(&bytes, 70, 1);

    writeU32Test(&bytes, 72, 0x00010000);
    writeU32Test(&bytes, 76, 1);
    writeU32Test(&bytes, 80, 16);
    writeU32Test(&bytes, 84, 30);
    writeU16Test(&bytes, 88, 1);
    writeU32Test(&bytes, 90, 6);
    writeU16Test(&bytes, 94, 1);
    writeU16Test(&bytes, 96, 1);
    writeI16Test(&bytes, 98, 8192);
    writeI16Test(&bytes, 100, 16384);
    writeU32Test(&bytes, 102, 0x00010000);
    writeU16Test(&bytes, 106, 1);
    writeU16Test(&bytes, 108, 0);
    writeU32Test(&bytes, 110, 12);
    writeU16Test(&bytes, 114, 0);
    writeU16Test(&bytes, 116, 1);
    writeU16Test(&bytes, 118, 0);

    var low = std.ArrayList(GlyphId).empty;
    defer low.deinit(std.testing.allocator);
    try low.append(std.testing.allocator, 1);
    try applyWithOptions(&bytes, 0, bytes.len, &low, std.testing.allocator, .{
        .normalized_variation_coords = &.{ 0.0, 0.25 },
        .apply_all_if_unselected = false,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{1}, low.items);

    var high = std.ArrayList(GlyphId).empty;
    defer high.deinit(std.testing.allocator);
    try high.append(std.testing.allocator, 1);
    try applyWithOptions(&bytes, 0, bytes.len, &high, std.testing.allocator, .{
        .normalized_variation_coords = &.{ 0.0, 0.75 },
        .apply_all_if_unselected = false,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{2}, high.items);
}

test "GSUB rejects malformed coverage ordering before substitution" {
    var bytes = [_]u8{0} ** 18;
    writeU16Test(&bytes, 0, 2); // SingleSubst format 2.
    writeU16Test(&bytes, 2, 10); // Coverage table.
    writeU16Test(&bytes, 4, 1); // Substitute array has one entry.
    writeU16Test(&bytes, 6, 20);
    writeU16Test(&bytes, 10, 1); // Coverage format 1.
    writeU16Test(&bytes, 12, 2);
    writeU16Test(&bytes, 14, 10);
    writeU16Test(&bytes, 16, 5); // Out-of-order; binary search would be unsound.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 10);

    try std.testing.expectError(error.BadGsub, direct_single.subtable(table, 0, &glyphs, 0, .{}));
    try std.testing.expectEqual(@as(GlyphId, 10), glyphs.items[0]);
}

test "GSUB parse-time contextual records avoid recursively validating lookup payloads" {
    var bytes = [_]u8{0} ** 120;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // ScriptList.
    writeU16Test(&bytes, 6, 12); // FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0: contextual wrapper.
    writeU16Test(&bytes, 18, 40); // Lookup 1: intentionally truncated payload.

    writeU16Test(&bytes, 20, 5); // ContextSubst lookup type.
    writeU16Test(&bytes, 22, 0);
    writeU16Test(&bytes, 24, 1);
    writeU16Test(&bytes, 26, 8);
    const context_subtable: usize = 28;
    writeU16Test(&bytes, context_subtable + 0, 1); // ContextSubst format 1.
    writeU16Test(&bytes, context_subtable + 2, 20); // Coverage.
    writeU16Test(&bytes, context_subtable + 4, 1); // SubRuleSetCount.
    writeU16Test(&bytes, context_subtable + 6, 14); // SubRuleSet offset.
    writeCoverage1(&bytes, context_subtable + 20, 1);
    const rule_set = context_subtable + 14;
    writeU16Test(&bytes, rule_set + 0, 1);
    writeU16Test(&bytes, rule_set + 2, 4);
    const rule = rule_set + 4;
    writeU16Test(&bytes, rule + 0, 1); // GlyphCount.
    writeU16Test(&bytes, rule + 2, 1); // SubstCount.
    writeU16Test(&bytes, rule + 4, 0); // SequenceIndex.
    writeU16Test(&bytes, rule + 6, 1); // LookupListIndex -> lookup 1.

    const nested_lookup: usize = 54;
    writeU16Test(&bytes, nested_lookup + 0, 2); // MultipleSubst.
    writeU16Test(&bytes, nested_lookup + 2, 0);
    writeU16Test(&bytes, nested_lookup + 4, 1);
    writeU16Test(&bytes, nested_lookup + 6, 8); // Payload exists but is too short for MultipleSubst.
    const nested_subtable = nested_lookup + 8;
    writeU16Test(&bytes, nested_subtable + 0, 1);
    writeU16Test(&bytes, nested_subtable + 2, 10); // Coverage offset.
    writeU16Test(&bytes, nested_subtable + 4, 1); // SequenceCount.
    writeU16Test(&bytes, nested_subtable + 6, 0); // Invalid required SequenceOffset.
    writeCoverage1(&bytes, nested_subtable + 10, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .glyph_count = 10 };
    try contextual_records.validateReferences(
        ContextualRecordExecutor,
        table,
        rule + 4,
        1,
    );
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 10));
}

test "GSUB rejects reserved LookupFlag bits" {
    var bytes = [_]u8{0} ** 40;
    _ = writeSingleLookupGsubTest(&bytes, 1);
    writeU16Test(&bytes, 24, 10); // Leave room for MarkFilteringSet when bit 4 is set.
    const subtable: usize = 28;
    writeU16Test(&bytes, 20, 0x0020); // Reserved middle-bit range in LookupFlag.
    writeU16Test(&bytes, subtable + 0, 1); // SingleSubst format 1.
    writeU16Test(&bytes, subtable + 2, 6);
    writeI16Test(&bytes, subtable + 4, 0);
    writeCoverage1(&bytes, subtable + 6, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.validateHeader(
            ContextualRecordExecutor,
            table,
            18,
        ),
    );
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 20, 0xff10); // MarkAttachmentType plus UseMarkFilteringSet are valid.
    writeU16Test(&bytes, 26, 0); // MarkFilteringSet index follows the subtable-offset array.
    _ = try validation.lookup.validateHeader(
        ContextualRecordExecutor,
        table,
        18,
    );
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GSUB rejects null top-level LookupList offsets" {
    var bytes = [_]u8{0} ** 38;
    const subtable = writeSingleLookupGsubTest(&bytes, 1);
    writeU16Test(&bytes, subtable + 0, 1); // SingleSubst format 1.
    writeU16Test(&bytes, subtable + 2, 6);
    writeI16Test(&bytes, subtable + 4, 0);
    writeCoverage1(&bytes, subtable + 6, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);

    writeU16Test(&bytes, 8, 0); // Invalid: LookupList is a required top-level table.
    try std.testing.expectError(error.BadGsub, checkedRequiredLookupListOffset(table));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGsub, applyWithOptions(&bytes, 0, bytes.len, &glyphs, std.testing.allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // Restoring the real LookupList pointer makes the same no-op lookup valid;
    // only aliasing the GSUB header as a LookupList is rejected.
    writeU16Test(&bytes, 8, 14);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    try applyWithOptions(&bytes, 0, bytes.len, &glyphs, std.testing.allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}

test "GSUB rejects null LookupList child offsets" {
    var bytes = [_]u8{0} ** 38;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 1); // LookupCount.
    writeU16Test(&bytes, 16, 0); // Invalid: LookupList child offsets are required.

    // If the null child pointer were accepted, the LookupList header would be
    // reinterpreted as a valid SingleSubst lookup: LookupCount becomes
    // LookupType, the null child offset becomes LookupFlag, and the following
    // words point at this real subtable. Keep the alias plausible so this test
    // covers the child-pointer contract rather than relying on later truncation.
    writeU16Test(&bytes, 18, 1); // Aliased SubTableCount.
    writeU16Test(&bytes, 20, 8); // Aliased SubTable offset: 14 + 8 == 22.
    writeU16Test(&bytes, 22, 1); // SingleSubst format 1.
    writeU16Test(&bytes, 24, 6);
    writeI16Test(&bytes, 26, 1);
    writeCoverage1(&bytes, 28, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, checkedRequiredLookupOffset(table, 14, 0));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, applyWithOptions(&bytes, 0, bytes.len, &glyphs, std.testing.allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // Rebuild the same logical lookup with a non-null LookupList child offset.
    // The repaired table applies normally; only the null Lookup pointer was bad.
    const subtable = writeSingleLookupGsubTest(&bytes, 1);
    writeU16Test(&bytes, subtable + 0, 1);
    writeU16Test(&bytes, subtable + 2, 6);
    writeI16Test(&bytes, subtable + 4, 1);
    writeCoverage1(&bytes, subtable + 6, 1);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    try applyWithOptions(&bytes, 0, bytes.len, &glyphs, std.testing.allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{2}, glyphs.items);
}

test "GSUB accepts the all-null empty topology" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU32Test(&bytes, 0, 0x00010000);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expect(try isEmptyGsubTopology(table));
    try std.testing.expect(try isEmptyTable(&bytes, 0, bytes.len));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    try std.testing.expect(!(try hasFeature(&bytes, 0, bytes.len, unicode.tag("liga"))));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    try applyWithOptions(&bytes, 0, bytes.len, &glyphs, allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);

    const selected = try selectedLookupIndicesForOptions(&bytes, 0, bytes.len, allocator, .{});
    defer allocator.free(selected);
    try std.testing.expectEqual(@as(usize, 0), selected.len);

    var feature_plan = try buildFeatureLookupPlan(
        &bytes,
        0,
        bytes.len,
        &.{.{ .tag = unicode.tag("liga") }},
        allocator,
        .{},
    );
    defer feature_plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), feature_plan.entries.len);
    try applyFeatureLookupPlanWithOptions(&bytes, 0, bytes.len, feature_plan, &glyphs, allocator, .{});

    var merged_plan = try buildMergedFeatureLookupPlan(
        &bytes,
        0,
        bytes.len,
        &.{.{ .tag = unicode.tag("liga") }},
        allocator,
        .{},
    );
    defer merged_plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), merged_plan.lookups.len);
    try applyMergedFeatureLookupPlanWithOptions(&bytes, 0, bytes.len, merged_plan, &glyphs, allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);

    const accelerators = try accelerator_root.build.lookup.build(&bytes, 0, bytes.len, allocator);
    defer allocator.free(accelerators);
    try std.testing.expectEqual(@as(usize, 0), accelerators.len);

    // A partial null topology is not an empty table and must retain required
    // child-pointer validation.
    writeU16Test(&bytes, 4, 2);
    try std.testing.expect(!(try isEmptyGsubTopology(table)));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
}

test "GSUB rejects null top-level ScriptList and FeatureList offsets" {
    var bytes = [_]u8{0} ** 38;
    const subtable = writeSingleLookupGsubTest(&bytes, 1);
    writeU16Test(&bytes, subtable + 0, 1); // SingleSubst format 1.
    writeU16Test(&bytes, subtable + 2, 6);
    writeI16Test(&bytes, subtable + 4, 1);
    writeCoverage1(&bytes, subtable + 6, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);

    writeU16Test(&bytes, 4, 0); // Invalid: ScriptList is required, even when empty.
    try std.testing.expectError(error.BadGsub, checkedRequiredScriptListOffset(table));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try applyWithOptions(&bytes, 0, bytes.len, &glyphs, std.testing.allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{2}, glyphs.items);

    writeU16Test(&bytes, 4, 10);
    writeU16Test(&bytes, 6, 0); // Invalid: FeatureList is required, even when empty.
    glyphs.clearRetainingCapacity();
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, checkedRequiredFeatureListOffset(table));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGsub, applyWithOptions(&bytes, 0, bytes.len, &glyphs, std.testing.allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // Non-null empty ScriptList/FeatureList tables are valid. With no selected
    // feature topology, the low-level apply API keeps its historical all-lookup
    // fallback and applies this SingleSubst normally.
    writeU16Test(&bytes, 6, 12);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    try applyWithOptions(&bytes, 0, bytes.len, &glyphs, std.testing.allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{2}, glyphs.items);
}

test "GSUB rejects null Lookup SubTable offsets" {
    var bytes = [_]u8{0} ** 38;
    const subtable = writeSingleLookupGsubTest(&bytes, 1);
    writeU16Test(&bytes, subtable + 0, 1); // SingleSubst format 1.
    writeU16Test(&bytes, subtable + 2, 6);
    writeI16Test(&bytes, subtable + 4, 0);
    writeCoverage1(&bytes, subtable + 6, 1);
    writeU16Test(&bytes, 24, 0); // Invalid: Lookup.SubTable offsets are required.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.validateSubtables(
            ContextualRecordExecutor,
            table,
            18,
            1,
            1,
            .strict,
        ),
    );
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, applyLookup(table, 18, &glyphs, std.testing.allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // Repairing only the child pointer should make the otherwise valid lookup
    // pass; the test guards against rejecting empty/no-op substitution data.
    writeU16Test(&bytes, 24, 8);
    try validation.lookup.validateSubtables(
        ContextualRecordExecutor,
        table,
        18,
        1,
        1,
        .strict,
    );
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GSUB rejects null required Coverage offsets" {
    var bytes = [_]u8{0} ** 38;
    const subtable = writeSingleLookupGsubTest(&bytes, 1);
    writeU16Test(&bytes, subtable + 0, 1); // SingleSubst format 1.
    writeU16Test(&bytes, subtable + 2, 0); // Invalid: Coverage offsets are required.
    writeI16Test(&bytes, subtable + 4, 1);
    writeCoverage1(&bytes, subtable + 6, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, validation.direct.single.validate(table, subtable));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, direct_single.subtable(table, subtable, &glyphs, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
    try std.testing.expectError(error.BadGsub, applyLookup(table, 18, &glyphs, std.testing.allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // With the Coverage pointer repaired, the same subtable is a normal
    // SingleSubst; only the aliasing null child pointer is invalid.
    writeU16Test(&bytes, subtable + 2, 6);
    try validation.direct.single.validate(table, subtable);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GSUB validates FeatureList lookup indexes against LookupList" {
    var bytes = [_]u8{0} ** 50;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 48); // Empty ScriptList; this test targets FeatureList topology.
    writeU16Test(&bytes, 6, 10); // FeatureList.
    writeU16Test(&bytes, 8, 24); // LookupList.

    writeU16Test(&bytes, 10, 1); // FeatureCount.
    writeU32Test(&bytes, 12, unicode.tag("liga"));
    writeU16Test(&bytes, 16, 8); // FeatureTable at offset 18.
    writeU16Test(&bytes, 20, 1); // LookupIndexCount.
    writeU16Test(&bytes, 22, 1); // Dangling: LookupList has only index 0.

    writeU16Test(&bytes, 24, 1);
    writeU16Test(&bytes, 26, 4);
    writeSingleDeltaLookup(&bytes, 28, 1, 0);
    writeU16Test(&bytes, 48, 0); // ScriptCount.

    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 22, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GSUB validates ScriptList LangSys feature indexes against FeatureList" {
    var bytes = [_]u8{0} ** 80;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // ScriptList.
    writeU16Test(&bytes, 6, 40); // FeatureList.
    writeU16Test(&bytes, 8, 56); // LookupList.

    writeU16Test(&bytes, 10, 1);
    writeU32Test(&bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(&bytes, 16, 8);

    writeU16Test(&bytes, 18, 4); // DefaultLangSys at offset 22.
    writeU16Test(&bytes, 20, 0);
    writeU16Test(&bytes, 22, 0);
    writeU16Test(&bytes, 24, 0xffff);
    writeU16Test(&bytes, 26, 1);
    writeU16Test(&bytes, 28, 1); // Dangling: FeatureList has only index 0.

    writeU16Test(&bytes, 40, 1);
    writeFeatureRecord(&bytes, 42, unicode.tag("liga"), 8);
    writeFeature(&bytes, 50, 0);

    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 4);
    writeSingleDeltaLookup(&bytes, 60, 1, 0);

    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 28, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);

    writeU16Test(&bytes, 24, 1); // ReqFeatureIndex is checked too.
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
}

test "GSUB contextual class subtables allow covered class indexes outside set arrays" {
    const allocator = std.testing.allocator;

    var context_bytes = [_]u8{0} ** 32;
    writeU16Test(&context_bytes, 0, 2); // ContextSubst format 2.
    writeU16Test(&context_bytes, 2, 12); // Coverage.
    writeU16Test(&context_bytes, 4, 18); // ClassDef.
    writeU16Test(&context_bytes, 6, 1); // Only class 0 has a SubClassSet slot.
    writeU16Test(&context_bytes, 8, 0); // Nullable class-0 SubClassSet.
    writeCoverage1(&context_bytes, 12, 5);
    writeClassDef1(&context_bytes, 18, 5, 1); // Covered glyph indexes past SubClassSetCount.

    var table = Table{ .data = &context_bytes, .offset = 0, .length = context_bytes.len };
    try validation.contextual.context.validate(
        ContextualRecordExecutor,
        table,
        0,
    );

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    try contextual_context.subtable(ContextualRecordExecutor, table, 0, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);

    writeClassDef1(&context_bytes, 18, 5, 0);
    try validation.contextual.context.validate(
        ContextualRecordExecutor,
        table,
        0,
    );

    var chaining_bytes = [_]u8{0} ** 48;
    writeU16Test(&chaining_bytes, 0, 2); // ChainingContextSubst format 2.
    writeU16Test(&chaining_bytes, 2, 16); // Coverage.
    writeU16Test(&chaining_bytes, 4, 22); // BacktrackClassDef.
    writeU16Test(&chaining_bytes, 6, 30); // InputClassDef.
    writeU16Test(&chaining_bytes, 8, 38); // LookaheadClassDef.
    writeU16Test(&chaining_bytes, 10, 1); // Only class 0 has a ChainSubClassSet slot.
    writeU16Test(&chaining_bytes, 12, 0); // Nullable class-0 ChainSubClassSet.
    writeCoverage1(&chaining_bytes, 16, 5);
    writeClassDef1(&chaining_bytes, 22, 0, 0);
    writeClassDef1(&chaining_bytes, 30, 5, 1); // Covered input glyph indexes past ChainSubClassSetCount.
    writeClassDef1(&chaining_bytes, 38, 0, 0);

    table = .{ .data = &chaining_bytes, .offset = 0, .length = chaining_bytes.len };
    try validation.contextual.chaining.validate(
        ContextualRecordExecutor,
        table,
        0,
        .strict,
    );
    try contextual_chaining_class.subtable(
        ContextualRecordExecutor,
        table,
        0,
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);

    writeClassDef1(&chaining_bytes, 30, 5, 0);
    try validation.contextual.chaining.validate(
        ContextualRecordExecutor,
        table,
        0,
        .strict,
    );
}

test "GSUB class-based substitutions handle null ClassDef offsets where HarfBuzz allows them" {
    const allocator = std.testing.allocator;

    var context_bytes = [_]u8{0} ** 26;
    writeU16Test(&context_bytes, 0, 2); // ContextSubst format 2.
    writeU16Test(&context_bytes, 2, 12); // Coverage.
    writeU16Test(&context_bytes, 4, 0); // Invalid: ClassDef offsets are required.
    writeU16Test(&context_bytes, 6, 1); // One nullable SubClassSet slot.
    writeU16Test(&context_bytes, 8, 0);
    writeCoverage1(&context_bytes, 12, 5);
    writeClassDef1(&context_bytes, 18, 5, 0);

    var table = Table{ .data = &context_bytes, .offset = 0, .length = context_bytes.len };
    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.context.validate(
            ContextualRecordExecutor,
            table,
            0,
        ),
    );

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    try std.testing.expectError(error.BadGsub, contextual_context.subtable(ContextualRecordExecutor, table, 0, &glyphs, allocator, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);

    writeU16Test(&context_bytes, 4, 18);
    try validation.contextual.context.validate(
        ContextualRecordExecutor,
        table,
        0,
    );
    try contextual_context.subtable(ContextualRecordExecutor, table, 0, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);

    var chaining_bytes = [_]u8{0} ** 46;
    writeU16Test(&chaining_bytes, 0, 2); // ChainingContextSubst format 2.
    writeU16Test(&chaining_bytes, 2, 16); // Coverage.
    writeU16Test(&chaining_bytes, 4, 22); // BacktrackClassDef.
    writeU16Test(&chaining_bytes, 6, 30); // InputClassDef.
    writeU16Test(&chaining_bytes, 8, 38); // LookaheadClassDef.
    writeU16Test(&chaining_bytes, 10, 1); // One nullable ChainSubClassSet slot.
    writeU16Test(&chaining_bytes, 12, 0);
    writeCoverage1(&chaining_bytes, 16, 5);
    writeClassDef1(&chaining_bytes, 22, 0, 0);
    writeClassDef1(&chaining_bytes, 30, 5, 0);
    writeClassDef1(&chaining_bytes, 38, 0, 0);

    table = .{ .data = &chaining_bytes, .offset = 0, .length = chaining_bytes.len };
    try validation.contextual.chaining.validate(
        ContextualRecordExecutor,
        table,
        0,
        .strict,
    );

    writeU16Test(&chaining_bytes, 4, 0);
    try validation.contextual.chaining.validate(
        ContextualRecordExecutor,
        table,
        0,
        .strict,
    );
    try contextual_chaining_class.subtable(
        ContextualRecordExecutor,
        table,
        0,
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
    writeU16Test(&chaining_bytes, 4, 22);

    writeU16Test(&chaining_bytes, 6, 0);
    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.chaining.validate(
            ContextualRecordExecutor,
            table,
            0,
            .strict,
        ),
    );
    try std.testing.expectError(
        error.BadGsub,
        contextual_chaining_class.subtable(
            ContextualRecordExecutor,
            table,
            0,
            &glyphs,
            allocator,
            0,
            .{},
        ),
    );
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
    writeU16Test(&chaining_bytes, 6, 30);

    writeU16Test(&chaining_bytes, 8, 0);
    try validation.contextual.chaining.validate(
        ContextualRecordExecutor,
        table,
        0,
        .strict,
    );
    try contextual_chaining_class.subtable(
        ContextualRecordExecutor,
        table,
        0,
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
    writeU16Test(&chaining_bytes, 8, 38);

    try validation.contextual.chaining.validate(
        ContextualRecordExecutor,
        table,
        0,
        .strict,
    );
    try contextual_chaining_class.subtable(
        ContextualRecordExecutor,
        table,
        0,
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
}

test "GSUB accelerated context class matching keeps shorter rules at syllable end" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    // The accelerated matcher is tested directly, but nested substitution
    // records still resolve through a normal GSUB LookupList.
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeSingleDeltaLookup(&bytes, 14, 1, 10);

    const coverage = 40;
    writeCoverage1(&bytes, coverage, 1);
    const class_def = 46;
    writeU16Test(&bytes, class_def + 0, 1);
    writeU16Test(&bytes, class_def + 2, 1);
    writeU16Test(&bytes, class_def + 4, 3);
    writeU16Test(&bytes, class_def + 6, 3);
    writeU16Test(&bytes, class_def + 8, 1);
    writeU16Test(&bytes, class_def + 10, 5);
    const records = 60;
    writeU16Test(&bytes, records + 0, 0);
    writeU16Test(&bytes, records + 2, 0);

    const classes = [_]u16{
        1, 5, // Three-glyph rule after the first input.
        2,                                                  1, 5, // Four-glyph rule after the first input.
        accelerator_root.index.class_first.sorted_encoding, 1, 0,
    };
    const rules = [_]class_context.Rule{
        .{
            .class_set = 3,
            .input_count = 3,
            .lookahead_count = 0,
            .hash = class_context.sequenceHash(classes[0..2]),
            .order = 0,
            .lookup_index = 0,
            .classes_start = 0,
            .subst_count = 1,
            .records_offset = records,
        },
        .{
            .class_set = 3,
            .input_count = 4,
            .lookahead_count = 0,
            .hash = class_context.sequenceHash(classes[2..5]),
            .order = 1,
            .lookup_index = 0,
            .classes_start = 2,
            .subst_count = 1,
            .records_offset = records,
        },
    };
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = rules.len,
        .max_input_count = 4,
        .max_lookahead_count = 0,
    }};
    const subtable = ContextClassSubtableAccelerator{
        .first_index_start = 5,
        .class_def = class_def,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3, 9 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3 });
    const source_byte_starts = [_]usize{ 0, 1, 2, 3 };
    const source_syllables = [_]u8{ 1, 1, 1, 2 };
    var source_boundaries = cluster_safety.SourceBoundaries{};
    defer source_boundaries.deinit(allocator);
    source_boundaries.reset(0, 4, &source_byte_starts);

    const result = try contextual_context.acceleratedClassAt(
        ContextualRecordExecutor,
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_boundaries = &source_boundaries,
            .source_syllables = &source_syllables,
            .match_source_syllable = true,
        },
    );

    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.next_pos);
    try std.testing.expectEqualSlices(GlyphId, &.{ 11, 2, 3, 9 }, glyphs.items);
    try std.testing.expect(!source_boundaries.isUnsafeBeforeByte(0));
    try std.testing.expect(source_boundaries.isUnsafeBeforeByte(1));
    try std.testing.expect(source_boundaries.isUnsafeBeforeByte(2));
    try std.testing.expect(!source_boundaries.isUnsafeBeforeByte(3));
}

test "GSUB MultipleSubst rejects null Sequence offsets" {
    var bytes = [_]u8{0} ** 44;
    const subtable = writeSingleLookupGsubTest(&bytes, 2);
    writeU16Test(&bytes, subtable + 0, 1); // MultipleSubst format 1.
    writeU16Test(&bytes, subtable + 2, 8); // Coverage after SequenceOffset array.
    writeU16Test(&bytes, subtable + 4, 1); // One SequenceOffset.
    writeU16Test(&bytes, subtable + 6, 0); // Invalid: Sequence offsets are not nullable.
    writeCoverage1(&bytes, subtable + 8, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, validation.direct.set_sequence.multiple(table, subtable));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, direct_multiple.subtable(table, subtable, &glyphs, std.testing.allocator, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // An empty Sequence can still be represented explicitly; only the child
    // pointer itself is required to name a real Sequence table.
    writeU16Test(&bytes, subtable + 6, 14);
    writeU16Test(&bytes, subtable + 14, 0); // Sequence.GlyphCount.
    try validation.direct.set_sequence.multiple(table, subtable);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GSUB AlternateSubst rejects null AlternateSet offsets" {
    var bytes = [_]u8{0} ** 44;
    const subtable = writeSingleLookupGsubTest(&bytes, 3);
    writeU16Test(&bytes, subtable + 0, 1); // AlternateSubst format 1.
    writeU16Test(&bytes, subtable + 2, 8); // Coverage after AlternateSetOffset array.
    writeU16Test(&bytes, subtable + 4, 1); // One AlternateSetOffset.
    writeU16Test(&bytes, subtable + 6, 0); // Invalid: AlternateSet offsets are not nullable.
    writeCoverage1(&bytes, subtable + 8, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, validation.direct.set_sequence.alternate(table, subtable));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, direct_alternate.subtable(table, subtable, &glyphs, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // A real AlternateSet may still be empty and produce no substitution; only
    // the child pointer itself is required to name an actual AlternateSet.
    writeU16Test(&bytes, subtable + 6, 14);
    writeU16Test(&bytes, subtable + 14, 0); // AlternateSet.GlyphCount.
    try validation.direct.set_sequence.alternate(table, subtable);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GSUB LigatureSubst rejects null required offsets" {
    {
        var bytes = [_]u8{0} ** 44;
        const subtable = writeSingleLookupGsubTest(&bytes, 4);
        writeU16Test(&bytes, subtable + 0, 1); // LigatureSubst format 1.
        writeU16Test(&bytes, subtable + 2, 8); // Coverage after LigatureSetOffset array.
        writeU16Test(&bytes, subtable + 4, 1); // One covered first glyph.
        writeU16Test(&bytes, subtable + 6, 0); // Invalid: LigatureSet offsets are not nullable.
        writeCoverage1(&bytes, subtable + 8, 1);

        const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
        try std.testing.expectError(error.BadGsub, validation.direct.ligature.validate(table, subtable, .strict));
        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

        var glyphs = std.ArrayList(GlyphId).empty;
        defer glyphs.deinit(std.testing.allocator);
        try glyphs.append(std.testing.allocator, 1);
        try glyphs.append(std.testing.allocator, 2);
        try direct_ligature.subtable(table, subtable, &glyphs, std.testing.allocator, 0, .{});
        try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
        try std.testing.expectEqual(null, try contextual_nested.direct.ligature(table, subtable, &glyphs, 0, std.testing.allocator, 0, .{}));
        try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);

        // A present but empty LigatureSet is still structurally valid; only the
        // offset itself is required to name a real child table.
        writeU16Test(&bytes, subtable + 6, 14);
        writeU16Test(&bytes, subtable + 14, 0); // LigatureSet.LigatureCount.
        try validation.direct.ligature.validate(table, subtable, .strict);
        try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    }

    {
        var bytes = [_]u8{0} ** 44;
        const subtable = writeSingleLookupGsubTest(&bytes, 4);
        writeU16Test(&bytes, subtable + 0, 1); // LigatureSubst format 1.
        writeU16Test(&bytes, subtable + 2, 12); // Coverage after the LigatureSet.
        writeU16Test(&bytes, subtable + 4, 1);
        writeU16Test(&bytes, subtable + 6, 8); // Non-null LigatureSet.
        const ligature_set = subtable + 8;
        writeU16Test(&bytes, ligature_set + 0, 1); // One Ligature offset follows.
        writeU16Test(&bytes, ligature_set + 2, 0); // Invalid: Ligature offsets are not nullable.
        writeCoverage1(&bytes, subtable + 12, 1);

        const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
        try std.testing.expectError(error.BadGsub, validation.direct.ligature.validate(table, subtable, .strict));
        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

        var glyphs = std.ArrayList(GlyphId).empty;
        defer glyphs.deinit(std.testing.allocator);
        try glyphs.append(std.testing.allocator, 1);
        try glyphs.append(std.testing.allocator, 2);
        try direct_ligature.subtable(table, subtable, &glyphs, std.testing.allocator, 0, .{});
        try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
        try std.testing.expectEqual(null, try contextual_nested.direct.ligature(table, subtable, &glyphs, 0, std.testing.allocator, 0, .{}));
        try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
    }
}

test "GSUB glyph ids are validated against maxp glyph count" {
    const max_glyphs: u16 = 3;

    {
        var bytes = [_]u8{0} ** 38;
        const subtable = writeSingleLookupGsubTest(&bytes, 1);
        writeU16Test(&bytes, subtable + 0, 1); // SingleSubst format 1.
        writeU16Test(&bytes, subtable + 2, 6);
        writeI16Test(&bytes, subtable + 4, 0);
        writeCoverage1(&bytes, subtable + 6, 3); // Invalid Coverage glyph.

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
    }

    {
        var bytes = [_]u8{0} ** 38;
        const subtable = writeSingleLookupGsubTest(&bytes, 1);
        writeU16Test(&bytes, subtable + 0, 1); // SingleSubst format 1.
        writeU16Test(&bytes, subtable + 2, 6);
        writeI16Test(&bytes, subtable + 4, 0x7fff);
        writeCoverage1(&bytes, subtable + 6, 1);

        // Delta results use the full 16-bit glyph-id domain and may be
        // transient inputs to a later lookup. Only the covered source glyph
        // must be renderable at this validation boundary.
        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
        try validateGlyphBoundsForShaping(&bytes, 0, bytes.len, max_glyphs);
    }

    {
        var bytes = [_]u8{0} ** 42;
        const subtable = writeSingleLookupGsubTest(&bytes, 1);
        writeU16Test(&bytes, subtable + 0, 2); // SingleSubst format 2.
        writeU16Test(&bytes, subtable + 2, 10);
        writeU16Test(&bytes, subtable + 4, 1);
        writeU16Test(&bytes, subtable + 6, 3); // Invalid substitute glyph.
        writeCoverage1(&bytes, subtable + 10, 1);

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
    }

    {
        var bytes = [_]u8{0} ** 46;
        const subtable = writeSingleLookupGsubTest(&bytes, 2);
        writeU16Test(&bytes, subtable + 0, 1);
        writeU16Test(&bytes, subtable + 2, 14);
        writeU16Test(&bytes, subtable + 4, 1);
        writeU16Test(&bytes, subtable + 6, 8);
        writeU16Test(&bytes, subtable + 8, 2);
        writeU16Test(&bytes, subtable + 10, 1);
        writeU16Test(&bytes, subtable + 12, 3); // Invalid MultipleSubst sequence glyph.
        writeCoverage1(&bytes, subtable + 14, 1);

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
    }

    {
        var bytes = [_]u8{0} ** 46;
        const subtable = writeSingleLookupGsubTest(&bytes, 3);
        writeU16Test(&bytes, subtable + 0, 1);
        writeU16Test(&bytes, subtable + 2, 14);
        writeU16Test(&bytes, subtable + 4, 1);
        writeU16Test(&bytes, subtable + 6, 8);
        writeU16Test(&bytes, subtable + 8, 2);
        writeU16Test(&bytes, subtable + 10, 2);
        writeU16Test(&bytes, subtable + 12, 3); // Invalid alternate glyph.
        writeCoverage1(&bytes, subtable + 14, 1);

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
    }

    {
        var bytes = [_]u8{0} ** 50;
        const subtable = writeSingleLookupGsubTest(&bytes, 4);
        writeU16Test(&bytes, subtable + 0, 1);
        writeU16Test(&bytes, subtable + 2, 18);
        writeU16Test(&bytes, subtable + 4, 1);
        writeU16Test(&bytes, subtable + 6, 8);
        writeU16Test(&bytes, subtable + 8, 1);
        writeU16Test(&bytes, subtable + 10, 4);
        writeU16Test(&bytes, subtable + 12, 2);
        writeU16Test(&bytes, subtable + 14, 2);
        writeU16Test(&bytes, subtable + 16, 3); // Invalid ligature component glyph.
        writeCoverage1(&bytes, subtable + 18, 1);

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
    }

    {
        var bytes = [_]u8{0} ** 48;
        const subtable = writeSingleLookupGsubTest(&bytes, 5);
        writeU16Test(&bytes, subtable + 0, 2); // ContextSubst format 2.
        writeU16Test(&bytes, subtable + 2, 8);
        writeU16Test(&bytes, subtable + 4, 14);
        writeU16Test(&bytes, subtable + 6, 0);
        writeCoverage1(&bytes, subtable + 8, 1);
        writeU16Test(&bytes, subtable + 14, 1); // ClassDef format 1.
        writeU16Test(&bytes, subtable + 16, 3); // Invalid ClassDef glyph range start.
        writeU16Test(&bytes, subtable + 18, 1);
        writeU16Test(&bytes, subtable + 20, 1);

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
    }

    {
        var bytes = [_]u8{0} ** 44;
        const subtable = writeSingleLookupGsubTest(&bytes, 8);
        writeU16Test(&bytes, subtable + 0, 1);
        writeU16Test(&bytes, subtable + 2, 12);
        writeU16Test(&bytes, subtable + 4, 0);
        writeU16Test(&bytes, subtable + 6, 0);
        writeU16Test(&bytes, subtable + 8, 1);
        writeU16Test(&bytes, subtable + 10, 3); // Invalid ReverseChainSingle substitute.
        writeCoverage1(&bytes, subtable + 12, 1);

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, max_glyphs));
    }
}

test "GSUB validates coverage indexes against substitution arrays" {
    {
        var bytes = [_]u8{0} ** 44;
        const subtable = writeSingleLookupGsubTest(&bytes, 1);
        writeU16Test(&bytes, subtable + 0, 2); // SingleSubst format 2.
        writeU16Test(&bytes, subtable + 2, 10);
        writeU16Test(&bytes, subtable + 4, 1); // One substitute for two covered glyphs.
        writeU16Test(&bytes, subtable + 6, 2);
        writeCoverage1List(&bytes, subtable + 10, &.{ 1, 2 });

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    }

    {
        var bytes = [_]u8{0} ** 46;
        const subtable = writeSingleLookupGsubTest(&bytes, 2);
        writeU16Test(&bytes, subtable + 0, 1);
        writeU16Test(&bytes, subtable + 2, 12);
        writeU16Test(&bytes, subtable + 4, 1); // One Sequence offset for two covered glyphs.
        writeU16Test(&bytes, subtable + 6, 8);
        const sequence = subtable + 8;
        writeU16Test(&bytes, sequence + 0, 1);
        writeU16Test(&bytes, sequence + 2, 2);
        writeCoverage1List(&bytes, subtable + 12, &.{ 1, 2 });

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    }

    {
        var bytes = [_]u8{0} ** 46;
        const subtable = writeSingleLookupGsubTest(&bytes, 3);
        writeU16Test(&bytes, subtable + 0, 1);
        writeU16Test(&bytes, subtable + 2, 12);
        writeU16Test(&bytes, subtable + 4, 1); // One AlternateSet offset for two covered glyphs.
        writeU16Test(&bytes, subtable + 6, 8);
        const alternate_set = subtable + 8;
        writeU16Test(&bytes, alternate_set + 0, 1);
        writeU16Test(&bytes, alternate_set + 2, 2);
        writeCoverage1List(&bytes, subtable + 12, &.{ 1, 2 });

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    }

    {
        var bytes = [_]u8{0} ** 50;
        const subtable = writeSingleLookupGsubTest(&bytes, 4);
        writeU16Test(&bytes, subtable + 0, 1);
        writeU16Test(&bytes, subtable + 2, 16);
        writeU16Test(&bytes, subtable + 4, 1); // One LigatureSet offset for two covered first glyphs.
        writeU16Test(&bytes, subtable + 6, 8);
        const lig_set = subtable + 8;
        writeU16Test(&bytes, lig_set + 0, 1);
        writeU16Test(&bytes, lig_set + 2, 4);
        const ligature = lig_set + 4;
        writeU16Test(&bytes, ligature + 0, 2);
        writeU16Test(&bytes, ligature + 2, 1);
        writeCoverage1List(&bytes, subtable + 16, &.{ 1, 2 });

        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    }
}

test "GSUB lookup selection honors script and language tags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 160;
    writeScriptLanguageSelectionTable(&bytes);
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var latin = try selectedLookupIndices(table, allocator, .{ .script_tag = .latn });
    defer latin.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{0}, latin.items);

    var han_default = try selectedLookupIndices(table, allocator, .{ .script_tag = .hani });
    defer han_default.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{1}, han_default.items);

    var han_japanese = try selectedLookupIndices(table, allocator, .{ .script_tag = .hani, .language_tag = .jan });
    defer han_japanese.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{2}, han_japanese.items);

    var fallback = try selectedLookupIndices(table, allocator, .{ .script_tag = .arab });
    defer fallback.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{3}, fallback.items);
}

test "vertical GSUB globally searches vert outside the active LangSys" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 84;
    writeGlobalVerticalFeatureSelectionTable(&bytes);
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var horizontal = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer horizontal.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), horizontal.items.len);

    var vertical = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        .vertical = true,
    });
    defer vertical.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{0}, vertical.items);

    var disabled = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        .vertical = true,
        .features = &.{.{ .tag = unicode.tag("vert"), .enabled = false }},
    });
    defer disabled.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), disabled.items.len);
}

test "GSUB validates layout tag record ordering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 92;
    writeLayoutTagOrderingTable(&bytes);
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    var selected = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer selected.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), selected.items.len);

    writeU32Test(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    var duplicate = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer duplicate.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), duplicate.items.len);

    writeU32Test(&bytes, 18, unicode.tag("AAAA"));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGsub, selectedLookupIndices(table, allocator, .{ .script_tag = .dflt }));
    writeU32Test(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));

    writeU32Test(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.ara));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    writeU32Test(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.kor));

    writeU32Test(&bytes, 76, unicode.tag("aalt"));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GSUB source-scoped feature gates substitution starts" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 68;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // ScriptList.
    writeU16Test(&bytes, 6, 30); // FeatureList.
    writeU16Test(&bytes, 8, 44); // LookupList.

    writeU16Test(&bytes, 10, 1); // ScriptCount.
    writeU32Test(&bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.arab));
    writeU16Test(&bytes, 16, 8); // Script table at 18.
    writeU16Test(&bytes, 18, 4); // DefaultLangSys at 22.
    writeU16Test(&bytes, 20, 0); // LangSysCount.
    writeU16Test(&bytes, 22, 0); // LookupOrder.
    writeU16Test(&bytes, 24, 0xffff); // No required feature.
    writeU16Test(&bytes, 26, 1);
    writeU16Test(&bytes, 28, 0); // Feature index 0.

    writeU16Test(&bytes, 30, 1); // FeatureCount.
    writeU32Test(&bytes, 32, unicode.tag("init"));
    writeU16Test(&bytes, 36, 8); // Feature table at 38.
    writeU16Test(&bytes, 38, 0); // FeatureParams.
    writeU16Test(&bytes, 40, 1);
    writeU16Test(&bytes, 42, 0); // Lookup index 0.

    writeU16Test(&bytes, 44, 1); // LookupCount.
    writeU16Test(&bytes, 46, 4); // Lookup at 48.
    writeU16Test(&bytes, 48, 1); // SingleSubst.
    writeU16Test(&bytes, 50, 0);
    writeU16Test(&bytes, 52, 1);
    writeU16Test(&bytes, 54, 8); // Subtable at 56.
    writeU16Test(&bytes, 56, 1); // SingleSubst format 1.
    writeU16Test(&bytes, 58, 6); // Coverage at 62.
    writeI16Test(&bytes, 60, 1); // 1 -> 2.
    writeCoverage1(&bytes, 62, 1);

    var scoped = std.ArrayList(GlyphId).empty;
    defer scoped.deinit(allocator);
    try scoped.appendSlice(allocator, &.{ 1, 1, 1 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    const source_features = [_]u32{ 0, unicode.tag("init"), 0 };
    try applySourceFeatureWithOptions(&bytes, 0, bytes.len, unicode.tag("init"), &scoped, allocator, .{
        .script_tag = .arab,
        .glyph_source_indices = &sources,
        .source_features = &source_features,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 1 }, scoped.items);

    var global = std.ArrayList(GlyphId).empty;
    defer global.deinit(allocator);
    try global.appendSlice(allocator, &.{ 1, 1, 1 });
    try applyFeatureWithOptions(&bytes, 0, bytes.len, unicode.tag("init"), &global, allocator, .{
        .script_tag = .arab,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 2, 2 }, global.items);
}

test "GSUB source feature masks ignore the shared marker bit" {
    const features = [_]u32{sourceFeatureMaskForTag(unicode.tag("blwf")).?};
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.append(std.testing.allocator, 0);

    try std.testing.expect(runtime_filtering.sourceFeatureAllowsGlyph(.{
        .glyph_source_indices = &sources,
        .source_features = &features,
        .active_source_feature = unicode.tag("blwf"),
    }, 0));
    try std.testing.expect(!runtime_filtering.sourceFeatureAllowsGlyph(.{
        .glyph_source_indices = &sources,
        .source_features = &features,
        .active_source_feature = unicode.tag("rphf"),
    }, 0));
}

test "GSUB source-scoped feature gates multiple substitutions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 78;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // ScriptList.
    writeU16Test(&bytes, 6, 30); // FeatureList.
    writeU16Test(&bytes, 8, 44); // LookupList.

    writeU16Test(&bytes, 10, 1);
    writeU32Test(&bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.arab));
    writeU16Test(&bytes, 16, 8);
    writeU16Test(&bytes, 18, 4);
    writeU16Test(&bytes, 20, 0);
    writeU16Test(&bytes, 22, 0);
    writeU16Test(&bytes, 24, 0xffff);
    writeU16Test(&bytes, 26, 1);
    writeU16Test(&bytes, 28, 0);

    writeU16Test(&bytes, 30, 1);
    writeU32Test(&bytes, 32, unicode.tag("fina"));
    writeU16Test(&bytes, 36, 8);
    writeU16Test(&bytes, 38, 0);
    writeU16Test(&bytes, 40, 1);
    writeU16Test(&bytes, 42, 0);

    writeU16Test(&bytes, 44, 1);
    writeU16Test(&bytes, 46, 4);
    writeU16Test(&bytes, 48, 2); // MultipleSubst.
    writeU16Test(&bytes, 50, 0);
    writeU16Test(&bytes, 52, 1);
    writeU16Test(&bytes, 54, 8);
    const subtable = 56;
    writeU16Test(&bytes, subtable + 0, 1);
    writeU16Test(&bytes, subtable + 2, 8); // Coverage at 64.
    writeU16Test(&bytes, subtable + 4, 1);
    writeU16Test(&bytes, subtable + 6, 14); // Sequence at 70.
    writeCoverage1(&bytes, 64, 1);
    writeU16Test(&bytes, 70, 2);
    writeU16Test(&bytes, 72, 2);
    writeU16Test(&bytes, 74, 3);

    var scoped = std.ArrayList(GlyphId).empty;
    defer scoped.deinit(allocator);
    try scoped.appendSlice(allocator, &.{ 1, 1, 1 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    const source_features = [_]u32{ 0, unicode.tag("fina"), 0 };
    try applySourceFeatureWithOptions(&bytes, 0, bytes.len, unicode.tag("fina"), &scoped, allocator, .{
        .script_tag = .arab,
        .glyph_source_indices = &sources,
        .source_features = &source_features,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 3, 1 }, scoped.items);
}

test "GSUB explicit feature sequence can chain Bengali half and pres ligatures" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 160;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // ScriptList.
    writeU16Test(&bytes, 6, 34); // FeatureList.
    writeU16Test(&bytes, 8, 62); // LookupList.

    writeU16Test(&bytes, 10, 1);
    writeU32Test(&bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.beng));
    writeU16Test(&bytes, 16, 8);
    writeU16Test(&bytes, 18, 4);
    writeU16Test(&bytes, 20, 0);
    writeU16Test(&bytes, 22, 0);
    writeU16Test(&bytes, 24, 0xffff);
    writeU16Test(&bytes, 26, 2);
    writeU16Test(&bytes, 28, 0);
    writeU16Test(&bytes, 30, 1);

    writeU16Test(&bytes, 34, 2);
    writeFeatureRecord(&bytes, 36, unicode.tag("half"), 14);
    writeFeatureRecord(&bytes, 42, unicode.tag("pres"), 20);
    writeFeature(&bytes, 48, 0);
    writeFeature(&bytes, 54, 1);

    writeU16Test(&bytes, 62, 2);
    writeU16Test(&bytes, 64, 6);
    writeU16Test(&bytes, 66, 58);
    writeLigatureLookupTest(&bytes, 68, 1, 2, 4);
    writeLigatureLookupTest(&bytes, 120, 4, 1, 6);

    var full = std.ArrayList(GlyphId).empty;
    defer full.deinit(allocator);
    try full.appendSlice(allocator, &.{ 1, 2, 1 });
    try applyWithOptions(&bytes, 0, bytes.len, &full, allocator, .{
        .script_tag = .beng,
        .features = &.{
            .{ .tag = unicode.tag("half"), .enabled = true },
            .{ .tag = unicode.tag("pres"), .enabled = true },
        },
    });
    try std.testing.expectEqualSlices(GlyphId, &.{6}, full.items);

    var staged = std.ArrayList(GlyphId).empty;
    defer staged.deinit(allocator);
    try staged.appendSlice(allocator, &.{ 1, 2, 1 });
    var staged_sources = std.ArrayList(usize).empty;
    defer staged_sources.deinit(allocator);
    try staged_sources.appendSlice(allocator, &.{ 0, 1, 2 });
    var staged_clusters = std.ArrayList(usize).empty;
    defer staged_clusters.deinit(allocator);
    try staged_clusters.appendSlice(allocator, &.{ 0, 0, 0 });
    const staged_syllables = [_]u8{ 1, 1, 1 };
    const staged_features = [_]u32{ sourceFeatureMaskForTag(unicode.tag("half")).?, 0, 0 };
    try applyFeatureSequenceWithOptions(&bytes, 0, bytes.len, &.{
        .{ .tag = unicode.tag("half"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
        .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    }, &staged, allocator, .{
        .script_tag = .beng,
        .glyph_source_indices = &staged_sources,
        .glyph_cluster_indices = &staged_clusters,
        .source_features = &staged_features,
        .source_syllables = &staged_syllables,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{6}, staged.items);
}

test "GSUB LangSys required feature bypasses optional feature filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;
    writeRequiredFeatureSelectionTable(&bytes, unicode.tag("ordn"), unicode.tag("liga"));
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var lookups = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        // Even an explicit off override must not disable ReqFeatureIndex. It
        // only disables the ordinary feature listed after it in FeatureIndex[].
        .features = &.{
            .{ .tag = unicode.tag("ordn"), .enabled = false },
            .{ .tag = unicode.tag("liga"), .enabled = false },
        },
    });
    defer lookups.deinit(allocator);

    try std.testing.expectEqualSlices(u16, &.{0}, lookups.items);
}

test "GSUB lookup selection sorts and deduplicates repeated feature lookups" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 78;
    writeRepeatedLookupSelectionTable(&bytes, unicode.tag("liga"));
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var lookups = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer lookups.deinit(allocator);

    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, lookups.items);
}

test "GSUB cached lookup executor requires an exact nonempty plan" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    writeCachedSingleFeatureGsubTest(&bytes);

    const accelerators = try accelerator_root.build.lookup.build(&bytes, 0, bytes.len, allocator);
    defer deinitLookupAccelerators(allocator, accelerators);
    var operations_left: usize = 64;
    const options = LookupOptions{
        .selected_lookups = &.{0},
        .lookup_accelerators = accelerators,
        .operations_left = &operations_left,
        .max_glyph_count = 64,
        .assume_validated = true,
    };

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);
    try std.testing.expect(try applyCachedLookupSelectionWithOptionsAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &glyphs,
        allocator,
        options,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{11}, glyphs.items);

    // Empty selections retain the generic executor's FeatureList/topology
    // semantics. A copied table, a selection outside the exact accelerator,
    // or a caller without the shared shaping budget must also decline before
    // changing the run.
    glyphs.items[0] = 10;
    var empty_options = options;
    empty_options.selected_lookups = &.{};
    try std.testing.expect(!try applyCachedLookupSelectionWithOptionsAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &glyphs,
        allocator,
        empty_options,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);

    var foreign_bytes = bytes;
    try std.testing.expect(!try applyCachedLookupSelectionWithOptionsAfterMetadataProof(
        &foreign_bytes,
        0,
        foreign_bytes.len,
        &glyphs,
        allocator,
        options,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);

    const copied_accelerators = try allocator.dupe(LookupAccelerator, accelerators);
    defer allocator.free(copied_accelerators);
    var copied_options = options;
    copied_options.lookup_accelerators = copied_accelerators;
    try std.testing.expect(!try applyCachedLookupSelectionWithOptionsAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &glyphs,
        allocator,
        copied_options,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);

    var invalid_selection_options = options;
    // The valid first index must not run before the invalid second index is
    // rejected; fallback is safe only while the complete cached selection is
    // known to be non-mutating on failure.
    invalid_selection_options.selected_lookups = &.{ 0, 1 };
    try std.testing.expect(!try applyCachedLookupSelectionWithOptionsAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &glyphs,
        allocator,
        invalid_selection_options,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);

    var unbounded_options = options;
    unbounded_options.operations_left = null;
    try std.testing.expect(!try applyCachedLookupSelectionWithOptionsAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &glyphs,
        allocator,
        unbounded_options,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);
}

test "GSUB chaining class substitution applies nested lookup" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, 112);
    defer allocator.free(bytes);
    @memset(bytes, 0);

    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 8, 10);
    writeU16Test(bytes, 10, 2);
    writeU16Test(bytes, 12, 6);
    writeU16Test(bytes, 14, 82);

    writeU16Test(bytes, 16, 6);
    writeU16Test(bytes, 20, 1);
    writeU16Test(bytes, 22, 8);

    const chain = 24;
    writeU16Test(bytes, chain + 0, 2);
    writeU16Test(bytes, chain + 2, 38);
    writeU16Test(bytes, chain + 4, 44);
    writeU16Test(bytes, chain + 6, 52);
    writeU16Test(bytes, chain + 8, 60);
    writeU16Test(bytes, chain + 10, 2);
    writeU16Test(bytes, chain + 14, 16);

    const set = chain + 16;
    writeU16Test(bytes, set + 0, 1);
    writeU16Test(bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(bytes, rule + 0, 1);
    writeU16Test(bytes, rule + 2, 1);
    writeU16Test(bytes, rule + 4, 1);
    writeU16Test(bytes, rule + 6, 1);
    writeU16Test(bytes, rule + 8, 1);
    writeU16Test(bytes, rule + 10, 1);
    writeU16Test(bytes, rule + 12, 0);
    writeU16Test(bytes, rule + 14, 1);

    writeCoverage1(bytes, chain + 38, 1);
    writeClassDef1(bytes, chain + 44, 1, 1);
    writeClassDef1(bytes, chain + 52, 1, 1);
    writeClassDef1(bytes, chain + 60, 1, 1);

    writeSingleDeltaLookup(bytes, 92, 1, 2);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
    try applyLookup(.{ .data = bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 1 }, glyphs.items);
}

test "GSUB chaining coverage substitution applies nested lookup" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, 82);
    defer allocator.free(bytes);
    @memset(bytes, 0);

    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 8, 10);
    writeU16Test(bytes, 10, 2);
    writeU16Test(bytes, 12, 6);
    writeU16Test(bytes, 14, 52);

    writeU16Test(bytes, 16, 6);
    writeU16Test(bytes, 20, 1);
    writeU16Test(bytes, 22, 8);

    const chain = 24;
    writeU16Test(bytes, chain + 0, 3);
    writeU16Test(bytes, chain + 2, 1);
    writeU16Test(bytes, chain + 4, 20);
    writeU16Test(bytes, chain + 6, 1);
    writeU16Test(bytes, chain + 8, 26);
    writeU16Test(bytes, chain + 10, 1);
    writeU16Test(bytes, chain + 12, 32);
    writeU16Test(bytes, chain + 14, 1);
    writeU16Test(bytes, chain + 16, 0);
    writeU16Test(bytes, chain + 18, 1);
    writeCoverage1(bytes, chain + 20, 1);
    writeCoverage1(bytes, chain + 26, 1);
    writeCoverage1(bytes, chain + 32, 1);

    writeSingleDeltaLookup(bytes, 62, 1, 2);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
    try applyLookup(.{ .data = bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 1 }, glyphs.items);
}

test "GSUB source syllable matching blocks cross-syllable chaining context" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, 82);
    defer allocator.free(bytes);
    @memset(bytes, 0);

    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 8, 10);
    writeU16Test(bytes, 10, 2);
    writeU16Test(bytes, 12, 6);
    writeU16Test(bytes, 14, 52);

    writeU16Test(bytes, 16, 6);
    writeU16Test(bytes, 20, 1);
    writeU16Test(bytes, 22, 8);

    const chain = 24;
    writeU16Test(bytes, chain + 0, 3);
    writeU16Test(bytes, chain + 2, 1);
    writeU16Test(bytes, chain + 4, 20);
    writeU16Test(bytes, chain + 6, 1);
    writeU16Test(bytes, chain + 8, 26);
    writeU16Test(bytes, chain + 10, 1);
    writeU16Test(bytes, chain + 12, 32);
    writeU16Test(bytes, chain + 14, 1);
    writeU16Test(bytes, chain + 16, 0);
    writeU16Test(bytes, chain + 18, 1);
    writeCoverage1(bytes, chain + 20, 1);
    writeCoverage1(bytes, chain + 26, 1);
    writeCoverage1(bytes, chain + 32, 1);

    writeSingleDeltaLookup(bytes, 62, 1, 2);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    const source_syllables = [_]u8{ 1, 2, 2 };

    try applyLookup(.{ .data = bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{
        .glyph_source_indices = &sources,
        .source_syllables = &source_syllables,
        .match_source_syllable = true,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 1, 1 }, glyphs.items);
}

test "GSUB chaining coverage lookup tries subtables per position" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 150;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3); // LookupCount.
    writeU16Test(&bytes, 12, 10); // ChainingContext lookup at 20.
    writeU16Test(&bytes, 14, 90); // SingleSubst lookup at 100.
    writeU16Test(&bytes, 16, 114); // SingleSubst lookup at 124.

    writeU16Test(&bytes, 20, 6);
    writeU16Test(&bytes, 22, 0);
    writeU16Test(&bytes, 24, 2);
    writeU16Test(&bytes, 26, 10);
    writeU16Test(&bytes, 28, 48);

    const first_chain = 30;
    writeU16Test(&bytes, first_chain + 0, 3);
    writeU16Test(&bytes, first_chain + 2, 0);
    writeU16Test(&bytes, first_chain + 4, 2);
    writeU16Test(&bytes, first_chain + 6, 18);
    writeU16Test(&bytes, first_chain + 8, 24);
    writeU16Test(&bytes, first_chain + 10, 0);
    writeU16Test(&bytes, first_chain + 12, 1);
    writeU16Test(&bytes, first_chain + 14, 0);
    writeU16Test(&bytes, first_chain + 16, 1);
    writeCoverage1(&bytes, first_chain + 18, 1);
    writeCoverage1(&bytes, first_chain + 24, 1);

    const second_chain = 68;
    writeU16Test(&bytes, second_chain + 0, 3);
    writeU16Test(&bytes, second_chain + 2, 0);
    writeU16Test(&bytes, second_chain + 4, 2);
    writeU16Test(&bytes, second_chain + 6, 18);
    writeU16Test(&bytes, second_chain + 8, 24);
    writeU16Test(&bytes, second_chain + 10, 0);
    writeU16Test(&bytes, second_chain + 12, 1);
    writeU16Test(&bytes, second_chain + 14, 0);
    writeU16Test(&bytes, second_chain + 16, 2);
    writeCoverage1(&bytes, second_chain + 18, 1);
    writeCoverage1(&bytes, second_chain + 24, 2);

    writeSingleDeltaLookup(&bytes, 100, 1, 1); // 1 -> 2.
    writeSingleDeltaLookup(&bytes, 124, 1, 2); // 1 -> 3.

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 1 });
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 20, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1 }, glyphs.items);

    glyphs.clearRetainingCapacity();
    try glyphs.appendSlice(allocator, &.{ 99, 1, 1 });
    const accelerators = try accelerator_root.build.lookup.build(&bytes, 0, bytes.len, allocator);
    defer deinitLookupAccelerators(allocator, accelerators);
    try std.testing.expect(!accelerators[0].chaining_input_digest.mayHave(99));
    try applyLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        20,
        0,
        &glyphs,
        allocator,
        .{ .lookup_accelerators = accelerators, .assume_validated = true },
        null,
    );

    // The lookup digest rejects the leading miss, while the following covered
    // position still tries ordered subtable alternatives and substitutes.
    try std.testing.expectEqualSlices(GlyphId, &.{ 99, 2, 1 }, glyphs.items);
}

test "GSUB chaining class lookup stops after the first matching subtable" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 180;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10); // LookupList.
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 12); // Chaining lookup at 20.
    writeU16Test(&bytes, 14, 122); // Identity SingleSubst at 130.
    writeU16Test(&bytes, 16, 146); // Visible SingleSubst at 154.

    writeU16Test(&bytes, 20, 6); // ChainingContextSubst.
    writeU16Test(&bytes, 24, 2);
    writeU16Test(&bytes, 26, 10); // First class subtable at 30.
    writeU16Test(&bytes, 28, 60); // Second class subtable at 80.

    for ([_]usize{ 30, 80 }, 0..) |chain, subtable_index| {
        writeU16Test(&bytes, chain + 0, 2);
        writeU16Test(&bytes, chain + 2, 34); // Coverage.
        writeU16Test(&bytes, chain + 4, 0); // No backtrack ClassDef.
        writeU16Test(&bytes, chain + 6, 40); // Input ClassDef.
        writeU16Test(&bytes, chain + 8, 0); // No lookahead ClassDef.
        writeU16Test(&bytes, chain + 10, 2); // ClassSetCount.
        writeU16Test(&bytes, chain + 12, 0);
        writeU16Test(&bytes, chain + 14, 16); // Class 1 set.

        const set = chain + 16;
        writeU16Test(&bytes, set + 0, 1);
        writeU16Test(&bytes, set + 2, 4);
        const rule = set + 4;
        writeU16Test(&bytes, rule + 0, 0); // BacktrackGlyphCount.
        writeU16Test(&bytes, rule + 2, 1); // InputGlyphCount.
        writeU16Test(&bytes, rule + 4, 0); // LookAheadGlyphCount.
        writeU16Test(&bytes, rule + 6, 1); // SubstCount.
        writeU16Test(&bytes, rule + 8, 0);
        writeU16Test(&bytes, rule + 10, @intCast(subtable_index + 1));

        writeCoverage1(&bytes, chain + 34, 1);
        writeClassDef1(&bytes, chain + 40, 1, 1);
    }

    // The first nested lookup deliberately substitutes glyph 1 with itself.
    // It still counts as a successful rule application and prevents the second
    // chaining subtable from applying its visible 1 -> 11 substitution at the
    // same position.
    writeSingleDeltaLookup(&bytes, 130, 1, 0);
    writeSingleDeltaLookup(&bytes, 154, 1, 10);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 20, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}

test "GSUB context substitution skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 18, 0x0008);
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
    writeSingleDeltaLookup(&bytes, 52, 2, 10);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 3, 2 });

    const glyph_classes = [_]u16{ 0, 0, 0, 3 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 12 }, glyphs.items);
}

test "GSUB direct context substitution preflights payload arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 110;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 60);

    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 20, 2);
    writeU16Test(&bytes, 22, 10);
    writeU16Test(&bytes, 24, 34);

    const first_context = 26;
    writeU16Test(&bytes, first_context + 0, 3);
    writeU16Test(&bytes, first_context + 2, 1);
    writeU16Test(&bytes, first_context + 4, 1);
    writeU16Test(&bytes, first_context + 6, 12);
    writeU16Test(&bytes, first_context + 8, 0);
    writeU16Test(&bytes, first_context + 10, 1);
    writeCoverage1(&bytes, first_context + 12, 10);

    const malformed_context = 50;
    writeU16Test(&bytes, malformed_context + 0, 3);
    writeU16Test(&bytes, malformed_context + 2, 1);
    writeU16Test(&bytes, malformed_context + 4, 0);
    writeU16Test(&bytes, malformed_context + 6, 10);
    const truncated_coverage = malformed_context + 10;
    writeU16Test(&bytes, truncated_coverage + 0, 1);
    writeU16Test(&bytes, truncated_coverage + 2, 54);
    writeU16Test(&bytes, truncated_coverage + 4, 30);
    // The second ContextSubst subtable declares a Coverage array that reaches
    // beyond table.length. Lookup preflight must reject the whole lookup before
    // the first subtable applies its nested SingleSubst.

    writeSingleDeltaLookup(&bytes, 70, 10, 5);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 30 });

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 30 }, glyphs.items);
}

test "GSUB direct chaining substitution preflights payload arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 62);

    writeU16Test(&bytes, 16, 6);
    writeU16Test(&bytes, 20, 2);
    writeU16Test(&bytes, 22, 10);
    writeU16Test(&bytes, 24, 36);

    const first_chain = 26;
    writeU16Test(&bytes, first_chain + 0, 3);
    writeU16Test(&bytes, first_chain + 2, 0);
    writeU16Test(&bytes, first_chain + 4, 1);
    writeU16Test(&bytes, first_chain + 6, 16);
    writeU16Test(&bytes, first_chain + 8, 0);
    writeU16Test(&bytes, first_chain + 10, 1);
    writeU16Test(&bytes, first_chain + 12, 0);
    writeU16Test(&bytes, first_chain + 14, 1);
    writeCoverage1(&bytes, first_chain + 16, 10);

    const malformed_chain = 52;
    writeU16Test(&bytes, malformed_chain + 0, 3);
    writeU16Test(&bytes, malformed_chain + 2, 0);
    writeU16Test(&bytes, malformed_chain + 4, 1);
    writeU16Test(&bytes, malformed_chain + 6, 16);
    writeU16Test(&bytes, malformed_chain + 8, 0);
    writeU16Test(&bytes, malformed_chain + 10, 0);
    const truncated_coverage = malformed_chain + 16;
    writeU16Test(&bytes, truncated_coverage + 0, 1);
    writeU16Test(&bytes, truncated_coverage + 2, 54);
    writeU16Test(&bytes, truncated_coverage + 4, 30);
    // ChainingSubst format 3 has three independent offset arrays. A malformed
    // later input coverage must be detected before an earlier subtable can run
    // the nested lookup and leave the caller with partial substitutions.

    writeSingleDeltaLookup(&bytes, 72, 10, 5);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 30 });

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 30 }, glyphs.items);
}

test "GSUB contextual record truncation is atomic" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 14);

    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 28);

    writeSingleDeltaLookup(&bytes, 24, 1, 9);

    const context = 44;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    // The second declared SequenceLookupRecord is beyond table.length below.

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = rule + 8 };
    try std.testing.expectError(error.BadGsub, applyLookup(table, 16, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}

test "GSUB contextual lookup preflight rejects later truncated lookup atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 5);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1(&bytes, context + 24, 1);

    writeSingleDeltaLookup(&bytes, 70, 1, 9);

    // Lookup 2 has a complete fixed header but declares one SubTable offset
    // beyond table.length. The contextual matcher must reject it before
    // applying lookup 1, otherwise glyph 1 would be partially substituted.
    writeU16Test(&bytes, 90, 1);
    writeU16Test(&bytes, 94, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}

test "GSUB contextual lookup preflight rejects missing nested mark filtering sets atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18); // Lookup 0: ContextSubst.
    writeU16Test(&bytes, 14, 60); // Lookup 1: valid SingleSubst.
    writeU16Test(&bytes, 16, 84); // Lookup 2: SingleSubst with a bad MarkFilteringSet index.

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 5);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);
    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1(&bytes, context + 24, 1);

    writeSingleDeltaLookup(&bytes, 70, 1, 9);

    const bad_lookup = 94;
    writeU16Test(&bytes, bad_lookup + 0, 1);
    writeU16Test(&bytes, bad_lookup + 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, bad_lookup + 4, 1);
    writeU16Test(&bytes, bad_lookup + 6, 10);
    writeU16Test(&bytes, bad_lookup + 8, 1); // Invalid: only set 0 is supplied below.
    const single = bad_lookup + 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 6);
    writeI16Test(&bytes, single + 4, 5);
    writeCoverage1(&bytes, single + 6, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);
    const mark_sets = [_][]const GlyphId{&.{1}};

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, allocator, .{
        .mark_filtering_sets = &mark_sets,
    }));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}

test "GSUB contextual lookup records reject dangling lookup indexes atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0: ContextSubst.
    writeU16Test(&bytes, 18, 50); // Lookup 1: SingleSubst.

    const context_lookup = 20;
    writeU16Test(&bytes, context_lookup + 0, 5);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2); // Dangling: LookupList has only 0 and 1.

    writeSingleDeltaLookup(&bytes, 64, 1, 9);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 20));
    try std.testing.expectError(error.BadGsub, applyLookup(table, context_lookup, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // Once every SequenceLookupRecord names an existing lookup, the same
    // contextual rule is structurally valid and the first nested SingleSubst
    // can run normally.
    writeU16Test(&bytes, rule + 10, 1);
    try validateGlyphBounds(&bytes, 0, bytes.len, 20);
    try applyLookup(table, context_lookup, &glyphs, allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);
}

test "GSUB contextual lookup records skip sequence indexes outside matched input" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 84;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0: ContextSubst.
    writeU16Test(&bytes, 18, 50); // Lookup 1: SingleSubst.

    const context_lookup = 20;
    writeU16Test(&bytes, context_lookup + 0, 5);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1); // One input glyph is matched.
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 1); // Invalid: only sequence index 0 exists.
    writeU16Test(&bytes, rule + 6, 1);

    writeSingleDeltaLookup(&bytes, 64, 1, 9);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try validateGlyphBounds(&bytes, 0, bytes.len, 20);
    try applyLookup(table, context_lookup, &glyphs, allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // With a valid SequenceIndex, the same context applies its nested lookup.
    writeU16Test(&bytes, rule + 4, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 20);
    try applyLookup(table, context_lookup, &glyphs, allocator, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);
}

test "GSUB contextual lookup preflight rejects nested extension payload atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 5);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1(&bytes, context + 24, 1);

    writeSingleDeltaLookup(&bytes, 70, 1, 9);

    writeU16Test(&bytes, 90, 7);
    writeU16Test(&bytes, 94, 1);
    writeU16Test(&bytes, 96, 8);
    const extension = 98;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    // The ExtensionSubst wrapper is complete, but its payload address falls
    // past table.length. The contextual preflight must catch that before the
    // earlier single-substitution record changes glyph 1 to glyph 10.
    writeU32Test(&bytes, extension + 4, 20);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}

test "GSUB extension single substitution preflights wrapped coverage arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 52;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 32);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 6);
    writeI16Test(&bytes, first_single + 4, 10);
    writeCoverage1(&bytes, first_single + 6, 10);

    const second_extension = 32;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 6);
    writeI16Test(&bytes, second_single + 4, 1);
    const truncated_coverage = second_single + 6;
    writeU16Test(&bytes, truncated_coverage + 0, 1);
    writeU16Test(&bytes, truncated_coverage + 2, 2);
    writeU16Test(&bytes, truncated_coverage + 4, 30);
    // Coverage declares two glyph ids but the second id falls beyond
    // table.length. The second wrapper would discover this only after the first
    // wrapper changed glyph 10 unless ExtensionSubst preflights wrapped arrays.

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 30 });

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 30 }, glyphs.items);
}

test "GSUB direct single substitution preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 36;

    writeU16Test(&bytes, 0, 1); // SingleSubst lookup.
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 24);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 6);
    writeI16Test(&bytes, first_single + 4, 10);
    writeCoverage1(&bytes, first_single + 6, 10);

    const second_single = 24;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 6);
    writeI16Test(&bytes, second_single + 4, 1);
    const truncated_coverage = second_single + 6;
    writeU16Test(&bytes, truncated_coverage + 0, 1);
    writeU16Test(&bytes, truncated_coverage + 2, 2);
    writeU16Test(&bytes, truncated_coverage + 4, 30);
    // The second subtable's Coverage declares a missing second glyph id. Lookup
    // preflight must reject it before the first subtable changes glyph 10.

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 30 });

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 30 }, glyphs.items);
}

test "GSUB extension multiple substitution preflights wrapped sequence arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 66;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 40);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_multiple = first_extension + 8;
    writeU16Test(&bytes, first_multiple + 0, 1);
    writeU16Test(&bytes, first_multiple + 2, 14);
    writeU16Test(&bytes, first_multiple + 4, 1);
    writeU16Test(&bytes, first_multiple + 6, 8);
    const first_sequence = first_multiple + 8;
    writeU16Test(&bytes, first_sequence + 0, 2);
    writeU16Test(&bytes, first_sequence + 2, 20);
    writeU16Test(&bytes, first_sequence + 4, 21);
    writeCoverage1(&bytes, first_multiple + 14, 10);

    const second_extension = 40;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_multiple = second_extension + 8;
    writeU16Test(&bytes, second_multiple + 0, 1);
    writeU16Test(&bytes, second_multiple + 2, 8);
    writeU16Test(&bytes, second_multiple + 4, 1);
    writeU16Test(&bytes, second_multiple + 6, 14);
    writeCoverage1(&bytes, second_multiple + 8, 30);
    const truncated_sequence = second_multiple + 14;
    writeU16Test(&bytes, truncated_sequence + 0, 2);
    writeU16Test(&bytes, truncated_sequence + 2, 31);
    // Sequence declares two replacements but only the first replacement is in
    // bounds. Reject the whole lookup before glyph 10 is expanded by wrapper 0.

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 30 });

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 30 }, glyphs.items);
}

test "GSUB mixed extension substitution preflights wrapped ligature arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 40);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 6);
    writeI16Test(&bytes, first_single + 4, 10);
    writeCoverage1(&bytes, first_single + 6, 10);

    const second_extension = 40;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 4);
    writeU32Test(&bytes, second_extension + 4, 8);
    const lig_subst = second_extension + 8;
    writeU16Test(&bytes, lig_subst + 0, 1);
    writeU16Test(&bytes, lig_subst + 2, 8);
    writeU16Test(&bytes, lig_subst + 4, 1);
    writeU16Test(&bytes, lig_subst + 6, 14);
    writeCoverage1(&bytes, lig_subst + 8, 30);
    const ligature_set = lig_subst + 14;
    writeU16Test(&bytes, ligature_set + 0, 1);
    writeU16Test(&bytes, ligature_set + 2, 4);
    const truncated_ligature = ligature_set + 4;
    writeU16Test(&bytes, truncated_ligature + 0, 40);
    writeU16Test(&bytes, truncated_ligature + 2, 3);
    writeU16Test(&bytes, truncated_ligature + 4, 31);
    // The ligature declares two component glyph ids after the first glyph, but
    // only one component id is present. This mixed-type ExtensionSubst lookup
    // uses the generic wrapper path, which must still preflight all payloads
    // before wrapper 0 mutates glyph 10.

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 30, 31, 32 });

    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 30, 31, 32 }, glyphs.items);
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

test "GSUB context coverage accelerator preserves order skips and cardinality changes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10); // LookupList.
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 8); // Context lookup at 18.
    writeU16Test(&bytes, 14, 74); // Multiple lookup at 84.
    writeU16Test(&bytes, 16, 106); // Single fallback lookup at 116.

    const context_lookup = 18;
    writeU16Test(&bytes, context_lookup + 0, 5);
    writeU16Test(&bytes, context_lookup + 2, 0x0008); // IgnoreMarks.
    writeU16Test(&bytes, context_lookup + 4, 2);
    writeU16Test(&bytes, context_lookup + 6, 10);
    writeU16Test(&bytes, context_lookup + 8, 38);

    // Both format-3 subtables match [1, 2]. The first expands glyph 2 and must
    // prevent the later fallback from changing glyph 1.
    const first_context = 28;
    writeU16Test(&bytes, first_context + 0, 3);
    writeU16Test(&bytes, first_context + 2, 2);
    writeU16Test(&bytes, first_context + 4, 1);
    writeU16Test(&bytes, first_context + 6, 16);
    writeU16Test(&bytes, first_context + 8, 22);
    writeU16Test(&bytes, first_context + 10, 1); // SequenceIndex 1.
    writeU16Test(&bytes, first_context + 12, 1); // Multiple lookup.
    writeCoverage1(&bytes, first_context + 16, 1);
    writeCoverage1(&bytes, first_context + 22, 2);

    const second_context = 56;
    writeU16Test(&bytes, second_context + 0, 3);
    writeU16Test(&bytes, second_context + 2, 2);
    writeU16Test(&bytes, second_context + 4, 1);
    writeU16Test(&bytes, second_context + 6, 16);
    writeU16Test(&bytes, second_context + 8, 22);
    writeU16Test(&bytes, second_context + 10, 0); // SequenceIndex 0.
    writeU16Test(&bytes, second_context + 12, 2); // Single fallback lookup.
    writeCoverage1(&bytes, second_context + 16, 1);
    writeCoverage1(&bytes, second_context + 22, 2);

    const multiple_lookup = 84;
    writeU16Test(&bytes, multiple_lookup + 0, 2);
    writeU16Test(&bytes, multiple_lookup + 2, 0);
    writeU16Test(&bytes, multiple_lookup + 4, 1);
    writeU16Test(&bytes, multiple_lookup + 6, 8);
    const multiple = 92;
    writeU16Test(&bytes, multiple + 0, 1);
    writeU16Test(&bytes, multiple + 2, 12);
    writeU16Test(&bytes, multiple + 4, 1);
    writeU16Test(&bytes, multiple + 6, 18);
    writeCoverage1(&bytes, multiple + 12, 2);
    writeU16Test(&bytes, multiple + 18, 2);
    writeU16Test(&bytes, multiple + 20, 20);
    writeU16Test(&bytes, multiple + 22, 21);

    writeSingleDeltaLookup(&bytes, 116, 1, 10);

    var glyph_classes = [_]u16{0} ** 22;
    glyph_classes[9] = 3;
    const options = LookupOptions{ .glyph_classes = &glyph_classes };
    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    var generic = std.ArrayList(GlyphId).empty;
    defer generic.deinit(allocator);
    try generic.appendSlice(allocator, &.{ 1, 9, 2, 1, 9, 2 });
    try applyLookup(table, context_lookup, &generic, allocator, options);

    const accelerator = try accelerator_root.build.lookup.one(table, context_lookup, allocator);
    defer {
        var accelerators = [_]LookupAccelerator{accelerator};
        deinitLookupAcceleratorContents(allocator, &accelerators);
    }
    try std.testing.expect(accelerator.context_group_slots.len > 1);
    const group_slot = accelerator.context_group_slots[1];
    try std.testing.expect(group_slot != 0);
    const candidates = accelerator.context_groups[group_slot - 1].subtable_indices;
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, candidates);

    var accelerated = std.ArrayList(GlyphId).empty;
    defer accelerated.deinit(allocator);
    try accelerated.appendSlice(allocator, &.{ 1, 9, 2, 1, 9, 2 });
    try contextual_context.acceleratedCoverageLookup(
        ContextualRecordExecutor,
        table,
        &accelerated,
        allocator,
        0x0008,
        .{
            .glyph_classes = &glyph_classes,
            .assume_validated = true,
        },
        &accelerator,
    );

    const expected = [_]GlyphId{ 1, 9, 20, 21, 1, 9, 20, 21 };
    try std.testing.expectEqualSlices(GlyphId, &expected, generic.items);
    try std.testing.expectEqualSlices(GlyphId, &expected, accelerated.items);

    // Accelerators are externally supplied through LookupOptions. Even after
    // lookup-offset validation, reject corrupt direct slots rather than using
    // them as unchecked indexes or silently dispatching another glyph's group.
    var invalid_index_slots = [_]u16{ 0, 2 };
    var invalid_accelerator = accelerator;
    invalid_accelerator.context_group_slots = &invalid_index_slots;
    var invalid_glyphs = std.ArrayList(GlyphId).empty;
    defer invalid_glyphs.deinit(allocator);
    try invalid_glyphs.appendSlice(allocator, &.{ 1, 2 });
    try std.testing.expectError(
        error.BadGsub,
        contextual_context.acceleratedCoverageLookup(
            ContextualRecordExecutor,
            table,
            &invalid_glyphs,
            allocator,
            0x0008,
            .{
                .glyph_classes = &glyph_classes,
                .assume_validated = true,
            },
            &invalid_accelerator,
        ),
    );

    var wrong_key_slots = [_]u16{ 0, 0, 1 };
    invalid_accelerator.context_group_slots = &wrong_key_slots;
    invalid_glyphs.clearRetainingCapacity();
    try invalid_glyphs.appendSlice(allocator, &.{ 2, 2 });
    try std.testing.expectError(
        error.BadGsub,
        contextual_context.acceleratedCoverageLookup(
            ContextualRecordExecutor,
            table,
            &invalid_glyphs,
            allocator,
            0x0008,
            .{
                .glyph_classes = &glyph_classes,
                .assume_validated = true,
            },
            &invalid_accelerator,
        ),
    );

    // A high first glyph would make a dense array wasteful. Rebuild the same
    // lookup with glyph 4096 and verify that the empty-slot representation
    // falls back to ordered group search without changing substitution order.
    writeCoverage1(
        &bytes,
        first_context + 16,
        accelerator_root.build.context_coverage.max_direct_group_slots,
    );
    writeCoverage1(
        &bytes,
        second_context + 16,
        accelerator_root.build.context_coverage.max_direct_group_slots,
    );
    const sparse_accelerator = try accelerator_root.build.lookup.one(table, context_lookup, allocator);
    defer {
        var accelerators = [_]LookupAccelerator{sparse_accelerator};
        deinitLookupAcceleratorContents(allocator, &accelerators);
    }
    try std.testing.expectEqual(@as(usize, 0), sparse_accelerator.context_group_slots.len);

    var sparse_glyphs = std.ArrayList(GlyphId).empty;
    defer sparse_glyphs.deinit(allocator);
    try sparse_glyphs.appendSlice(allocator, &.{
        accelerator_root.build.context_coverage.max_direct_group_slots,
        9,
        2,
    });
    try contextual_context.acceleratedCoverageLookup(
        ContextualRecordExecutor,
        table,
        &sparse_glyphs,
        allocator,
        0x0008,
        .{
            .glyph_classes = &glyph_classes,
            .assume_validated = true,
        },
        &sparse_accelerator,
    );
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{
            accelerator_root.build.context_coverage.max_direct_group_slots,
            9,
            20,
            21,
        },
        sparse_glyphs.items,
    );
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

test "GSUB single substitution subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 38;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 24);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 6);
    writeI16Test(&bytes, first_single + 4, 10);
    writeCoverage1(&bytes, first_single + 6, 10);

    const second_single = 24;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 6);
    writeI16Test(&bytes, second_single + 4, 10);
    writeCoverage1(&bytes, second_single + 6, 20);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 30 }, glyphs.items);
}

test "GSUB extension single substitution subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 54;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 32);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 6);
    writeI16Test(&bytes, first_single + 4, 10);
    writeCoverage1(&bytes, first_single + 6, 10);

    const second_extension = 32;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 6);
    writeI16Test(&bytes, second_single + 4, 10);
    writeCoverage1(&bytes, second_single + 6, 20);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    // Wrapped SingleSubst subtables obey the same lookup ordering as direct
    // SingleSubst: the glyph created by the first wrapper is not eligible for
    // the later wrapper in the same lookup.
    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 30 }, glyphs.items);
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

test "GSUB MarkAttachmentType uses MarkAttachClassDef without glyph classes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0100); // MarkAttachmentType 1.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const single = 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 6);
    writeI16Test(&bytes, single + 4, 10);
    writeU16Test(&bytes, single + 6, 1);
    writeU16Test(&bytes, single + 8, 3);
    writeU16Test(&bytes, single + 10, 5);
    writeU16Test(&bytes, single + 12, 7);
    writeU16Test(&bytes, single + 14, 8);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 5, 7, 8 });

    var mark_attach_classes = [_]u16{0} ** 9;
    mark_attach_classes[5] = 2;
    mark_attach_classes[7] = 1;
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .mark_attach_classes = &mark_attach_classes,
    });

    // Fonts may omit useful GlyphClassDef data while still classifying marks in
    // MarkAttachClassDef. Non-zero attachment classes must therefore activate
    // MarkAttachmentType filtering; ordinary glyphs (class zero and attachment
    // class zero) still participate.
    try std.testing.expectEqualSlices(GlyphId, &.{ 5, 17, 18 }, glyphs.items);
}

test "GSUB lookup flags honor GDEF mark filtering sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 22;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 1); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 6);
    writeI16Test(&bytes, single + 4, 10);
    writeCoverage1(&bytes, single + 6, 5);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 5, 7 });

    const mark_sets = [_][]const GlyphId{ &.{7}, &.{5} };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 15, 7 }, glyphs.items);

    // The validated Font path serves LookupFlag metadata from the accelerator
    // rather than rereading the variable-length header on every run.
    glyphs.items[0] = 5;
    const accelerator = try accelerator_root.build.lookup.one(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    const accelerators = [_]LookupAccelerator{accelerator};
    try applyLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        0,
        &glyphs,
        allocator,
        .{
            .mark_filtering_sets = &mark_sets,
            .lookup_accelerators = &accelerators,
            .assume_validated = true,
        },
        null,
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 15, 7 }, glyphs.items);
}

test "GSUB rejects missing GDEF mark filtering set indexes during shaping" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 22;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 1); // Invalid: only set 0 is supplied below.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 6);
    writeI16Test(&bytes, single + 4, 10);
    writeCoverage1(&bytes, single + 6, 5);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);

    const mark_sets = [_][]const GlyphId{&.{5}};
    // The MarkFilteringSet field is a direct index into GDEF MarkGlyphSetsDef.
    // Once those sets are available, treating an out-of-range index as "ignore
    // all marks" would hide malformed layout data and make lookup behavior
    // depend on fallback glyph-class metadata.
    try std.testing.expectError(error.BadGsub, applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .mark_filtering_sets = &mark_sets,
    }));
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
}

test "GSUB lookup flags combine mark filtering set and attachment type" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 26;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0210); // MarkAttachmentType 2 + UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 0); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeI16Test(&bytes, single + 4, 10);
    writeCoverage1List(&bytes, single + 8, &.{ 5, 7 });

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 5, 7 });

    var glyph_classes = [_]u16{0} ** 8;
    glyph_classes[5] = 3;
    glyph_classes[7] = 3;
    var mark_attach_classes = [_]u16{0} ** 8;
    mark_attach_classes[5] = 1;
    mark_attach_classes[7] = 2;
    const mark_sets = [_][]const GlyphId{&.{ 5, 7 }};
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 5, 17 }, glyphs.items);
}

test "GSUB extension substitution preserves wrapper lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 28;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 2, 0x0008);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const extension = 8;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    writeU32Test(&bytes, extension + 4, 8);

    const single = extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 6);
    writeI16Test(&bytes, single + 4, 1);
    writeCoverage1(&bytes, single + 6, 3);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 3);

    const glyph_classes = [_]u16{ 0, 1, 2, 3 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{3}, glyphs.items);
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

fn writeLigatureLookupTest(bytes: []u8, lookup_offset: usize, first: GlyphId, second: GlyphId, ligature: GlyphId) void {
    writeU16Test(bytes, lookup_offset + 0, 4); // LigatureSubst.
    writeU16Test(bytes, lookup_offset + 2, 0); // LookupFlag.
    writeU16Test(bytes, lookup_offset + 4, 1); // SubTableCount.
    writeU16Test(bytes, lookup_offset + 6, 8);

    const subtable = lookup_offset + 8;
    writeU16Test(bytes, subtable + 0, 1); // LigatureSubst format 1.
    writeU16Test(bytes, subtable + 2, 18); // Coverage.
    writeU16Test(bytes, subtable + 4, 1); // LigatureSetCount.
    writeU16Test(bytes, subtable + 6, 8);

    const set = subtable + 8;
    writeU16Test(bytes, set + 0, 1); // LigatureCount.
    writeU16Test(bytes, set + 2, 4);
    writeU16Test(bytes, set + 4, ligature);
    writeU16Test(bytes, set + 6, 2); // First glyph plus one component.
    writeU16Test(bytes, set + 8, second);
    writeCoverage1(bytes, subtable + 18, first);
}

fn writeSingleLookupGsubTest(bytes: []u8, lookup_type: u16) usize {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 12);
    writeU16Test(bytes, 8, 14);
    writeU16Test(bytes, 10, 0);
    writeU16Test(bytes, 12, 0);
    writeU16Test(bytes, 14, 1);
    writeU16Test(bytes, 16, 4);
    writeU16Test(bytes, 18, lookup_type);
    writeU16Test(bytes, 20, 0);
    writeU16Test(bytes, 22, 1);
    writeU16Test(bytes, 24, 8);
    return 26;
}

fn writeCachedSingleFeatureGsubTest(bytes: []u8) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10); // ScriptList.
    writeU16Test(bytes, 6, 30); // FeatureList.
    writeU16Test(bytes, 8, 44); // LookupList.

    writeU16Test(bytes, 10, 1);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 8);
    writeU16Test(bytes, 18, 4);
    writeU16Test(bytes, 20, 0);
    writeU16Test(bytes, 22, 0);
    writeU16Test(bytes, 24, 0xffff);
    writeU16Test(bytes, 26, 1);
    writeU16Test(bytes, 28, 0);

    writeU16Test(bytes, 30, 1);
    writeFeatureRecord(bytes, 32, unicode.tag("liga"), 8);
    writeFeature(bytes, 38, 0);

    writeU16Test(bytes, 44, 1);
    writeU16Test(bytes, 46, 4);
    writeU16Test(bytes, 48, 1); // SingleSubst lookup.
    writeU16Test(bytes, 50, 0);
    writeU16Test(bytes, 52, 1);
    writeU16Test(bytes, 54, 8);

    const single = 56;
    writeU16Test(bytes, single + 0, 1);
    writeU16Test(bytes, single + 2, 6);
    writeI16Test(bytes, single + 4, 1);
    writeCoverage1(bytes, single + 6, 10);
}

fn writeRandomFeatureGsubTest(bytes: []u8) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10); // ScriptList.
    writeU16Test(bytes, 6, 30); // FeatureList.
    writeU16Test(bytes, 8, 44); // LookupList.

    writeU16Test(bytes, 10, 1);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 8);
    writeU16Test(bytes, 18, 4);
    writeU16Test(bytes, 20, 0);
    writeU16Test(bytes, 22, 0);
    writeU16Test(bytes, 24, 0xffff);
    writeU16Test(bytes, 26, 1);
    writeU16Test(bytes, 28, 0);

    writeU16Test(bytes, 30, 1);
    writeFeatureRecord(bytes, 32, unicode.tag("rand"), 8);
    writeFeature(bytes, 38, 0);

    writeU16Test(bytes, 44, 1);
    writeU16Test(bytes, 46, 4);
    writeU16Test(bytes, 48, 3); // AlternateSubst.
    writeU16Test(bytes, 50, 0);
    writeU16Test(bytes, 52, 1);
    writeU16Test(bytes, 54, 8);

    const alternate = 56;
    writeU16Test(bytes, alternate + 0, 1);
    writeU16Test(bytes, alternate + 2, 12);
    writeU16Test(bytes, alternate + 4, 1);
    writeU16Test(bytes, alternate + 6, 18);
    writeCoverage1(bytes, alternate + 12, 10);
    writeU16Test(bytes, alternate + 18, 2);
    writeU16Test(bytes, alternate + 20, 20);
    writeU16Test(bytes, alternate + 22, 30);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, glyph);
}

fn writeCoverage1List(bytes: []u8, offset: usize, glyphs: []const GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, i| {
        writeU16Test(bytes, offset + 4 + i * 2, glyph);
    }
}

fn writeClassDef1(bytes: []u8, offset: usize, start: GlyphId, class: u16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, start);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, class);
}

fn writeScriptLanguageSelectionTable(bytes: []u8) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 90);
    writeU16Test(bytes, 8, 142);

    writeU16Test(bytes, 10, 3);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 20);
    writeU32Test(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));
    writeU16Test(bytes, 22, 44);
    writeU32Test(bytes, 24, @intFromEnum(unicode.OpenTypeScriptTag.latn));
    writeU16Test(bytes, 28, 32);

    writeScriptTable(bytes, 30, 4, 0);
    writeLangSys(bytes, 34, 2);
    writeScriptTable(bytes, 42, 4, 0);
    writeLangSys(bytes, 46, 1);
    writeU16Test(bytes, 54, 10);
    writeU16Test(bytes, 56, 1);
    writeU32Test(bytes, 58, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16Test(bytes, 62, 18);
    writeLangSys(bytes, 64, 0);
    writeLangSys(bytes, 72, 3);

    writeU16Test(bytes, 90, 4);
    writeFeatureRecord(bytes, 92, unicode.tag("ccmp"), 32);
    writeFeatureRecord(bytes, 98, unicode.tag("liga"), 26);
    writeFeatureRecord(bytes, 104, unicode.tag("rclt"), 44);
    writeFeatureRecord(bytes, 110, unicode.tag("rlig"), 38);
    writeFeature(bytes, 116, 0);
    writeFeature(bytes, 122, 1);
    writeFeature(bytes, 128, 2);
    writeFeature(bytes, 134, 3);

    writeU16Test(bytes, 142, 4);
    writeU16Test(bytes, 144, 8);
    writeU16Test(bytes, 146, 8);
    writeU16Test(bytes, 148, 8);
    writeU16Test(bytes, 150, 8);
}

fn writeGlobalVerticalFeatureSelectionTable(bytes: []u8) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10); // ScriptList.
    writeU16Test(bytes, 6, 46); // FeatureList.
    writeU16Test(bytes, 8, 60); // LookupList.

    writeU16Test(bytes, 10, 2);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 14);
    writeU32Test(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.kana));
    writeU16Test(bytes, 22, 24);

    // DFLT has a default LangSys but no features.
    writeU16Test(bytes, 24, 4);
    writeU16Test(bytes, 26, 0);
    writeU16Test(bytes, 28, 0);
    writeU16Test(bytes, 30, 0xffff);
    writeU16Test(bytes, 32, 0);

    // kana references the sole `vert` feature.
    writeU16Test(bytes, 34, 4);
    writeU16Test(bytes, 36, 0);
    writeU16Test(bytes, 38, 0);
    writeU16Test(bytes, 40, 0xffff);
    writeU16Test(bytes, 42, 1);
    writeU16Test(bytes, 44, 0);

    writeU16Test(bytes, 46, 1);
    writeU32Test(bytes, 48, unicode.tag("vert"));
    writeU16Test(bytes, 52, 8);
    writeU16Test(bytes, 54, 0);
    writeU16Test(bytes, 56, 1);
    writeU16Test(bytes, 58, 0);

    writeU16Test(bytes, 60, 1);
    writeU16Test(bytes, 62, 4);
    writeU16Test(bytes, 64, 1); // SingleSubst lookup.
    writeU16Test(bytes, 66, 0);
    writeU16Test(bytes, 68, 1);
    writeU16Test(bytes, 70, 8);
    writeU16Test(bytes, 72, 1);
    writeU16Test(bytes, 74, 6);
    writeI16Test(bytes, 76, 1);
    writeCoverage1(bytes, 78, 1);
}

fn writeScriptTable(bytes: []u8, offset: usize, default_lang_offset: u16, lang_count: u16) void {
    writeU16Test(bytes, offset, default_lang_offset);
    writeU16Test(bytes, offset + 2, lang_count);
}

fn writeLangSys(bytes: []u8, offset: usize, feature_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 0xffff);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, feature_index);
}

fn writeFeatureRecord(bytes: []u8, offset: usize, tag_value: u32, feature_offset: u16) void {
    writeU32Test(bytes, offset, tag_value);
    writeU16Test(bytes, offset + 4, feature_offset);
}

fn writeFeature(bytes: []u8, offset: usize, lookup_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, lookup_index);
}

fn writeFeatureList(bytes: []u8, offset: usize, lookups: []const u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, @intCast(lookups.len));
    for (lookups, 0..) |lookup_index, index| {
        writeU16Test(bytes, offset + 4 + index * 2, lookup_index);
    }
}

fn writeLayoutTagOrderingTable(bytes: []u8) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 68);
    writeU16Test(bytes, 8, 90);

    writeU16Test(bytes, 10, 2);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 14);
    writeU32Test(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));
    writeU16Test(bytes, 22, 54);

    writeU16Test(bytes, 24, 16);
    writeU16Test(bytes, 26, 2);
    writeU32Test(bytes, 28, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16Test(bytes, 32, 24);
    writeU32Test(bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.kor));
    writeU16Test(bytes, 38, 32);
    writeLangSys(bytes, 40, 0);
    writeLangSys(bytes, 48, 1);
    writeLangSys(bytes, 56, 1);

    writeU16Test(bytes, 64, 0);
    writeU16Test(bytes, 66, 0);

    writeU16Test(bytes, 68, 2);
    writeFeatureRecord(bytes, 70, unicode.tag("ccmp"), 14);
    writeFeatureRecord(bytes, 76, unicode.tag("liga"), 18);
    writeU16Test(bytes, 82, 0);
    writeU16Test(bytes, 84, 0);
    writeU16Test(bytes, 86, 0);
    writeU16Test(bytes, 88, 0);

    writeU16Test(bytes, 90, 0);
}

fn writeRequiredFeatureSelectionTable(bytes: []u8, required_tag: u32, optional_tag: u32) void {
    const required_first = required_tag < optional_tag;
    const required_feature_index: u16 = if (required_first) 0 else 1;
    const optional_feature_index: u16 = if (required_first) 1 else 0;

    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 34);
    writeU16Test(bytes, 8, 60);

    writeU16Test(bytes, 10, 1);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 8);

    writeU16Test(bytes, 18, 4);
    writeU16Test(bytes, 20, 0);
    writeU16Test(bytes, 22, 0);
    writeU16Test(bytes, 24, required_feature_index);
    writeU16Test(bytes, 26, 1);
    writeU16Test(bytes, 28, optional_feature_index);

    writeU16Test(bytes, 34, 2);
    if (required_first) {
        writeFeatureRecord(bytes, 36, required_tag, 14);
        writeFeatureRecord(bytes, 42, optional_tag, 20);
    } else {
        writeFeatureRecord(bytes, 36, optional_tag, 20);
        writeFeatureRecord(bytes, 42, required_tag, 14);
    }
    writeFeature(bytes, 48, 0);
    writeFeature(bytes, 54, 1);

    writeU16Test(bytes, 60, 2);
    writeU16Test(bytes, 62, 0);
    writeU16Test(bytes, 64, 0);
}

fn writeRepeatedLookupSelectionTable(bytes: []u8, feature_tag: u32) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 34);
    writeU16Test(bytes, 8, 66);

    writeU16Test(bytes, 10, 1);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 8);

    writeU16Test(bytes, 18, 4);
    writeU16Test(bytes, 20, 0);
    writeU16Test(bytes, 22, 0);
    writeU16Test(bytes, 24, 0xffff);
    writeU16Test(bytes, 26, 2);
    writeU16Test(bytes, 28, 0);
    writeU16Test(bytes, 30, 1);

    writeU16Test(bytes, 34, 2);
    writeFeatureRecord(bytes, 36, feature_tag, 14);
    writeFeatureRecord(bytes, 42, feature_tag, 24);
    writeFeatureList(bytes, 48, &.{ 3, 1, 3 });
    writeFeatureList(bytes, 58, &.{ 2, 1 });

    writeU16Test(bytes, 66, 4);
    writeU16Test(bytes, 68, 0);
    writeU16Test(bytes, 70, 0);
    writeU16Test(bytes, 72, 0);
    writeU16Test(bytes, 74, 0);
}

test "GSUB public apply validates source metadata cardinality" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.append(allocator, 0);

    try std.testing.expectError(error.InvalidShapingInput, applyWithOptions(&bytes, 0, bytes.len, &glyphs, allocator, .{
        .glyph_source_indices = &sources,
    }));
}

test "GSUB public apply validates ligature component source order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);

    var ligature_components = ligature_provenance.Store{};
    defer ligature_components.deinit(allocator);
    try ligature_components.sources.appendSlice(allocator, &.{ 3, 2 });
    try ligature_components.infos.append(allocator, .{ .component_count = 2 });

    try std.testing.expectError(error.InvalidShapingInput, applyWithOptions(&bytes, 0, bytes.len, &glyphs, allocator, .{
        .ligature_components = &ligature_components,
    }));
}

test {
    _ = @import("gsub/tests/accelerator/root.zig");
    _ = @import("gsub/tests/execution/root.zig");
    _ = @import("gsub/tests/feature/root.zig");
    _ = @import("gsub/tests/runtime/root.zig");
    _ = @import("gsub/tests/table/root.zig");
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
