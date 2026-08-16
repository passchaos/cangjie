const std = @import("std");
const accelerator_root = @import("gsub/accelerator/root.zig");
const accelerator_model = accelerator_root.model;
const cluster_safety = @import("shaping/cluster_safety.zig");
const feature_domain = @import("gsub/feature/root.zig");
const GlyphDigest = @import("glyph_digest.zig").GlyphDigest;
const GlyphId = @import("glyph.zig").GlyphId;
const ligature_provenance = @import("ligature_provenance.zig");
const class_context = @import("opentype/class_context.zig");
pub const runtime = @import("gsub/runtime/root.zig");
const table_core = @import("gsub/table/root.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const shaping_sections = @import("shaping_sections.zig");
const unicode = @import("unicode.zig");
const shape_profile_mod = @import("shape_profile.zig");

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
const SingleSubstAccelerator = accelerator_model.SingleSubstitution;
const SingleSubstEntry = accelerator_model.SingleEntry;
const MultipleSubstAccelerator = accelerator_model.MultipleSubstitution;
const MultipleSubstEntry = accelerator_model.MultipleEntry;
const LigatureSubstAccelerator = accelerator_model.LigatureSubstitution;
const LigatureSetEntry = accelerator_model.LigatureSet;
const LigatureDefinition = accelerator_model.LigatureDefinition;
const ContextClassSubtableAccelerator = accelerator_model.ContextClassSubtable;
const ContextCoverageSubtable = accelerator_model.ContextCoverageSubtable;
const ChainingCoverageSubtable = accelerator_model.ChainingCoverageSubtable;
const FastSingleRecord = accelerator_model.FastSingleRecord;
const ChainingClassSubtableAccelerator = accelerator_model.ChainingClassSubtable;
const ReverseChainingSingleSubtable = accelerator_model.ReverseChainingSingleSubtable;
const ReverseChainingContextKey = accelerator_model.ReverseChainingContextKey;
const ReverseChainingContextEntry = accelerator_model.ReverseChainingContextEntry;
const ChainingSubtableGroup = accelerator_model.ChainingGroup;
const ChainingSubtablePair = accelerator_model.ChainingPair;
const ChainingPairSubtableGroup = accelerator_model.ChainingPairGroup;
const ChainingPairSubtablePair = accelerator_model.ChainingPairEntry;
const deinitLookupAccelerators = accelerator_root.ownership.deinit;
const deinitLookupAcceleratorContents =
    accelerator_root.ownership.deinitContents;

// HarfBuzz's fast LigatureSet path extracts the second component once before
// trying definitions. Select these thresholds once per lookup rather than
// adding branches to every candidate glyph.
fn chainingClassRuleBacktrackCount(rule: class_context.Rule) u16 {
    // The conservative accelerator subset has no substitution-record offset,
    // so this shared Rule field carries its already-proven backtrack count.
    return @intCast(rule.records_offset);
}

const empty_class_def_offset = table_core.class_def.empty_offset;

const max_run_digest_cache_entries = 16;

const RunDigestCache = struct {
    const Entry = struct {
        lookup_flag: u16,
        active_mark_filtering_set: ?u16,
        active_source_feature: ?u32,
        active_source_feature_mask: u32,
        digest: GlyphDigest,
    };

    entries: [max_run_digest_cache_entries]Entry = undefined,
    len: usize = 0,
    generation: usize = 0,

    fn init() RunDigestCache {
        // `get` only reads entries below `len`, and every such entry is
        // assigned immediately before `len` advances. Initializing only this
        // small header avoids clearing 16 large digest entries for every
        // shaped run while preserving the same mutation-generation semantics.
        var cache: RunDigestCache = undefined;
        cache.len = 0;
        cache.generation = 0;
        return cache;
    }

    fn get(self: *RunDigestCache, glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GlyphDigest {
        const generation = if (options.glyph_mutation_generation) |value| value.* else 0;
        if (generation != self.generation) {
            // A GSUB replacement may introduce a glyph covered by a later
            // lookup. Drop all summaries at once rather than trying to update
            // approximate sets through cardinality-changing nested lookups.
            self.len = 0;
            self.generation = generation;
        }

        for (self.entries[0..self.len]) |entry| {
            if (entry.lookup_flag == lookup_flag and
                entry.active_mark_filtering_set == options.active_mark_filtering_set and
                entry.active_source_feature == options.active_source_feature and
                entry.active_source_feature_mask == options.active_source_feature_mask)
            {
                return entry.digest;
            }
        }

        const digest = glyphRunDigest(glyphs, lookup_flag, options);
        if (self.len < self.entries.len) {
            self.entries[self.len] = .{
                .lookup_flag = lookup_flag,
                .active_mark_filtering_set = options.active_mark_filtering_set,
                .active_source_feature = options.active_source_feature,
                .active_source_feature_mask = options.active_source_feature_mask,
                .digest = digest,
            };
            self.len += 1;
        }
        return digest;
    }
};

const FeatureApplication = feature.Application;
const FeatureLookupPlanEntry = feature.LookupPlanEntry;
const MergedFeatureLookup = feature.MergedLookup;
const MergedFeatureLookupPlan = feature.MergedLookupPlan;
const FeatureLookupPlan = feature.LookupPlan;
const source_feature_mask_marker = feature.source_mask_marker;
const sourceFeatureMaskForTag = feature.sourceMaskForTag;

const SelectedLookup = feature_domain.run_selection.SelectedLookup;

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
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    try runtime.metadata.validate(options, glyphs.items.len);
    var mutation_generation: usize = 0;
    var operations_left: usize = 0;
    const shaping_options = try optionsWithTopLevelState(
        options,
        glyphs.items.len,
        &mutation_generation,
        &operations_left,
    );
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = shaping_options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return;
    // Script/language/feature selection happens before the lookup list pass.
    // When no explicit features are supplied, selectedLookupIndices returns the
    // default-enabled lookups for the requested script/language.
    const select_start = shapeProfileNow(shaping_options.shape_profile, shaping_options.profile_io);
    var selected_lookup_records_owned = if (shaping_options.selected_lookups == null) blk: {
        break :blk selectedLookupRecords(table, allocator, shaping_options) catch |err| {
            if (err == error.BadGsub and try canFallbackFromBadGsubSelection(table)) {
                break :blk std.ArrayList(SelectedLookup).empty;
            }
            return err;
        };
    } else std.ArrayList(SelectedLookup).empty;
    if (shaping_options.shape_profile) |profile| profile.gsub_select_ns += shapeProfileElapsed(select_start, shaping_options.profile_io);
    defer selected_lookup_records_owned.deinit(allocator);
    const selected_lookup_count = if (shaping_options.selected_lookups) |selected_lookups|
        selected_lookups.len
    else
        selected_lookup_records_owned.items.len;
    const script_list_offset = try readU16(table, 4);
    const feature_list_offset = try readU16(table, 6);
    const has_feature_topology = script_list_offset != 0 and
        feature_list_offset != 0 and
        try readU16(table, script_list_offset) != 0 and
        try readU16(table, feature_list_offset) != 0;
    // An empty selection means the active LangSys has no required/default
    // feature to apply. Falling through used to execute every lookup in the
    // font, enabling optional stylistic sets such as New Computer Modern's
    // Devanagari digit substitutions for ordinary ASCII digits. Low-level
    // callers can retain the historical all-lookup behavior; the text shaper
    // explicitly disables it after Script/LangSys selection.
    if (selected_lookup_count == 0 and
        (shaping_options.features.len != 0 or (!shaping_options.apply_all_if_unselected and has_feature_topology))) return;

    const apply_start = shapeProfileNow(shaping_options.shape_profile, shaping_options.profile_io);
    defer {
        if (shaping_options.shape_profile) |profile| profile.gsub_apply_ns += shapeProfileElapsed(apply_start, shaping_options.profile_io);
    }
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    var run_digest_cache = RunDigestCache.init();
    if (shaping_options.selected_lookups) |selected_lookups| {
        for (selected_lookups) |lookup_index| {
            if (lookup_index >= lookup_count) continue;
            const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
            try applyLookupWithIndex(table, lookup_offset, lookup_index, glyphs, allocator, shaping_options, &run_digest_cache);
        }
    } else if (selected_lookup_records_owned.items.len != 0) {
        for (selected_lookup_records_owned.items) |selected_lookup| {
            const lookup_index = selected_lookup.index;
            if (lookup_index >= lookup_count) continue;
            const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
            var selected_options = shaping_options;
            selected_options.active_feature_value = selected_lookup.value;
            selected_options.active_feature_random = selected_lookup.random;
            try applyLookupWithIndex(table, lookup_offset, lookup_index, glyphs, allocator, selected_options, &run_digest_cache);
        }
    } else {
        for (0..lookup_count) |i| {
            const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + i * 2));
            try applyLookupWithIndex(table, lookup_offset, @intCast(i), glyphs, allocator, shaping_options, &run_digest_cache);
        }
    }
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
    if (!options.assume_validated) return false;
    // The layout shaper installs one shared HarfBuzz-compatible budget across
    // all of its GSUB stages. Do not let another caller accidentally turn this
    // trusted shortcut into an unbounded substitution executor.
    if (options.operations_left == null or options.max_glyph_count == null) return false;
    if (length < 10 or offset > data.len or length > data.len - offset) return false;
    const selected_lookups = options.selected_lookups orelse return false;
    if (selected_lookups.len == 0) return false;
    const accelerators = options.lookup_accelerators orelse return false;
    _ = accelerator_root.feature_index.exact(
        data,
        offset,
        length,
        accelerators,
    ) orelse return false;

    for (selected_lookups) |lookup_index| {
        if (lookup_index >= accelerators.len) return false;
        const accelerator = accelerators[lookup_index];
        if (accelerator.lookup_offset == 0 or accelerator.lookup_type == 0) return false;
    }

    var mutation_generation: usize = 0;
    const shaping_options = optionsWithRunDigestGeneration(options, &mutation_generation);
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = true,
    };
    var run_digest_cache = RunDigestCache.init();
    for (selected_lookups) |lookup_index| {
        const accelerator = accelerators[lookup_index];
        try applyLookupWithIndex(
            table,
            accelerator.lookup_offset,
            lookup_index,
            glyphs,
            allocator,
            shaping_options,
            &run_digest_cache,
        );
    }
    return true;
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
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return try allocator.alloc(u16, 0);

    var feature_indices = std.ArrayList(FeatureSelection).empty;
    defer feature_indices.deinit(allocator);
    const script_list_offset = try checkedRequiredScriptListOffset(table);
    const script_offset = (try feature_domain.selection.script(
        table,
        script_list_offset,
        options.script_tag,
    )) orelse 0;
    if (script_offset != 0) {
        try feature_domain.selection.collect(
            table,
            script_offset,
            options.language_tag,
            &feature_indices,
            allocator,
        );
    }
    const feature_list_offset = try checkedRequiredFeatureListOffset(table);
    const feature_count = try readU16(table, feature_list_offset);
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    return selectedFeatureLookupsFromPlanOwned(
        table,
        feature_tag,
        feature_indices.items,
        feature_list_offset,
        feature_count,
        lookup_count,
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
    const shaping_options = optionsWithRunDigestGeneration(
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
    var run_digest_cache = RunDigestCache.init();
    try applyLookupIndices(
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

fn canFallbackFromBadGsubSelection(table: Table) GsubError!bool {
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    try ensureBytesWithin(table, lookup_list_offset + 2, @as(usize, lookup_count) * 2);
    _ = try feature_domain.validation.lookupReferences(table, lookup_count);
    return true;
}

pub fn hasFeature(data: []const u8, offset: usize, length: usize, feature_tag: u32) GsubError!bool {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = true };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return false;
    const feature_list_offset = try checkedRequiredFeatureListOffset(table);
    const feature_count = try readU16(table, feature_list_offset);
    for (0..feature_count) |feature_i| {
        if (try readU32(table, feature_list_offset + 2 + feature_i * 6) == feature_tag) return true;
    }
    return false;
}

pub fn isEmptyTable(data: []const u8, offset: usize, length: usize) GsubError!bool {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{ .data = data, .offset = offset, .length = length };
    const major = try readU16BadGsub(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    return isEmptyGsubTopology(table);
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
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    try runtime.metadata.validateApplications(options, glyphs.items.len, applications);
    var mutation_generation: usize = 0;
    var operations_left: usize = 0;
    const shaping_options = try optionsWithTopLevelState(
        options,
        glyphs.items.len,
        &mutation_generation,
        &operations_left,
    );
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = shaping_options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return;
    var run_digest_cache = RunDigestCache.init();

    // Preserve arbitrary LangSys-required features even when a higher-level
    // script plan names only the well-known stages it needs to interleave.
    // Required tags already present in the explicit plan are handled there so
    // position-scoped form features do not run once globally and once scoped.
    var feature_indices_stack: [64]FeatureSelection = undefined;
    var feature_indices_stack_len: usize = 0;
    var owned_feature_indices = std.ArrayList(FeatureSelection).empty;
    defer owned_feature_indices.deinit(allocator);
    const script_list_offset = try checkedRequiredScriptListOffset(table);
    const script_offset = (try feature_domain.selection.script(
        table,
        script_list_offset,
        shaping_options.script_tag,
    )) orelse 0;
    if (script_offset != 0) {
        if (try feature_domain.selection.languageSystem(table, script_offset, shaping_options.language_tag)) |lang_sys_offset| {
            try feature_domain.selection.collectLanguageStackFirst(
                table,
                lang_sys_offset,
                &feature_indices_stack,
                &feature_indices_stack_len,
                &owned_feature_indices,
                allocator,
            );
        }
    }
    const feature_indices = if (owned_feature_indices.items.len != 0)
        owned_feature_indices.items
    else
        feature_indices_stack[0..feature_indices_stack_len];
    const feature_list_offset = try checkedRequiredFeatureListOffset(table);
    const feature_count = try readU16(table, feature_list_offset);
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    for (feature_indices) |selection| {
        if (!selection.required or selection.index >= feature_count) continue;
        const feature_record = feature_list_offset + 2 + @as(usize, selection.index) * 6;
        const required_tag = try readU32(table, feature_record);
        if (featurePlanContains(applications, required_tag)) continue;
        var required_options = shaping_options;
        required_options.active_source_feature = null;
        try applySelectedFeatureFromPlan(table, required_tag, feature_indices, feature_list_offset, feature_count, lookup_list_offset, lookup_count, glyphs, allocator, required_options, &run_digest_cache);
    }

    for (applications) |application| {
        var selected_options = shaping_options;
        selected_options.active_source_feature = if (application.source_scoped) application.tag else null;
        selected_options.match_source_syllable = application.match_source_syllable;
        selected_options.active_auto_zwnj = application.auto_zwnj;
        selected_options.active_auto_zwj = application.auto_zwj;
        selected_options.active_feature_value = application.value;
        selected_options.active_feature_random = featureApplicationIsRandom(application);
        try applySelectedFeatureFromPlan(table, application.tag, feature_indices, feature_list_offset, feature_count, lookup_list_offset, lookup_count, glyphs, allocator, selected_options, &run_digest_cache);
    }
}

fn buildFeatureLookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    applications: []const feature.Application,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!feature.LookupPlan {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) {
        return .{ .entries = try allocator.alloc(FeatureLookupPlanEntry, 0) };
    }

    var feature_indices = std.ArrayList(FeatureSelection).empty;
    defer feature_indices.deinit(allocator);
    const script_list_offset = try checkedRequiredScriptListOffset(table);
    const script_offset = (try feature_domain.selection.script(
        table,
        script_list_offset,
        options.script_tag,
    )) orelse 0;
    if (script_offset != 0) try feature_domain.selection.collect(table, script_offset, options.language_tag, &feature_indices, allocator);
    const feature_list_offset = try checkedRequiredFeatureListOffset(table);
    const feature_count = try readU16(table, feature_list_offset);
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);

    var entries = std.ArrayList(FeatureLookupPlanEntry).empty;
    errdefer {
        for (entries.items) |entry| allocator.free(entry.lookups);
        entries.deinit(allocator);
    }
    for (feature_indices.items) |selection| {
        if (!selection.required or selection.index >= feature_count) continue;
        const feature_record = feature_list_offset + 2 + @as(usize, selection.index) * 6;
        const required_tag = try readU32(table, feature_record);
        if (featurePlanContains(applications, required_tag)) continue;
        const lookups = try selectedFeatureLookupsFromPlanOwned(table, required_tag, feature_indices.items, feature_list_offset, feature_count, lookup_count, allocator, options);
        errdefer allocator.free(lookups);
        const lookup_offsets = try lookupOffsetsForIndices(table, lookup_list_offset, lookups, allocator);
        errdefer allocator.free(lookup_offsets);
        try entries.append(allocator, .{
            .application = .{ .tag = required_tag },
            .lookups = lookups,
            .lookup_offsets = lookup_offsets,
        });
    }
    for (applications) |application| {
        const lookups = try selectedFeatureLookupsFromPlanOwned(table, application.tag, feature_indices.items, feature_list_offset, feature_count, lookup_count, allocator, options);
        errdefer allocator.free(lookups);
        const lookup_offsets = try lookupOffsetsForIndices(table, lookup_list_offset, lookups, allocator);
        errdefer allocator.free(lookup_offsets);
        try entries.append(allocator, .{
            .application = application,
            .lookups = lookups,
            .lookup_offsets = lookup_offsets,
        });
    }
    return .{ .entries = try entries.toOwnedSlice(allocator) };
}

fn buildMergedFeatureLookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    applications: []const feature.Application,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!feature.MergedLookupPlan {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) {
        return .{
            .lookups = try allocator.alloc(MergedFeatureLookup, 0),
            .lookup_offsets = try allocator.alloc(usize, 0),
        };
    }

    var feature_indices = std.ArrayList(FeatureSelection).empty;
    defer feature_indices.deinit(allocator);
    const script_list_offset = try checkedRequiredScriptListOffset(table);
    const script_offset = (try feature_domain.selection.script(
        table,
        script_list_offset,
        options.script_tag,
    )) orelse 0;
    if (script_offset != 0) try feature_domain.selection.collect(table, script_offset, options.language_tag, &feature_indices, allocator);
    const feature_list_offset = try checkedRequiredFeatureListOffset(table);
    const feature_count = try readU16(table, feature_list_offset);
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);

    var lookups = std.ArrayList(MergedFeatureLookup).empty;
    errdefer lookups.deinit(allocator);
    for (feature_indices.items) |selection| {
        if (!selection.required or selection.index >= feature_count) continue;
        const feature_record = feature_list_offset + 2 + @as(usize, selection.index) * 6;
        const required_tag = try readU32(table, feature_record);
        if (featurePlanContains(applications, required_tag)) continue;
        const selected = try selectedFeatureLookupsFromPlanOwned(table, required_tag, feature_indices.items, feature_list_offset, feature_count, lookup_count, allocator, options);
        defer allocator.free(selected);
        try appendMergedFeatureLookups(&lookups, allocator, selected, .{ .tag = required_tag });
    }
    for (applications) |application| {
        const selected = try selectedFeatureLookupsFromPlanOwned(table, application.tag, feature_indices.items, feature_list_offset, feature_count, lookup_count, allocator, options);
        defer allocator.free(selected);
        try appendMergedFeatureLookups(&lookups, allocator, selected, application);
    }

    sortMergeFeatureLookups(&lookups);
    const owned_lookups = try lookups.toOwnedSlice(allocator);
    errdefer allocator.free(owned_lookups);
    const selected_lookup_indices = try allocator.alloc(u16, owned_lookups.len);
    defer allocator.free(selected_lookup_indices);
    for (owned_lookups, selected_lookup_indices) |lookup, *selected_lookup_index| {
        selected_lookup_index.* = lookup.lookup;
    }
    const lookup_offsets = try lookupOffsetsForIndices(table, lookup_list_offset, selected_lookup_indices, allocator);
    return .{ .lookups = owned_lookups, .lookup_offsets = lookup_offsets };
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
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    try runtime.metadata.validateLookupPlan(options, glyphs.items.len, plan);
    return try applyFeatureLookupPlanWithOptionsAfterMetadataProof(
        data,
        offset,
        length,
        plan,
        glyphs,
        allocator,
        options,
    );
}

/// Apply a cached feature plan after the caller has proved glyph/source
/// metadata for this shaping run.
///
/// This is an internal shaping fast path. It is sound across consecutive GSUB
/// stages because every supported substitution updates glyph ids and all
/// source-parallel arrays atomically. SingleSubst format 1 may temporarily
/// leave maxp's renderable range, so the complete shaper must validate final
/// glyph IDs before GPOS or metrics. Callers must not use it for an
/// independently supplied or externally mutated run;
/// `applyFeatureLookupPlanWithOptions` remains the defensive API.
fn applyFeatureLookupPlanWithOptionsAfterMetadataProof(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.LookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    var mutation_generation: usize = 0;
    var operations_left: usize = 0;
    const shaping_options = try optionsWithTopLevelState(
        options,
        glyphs.items.len,
        &mutation_generation,
        &operations_left,
    );
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = shaping_options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) {
        // Cached plans built for this topology are necessarily empty. Keep the
        // executor independently safe because callers may retain a plan across
        // cache layers rather than re-entering the builder on every run.
        if (plan.entries.len != 0) return error.BadGsub;
        return;
    }

    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    var run_digest_cache = RunDigestCache.init();
    for (plan.entries) |entry| {
        var selected_options = shaping_options;
        selected_options.active_source_feature = if (entry.application.source_scoped) entry.application.tag else null;
        selected_options.match_source_syllable = entry.application.match_source_syllable;
        selected_options.active_auto_zwnj = entry.application.auto_zwnj;
        selected_options.active_auto_zwj = entry.application.auto_zwj;
        selected_options.active_feature_value = entry.application.value;
        selected_options.active_feature_random = featureApplicationIsRandom(entry.application);
        try applyLookupPlanEntry(table, lookup_count, entry, glyphs, allocator, selected_options, &run_digest_cache);
    }
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
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    try runtime.metadata.validateMergedLookupPlan(options, glyphs.items.len, plan);
    return try applyMergedFeatureLookupPlanWithOptionsAfterMetadataProof(
        data,
        offset,
        length,
        plan,
        glyphs,
        allocator,
        options,
    );
}

/// Merged-plan counterpart to
/// `applyFeatureLookupPlanWithOptionsAfterMetadataProof`.
fn applyMergedFeatureLookupPlanWithOptionsAfterMetadataProof(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.MergedLookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    var mutation_generation: usize = 0;
    var operations_left: usize = 0;
    const shaping_options = try optionsWithTopLevelState(
        options,
        glyphs.items.len,
        &mutation_generation,
        &operations_left,
    );
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = shaping_options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) {
        if (plan.lookups.len != 0 or plan.lookup_offsets.len != 0) return error.BadGsub;
        return;
    }

    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    if (plan.lookups.len != plan.lookup_offsets.len) return error.BadGsub;
    var run_digest_cache = RunDigestCache.init();
    for (plan.lookups, plan.lookup_offsets) |lookup, lookup_offset| {
        if (lookup.lookup >= lookup_count) return error.BadGsub;
        var selected_options = shaping_options;
        selected_options.active_source_feature = null;
        selected_options.active_source_feature_mask = lookup.source_mask;
        selected_options.active_auto_zwnj = lookup.auto_zwnj;
        selected_options.active_auto_zwj = lookup.auto_zwj;
        selected_options.match_source_syllable = lookup.match_source_syllable;
        selected_options.active_feature_value = lookup.value;
        selected_options.active_feature_random = lookup.random;
        try applyLookupWithIndex(table, lookup_offset, lookup.lookup, glyphs, allocator, selected_options, &run_digest_cache);
    }
}

fn featurePlanContains(applications: []const FeatureApplication, feature_tag: u32) bool {
    for (applications) |application| {
        if (application.tag == feature_tag) return true;
    }
    return false;
}

fn featureApplicationIsRandom(application: FeatureApplication) bool {
    return application.tag == unicode.tag("rand") and
        application.value == random_feature_value;
}

fn applySelectedFeature(
    table: Table,
    feature_tag: u32,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    var feature_indices = std.ArrayList(FeatureSelection).empty;
    defer feature_indices.deinit(allocator);
    const script_list_offset = try checkedRequiredScriptListOffset(table);
    const script_offset = (try feature_domain.selection.script(
        table,
        script_list_offset,
        options.script_tag,
    )) orelse return;
    try feature_domain.selection.collect(table, script_offset, options.language_tag, &feature_indices, allocator);

    const feature_list_offset = try checkedRequiredFeatureListOffset(table);
    const feature_count = try readU16(table, feature_list_offset);
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    try applySelectedFeatureFromPlan(table, feature_tag, feature_indices.items, feature_list_offset, feature_count, lookup_list_offset, lookup_count, glyphs, allocator, options, null);
}

fn applySelectedFeatureFromPlan(
    table: Table,
    feature_tag: u32,
    feature_indices: []const FeatureSelection,
    feature_list_offset: usize,
    feature_count: u16,
    lookup_list_offset: usize,
    lookup_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
    run_digest_cache: ?*RunDigestCache,
) (GsubError || std.mem.Allocator.Error)!void {
    if (borrowedSelectedFeatureLookups(
        table,
        feature_tag,
        feature_indices,
        feature_count,
        options,
    )) |selected_lookups| {
        try applyLookupIndices(table, lookup_list_offset, lookup_count, selected_lookups, glyphs, allocator, options, run_digest_cache);
        return;
    }
    const selected_lookups = try selectedFeatureLookupsFromPlanOwned(table, feature_tag, feature_indices, feature_list_offset, feature_count, lookup_count, allocator, options);
    defer allocator.free(selected_lookups);
    try applyLookupIndices(table, lookup_list_offset, lookup_count, selected_lookups, glyphs, allocator, options, run_digest_cache);
}

fn borrowedSelectedFeatureLookups(
    table: Table,
    feature_tag: u32,
    feature_indices: []const FeatureSelection,
    feature_count: u16,
    options: LookupOptions,
) ?[]const u16 {
    if (options.normalized_variation_coords.len != 0) return null;
    if (!table.assume_validated or feature_indices.len == 0) return null;
    const accelerators = options.lookup_accelerators orelse return null;
    const feature_index = accelerator_root.feature_index.exact(
        table.data,
        table.offset,
        table.length,
        accelerators,
    ) orelse return null;
    return accelerator_root.feature_index.selectedLookups(
        feature_index,
        feature_tag,
        feature_indices,
        feature_count,
    );
}

fn selectedFeatureLookupsFromPlanOwned(
    table: Table,
    feature_tag: u32,
    feature_indices: []const FeatureSelection,
    feature_list_offset: usize,
    feature_count: u16,
    lookup_count: u16,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)![]u16 {
    var selected_lookups = std.ArrayList(u16).empty;
    errdefer selected_lookups.deinit(allocator);
    const feature_variation_index = try feature_domain.variations.matchingRecord(
        table,
        options.normalized_variation_coords,
    );
    for (feature_indices) |selection| {
        if (selection.index >= feature_count) continue;
        const feature_record = feature_list_offset + 2 + @as(usize, selection.index) * 6;
        if (try readU32(table, feature_record) != feature_tag) continue;
        const default_feature_offset = feature_list_offset + try readU16(table, feature_record + 4);
        const feature_offset = if (feature_variation_index) |variation_index|
            try feature_domain.variations.substitutedFeatureOffset(
                table,
                variation_index,
                selection.index,
            ) orelse default_feature_offset
        else
            default_feature_offset;
        const lookup_index_count = try readU16(table, feature_offset + 2);
        for (0..lookup_index_count) |lookup_i| {
            const lookup_index = try readU16(table, feature_offset + 4 + lookup_i * 2);
            if (lookup_index >= lookup_count) return error.BadGsub;
            // Some production fonts repeat a feature record or the same lookup
            // index within one feature. OpenType feature application is a set
            // of lookups in lookup-list order; do not feed a replacement back
            // through the same lookup merely because the activation graph has
            // duplicate references.
            try selected_lookups.append(allocator, lookup_index);
        }
    }
    sortUniqueLookupIndices(&selected_lookups);
    return try selected_lookups.toOwnedSlice(allocator);
}

fn applyLookupIndices(
    table: Table,
    lookup_list_offset: usize,
    lookup_count: u16,
    selected_lookups: []const u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
    run_digest_cache: ?*RunDigestCache,
) (GsubError || std.mem.Allocator.Error)!void {
    for (selected_lookups) |lookup_index| {
        if (lookup_index >= lookup_count) return error.BadGsub;
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
        try applyLookupWithIndex(table, lookup_offset, lookup_index, glyphs, allocator, options, run_digest_cache);
    }
}

fn lookupOffsetsForIndices(table: Table, lookup_list_offset: usize, selected_lookups: []const u16, allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)![]usize {
    const lookup_offsets = try allocator.alloc(usize, selected_lookups.len);
    errdefer allocator.free(lookup_offsets);
    for (selected_lookups, lookup_offsets) |lookup_index, *lookup_offset| {
        lookup_offset.* = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
    }
    return lookup_offsets;
}

fn applyLookupPlanEntry(table: Table, lookup_count: u16, entry: FeatureLookupPlanEntry, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions, run_digest_cache: ?*RunDigestCache) (GsubError || std.mem.Allocator.Error)!void {
    if (entry.lookup_offsets.len != entry.lookups.len) return error.BadGsub;
    for (entry.lookups, entry.lookup_offsets) |lookup_index, lookup_offset| {
        if (lookup_index >= lookup_count) return error.BadGsub;
        try applyLookupWithIndex(table, lookup_offset, lookup_index, glyphs, allocator, options, run_digest_cache);
    }
}

fn classGroupForGlyph(classes: []const u16, first_index_start: usize, groups: []const class_context.RuleGroup, glyph: GlyphId) ?class_context.RuleGroup {
    return accelerator_root.index.class_first.find(
        classes,
        first_index_start,
        groups,
        glyph,
    );
}

fn chainingClassGroupForGlyph(subtable: ChainingClassSubtableAccelerator, glyph: GlyphId) ?class_context.RuleGroup {
    return classGroupForGlyph(subtable.classes, subtable.first_index_start, subtable.groups, glyph);
}

fn buildSingleSubstEntries(table: Table, subtable_offset: usize, allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)![]SingleSubstEntry {
    return accelerator_root.build.single.entries(
        table,
        subtable_offset,
        allocator,
    );
}

const buildLigatureSubstAccelerator =
    accelerator_root.build.ligature.build;

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
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{ .data = data, .offset = offset, .length = length, .glyph_count = glyph_count };
    const major = try readU16BadGsub(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return;

    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16BadGsub(table, lookup_list_offset);
    try ensureBytesWithin(table, lookup_list_offset + 2, @as(usize, lookup_count) * 2);
    const feature_count = try feature_domain.validation.lookupReferences(table, lookup_count);
    try feature_domain.validation.scriptReferences(table, feature_count);
    for (0..lookup_count) |lookup_i| {
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16BadGsub(table, lookup_list_offset + 2 + lookup_i * 2));
        try ensureLookupHeaderWithin(table, lookup_offset);
        const lookup_type = try readU16BadGsub(table, lookup_offset);
        const subtable_count = try readU16BadGsub(table, lookup_offset + 4);
        try ensureSubstitutionLookupSubtablesWithin(table, lookup_offset, lookup_type, subtable_count);
    }
}

pub fn validateGlyphBoundsForShaping(data: []const u8, offset: usize, length: usize, glyph_count: u16) GsubError!void {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .glyph_count = glyph_count,
        .allow_transient_single_delta = true,
    };
    const major = try readU16BadGsub(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    if (try isEmptyGsubTopology(table)) return;

    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16BadGsub(table, lookup_list_offset);
    try ensureBytesWithin(table, lookup_list_offset + 2, @as(usize, lookup_count) * 2);
    const feature_count = try feature_domain.validation.lookupReferences(table, lookup_count);
    feature_domain.validation.scriptReferences(table, feature_count) catch {};
    for (0..lookup_count) |lookup_i| {
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16BadGsub(table, lookup_list_offset + 2 + lookup_i * 2));
        try ensureLookupHeaderWithin(table, lookup_offset);
        const lookup_type = try readU16BadGsub(table, lookup_offset);
        const subtable_count = try readU16BadGsub(table, lookup_offset + 4);
        if (lookup_type == 4) {
            try ensureLigatureLookupSubtablesWithinForShaping(table, lookup_offset, subtable_count);
        } else {
            try ensureSubstitutionLookupSubtablesWithinForShaping(table, lookup_offset, lookup_type, subtable_count);
        }
    }
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    return feature_domain.run_selection.lookupIndices(
        table,
        allocator,
        options,
    );
}

fn selectedLookupRecords(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!std.ArrayList(SelectedLookup) {
    return feature_domain.run_selection.lookupRecords(
        table,
        allocator,
        options,
    );
}

fn mergedFeatureLookupLessThan(_: void, lhs: MergedFeatureLookup, rhs: MergedFeatureLookup) bool {
    return lhs.lookup < rhs.lookup;
}

fn recordGsubLookupProfile(profile: ?*shape_profile_mod.ShapeStageProfile, lookup_type: u16) void {
    const p = profile orelse return;
    p.gsub_lookup_count += 1;
    switch (lookup_type) {
        1 => p.gsub_single_lookup_count += 1,
        2 => p.gsub_multiple_lookup_count += 1,
        3 => p.gsub_alternate_lookup_count += 1,
        4 => p.gsub_ligature_lookup_count += 1,
        5, 6 => p.gsub_context_lookup_count += 1,
        7 => p.gsub_extension_lookup_count += 1,
        else => {},
    }
}

fn sortUniqueLookupIndices(lookups: *std.ArrayList(u16)) void {
    feature_domain.run_selection.sortUniqueIndices(lookups);
}

fn appendMergedFeatureLookups(
    lookups: *std.ArrayList(MergedFeatureLookup),
    allocator: std.mem.Allocator,
    selected_lookups: []const u16,
    application: FeatureApplication,
) std.mem.Allocator.Error!void {
    const source_mask = if (application.source_scoped)
        sourceFeatureMaskForTag(application.tag) orelse 0
    else
        0;
    for (selected_lookups) |lookup| {
        try lookups.append(allocator, .{
            .lookup = lookup,
            .source_mask = source_mask,
            .auto_zwnj = application.auto_zwnj,
            .auto_zwj = application.auto_zwj,
            .match_source_syllable = application.match_source_syllable,
            .value = application.value,
            .random = featureApplicationIsRandom(application),
        });
    }
}

fn sortMergeFeatureLookups(lookups: *std.ArrayList(MergedFeatureLookup)) void {
    if (lookups.items.len < 2) return;

    std.sort.heap(MergedFeatureLookup, lookups.items, {}, mergedFeatureLookupLessThan);
    var write: usize = 1;
    var previous = lookups.items[0];
    for (lookups.items[1..]) |lookup| {
        if (lookup.lookup == previous.lookup) {
            lookups.items[write - 1].source_mask |= lookup.source_mask;
            lookups.items[write - 1].auto_zwnj = lookups.items[write - 1].auto_zwnj and lookup.auto_zwnj;
            lookups.items[write - 1].auto_zwj = lookups.items[write - 1].auto_zwj and lookup.auto_zwj;
            lookups.items[write - 1].match_source_syllable = lookups.items[write - 1].match_source_syllable or lookup.match_source_syllable;
            if (lookups.items[write - 1].value == 1) lookups.items[write - 1].value = lookup.value;
            lookups.items[write - 1].random = lookups.items[write - 1].random or lookup.random;
        } else {
            lookups.items[write] = lookup;
            write += 1;
            previous = lookup;
        }
    }
    lookups.shrinkRetainingCapacity(write);
}

fn applyLookup(table: Table, lookup_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    try applyLookupWithIndex(table, lookup_offset, null, glyphs, allocator, options, null);
}

fn applyLookupWithIndex(table: Table, lookup_offset: usize, lookup_index: ?u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions, run_digest_cache: ?*RunDigestCache) (GsubError || std.mem.Allocator.Error)!void {
    // The cached Font path overwhelmingly dispatches predecoded ligature and
    // chaining lookups. Keep those cases outside the generic function below:
    // its support for every lookup kind, nested contextual mutation, and
    // profiling windows otherwise forces a roughly 10 KiB stack frame on each
    // tiny lookup invocation even when none of that state is used.
    if ((options.shape_profile == null or options.profile_fast_path) and table.assume_validated) {
        if (try applyValidatedAcceleratedLookup(
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

fn applyValidatedAcceleratedLookup(
    table: Table,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    options: LookupOptions,
    run_digest_cache: ?*RunDigestCache,
) (GsubError || std.mem.Allocator.Error)!bool {
    const accelerator =
        runtime.dispatch.any(lookup_index, options) orelse return false;
    if (accelerator.lookup_offset != lookup_offset or accelerator.lookup_type == 0) return false;
    const lookup_start = shapeProfileNow(options.shape_profile, options.profile_io);
    const glyph_count_before = if (options.shape_profile != null) glyphs.items.len else 0;

    const scoped_syllable =
        runtime.dispatch.matchesSourceSyllable(lookup_index, options);
    if (runtime.dispatch.needsCustomizedOptions(
        accelerator.lookup_flag,
        scoped_syllable,
        options,
    )) {
        // LookupOptions carries all source-parallel shaping metadata and is
        // intentionally large. Materialize a customized copy only for lookups
        // that actually override mark-filtering or syllable scope; ordinary
        // cached lookups can pass the caller's immutable value straight into
        // the prepared dispatcher.
        var customized_options = options;
        if ((accelerator.lookup_flag & 0x0010) != 0) {
            customized_options.active_mark_filtering_set = accelerator.mark_filtering_set;
            try validateMarkFilteringSetIndex(customized_options);
        }
        customized_options.match_source_syllable = scoped_syllable;
        return applyValidatedAcceleratedLookupPrepared(
            table,
            lookup_offset,
            lookup_index,
            glyphs,
            allocator,
            customized_options,
            run_digest_cache,
            accelerator,
            lookup_start,
            glyph_count_before,
        );
    }
    return applyValidatedAcceleratedLookupPrepared(
        table,
        lookup_offset,
        lookup_index,
        glyphs,
        allocator,
        options,
        run_digest_cache,
        accelerator,
        lookup_start,
        glyph_count_before,
    );
}

noinline fn applyValidatedAcceleratedLookupPrepared(
    table: Table,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_options: LookupOptions,
    run_digest_cache: ?*RunDigestCache,
    accelerator: *const LookupAccelerator,
    lookup_start: i128,
    glyph_count_before: usize,
) (GsubError || std.mem.Allocator.Error)!bool {
    switch (accelerator.lookup_type) {
        4 => {
            if (accelerator.subtable_count != 1 or accelerator.ligature_subst.sets.len == 0) return false;
            if (run_digest_cache) |cache| {
                const run_digest = cache.get(glyphs.items, accelerator.lookup_flag, lookup_options);
                if (run_digest.isEmpty() or
                    !accelerator.ligature_subst.first_component_digest.mayIntersect(run_digest))
                {
                    recordAcceleratedGsubLookupProfile(lookup_options, lookup_index, accelerator.lookup_type, lookup_start, glyph_count_before, glyphs.items.len);
                    return true;
                }
            }
            if (accelerator.ligature_subst.prefilter_second) {
                try applyLigatureSubstitutionPrefiltered(
                    table,
                    accelerator.ligature_subst,
                    glyphs,
                    allocator,
                    accelerator.lookup_flag,
                    lookup_options,
                );
            } else if (accelerator.ligature_subst.required_second_len != 0) {
                @branchHint(.unlikely);
                try applyLigatureSubstitutionRequiredSecondPrefiltered(
                    table,
                    accelerator.ligature_subst,
                    glyphs,
                    allocator,
                    accelerator.lookup_flag,
                    lookup_options,
                );
            } else {
                try applyLigatureSubstitutionAccelerated(
                    table,
                    accelerator.ligature_subst,
                    glyphs,
                    allocator,
                    accelerator.lookup_flag,
                    lookup_options,
                );
            }
            recordAcceleratedGsubLookupProfile(lookup_options, lookup_index, accelerator.lookup_type, lookup_start, glyph_count_before, glyphs.items.len);
            return true;
        },
        5 => {
            if (accelerator.context_class_subtables.len != 0) {
                try applyContextClassSubstitutionLookupAccelerated(
                    table,
                    lookup_offset,
                    accelerator.subtable_count,
                    glyphs,
                    allocator,
                    accelerator.lookup_flag,
                    lookup_options,
                    accelerator,
                );
                recordAcceleratedGsubLookupProfile(lookup_options, lookup_index, accelerator.lookup_type, lookup_start, glyph_count_before, glyphs.items.len);
                return true;
            }
            if (accelerator.context_coverage_subtables.len != 0) {
                try applyContextCoverageLookupAccelerated(
                    table,
                    glyphs,
                    allocator,
                    accelerator.lookup_flag,
                    lookup_options,
                    accelerator,
                );
                recordAcceleratedGsubLookupProfile(lookup_options, lookup_index, accelerator.lookup_type, lookup_start, glyph_count_before, glyphs.items.len);
                return true;
            }
            return false;
        },
        6 => {
            if (!accelerator.chaining_coverage_only) return false;
            const run_digest = if (run_digest_cache) |cache|
                cache.get(glyphs.items, accelerator.lookup_flag, lookup_options)
            else
                glyphRunDigest(glyphs.items, accelerator.lookup_flag, lookup_options);
            if (run_digest.isEmpty() or !accelerator.chaining_input_digest.mayIntersect(run_digest)) {
                recordAcceleratedGsubLookupProfile(lookup_options, lookup_index, accelerator.lookup_type, lookup_start, glyph_count_before, glyphs.items.len);
                return true;
            }
            try applyChainingContextSubstitutionLookup(
                table,
                lookup_offset,
                accelerator.subtable_count,
                glyphs,
                allocator,
                accelerator.lookup_flag,
                lookup_options,
                accelerator,
            );
            recordAcceleratedGsubLookupProfile(lookup_options, lookup_index, accelerator.lookup_type, lookup_start, glyph_count_before, glyphs.items.len);
            return true;
        },
        else => return false,
    }
}

fn recordAcceleratedGsubLookupProfile(options: LookupOptions, lookup_index: ?u16, lookup_type: u16, lookup_start: i128, glyph_count_before: usize, glyph_count_after: usize) void {
    const profile = options.shape_profile orelse return;
    recordGsubLookupProfile(profile, lookup_type);
    profile.recordGsubLookupTime(lookup_index, shapeProfileElapsed(lookup_start, options.profile_io));
    profile.recordGsubLookupGlyphs(lookup_index, glyph_count_before, glyph_count_after, 0, 0, glyph_count_before, 0, &.{}, &.{});
}

noinline fn applyLookupWithIndexGeneric(table: Table, lookup_offset: usize, lookup_index: ?u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions, run_digest_cache: ?*RunDigestCache) (GsubError || std.mem.Allocator.Error)!void {
    const profiling = options.shape_profile != null;
    const lookup_start = shapeProfileNow(options.shape_profile, options.profile_io);
    const glyph_count_before = if (profiling) glyphs.items.len else 0;
    const glyph_hash_before = if (profiling) glyphRunHash(glyphs.items) else 0;
    const glyphs_before = if (profiling) try allocator.dupe(GlyphId, glyphs.items) else &.{};
    defer if (profiling) allocator.free(glyphs_before);
    defer {
        if (options.shape_profile) |profile| {
            const first_diff = firstDifferentGlyphIndex(glyphs_before, glyphs.items);
            const window_start = first_diff -| 2;
            const before_window = glyphs_before[window_start..@min(glyphs_before.len, window_start + shape_profile_mod.ShapeStageProfile.lookup_window_capacity)];
            const after_window = glyphs.items[window_start..@min(glyphs.items.len, window_start + shape_profile_mod.ShapeStageProfile.lookup_window_capacity)];
            profile.recordGsubLookupTime(lookup_index, shapeProfileElapsed(lookup_start, options.profile_io));
            profile.recordGsubLookupGlyphs(lookup_index, glyph_count_before, glyphs.items.len, glyph_hash_before, glyphRunHash(glyphs.items), first_diff, window_start, before_window, after_window);
        }
    }
    // Header validation remains coupled to ExtensionSubst payload preflight;
    // dispatch itself only parses fixed fields or trusts an exact sidecar.
    try ensureLookupHeaderWithin(table, lookup_offset);
    const dispatch = try runtime.dispatch.header(
        table,
        lookup_offset,
        lookup_index,
        options,
    );
    const lookup_type = dispatch.lookup_type;
    const lookup_flag = dispatch.lookup_flag;
    const subtable_count = dispatch.subtable_count;
    recordGsubLookupProfile(options.shape_profile, lookup_type);
    // A GSUB lookup is an ordered list of alternative subtables and must apply
    // as one unit. Validate every supported direct subtable before touching the
    // glyph run; otherwise a malformed later subtable can leak substitutions
    // already made by an earlier subtable in the same lookup.
    if (!table.assume_validated) try ensureSubstitutionLookupSubtablesWithin(table, lookup_offset, lookup_type, subtable_count);
    var lookup_options = options;
    if ((lookup_flag & 0x0010) != 0) {
        // UseMarkFilteringSet stores its set index after the variable-length
        // SubTable offset array. The high byte remains reserved for the older
        // MarkAttachmentType mechanism when bit 4 is clear.
        lookup_options.active_mark_filtering_set = dispatch.mark_filtering_set;
        try validateMarkFilteringSetIndex(lookup_options);
    }
    lookup_options.match_source_syllable =
        runtime.dispatch.matchesSourceSyllable(lookup_index, options);
    if (lookup_type == 1) {
        if (runtime.dispatch.singleEntries(
            lookup_index,
            lookup_options,
        )) |entries| {
            applySingleSubstitutionEntries(entries, glyphs, lookup_flag, lookup_options);
            return;
        }
        try applySingleSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 2) {
        if (runtime.dispatch.multiple(
            lookup_index,
            lookup_options,
        )) |accelerator| {
            try applyMultipleSubstitutionAccelerated(table, accelerator.*, glyphs, allocator, lookup_flag, lookup_options);
            return;
        }
        try applyMultipleSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 3) {
        try applyAlternateSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 7) {
        // ExtensionSubst is only an addressing wrapper, but malformed wrapped
        // payloads can otherwise be discovered after an earlier wrapper in the
        // same lookup has already substituted glyphs. Preflight every wrapper
        // before choosing the optimized homogeneous path below so the lookup
        // remains all-or-nothing for truncated variable arrays.
        if (!table.assume_validated) try ensureExtensionSubstitutionLookupPayloadsWithin(table, lookup_offset, subtable_count);
        const wrapped_type = if (runtime.dispatch.extensionType(
            lookup_index,
            lookup_options,
        )) |accelerator|
            accelerator.extension_lookup_type orelse 0
        else
            try accelerator_root.build.lookup.extension.commonType(
                table,
                lookup_offset,
                subtable_count,
            ) orelse 0;
        switch (wrapped_type) {
            1 => {
                try applyExtensionSingleSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
                return;
            },
            2 => {
                try applyExtensionMultipleSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
                return;
            },
            3 => {
                try applyExtensionAlternateSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
                return;
            },
            5 => {
                if (runtime.dispatch.contextClass(
                    lookup_index,
                    lookup_options,
                )) |accelerator| {
                    try applyExtensionContextClassSubstitutionLookupAccelerated(table, subtable_count, glyphs, allocator, lookup_flag, lookup_options, accelerator);
                } else {
                    try applyExtensionContextSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
                }
                return;
            },
            6 => {
                if (runtime.dispatch.chainingClass(
                    lookup_index,
                    lookup_options,
                )) |accelerator| {
                    try applyExtensionChainingClassSubstitutionLookupAccelerated(table, subtable_count, glyphs, allocator, lookup_flag, lookup_options, accelerator);
                } else if (runtime.dispatch.chainingCoverage(
                    lookup_index,
                    lookup_options,
                )) |accelerator| {
                    try applyChainingContextSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options, accelerator);
                } else {
                    try applyExtensionChainingContextSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options);
                }
                return;
            },
            8 => {
                try applyExtensionReverseChainingSingleSubstitutionLookup(
                    table,
                    lookup_offset,
                    subtable_count,
                    glyphs,
                    lookup_flag,
                    lookup_options,
                    runtime.dispatch.reverseChaining(
                        lookup_index,
                        lookup_options,
                    ),
                );
                return;
            },
            else => {},
        }
    }
    if (lookup_type == 5) {
        if (runtime.dispatch.contextClass(
            lookup_index,
            lookup_options,
        )) |accelerator| {
            try applyContextClassSubstitutionLookupAccelerated(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options, accelerator);
            return;
        }
        if (runtime.dispatch.contextCoverage(
            lookup_index,
            lookup_options,
        )) |accelerator| {
            try applyContextCoverageLookupAccelerated(
                table,
                glyphs,
                allocator,
                lookup_flag,
                lookup_options,
                accelerator,
            );
            return;
        }
        try applyContextSubstitutionLookup(
            table,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            lookup_options,
        );
        return;
    }
    if (lookup_type == 6) {
        if (runtime.dispatch.chainingClass(
            lookup_index,
            lookup_options,
        )) |accelerator| {
            try applyChainingClassSubstitutionLookupAccelerated(
                table,
                subtable_count,
                glyphs,
                allocator,
                lookup_flag,
                lookup_options,
                accelerator,
            );
            return;
        }
        if (runtime.dispatch.chainingCoverage(
            lookup_index,
            lookup_options,
        )) |accelerator| {
            const run_digest = if (run_digest_cache) |cache|
                cache.get(glyphs.items, lookup_flag, lookup_options)
            else
                glyphRunDigest(glyphs.items, lookup_flag, lookup_options);
            if (run_digest.isEmpty() or !accelerator.chaining_input_digest.mayIntersect(run_digest)) return;
            try applyChainingContextSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options, accelerator);
            return;
        }
        if (try accelerator_root.build.chaining_coverage.lookupUsesCoverageOnly(table, lookup_offset, subtable_count, false)) {
            if (!try chainingCoverageLookupMayMatch(table, lookup_offset, subtable_count, glyphs.items, lookup_flag, lookup_options)) return;
            try applyChainingContextSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options, null);
            return;
        }
        // Mixed glyph/class/coverage lookups still require position-major
        // dispatch: subtables are ordered alternatives for one candidate, not
        // independent whole-run passes. The generic dispatcher preserves that
        // ordering without requiring a format-specific accelerator.
        try applyChainingContextSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, allocator, lookup_flag, lookup_options, null);
        return;
    }
    if (lookup_type == 4 and subtable_count == 1) {
        if (runtime.dispatch.ligature(
            lookup_index,
            lookup_options,
        )) |accelerator| {
            if (run_digest_cache) |cache| {
                const run_digest = cache.get(glyphs.items, lookup_flag, lookup_options);
                if (run_digest.isEmpty() or
                    !accelerator.first_component_digest.mayIntersect(run_digest))
                {
                    return;
                }
            }
            if (accelerator.prefilter_second) {
                try applyLigatureSubstitutionPrefiltered(table, accelerator.*, glyphs, allocator, lookup_flag, lookup_options);
            } else if (accelerator.required_second_len != 0) {
                @branchHint(.unlikely);
                try applyLigatureSubstitutionRequiredSecondPrefiltered(table, accelerator.*, glyphs, allocator, lookup_flag, lookup_options);
            } else {
                try applyLigatureSubstitutionAccelerated(table, accelerator.*, glyphs, allocator, lookup_flag, lookup_options);
            }
            return;
        }
    }

    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => {}, // SingleSubst needs whole-lookup ordering; handled below.
            2 => {}, // MultipleSubst needs per-position subtable ordering; handled above.
            3 => {}, // AlternateSubst needs whole-lookup ordering; handled above.
            4 => try applyLigatureSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, lookup_options),
            5 => unreachable, // ContextSubst needs position-major subtable ordering.
            6 => unreachable, // ChainingContextSubst is handled position-major above.
            7 => try applyExtensionSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, lookup_options),
            8 => {}, // ReverseChainSingleSubst needs whole-lookup ordering; handled below.
            else => {},
        }
    }
    if (lookup_type == 8) {
        try applyReverseChainingSingleSubstitutionLookup(table, lookup_offset, subtable_count, glyphs, lookup_flag, lookup_options);
    }
}

fn glyphRunHash(glyphs: []const GlyphId) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (glyphs) |glyph| {
        hash ^= glyph;
        hash *%= 0x100000001b3;
    }
    return hash;
}

fn firstDifferentGlyphIndex(before: []const GlyphId, after: []const GlyphId) usize {
    const len = @min(before.len, after.len);
    for (0..len) |index| {
        if (before[index] != after[index]) return index;
    }
    return len;
}

fn optionsWithRunDigestGeneration(options: LookupOptions, generation: *usize) LookupOptions {
    var result = options;
    if (runtime.dispatch.tableUsesRunDigestCache(
        result.lookup_accelerators,
    ) and result.glyph_mutation_generation == null) {
        result.glyph_mutation_generation = generation;
    }
    return result;
}

fn optionsWithTopLevelState(
    options: LookupOptions,
    initial_glyph_count: usize,
    mutation_generation: *usize,
    operations_left: *usize,
) GsubError!LookupOptions {
    var result = optionsWithRunDigestGeneration(options, mutation_generation);
    if (result.operations_left == null) {
        const limits = try runtime.Limits.init(initial_glyph_count);
        operations_left.* = limits.operations_left;
        result.operations_left = operations_left;
        if (result.max_glyph_count == null) result.max_glyph_count = limits.max_glyph_count;
    } else if (result.max_glyph_count == null) {
        result.max_glyph_count = (try runtime.Limits.init(initial_glyph_count)).max_glyph_count;
    }
    return result;
}

fn consumeGsubMutationBudget(
    options: LookupOptions,
    current_glyph_count: usize,
    removed_len: usize,
    inserted_len: usize,
) GsubError!void {
    if (removed_len > current_glyph_count) return error.InvalidShapingInput;
    const retained = current_glyph_count - removed_len;
    const new_glyph_count = std.math.add(usize, retained, inserted_len) catch return error.ShapingLimitExceeded;
    if (options.max_glyph_count) |limit| {
        if (new_glyph_count > limit) return error.ShapingLimitExceeded;
    }
    if (options.operations_left) |operations_left| {
        // HarfBuzz charges one recursive lookup operation here; its separate
        // glyph-count ceiling bounds expansion. Keep the same semantic budget
        // so legitimate long MultipleSubst-heavy corpora are not rejected
        // merely because ArrayList uses a different physical representation.
        const charge: usize = 1;
        if (charge > operations_left.*) return error.ShapingLimitExceeded;
        operations_left.* -= charge;
    }
}

fn consumeNestedGsubOperation(options: LookupOptions) GsubError!void {
    const operations_left = options.operations_left orelse return;
    if (operations_left.* == 0) return error.ShapingLimitExceeded;
    operations_left.* -= 1;
}

fn extensionSubtablePayload(table: Table, subtable_offset: usize, expected_lookup_type: u16) GsubError!usize {
    return accelerator_root.build.lookup.extension.payload(
        table,
        subtable_offset,
        expected_lookup_type,
    );
}

const stack_matched_capacity = 128;

const BoolScratch = struct {
    items: []bool,
    heap: ?[]bool = null,

    fn init(allocator: std.mem.Allocator, len: usize, stack: *[stack_matched_capacity]bool) (GsubError || std.mem.Allocator.Error)!BoolScratch {
        const items = if (len <= stack.len)
            stack[0..len]
        else {
            const heap = try allocator.alloc(bool, len);
            return .{ .items = heap, .heap = heap };
        };
        return .{ .items = items };
    }

    fn deinit(self: BoolScratch, allocator: std.mem.Allocator) void {
        if (self.heap) |heap| allocator.free(heap);
    }
};

fn applyExtensionSingleSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    if (subtable_count == 1) {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6);
        const extension_subtable = try extensionSubtablePayload(table, subtable_offset, 1);
        try applySingleSubstitution(table, extension_subtable, glyphs, lookup_flag, options);
        return;
    }

    // ExtensionSubst only widens subtable offsets; homogeneous wrapped
    // SingleSubst subtables are still ordered alternatives within one lookup.
    // Track physical positions matched by earlier wrapped subtables so a
    // replacement glyph cannot cascade into a later ExtensionSubst wrapper.
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const matched_scratch = try BoolScratch.init(allocator, glyphs.items.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    const matched = matched_scratch.items;
    @memset(matched, false);

    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        const extension_subtable = try extensionSubtablePayload(table, subtable_offset, 1);
        try applySingleSubstitutionSubtable(table, extension_subtable, glyphs, lookup_flag, options, matched);
    }
}

fn applyAlternateSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    // As with SingleSubst, AlternateSubst subtables in one lookup are ordered
    // alternatives for each input position. A glyph chosen from an earlier
    // alternate set must not be reconsidered by later subtables in the same
    // lookup, even if that replacement glyph is covered there.
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const matched_scratch = try BoolScratch.init(allocator, glyphs.items.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    const matched = matched_scratch.items;
    @memset(matched, false);

    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        try applyAlternateSubstitutionSubtable(table, subtable_offset, glyphs, lookup_flag, options, matched);
    }
}

fn applyExtensionAlternateSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    // Match direct AlternateSubst lookup ordering through ExtensionSubst: the
    // chosen alternate for one original glyph is final for this lookup, even if
    // that alternate is covered by a later wrapped subtable.
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const matched_scratch = try BoolScratch.init(allocator, glyphs.items.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    const matched = matched_scratch.items;
    @memset(matched, false);

    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        const extension_subtable = try extensionSubtablePayload(table, subtable_offset, 3);
        try applyAlternateSubstitutionSubtable(table, extension_subtable, glyphs, lookup_flag, options, matched);
    }
}

fn applyMultipleSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    if (subtable_count == 1) {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6);
        try applyMultipleSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options);
        return;
    }

    // MultipleSubst can change cardinality, but lookup subtables are still
    // alternatives for a single original input position. Process one target
    // position through the subtable list before advancing, so a replacement
    // glyph produced by an earlier subtable is not fed into a later subtable in
    // the same lookup.
    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) {
        if (!sourceFeatureAllowsGlyph(options, glyph_index)) {
            glyph_index += 1;
            continue;
        }
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[glyph_index])) {
            glyph_index += 1;
            continue;
        }

        var matched = false;
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            if (try applyMultipleSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, options)) |change| {
                // Advance past the glyphs inserted for this original input.
                // For deletion, stay at the same physical index so the next
                // original glyph that shifted left is considered from the
                // first subtable on the next loop iteration.
                glyph_index += change.inserted_len;
                matched = true;
                break;
            }
        }
        if (!matched) glyph_index += 1;
    }
}

fn applyExtensionMultipleSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    if (subtable_count == 1) {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6);
        const extension_subtable = try extensionSubtablePayload(table, subtable_offset, 2);
        try applyMultipleSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options);
        return;
    }

    // Homogeneous ExtensionSubst(MultipleSubst) lookups need the same
    // per-position ordering as direct MultipleSubst. Delegating each extension
    // subtable over the whole run would allow 10=>20 in subtable 0 to cascade
    // into 20=>[...] in subtable 1, even though both subtables belong to one
    // lookup and should be alternatives for the original glyph.
    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) {
        if (!sourceFeatureAllowsGlyph(options, glyph_index)) {
            glyph_index += 1;
            continue;
        }
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[glyph_index])) {
            glyph_index += 1;
            continue;
        }

        var matched = false;
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            if (try applyNestedExtensionSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, options)) |change| {
                glyph_index += change.inserted_len;
                matched = true;
                break;
            }
        }
        if (!matched) glyph_index += 1;
    }
}

fn applySingleSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    if (subtable_count == 1) {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6);
        try applySingleSubstitution(table, subtable_offset, glyphs, lookup_flag, options);
        return;
    }

    // OpenType lookup subtables are ordered alternatives for a lookup. A glyph
    // that matched an earlier SingleSubst subtable must not be fed into later
    // subtables in the same lookup; otherwise fonts that split disjoint rules
    // into subtables can accidentally cascade (for example 10->20 then 20->30).
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const matched_scratch = try BoolScratch.init(allocator, glyphs.items.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    const matched = matched_scratch.items;
    @memset(matched, false);

    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        try applySingleSubstitutionSubtable(table, subtable_offset, glyphs, lookup_flag, options, matched);
    }
}

fn applySingleSubstitutionEntries(entries: []const SingleSubstEntry, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions) void {
    for (glyphs.items, 0..) |*glyph, glyph_index| {
        if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
        const entry = singleSubstEntryForGlyph(entries, glyph.*) orelse continue;
        glyph.* = entry.to;
        markGlyphSubstituted(options, glyph_index);
    }
}

fn singleSubstEntryForGlyph(entries: []const SingleSubstEntry, glyph: GlyphId) ?SingleSubstEntry {
    var lo: usize = 0;
    var hi: usize = entries.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const candidate = entries[mid].from;
        if (glyph < candidate) {
            hi = mid;
        } else if (glyph > candidate) {
            lo = mid + 1;
        } else {
            return entries[mid];
        }
    }
    return null;
}

test "GSUB native single substitution entries preserve coverage mapping and flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;

    writeU16Test(&bytes, 0, 2); // SingleSubst format 2.
    writeU16Test(&bytes, 2, 12);
    writeU16Test(&bytes, 4, 3);
    writeU16Test(&bytes, 6, 30);
    writeU16Test(&bytes, 8, 31);
    writeU16Test(&bytes, 10, 40);

    writeU16Test(&bytes, 12, 2); // Coverage format 2.
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 10);
    writeU16Test(&bytes, 18, 11);
    writeU16Test(&bytes, 20, 0);
    writeU16Test(&bytes, 22, 20);
    writeU16Test(&bytes, 24, 20);
    writeU16Test(&bytes, 26, 2);

    const entries = try buildSingleSubstEntries(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        allocator,
    );
    defer allocator.free(entries);
    try std.testing.expectEqual(@as(usize, 3), entries.len);
    try std.testing.expectEqual(SingleSubstEntry{ .from = 10, .to = 30 }, entries[0]);
    try std.testing.expectEqual(SingleSubstEntry{ .from = 11, .to = 31 }, entries[1]);
    try std.testing.expectEqual(SingleSubstEntry{ .from = 20, .to = 40 }, entries[2]);
    try std.testing.expect(singleSubstEntryForGlyph(entries, 19) == null);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 9, 10, 11, 20, 21 });
    var glyph_classes = [_]u16{0} ** 22;
    glyph_classes[11] = 3;
    applySingleSubstitutionEntries(entries, &glyphs, 0x0008, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{ 9, 30, 11, 40, 21 }, glyphs.items);
}

fn applySingleSubstitutionSubtable(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions, matched: []bool) GsubError!void {
    const subst_format = try readU16(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    switch (subst_format) {
        1 => {
            const delta = try readI16(table, subtable_offset + 4);
            for (glyphs.items, 0..) |*glyph, glyph_index| {
                if (matched[glyph_index]) continue;
                if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
                if (try table_core.coverage.index(table, coverage_offset, glyph.*) != null) {
                    glyph.* = @bitCast(@as(i16, @bitCast(glyph.*)) +% delta);
                    markGlyphSubstituted(options, glyph_index);
                    matched[glyph_index] = true;
                }
            }
        },
        2 => {
            const glyph_count = try readU16(table, subtable_offset + 4);
            for (glyphs.items, 0..) |*glyph, glyph_index| {
                if (matched[glyph_index]) continue;
                if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
                if (try table_core.coverage.index(table, coverage_offset, glyph.*)) |index| {
                    if (index < glyph_count) {
                        glyph.* = try readU16(table, subtable_offset + 6 + index * 2);
                        markGlyphSubstituted(options, glyph_index);
                        matched[glyph_index] = true;
                    }
                }
            }
        },
        else => return error.UnsupportedGsub,
    }
}

fn applySingleSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions) GsubError!void {
    const subst_format = try readU16(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    switch (subst_format) {
        1 => {
            const delta = try readI16(table, subtable_offset + 4);
            for (glyphs.items, 0..) |*glyph, glyph_index| {
                if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
                if (try table_core.coverage.index(table, coverage_offset, glyph.*) != null) {
                    glyph.* = @bitCast(@as(i16, @bitCast(glyph.*)) +% delta);
                    markGlyphSubstituted(options, glyph_index);
                }
            }
        },
        2 => {
            const glyph_count = try readU16(table, subtable_offset + 4);
            for (glyphs.items, 0..) |*glyph, glyph_index| {
                if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
                if (try table_core.coverage.index(table, coverage_offset, glyph.*)) |index| {
                    if (index < glyph_count) {
                        glyph.* = try readU16(table, subtable_offset + 6 + index * 2);
                        markGlyphSubstituted(options, glyph_index);
                    }
                }
            }
        },
        else => return error.UnsupportedGsub,
    }
}

fn applySingleSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, lookup_flag: u16, options: LookupOptions) GsubError!bool {
    if (glyph_index >= glyphs.items.len) return false;
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[glyph_index])) return false;
    const subst_format = try readU16(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    switch (subst_format) {
        1 => {
            const delta = try readI16(table, subtable_offset + 4);
            if (try table_core.coverage.index(table, coverage_offset, glyphs.items[glyph_index]) == null) return false;
            glyphs.items[glyph_index] = @bitCast(@as(i16, @bitCast(glyphs.items[glyph_index])) +% delta);
            markGlyphSubstituted(options, glyph_index);
            return true;
        },
        2 => {
            const glyph_count = try readU16(table, subtable_offset + 4);
            const coverage = try table_core.coverage.index(table, coverage_offset, glyphs.items[glyph_index]) orelse return false;
            if (coverage >= glyph_count) return false;
            glyphs.items[glyph_index] = try readU16(table, subtable_offset + 6 + coverage * 2);
            markGlyphSubstituted(options, glyph_index);
            return true;
        },
        else => return error.UnsupportedGsub,
    }
}

fn applySingleSubstitutionAccelerated(table: Table, accelerator: SingleSubstAccelerator, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, options: LookupOptions) GsubError!bool {
    if (!accelerator.enabled) return false;
    if (glyph_index >= glyphs.items.len) return false;
    if (lookupIgnoresGlyph(0, options, glyphs.items[glyph_index])) return false;
    if (accelerator.single_mapping) {
        if (glyphs.items[glyph_index] != accelerator.single_from) return false;
        glyphs.items[glyph_index] = accelerator.single_to;
        markGlyphSubstituted(options, glyph_index);
        return true;
    }
    switch (accelerator.subst_format) {
        1 => {
            if (try table_core.coverage.index(table, accelerator.coverage_offset, glyphs.items[glyph_index]) == null) return false;
            glyphs.items[glyph_index] = @bitCast(@as(i16, @bitCast(glyphs.items[glyph_index])) +% accelerator.delta);
            markGlyphSubstituted(options, glyph_index);
            return true;
        },
        2 => {
            const coverage = try table_core.coverage.index(table, accelerator.coverage_offset, glyphs.items[glyph_index]) orelse return false;
            if (coverage >= accelerator.glyph_count) return false;
            glyphs.items[glyph_index] = try readU16(table, accelerator.substitutes_pos + coverage * 2);
            markGlyphSubstituted(options, glyph_index);
            return true;
        },
        else => return false,
    }
}

inline fn lookupIgnoresGlyph(lookup_flag: u16, options: LookupOptions, glyph: GlyphId) bool {
    if (lookup_flag == 0) return false;
    const classes = options.glyph_classes;
    const class = if (classes) |items| if (glyph < items.len) items[glyph] else 0 else 0;
    if (lookup_flag == 0x0008) return class == 3;
    return lookupIgnoresGlyphComplex(lookup_flag, options, glyph, class);
}

noinline fn lookupIgnoresGlyphComplex(lookup_flag: u16, options: LookupOptions, glyph: GlyphId, class: u16) bool {
    // UseMarkFilteringSet appends a set index after the SubTable offsets; it
    // does not consume the high-byte MarkAttachmentType bits. Apply both mark
    // filters independently so a lookup can require a selected mark set and a
    // selected GDEF mark attachment class at the same time.
    if ((lookup_flag & 0x0010) != 0) {
        const mark_filtering_set_index = options.active_mark_filtering_set orelse return class == 3;
        const mark_sets = options.mark_filtering_sets orelse return class == 3;
        if (mark_filtering_set_index >= mark_sets.len) return class == 3;
        const in_selected_set = glyphInMarkFilteringSet(mark_sets[mark_filtering_set_index], glyph);
        const is_mark = class == 3;
        if (is_mark and !in_selected_set) return true;
    }

    if (options.glyph_classes != null) {
        if ((lookup_flag & 0x0002) != 0 and class == 1) return true;
        if ((lookup_flag & 0x0004) != 0 and class == 2) return true;
        if ((lookup_flag & 0x0008) != 0 and class == 3) return true;
    }
    const mark_attachment_type = lookup_flag >> 8;
    if (mark_attachment_type != 0) {
        const attach_classes = options.mark_attach_classes orelse return class == 3;
        if (glyph >= attach_classes.len) return class == 3;
        const attach_class = attach_classes[glyph];
        // MarkAttachClassDef is mark-only data. Some fonts provide it without a
        // useful GlyphClassDef; treat non-zero attachment classes as marks for
        // MarkAttachmentType filtering while still letting an explicit mark
        // glyph class cover attachment class zero.
        const is_mark = class == 3 or (class == 0 and attach_class != 0);
        if (!is_mark) return false;
        return attach_class != mark_attachment_type;
    }
    return false;
}

fn glyphInMarkFilteringSet(glyphs: []const GlyphId, glyph: GlyphId) bool {
    for (glyphs) |candidate| {
        if (candidate == glyph) return true;
    }
    return false;
}

fn validateMarkFilteringSetIndex(options: LookupOptions) GsubError!void {
    const mark_filtering_set_index = options.active_mark_filtering_set orelse return;
    const mark_sets = options.mark_filtering_sets orelse return;
    // A lookup that names a non-existent GDEF MarkGlyphSetsDef entry is
    // malformed. Silently falling back to glyph-class metadata makes
    // substitution depend on missing state instead of the font's declared
    // lookup flag contract.
    if (mark_filtering_set_index >= mark_sets.len) return error.BadGsub;
}

fn shapeProfileNow(profile: ?*shape_profile_mod.ShapeStageProfile, io: ?std.Io) i128 {
    return if (profile != null) std.Io.Clock.now(.awake, io.?).nanoseconds else 0;
}

fn shapeProfileElapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}

fn sourceForGlyph(options: LookupOptions, glyph_index: usize) usize {
    const sources = options.glyph_source_indices orelse return glyph_index;
    if (glyph_index >= sources.items.len) return glyph_index;
    return sources.items[glyph_index];
}

fn clusterForGlyph(options: LookupOptions, glyph_index: usize) usize {
    const clusters = options.glyph_cluster_indices orelse return sourceForGlyph(options, glyph_index);
    if (glyph_index >= clusters.items.len) return sourceForGlyph(options, glyph_index);
    return clusters.items[glyph_index];
}

fn sourceFeatureAllowsGlyph(options: LookupOptions, glyph_index: usize) bool {
    if (options.active_source_feature_mask == 0 and options.active_source_feature == null) return true;
    const features = options.source_features orelse return false;
    const source = sourceForGlyph(options, glyph_index);
    if (source >= features.len) return false;
    const assigned = features[source];
    if ((assigned & source_feature_mask_marker) != 0) {
        const active_mask = if (options.active_source_feature_mask != 0)
            options.active_source_feature_mask
        else
            sourceFeatureMaskForTag(options.active_source_feature.?) orelse return false;
        return (assigned & (active_mask & ~source_feature_mask_marker)) != 0;
    }
    const active = options.active_source_feature orelse return false;
    return assigned == active;
}

fn sourceCodepointForGlyph(options: LookupOptions, glyph_index: usize) ?u21 {
    const codepoints = options.source_codepoints orelse return null;
    const source = sourceForGlyph(options, glyph_index);
    if (source >= codepoints.len) return null;
    return codepoints[source];
}

fn sourceSyllableForGlyph(options: LookupOptions, glyph_index: usize) ?u8 {
    if (!options.match_source_syllable) return null;
    const syllables = options.source_syllables orelse return null;
    const source = sourceForGlyph(options, glyph_index);
    if (source >= syllables.len) return null;
    return syllables[source];
}

fn sourceSyllableAllowsGlyph(options: LookupOptions, anchor_syllable: ?u8, glyph_index: usize) bool {
    const anchor = anchor_syllable orelse return true;
    return sourceSyllableForGlyph(options, glyph_index) == anchor;
}

fn glyphWasSubstituted(options: LookupOptions, glyph_index: usize) bool {
    const substituted = options.glyph_substituted orelse return false;
    return glyph_index < substituted.items.len and substituted.items[glyph_index];
}

fn markGlyphSubstituted(options: LookupOptions, glyph_index: usize) void {
    noteGlyphMutation(options);
    if (options.glyph_substituted) |substituted| {
        if (glyph_index < substituted.items.len) substituted.items[glyph_index] = true;
    }
    if (options.glyph_stage_substituted) |substituted| {
        if (glyph_index < substituted.items.len) substituted.items[glyph_index] = true;
    }
}

fn noteGlyphMutation(options: LookupOptions) void {
    const generation = options.glyph_mutation_generation orelse return;
    generation.* +%= 1;
}

fn contextualMaySkipGlyph(lookup_flag: u16, options: LookupOptions, glyphs: []const GlyphId, glyph_index: usize, context_match: bool) bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[glyph_index])) return true;
    const codepoint = sourceCodepointForGlyph(options, glyph_index) orelse return false;
    if (options.visible_variation_selectors and unicode.isVariationSelector(codepoint)) return false;
    // Mongolian FVS characters are hidden only after shaping. HarfBuzz marks
    // them as non-skippable “hidden” default-ignorables during GSUB so fonts
    // can consume them in a ligature or let an unconsumed selector block a
    // contextual match. This is independent of whether cmap supplied a real
    // selector glyph; final output handling still hides an untouched FVS.
    if (unicode.isMongolianFreeVariationSelector(codepoint)) return false;
    // CGJ is always transparent to OpenType matching: unlike ZWNJ/ZWJ, it has
    // no feature-specific auto-joiner mode and must never become an input or
    // ligature component merely because the lookup is matching its input run.
    if (codepoint == 0x034f) return true;
    if (!context_match) return false;
    // Mongolian Vowel Separator is default-ignorable, but Mongolian fonts may
    // name it explicitly in contextual backtrack/lookahead. HarfBuzz treats
    // default-ignorables as maybe-skippable; keeping U+180E visible here lets
    // explicit MVS rules match instead of being skipped unconditionally.
    if (codepoint == 0x180e) return false;
    if (glyphWasSubstituted(options, glyph_index)) return false;
    if (!unicode.isDefaultIgnorableForShaping(codepoint)) return false;
    if (codepoint == 0x200c and !options.active_auto_zwnj) return false;
    if (codepoint == 0x200d and !options.active_auto_zwj) return false;
    return true;
}

fn ligatureMaySkipGlyph(lookup_flag: u16, options: LookupOptions, glyphs: []const GlyphId, glyph_base: usize, relative_index: usize) bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[relative_index])) return true;
    const codepoint = sourceCodepointForGlyph(options, glyph_base + relative_index) orelse return false;
    if (codepoint == 0x034f) return !cgjPreventedMarkReorder(options, glyph_base + relative_index);
    if (unicode.isMongolianFreeVariationSelector(codepoint)) return false;
    return !options.visible_variation_selectors and glyphs[relative_index] == 0 and unicode.isVariationSelector(codepoint);
}

fn ligatureAnchorSyllable(options: LookupOptions, glyph_base: usize) ?u8 {
    return sourceSyllableForGlyph(options, glyph_base);
}

fn ligatureAllowsRelativeGlyph(options: LookupOptions, anchor_syllable: ?u8, glyph_base: usize, relative_index: usize) bool {
    return sourceSyllableAllowsGlyph(options, anchor_syllable, glyph_base + relative_index);
}

fn cgjPreventedMarkReorder(options: LookupOptions, glyph_index: usize) bool {
    const sources = options.glyph_source_indices orelse return false;
    const codepoints = options.source_codepoints orelse return false;
    if (glyph_index == 0 or glyph_index + 1 >= sources.items.len) return false;
    const prev_source = sources.items[glyph_index - 1];
    const next_source = sources.items[glyph_index + 1];
    if (prev_source >= codepoints.len or next_source >= codepoints.len) return false;
    const prev_class = unicode.modifiedCombiningClassForShaping(codepoints[prev_source]);
    const next_class = unicode.modifiedCombiningClassForShaping(codepoints[next_source]);
    return next_class != 0 and prev_class > next_class;
}

fn replaceSourceMetadata(allocator: std.mem.Allocator, options: LookupOptions, glyph_index: usize, removed_len: usize, inserted_len: usize, source: usize) std.mem.Allocator.Error!void {
    const cluster = clusterForGlyph(options, glyph_index);
    var component_info: ligature_provenance.Info = if (options.ligature_components) |store|
        if (glyph_index < store.infos.items.len)
            store.infos.items[glyph_index]
        else
            .{}
    else
        .{};
    if (inserted_len > 1) {
        component_info.flags.multiplied = true;
        component_info.flags.multiple_component = 0;
    }
    if (options.glyph_source_indices) |sources| {
        if (glyph_index <= sources.items.len) {
            const remove_count = @min(removed_len, sources.items.len - glyph_index);
            const replacements = try allocator.alloc(usize, inserted_len);
            defer allocator.free(replacements);
            @memset(replacements, source);
            try sources.replaceRange(allocator, glyph_index, remove_count, replacements);
        }
    }
    if (options.glyph_cluster_indices) |clusters| {
        if (glyph_index <= clusters.items.len) {
            const remove_count = @min(removed_len, clusters.items.len - glyph_index);
            const replacements = try allocator.alloc(usize, inserted_len);
            defer allocator.free(replacements);
            @memset(replacements, cluster);
            try clusters.replaceRange(allocator, glyph_index, remove_count, replacements);
        }
    }
    if (options.glyph_substituted) |substituted| {
        if (glyph_index <= substituted.items.len) {
            const remove_count = @min(removed_len, substituted.items.len - glyph_index);
            const replacements = try allocator.alloc(bool, inserted_len);
            defer allocator.free(replacements);
            @memset(replacements, true);
            try substituted.replaceRange(allocator, glyph_index, remove_count, replacements);
        }
    }
    if (options.glyph_stage_substituted) |substituted| {
        if (glyph_index <= substituted.items.len) {
            const remove_count = @min(removed_len, substituted.items.len - glyph_index);
            const replacements = try allocator.alloc(bool, inserted_len);
            defer allocator.free(replacements);
            @memset(replacements, true);
            try substituted.replaceRange(allocator, glyph_index, remove_count, replacements);
        }
    }
    if (options.ligature_components) |store| {
        if (glyph_index <= store.infos.items.len) {
            const remove_count = @min(removed_len, store.infos.items.len - glyph_index);
            const replacements = try allocator.alloc(ligature_provenance.Info, inserted_len);
            defer allocator.free(replacements);
            // MultipleSubst can decompose a glyph produced by a ligature. Each
            // output remains ligated in HarfBuzz, which matters to script
            // reorder (a decomposed halant-looking glyph is not a live
            // halant) and later mark attachment. Preserve that provenance
            // across every replacement component instead of resetting it to a
            // one-source glyph.
            for (replacements, 0..) |*replacement, replacement_index| {
                replacement.* = component_info;
                replacement.flags.multiple_component = @intCast(@min(replacement_index, 0x0f));
            }
            try store.infos.replaceRange(allocator, glyph_index, remove_count, replacements);
        }
    }
}

fn mergeLigatureClusterMetadata(options: LookupOptions, glyph_index: usize, match: LigatureMatch) void {
    const clusters = options.glyph_cluster_indices orelse return;
    if (glyph_index >= clusters.items.len) return;
    switch (options.cluster_level) {
        .monotone_graphemes, .monotone_characters => shaping_metadata.mergeMonotoneClusters(clusters.items, glyph_index, glyph_index + match.match_end),
        .characters, .graphemes => {},
    }
    mergeFollowingMarksForLigatureCluster(options, glyph_index, match);
}

fn mergeFollowingMarksForLigatureCluster(options: LookupOptions, glyph_index: usize, match: LigatureMatch) void {
    const clusters = options.glyph_cluster_indices orelse return;
    const sources = options.glyph_source_indices orelse return;
    if (glyph_index >= clusters.items.len or glyph_index >= sources.items.len) return;
    if (match.component_count <= 1) return;

    const last_component = glyph_index + match.component_offsets[match.component_count - 1];
    if (last_component >= clusters.items.len or last_component >= sources.items.len) return;
    const last_source = sources.items[last_component];
    const merged_cluster = clusters.items[glyph_index];

    var index = glyph_index + match.match_end;
    while (index < clusters.items.len and index < sources.items.len) : (index += 1) {
        if (sources.items[index] != last_source) break;
        if (clusters.items[index] != last_source) break;
        clusters.items[index] = merged_cluster;
    }
}

fn ligatureComponentInfoForMatch(
    allocator: std.mem.Allocator,
    options: LookupOptions,
    glyph_index: usize,
    match: LigatureMatch,
) std.mem.Allocator.Error!ligature_provenance.Info {
    const store = options.ligature_components orelse return .{};
    const matched_component_count = @min(match.component_count, ligature_provenance.max_components);
    if (matched_component_count <= 1) return .{};
    var all_sources: [ligature_provenance.max_components]usize = undefined;
    var all_source_count: usize = 0;
    var logical_sources: [ligature_provenance.max_components]usize = undefined;
    var logical_component_count: usize = 0;
    appendLigatureSourcesForMatch(
        all_sources[0..],
        &all_source_count,
        logical_sources[0..],
        &logical_component_count,
        options,
        glyph_index,
    );
    var synthetic_base = false;
    if (glyph_index < store.infos.items.len) {
        synthetic_base = store.infos.items[glyph_index].flags.synthetic_base;
    }
    for (1..matched_component_count) |component_index| {
        const matched_index = glyph_index + match.component_offsets[component_index];
        appendLigatureSourcesForMatch(
            all_sources[0..],
            &all_source_count,
            logical_sources[0..],
            &logical_component_count,
            options,
            matched_index,
        );
        if (matched_index < store.infos.items.len) {
            synthetic_base = synthetic_base or store.infos.items[matched_index].flags.synthetic_base;
        }
    }
    std.debug.assert(logical_component_count != 0);
    const base_mark_ligature = ligatureIsBaseWithMarks(
        options,
        glyph_index,
        match,
        matched_component_count,
    );
    var info = if (all_source_count > 1)
        try store.addLigatureWithSources(
            allocator,
            all_sources[0..all_source_count],
            logical_sources[0..logical_component_count],
        )
    else
        ligature_provenance.Info{
            .component_count = @intCast(logical_component_count),
            .flags = .{ .ligated = true },
        };
    info.flags.synthetic_base = synthetic_base;
    info.flags.base_mark_ligature = base_mark_ligature;
    return info;
}

fn appendLigatureSourcesForMatch(
    sources: []usize,
    source_count: *usize,
    logical_sources: []usize,
    logical_component_count: *usize,
    options: LookupOptions,
    glyph_index: usize,
) void {
    if (source_count.* >= sources.len) return;
    var contributes_component = true;
    if (options.ligature_components) |store| {
        if (glyph_index < store.infos.items.len) {
            const info = store.infos.items[glyph_index];
            // HarfBuzz's `_hb_glyph_info_get_lig_num_comps_in_ligation`
            // assigns every non-first MultipleSubst output zero component
            // weight. All pieces therefore remain one logical component when
            // a later LigatureSubst consumes them, and intervening marks keep
            // the component identity of the first piece.
            if (info.flags.multiplied and info.flags.multiple_component != 0) {
                contributes_component = false;
            }
        }
    }
    insertLigatureComponentSource(
        sources,
        source_count.*,
        sourceForGlyph(options, glyph_index),
    );
    source_count.* += 1;
    if (contributes_component and logical_component_count.* < logical_sources.len) {
        insertLigatureComponentSource(
            logical_sources,
            logical_component_count.*,
            sourceForGlyph(options, glyph_index),
        );
        logical_component_count.* += 1;
    }
}

test "GSUB ligation counts a MultipleSubst sequence as one component" {
    var glyph_sources = std.ArrayList(usize).empty;
    defer glyph_sources.deinit(std.testing.allocator);
    try glyph_sources.appendSlice(std.testing.allocator, &.{ 0, 2, 2, 4 });

    var components = ligature_provenance.Store{};
    defer components.deinit(std.testing.allocator);
    try components.infos.appendSlice(std.testing.allocator, &.{
        .{},
        .{ .flags = .{ .multiplied = true, .multiple_component = 0 } },
        .{ .flags = .{ .multiplied = true, .multiple_component = 1 } },
        .{},
    });

    var component_offsets = [_]usize{0} ** max_ligature_components;
    component_offsets[1] = 1;
    component_offsets[2] = 2;
    component_offsets[3] = 3;
    const info = try ligatureComponentInfoForMatch(
        std.testing.allocator,
        .{
            .glyph_source_indices = &glyph_sources,
            .ligature_components = &components,
        },
        0,
        .{
            .ligature = 50,
            .component_count = 4,
            .component_offsets = &component_offsets,
            .match_end = 4,
        },
    );

    try std.testing.expectEqual(@as(u8, 3), info.component_count);
    try std.testing.expectEqual(@as(u8, 4), info.source_count);
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 2, 2, 4 },
        components.componentSources(info).?,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 2, 4 },
        components.logicalComponentSources(info).?,
    );

    var single_component_offsets = [_]usize{0} ** max_ligature_components;
    single_component_offsets[1] = 1;
    const single_logical_component = try ligatureComponentInfoForMatch(
        std.testing.allocator,
        .{
            .glyph_source_indices = &glyph_sources,
            .ligature_components = &components,
        },
        1,
        .{
            .ligature = 51,
            .component_count = 2,
            .component_offsets = &single_component_offsets,
            .match_end = 2,
        },
    );
    try std.testing.expect(single_logical_component.isLigature());
    try std.testing.expectEqual(@as(u8, 1), single_logical_component.component_count);
    try std.testing.expectEqual(@as(u8, 2), single_logical_component.source_count);
    try std.testing.expectEqualSlices(
        usize,
        &.{ 2, 2 },
        components.componentSources(single_logical_component).?,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{2},
        components.logicalComponentSources(single_logical_component).?,
    );
}

fn insertLigatureComponentSource(sources: []usize, end: usize, source: usize) void {
    var index = end;
    while (index > 0 and source < sources[index - 1]) : (index -= 1) {
        sources[index] = sources[index - 1];
    }
    sources[index] = source;
}

fn ligatureIsBaseWithMarks(options: LookupOptions, glyph_index: usize, match: LigatureMatch, component_count: usize) bool {
    const codepoints = options.source_codepoints orelse return false;
    const first_source = sourceForGlyph(options, glyph_index);
    if (first_source >= codepoints.len or unicode.isUnicodeMarkCodepoint(codepoints[first_source])) return false;
    for (1..component_count) |component_index| {
        const matched_index = glyph_index + match.component_offsets[component_index];
        const source = sourceForGlyph(options, matched_index);
        if (source >= codepoints.len or !unicode.isUnicodeMarkCodepoint(codepoints[source])) return false;
    }
    return true;
}

test "GSUB base plus mark ligatures retain provenance with a GPOS hint" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });

    var components = ligature_provenance.Store{};
    defer components.deinit(std.testing.allocator);
    try components.infos.resize(std.testing.allocator, 2);
    @memset(components.infos.items, .{});
    var component_offsets = [_]usize{0} ** max_ligature_components;
    component_offsets[1] = 1;

    const base_mark_codepoints = [_]u21{ 0x05e0, 0x05bc };
    const base_mark = try ligatureComponentInfoForMatch(
        std.testing.allocator,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &base_mark_codepoints,
            .ligature_components = &components,
        },
        0,
        .{
            .ligature = 83,
            .component_count = 2,
            .component_offsets = &component_offsets,
            .match_end = 2,
        },
    );
    try std.testing.expectEqual(@as(u8, 2), base_mark.component_count);
    try std.testing.expect(base_mark.flags.base_mark_ligature);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, components.componentSources(base_mark).?);

    const mark_mark_codepoints = [_]u21{ 0x05b8, 0x05bd };
    const mark_mark = try ligatureComponentInfoForMatch(
        std.testing.allocator,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &mark_mark_codepoints,
            .ligature_components = &components,
        },
        0,
        .{
            .ligature = 97,
            .component_count = 2,
            .component_offsets = &component_offsets,
            .match_end = 2,
        },
    );
    try std.testing.expectEqual(@as(u8, 2), mark_mark.component_count);
    try std.testing.expect(!mark_mark.flags.base_mark_ligature);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, components.componentSources(mark_mark).?);
}

fn setLigatureMetadata(options: LookupOptions, glyph_index: usize, info: ligature_provenance.Info) void {
    if (options.ligature_components) |store| {
        if (glyph_index < store.infos.items.len) store.infos.items[glyph_index] = info;
    }
}

fn applyMultipleSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const sequence_count = try readU16(table, subtable_offset + 4);

    var i: usize = 0;
    while (i < glyphs.items.len) : (i += 1) {
        if (!sourceFeatureAllowsGlyph(options, i)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[i])) continue;
        const coverage = try table_core.coverage.index(table, coverage_offset, glyphs.items[i]) orelse continue;
        if (coverage >= sequence_count) continue;
        const sequence_offset = try checkedRequiredSubtableOffset(table, subtable_offset, try readU16(table, subtable_offset + 6 + coverage * 2));
        const glyph_count = try readU16(table, sequence_offset);
        if (glyph_count == 0) {
            // A zero-length sequence deletes the covered glyph.
            try consumeGsubMutationBudget(options, glyphs.items.len, 1, 0);
            try glyphs.replaceRange(allocator, i, 1, &.{});
            noteGlyphMutation(options);
            try replaceSourceMetadata(allocator, options, i, 1, 0, 0);
            if (i > 0) i -= 1;
            continue;
        }
        if (glyph_count == 1) {
            try consumeGsubMutationBudget(options, glyphs.items.len, 1, 1);
            glyphs.items[i] = try readU16(table, sequence_offset + 2);
            markGlyphSubstituted(options, i);
            continue;
        }
        const replacement = try allocator.alloc(GlyphId, glyph_count);
        defer allocator.free(replacement);
        for (replacement, 0..) |*glyph, replacement_index| {
            glyph.* = try readU16(table, sequence_offset + 2 + replacement_index * 2);
        }
        try consumeGsubMutationBudget(options, glyphs.items.len, 1, replacement.len);
        try glyphs.replaceRange(allocator, i, 1, replacement);
        noteGlyphMutation(options);
        if (replacement.len == 1) {
            markGlyphSubstituted(options, i);
        } else {
            try replaceSourceMetadata(allocator, options, i, 1, replacement.len, sourceForGlyph(options, i));
        }
        i += glyph_count - 1;
    }
}

fn applyMultipleSubstitutionAccelerated(table: Table, accelerator: MultipleSubstAccelerator, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    var i: usize = 0;
    while (i < glyphs.items.len) : (i += 1) {
        if (!sourceFeatureAllowsGlyph(options, i)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[i])) continue;
        const entry = multipleSubstEntryForGlyph(accelerator.entries, glyphs.items[i]) orelse continue;
        if (entry.glyph_count == 0) {
            try consumeGsubMutationBudget(options, glyphs.items.len, 1, 0);
            try glyphs.replaceRange(allocator, i, 1, &.{});
            noteGlyphMutation(options);
            try replaceSourceMetadata(allocator, options, i, 1, 0, 0);
            if (i > 0) i -= 1;
            continue;
        }
        if (entry.glyph_count == 1) {
            try consumeGsubMutationBudget(options, glyphs.items.len, 1, 1);
            glyphs.items[i] = entry.single_to;
            markGlyphSubstituted(options, i);
            continue;
        }
        const replacement = try allocator.alloc(GlyphId, entry.glyph_count);
        defer allocator.free(replacement);
        for (replacement, 0..) |*glyph, replacement_index| {
            glyph.* = try readU16(table, entry.sequence_offset + 2 + replacement_index * 2);
        }
        try consumeGsubMutationBudget(options, glyphs.items.len, 1, replacement.len);
        try glyphs.replaceRange(allocator, i, 1, replacement);
        noteGlyphMutation(options);
        try replaceSourceMetadata(allocator, options, i, 1, replacement.len, sourceForGlyph(options, i));
        i += replacement.len - 1;
    }
}

fn multipleSubstEntryForGlyph(entries: []const MultipleSubstEntry, glyph: GlyphId) ?MultipleSubstEntry {
    var lo: usize = 0;
    var hi: usize = entries.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const candidate = entries[mid].glyph;
        if (glyph < candidate) {
            hi = mid;
        } else if (glyph > candidate) {
            lo = mid + 1;
        } else {
            return entries[mid];
        }
    }
    return null;
}

fn applyAlternateSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions) GsubError!void {
    return try applyAlternateSubstitutionSubtable(table, subtable_offset, glyphs, lookup_flag, options, null);
}

fn applyAlternateSubstitutionSubtable(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions, matched: ?[]bool) GsubError!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const alternate_set_count = try readU16(table, subtable_offset + 4);
    const configured_alternate_index = options.active_feature_value;
    if (configured_alternate_index == 0) return;

    for (glyphs.items, 0..) |*glyph, glyph_index| {
        if (matched) |items| {
            if (items[glyph_index]) continue;
        }
        if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
        const coverage = try table_core.coverage.index(table, coverage_offset, glyph.*) orelse continue;
        if (coverage >= alternate_set_count) continue;
        const alternate_set_offset = try checkedRequiredSubtableOffset(table, subtable_offset, try readU16(table, subtable_offset + 6 + coverage * 2));
        const glyph_count = try readU16(table, alternate_set_offset);
        if (glyph_count == 0) continue;
        const alternate_index = if (options.active_feature_random and configured_alternate_index == random_feature_value)
            randomAlternateIndex(options.random_state orelse return error.InvalidShapingInput, glyph_count)
        else
            configured_alternate_index;
        if (alternate_index > glyph_count) continue;
        glyph.* = try readU16(table, alternate_set_offset + 2 + @as(usize, alternate_index - 1) * 2);
        markGlyphSubstituted(options, glyph_index);
        if (matched) |items| items[glyph_index] = true;
    }
}

fn randomAlternateIndex(random_state: *u32, alternate_count: u16) u32 {
    random_state.* = random_state.* *% 48271 % 2147483647;
    return random_state.* % @as(u32, alternate_count) + 1;
}

test "GSUB random AlternateSubst uses HarfBuzz wrapping minstd sequence" {
    var state: u32 = 1;
    const expected = [_]u32{ 2, 1, 1, 1, 1, 1, 3, 3, 1, 2, 2, 3 };
    for (expected) |alternate| {
        try std.testing.expectEqual(alternate, randomAlternateIndex(&state, 3));
    }
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
        1 => try applySingleSubstitution(table, extension_subtable, glyphs, lookup_flag, options),
        2 => try applyMultipleSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        3 => try applyAlternateSubstitution(table, extension_subtable, glyphs, lookup_flag, options),
        4 => try applyLigatureSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        5 => try applyContextSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        6 => try applyChainingContextSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        8 => try applyReverseChainingSingleSubstitution(table, extension_subtable, glyphs, lookup_flag, options, null),
        else => {},
    }
}

fn applyLigatureSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const lig_set_count = try readU16(table, subtable_offset + 4);

    var component_offsets: [max_ligature_components]usize = undefined;
    var i: usize = 0;
    while (i < glyphs.items.len) : (i += 1) {
        if (!sourceFeatureAllowsGlyph(options, i)) continue;
        const first = glyphs.items[i];
        if (lookupIgnoresGlyph(lookup_flag, options, first)) continue;
        const covered = try table_core.coverage.index(table, coverage_offset, first) orelse continue;
        if (covered >= lig_set_count) continue;
        const set_offset = checkedRequiredSubtableOffset(table, subtable_offset, try readU16(table, subtable_offset + 6 + covered * 2)) catch continue;
        if (try ligatureAt(table, set_offset, glyphs.items[i..], i, lookup_flag, options, &component_offsets)) |match| {
            const component_info = try ligatureComponentInfoForMatch(allocator, options, i, match);
            mergeLigatureClusterMetadata(options, i, match);
            glyphs.items[i] = match.ligature;
            markGlyphSubstituted(options, i);
            setLigatureMetadata(options, i, component_info);
            if (match.component_count > 1) {
                var component_index = match.component_count;
                while (component_index > 1) {
                    component_index -= 1;
                    try glyphs.replaceRange(allocator, i + match.component_offsets[component_index], 1, &.{});
                    try replaceSourceMetadata(allocator, options, i + match.component_offsets[component_index], 1, 0, 0);
                }
            }
        }
    }
}

fn applyLigatureSubstitutionAccelerated(table: Table, accelerator: LigatureSubstAccelerator, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    return applyLigatureSubstitutionAcceleratedImpl(false, table, accelerator, glyphs, allocator, lookup_flag, options);
}

fn applyLigatureSubstitutionPrefiltered(table: Table, accelerator: LigatureSubstAccelerator, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    return applyLigatureSubstitutionAcceleratedImpl(true, table, accelerator, glyphs, allocator, lookup_flag, options);
}

noinline fn applyLigatureSubstitutionRequiredSecondPrefiltered(
    table: Table,
    accelerator: LigatureSubstAccelerator,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    @branchHint(.cold);
    const second_components = requiredLigatureSecondComponents(accelerator);
    if (second_components.len == 0 or
        !runHasAnyGlyph(glyphs.items, second_components))
    {
        return;
    }
    return applyLigatureSubstitutionPrefiltered(
        table,
        accelerator,
        glyphs,
        allocator,
        lookup_flag,
        options,
    );
}

fn applyLigatureSubstitutionAcceleratedImpl(comptime prefilter_second: bool, table: Table, accelerator: LigatureSubstAccelerator, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    _ = table;
    var component_offsets: [max_ligature_components]usize = undefined;
    var i: usize = 0;
    while (i < glyphs.items.len) : (i += 1) {
        if (!sourceFeatureAllowsGlyph(options, i)) continue;
        const first = glyphs.items[i];
        if (lookupIgnoresGlyph(lookup_flag, options, first)) continue;
        const set = ligatureSetForGlyph(accelerator.sets, accelerator.set_slots, first) orelse continue;
        const match = if (prefilter_second)
            ligatureAtAcceleratedPrefiltered(accelerator, set, glyphs.items[i..], i, lookup_flag, options, &component_offsets)
        else
            ligatureAtAccelerated(accelerator, set, glyphs.items[i..], i, lookup_flag, options, &component_offsets);
        if (match) |matched| {
            const component_info = try ligatureComponentInfoForMatch(allocator, options, i, matched);
            mergeLigatureClusterMetadata(options, i, matched);
            glyphs.items[i] = matched.ligature;
            markGlyphSubstituted(options, i);
            setLigatureMetadata(options, i, component_info);
            if (matched.component_count > 1) {
                var component_index = matched.component_count;
                while (component_index > 1) {
                    component_index -= 1;
                    try glyphs.replaceRange(allocator, i + matched.component_offsets[component_index], 1, &.{});
                    try replaceSourceMetadata(allocator, options, i + matched.component_offsets[component_index], 1, 0, 0);
                }
            }
        }
    }
}

fn requiredLigatureSecondComponents(accelerator: LigatureSubstAccelerator) []const GlyphId {
    return accelerator_root.build.ligature.requiredSecondComponents(
        accelerator,
    );
}

fn ligatureSetForGlyph(sets: []const LigatureSetEntry, slots: []const u16, glyph: GlyphId) ?LigatureSetEntry {
    return accelerator_root.build.ligature.index.find(sets, slots, glyph);
}

fn ligatureAtAccelerated(accelerator: LigatureSubstAccelerator, set: LigatureSetEntry, glyphs: []const GlyphId, glyph_base: usize, lookup_flag: u16, options: LookupOptions, component_offsets: *[max_ligature_components]usize) ?LigatureMatch {
    const definition_end = set.definition_start + set.definition_len;
    const anchor_syllable = ligatureAnchorSyllable(options, glyph_base);
    for (accelerator.definitions[set.definition_start..definition_end]) |definition| {
        component_offsets[0] = 0;
        var cursor: usize = 1;
        var matched = true;
        const component_count: usize = definition.component_count;
        const expected_components = accelerator.components[definition.component_start .. definition.component_start + component_count - 1];
        for (expected_components, 1..) |expected, component_index| {
            while (cursor < glyphs.len and ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor) and ligatureMaySkipGlyph(lookup_flag, options, glyphs, glyph_base, cursor)) : (cursor += 1) {}
            if (cursor < glyphs.len and !ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor)) {
                matched = false;
                break;
            }
            if (cursor >= glyphs.len or glyphs[cursor] != expected) {
                matched = false;
                break;
            }
            component_offsets[component_index] = cursor;
            cursor += 1;
        }
        if (matched) {
            // Definitions remain in font-authored preference order.
            return .{
                .ligature = definition.ligature,
                .component_count = component_count,
                .component_offsets = component_offsets,
                .match_end = cursor,
            };
        }
    }
    return null;
}

fn ligatureAtAcceleratedPrefiltered(accelerator: LigatureSubstAccelerator, set: LigatureSetEntry, glyphs: []const GlyphId, glyph_base: usize, lookup_flag: u16, options: LookupOptions, component_offsets: *[max_ligature_components]usize) ?LigatureMatch {
    const anchor_syllable = ligatureAnchorSyllable(options, glyph_base);
    var second_offset: ?usize = null;
    if (glyphs.len > 1) {
        var cursor: usize = 1;
        while (cursor < glyphs.len and ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor) and ligatureMaySkipGlyph(lookup_flag, options, glyphs, glyph_base, cursor)) : (cursor += 1) {}
        if (cursor < glyphs.len and ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor)) second_offset = cursor;
    }

    component_offsets[0] = 0;
    const definition_end = set.definition_start + set.definition_len;
    for (accelerator.definitions[set.definition_start..definition_end]) |definition| {
        const component_count: usize = definition.component_count;
        const expected_components = accelerator.components[definition.component_start .. definition.component_start + component_count - 1];
        if (component_count == 1) {
            return .{
                .ligature = definition.ligature,
                .component_count = 1,
                .component_offsets = component_offsets,
                .match_end = 1,
            };
        }
        const second = second_offset orelse continue;
        if (expected_components[0] != glyphs[second]) continue;
        component_offsets[1] = second;

        var cursor = second + 1;
        var matched = true;
        for (expected_components[1..], 2..) |expected, component_index| {
            while (cursor < glyphs.len and ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor) and ligatureMaySkipGlyph(lookup_flag, options, glyphs, glyph_base, cursor)) : (cursor += 1) {}
            if (cursor < glyphs.len and !ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor)) {
                matched = false;
                break;
            }
            if (cursor >= glyphs.len or glyphs[cursor] != expected) {
                matched = false;
                break;
            }
            component_offsets[component_index] = cursor;
            cursor += 1;
        }
        if (matched) {
            // Definitions remain in font-authored preference order.
            return .{
                .ligature = definition.ligature,
                .component_count = component_count,
                .component_offsets = component_offsets,
                .match_end = cursor,
            };
        }
    }
    return null;
}

fn applyMultipleSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!?NestedGlyphChange {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    if (glyph_index >= glyphs.items.len) return null;
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[glyph_index])) return null;

    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const sequence_count = try readU16(table, subtable_offset + 4);
    const coverage = try table_core.coverage.index(table, coverage_offset, glyphs.items[glyph_index]) orelse return null;
    if (coverage >= sequence_count) return null;
    const sequence_offset = try checkedRequiredSubtableOffset(table, subtable_offset, try readU16(table, subtable_offset + 6 + coverage * 2));
    const glyph_count = try readU16(table, sequence_offset);
    if (glyph_count == 1) {
        try consumeGsubMutationBudget(options, glyphs.items.len, 1, 1);
        glyphs.items[glyph_index] = try readU16(table, sequence_offset + 2);
        markGlyphSubstituted(options, glyph_index);
        return .{};
    }

    const replacement = try allocator.alloc(GlyphId, glyph_count);
    defer allocator.free(replacement);
    for (replacement, 0..) |*glyph, replacement_index| {
        glyph.* = try readU16(table, sequence_offset + 2 + replacement_index * 2);
    }

    try consumeGsubMutationBudget(options, glyphs.items.len, 1, replacement.len);
    try glyphs.replaceRange(allocator, glyph_index, 1, replacement);
    noteGlyphMutation(options);
    if (replacement.len == 1) {
        markGlyphSubstituted(options, glyph_index);
    } else {
        try replaceSourceMetadata(allocator, options, glyph_index, 1, replacement.len, sourceForGlyph(options, glyph_index));
    }
    return .{ .removed_len = 1, .inserted_len = replacement.len };
}

fn applyLigatureSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!?NestedGlyphChange {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    if (glyph_index >= glyphs.items.len) return null;
    const first = glyphs.items[glyph_index];
    if (lookupIgnoresGlyph(lookup_flag, options, first)) return null;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const lig_set_count = try readU16(table, subtable_offset + 4);
    const covered = try table_core.coverage.index(table, coverage_offset, first) orelse return null;
    if (covered >= lig_set_count) return null;
    const set_offset = checkedRequiredSubtableOffset(table, subtable_offset, try readU16(table, subtable_offset + 6 + covered * 2)) catch return null;
    var component_offsets: [max_ligature_components]usize = undefined;
    const match = try ligatureAt(table, set_offset, glyphs.items[glyph_index..], glyph_index, lookup_flag, options, &component_offsets) orelse return null;
    const component_info = try ligatureComponentInfoForMatch(allocator, options, glyph_index, match);
    mergeLigatureClusterMetadata(options, glyph_index, match);
    glyphs.items[glyph_index] = match.ligature;
    markGlyphSubstituted(options, glyph_index);
    setLigatureMetadata(options, glyph_index, component_info);
    if (match.component_count > 1) {
        var component_index = match.component_count;
        while (component_index > 1) {
            component_index -= 1;
            try glyphs.replaceRange(allocator, glyph_index + match.component_offsets[component_index], 1, &.{});
            try replaceSourceMetadata(allocator, options, glyph_index + match.component_offsets[component_index], 1, 0, 0);
        }
    }
    return .{
        .removed_len = match.component_count,
        .inserted_len = 1,
        .component_offsets = component_offsets,
        .component_count = match.component_count,
    };
}

fn applyContextSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    switch (subst_format) {
        1 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
            const rule_set_count = try readU16(table, subtable_offset + 4);
            var pos: usize = 0;
            while (pos < glyphs.items.len) : (pos += 1) {
                if (!sourceFeatureAllowsGlyph(options, pos)) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
                const coverage = try table_core.coverage.index(table, coverage_offset, glyphs.items[pos]) orelse continue;
                if (coverage >= rule_set_count) continue;
                const rule_set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
                if (rule_set_relative == 0) continue;
                const rule_set_offset = subtable_offset + rule_set_relative;
                _ = try applyContextRuleSet(table, rule_set_offset, glyphs, pos, allocator, lookup_flag, options);
            }
        },
        2 => try applyContextClassSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        3 => try applyContextCoverageSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        else => return error.UnsupportedGsub,
    }
}

fn applyContextSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    if (glyph_index >= glyphs.items.len) return .{};
    const subst_format = try readU16(table, subtable_offset);
    switch (subst_format) {
        1 => {
            if (!sourceFeatureAllowsGlyph(options, glyph_index)) return .{};
            if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[glyph_index])) return .{};
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
            const coverage = try table_core.coverage.index(table, coverage_offset, glyphs.items[glyph_index]) orelse return .{};
            const rule_set_count = try readU16(table, subtable_offset + 4);
            if (coverage >= rule_set_count) return .{};
            const rule_set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
            if (rule_set_relative == 0) return .{};
            return if (try applyContextRuleSet(table, subtable_offset + rule_set_relative, glyphs, glyph_index, allocator, lookup_flag, options))
                .{ .matched = true, .next_pos = glyph_index + 1 }
            else
                .{};
        },
        2 => return try applyContextClassSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, options),
        3 => return try applyContextCoverageSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, options),
        else => return error.UnsupportedGsub,
    }
}

fn applyContextSubstitutionLookup(
    table: Table,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    options: LookupOptions,
) (GsubError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const result = try applyContextSubstitutionAt(
                table,
                subtable_offset,
                glyphs,
                pos,
                allocator,
                lookup_flag,
                options,
            );
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
    }
}

fn applyContextClassSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const class_def_offset = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const class_set_count = try readU16(table, subtable_offset + 6);
    var pos: usize = 0;
    while (pos < glyphs.items.len) : (pos += 1) {
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        if (try table_core.coverage.index(table, coverage_offset, glyphs.items[pos]) == null) continue;
        const class = try table_core.class_def.value(table, class_def_offset, glyphs.items[pos]);
        if (class >= class_set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 8 + @as(usize, class) * 2);
        if (set_relative == 0) continue;
        _ = try applyClassRuleSet(table, subtable_offset + set_relative, class_def_offset, glyphs, pos, allocator, lookup_flag, options);
    }
}

fn applyContextClassSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    if (!sourceFeatureAllowsGlyph(options, pos)) return .{};
    if (pos >= glyphs.items.len) return .{};
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) return .{};
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    if (try table_core.coverage.index(table, coverage_offset, glyphs.items[pos]) == null) return .{};
    const class_def_offset = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const class = try table_core.class_def.value(table, class_def_offset, glyphs.items[pos]);
    const class_set_count = try readU16(table, subtable_offset + 6);
    if (class >= class_set_count) return .{};
    const set_relative = try readU16(table, subtable_offset + 8 + @as(usize, class) * 2);
    if (set_relative == 0) return .{};
    return if (try applyClassRuleSet(table, subtable_offset + set_relative, class_def_offset, glyphs, pos, allocator, lookup_flag, options))
        .{ .matched = true, .next_pos = pos + 1 }
    else
        .{};
}

fn applyExtensionContextSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        for (0..subtable_count) |subtable_i| {
            const wrapper_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const subtable_offset = try extensionSubtablePayload(table, wrapper_offset, 5);
            const result = try applyContextSubstitutionAt(table, subtable_offset, glyphs, pos, allocator, lookup_flag, options);
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
    }
}

fn applyExtensionContextClassSubstitutionLookupAccelerated(table: Table, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GsubError || std.mem.Allocator.Error)!void {
    return try applyContextClassSubstitutionLookupAccelerated(table, 0, subtable_count, glyphs, allocator, lookup_flag, options, accelerator);
}

fn applyContextClassSubstitutionLookupAccelerated(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GsubError || std.mem.Allocator.Error)!void {
    _ = lookup_offset;
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        var subtable_i: usize = 0;
        while (subtable_i < subtable_count and subtable_i < accelerator.context_class_subtables.len) : (subtable_i += 1) {
            const subtable = accelerator.context_class_subtables[subtable_i];
            if (subtable.rules.len == 0) continue;
            const result = try applyAcceleratedContextClassSubstitutionAt(table, subtable, glyphs, pos, allocator, lookup_flag, options);
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
    }
}

fn applyAcceleratedContextClassSubstitutionAt(table: Table, subtable: ContextClassSubtableAccelerator, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    const group = classGroupForGlyph(subtable.classes, subtable.first_index_start, subtable.groups, glyphs.items[pos]) orelse return .{};
    if (group.max_input_count == 0 or group.max_input_count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;

    var input_indices_buf: [max_chaining_class_region_glyphs]usize = undefined;
    const input_len = collectForwardUnignoredGlyphPrefix(
        glyphs.items,
        pos,
        lookup_flag,
        options,
        input_indices_buf[0..group.max_input_count],
        false,
        pos,
    );
    if (input_len == 0) return .{};
    const input_indices = input_indices_buf[0..input_len];
    var input_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    for (1..input_len) |input_i| {
        input_classes[input_i - 1] = if (subtable.class_def == empty_class_def_offset)
            glyphs.items[input_indices[input_i]]
        else
            try table_core.class_def.value(table, subtable.class_def, glyphs.items[input_indices[input_i]]);
    }

    const rules = subtable.rules[group.start .. group.start + group.len];
    for (rules) |rule| {
        // A class set may mix short and long rules. Reaching the end of a run
        // or source syllable while collecting the group's maximum window only
        // disqualifies rules longer than the available prefix; shorter rules
        // remain valid and must still be tried in font-authored order.
        if (rule.input_count == 0 or rule.input_count > input_len) continue;
        const extra_input_count = @as(usize, rule.input_count) - 1;
        const hash = class_context.sequenceHash(input_classes[0..extra_input_count]);
        if (rule.hash != hash) continue;
        const expected_input = subtable.classes[rule.classes_start .. rule.classes_start + extra_input_count];
        if (!std.mem.eql(u16, expected_input, input_classes[0..extra_input_count])) continue;
        try markUnsafeContextMatch(allocator, options, input_indices[0..rule.input_count]);
        const glyph_count_before = glyphs.items.len;
        try applySubstitutionRecordsMapped(table, glyphs, rule.records_offset, rule.subst_count, input_indices[0..rule.input_count], allocator, options);
        const original_next = input_indices[rule.input_count - 1] + 1;
        return .{
            .matched = true,
            .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
        };
    }
    return .{};
}

fn applyClassRuleSet(table: Table, rule_set_offset: usize, class_def_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, rule_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = rule_set_offset + try readU16(table, rule_set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const subst_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0 or pos + glyph_count > glyphs.items.len) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..glyph_count], false, pos)) continue;
        var matched = true;
        for (1..glyph_count) |i| {
            const expected_class = try readU16(table, rule_offset + 4 + (i - 1) * 2);
            const actual_class = try table_core.class_def.value(table, class_def_offset, glyphs.items[input_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        // Once the input classes match, each substitution record points at a
        // glyph within the matched input sequence and a nested lookup index.
        const records_offset = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        try markUnsafeContextMatch(allocator, options, input_indices_buf[0..glyph_count]);
        try applySubstitutionRecordsMapped(table, glyphs, records_offset, subst_count, input_indices_buf[0..glyph_count], allocator, options);
        return true;
    }
    return false;
}

fn applyContextCoverageSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const glyph_count = try readU16(table, subtable_offset + 2);
    const subst_count = try readU16(table, subtable_offset + 4);
    if (glyph_count == 0) return;
    const coverage_offsets_pos = subtable_offset + 6;
    const subst_records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
    var pos: usize = 0;
    while (pos < glyphs.items.len) : (pos += 1) {
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..glyph_count], false, pos)) continue;
        var matched = true;
        for (0..glyph_count) |i| {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, coverage_offsets_pos + i * 2));
            if (try table_core.coverage.index(table, coverage_offset, glyphs.items[input_indices_buf[i]]) == null) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        try markUnsafeContextMatch(allocator, options, input_indices_buf[0..glyph_count]);
        try applySubstitutionRecordsMapped(table, glyphs, subst_records_pos, subst_count, input_indices_buf[0..glyph_count], allocator, options);
        pos += glyph_count - 1;
    }
}

fn applyContextCoverageSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    if (!sourceFeatureAllowsGlyph(options, pos)) return .{};
    if (pos >= glyphs.items.len) return .{};
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) return .{};
    const glyph_count = try readU16(table, subtable_offset + 2);
    if (glyph_count == 0) return .{};
    var input_indices_buf: [64]usize = undefined;
    if (glyph_count > input_indices_buf.len) return error.UnsupportedGsub;
    if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..glyph_count], false, pos)) return .{};

    const coverage_offsets_pos = subtable_offset + 6;
    for (0..glyph_count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, coverage_offsets_pos + i * 2));
        if (try table_core.coverage.index(table, coverage_offset, glyphs.items[input_indices_buf[i]]) == null) return .{};
    }
    const subst_count = try readU16(table, subtable_offset + 4);
    const subst_records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
    try markUnsafeContextMatch(allocator, options, input_indices_buf[0..glyph_count]);
    const glyph_count_before = glyphs.items.len;
    try applySubstitutionRecordsMapped(table, glyphs, subst_records_pos, subst_count, input_indices_buf[0..glyph_count], allocator, options);
    const original_next = input_indices_buf[glyph_count - 1] + 1;
    return .{
        .matched = true,
        .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
    };
}

fn applyContextCoverageLookupAccelerated(
    table: Table,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    options: LookupOptions,
    accelerator: *const LookupAccelerator,
) (GsubError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        const first = glyphs.items[pos];
        if (lookupIgnoresGlyph(lookup_flag, options, first)) continue;
        const candidates = candidates: {
            if (accelerator.context_group_slots.len != 0) {
                if (first >= accelerator.context_group_slots.len) continue;
                const group_slot = accelerator.context_group_slots[first];
                if (group_slot == 0) continue;
                const group_index = @as(usize, group_slot) - 1;
                if (group_index >= accelerator.context_groups.len) return error.BadGsub;
                const group = accelerator.context_groups[group_index];
                if (group.glyph != first) return error.BadGsub;
                break :candidates group.subtable_indices;
            }
            break :candidates accelerator_root.index.chaining.findIndices(
                accelerator.context_groups,
                &.{},
                first,
            ) orelse continue;
        };
        for (candidates) |subtable_i| {
            if (subtable_i >= accelerator.context_coverage_subtables.len) return error.BadGsub;
            const subtable = accelerator.context_coverage_subtables[subtable_i];
            if (subtable.glyph_count == 0 or
                subtable.coverage_start > accelerator.context_coverage_offsets.len or
                subtable.glyph_count > accelerator.context_coverage_offsets.len - subtable.coverage_start)
            {
                return error.BadGsub;
            }
            var input_indices_buf: [64]usize = undefined;
            if (!collectForwardUnignoredGlyphs(
                glyphs.items,
                pos,
                lookup_flag,
                options,
                input_indices_buf[0..subtable.glyph_count],
                false,
                pos,
            )) continue;
            var matched = true;
            const coverage_offsets = accelerator.context_coverage_offsets[subtable.coverage_start .. subtable.coverage_start + subtable.glyph_count];
            // First coverage was resolved exactly by `context_groups`.
            for (coverage_offsets[1..], 1..) |coverage_offset, input_i| {
                if (try table_core.coverage.index(table, coverage_offset, glyphs.items[input_indices_buf[input_i]]) == null) {
                    matched = false;
                    break;
                }
            }
            if (!matched) continue;

            try markUnsafeContextMatch(
                allocator,
                options,
                input_indices_buf[0..subtable.glyph_count],
            );
            const glyph_count_before = glyphs.items.len;
            try applySubstitutionRecordsMapped(
                table,
                glyphs,
                subtable.records_pos,
                subtable.subst_count,
                input_indices_buf[0..subtable.glyph_count],
                allocator,
                options,
            );
            const original_next = input_indices_buf[subtable.glyph_count - 1] + 1;
            next_pos = @max(
                next_pos,
                contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
            );
            break;
        }
    }
}

fn applyContextRuleSet(table: Table, rule_set_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, rule_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = rule_set_offset + try readU16(table, rule_set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const subst_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0 or pos + glyph_count > glyphs.items.len) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..glyph_count], false, pos)) continue;
        var matched = true;
        for (1..glyph_count) |component_i| {
            const expected = try readU16(table, rule_offset + 4 + (component_i - 1) * 2);
            if (glyphs.items[input_indices_buf[component_i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;

        const records_offset = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        try markUnsafeContextMatch(allocator, options, input_indices_buf[0..glyph_count]);
        try applySubstitutionRecordsMapped(table, glyphs, records_offset, subst_count, input_indices_buf[0..glyph_count], allocator, options);
        return true;
    }
    return false;
}

fn applyChainingContextSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    switch (subst_format) {
        1 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
            const chain_set_count = try readU16(table, subtable_offset + 4);
            var pos: usize = 0;
            while (pos < glyphs.items.len) {
                var next_pos = pos + 1;
                defer pos = next_pos;
                if (!sourceFeatureAllowsGlyph(options, pos)) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
                const coverage = try table_core.coverage.index(table, coverage_offset, glyphs.items[pos]) orelse continue;
                if (coverage >= chain_set_count) continue;
                const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
                if (set_relative == 0) continue;
                const result = try applyChainingRuleSet(table, subtable_offset + set_relative, glyphs, pos, allocator, lookup_flag, options);
                if (result.matched) next_pos = @max(next_pos, result.next_pos);
            }
        },
        2 => try applyChainingClassSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        3 => try applyChainingCoverageSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        else => return error.UnsupportedGsub,
    }
}

fn chainingCoverageLookupMayMatch(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GsubError!bool {
    if (glyphs.len == 0) return false;
    // Arabic shaping often reaches this path one short word at a time. For
    // those tiny runs the exact scan is cheaper than building coverage digests;
    // reserve the approximate filter for longer runs where it can amortize.
    if (glyphs.len < 64) return try chainingCoverageLookupMayMatchByScan(table, lookup_offset, subtable_count, glyphs, lookup_flag, options);
    const run_digest = glyphRunDigest(glyphs, lookup_flag, options);
    if (run_digest.isEmpty()) return false;
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const coverage_offset = try accelerator_root.build.chaining_coverage.parser.firstInputCoverage(table, subtable_offset) orelse continue;
        const coverage_digest = try table_core.coverage.digest(table, coverage_offset);
        if (coverage_digest.mayIntersect(run_digest)) return true;
    }
    return false;
}

fn chainingCoverageLookupMayMatchByScan(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GsubError!bool {
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const coverage_offset = try accelerator_root.build.chaining_coverage.parser.firstInputCoverage(table, subtable_offset) orelse continue;
        for (glyphs, 0..) |glyph, glyph_index| {
            if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
            if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
            if (try table_core.coverage.index(table, coverage_offset, glyph) != null) return true;
        }
    }
    return false;
}

fn glyphRunDigest(glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GlyphDigest {
    var digest = GlyphDigest.empty();
    for (glyphs, 0..) |glyph, glyph_index| {
        if (!sourceFeatureAllowsGlyph(options, glyph_index)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
        digest.add(glyph);
    }
    return digest;
}

fn runHasAnyGlyph(
    glyphs: []const GlyphId,
    candidates: []const GlyphId,
) bool {
    // This is only a necessary-condition proof. Search every glyph id: lookup
    // flags, source feature scope, and syllable bounds can make an occurrence
    // unusable (a harmless false positive), but filtering here could hide a
    // valid non-leading ligature component and create a false negative.
    for (glyphs) |glyph| {
        if (std.sort.binarySearch(GlyphId, candidates, glyph, glyphIdOrder) != null) return true;
    }
    return false;
}

fn glyphIdOrder(target: GlyphId, item: GlyphId) std.math.Order {
    return std.math.order(target, item);
}

test "GSUB required ligature components scan exact run glyphs" {
    const candidates = [_]GlyphId{ 2, 7, 11 };
    try std.testing.expect(runHasAnyGlyph(&.{ 1, 7 }, &candidates));
    try std.testing.expect(!runHasAnyGlyph(&.{ 1, 8 }, &candidates));

    const accelerator = LigatureSubstAccelerator{
        .components = &.{ 20, 21, 2, 7, 11 },
        .required_second_start = 2,
        .required_second_len = 3,
    };
    try std.testing.expectEqualSlices(
        GlyphId,
        &candidates,
        requiredLigatureSecondComponents(accelerator),
    );
    var stale = accelerator;
    stale.required_second_start = 4;
    stale.required_second_len = 2;
    try std.testing.expectEqual(@as(usize, 0), requiredLigatureSecondComponents(stale).len);
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
    var cache = RunDigestCache{};

    const first = cache.get(glyphs.items, 0, options);
    try std.testing.expect(first.mayHave(1));

    // Consecutive no-op contextual lookups reuse the old summary.
    const second = cache.get(glyphs.items, 0, options);
    try std.testing.expect(second.mayHave(1));
    try std.testing.expectEqual(@as(usize, 1), cache.len);

    // A substitution can introduce the first-input glyph of a later lookup.
    // The actual substitution primitive advances the common mutation epoch,
    // forcing the later lookup to discard the old negative summary.
    try std.testing.expect(try applySingleSubstitutionAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len },
        0,
        &glyphs,
        0,
        0,
        options,
    ));
    const after_substitution = cache.get(glyphs.items, 0, options);
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
        consumeNestedGsubOperation(options) catch |err| {
            try std.testing.expectEqual(error.ShapingLimitExceeded, err);
            break;
        };
        consumeGsubMutationBudget(options, glyph_count, 1, 19) catch |err| {
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
        consumeGsubMutationBudget(options, glyph_count, 1, options.max_glyph_count.?),
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
    const single_options = optionsWithRunDigestGeneration(
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

    const two_options = optionsWithRunDigestGeneration(
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
    var cache = RunDigestCache.init();
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
    const final_digest = cache.get(glyphs.items, 0, options);
    try std.testing.expect(final_digest.mayHave(9));
    try std.testing.expect(!final_digest.mayHave(5));
    try std.testing.expectEqual(generation, cache.generation);
}

fn applyChainingContextSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: ?*const LookupAccelerator) (GsubError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        const current_glyph = glyphs.items[pos];
        if (accelerator) |accel| {
            // The exact first-input group index is deliberately larger and
            // more expensive than the three-mask digest. Follow HarfBuzz's
            // forward-lookup order and reject definite misses here before
            // consulting source metadata, GDEF, or the group hash table.
            // `chaining_input_digest` is the union of every first-input
            // Coverage, so its false positives are harmless and it cannot
            // hide an applicable subtable.
            if (!accel.chaining_input_digest.mayHave(current_glyph)) continue;
            if (!sourceFeatureAllowsGlyph(options, pos)) continue;
            if (lookupIgnoresGlyph(lookup_flag, options, current_glyph)) continue;
            const group = accelerator_root.index.chaining.find(accel.chaining_groups, accel.chaining_group_slots, current_glyph) orelse continue;
            const grouped_subtables = group.subtable_indices;
            const second_glyph_index = if (accel.chaining_needs_second_input)
                nextUnignoredGlyphIndex(glyphs.items, pos + 1, lookup_flag, options, false, pos)
            else
                null;
            const second_glyph = if (second_glyph_index) |index| glyphs.items[index] else null;
            if (!group.has_no_second_input and !group.second_input_digest.isEmpty()) {
                const glyph = second_glyph orelse continue;
                if (!group.second_input_digest.mayHave(glyph)) continue;
            }
            const candidate_subtables = if (accel.chaining_pair_index_complete and !group.has_no_second_input) pair: {
                const glyph = second_glyph orelse continue;
                break :pair accelerator_root.index.chaining.findPairIndices(
                    accel.chaining_pair_groups,
                    accel.chaining_pair_group_slots,
                    current_glyph,
                    glyph,
                ) orelse continue;
            } else grouped_subtables;
            const first_backtrack_glyph = if (accel.chaining_needs_backtrack)
                previousUnignoredGlyph(glyphs.items, pos, lookup_flag, options, true, pos)
            else
                null;
            const single_input_lookahead_glyph = if (accel.chaining_needs_single_input_lookahead)
                nextUnignoredGlyph(glyphs.items, pos + 1, lookup_flag, options, true, pos)
            else
                null;
            var third_glyph_index: ?usize = null;
            var third_glyph_resolved = false;
            for (candidate_subtables) |subtable_i| {
                const parsed_subtable = if (subtable_i < accel.chaining_subtables.len and accel.chaining_subtables[subtable_i].input_count != 0)
                    accel.chaining_subtables[subtable_i]
                else
                    null;
                if (parsed_subtable) |subtable| {
                    if (subtable.input_count > 1) {
                        const glyph = second_glyph orelse continue;
                        if (!subtable.second_input_digest.mayHave(glyph)) continue;
                    }
                    if (subtable.input_count > 2) {
                        if (!third_glyph_resolved) {
                            third_glyph_index = if (second_glyph_index) |index|
                                nextUnignoredGlyphIndex(glyphs.items, index + 1, lookup_flag, options, false, pos)
                            else
                                null;
                            third_glyph_resolved = true;
                        }
                        const index = third_glyph_index orelse continue;
                        const glyph = glyphs.items[index];
                        if (!subtable.third_input_digest.mayHave(glyph)) continue;
                    }
                    if (subtable.backtrack_count != 0) {
                        const glyph = first_backtrack_glyph orelse continue;
                        if (!subtable.first_backtrack_digest.mayHave(glyph)) continue;
                    }
                    if (subtable.input_count == 1 and subtable.lookahead_count != 0) {
                        const glyph = single_input_lookahead_glyph orelse continue;
                        if (!subtable.first_lookahead_digest.mayHave(glyph)) continue;
                    }
                    const result = if (subtable.backtrack_count == 0 and subtable.lookahead_count == 0 and subtable.input_count <= 3)
                        try applyAcceleratedChainingCoverageNoContextAt(table, subtable, glyphs, pos, second_glyph_index, third_glyph_index, allocator, options)
                    else
                        try applyAcceleratedChainingCoverageSubstitutionAt(table, subtable, glyphs, pos, allocator, lookup_flag, options);
                    if (result.matched) {
                        next_pos = @max(next_pos, result.next_pos);
                        break;
                    }
                    continue;
                }
                const raw_subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + @as(usize, subtable_i) * 2);
                const subtable_offset = if (accel.extension_lookup_type == 6)
                    try extensionSubtablePayload(table, raw_subtable_offset, 6)
                else
                    raw_subtable_offset;
                const result = try applyChainingContextSubstitutionAt(table, subtable_offset, parsed_subtable, glyphs, pos, allocator, lookup_flag, options);
                if (result.matched) {
                    next_pos = @max(next_pos, result.next_pos);
                    break;
                }
            }
        } else {
            for (0..subtable_count) |subtable_i| {
                const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
                const result = try applyChainingContextSubstitutionAt(table, subtable_offset, null, glyphs, pos, allocator, lookup_flag, options);
                if (result.matched) {
                    next_pos = @max(next_pos, result.next_pos);
                    break;
                }
            }
        }
    }
}

fn applyExtensionChainingContextSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const extension_subtable = try extensionSubtablePayload(table, subtable_offset, 6);
            const result = try applyChainingContextSubstitutionAt(table, extension_subtable, null, glyphs, pos, allocator, lookup_flag, options);
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
    }
}

fn applyExtensionChainingClassSubstitutionLookupAccelerated(table: Table, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GsubError || std.mem.Allocator.Error)!void {
    return try applyChainingClassSubstitutionLookupAccelerated(
        table,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        options,
        accelerator,
    );
}

fn applyChainingClassSubstitutionLookupAccelerated(
    table: Table,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    options: LookupOptions,
    accelerator: *const LookupAccelerator,
) (GsubError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        var subtable_i: usize = 0;
        while (subtable_i < subtable_count and subtable_i < accelerator.chaining_class_subtables.len) : (subtable_i += 1) {
            const subtable = accelerator.chaining_class_subtables[subtable_i];
            if (subtable.rules.len == 0) continue;
            const result = try applyAcceleratedChainingClassSubstitutionWithBacktrackAt(table, subtable, glyphs, pos, allocator, lookup_flag, options);
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
    }
}

fn applyReverseChainingSingleSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions) GsubError!void {
    if (glyphs.items.len == 0) return;
    var pos = glyphs.items.len;
    while (pos > 0) {
        pos -= 1;
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            if (try applyReverseChainingSingleSubstitutionAt(table, subtable_offset, glyphs, pos, lookup_flag, options)) break;
        }
    }
}

fn applyExtensionReverseChainingSingleSubstitutionLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions, accelerator: ?*const LookupAccelerator) GsubError!void {
    if (glyphs.items.len == 0) return;
    var pos = glyphs.items.len;
    while (pos > 0) {
        pos -= 1;
        if (accelerator) |accel| {
            const glyph = glyphs.items[pos];
            if (!sourceFeatureAllowsGlyph(options, pos)) continue;
            if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
            if (accel.reverse_chaining_exact_contexts.len != 0) {
                const key = reverseChainingContextKeyForPosition(glyphs.items, pos, glyph, lookup_flag, options) orelse continue;
                const entry = runtime.reverse_context.find(
                    accel.reverse_chaining_exact_contexts,
                    key,
                ) orelse continue;
                glyphs.items[pos] = entry.substitute;
                markGlyphSubstituted(options, pos);
                continue;
            }
            const grouped_subtables = accelerator_root.index.chaining.findIndices(accel.reverse_chaining_groups, &.{}, glyph) orelse continue;
            for (grouped_subtables) |subtable_i| {
                if (subtable_i >= accel.reverse_chaining_subtables.len) return error.BadGsub;
                if (try applyParsedReverseChainingSingleSubstitutionAt(table, accel.reverse_chaining_subtables[subtable_i], glyphs, pos, lookup_flag, options)) break;
            }
            continue;
        }
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const extension_subtable = try extensionSubtablePayload(table, subtable_offset, 8);
            if (try applyReverseChainingSingleSubstitutionAt(table, extension_subtable, glyphs, pos, lookup_flag, options)) break;
        }
    }
}

fn applyChainingContextSubstitutionAt(table: Table, subtable_offset: usize, parsed_subtable: ?ChainingCoverageSubtable, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    const subst_format = try readU16(table, subtable_offset);
    return switch (subst_format) {
        1 => try applyChainingGlyphSubstitutionAt(table, subtable_offset, glyphs, pos, allocator, lookup_flag, options),
        2 => try applyChainingClassSubstitutionAt(table, subtable_offset, glyphs, pos, allocator, lookup_flag, options),
        3 => try applyChainingCoverageSubstitutionAt(table, parsed_subtable orelse (try accelerator_root.build.chaining_coverage.parser.parse(table, subtable_offset) orelse return .{}), glyphs, pos, allocator, lookup_flag, options),
        else => .{},
    };
}

fn applyChainingGlyphSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    if (!sourceFeatureAllowsGlyph(options, pos)) return .{};
    if (pos >= glyphs.items.len) return .{};
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) return .{};

    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const chain_set_count = try readU16(table, subtable_offset + 4);
    const coverage = try table_core.coverage.index(table, coverage_offset, glyphs.items[pos]) orelse return .{};
    if (coverage >= chain_set_count) return .{};
    const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
    if (set_relative == 0) return .{};
    return try applyChainingRuleSet(table, subtable_offset + set_relative, glyphs, pos, allocator, lookup_flag, options);
}

fn applyChainingClassSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const backtrack_class_def = try checkedOptionalClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const input_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 6));
    const lookahead_class_def = try checkedOptionalClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
    const set_count = try readU16(table, subtable_offset + 10);
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (!sourceFeatureAllowsGlyph(options, pos)) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        if (try table_core.coverage.index(table, coverage_offset, glyphs.items[pos]) == null) continue;
        const input_class = try table_core.class_def.value(table, input_class_def, glyphs.items[pos]);
        if (input_class >= set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 12 + @as(usize, input_class) * 2);
        if (set_relative == 0) continue;
        const result = try applyChainingClassRuleSet(table, subtable_offset + set_relative, backtrack_class_def, input_class_def, lookahead_class_def, glyphs, pos, allocator, lookup_flag, options);
        if (result.matched) next_pos = @max(next_pos, result.next_pos);
    }
}

fn applyChainingClassSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    if (!sourceFeatureAllowsGlyph(options, pos)) return .{};
    if (pos >= glyphs.items.len) return .{};
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) return .{};

    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const backtrack_class_def = try checkedOptionalClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const input_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 6));
    const lookahead_class_def = try checkedOptionalClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
    const set_count = try readU16(table, subtable_offset + 10);
    if (try table_core.coverage.index(table, coverage_offset, glyphs.items[pos]) == null) return .{};
    const input_class = try table_core.class_def.value(table, input_class_def, glyphs.items[pos]);
    if (input_class >= set_count) return .{};
    const set_relative = try readU16(table, subtable_offset + 12 + @as(usize, input_class) * 2);
    if (set_relative == 0) return .{};
    return try applyChainingClassRuleSet(table, subtable_offset + set_relative, backtrack_class_def, input_class_def, lookahead_class_def, glyphs, pos, allocator, lookup_flag, options);
}

const max_chaining_class_region_glyphs =
    accelerator_model.max_context_region_glyphs;

const ChainingClassRuleMatchWindow = struct {
    table: Table,
    glyphs: []const GlyphId,
    backtrack_class_def: usize,
    input_class_def: usize,
    lookahead_class_def: usize,
    lookup_flag: u16,
    options: LookupOptions,
    anchor_syllable: ?u8,

    input_indices: [max_chaining_class_region_glyphs]usize = undefined,
    input_classes: [max_chaining_class_region_glyphs]u16 = undefined,
    input_class_valid: [max_chaining_class_region_glyphs]bool = [_]bool{false} ** max_chaining_class_region_glyphs,
    input_len: usize = 0,
    input_scan: usize,
    input_exhausted: bool = false,

    backtrack_indices: [max_chaining_class_region_glyphs]usize = undefined,
    backtrack_classes: [max_chaining_class_region_glyphs]u16 = undefined,
    backtrack_class_valid: [max_chaining_class_region_glyphs]bool = [_]bool{false} ** max_chaining_class_region_glyphs,
    backtrack_len: usize = 0,
    backtrack_scan: usize,
    backtrack_exhausted: bool = false,

    lookahead_indices: [max_chaining_class_region_glyphs]usize = undefined,
    lookahead_classes: [max_chaining_class_region_glyphs]u16 = undefined,
    lookahead_class_valid: [max_chaining_class_region_glyphs]bool = [_]bool{false} ** max_chaining_class_region_glyphs,
    lookahead_len: usize = 0,
    lookahead_scan: usize = 0,
    lookahead_start: usize = std.math.maxInt(usize),
    lookahead_exhausted: bool = false,

    fn init(table: Table, glyphs: []const GlyphId, pos: usize, backtrack_class_def: usize, input_class_def: usize, lookahead_class_def: usize, lookup_flag: u16, options: LookupOptions) ChainingClassRuleMatchWindow {
        return .{
            .table = table,
            .glyphs = glyphs,
            .backtrack_class_def = backtrack_class_def,
            .input_class_def = input_class_def,
            .lookahead_class_def = lookahead_class_def,
            .lookup_flag = lookup_flag,
            .options = options,
            .anchor_syllable = sourceSyllableForGlyph(options, pos),
            .input_scan = pos,
            .backtrack_scan = pos,
        };
    }

    fn inputSlice(self: *ChainingClassRuleMatchWindow, count: usize) GsubError!?[]const usize {
        if (count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        if (!try self.ensureInputCount(count)) return null;
        return self.input_indices[0..count];
    }

    fn inputClassAt(self: *ChainingClassRuleMatchWindow, index: usize) GsubError!?u16 {
        if (index >= max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        if (!try self.ensureInputCount(index + 1)) return null;
        if (!self.input_class_valid[index]) {
            self.input_classes[index] = try table_core.class_def.value(self.table, self.input_class_def, self.glyphs[self.input_indices[index]]);
            self.input_class_valid[index] = true;
        }
        return self.input_classes[index];
    }

    fn backtrackClassAt(self: *ChainingClassRuleMatchWindow, index: usize) GsubError!?u16 {
        if (index >= max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        if (!try self.ensureBacktrackCount(index + 1)) return null;
        if (!self.backtrack_class_valid[index]) {
            self.backtrack_classes[index] = try table_core.class_def.value(self.table, self.backtrack_class_def, self.glyphs[self.backtrack_indices[index]]);
            self.backtrack_class_valid[index] = true;
        }
        return self.backtrack_classes[index];
    }

    fn lookaheadClassAt(self: *ChainingClassRuleMatchWindow, input_count: usize, index: usize) GsubError!?u16 {
        if (index >= max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        if (!try self.ensureLookaheadCount(input_count, index + 1)) return null;
        if (!self.lookahead_class_valid[index]) {
            self.lookahead_classes[index] = try table_core.class_def.value(self.table, self.lookahead_class_def, self.glyphs[self.lookahead_indices[index]]);
            self.lookahead_class_valid[index] = true;
        }
        return self.lookahead_classes[index];
    }

    fn ensureInputCount(self: *ChainingClassRuleMatchWindow, count: usize) GsubError!bool {
        if (count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        while (self.input_len < count) {
            if (self.input_exhausted) return false;
            var found = false;
            while (self.input_scan < self.glyphs.len) : (self.input_scan += 1) {
                const glyph_index = self.input_scan;
                if (contextualMaySkipGlyph(self.lookup_flag, self.options, self.glyphs, glyph_index, false)) continue;
                if (!sourceSyllableAllowsGlyph(self.options, self.anchor_syllable, glyph_index)) {
                    self.input_exhausted = true;
                    return false;
                }
                self.input_indices[self.input_len] = glyph_index;
                self.input_len += 1;
                self.input_scan += 1;
                found = true;
                break;
            }
            if (!found) {
                self.input_exhausted = true;
                return false;
            }
        }
        return true;
    }

    fn ensureBacktrackCount(self: *ChainingClassRuleMatchWindow, count: usize) GsubError!bool {
        if (count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        while (self.backtrack_len < count) {
            if (self.backtrack_exhausted) return false;
            var found = false;
            while (self.backtrack_scan > 0) {
                self.backtrack_scan -= 1;
                if (contextualMaySkipGlyph(self.lookup_flag, self.options, self.glyphs, self.backtrack_scan, true)) continue;
                if (!sourceSyllableAllowsGlyph(self.options, self.anchor_syllable, self.backtrack_scan)) {
                    self.backtrack_exhausted = true;
                    return false;
                }
                self.backtrack_indices[self.backtrack_len] = self.backtrack_scan;
                self.backtrack_len += 1;
                found = true;
                break;
            }
            if (!found) {
                self.backtrack_exhausted = true;
                return false;
            }
        }
        return true;
    }

    fn ensureLookaheadCount(self: *ChainingClassRuleMatchWindow, input_count: usize, count: usize) GsubError!bool {
        if (input_count == 0 or input_count > max_chaining_class_region_glyphs or count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        if (!try self.ensureInputCount(input_count)) return false;
        const start = self.input_indices[input_count - 1] + 1;
        if (self.lookahead_start != start) {
            self.lookahead_start = start;
            self.lookahead_scan = start;
            self.lookahead_len = 0;
            self.lookahead_exhausted = false;
            @memset(&self.lookahead_class_valid, false);
        }
        while (self.lookahead_len < count) {
            if (self.lookahead_exhausted) return false;
            var found = false;
            while (self.lookahead_scan < self.glyphs.len) : (self.lookahead_scan += 1) {
                const glyph_index = self.lookahead_scan;
                if (contextualMaySkipGlyph(self.lookup_flag, self.options, self.glyphs, glyph_index, true)) continue;
                if (!sourceSyllableAllowsGlyph(self.options, self.anchor_syllable, glyph_index)) {
                    self.lookahead_exhausted = true;
                    return false;
                }
                self.lookahead_indices[self.lookahead_len] = glyph_index;
                self.lookahead_len += 1;
                self.lookahead_scan += 1;
                found = true;
                break;
            }
            if (!found) {
                self.lookahead_exhausted = true;
                return false;
            }
        }
        return true;
    }
};

fn applyChainingClassRuleSet(table: Table, set_offset: usize, backtrack_class_def: usize, input_class_def: usize, lookahead_class_def: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    const rule_count = try readU16(table, set_offset);
    var window = ChainingClassRuleMatchWindow.init(table, glyphs.items, pos, backtrack_class_def, input_class_def, lookahead_class_def, lookup_flag, options);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;

        // Chaining rules match three regions around `pos`: backtrack before the
        // input, input at `pos`, and lookahead after the input.
        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        if (backtrack_count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        var matched = true;
        for (0..backtrack_count) |i| {
            const expected_class = try readU16(table, cursor + i * 2);
            const actual_class = (try window.backtrackClassAt(i)) orelse {
                matched = false;
                break;
            };
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += backtrack_count * 2;

        const input_count = try readU16(table, cursor);
        cursor += 2;
        if (input_count == 0) continue;
        if (input_count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        const input_indices = (try window.inputSlice(input_count)) orelse continue;
        for (1..input_count) |i| {
            const expected_class = try readU16(table, cursor + (i - 1) * 2);
            const actual_class = (try window.inputClassAt(i)) orelse {
                matched = false;
                break;
            };
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += (@as(usize, input_count) - 1) * 2;

        const lookahead_count = try readU16(table, cursor);
        cursor += 2;
        if (lookahead_count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;
        if (!try window.ensureLookaheadCount(input_count, lookahead_count)) continue;
        for (0..lookahead_count) |i| {
            const expected_class = try readU16(table, cursor + i * 2);
            const actual_class = (try window.lookaheadClassAt(input_count, i)) orelse {
                matched = false;
                break;
            };
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += lookahead_count * 2;

        const subst_count = try readU16(table, cursor);
        cursor += 2;
        try markUnsafeChainingMatch(
            allocator,
            options,
            window.backtrack_indices[0..backtrack_count],
            input_indices,
            window.lookahead_indices[0..lookahead_count],
        );
        const glyph_count_before = glyphs.items.len;
        try applySubstitutionRecordsMapped(table, glyphs, cursor, subst_count, input_indices, allocator, options);
        const original_next = input_indices[input_count - 1] + 1;
        return .{
            .matched = true,
            .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
        };
    }
    return .{};
}

fn applyChainingCoverageSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const parsed_subtable = try accelerator_root.build.chaining_coverage.parser.parse(table, subtable_offset) orelse return;
    var pos: usize = 0;
    while (pos < glyphs.items.len) {
        const result = try applyChainingCoverageSubstitutionAt(table, parsed_subtable, glyphs, pos, allocator, lookup_flag, options);
        pos = if (result.matched) @max(pos + 1, result.next_pos) else pos + 1;
    }
}

fn applyChainingCoverageSubstitutionAt(table: Table, subtable_info: ChainingCoverageSubtable, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    if (!sourceFeatureAllowsGlyph(options, pos)) return .{};
    if (pos >= glyphs.items.len) return .{};
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) return .{};
    var input_indices_buf: [64]usize = undefined;
    if (subtable_info.input_count > input_indices_buf.len) return error.UnsupportedGsub;
    if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..subtable_info.input_count], false, pos)) return .{};
    if (!try coverageIndicesMatch(table, subtable_info.subtable_offset, glyphs.items, input_indices_buf[0..subtable_info.input_count], subtable_info.input_offsets_pos)) return .{};
    var backtrack_indices_buf: [64]usize = undefined;
    if (subtable_info.backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGsub;
    if (!collectBacktrackUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, backtrack_indices_buf[0..subtable_info.backtrack_count], true, pos)) return .{};
    const lookahead_start = input_indices_buf[subtable_info.input_count - 1] + 1;
    var lookahead_indices_buf: [64]usize = undefined;
    if (subtable_info.lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGsub;
    if (!collectForwardUnignoredGlyphs(glyphs.items, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..subtable_info.lookahead_count], true, pos)) return .{};
    if (!try coverageIndicesMatch(table, subtable_info.subtable_offset, glyphs.items, backtrack_indices_buf[0..subtable_info.backtrack_count], subtable_info.backtrack_offsets_pos)) return .{};
    if (!try coverageIndicesMatch(table, subtable_info.subtable_offset, glyphs.items, lookahead_indices_buf[0..subtable_info.lookahead_count], subtable_info.lookahead_offsets_pos)) return .{};
    try markUnsafeChainingMatch(
        allocator,
        options,
        backtrack_indices_buf[0..subtable_info.backtrack_count],
        input_indices_buf[0..subtable_info.input_count],
        lookahead_indices_buf[0..subtable_info.lookahead_count],
    );
    if (try applyFastChainingSingleRecords(table, subtable_info, glyphs, input_indices_buf[0..subtable_info.input_count], options)) {
        return .{ .matched = true, .next_pos = input_indices_buf[subtable_info.input_count - 1] + 1 };
    }
    const glyph_count_before = glyphs.items.len;
    try applySubstitutionRecordsMapped(table, glyphs, subtable_info.records_pos, subtable_info.subst_count, input_indices_buf[0..subtable_info.input_count], allocator, options);
    const original_next = input_indices_buf[subtable_info.input_count - 1] + 1;
    return .{
        .matched = true,
        .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
    };
}

fn applyAcceleratedChainingCoverageSubstitutionAt(table: Table, subtable_info: ChainingCoverageSubtable, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    // The lookup accelerator groups format-3 chaining subtables by their first
    // input Coverage. Reuse that proof here and only test the remaining input
    // coverages plus the backtrack/lookahead regions.
    if (subtable_info.input_count == 0) return .{};
    var input_indices_buf: [64]usize = undefined;
    if (subtable_info.input_count > input_indices_buf.len) return error.UnsupportedGsub;
    if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..subtable_info.input_count], false, pos)) return .{};
    if (input_indices_buf[0] != pos) return .{};
    if (!try coverageIndicesMatchFrom(table, subtable_info.subtable_offset, glyphs.items, input_indices_buf[0..subtable_info.input_count], subtable_info.input_offsets_pos, 1)) return .{};
    var backtrack_indices_buf: [64]usize = undefined;
    if (subtable_info.backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGsub;
    if (!collectBacktrackUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, backtrack_indices_buf[0..subtable_info.backtrack_count], true, pos)) return .{};
    const lookahead_start = input_indices_buf[subtable_info.input_count - 1] + 1;
    var lookahead_indices_buf: [64]usize = undefined;
    if (subtable_info.lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGsub;
    if (!collectForwardUnignoredGlyphs(glyphs.items, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..subtable_info.lookahead_count], true, pos)) return .{};
    if (!try coverageIndicesMatch(table, subtable_info.subtable_offset, glyphs.items, backtrack_indices_buf[0..subtable_info.backtrack_count], subtable_info.backtrack_offsets_pos)) return .{};
    if (!try coverageIndicesMatch(table, subtable_info.subtable_offset, glyphs.items, lookahead_indices_buf[0..subtable_info.lookahead_count], subtable_info.lookahead_offsets_pos)) return .{};
    try markUnsafeChainingMatch(
        allocator,
        options,
        backtrack_indices_buf[0..subtable_info.backtrack_count],
        input_indices_buf[0..subtable_info.input_count],
        lookahead_indices_buf[0..subtable_info.lookahead_count],
    );
    const glyph_count_before = glyphs.items.len;
    try applySubstitutionRecordsMapped(table, glyphs, subtable_info.records_pos, subtable_info.subst_count, input_indices_buf[0..subtable_info.input_count], allocator, options);
    const original_next = input_indices_buf[subtable_info.input_count - 1] + 1;
    return .{
        .matched = true,
        .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
    };
}

fn applyAcceleratedChainingCoverageNoContextAt(table: Table, subtable_info: ChainingCoverageSubtable, glyphs: *std.ArrayList(GlyphId), pos: usize, second_glyph_index: ?usize, third_glyph_index: ?usize, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    if (subtable_info.input_count == 0 or subtable_info.input_count > 3) return .{};
    var input_indices_buf: [3]usize = undefined;
    input_indices_buf[0] = pos;
    if (subtable_info.input_count > 1) {
        input_indices_buf[1] = second_glyph_index orelse return .{};
    }
    if (subtable_info.input_count > 2) {
        input_indices_buf[2] = third_glyph_index orelse return .{};
    }
    const input_indices = input_indices_buf[0..subtable_info.input_count];
    if (subtable_info.input_count > 1) {
        const coverage_offset = if (subtable_info.second_input_coverage_offset != 0)
            subtable_info.second_input_coverage_offset
        else
            try checkedRequiredCoverageOffset(table, subtable_info.subtable_offset, try readU16(table, subtable_info.input_offsets_pos + 2));
        if (try table_core.coverage.index(table, coverage_offset, glyphs.items[input_indices[1]]) == null) return .{};
    }
    if (subtable_info.input_count > 2) {
        const coverage_offset = if (subtable_info.third_input_coverage_offset != 0)
            subtable_info.third_input_coverage_offset
        else
            try checkedRequiredCoverageOffset(table, subtable_info.subtable_offset, try readU16(table, subtable_info.input_offsets_pos + 4));
        if (try table_core.coverage.index(table, coverage_offset, glyphs.items[input_indices[2]]) == null) return .{};
    }
    try markUnsafeContextMatch(allocator, options, input_indices);
    if (try applyFastChainingSingleRecords(table, subtable_info, glyphs, input_indices, options)) {
        return .{ .matched = true, .next_pos = input_indices[input_indices.len - 1] + 1 };
    }
    const glyph_count_before = glyphs.items.len;
    try applySubstitutionRecordsMapped(table, glyphs, subtable_info.records_pos, subtable_info.subst_count, input_indices, allocator, options);
    const original_next = input_indices[input_indices.len - 1] + 1;
    return .{
        .matched = true,
        .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
    };
}

fn applyFastChainingSingleRecords(table: Table, subtable: ChainingCoverageSubtable, glyphs: *std.ArrayList(GlyphId), input_indices: []const usize, options: LookupOptions) GsubError!bool {
    if (subtable.fast_record_count == 0) return false;
    for (subtable.fast_records[0..subtable.fast_record_count]) |record| {
        if (record.sequence_index >= input_indices.len) return false;
        const target_index = input_indices[record.sequence_index];
        if (target_index >= glyphs.items.len) continue;
        _ = try applySingleSubstitutionAccelerated(table, record.accelerator, glyphs, target_index, options);
    }
    return true;
}

const CoverageSequenceKind = enum {
    backtrack,
    input,
    lookahead,
};

fn collectForwardUnignoredGlyphs(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions, out: []usize, context_match: bool, anchor_index: usize) bool {
    // Contextual GSUB sequences are written in terms of glyphs that the lookup
    // participates in. IgnoreBase/Ligature/Mark and mark attachment filters
    // remove glyphs from matching, but those skipped glyphs must remain in the
    // buffer so sequence indexes can still target the original glyph positions.
    // HarfBuzz also skips default-ignorable joiners only for contextual
    // backtrack/lookahead matching when the active feature allows auto joiners;
    // input matching keeps ZWNJ/ZWJ visible unless LookupFlag itself ignores it.
    return collectForwardUnignoredGlyphPrefix(glyphs, start, lookup_flag, options, out, context_match, anchor_index) == out.len;
}

fn collectForwardUnignoredGlyphPrefix(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions, out: []usize, context_match: bool, anchor_index: usize) usize {
    var out_i: usize = 0;
    var glyph_i = start;
    const anchor_syllable = sourceSyllableForGlyph(options, anchor_index);
    while (glyph_i < glyphs.len and out_i < out.len) : (glyph_i += 1) {
        if (contextualMaySkipGlyph(lookup_flag, options, glyphs, glyph_i, context_match)) continue;
        if (!sourceSyllableAllowsGlyph(options, anchor_syllable, glyph_i)) break;
        out[out_i] = glyph_i;
        out_i += 1;
    }
    return out_i;
}

fn nextUnignoredGlyph(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions, context_match: bool, anchor_index: usize) ?GlyphId {
    const index = nextUnignoredGlyphIndex(glyphs, start, lookup_flag, options, context_match, anchor_index) orelse return null;
    return glyphs[index];
}

fn nextUnignoredGlyphIndex(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions, context_match: bool, anchor_index: usize) ?usize {
    var glyph_i = start;
    const anchor_syllable = sourceSyllableForGlyph(options, anchor_index);
    while (glyph_i < glyphs.len) : (glyph_i += 1) {
        if (contextualMaySkipGlyph(lookup_flag, options, glyphs, glyph_i, context_match)) continue;
        if (!sourceSyllableAllowsGlyph(options, anchor_syllable, glyph_i)) return null;
        return glyph_i;
    }
    return null;
}

fn collectBacktrackUnignoredGlyphs(glyphs: []const GlyphId, pos: usize, lookup_flag: u16, options: LookupOptions, out: []usize, context_match: bool, anchor_index: usize) bool {
    var out_i: usize = 0;
    var glyph_i = pos;
    const anchor_syllable = sourceSyllableForGlyph(options, anchor_index);
    while (glyph_i > 0 and out_i < out.len) {
        glyph_i -= 1;
        if (contextualMaySkipGlyph(lookup_flag, options, glyphs, glyph_i, context_match)) continue;
        if (!sourceSyllableAllowsGlyph(options, anchor_syllable, glyph_i)) return false;
        out[out_i] = glyph_i;
        out_i += 1;
    }
    return out_i == out.len;
}

fn coverageIndicesMatch(table: Table, base_offset: usize, glyphs: []const GlyphId, indices: []const usize, offsets_pos: usize) GsubError!bool {
    return coverageIndicesMatchFrom(table, base_offset, glyphs, indices, offsets_pos, 0);
}

fn coverageIndicesMatchFrom(table: Table, base_offset: usize, glyphs: []const GlyphId, indices: []const usize, offsets_pos: usize, start: usize) GsubError!bool {
    var i = start;
    while (i < indices.len) : (i += 1) {
        const glyph_index = indices[i];
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16(table, offsets_pos + i * 2));
        if (try table_core.coverage.index(table, coverage_offset, glyphs[glyph_index]) == null) return false;
    }
    return true;
}

fn coverageSequenceMatches(table: Table, base_offset: usize, glyphs: []const GlyphId, pos: usize, offsets_pos: usize, count: usize, kind: CoverageSequenceKind) GsubError!bool {
    switch (kind) {
        .backtrack => if (pos < count) return false,
        .input, .lookahead => if (pos + count > glyphs.len) return false,
    }
    for (0..count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16(table, offsets_pos + i * 2));
        const glyph_index = switch (kind) {
            .backtrack => pos - 1 - i,
            .input, .lookahead => pos + i,
        };
        if (try table_core.coverage.index(table, coverage_offset, glyphs[glyph_index]) == null) return false;
    }
    return true;
}

fn applyChainingRuleSet(table: Table, chain_set_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    const rule_count = try readU16(table, chain_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = chain_set_offset + try readU16(table, chain_set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;

        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGsub;
        if (!collectBacktrackUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count], true, pos)) continue;
        var matched = true;
        for (0..backtrack_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs.items[backtrack_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += backtrack_count * 2;

        const input_count = try readU16(table, cursor);
        cursor += 2;
        if (input_count == 0) continue;
        var input_indices_buf: [64]usize = undefined;
        if (input_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..input_count], false, pos)) continue;
        for (1..input_count) |i| {
            const expected = try readU16(table, cursor + (i - 1) * 2);
            if (glyphs.items[input_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += (@as(usize, input_count) - 1) * 2;

        const lookahead_count = try readU16(table, cursor);
        cursor += 2;
        const lookahead_start = input_indices_buf[input_count - 1] + 1;
        var lookahead_indices_buf: [64]usize = undefined;
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count], true, pos)) continue;
        for (0..lookahead_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs.items[lookahead_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += lookahead_count * 2;

        const subst_count = try readU16(table, cursor);
        cursor += 2;
        try markUnsafeChainingMatch(
            allocator,
            options,
            backtrack_indices_buf[0..backtrack_count],
            input_indices_buf[0..input_count],
            lookahead_indices_buf[0..lookahead_count],
        );
        const glyph_count_before = glyphs.items.len;
        try applySubstitutionRecordsMapped(table, glyphs, cursor, subst_count, input_indices_buf[0..input_count], allocator, options);
        const original_next = input_indices_buf[input_count - 1] + 1;
        return .{
            .matched = true,
            .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
        };
    }
    return .{};
}

const NestedGlyphChange = struct {
    /// Number of matched input glyphs replaced by the nested lookup, counting
    /// the target glyph. Non-ligature substitutions replace a contiguous target
    /// run; ligatures additionally fill `component_offsets` because LookupFlag
    /// ignored glyphs may remain physically between matched components.
    removed_len: usize = 1,
    inserted_len: usize = 1,
    component_offsets: ?[max_ligature_components]usize = null,
    component_count: usize = 0,
};

const ContextApplyResult = struct {
    matched: bool = false,
    next_pos: usize = 0,
};

fn contextNextPosAfterMutation(original_next: usize, match_start: usize, glyph_count_before: usize, glyph_count_after: usize) usize {
    if (glyph_count_after >= glyph_count_before) {
        return original_next + (glyph_count_after - glyph_count_before);
    }

    // HarfBuzz resumes a contextual lookup at the adjusted end of the match.
    // A nested ligature or deletion shifts that end left, but it cannot rewind
    // before the position immediately after the current match start. This is
    // essential when adjacent candidates move into the just-consumed range.
    return @max(match_start + 1, original_next -| (glyph_count_before - glyph_count_after));
}

fn markUnsafeContextMatch(
    allocator: std.mem.Allocator,
    options: LookupOptions,
    glyph_indices: []const usize,
) std.mem.Allocator.Error!void {
    const safety = options.source_boundaries orelse return;
    const sources = options.glyph_source_indices orelse return;
    try safety.markMatchedGlyphs(
        allocator,
        sources.items,
        glyph_indices,
    );
}

fn markUnsafeChainingMatch(
    allocator: std.mem.Allocator,
    options: LookupOptions,
    backtrack: []const usize,
    input: []const usize,
    lookahead: []const usize,
) std.mem.Allocator.Error!void {
    const safety = options.source_boundaries orelse return;
    const sources = options.glyph_source_indices orelse return;
    try safety.markMatchedRegions(
        allocator,
        sources.items,
        backtrack,
        input,
        lookahead,
    );
}

fn applySubstitutionRecordsMapped(table: Table, glyphs: *std.ArrayList(GlyphId), records_offset: usize, record_count: usize, input_indices: []const usize, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    if (!table.assume_validated) {
        try ensureSubstitutionRecordsWithin(table, records_offset, record_count, input_indices.len);
        try ensureSubstitutionRecordMarkFilteringSetsValid(table, records_offset, record_count, options);
    }
    if (try applySingleSubstitutionRecordsMappedFast(table, glyphs, records_offset, record_count, input_indices, options)) return;

    // SequenceLookupRecord indexes address a mutable match-position array. It
    // starts with the input sequence, but OpenType implementations extend it
    // when a nested MultipleSubst grows the buffer: the inserted positions are
    // spliced immediately after the current SequenceIndex. Consequently, a
    // later index that was outside the original input count can become valid,
    // and an originally valid later index can name a newly inserted glyph.
    //
    // Each entry stores its current physical glyph-buffer index. The parallel
    // live map preserves deletion semantics: a repeated record for a deleted
    // position must not accidentally target the glyph that shifted into that
    // physical slot.
    var mapped_buf: [64]usize = undefined;
    var mapped_live_buf: [64]bool = undefined;
    if (input_indices.len > mapped_buf.len) return error.UnsupportedGsub;
    @memcpy(mapped_buf[0..input_indices.len], input_indices);
    var mapped_len = input_indices.len;
    @memset(mapped_live_buf[0..mapped_len], true);

    for (0..record_count) |subst_i| {
        const record_offset = records_offset + subst_i * 4;
        const sequence_index = try readU16(table, record_offset);
        const lookup_index = try readU16(table, record_offset + 2);
        if (sequence_index >= mapped_len) continue;
        if (!mapped_live_buf[sequence_index]) continue;
        const target_index = mapped_buf[sequence_index];
        if (target_index >= glyphs.items.len) continue;
        const change = try applyNestedGlyphLookup(table, glyphs, target_index, lookup_index, allocator, options);
        if (change.removed_len == change.inserted_len) continue;
        if (change.component_offsets) |component_offsets| {
            for (mapped_buf[0..mapped_len], 0..) |*mapped_index, mapped_i| {
                if (!mapped_live_buf[mapped_i]) continue;
                if (mapped_index.* <= target_index) continue;
                const relative_index = mapped_index.* - target_index;
                var removed_before: usize = 0;
                var consumed_component = false;
                for (component_offsets[1..change.component_count]) |component_offset| {
                    if (relative_index == component_offset) {
                        consumed_component = true;
                        break;
                    }
                    if (component_offset < relative_index) removed_before += 1;
                }
                if (consumed_component) {
                    mapped_index.* = target_index;
                } else {
                    mapped_index.* -= removed_before;
                }
            }

            // HarfBuzz removes the length delta's worth of logical positions
            // immediately after the lookup's SequenceIndex, even when the
            // nested ligature used a different LookupFlag and physically
            // consumed a later component around an ignored glyph. Compact the
            // mapped sequence the same way after resolving physical indices.
            // This makes the next SequenceIndex name the old later component,
            // which may now be the replacement ligature.
            const remove_count = @min(
                change.removed_len - change.inserted_len,
                mapped_len -| (@as(usize, sequence_index) + 1),
            );
            if (remove_count != 0) {
                const remove_start = @as(usize, sequence_index) + 1;
                const remove_end = remove_start + remove_count;
                std.mem.copyForwards(
                    usize,
                    mapped_buf[remove_start .. mapped_len - remove_count],
                    mapped_buf[remove_end..mapped_len],
                );
                std.mem.copyForwards(
                    bool,
                    mapped_live_buf[remove_start .. mapped_len - remove_count],
                    mapped_live_buf[remove_end..mapped_len],
                );
                mapped_len -= remove_count;
            }
            continue;
        }
        if (change.inserted_len > change.removed_len) {
            const added = change.inserted_len - change.removed_len;
            // First account for the physical insertion in every existing match
            // position. Then extend the logical match-position array in the
            // same place as HarfBuzz's apply_lookup(): immediately after the
            // SequenceIndex whose nested lookup caused the growth.
            for (mapped_buf[0..mapped_len], 0..) |*mapped_index, mapped_i| {
                if (!mapped_live_buf[mapped_i]) continue;
                if (mapped_index.* < target_index) continue;
                if (mapped_index.* < target_index + change.removed_len) {
                    mapped_index.* = target_index;
                } else {
                    mapped_index.* += added;
                }
            }

            const insert_at = @as(usize, sequence_index) + 1;
            if (mapped_len + added > mapped_buf.len) return error.UnsupportedGsub;
            std.mem.copyBackwards(
                usize,
                mapped_buf[insert_at + added .. mapped_len + added],
                mapped_buf[insert_at..mapped_len],
            );
            std.mem.copyBackwards(
                bool,
                mapped_live_buf[insert_at + added .. mapped_len + added],
                mapped_live_buf[insert_at..mapped_len],
            );
            for (0..added) |added_i| {
                mapped_buf[insert_at + added_i] = target_index + 1 + added_i;
                mapped_live_buf[insert_at + added_i] = true;
            }
            mapped_len += added;
            continue;
        }
        for (mapped_buf[0..mapped_len], 0..) |*mapped_index, mapped_i| {
            if (!mapped_live_buf[mapped_i]) continue;
            if (mapped_index.* < target_index) continue;
            if (mapped_index.* < target_index + change.removed_len) {
                // A non-ligature nested lookup consumed this input glyph. If
                // it produced replacements, later records for the same
                // sequence index operate on the first replacement. If it was a
                // deletion, there is no surviving glyph to target.
                if (change.inserted_len == 0) {
                    mapped_live_buf[mapped_i] = false;
                } else {
                    mapped_index.* = target_index;
                }
            } else {
                if (change.removed_len > change.inserted_len) {
                    mapped_index.* -= change.removed_len - change.inserted_len;
                }
            }
        }
    }
}

const max_fast_single_records = 64;

fn applySingleSubstitutionRecordsMappedFast(table: Table, glyphs: *std.ArrayList(GlyphId), records_offset: usize, record_count: usize, input_indices: []const usize, options: LookupOptions) GsubError!bool {
    if (record_count == 0) return true;
    if (record_count > max_fast_single_records) return false;
    if (try applyAcceleratedSingleSubstitutionRecordsMapped(table, glyphs, records_offset, record_count, input_indices, options)) return true;

    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    var target_indices: [max_fast_single_records]usize = undefined;
    var lookup_offsets: [max_fast_single_records]usize = undefined;
    var lookup_flags: [max_fast_single_records]u16 = undefined;
    var subtable_counts: [max_fast_single_records]u16 = undefined;
    var lookup_indices: [max_fast_single_records]u16 = undefined;
    var single_accelerators: [max_fast_single_records]SingleSubstAccelerator = undefined;

    for (0..record_count) |record_i| {
        const record_offset = records_offset + record_i * 4;
        const sequence_index = try readU16(table, record_offset);
        const lookup_index = try readU16(table, record_offset + 2);
        if (sequence_index >= input_indices.len) return false;
        if (lookup_index >= lookup_count) return error.BadGsub;
        var single_accelerator = SingleSubstAccelerator{};
        var lookup_offset: usize = 0;
        var lookup_flag: u16 = 0;
        var subtable_count: u16 = 0;
        var cached = false;
        if (options.lookup_accelerators) |accelerators| {
            if (lookup_index < accelerators.len and accelerators[lookup_index].single_subst.enabled) {
                single_accelerator = accelerators[lookup_index].single_subst;
                cached = true;
            }
        }
        for (lookup_indices[0..record_i], 0..) |existing_index, existing_i| {
            if (existing_index != lookup_index) continue;
            lookup_offset = lookup_offsets[existing_i];
            lookup_flag = lookup_flags[existing_i];
            subtable_count = subtable_counts[existing_i];
            single_accelerator = single_accelerators[existing_i];
            cached = true;
            break;
        }
        if (!cached or !single_accelerator.enabled) {
            lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
            if (try readU16(table, lookup_offset) != 1) return false;
            lookup_flag = try readU16(table, lookup_offset + 2);
            subtable_count = try readU16(table, lookup_offset + 4);
        }
        lookup_indices[record_i] = lookup_index;
        target_indices[record_i] = input_indices[sequence_index];
        lookup_offsets[record_i] = lookup_offset;
        lookup_flags[record_i] = lookup_flag;
        subtable_counts[record_i] = subtable_count;
        single_accelerators[record_i] = single_accelerator;
    }

    for (0..record_count) |record_i| {
        if (target_indices[record_i] >= glyphs.items.len) continue;
        if (single_accelerators[record_i].enabled) {
            _ = try applySingleSubstitutionAccelerated(table, single_accelerators[record_i], glyphs, target_indices[record_i], options);
            continue;
        }
        var lookup_options = options;
        if ((lookup_flags[record_i] & 0x0010) != 0) {
            lookup_options.active_mark_filtering_set = try readU16(table, lookup_offsets[record_i] + 6 + @as(usize, subtable_counts[record_i]) * 2);
            try validateMarkFilteringSetIndex(lookup_options);
        }
        for (0..subtable_counts[record_i]) |subtable_i| {
            const subtable_offset = lookup_offsets[record_i] + try readU16(table, lookup_offsets[record_i] + 6 + subtable_i * 2);
            if (try applySingleSubstitutionAt(table, subtable_offset, glyphs, target_indices[record_i], lookup_flags[record_i], lookup_options)) break;
        }
    }
    return true;
}

fn applyAcceleratedSingleSubstitutionRecordsMapped(table: Table, glyphs: *std.ArrayList(GlyphId), records_offset: usize, record_count: usize, input_indices: []const usize, options: LookupOptions) GsubError!bool {
    const accelerators = options.lookup_accelerators orelse return false;
    var target_indices: [max_fast_single_records]usize = undefined;
    var single_accelerators: [max_fast_single_records]SingleSubstAccelerator = undefined;

    for (0..record_count) |record_i| {
        const record_offset = records_offset + record_i * 4;
        const sequence_index = try readU16(table, record_offset);
        const lookup_index = try readU16(table, record_offset + 2);
        if (sequence_index >= input_indices.len) return false;
        if (lookup_index >= accelerators.len) return error.BadGsub;
        const single_accelerator = accelerators[lookup_index].single_subst;
        if (!single_accelerator.enabled) return false;
        target_indices[record_i] = input_indices[sequence_index];
        single_accelerators[record_i] = single_accelerator;
    }

    for (0..record_count) |record_i| {
        if (target_indices[record_i] >= glyphs.items.len) continue;
        _ = try applySingleSubstitutionAccelerated(table, single_accelerators[record_i], glyphs, target_indices[record_i], options);
    }
    return true;
}

fn ensureSubstitutionRecordListWithin(table: Table, records_offset: usize, record_count: usize) GsubError!void {
    // Contextual lookup records are applied eagerly and may mutate the glyph
    // stream. Reject a truncated record array before the first nested lookup so
    // malformed fonts cannot leave the caller with a partially substituted run.
    if (records_offset > table.length) return error.BadGsub;
    if (record_count > (table.length - records_offset) / 4) return error.BadGsub;
}

fn ensureSubstitutionRecordsWithin(table: Table, records_offset: usize, record_count: usize, input_count: usize) GsubError!void {
    try ensureSubstitutionRecordListWithin(table, records_offset, record_count);
    try ensureSubstitutionRecordReferencesWithin(table, records_offset, record_count, input_count);
}

fn ensureSubstitutionRecordReferencesWithin(table: Table, records_offset: usize, record_count: usize, input_count: usize) GsubError!void {
    // A complete SequenceLookupRecord array is not enough for atomic
    // contextual application: each record must target a glyph inside the
    // already-matched input sequence and must name a real lookup. Preflight
    // both fields before the first nested lookup mutates `glyphs`, otherwise a
    // malformed later record could either be silently skipped or leave earlier
    // substitutions visible to the caller.
    _ = input_count;
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16BadGsub(table, lookup_list_offset);
    for (0..record_count) |record_i| {
        const record_offset = records_offset + record_i * 4;
        // HarfBuzz safely ignores an out-of-range SequenceIndex while applying
        // the remaining records in design order. Such records occur in shipped
        // fonts (including TestShapeLana.ttf), so validate their lookup target
        // but do not reject the entire font.
        const lookup_index = try readU16BadGsub(table, record_offset + 2);
        if (lookup_index >= lookup_count) return error.BadGsub;
        const lookup_offset_pos = lookup_list_offset + 2 + @as(usize, lookup_index) * 2;
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16BadGsub(table, lookup_offset_pos));
        if (table.glyph_count != null) {
            // Font-load validation already walks every LookupList entry as a
            // top-level lookup. Contextual records may reference the same
            // extension/chaining lookups thousands of times in complex fonts;
            // validating only the fixed header here preserves reference bounds
            // while avoiding recursive revalidation of the referenced payload.
            _ = try ensureLookupFixedHeaderWithin(table, lookup_offset);
        } else {
            try ensureLookupHeaderWithin(table, lookup_offset);
        }
    }
}

fn ensureSubstitutionRecordMarkFilteringSetsValid(table: Table, records_offset: usize, record_count: usize, options: LookupOptions) GsubError!void {
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    for (0..record_count) |record_i| {
        const record_offset = records_offset + record_i * 4;
        const lookup_index = try readU16BadGsub(table, record_offset + 2);
        const lookup_offset_pos = lookup_list_offset + 2 + @as(usize, lookup_index) * 2;
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16BadGsub(table, lookup_offset_pos));
        const lookup_flag = try readU16BadGsub(table, lookup_offset + 2);
        if ((lookup_flag & 0x0010) == 0) continue;
        const subtable_count = try readU16BadGsub(table, lookup_offset + 4);
        try validateMarkFilteringSetIndex(.{
            .mark_filtering_sets = options.mark_filtering_sets,
            .active_mark_filtering_set = try readU16BadGsub(table, lookup_offset + 6 + @as(usize, subtable_count) * 2),
        });
    }
}

fn ensureExtensionSubstitutionLookupPayloadsWithin(table: Table, lookup_offset: usize, subtable_count: u16) GsubError!void {
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = try checkedRequiredSubtableOffset(table, lookup_offset, try readU16BadGsub(table, lookup_offset + 6 + subtable_i * 2));
        try ensureExtensionSubstitutionPayloadWithin(table, subtable_offset);
    }
}

fn ensureLookupHeaderWithin(table: Table, lookup_offset: usize) GsubError!void {
    const lookup_type = try ensureLookupFixedHeaderWithin(table, lookup_offset);
    if (lookup_type == 7 and !table.assume_validated) {
        const subtable_count = try readU16BadGsub(table, lookup_offset + 4);
        try ensureExtensionSubstitutionLookupPayloadsWithin(table, lookup_offset, subtable_count);
    }
}

fn ensureLookupFixedHeaderWithin(table: Table, lookup_offset: usize) GsubError!u16 {
    try accelerator_root.build.lookup.header.validate(table, lookup_offset);
    const lookup_type = try readU16BadGsub(table, lookup_offset);
    return lookup_type;
}

fn ensureSubstitutionLookupSubtablesWithin(table: Table, lookup_offset: usize, lookup_type: u16, subtable_count: u16) GsubError!void {
    switch (lookup_type) {
        1, 2, 3, 4, 5, 6, 8 => {},
        else => return,
    }
    for (0..subtable_count) |subtable_i| {
        // Lookup.SubTable offsets are mandatory child pointers for supported
        // lookups. Offset zero would alias the Lookup header as a subtable and
        // let lookup type/flag/count bytes masquerade as substitution payload.
        const subtable_offset = try checkedRequiredSubtableOffset(table, lookup_offset, try readU16BadGsub(table, lookup_offset + 6 + subtable_i * 2));
        try ensureSubstitutionSubtableFixedHeaderWithin(table, subtable_offset, lookup_type);
        try ensureSubstitutionSubtableVariableDataWithin(table, subtable_offset, lookup_type);
    }
}

fn ensureSubstitutionLookupSubtablesWithinForShaping(table: Table, lookup_offset: usize, lookup_type: u16, subtable_count: u16) GsubError!void {
    switch (lookup_type) {
        1, 2, 3, 4, 5, 6, 8 => {},
        else => return,
    }
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = try checkedRequiredSubtableOffset(table, lookup_offset, try readU16BadGsub(table, lookup_offset + 6 + subtable_i * 2));
        try ensureSubstitutionSubtableFixedHeaderWithin(table, subtable_offset, lookup_type);
        try ensureSubstitutionSubtableVariableDataWithinForShaping(table, subtable_offset, lookup_type);
    }
}

fn ensureLigatureLookupSubtablesWithinForShaping(table: Table, lookup_offset: usize, subtable_count: u16) GsubError!void {
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = try checkedRequiredSubtableOffset(table, lookup_offset, try readU16BadGsub(table, lookup_offset + 6 + subtable_i * 2));
        try ensureSubstitutionSubtableFixedHeaderWithin(table, subtable_offset, 4);
        try ensureLigatureSubstitutionSubtableWithinForShaping(table, subtable_offset);
    }
}

fn ensureExtensionSubstitutionPayloadWithin(table: Table, subtable_offset: usize) GsubError!void {
    // A contextual record may reference ExtensionSubst after earlier records
    // have already mutated the glyph stream. Preflight both the wrapper and the
    // wrapped subtable's fixed header so a malformed extension payload fails
    // before any record in the contextual match is applied.
    if (subtable_offset > table.length or table.length - subtable_offset < 8) return error.BadGsub;
    const subst_format = try readU16BadGsub(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const extension_lookup_type = try readU16BadGsub(table, subtable_offset + 2);
    if (extension_lookup_type == 7) return error.UnsupportedGsub;
    const extension_subtable = try checkedExtensionSubtablePayloadOffset(table, subtable_offset, try readU32BadGsub(table, subtable_offset + 4));
    try ensureSubstitutionSubtableFixedHeaderWithin(table, extension_subtable, extension_lookup_type);
    try ensureSubstitutionSubtableVariableDataWithin(table, extension_subtable, extension_lookup_type);
}

fn ensureSubstitutionSubtableFixedHeaderWithin(table: Table, subtable_offset: usize, lookup_type: u16) GsubError!void {
    if (subtable_offset > table.length or table.length - subtable_offset < 2) return error.BadGsub;
    const subst_format = try readU16BadGsub(table, subtable_offset);
    const min_len: usize = switch (lookup_type) {
        1, 2, 3, 4 => 6,
        5 => switch (subst_format) {
            1, 3 => 6,
            2 => 8,
            else => return error.UnsupportedGsub,
        },
        6 => switch (subst_format) {
            1 => 6,
            2 => 12,
            3 => 4,
            else => return error.UnsupportedGsub,
        },
        8 => 6,
        else => return,
    };
    if (table.length - subtable_offset < min_len) return error.BadGsub;
}

fn ensureSubstitutionSubtableVariableDataWithin(table: Table, subtable_offset: usize, lookup_type: u16) GsubError!void {
    switch (lookup_type) {
        1 => try ensureSingleSubstitutionSubtableWithin(table, subtable_offset),
        2 => try ensureMultipleSubstitutionSubtableWithin(table, subtable_offset),
        3 => try ensureAlternateSubstitutionSubtableWithin(table, subtable_offset),
        4 => try ensureLigatureSubstitutionSubtableWithin(table, subtable_offset),
        5 => try ensureContextSubstitutionSubtableWithin(table, subtable_offset),
        6 => try ensureChainingContextSubstitutionSubtableWithin(table, subtable_offset),
        8 => try ensureReverseChainingSingleSubstitutionSubtableWithin(table, subtable_offset),
        else => {},
    }
}

fn ensureSubstitutionSubtableVariableDataWithinForShaping(table: Table, subtable_offset: usize, lookup_type: u16) GsubError!void {
    switch (lookup_type) {
        // Chaining input/backtrack/lookahead Coverage tables are boolean
        // membership sets; unlike a top-level coverage, their numeric index is
        // never used to address a parallel array. HarfBuzz accepts duplicate
        // format-1 glyph IDs in these sets (TestGPOSOne.ttf contains one), so
        // validate bounds and glyph IDs without imposing strict order.
        6 => try ensureChainingContextSubstitutionSubtableWithinForShaping(table, subtable_offset),
        else => try ensureSubstitutionSubtableVariableDataWithin(table, subtable_offset, lookup_type),
    }
}

fn ensureSingleSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    const subst_format = try readU16BadGsub(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
    switch (subst_format) {
        // Format 1 explicitly defines modulo-16-bit results. A lookup may use
        // an intermediate ID outside maxp as both this lookup's output and a
        // later format-1 lookup's Coverage input (the OpenType AOTS modulo
        // fixture does exactly this). Validate the Coverage topology and full
        // 16-bit domain, but defer renderable-glyph bounds until the complete
        // GSUB lookup sequence has finished.
        1 => if (table.allow_transient_single_delta) {
            var transient_table = table;
            transient_table.glyph_count = null;
            try ensureCoverageTableWithin(transient_table, coverage_offset);
        } else {
            try ensureCoverageTableWithin(table, coverage_offset);
            const delta = try readI16BadGsub(table, subtable_offset + 4);
            try ensureSingleDeltaSubstitutionWithinMaxp(table, coverage_offset, delta);
        },
        2 => {
            try ensureCoverageTableWithin(table, coverage_offset);
            const glyph_count = try readU16BadGsub(table, subtable_offset + 4);
            // Format 2 Coverage indexes address the substitute glyph array
            // directly. Reject uncovered array slots at validation time instead
            // of letting shaping silently skip malformed covered glyphs.
            try ensureCoverageIndicesWithin(table, coverage_offset, glyph_count);
            try ensureBytesWithin(table, subtable_offset + 6, @as(usize, glyph_count) * 2);
            for (0..glyph_count) |glyph_i| {
                try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, subtable_offset + 6 + glyph_i * 2));
            }
        },
        else => return error.UnsupportedGsub,
    }
}

fn ensureMultipleSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    const subst_format = try readU16BadGsub(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const sequence_count = try readU16BadGsub(table, subtable_offset + 4);
    // Coverage indexes select Sequence offsets one-for-one. A dangling
    // coverage entry would otherwise make a declared substitution disappear
    // for only the affected glyph.
    try ensureCoverageIndicesWithin(table, coverage_offset, sequence_count);
    const sequence_offsets_pos = subtable_offset + 6;
    try ensureBytesWithin(table, sequence_offsets_pos, @as(usize, sequence_count) * 2);
    for (0..sequence_count) |sequence_i| {
        const sequence_relative = try readU16BadGsub(table, sequence_offsets_pos + sequence_i * 2);
        // SequenceOffset entries are required children keyed by Coverage
        // index. Offset zero would reinterpret the MultipleSubst header as a
        // Sequence table, deriving replacement glyphs from unrelated fields.
        const sequence_offset = try checkedRequiredSubtableOffset(table, subtable_offset, sequence_relative);
        const glyph_count = try readU16BadGsub(table, sequence_offset);
        try ensureBytesWithin(table, sequence_offset + 2, @as(usize, glyph_count) * 2);
        for (0..glyph_count) |glyph_i| {
            try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, sequence_offset + 2 + glyph_i * 2));
        }
    }
}

fn ensureAlternateSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    const subst_format = try readU16BadGsub(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const alternate_set_count = try readU16BadGsub(table, subtable_offset + 4);
    // AlternateSet offsets share the same coverage-index topology as
    // MultipleSubst sequences; every covered glyph needs an addressable set.
    try ensureCoverageIndicesWithin(table, coverage_offset, alternate_set_count);
    const alternate_set_offsets_pos = subtable_offset + 6;
    try ensureBytesWithin(table, alternate_set_offsets_pos, @as(usize, alternate_set_count) * 2);
    for (0..alternate_set_count) |alternate_set_i| {
        const alternate_set_relative = try readU16BadGsub(table, alternate_set_offsets_pos + alternate_set_i * 2);
        // AlternateSet offsets are required children selected by Coverage
        // index. Treating zero as a real offset aliases the AlternateSubst
        // header as an AlternateSet and can synthesize replacement glyph ids
        // from unrelated header fields.
        const alternate_set_offset = try checkedRequiredSubtableOffset(table, subtable_offset, alternate_set_relative);
        const glyph_count = try readU16BadGsub(table, alternate_set_offset);
        try ensureBytesWithin(table, alternate_set_offset + 2, @as(usize, glyph_count) * 2);
        for (0..glyph_count) |glyph_i| {
            try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, alternate_set_offset + 2 + glyph_i * 2));
        }
    }
}

fn ensureLigatureSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    const subst_format = try readU16BadGsub(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const lig_set_count = try readU16BadGsub(table, subtable_offset + 4);
    // LigatureSet offsets are selected by coverage index. Reject dangling
    // indexes up front so covered first components cannot be silently ignored.
    try ensureCoverageIndicesWithin(table, coverage_offset, lig_set_count);
    const lig_set_offsets_pos = subtable_offset + 6;
    try ensureBytesWithin(table, lig_set_offsets_pos, @as(usize, lig_set_count) * 2);
    for (0..lig_set_count) |set_i| {
        // LigatureSet offsets are required for each covered first component.
        // Zero would alias the LigatureSubst header as a LigatureSet and can
        // reinterpret coverage/offset metadata as a real ligature definition.
        const set_offset = try checkedRequiredSubtableOffset(table, subtable_offset, try readU16BadGsub(table, lig_set_offsets_pos + set_i * 2));
        const ligature_count = try readU16BadGsub(table, set_offset);
        const ligature_offsets_pos = set_offset + 2;
        try ensureBytesWithin(table, ligature_offsets_pos, @as(usize, ligature_count) * 2);
        for (0..ligature_count) |ligature_i| {
            // Ligature offsets inside a non-empty LigatureSet are required
            // children as well. Reject nulls before they can be treated as the
            // LigatureSet header and silently skipped or misread by shaping.
            const ligature_offset = try checkedRequiredSubtableOffset(table, set_offset, try readU16BadGsub(table, ligature_offsets_pos + ligature_i * 2));
            try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, ligature_offset));
            const component_count = try readU16BadGsub(table, ligature_offset + 2);
            if (component_count == 0) return error.BadGsub;
            try ensureBytesWithin(table, ligature_offset + 4, (@as(usize, component_count) - 1) * 2);
            for (1..component_count) |component_i| {
                try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, ligature_offset + 4 + (component_i - 1) * 2));
            }
        }
    }
}

fn ensureLigatureSubstitutionSubtableWithinForShaping(table: Table, subtable_offset: usize) GsubError!void {
    const subst_format = try readU16BadGsub(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const lig_set_count = try readU16BadGsub(table, subtable_offset + 4);
    try ensureCoverageIndicesWithin(table, coverage_offset, lig_set_count);
    const lig_set_offsets_pos = subtable_offset + 6;
    try ensureBytesWithin(table, lig_set_offsets_pos, @as(usize, lig_set_count) * 2);
    for (0..lig_set_count) |set_i| {
        const set_relative = try readU16BadGsub(table, lig_set_offsets_pos + set_i * 2);
        const set_offset = checkedRequiredSubtableOffset(table, subtable_offset, set_relative) catch continue;
        const ligature_count = try readU16BadGsub(table, set_offset);
        const ligature_offsets_pos = set_offset + 2;
        try ensureBytesWithin(table, ligature_offsets_pos, @as(usize, ligature_count) * 2);
        for (0..ligature_count) |ligature_i| {
            const ligature_relative = try readU16BadGsub(table, ligature_offsets_pos + ligature_i * 2);
            const ligature_offset = checkedRequiredSubtableOffset(table, set_offset, ligature_relative) catch continue;
            try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, ligature_offset));
            const component_count = try readU16BadGsub(table, ligature_offset + 2);
            if (component_count == 0) continue;
            try ensureBytesWithin(table, ligature_offset + 4, (@as(usize, component_count) - 1) * 2);
            for (1..component_count) |component_i| {
                try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, ligature_offset + 4 + (component_i - 1) * 2));
            }
        }
    }
}

fn ensureContextSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    // Contextual substitutions defer their real work to nested lookups after a
    // variable-length match structure. Validate every rule/set/coverage/record
    // array before matching so a malformed later subtable in the same lookup
    // cannot leak substitutions made by an earlier context subtable.
    const subst_format = try readU16BadGsub(table, subtable_offset);
    switch (subst_format) {
        1 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
            try ensureCoverageTableWithin(table, coverage_offset);
            const rule_set_count = try readU16BadGsub(table, subtable_offset + 4);
            const rule_set_offsets_pos = subtable_offset + 6;
            try ensureBytesWithin(table, rule_set_offsets_pos, @as(usize, rule_set_count) * 2);
            for (0..rule_set_count) |set_i| {
                const set_relative = try readU16BadGsub(table, rule_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureContextRuleSetWithin(table, try checkedSubtableOffset(table, subtable_offset, set_relative));
            }
        },
        2 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
            const class_def_offset = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 4));
            try ensureCoverageTableWithin(table, coverage_offset);
            try ensureClassDefTableWithin(table, class_def_offset);
            const class_set_count = try readU16BadGsub(table, subtable_offset + 6);
            const class_set_offsets_pos = subtable_offset + 8;
            try ensureBytesWithin(table, class_set_offsets_pos, @as(usize, class_set_count) * 2);
            for (0..class_set_count) |set_i| {
                const set_relative = try readU16BadGsub(table, class_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureContextRuleSetWithin(table, try checkedSubtableOffset(table, subtable_offset, set_relative));
            }
        },
        3 => {
            const glyph_count = try readU16BadGsub(table, subtable_offset + 2);
            if (glyph_count == 0) return error.BadGsub;
            const subst_count = try readU16BadGsub(table, subtable_offset + 4);
            const coverage_offsets_pos = subtable_offset + 6;
            try ensureCoverageOffsetArrayWithin(table, subtable_offset, coverage_offsets_pos, glyph_count);
            const records_offset = coverage_offsets_pos + @as(usize, glyph_count) * 2;
            try ensureSubstitutionRecordsWithin(table, records_offset, subst_count, glyph_count);
        },
        else => return error.UnsupportedGsub,
    }
}

fn ensureContextRuleSetWithin(table: Table, rule_set_offset: usize) GsubError!void {
    const rule_count = try readU16BadGsub(table, rule_set_offset);
    const rule_offsets_pos = rule_set_offset + 2;
    try ensureBytesWithin(table, rule_offsets_pos, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_i| {
        const rule_relative = try readU16BadGsub(table, rule_offsets_pos + rule_i * 2);
        // SubRule and SubClassRule offsets are mandatory once their parent
        // RuleSet is present. A zero offset aliases the RuleSet header as a
        // rule, deriving glyph/substitution counts from offset-array metadata
        // instead of from a declared contextual rule payload.
        if (rule_relative == 0) return error.BadGsub;
        const rule_offset = try checkedSubtableOffset(table, rule_set_offset, rule_relative);
        try ensureContextRuleWithin(table, rule_offset);
    }
}

fn ensureContextRuleWithin(table: Table, rule_offset: usize) GsubError!void {
    const glyph_count = try readU16BadGsub(table, rule_offset);
    if (glyph_count == 0) return error.BadGsub;
    const subst_count = try readU16BadGsub(table, rule_offset + 2);
    const input_pos = rule_offset + 4;
    try ensureBytesWithin(table, input_pos, (@as(usize, glyph_count) - 1) * 2);
    for (1..glyph_count) |input_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, input_pos + (input_i - 1) * 2));
    }
    const records_offset = input_pos + (@as(usize, glyph_count) - 1) * 2;
    try ensureSubstitutionRecordsWithin(table, records_offset, subst_count, glyph_count);
}

fn ensureChainingContextSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    // Chaining contextual subtables have three independent variable regions
    // (backtrack, input, lookahead) before their substitution records. Bounds
    // checking them up front preserves lookup-level atomicity for malformed
    // fonts and keeps the runtime matcher focused on glyph semantics.
    const subst_format = try readU16BadGsub(table, subtable_offset);
    switch (subst_format) {
        1 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
            try ensureCoverageTableWithin(table, coverage_offset);
            const chain_set_count = try readU16BadGsub(table, subtable_offset + 4);
            const chain_set_offsets_pos = subtable_offset + 6;
            try ensureBytesWithin(table, chain_set_offsets_pos, @as(usize, chain_set_count) * 2);
            for (0..chain_set_count) |set_i| {
                const set_relative = try readU16BadGsub(table, chain_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureChainingRuleSetWithin(table, try checkedSubtableOffset(table, subtable_offset, set_relative));
            }
        },
        2 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
            const backtrack_class_def = try checkedOptionalClassDefOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 4));
            const input_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 6));
            const lookahead_class_def = try checkedOptionalClassDefOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 8));
            try ensureCoverageTableWithin(table, coverage_offset);
            try ensureOptionalClassDefTableWithin(table, backtrack_class_def);
            try ensureClassDefTableWithin(table, input_class_def);
            try ensureOptionalClassDefTableWithin(table, lookahead_class_def);
            const set_count = try readU16BadGsub(table, subtable_offset + 10);
            const set_offsets_pos = subtable_offset + 12;
            try ensureBytesWithin(table, set_offsets_pos, @as(usize, set_count) * 2);
            for (0..set_count) |set_i| {
                const set_relative = try readU16BadGsub(table, set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureChainingRuleSetWithin(table, try checkedSubtableOffset(table, subtable_offset, set_relative));
            }
        },
        3 => try ensureChainingCoverageSubstitutionSubtableWithin(table, subtable_offset),
        else => return error.UnsupportedGsub,
    }
}

fn ensureChainingContextSubstitutionSubtableWithinForShaping(table: Table, subtable_offset: usize) GsubError!void {
    const subst_format = try readU16BadGsub(table, subtable_offset);
    if (subst_format != 3) {
        return ensureChainingContextSubstitutionSubtableWithin(table, subtable_offset);
    }

    var cursor = subtable_offset + 2;
    const backtrack_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithinForShaping(table, subtable_offset, cursor, backtrack_count);
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try readU16BadGsub(table, cursor);
    if (input_count == 0) return error.BadGsub;
    cursor += 2;
    try ensureCoverageOffsetArrayWithinForShaping(table, subtable_offset, cursor, input_count);
    cursor += @as(usize, input_count) * 2;

    const lookahead_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithinForShaping(table, subtable_offset, cursor, lookahead_count);
    cursor += @as(usize, lookahead_count) * 2;

    const subst_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureSubstitutionRecordsWithin(table, cursor, subst_count, input_count);
}

fn ensureChainingRuleSetWithin(table: Table, rule_set_offset: usize) GsubError!void {
    const rule_count = try readU16BadGsub(table, rule_set_offset);
    const rule_offsets_pos = rule_set_offset + 2;
    try ensureBytesWithin(table, rule_offsets_pos, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_i| {
        const rule_relative = try readU16BadGsub(table, rule_offsets_pos + rule_i * 2);
        // ChainSubRule and ChainSubClassRule offsets are required children.
        // Treating zero as a relative offset would reinterpret the RuleSet's
        // own count/offset array as backtrack/input/lookahead counts and make
        // malformed contextual substitution topology appear valid.
        if (rule_relative == 0) return error.BadGsub;
        const rule_offset = try checkedSubtableOffset(table, rule_set_offset, rule_relative);
        try ensureChainingRuleWithin(table, rule_offset);
    }
}

fn ensureChainingRuleWithin(table: Table, rule_offset: usize) GsubError!void {
    var cursor = rule_offset;
    const backtrack_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureBytesWithin(table, cursor, @as(usize, backtrack_count) * 2);
    for (0..backtrack_count) |backtrack_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, cursor + backtrack_i * 2));
    }
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try readU16BadGsub(table, cursor);
    if (input_count == 0) return error.BadGsub;
    cursor += 2;
    try ensureBytesWithin(table, cursor, (@as(usize, input_count) - 1) * 2);
    for (1..input_count) |input_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, cursor + (input_i - 1) * 2));
    }
    cursor += (@as(usize, input_count) - 1) * 2;

    const lookahead_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureBytesWithin(table, cursor, @as(usize, lookahead_count) * 2);
    for (0..lookahead_count) |lookahead_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, cursor + lookahead_i * 2));
    }
    cursor += @as(usize, lookahead_count) * 2;

    const subst_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureSubstitutionRecordsWithin(table, cursor, subst_count, input_count);
}

fn ensureChainingCoverageSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    var cursor = subtable_offset + 2;
    const backtrack_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, backtrack_count);
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try readU16BadGsub(table, cursor);
    if (input_count == 0) return error.BadGsub;
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, input_count);
    cursor += @as(usize, input_count) * 2;

    const lookahead_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, lookahead_count);
    cursor += @as(usize, lookahead_count) * 2;

    const subst_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureSubstitutionRecordsWithin(table, cursor, subst_count, input_count);
}

fn ensureReverseChainingSingleSubstitutionSubtableWithin(table: Table, subtable_offset: usize) GsubError!void {
    const subst_format = try readU16BadGsub(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGsub(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);

    var cursor = subtable_offset + 4;
    const backtrack_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, backtrack_count);
    cursor += @as(usize, backtrack_count) * 2;

    const lookahead_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, lookahead_count);
    cursor += @as(usize, lookahead_count) * 2;

    const glyph_count = try readU16BadGsub(table, cursor);
    cursor += 2;
    try ensureCoverageIndicesWithin(table, coverage_offset, glyph_count);
    try ensureBytesWithin(table, cursor, @as(usize, glyph_count) * 2);
    for (0..glyph_count) |glyph_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGsub(table, cursor + glyph_i * 2));
    }
}

fn ensureCoverageOffsetArrayWithin(table: Table, base_offset: usize, offsets_pos: usize, count: u16) GsubError!void {
    try ensureBytesWithin(table, offsets_pos, @as(usize, count) * 2);
    for (0..count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16BadGsub(table, offsets_pos + i * 2));
        try ensureCoverageTableWithin(table, coverage_offset);
    }
}

fn ensureCoverageOffsetArrayWithinForShaping(table: Table, base_offset: usize, offsets_pos: usize, count: u16) GsubError!void {
    try ensureBytesWithin(table, offsets_pos, @as(usize, count) * 2);
    for (0..count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16BadGsub(table, offsets_pos + i * 2));
        try ensureCoverageTableWithinForMembership(table, coverage_offset);
    }
}

fn ensureCoverageIndicesWithin(table: Table, coverage_offset: usize, target_count: usize) GsubError!void {
    return table_core.coverage.validateIndices(table, coverage_offset, target_count);
}

fn ensureClassDefTableWithin(table: Table, class_def_offset: usize) GsubError!void {
    return table_core.class_def.validate(table, class_def_offset);
}

fn ensureOptionalClassDefTableWithin(table: Table, class_def_offset: usize) GsubError!void {
    if (class_def_offset == empty_class_def_offset) return;
    return table_core.class_def.validate(table, class_def_offset);
}

fn ensureCoverageTableWithin(table: Table, coverage_offset: usize) GsubError!void {
    return table_core.coverage.validate(table, coverage_offset, .indexed);
}

fn ensureCoverageTableWithinForMembership(table: Table, coverage_offset: usize) GsubError!void {
    return table_core.coverage.validate(table, coverage_offset, .membership);
}

fn ensureSingleDeltaSubstitutionWithinMaxp(table: Table, coverage_offset: usize, delta: i16) GsubError!void {
    const format = try readU16BadGsub(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16BadGsub(table, coverage_offset + 2);
            for (0..glyph_count) |glyph_i| {
                const glyph = try readU16BadGsub(table, coverage_offset + 4 + glyph_i * 2);
                try ensureGlyphIdWithinMaxp(table, singleSubstDeltaResult(glyph, delta));
            }
        },
        2 => {
            const range_count = try readU16BadGsub(table, coverage_offset + 2);
            for (0..range_count) |range_i| {
                const range_offset = coverage_offset + 4 + range_i * 6;
                const start = try readU16BadGsub(table, range_offset);
                const end = try readU16BadGsub(table, range_offset + 2);
                for (@as(usize, start)..@as(usize, end) + 1) |glyph| {
                    try ensureGlyphIdWithinMaxp(table, singleSubstDeltaResult(@intCast(glyph), delta));
                }
            }
        },
        else => return error.UnsupportedGsub,
    }
}

fn singleSubstDeltaResult(glyph_id: GlyphId, delta: i16) GlyphId {
    return @bitCast(@as(i16, @bitCast(glyph_id)) +% delta);
}

fn ensureGlyphIdWithinMaxp(table: Table, glyph_id: usize) GsubError!void {
    if (table.glyph_count) |glyph_count| {
        if (glyph_id >= glyph_count) return error.BadGsub;
    }
}

fn ensureGlyphRangeWithinMaxp(table: Table, start_glyph: u16, end_glyph: u16) GsubError!void {
    try ensureGlyphIdWithinMaxp(table, start_glyph);
    try ensureGlyphIdWithinMaxp(table, end_glyph);
}

fn checkedSubtableOffset(table: Table, base_offset: usize, relative_offset: u32) GsubError!usize {
    return (try table_core.offset.optional32(table, base_offset, relative_offset)) orelse base_offset;
}

fn checkedRequiredSubtableOffset(table: Table, base_offset: usize, relative_offset: u16) GsubError!usize {
    return table_core.offset.required16(table, base_offset, relative_offset);
}

fn checkedExtensionSubtablePayloadOffset(table: Table, extension_offset: usize, relative_offset: u32) GsubError!usize {
    return table_core.offset.extensionPayload(table, extension_offset, relative_offset);
}

fn isEmptyGsubTopology(table: Table) GsubError!bool {
    const script_list = try readU16BadGsub(table, 4);
    const feature_list = try readU16BadGsub(table, 6);
    const lookup_list = try readU16BadGsub(table, 8);
    return script_list == 0 and feature_list == 0 and lookup_list == 0;
}

fn checkedRequiredScriptListOffset(table: Table) GsubError!usize {
    return checkedRequiredSubtableOffset(table, 0, try readU16BadGsub(table, 4));
}

fn checkedRequiredFeatureListOffset(table: Table) GsubError!usize {
    return checkedRequiredSubtableOffset(table, 0, try readU16BadGsub(table, 6));
}

fn checkedRequiredLookupListOffset(table: Table) GsubError!usize {
    return checkedRequiredSubtableOffset(table, 0, try readU16BadGsub(table, 8));
}

fn checkedRequiredLookupOffset(table: Table, lookup_list_offset: usize, relative_offset: u16) GsubError!usize {
    return checkedRequiredSubtableOffset(table, lookup_list_offset, relative_offset);
}

fn checkedRequiredCoverageOffset(table: Table, base_offset: usize, relative_offset: u16) GsubError!usize {
    return checkedRequiredSubtableOffset(table, base_offset, relative_offset);
}

fn checkedRequiredClassDefOffset(table: Table, base_offset: usize, relative_offset: u16) GsubError!usize {
    return checkedRequiredSubtableOffset(table, base_offset, relative_offset);
}

fn checkedOptionalClassDefOffset(table: Table, base_offset: usize, relative_offset: u16) GsubError!usize {
    return (try table_core.offset.optional16(table, base_offset, relative_offset)) orelse empty_class_def_offset;
}

fn ensureBytesWithin(table: Table, offset: usize, len: usize) GsubError!void {
    return table.ensure(offset, len);
}

fn readU16BadGsub(table: Table, relative: usize) GsubError!u16 {
    return readU16(table, relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}

fn readI16BadGsub(table: Table, relative: usize) GsubError!i16 {
    return readI16(table, relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}

fn readU32BadGsub(table: Table, relative: usize) GsubError!u32 {
    return readU32(table, relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}

fn applyNestedGlyphLookup(table: Table, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, lookup_index: u16, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!NestedGlyphChange {
    try consumeNestedGsubOperation(options);
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    if (lookup_index >= lookup_count) return error.BadGsub;
    const nested_lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
    const lookup_type = try readU16(table, nested_lookup_offset);
    const lookup_flag = try readU16(table, nested_lookup_offset + 2);
    const subtable_count = try readU16(table, nested_lookup_offset + 4);
    var lookup_options = options;
    if ((lookup_flag & 0x0010) != 0) {
        lookup_options.active_mark_filtering_set = try readU16(table, nested_lookup_offset + 6 + @as(usize, subtable_count) * 2);
        try validateMarkFilteringSetIndex(lookup_options);
    }
    if (lookup_type == 1) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = nested_lookup_offset + try readU16(table, nested_lookup_offset + 6 + subtable_i * 2);
            if (try applySingleSubstitutionAt(table, subtable_offset, glyphs, glyph_index, lookup_flag, lookup_options)) return .{};
        }
        return .{};
    }
    if (lookup_type == 4) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = nested_lookup_offset + try readU16(table, nested_lookup_offset + 6 + subtable_i * 2);
            if (try applyLigatureSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, lookup_options)) |change| {
                return change;
            }
        }
        return .{};
    }
    if (lookup_type == 2) {
        // MultipleSubst is cardinality-changing, so contextual records must
        // observe only the first matching subtable for the target glyph. Running
        // the whole lookup on a scratch glyph can feed the replacement into
        // later subtables and report the wrong insert count to the record map.
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = nested_lookup_offset + try readU16(table, nested_lookup_offset + 6 + subtable_i * 2);
            if (try applyMultipleSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, lookup_options)) |change| {
                return change;
            }
        }
        return .{};
    }
    if (lookup_type == 7) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = nested_lookup_offset + try readU16(table, nested_lookup_offset + 6 + subtable_i * 2);
            if (try applyNestedExtensionSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, lookup_options)) |change| {
                return change;
            }
        }
    }
    if (lookup_type == 5) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = nested_lookup_offset + try readU16(table, nested_lookup_offset + 6 + subtable_i * 2);
            if ((try applyContextSubstitutionAt(table, subtable_offset, glyphs, glyph_index, allocator, lookup_flag, lookup_options)).matched) return .{};
        }
        return .{};
    }
    if (lookup_type == 6) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = nested_lookup_offset + try readU16(table, nested_lookup_offset + 6 + subtable_i * 2);
            if ((try applyChainingContextSubstitutionAt(table, subtable_offset, null, glyphs, glyph_index, allocator, lookup_flag, lookup_options)).matched) return .{};
        }
        return .{};
    }

    // Contextual records target one glyph in the matched input sequence. Run
    // the nested lookup on a one-glyph scratch buffer so it cannot accidentally
    // scan and modify later glyphs for single-glyph lookup types, then splice
    // the result back even when the lookup changes cardinality (for example
    // MultipleSubst). LigatureSubst is handled above because it intentionally
    // consumes following glyphs from the real run.
    var slice = std.ArrayList(GlyphId).empty;
    defer slice.deinit(allocator);
    try slice.append(allocator, glyphs.items[glyph_index]);
    var scratch_options = options;
    scratch_options.glyph_source_indices = null;
    scratch_options.glyph_substituted = null;
    scratch_options.glyph_stage_substituted = null;
    scratch_options.ligature_components = null;
    scratch_options.source_features = null;
    scratch_options.active_source_feature = null;
    scratch_options.active_source_feature_mask = 0;
    try applyLookup(table, nested_lookup_offset, &slice, allocator, scratch_options);
    try glyphs.replaceRange(allocator, glyph_index, 1, slice.items);
    noteGlyphMutation(options);
    if (slice.items.len == 1) {
        markGlyphSubstituted(options, glyph_index);
    } else {
        try replaceSourceMetadata(allocator, options, glyph_index, 1, slice.items.len, sourceForGlyph(options, glyph_index));
    }
    return .{ .removed_len = 1, .inserted_len = slice.items.len };
}

fn applyNestedExtensionSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!?NestedGlyphChange {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 7) return error.UnsupportedGsub;
    const extension_subtable = try checkedExtensionSubtablePayloadOffset(table, subtable_offset, try readU32(table, subtable_offset + 4));

    // ExtensionSubst is only an offset-widening wrapper. Contextual records,
    // however, name one target glyph inside the pre-match input sequence. Apply
    // wrapped cardinality-changing subtables at that real target so the caller
    // can remap later records from the actual removal/insertion shape.
    switch (extension_lookup_type) {
        1 => {
            if (try applySingleSubstitutionAt(table, extension_subtable, glyphs, glyph_index, lookup_flag, options)) return .{};
            return null;
        },
        2 => return try applyMultipleSubstitutionAt(table, extension_subtable, glyphs, glyph_index, allocator, lookup_flag, options),
        4 => return try applyLigatureSubstitutionAt(table, extension_subtable, glyphs, glyph_index, allocator, lookup_flag, options),
        5 => return if ((try applyContextSubstitutionAt(table, extension_subtable, glyphs, glyph_index, allocator, lookup_flag, options)).matched) .{} else null,
        6 => return if ((try applyChainingContextSubstitutionAt(table, extension_subtable, null, glyphs, glyph_index, allocator, lookup_flag, options)).matched) .{} else null,
        else => return null,
    }
}

fn applyReverseChainingSingleSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions, matched: ?[]bool) GsubError!void {
    const parsed =
        try accelerator_root.build.reverse.parse(table, subtable_offset);

    if (glyphs.items.len == 0) return;
    // Reverse chaining scans backward so earlier replacements cannot influence
    // the lookahead context of glyphs that have not been visited yet.
    var pos = glyphs.items.len;
    while (pos > 0) {
        pos -= 1;
        if (matched) |items| {
            if (items[pos]) continue;
        }
        if (try applyParsedReverseChainingSingleSubstitutionAt(table, parsed, glyphs, pos, lookup_flag, options)) {
            if (matched) |items| items[pos] = true;
        }
    }
}

fn applyAcceleratedChainingClassSubstitutionAt(table: Table, subtable: ChainingClassSubtableAccelerator, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    const group = chainingClassGroupForGlyph(subtable, glyphs.items[pos]) orelse return .{};
    if (group.max_input_count == 0 or group.max_input_count > max_chaining_class_region_glyphs or group.max_lookahead_count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;

    var window = ChainingClassRuleMatchWindow.init(table, glyphs.items, pos, empty_class_def_offset, subtable.input_class_def, subtable.lookahead_class_def, lookup_flag, options);
    var input_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    var lookahead_classes: [max_chaining_class_region_glyphs]u16 = undefined;

    const rules = subtable.rules[group.start .. group.start + group.len];
    for (rules) |rule| {
        if (rule.input_count == 0 or rule.input_count > group.max_input_count) continue;
        if (rule.lookahead_count > group.max_lookahead_count) continue;
        // Rules in one class set are tried in font order and may have different
        // input lengths. Do not prefetch the group's longest window: a short
        // early rule can match at the end of a syllable even when a later long
        // rule has more inputs than remain in the run.
        const input_indices = (try window.inputSlice(rule.input_count)) orelse continue;
        var input_available = true;
        for (1..rule.input_count) |input_i| {
            input_classes[input_i - 1] = (try window.inputClassAt(input_i)) orelse {
                input_available = false;
                break;
            };
        }
        if (!input_available) continue;
        if (!try window.ensureLookaheadCount(rule.input_count, rule.lookahead_count)) continue;
        const extra_input_count = @as(usize, rule.input_count) - 1;
        var hash = class_context.sequenceHash(input_classes[0..extra_input_count]);
        for (0..rule.lookahead_count) |lookahead_i| {
            const class = (try window.lookaheadClassAt(rule.input_count, lookahead_i)) orelse {
                hash = 0;
                break;
            };
            lookahead_classes[lookahead_i] = class;
            hash = class_context.sequenceHashAppend(hash, class);
        }
        if (rule.hash != hash) continue;
        const expected_input = subtable.classes[rule.classes_start .. rule.classes_start + extra_input_count];
        if (!std.mem.eql(u16, expected_input, input_classes[0..extra_input_count])) continue;
        const expected_lookahead = subtable.classes[rule.classes_start + extra_input_count .. rule.classes_start + extra_input_count + rule.lookahead_count];
        if (!std.mem.eql(u16, expected_lookahead, lookahead_classes[0..rule.lookahead_count])) continue;

        try markUnsafeChainingMatch(
            allocator,
            options,
            window.backtrack_indices[0..0],
            input_indices,
            window.lookahead_indices[0..rule.lookahead_count],
        );
        const glyph_count_before = glyphs.items.len;
        _ = try applyNestedGlyphLookup(table, glyphs, input_indices[0], rule.lookup_index, allocator, options);
        const original_next = input_indices[rule.input_count - 1] + 1;
        return .{
            .matched = true,
            .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
        };
    }
    return .{};
}

noinline fn applyAcceleratedChainingClassSubstitutionWithBacktrackAt(table: Table, subtable: ChainingClassSubtableAccelerator, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!ContextApplyResult {
    const group = chainingClassGroupForGlyph(subtable, glyphs.items[pos]) orelse return .{};
    if (group.max_input_count == 0 or group.max_input_count > max_chaining_class_region_glyphs or group.max_lookahead_count > max_chaining_class_region_glyphs) return error.UnsupportedGsub;

    var window = ChainingClassRuleMatchWindow.init(table, glyphs.items, pos, subtable.backtrack_class_def, subtable.input_class_def, subtable.lookahead_class_def, lookup_flag, options);
    var backtrack_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    var input_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    var lookahead_classes: [max_chaining_class_region_glyphs]u16 = undefined;

    const rules = subtable.rules[group.start .. group.start + group.len];
    for (rules) |rule| {
        const backtrack_count = chainingClassRuleBacktrackCount(rule);
        if (backtrack_count > max_chaining_class_region_glyphs) continue;
        if (rule.input_count == 0 or rule.input_count > group.max_input_count) continue;
        if (rule.lookahead_count > group.max_lookahead_count) continue;
        // Rules in one class set are tried in font order and may have different
        // input lengths. Do not prefetch the group's longest window: a short
        // early rule can match at the end of a syllable even when a later long
        // rule has more inputs than remain in the run.
        const input_indices = (try window.inputSlice(rule.input_count)) orelse continue;
        var backtrack_available = true;
        for (0..backtrack_count) |backtrack_i| {
            backtrack_classes[backtrack_i] = (try window.backtrackClassAt(backtrack_i)) orelse {
                backtrack_available = false;
                break;
            };
        }
        if (!backtrack_available) continue;
        var input_available = true;
        for (1..rule.input_count) |input_i| {
            input_classes[input_i - 1] = (try window.inputClassAt(input_i)) orelse {
                input_available = false;
                break;
            };
        }
        if (!input_available) continue;
        if (!try window.ensureLookaheadCount(rule.input_count, rule.lookahead_count)) continue;
        var hash = class_context.sequenceHash(backtrack_classes[0..backtrack_count]);
        const extra_input_count = @as(usize, rule.input_count) - 1;
        for (input_classes[0..extra_input_count]) |class| {
            hash = class_context.sequenceHashAppend(hash, class);
        }
        for (0..rule.lookahead_count) |lookahead_i| {
            const class = (try window.lookaheadClassAt(rule.input_count, lookahead_i)) orelse {
                hash = 0;
                break;
            };
            lookahead_classes[lookahead_i] = class;
            hash = class_context.sequenceHashAppend(hash, class);
        }
        if (rule.hash != hash) continue;
        const expected_backtrack = subtable.classes[rule.classes_start .. rule.classes_start + backtrack_count];
        if (!std.mem.eql(u16, expected_backtrack, backtrack_classes[0..backtrack_count])) continue;
        const input_start = rule.classes_start + backtrack_count;
        const expected_input = subtable.classes[input_start .. input_start + extra_input_count];
        if (!std.mem.eql(u16, expected_input, input_classes[0..extra_input_count])) continue;
        const lookahead_start = input_start + extra_input_count;
        const expected_lookahead = subtable.classes[lookahead_start .. lookahead_start + rule.lookahead_count];
        if (!std.mem.eql(u16, expected_lookahead, lookahead_classes[0..rule.lookahead_count])) continue;

        try markUnsafeChainingMatch(
            allocator,
            options,
            window.backtrack_indices[0..backtrack_count],
            input_indices,
            window.lookahead_indices[0..rule.lookahead_count],
        );
        const glyph_count_before = glyphs.items.len;
        _ = try applyNestedGlyphLookup(table, glyphs, input_indices[0], rule.lookup_index, allocator, options);
        const original_next = input_indices[rule.input_count - 1] + 1;
        return .{
            .matched = true,
            .next_pos = contextNextPosAfterMutation(original_next, pos, glyph_count_before, glyphs.items.len),
        };
    }
    return .{};
}

fn applyReverseChainingSingleSubstitutionAt(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, lookup_flag: u16, options: LookupOptions) GsubError!bool {
    const parsed =
        try accelerator_root.build.reverse.parse(table, subtable_offset);
    return try applyParsedReverseChainingSingleSubstitutionAt(table, parsed, glyphs, pos, lookup_flag, options);
}

fn reverseChainingContextKeyForPosition(glyphs: []const GlyphId, pos: usize, target: GlyphId, lookup_flag: u16, options: LookupOptions) ?ReverseChainingContextKey {
    const backtrack = previousUnignoredGlyph(glyphs, pos, lookup_flag, options, true, pos) orelse return null;
    var lookahead: [2]GlyphId = undefined;
    var lookahead_i: usize = 0;
    var glyph_i = pos + 1;
    const anchor_syllable = sourceSyllableForGlyph(options, pos);
    while (glyph_i < glyphs.len and lookahead_i < lookahead.len) : (glyph_i += 1) {
        if (contextualMaySkipGlyph(lookup_flag, options, glyphs, glyph_i, true)) continue;
        if (!sourceSyllableAllowsGlyph(options, anchor_syllable, glyph_i)) return null;
        lookahead[lookahead_i] = glyphs[glyph_i];
        lookahead_i += 1;
    }
    if (lookahead_i != lookahead.len) return null;
    return .{
        .target = target,
        .backtrack = backtrack,
        .lookahead_0 = lookahead[0],
        .lookahead_1 = lookahead[1],
    };
}

fn previousUnignoredGlyph(glyphs: []const GlyphId, pos: usize, lookup_flag: u16, options: LookupOptions, context_match: bool, anchor_index: usize) ?GlyphId {
    var glyph_i = pos;
    const anchor_syllable = sourceSyllableForGlyph(options, anchor_index);
    while (glyph_i > 0) {
        glyph_i -= 1;
        if (contextualMaySkipGlyph(lookup_flag, options, glyphs, glyph_i, context_match)) continue;
        if (!sourceSyllableAllowsGlyph(options, anchor_syllable, glyph_i)) return null;
        return glyphs[glyph_i];
    }
    return null;
}

fn applyParsedReverseChainingSingleSubstitutionAt(table: Table, subtable: ReverseChainingSingleSubtable, glyphs: *std.ArrayList(GlyphId), pos: usize, lookup_flag: u16, options: LookupOptions) GsubError!bool {
    if (pos >= glyphs.items.len) return false;
    if (!sourceFeatureAllowsGlyph(options, pos)) return false;
    const glyph = glyphs.items[pos];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const coverage = try table_core.coverage.index(table, subtable.coverage_offset, glyph) orelse return false;
    if (coverage >= subtable.glyph_count) return false;
    if (!try reverseCoverageMatches(table, subtable.subtable_offset, glyphs.items, pos, subtable.backtrack_offsets_pos, subtable.backtrack_count, true, lookup_flag, options)) return false;
    if (!try reverseCoverageMatches(table, subtable.subtable_offset, glyphs.items, pos, subtable.lookahead_offsets_pos, subtable.lookahead_count, false, lookup_flag, options)) return false;

    glyphs.items[pos] = try readU16(table, subtable.substitutes_pos + coverage * 2);
    markGlyphSubstituted(options, pos);
    return true;
}
fn reverseCoverageMatches(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, offsets_pos: usize, count: usize, backtrack: bool, lookup_flag: u16, options: LookupOptions) GsubError!bool {
    var indices_buf: [64]usize = undefined;
    if (count > indices_buf.len) return error.UnsupportedGsub;
    const indices = indices_buf[0..count];
    const has_context = if (backtrack)
        collectBacktrackUnignoredGlyphs(glyphs, pos, lookup_flag, options, indices, true, pos)
    else
        collectForwardUnignoredGlyphs(glyphs, pos + 1, lookup_flag, options, indices, true, pos);
    if (!has_context) return false;
    return try coverageIndicesMatch(table, subtable_offset, glyphs, indices, offsets_pos);
}

const LigatureMatch = struct {
    ligature: GlyphId,
    component_count: usize,
    component_offsets: *const [max_ligature_components]usize,
    match_end: usize = 1,
};

const max_ligature_components = accelerator_model.max_ligature_components;

fn ligatureAt(table: Table, set_offset: usize, glyphs: []const GlyphId, glyph_base: usize, lookup_flag: u16, options: LookupOptions, component_offsets: *[max_ligature_components]usize) GsubError!?LigatureMatch {
    const ligature_count = try readU16(table, set_offset);
    const anchor_syllable = ligatureAnchorSyllable(options, glyph_base);
    for (0..ligature_count) |i| {
        const lig_offset = checkedRequiredSubtableOffset(table, set_offset, try readU16(table, set_offset + 2 + i * 2)) catch continue;
        const ligature = try readU16(table, lig_offset);
        const component_count = try readU16(table, lig_offset + 2);
        if (component_count == 0 or component_count > max_ligature_components) continue;
        component_offsets[0] = 0;
        var ok = true;
        var cursor: usize = 1;
        for (1..component_count) |component_index| {
            const expected = try readU16(table, lig_offset + 4 + (component_index - 1) * 2);
            while (cursor < glyphs.len and ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor) and ligatureMaySkipGlyph(lookup_flag, options, glyphs, glyph_base, cursor)) : (cursor += 1) {}
            if (cursor < glyphs.len and !ligatureAllowsRelativeGlyph(options, anchor_syllable, glyph_base, cursor)) {
                ok = false;
                break;
            }
            if (cursor >= glyphs.len or glyphs[cursor] != expected) {
                ok = false;
                break;
            }
            component_offsets[component_index] = cursor;
            cursor += 1;
        }
        if (ok) {
            // LigatureSet records are ordered by font-authored preference. Do
            // not choose the longest matching sequence: a font may deliberately
            // place a shorter ligature before a longer one to control shaping.
            return .{ .ligature = ligature, .component_count = component_count, .component_offsets = component_offsets, .match_end = cursor };
        }
    }
    return null;
}

fn readU16(table: Table, relative: usize) GsubError!u16 {
    return table.readU16(relative);
}

fn readI16(table: Table, relative: usize) GsubError!i16 {
    return table.readI16(relative);
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
    try std.testing.expectError(error.BadGsub, applyNestedExtensionSubstitutionAt(table, 0, &glyphs, 0, std.testing.allocator, 0, .{}));
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
    try std.testing.expectError(error.BadGsub, ensureExtensionSubstitutionPayloadWithin(table, 0));
    try std.testing.expectError(error.BadGsub, applyExtensionSubstitution(table, 0, &glyphs, std.testing.allocator, 0, .{}));
    try std.testing.expectError(error.BadGsub, applyNestedExtensionSubstitutionAt(table, 0, &glyphs, 0, std.testing.allocator, 0, .{}));
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

test "GSUB coverage format 2 handles full glyph-space index boundary" {
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 1);
    writeU16Test(&bytes, 4, 0);
    writeU16Test(&bytes, 6, 0xffff);
    writeU16Test(&bytes, 8, 0);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(@as(?usize, 0xfffe), try table_core.coverage.index(table, 0, 0xfffe));
    try std.testing.expectEqual(@as(?usize, 0xffff), try table_core.coverage.index(table, 0, 0xffff));
}

test "GSUB coverage format 2 rejects inconsistent start coverage indexes" {
    var bytes = [_]u8{0} ** 16;
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 2);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 1);
    writeU16Test(&bytes, 8, 0);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 3);
    writeU16Test(&bytes, 14, 2); // Must be 1: indexes are dense over preceding ranges.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, ensureCoverageTableWithin(table, 0));
    try std.testing.expectError(error.BadGsub, table_core.coverage.index(table, 0, 3));
}

test "GSUB coverage format 2 tolerates overlapping real-font ranges" {
    var bytes = [_]u8{0} ** 22;
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 3);
    writeU16Test(&bytes, 4, 10);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 0);
    writeU16Test(&bytes, 10, 12);
    writeU16Test(&bytes, 12, 14);
    writeU16Test(&bytes, 14, 3);
    writeU16Test(&bytes, 16, 20);
    writeU16Test(&bytes, 18, 20);
    writeU16Test(&bytes, 20, 6);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try ensureCoverageTableWithin(table, 0);
    try std.testing.expectEqual(@as(?usize, 2), try table_core.coverage.index(table, 0, 12));
    try std.testing.expectEqual(@as(?usize, 4), try table_core.coverage.index(table, 0, 13));
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

    try std.testing.expectError(error.BadGsub, applySingleSubstitution(table, 0, &glyphs, 0, .{}));
    try std.testing.expectEqual(@as(GlyphId, 10), glyphs.items[0]);
}

test "GSUB shaping accepts duplicate chaining membership glyphs" {
    var bytes = [_]u8{0} ** 36;
    const chain = 0;
    writeU16Test(&bytes, chain + 0, 3);
    writeU16Test(&bytes, chain + 2, 1);
    writeU16Test(&bytes, chain + 4, 18);
    writeU16Test(&bytes, chain + 6, 1);
    writeU16Test(&bytes, chain + 8, 26);
    writeU16Test(&bytes, chain + 10, 0);
    writeU16Test(&bytes, chain + 12, 0);
    writeU16Test(&bytes, chain + 14, 0);
    writeU16Test(&bytes, chain + 16, 0);

    // Duplicate glyph 7 is harmless in a backtrack membership set.
    writeU16Test(&bytes, chain + 18, 1);
    writeU16Test(&bytes, chain + 20, 2);
    writeU16Test(&bytes, chain + 22, 7);
    writeU16Test(&bytes, chain + 24, 7);
    writeCoverage1(&bytes, chain + 26, 8);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 16,
    };
    try std.testing.expectError(
        error.BadGsub,
        ensureChainingContextSubstitutionSubtableWithin(table, chain),
    );
    try ensureChainingContextSubstitutionSubtableWithinForShaping(table, chain);
}

test "GSUB class format 1 handles upper glyph boundary" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0xfffe);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 7);
    writeU16Test(&bytes, 8, 9);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(@as(u16, 7), try table_core.class_def.value(table, 0, 0xfffe));
    try std.testing.expectEqual(@as(u16, 9), try table_core.class_def.value(table, 0, 0xffff));
    try std.testing.expectEqual(@as(u16, 0), try table_core.class_def.value(table, 0, 0xfffd));
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
    try ensureSubstitutionRecordsWithin(table, rule + 4, 1, 1);
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
    try std.testing.expectError(error.BadGsub, ensureLookupHeaderWithin(table, 18));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 20, 0xff10); // MarkAttachmentType plus UseMarkFilteringSet are valid.
    writeU16Test(&bytes, 26, 0); // MarkFilteringSet index follows the subtable-offset array.
    try ensureLookupHeaderWithin(table, 18);
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
    try std.testing.expectError(error.BadGsub, ensureSubstitutionLookupSubtablesWithin(table, 18, 1, 1));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, applyLookup(table, 18, &glyphs, std.testing.allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // Repairing only the child pointer should make the otherwise valid lookup
    // pass; the test guards against rejecting empty/no-op substitution data.
    writeU16Test(&bytes, 24, 8);
    try ensureSubstitutionLookupSubtablesWithin(table, 18, 1, 1);
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
    try std.testing.expectError(error.BadGsub, ensureSingleSubstitutionSubtableWithin(table, subtable));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, applySingleSubstitution(table, subtable, &glyphs, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
    try std.testing.expectError(error.BadGsub, applyLookup(table, 18, &glyphs, std.testing.allocator, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // With the Coverage pointer repaired, the same subtable is a normal
    // SingleSubst; only the aliasing null child pointer is invalid.
    writeU16Test(&bytes, subtable + 2, 6);
    try ensureSingleSubstitutionSubtableWithin(table, subtable);
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

test "GSUB rejects malformed ClassDef format 2 ranges" {
    var bytes = [_]u8{0} ** 22;
    writeU16Test(&bytes, 0, 2); // ClassDef format 2.
    writeU16Test(&bytes, 2, 3); // Three ClassRangeRecords.
    writeU16Test(&bytes, 4, 10);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 12); // Overlaps the previous inclusive range.
    writeU16Test(&bytes, 12, 14);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 20);
    writeU16Test(&bytes, 18, 18); // Reversed range must also be rejected.
    writeU16Test(&bytes, 20, 3);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, table_core.class_def.value(table, 0, 12));

    writeU16Test(&bytes, 10, 13); // Repair overlap so the reversed range is checked.
    try std.testing.expectError(error.BadGsub, table_core.class_def.value(table, 0, 18));
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
    try ensureContextSubstitutionSubtableWithin(table, 0);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    try applyContextClassSubstitution(table, 0, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);

    writeClassDef1(&context_bytes, 18, 5, 0);
    try ensureContextSubstitutionSubtableWithin(table, 0);

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
    try ensureChainingContextSubstitutionSubtableWithin(table, 0);
    try applyChainingClassSubstitution(table, 0, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);

    writeClassDef1(&chaining_bytes, 30, 5, 0);
    try ensureChainingContextSubstitutionSubtableWithin(table, 0);
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
    try std.testing.expectError(error.BadGsub, ensureContextSubstitutionSubtableWithin(table, 0));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    try std.testing.expectError(error.BadGsub, applyContextClassSubstitution(table, 0, &glyphs, allocator, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);

    writeU16Test(&context_bytes, 4, 18);
    try ensureContextSubstitutionSubtableWithin(table, 0);
    try applyContextClassSubstitution(table, 0, &glyphs, allocator, 0, .{});
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
    try ensureChainingContextSubstitutionSubtableWithin(table, 0);

    writeU16Test(&chaining_bytes, 4, 0);
    try ensureChainingContextSubstitutionSubtableWithin(table, 0);
    try applyChainingClassSubstitution(table, 0, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
    writeU16Test(&chaining_bytes, 4, 22);

    writeU16Test(&chaining_bytes, 6, 0);
    try std.testing.expectError(error.BadGsub, ensureChainingContextSubstitutionSubtableWithin(table, 0));
    try std.testing.expectError(error.BadGsub, applyChainingClassSubstitution(table, 0, &glyphs, allocator, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
    writeU16Test(&chaining_bytes, 6, 30);

    writeU16Test(&chaining_bytes, 8, 0);
    try ensureChainingContextSubstitutionSubtableWithin(table, 0);
    try applyChainingClassSubstitution(table, 0, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
    writeU16Test(&chaining_bytes, 8, 38);

    try ensureChainingContextSubstitutionSubtableWithin(table, 0);
    try applyChainingClassSubstitution(table, 0, &glyphs, allocator, 0, .{});
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

    const result = try applyAcceleratedContextClassSubstitutionAt(
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

test "GSUB accelerated chaining class matching keeps shorter rules at run end" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    // The first two glyphs form the short rule's input and the third is its
    // lookahead. A later rule in the same class set declares four inputs, so
    // eager collection of the group-wide maximum would incorrectly reject the
    // whole subtable before trying the short rule.
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeSingleDeltaLookup(&bytes, 14, 1, 10);

    const coverage = 40;
    writeCoverage1(&bytes, coverage, 1);
    const input_class_def = 46;
    writeU16Test(&bytes, input_class_def + 0, 1);
    writeU16Test(&bytes, input_class_def + 2, 1);
    writeU16Test(&bytes, input_class_def + 4, 3);
    writeU16Test(&bytes, input_class_def + 6, 3);
    writeU16Test(&bytes, input_class_def + 8, 5);
    writeU16Test(&bytes, input_class_def + 10, 5);
    const lookahead_class_def = 60;
    writeU16Test(&bytes, lookahead_class_def + 0, 1);
    writeU16Test(&bytes, lookahead_class_def + 2, 1);
    writeU16Test(&bytes, lookahead_class_def + 4, 3);
    writeU16Test(&bytes, lookahead_class_def + 6, 9);
    writeU16Test(&bytes, lookahead_class_def + 8, 1);
    writeU16Test(&bytes, lookahead_class_def + 10, 7);

    const classes = [_]u16{
        5, 7, // Short rule: one extra input and one lookahead.
        5,                                                  5, 5, // Long rule: three extra inputs.
        accelerator_root.index.class_first.sorted_encoding, 1, 0,
    };
    const rules = [_]class_context.Rule{
        .{
            .class_set = 3,
            .input_count = 2,
            .lookahead_count = 1,
            .hash = class_context.sequenceHash(classes[0..2]),
            .order = 0,
            .lookup_index = 0,
            .classes_start = 0,
        },
        .{
            .class_set = 3,
            .input_count = 4,
            .lookahead_count = 0,
            .hash = class_context.sequenceHash(classes[2..5]),
            .order = 1,
            .lookup_index = 0,
            .classes_start = 2,
        },
    };
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = rules.len,
        .max_input_count = 4,
        .max_lookahead_count = 1,
    }};
    const subtable = ChainingClassSubtableAccelerator{
        .first_index_start = 5,
        .input_class_def = input_class_def,
        .lookahead_class_def = lookahead_class_def,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });
    const source_byte_starts = [_]usize{ 0, 1, 2 };
    var source_boundaries = cluster_safety.SourceBoundaries{};
    defer source_boundaries.deinit(allocator);
    source_boundaries.reset(0, 3, &source_byte_starts);

    const result = try applyAcceleratedChainingClassSubstitutionAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_boundaries = &source_boundaries,
        },
    );

    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 2), result.next_pos);
    try std.testing.expectEqualSlices(GlyphId, &.{ 11, 2, 3 }, glyphs.items);
    try std.testing.expect(!source_boundaries.isUnsafeBeforeByte(0));
    try std.testing.expect(source_boundaries.isUnsafeBeforeByte(1));
    try std.testing.expect(source_boundaries.isUnsafeBeforeByte(2));
}

test "GSUB accelerated chaining class matching preserves backtrack order and boundaries" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    // Nested lookup 0 replaces the current input glyph. The contextual table
    // itself is represented by the accelerator fixture below.
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeSingleDeltaLookup(&bytes, 14, 1, 10);

    const coverage = 40;
    writeCoverage1(&bytes, coverage, 1);
    const backtrack_class_def = 46;
    writeU16Test(&bytes, backtrack_class_def + 0, 1);
    writeU16Test(&bytes, backtrack_class_def + 2, 4);
    writeU16Test(&bytes, backtrack_class_def + 4, 2);
    writeU16Test(&bytes, backtrack_class_def + 6, 6); // Far glyph 4.
    writeU16Test(&bytes, backtrack_class_def + 8, 2); // Near glyph 5.
    const input_class_def = 58;
    writeClassDef1(&bytes, input_class_def, 1, 3);
    const lookahead_class_def = 66;
    writeClassDef1(&bytes, lookahead_class_def, 3, 7);

    // OpenType stores backtrack classes nearest to the input first. Keeping
    // that order in the sidecar avoids reversing either the font data or the
    // lazily collected backtrack window.
    const classes = [_]u16{
        2,                                                  6, 7,
        accelerator_root.index.class_first.sorted_encoding, 1, 0,
    };
    const rules = [_]class_context.Rule{.{
        .class_set = 3,
        .input_count = 1,
        .lookahead_count = 1,
        .hash = class_context.sequenceHash(classes[0..3]),
        .order = 0,
        .lookup_index = 0,
        .classes_start = 0,
        .records_offset = 2,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 3,
        .start = 0,
        .len = rules.len,
        .max_input_count = 1,
        .max_lookahead_count = 1,
    }};
    const subtable = ChainingClassSubtableAccelerator{
        .first_index_start = 3,
        .backtrack_class_def = backtrack_class_def,
        .input_class_def = input_class_def,
        .lookahead_class_def = lookahead_class_def,
        .rules = &rules,
        .classes = &classes,
        .groups = &groups,
    };

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    // Marks 9 and 8 are transparent in the backtrack and lookahead regions.
    try glyphs.appendSlice(allocator, &.{ 4, 9, 5, 1, 8, 3 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2, 3, 4, 5 });
    const source_byte_starts = [_]usize{ 0, 1, 2, 3, 4, 5 };
    var source_boundaries = cluster_safety.SourceBoundaries{};
    defer source_boundaries.deinit(allocator);
    source_boundaries.reset(0, 6, &source_byte_starts);
    var glyph_classes = [_]u16{0} ** 10;
    glyph_classes[8] = 3;
    glyph_classes[9] = 3;

    // The farther backtrack glyph belongs to another source syllable. Matching
    // must stop there rather than leaking context across the shaping boundary.
    const split_syllables = [_]u8{ 1, 1, 2, 2, 2, 2 };
    var result = try applyAcceleratedChainingClassSubstitutionWithBacktrackAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        subtable,
        &glyphs,
        3,
        allocator,
        0x0008,
        .{
            .glyph_classes = &glyph_classes,
            .glyph_source_indices = &sources,
            .source_boundaries = &source_boundaries,
            .source_syllables = &split_syllables,
            .match_source_syllable = true,
        },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expectEqualSlices(GlyphId, &.{ 4, 9, 5, 1, 8, 3 }, glyphs.items);
    try std.testing.expect(!source_boundaries.isUnsafeBeforeByte(3));

    const one_syllable = [_]u8{2} ** 6;
    result = try applyAcceleratedChainingClassSubstitutionWithBacktrackAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        subtable,
        &glyphs,
        3,
        allocator,
        0x0008,
        .{
            .glyph_classes = &glyph_classes,
            .glyph_source_indices = &sources,
            .source_boundaries = &source_boundaries,
            .source_syllables = &one_syllable,
            .match_source_syllable = true,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 4), result.next_pos);
    try std.testing.expectEqualSlices(GlyphId, &.{ 4, 9, 5, 11, 8, 3 }, glyphs.items);
    for (1..6) |boundary| {
        try std.testing.expect(source_boundaries.isUnsafeBeforeByte(boundary));
    }
}

test "GSUB ContextSubst rejects null required rule offsets" {
    var bytes = [_]u8{0} ** 24;
    writeU16Test(&bytes, 8, 12); // LookupList offset for nested-record preflight.
    writeU16Test(&bytes, 12, 0); // Empty LookupList; repaired rule has no records.

    const rule_set = 16;
    writeU16Test(&bytes, rule_set + 0, 1); // One SubRule offset follows.
    writeU16Test(&bytes, rule_set + 2, 0); // Invalid: SubRule offsets are not nullable.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, ensureContextRuleSetWithin(table, rule_set));

    // A real rule can still match one input glyph and contain no substitution
    // records; only the child pointer itself must name an actual SubRule.
    const rule = rule_set + 4;
    writeU16Test(&bytes, rule_set + 2, 4);
    writeU16Test(&bytes, rule + 0, 1); // GlyphCount includes the first covered glyph.
    writeU16Test(&bytes, rule + 2, 0); // SubstCount.
    try ensureContextRuleSetWithin(table, rule_set);
}

test "GSUB ChainingContextSubst rejects null required rule offsets" {
    var bytes = [_]u8{0} ** 28;
    writeU16Test(&bytes, 8, 12); // LookupList offset for nested-record preflight.
    writeU16Test(&bytes, 12, 0); // Empty LookupList; repaired rule has no records.

    const rule_set = 16;
    writeU16Test(&bytes, rule_set + 0, 1); // One ChainSubRule offset follows.
    writeU16Test(&bytes, rule_set + 2, 0); // Invalid: ChainSubRule offsets are not nullable.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGsub, ensureChainingRuleSetWithin(table, rule_set));

    // Minimal valid ChainSubRule: no backtrack, one input glyph (the covered
    // glyph), no lookahead, and no substitution records.
    const rule = rule_set + 4;
    writeU16Test(&bytes, rule_set + 2, 4);
    writeU16Test(&bytes, rule + 0, 0); // BacktrackGlyphCount.
    writeU16Test(&bytes, rule + 2, 1); // InputGlyphCount.
    writeU16Test(&bytes, rule + 4, 0); // LookaheadGlyphCount.
    writeU16Test(&bytes, rule + 6, 0); // SubstCount.
    try ensureChainingRuleSetWithin(table, rule_set);
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
    try std.testing.expectError(error.BadGsub, ensureMultipleSubstitutionSubtableWithin(table, subtable));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, applyMultipleSubstitution(table, subtable, &glyphs, std.testing.allocator, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // An empty Sequence can still be represented explicitly; only the child
    // pointer itself is required to name a real Sequence table.
    writeU16Test(&bytes, subtable + 6, 14);
    writeU16Test(&bytes, subtable + 14, 0); // Sequence.GlyphCount.
    try ensureMultipleSubstitutionSubtableWithin(table, subtable);
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
    try std.testing.expectError(error.BadGsub, ensureAlternateSubstitutionSubtableWithin(table, subtable));
    try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    try std.testing.expectError(error.BadGsub, applyAlternateSubstitution(table, subtable, &glyphs, 0, .{}));
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);

    // A real AlternateSet may still be empty and produce no substitution; only
    // the child pointer itself is required to name an actual AlternateSet.
    writeU16Test(&bytes, subtable + 6, 14);
    writeU16Test(&bytes, subtable + 14, 0); // AlternateSet.GlyphCount.
    try ensureAlternateSubstitutionSubtableWithin(table, subtable);
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
        try std.testing.expectError(error.BadGsub, ensureLigatureSubstitutionSubtableWithin(table, subtable));
        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

        var glyphs = std.ArrayList(GlyphId).empty;
        defer glyphs.deinit(std.testing.allocator);
        try glyphs.append(std.testing.allocator, 1);
        try glyphs.append(std.testing.allocator, 2);
        try applyLigatureSubstitution(table, subtable, &glyphs, std.testing.allocator, 0, .{});
        try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
        try std.testing.expectEqual(null, try applyLigatureSubstitutionAt(table, subtable, &glyphs, 0, std.testing.allocator, 0, .{}));
        try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);

        // A present but empty LigatureSet is still structurally valid; only the
        // offset itself is required to name a real child table.
        writeU16Test(&bytes, subtable + 6, 14);
        writeU16Test(&bytes, subtable + 14, 0); // LigatureSet.LigatureCount.
        try ensureLigatureSubstitutionSubtableWithin(table, subtable);
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
        try std.testing.expectError(error.BadGsub, ensureLigatureSubstitutionSubtableWithin(table, subtable));
        try std.testing.expectError(error.BadGsub, validateGlyphBounds(&bytes, 0, bytes.len, 4));

        var glyphs = std.ArrayList(GlyphId).empty;
        defer glyphs.deinit(std.testing.allocator);
        try glyphs.append(std.testing.allocator, 1);
        try glyphs.append(std.testing.allocator, 2);
        try applyLigatureSubstitution(table, subtable, &glyphs, std.testing.allocator, 0, .{});
        try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
        try std.testing.expectEqual(null, try applyLigatureSubstitutionAt(table, subtable, &glyphs, 0, std.testing.allocator, 0, .{}));
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

    try std.testing.expect(sourceFeatureAllowsGlyph(.{
        .glyph_source_indices = &sources,
        .source_features = &features,
        .active_source_feature = unicode.tag("blwf"),
    }, 0));
    try std.testing.expect(!sourceFeatureAllowsGlyph(.{
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

test "GSUB multiple substitution preserves ligature provenance" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;

    writeU16Test(&bytes, 0, 2); // MultipleSubst lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);
    const multiple = 8;
    writeU16Test(&bytes, multiple + 0, 1);
    writeU16Test(&bytes, multiple + 2, 12);
    writeU16Test(&bytes, multiple + 4, 1);
    writeU16Test(&bytes, multiple + 6, 18);
    writeCoverage1(&bytes, multiple + 12, 10);
    const sequence = multiple + 18;
    writeU16Test(&bytes, sequence + 0, 2);
    writeU16Test(&bytes, sequence + 2, 20);
    writeU16Test(&bytes, sequence + 4, 21);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.append(allocator, 3);

    var stage_substituted = std.ArrayList(bool).empty;
    defer stage_substituted.deinit(allocator);
    try stage_substituted.append(allocator, false);

    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    const ligature_info = try components.addLigature(allocator, &.{ 3, 4 });
    try components.infos.append(allocator, ligature_info);

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_source_indices = &sources,
        .glyph_stage_substituted = &stage_substituted,
        .ligature_components = &components,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 21 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 3, 3 }, sources.items);
    try std.testing.expectEqualSlices(bool, &.{ true, true }, stage_substituted.items);
    try std.testing.expectEqual(@as(u8, 2), components.infos.items[0].component_count);
    try std.testing.expectEqual(@as(u8, 2), components.infos.items[1].component_count);
    try std.testing.expect(components.infos.items[0].flags.multiplied);
    try std.testing.expect(components.infos.items[1].flags.multiplied);
    try std.testing.expectEqual(@as(u4, 0), components.infos.items[0].flags.multiple_component);
    try std.testing.expectEqual(@as(u4, 1), components.infos.items[1].flags.multiple_component);
    try std.testing.expectEqual(
        components.infos.items[0].source_start,
        components.infos.items[1].source_start,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 3, 4 },
        components.componentSources(components.infos.items[0]).?,
    );
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
    try applyContextCoverageLookupAccelerated(
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
        applyContextCoverageLookupAccelerated(
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
        applyContextCoverageLookupAccelerated(
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
    try applyContextCoverageLookupAccelerated(
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

test "GSUB multiple substitution skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0x0008);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const multiple = 8;
    writeU16Test(&bytes, multiple + 0, 1);
    writeU16Test(&bytes, multiple + 2, 12);
    writeU16Test(&bytes, multiple + 4, 1);
    writeU16Test(&bytes, multiple + 6, 18);
    writeCoverage1(&bytes, multiple + 12, 3);
    const sequence = multiple + 18;
    writeU16Test(&bytes, sequence + 0, 2);
    writeU16Test(&bytes, sequence + 2, 30);
    writeU16Test(&bytes, sequence + 4, 31);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 3, 4, 3 });

    const glyph_classes = [_]u16{ 0, 0, 0, 3, 0 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 3, 4, 3 }, glyphs.items);
}

test "GSUB alternate substitution skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 2, 0x0008);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const alternate = 8;
    writeU16Test(&bytes, alternate + 0, 1);
    writeU16Test(&bytes, alternate + 2, 12);
    writeU16Test(&bytes, alternate + 4, 1);
    writeU16Test(&bytes, alternate + 6, 18);
    writeCoverage1(&bytes, alternate + 12, 3);
    const alternate_set = alternate + 18;
    writeU16Test(&bytes, alternate_set + 0, 1);
    writeU16Test(&bytes, alternate_set + 2, 30);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 3, 4, 3 });

    const glyph_classes = [_]u16{ 0, 0, 0, 3, 0 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 3, 4, 3 }, glyphs.items);
}

test "GSUB alternate substitution uses feature value as one-based alternate index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 36;

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const alternate = 8;
    writeU16Test(&bytes, alternate + 0, 1);
    writeU16Test(&bytes, alternate + 2, 12);
    writeU16Test(&bytes, alternate + 4, 1);
    writeU16Test(&bytes, alternate + 6, 18);
    writeCoverage1(&bytes, alternate + 12, 10);
    const alternate_set = alternate + 18;
    writeU16Test(&bytes, alternate_set + 0, 2);
    writeU16Test(&bytes, alternate_set + 2, 20);
    writeU16Test(&bytes, alternate_set + 4, 30);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .active_feature_value = 2,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{30}, glyphs.items);
}

test "GSUB alternate substitution subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 58;

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 34);

    const first_alternate = 10;
    writeU16Test(&bytes, first_alternate + 0, 1);
    writeU16Test(&bytes, first_alternate + 2, 8);
    writeU16Test(&bytes, first_alternate + 4, 1);
    writeU16Test(&bytes, first_alternate + 6, 14);
    writeCoverage1(&bytes, first_alternate + 8, 10);
    const first_set = first_alternate + 14;
    writeU16Test(&bytes, first_set + 0, 1);
    writeU16Test(&bytes, first_set + 2, 20);

    const second_alternate = 34;
    writeU16Test(&bytes, second_alternate + 0, 1);
    writeU16Test(&bytes, second_alternate + 2, 8);
    writeU16Test(&bytes, second_alternate + 4, 1);
    writeU16Test(&bytes, second_alternate + 6, 14);
    writeCoverage1(&bytes, second_alternate + 8, 20);
    const second_set = second_alternate + 14;
    writeU16Test(&bytes, second_set + 0, 1);
    writeU16Test(&bytes, second_set + 2, 30);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    // The first glyph becomes 20 in the first subtable but must not be fed
    // through the later subtable that also covers glyph 20.
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

test "GSUB extension alternate substitution subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 66;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 38);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 3);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_alternate = first_extension + 8;
    writeU16Test(&bytes, first_alternate + 0, 1);
    writeU16Test(&bytes, first_alternate + 2, 8);
    writeU16Test(&bytes, first_alternate + 4, 1);
    writeU16Test(&bytes, first_alternate + 6, 14);
    writeCoverage1(&bytes, first_alternate + 8, 10);
    const first_set = first_alternate + 14;
    writeU16Test(&bytes, first_set + 0, 1);
    writeU16Test(&bytes, first_set + 2, 20);

    const second_extension = 38;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 3);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_alternate = second_extension + 8;
    writeU16Test(&bytes, second_alternate + 0, 1);
    writeU16Test(&bytes, second_alternate + 2, 8);
    writeU16Test(&bytes, second_alternate + 4, 1);
    writeU16Test(&bytes, second_alternate + 6, 14);
    writeCoverage1(&bytes, second_alternate + 8, 20);
    const second_set = second_alternate + 14;
    writeU16Test(&bytes, second_set + 0, 1);
    writeU16Test(&bytes, second_set + 2, 30);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    // ExtensionSubst does not create another lookup boundary; wrapped
    // AlternateSubst subtables remain alternatives for the original glyph.
    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 30 }, glyphs.items);
}

test "GSUB multiple substitution subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 58;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 34);

    const first_multiple = 10;
    writeU16Test(&bytes, first_multiple + 0, 1);
    writeU16Test(&bytes, first_multiple + 2, 14);
    writeU16Test(&bytes, first_multiple + 4, 1);
    writeU16Test(&bytes, first_multiple + 6, 8);
    const first_sequence = first_multiple + 8;
    writeU16Test(&bytes, first_sequence + 0, 2);
    writeU16Test(&bytes, first_sequence + 2, 20);
    writeU16Test(&bytes, first_sequence + 4, 21);
    writeCoverage1(&bytes, first_multiple + 14, 10);

    const second_multiple = 34;
    writeU16Test(&bytes, second_multiple + 0, 1);
    writeU16Test(&bytes, second_multiple + 2, 14);
    writeU16Test(&bytes, second_multiple + 4, 1);
    writeU16Test(&bytes, second_multiple + 6, 8);
    const second_sequence = second_multiple + 8;
    writeU16Test(&bytes, second_sequence + 0, 2);
    writeU16Test(&bytes, second_sequence + 2, 30);
    writeU16Test(&bytes, second_sequence + 4, 31);
    writeCoverage1(&bytes, second_multiple + 14, 20);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    // The first subtable expands glyph 10 into a sequence whose first glyph is
    // also covered by the second subtable. Subtables in one lookup are
    // alternatives for each original input position, so only the original
    // second glyph 20 may be considered by the later subtable.
    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 21, 30, 31 }, glyphs.items);
}

test "GSUB extension multiple substitution subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 82;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 50);

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

    const second_extension = 50;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_multiple = second_extension + 8;
    writeU16Test(&bytes, second_multiple + 0, 1);
    writeU16Test(&bytes, second_multiple + 2, 14);
    writeU16Test(&bytes, second_multiple + 4, 1);
    writeU16Test(&bytes, second_multiple + 6, 8);
    const second_sequence = second_multiple + 8;
    writeU16Test(&bytes, second_sequence + 0, 2);
    writeU16Test(&bytes, second_sequence + 2, 30);
    writeU16Test(&bytes, second_sequence + 4, 31);
    writeCoverage1(&bytes, second_multiple + 14, 20);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    // ExtensionSubst only widens offsets; homogeneous ExtensionSubst wrappers
    // around MultipleSubst must still preserve lookup-level subtable ordering.
    try std.testing.expectEqualSlices(GlyphId, &.{ 20, 21, 30, 31 }, glyphs.items);
}

test "GSUB ligature substitution honors LigatureSet order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;

    writeU16Test(&bytes, 0, 4);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const lig_subst = 8;
    writeU16Test(&bytes, lig_subst + 0, 1);
    writeU16Test(&bytes, lig_subst + 2, 28);
    writeU16Test(&bytes, lig_subst + 4, 1);
    writeU16Test(&bytes, lig_subst + 6, 8);

    const ligature_set = lig_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 2);
    writeU16Test(&bytes, ligature_set + 2, 6);
    writeU16Test(&bytes, ligature_set + 4, 14);

    // Both records match the input prefix. OpenType gives priority to the
    // first Ligature table in the set, even when a later record consumes more
    // components.
    const first_ligature = ligature_set + 6;
    writeU16Test(&bytes, first_ligature + 0, 40);
    writeU16Test(&bytes, first_ligature + 2, 2);
    writeU16Test(&bytes, first_ligature + 4, 2);

    const later_longer_ligature = ligature_set + 14;
    writeU16Test(&bytes, later_longer_ligature + 0, 50);
    writeU16Test(&bytes, later_longer_ligature + 2, 3);
    writeU16Test(&bytes, later_longer_ligature + 4, 2);
    writeU16Test(&bytes, later_longer_ligature + 6, 3);

    writeCoverage1(&bytes, lig_subst + 28, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 40, 3 }, glyphs.items);
}

test "GSUB ligature preserves synthetic base provenance" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;

    writeU16Test(&bytes, 0, 4);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);
    const ligature_subst = 8;
    writeU16Test(&bytes, ligature_subst + 0, 1);
    writeU16Test(&bytes, ligature_subst + 2, 18);
    writeU16Test(&bytes, ligature_subst + 4, 1);
    writeU16Test(&bytes, ligature_subst + 6, 8);
    const ligature_set = ligature_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 1);
    writeU16Test(&bytes, ligature_set + 2, 4);
    const ligature = ligature_set + 4;
    writeU16Test(&bytes, ligature + 0, 40);
    writeU16Test(&bytes, ligature + 2, 2);
    writeU16Test(&bytes, ligature + 4, 2);
    writeCoverage1(&bytes, ligature_subst + 18, 1);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    var components = ligature_provenance.Store{};
    defer components.deinit(allocator);
    try components.infos.appendSlice(allocator, &.{
        .{ .flags = .{ .synthetic_base = true } },
        .{},
    });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .ligature_components = &components,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{40}, glyphs.items);
    try std.testing.expect(components.infos.items[0].flags.synthetic_base);
}

test "GSUB ligature accelerator preserves preference and ignored component offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;

    const lig_subst = 0;
    writeU16Test(&bytes, lig_subst + 0, 1);
    writeU16Test(&bytes, lig_subst + 2, 34);
    writeU16Test(&bytes, lig_subst + 4, 1);
    writeU16Test(&bytes, lig_subst + 6, 8);

    const ligature_set = lig_subst + 8;
    writeU16Test(&bytes, ligature_set + 0, 2);
    writeU16Test(&bytes, ligature_set + 2, 6);
    writeU16Test(&bytes, ligature_set + 4, 14);

    const preferred = ligature_set + 6;
    writeU16Test(&bytes, preferred + 0, 40);
    writeU16Test(&bytes, preferred + 2, 2);
    writeU16Test(&bytes, preferred + 4, 2);

    const later_longer = ligature_set + 14;
    writeU16Test(&bytes, later_longer + 0, 50);
    writeU16Test(&bytes, later_longer + 2, 3);
    writeU16Test(&bytes, later_longer + 4, 2);
    writeU16Test(&bytes, later_longer + 6, 3);
    writeCoverage1(&bytes, lig_subst + 34, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLigatureSubstAccelerator(table, lig_subst, allocator);
    defer {
        allocator.free(accelerator.components);
        allocator.free(accelerator.definitions);
        allocator.free(accelerator.set_slots);
        allocator.free(accelerator.sets);
    }

    try std.testing.expectEqual(@as(usize, 1), accelerator.sets.len);
    try std.testing.expectEqual(@as(usize, 2), accelerator.definitions.len);
    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 2, 3 }, accelerator.components);
    try std.testing.expect(accelerator.first_component_digest.mayHave(1));
    try std.testing.expect(!accelerator.first_component_digest.mayHave(99));
    try std.testing.expectEqual(@as(usize, 0), requiredLigatureSecondComponents(accelerator).len);
    try std.testing.expect(!accelerator.prefilter_second);

    const set = ligatureSetForGlyph(accelerator.sets, accelerator.set_slots, 1).?;
    const glyphs = [_]GlyphId{ 1, 4, 2, 3 };
    const glyph_classes = [_]u16{ 0, 1, 1, 1, 3 };
    var component_offsets: [max_ligature_components]usize = undefined;
    const match = ligatureAtAcceleratedPrefiltered(
        accelerator,
        set,
        &glyphs,
        0,
        0x0008,
        .{ .glyph_classes = &glyph_classes },
        &component_offsets,
    ).?;
    try std.testing.expectEqual(@as(GlyphId, 40), match.ligature);
    try std.testing.expectEqual(@as(usize, 2), match.component_count);
    try std.testing.expectEqual(@as(usize, 2), match.component_offsets[1]);
    try std.testing.expectEqual(@as(usize, 3), match.match_end);

    var accelerated_glyphs = std.ArrayList(GlyphId).empty;
    defer accelerated_glyphs.deinit(allocator);
    try accelerated_glyphs.appendSlice(allocator, &glyphs);
    const lookup_accelerators = [_]LookupAccelerator{.{
        .lookup_offset = 0,
        .lookup_type = 4,
        .lookup_flag = 0x0008,
        .subtable_count = 1,
        .ligature_subst = accelerator,
    }};
    try std.testing.expect(try applyValidatedAcceleratedLookup(
        table,
        0,
        0,
        &accelerated_glyphs,
        allocator,
        .{
            .glyph_classes = &glyph_classes,
            .lookup_accelerators = &lookup_accelerators,
            .assume_validated = true,
        },
        null,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{ 40, 4, 3 }, accelerated_glyphs.items);
}

test "GSUB ligature matching skips CGJ without IgnoreMarks" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1); // LigatureCount.
    writeU16Test(&bytes, 2, 4);
    writeU16Test(&bytes, 4, 40); // Ligature glyph.
    writeU16Test(&bytes, 6, 2); // First glyph plus one component.
    writeU16Test(&bytes, 8, 2);

    const glyphs = [_]GlyphId{ 7, 1, 9, 2 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });
    const codepoints = [_]u21{ 'X', 'A', 0x034f, 'B' };

    var component_offsets: [max_ligature_components]usize = undefined;
    const match = (try ligatureAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        glyphs[1..],
        1,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
        },
        &component_offsets,
    )).?;

    try std.testing.expectEqual(@as(GlyphId, 40), match.ligature);
    try std.testing.expectEqual(@as(usize, 2), match.component_offsets[1]);
}

test "GSUB ligature matching does not skip CGJ that blocked mark reordering" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1); // LigatureCount.
    writeU16Test(&bytes, 2, 4);
    writeU16Test(&bytes, 4, 40); // Ligature glyph.
    writeU16Test(&bytes, 6, 2); // First glyph plus one component.
    writeU16Test(&bytes, 8, 2);

    const glyphs = [_]GlyphId{ 3, 0, 2 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });
    const codepoints = [_]u21{ 0x064e, 0x034f, 0x0651 };

    var component_offsets: [max_ligature_components]usize = undefined;
    const match = try ligatureAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        &glyphs,
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
        },
        &component_offsets,
    );

    try std.testing.expect(match == null);
}

test "GSUB ligature matching skips variation selector fallback glyphs" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1); // LigatureCount.
    writeU16Test(&bytes, 2, 4);
    writeU16Test(&bytes, 4, 40); // Ligature glyph.
    writeU16Test(&bytes, 6, 2); // First glyph plus one component.
    writeU16Test(&bytes, 8, 2);

    const glyphs = [_]GlyphId{ 1, 0, 2 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });
    const codepoints = [_]u21{ 'f', 0xfe00, 'i' };

    var component_offsets: [max_ligature_components]usize = undefined;
    const match = (try ligatureAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        &glyphs,
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
        },
        &component_offsets,
    )).?;

    try std.testing.expectEqual(@as(GlyphId, 40), match.ligature);
    try std.testing.expectEqual(@as(usize, 2), match.component_offsets[1]);
}

test "GSUB ligature matching keeps Mongolian FVS fallback glyphs visible" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1); // LigatureCount.
    writeU16Test(&bytes, 2, 4);
    writeU16Test(&bytes, 4, 40); // Ligature glyph.
    writeU16Test(&bytes, 6, 2); // First glyph plus one component.
    writeU16Test(&bytes, 8, 2);

    const glyphs = [_]GlyphId{ 1, 0, 2 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });
    const codepoints = [_]u21{ 0x1868, 0x180d, 0x180a };

    var component_offsets: [max_ligature_components]usize = undefined;
    const match = try ligatureAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        &glyphs,
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
        },
        &component_offsets,
    );

    // Unlike an ordinary unresolved VS, Mongolian FVS is non-skippable during
    // shaping. It therefore blocks this base-plus-NIRUGU ligature even when its
    // own nominal cmap lookup produced glyph zero.
    try std.testing.expect(match == null);
}

test "GSUB ligature matching keeps variation selectors with real glyphs" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1); // LigatureCount.
    writeU16Test(&bytes, 2, 4);
    writeU16Test(&bytes, 4, 40); // Ligature glyph.
    writeU16Test(&bytes, 6, 2); // First glyph plus one component.
    writeU16Test(&bytes, 8, 4);

    const glyphs = [_]GlyphId{ 1, 4, 2 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });
    const codepoints = [_]u21{ 0x101d, 0xfe00, 0x1031 };

    var component_offsets: [max_ligature_components]usize = undefined;
    const match = (try ligatureAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        &glyphs,
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
        },
        &component_offsets,
    )).?;

    try std.testing.expectEqual(@as(GlyphId, 40), match.ligature);
    try std.testing.expectEqual(@as(usize, 1), match.component_offsets[1]);
}

test "GSUB ligature matching stops skipped components at source syllable boundary" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1); // LigatureCount.
    writeU16Test(&bytes, 2, 4);
    writeU16Test(&bytes, 4, 40); // Ligature glyph.
    writeU16Test(&bytes, 6, 2); // First glyph plus one component.
    writeU16Test(&bytes, 8, 3);

    const glyphs = [_]GlyphId{ 1, 2, 3 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });
    const syllables = [_]u8{ 1, 2, 2 };

    var component_offsets: [max_ligature_components]usize = undefined;
    const match = try ligatureAt(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        &glyphs,
        0,
        0x0002, // ignoreBaseGlyphs skips glyph 2 but must not cross its syllable.
        .{
            .glyph_source_indices = &sources,
            .source_syllables = &syllables,
            .match_source_syllable = true,
        },
        &component_offsets,
    );

    try std.testing.expect(match == null);
}

test "GSUB reverse chaining skips lookup-flag ignored context glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 46;

    writeU16Test(&bytes, 0, 8);
    writeU16Test(&bytes, 2, 0x0008);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const reverse = 8;
    writeU16Test(&bytes, reverse + 0, 1);
    writeU16Test(&bytes, reverse + 2, 20);
    writeU16Test(&bytes, reverse + 4, 1);
    writeU16Test(&bytes, reverse + 6, 26);
    writeU16Test(&bytes, reverse + 8, 1);
    writeU16Test(&bytes, reverse + 10, 32);
    writeU16Test(&bytes, reverse + 12, 1);
    writeU16Test(&bytes, reverse + 14, 9);
    writeCoverage1(&bytes, reverse + 20, 2);
    writeCoverage1(&bytes, reverse + 26, 1);
    writeCoverage1(&bytes, reverse + 32, 3);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 4, 2, 5, 3 });

    const glyph_classes = [_]u16{ 0, 0, 0, 0, 3, 3 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 4, 9, 5, 3 }, glyphs.items);
}

test "GSUB substituted default ignorables stay visible to contextual matching" {
    const allocator = std.testing.allocator;
    const glyphs = [_]GlyphId{ 10, 11, 12 };
    const codepoints = [_]u21{ 'A', 0x200c, 'B' };

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1, 2 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false, false });

    const options = LookupOptions{
        .glyph_source_indices = &sources,
        .glyph_substituted = &substituted,
        .source_codepoints = &codepoints,
    };

    try std.testing.expect(contextualMaySkipGlyph(0, options, &glyphs, 1, true));
    substituted.items[1] = true;
    try std.testing.expect(!contextualMaySkipGlyph(0, options, &glyphs, 1, true));

    const cgj_codepoints = [_]u21{ 'A', 0x034f, 'B' };
    const cgj_options = LookupOptions{
        .glyph_source_indices = &sources,
        .glyph_substituted = &substituted,
        .source_codepoints = &cgj_codepoints,
    };
    // CGJ remains transparent even after GSUB touched its glyph, and input
    // matching treats it as transparent just like context matching does.
    try std.testing.expect(contextualMaySkipGlyph(0, cgj_options, &glyphs, 1, true));
    try std.testing.expect(contextualMaySkipGlyph(0, cgj_options, &glyphs, 1, false));

    const mongolian_fvs_codepoints = [_]u21{ 0x1868, 0x180d, 0x180a };
    const mongolian_fvs_options = LookupOptions{
        .glyph_source_indices = &sources,
        .glyph_substituted = &substituted,
        .source_codepoints = &mongolian_fvs_codepoints,
    };
    try std.testing.expect(!contextualMaySkipGlyph(0, mongolian_fvs_options, &glyphs, 1, true));
    try std.testing.expect(!contextualMaySkipGlyph(0, mongolian_fvs_options, &glyphs, 1, false));
}

test "GSUB reverse chaining subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 120;

    writeU16Test(&bytes, 0, 8);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 3);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 48);
    writeU16Test(&bytes, 10, 86);

    const first_reverse = 12;
    writeU16Test(&bytes, first_reverse + 0, 1);
    writeU16Test(&bytes, first_reverse + 2, 20);
    writeU16Test(&bytes, first_reverse + 4, 1);
    writeU16Test(&bytes, first_reverse + 6, 26);
    writeU16Test(&bytes, first_reverse + 8, 0);
    writeU16Test(&bytes, first_reverse + 10, 1);
    writeU16Test(&bytes, first_reverse + 12, 3);
    writeCoverage1(&bytes, first_reverse + 20, 2);
    writeCoverage1(&bytes, first_reverse + 26, 1);

    const second_reverse = 48;
    writeU16Test(&bytes, second_reverse + 0, 1);
    writeU16Test(&bytes, second_reverse + 2, 20);
    writeU16Test(&bytes, second_reverse + 4, 1);
    writeU16Test(&bytes, second_reverse + 6, 26);
    writeU16Test(&bytes, second_reverse + 8, 0);
    writeU16Test(&bytes, second_reverse + 10, 1);
    writeU16Test(&bytes, second_reverse + 12, 4);
    writeCoverage1(&bytes, second_reverse + 20, 3);
    writeCoverage1(&bytes, second_reverse + 26, 1);

    const third_reverse = 86;
    writeU16Test(&bytes, third_reverse + 0, 1);
    writeU16Test(&bytes, third_reverse + 2, 20);
    writeU16Test(&bytes, third_reverse + 4, 0);
    writeU16Test(&bytes, third_reverse + 6, 1);
    writeU16Test(&bytes, third_reverse + 8, 26);
    writeU16Test(&bytes, third_reverse + 10, 1);
    writeU16Test(&bytes, third_reverse + 12, 5);
    writeCoverage1(&bytes, third_reverse + 20, 1);
    writeCoverage1(&bytes, third_reverse + 26, 3);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{});

    // The rightmost glyph first matches subtable 0 (2 -> 3). The left glyph
    // then sees that refined lookahead and may match subtable 2 (1 -> 5).
    // A subtable-global implementation would visit subtable 2 before subtable
    // 0 has refined the right glyph and would leave the left glyph unchanged.
    // The middle subtable also proves a replacement is not fed through later
    // subtables for the same original position.
    try std.testing.expectEqualSlices(GlyphId, &.{ 5, 3 }, glyphs.items);
}

test "GSUB accelerates extension reverse chaining without changing subtable order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 7); // ExtensionSubst lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10); // Wrapper 0.
    writeU16Test(&bytes, 8, 44); // Wrapper 1.

    const wrapper0 = 10;
    writeU16Test(&bytes, wrapper0 + 0, 1);
    writeU16Test(&bytes, wrapper0 + 2, 8); // ReverseChainSingleSubst.
    writeU32Test(&bytes, wrapper0 + 4, 8);
    const reverse0 = wrapper0 + 8;
    writeU16Test(&bytes, reverse0 + 0, 1);
    writeU16Test(&bytes, reverse0 + 2, 14); // Coverage.
    writeU16Test(&bytes, reverse0 + 4, 0); // BacktrackGlyphCount.
    writeU16Test(&bytes, reverse0 + 6, 1); // LookaheadGlyphCount.
    writeU16Test(&bytes, reverse0 + 8, 20);
    writeU16Test(&bytes, reverse0 + 10, 1); // GlyphCount.
    writeU16Test(&bytes, reverse0 + 12, 9); // Substitute glyph.
    writeCoverage1(&bytes, reverse0 + 14, 2);
    writeCoverage1(&bytes, reverse0 + 20, 3);

    const wrapper1 = 44;
    writeU16Test(&bytes, wrapper1 + 0, 1);
    writeU16Test(&bytes, wrapper1 + 2, 8);
    writeU32Test(&bytes, wrapper1 + 4, 8);
    const reverse1 = wrapper1 + 8;
    writeU16Test(&bytes, reverse1 + 0, 1);
    writeU16Test(&bytes, reverse1 + 2, 12);
    writeU16Test(&bytes, reverse1 + 4, 0);
    writeU16Test(&bytes, reverse1 + 6, 0);
    writeU16Test(&bytes, reverse1 + 8, 1);
    writeU16Test(&bytes, reverse1 + 10, 10);
    writeCoverage1(&bytes, reverse1 + 12, 2);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true };
    const accelerator = try accelerator_root.build.lookup.one(table, 0, allocator);
    defer {
        var accelerators = [_]LookupAccelerator{accelerator};
        deinitLookupAcceleratorContents(allocator, accelerators[0..]);
    }
    try std.testing.expect(accelerator.reverse_chaining_groups.len != 0);

    var first = std.ArrayList(GlyphId).empty;
    defer first.deinit(allocator);
    try first.appendSlice(allocator, &.{ 2, 3 });
    try applyExtensionReverseChainingSingleSubstitutionLookup(table, 0, 2, &first, 0, .{}, &accelerator);
    try std.testing.expectEqualSlices(GlyphId, &.{ 9, 3 }, first.items);

    var second = std.ArrayList(GlyphId).empty;
    defer second.deinit(allocator);
    try second.appendSlice(allocator, &.{ 2, 4 });
    try applyExtensionReverseChainingSingleSubstitutionLookup(table, 0, 2, &second, 0, .{}, &accelerator);
    try std.testing.expectEqualSlices(GlyphId, &.{ 10, 4 }, second.items);
}

test "GSUB exact extension reverse chaining context accelerator" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 110;

    writeU16Test(&bytes, 0, 7); // ExtensionSubst lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10); // Wrapper 0.
    writeU16Test(&bytes, 8, 60); // Wrapper 1.

    const first_wrapper = 10;
    writeU16Test(&bytes, first_wrapper + 0, 1);
    writeU16Test(&bytes, first_wrapper + 2, 8); // ReverseChainSingleSubst.
    writeU32Test(&bytes, first_wrapper + 4, 8);
    const first_reverse = first_wrapper + 8;
    writeU16Test(&bytes, first_reverse + 0, 1);
    writeU16Test(&bytes, first_reverse + 2, 18); // Target coverage.
    writeU16Test(&bytes, first_reverse + 4, 1); // BacktrackGlyphCount.
    writeU16Test(&bytes, first_reverse + 6, 24);
    writeU16Test(&bytes, first_reverse + 8, 2); // LookaheadGlyphCount.
    writeU16Test(&bytes, first_reverse + 10, 30);
    writeU16Test(&bytes, first_reverse + 12, 36);
    writeU16Test(&bytes, first_reverse + 14, 1); // GlyphCount.
    writeU16Test(&bytes, first_reverse + 16, 9);
    writeCoverage1(&bytes, first_reverse + 18, 2);
    writeCoverage1(&bytes, first_reverse + 24, 1);
    writeCoverage1(&bytes, first_reverse + 30, 3);
    writeCoverage1(&bytes, first_reverse + 36, 4);

    const second_wrapper = 60;
    writeU16Test(&bytes, second_wrapper + 0, 1);
    writeU16Test(&bytes, second_wrapper + 2, 8);
    writeU32Test(&bytes, second_wrapper + 4, 8);
    const second_reverse = second_wrapper + 8;
    writeU16Test(&bytes, second_reverse + 0, 1);
    writeU16Test(&bytes, second_reverse + 2, 18);
    writeU16Test(&bytes, second_reverse + 4, 1);
    writeU16Test(&bytes, second_reverse + 6, 24);
    writeU16Test(&bytes, second_reverse + 8, 2);
    writeU16Test(&bytes, second_reverse + 10, 30);
    writeU16Test(&bytes, second_reverse + 12, 36);
    writeU16Test(&bytes, second_reverse + 14, 1);
    writeU16Test(&bytes, second_reverse + 16, 10);
    writeCoverage1(&bytes, second_reverse + 18, 2);
    writeCoverage1(&bytes, second_reverse + 24, 1);
    writeCoverage1(&bytes, second_reverse + 30, 3);
    writeCoverage1(&bytes, second_reverse + 36, 5);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true };
    const accelerator = try accelerator_root.build.lookup.one(table, 0, allocator);
    defer {
        var accelerators = [_]LookupAccelerator{accelerator};
        deinitLookupAcceleratorContents(allocator, accelerators[0..]);
    }
    try std.testing.expectEqual(@as(usize, 2), accelerator.reverse_chaining_exact_contexts.len);

    var first = std.ArrayList(GlyphId).empty;
    defer first.deinit(allocator);
    try first.appendSlice(allocator, &.{ 1, 2, 3, 4 });
    try applyExtensionReverseChainingSingleSubstitutionLookup(table, 0, 2, &first, 0, .{}, &accelerator);
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 9, 3, 4 }, first.items);

    var second = std.ArrayList(GlyphId).empty;
    defer second.deinit(allocator);
    try second.appendSlice(allocator, &.{ 1, 2, 3, 5 });
    try applyExtensionReverseChainingSingleSubstitutionLookup(table, 0, 2, &second, 0, .{}, &accelerator);
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 10, 3, 5 }, second.items);

    var miss = std.ArrayList(GlyphId).empty;
    defer miss.deinit(allocator);
    try miss.appendSlice(allocator, &.{ 1, 2, 3, 6 });
    try applyExtensionReverseChainingSingleSubstitutionLookup(table, 0, 2, &miss, 0, .{}, &accelerator);
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2, 3, 6 }, miss.items);
}

test "GSUB source syllable matching blocks reverse chaining backtrack" {
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

    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_source_indices = &sources,
        .source_syllables = &source_syllables,
        .match_source_syllable = true,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);

    const same_syllable = [_]u8{ 1, 1 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_source_indices = &sources,
        .source_syllables = &same_syllable,
        .match_source_syllable = true,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 9 }, glyphs.items);
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
    _ = @import("gsub/tests/feature/root.zig");
    _ = @import("gsub/tests/runtime/root.zig");
    _ = @import("gsub/tests/table/root.zig");
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
