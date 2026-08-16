const std = @import("std");
const accelerator_core = @import("gpos/accelerator/root.zig");
const feature_core = @import("gpos/feature/root.zig");
const GlyphDigest = @import("glyph_digest.zig").GlyphDigest;
const GlyphId = @import("glyph.zig").GlyphId;
const positioning = @import("gpos/positioning/root.zig");
pub const runtime = @import("gpos/runtime/root.zig");
const runtime_lookup = @import("gpos/runtime/lookup/root.zig");
const runtime_output = @import("gpos/runtime/output/root.zig");
const table_core = @import("gpos/table/root.zig");
const validation = @import("gpos/validation/root.zig");
const class_context = @import("opentype/class_context.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const run_metadata = @import("shaping/run_metadata.zig");
const unicode = @import("unicode.zig");
const shape_profile_mod = @import("shape_profile.zig");

/// GPOS produces additive adjustments instead of mutating glyph ids. The caller
/// applies these deltas while constructing final glyph positions.
pub const GposError = error{
    BadGpos,
    InvalidShapingInput,
    UnsupportedGpos,
    EndOfStream,
};

pub const Adjustment = positioning.Adjustment;
pub const AttachmentType = positioning.AttachmentType;

const PositionContextResult = runtime_lookup.contextual.context.Result;

const Table = table_core.View;

pub const VariationStore = positioning.VariationStore;

pub const LookupAccelerator = accelerator_core.model.Lookup;
pub const LookupOptions = runtime.Options;
const PairPosAcceleratorKind = accelerator_core.model.PairPositionKind;
const PairPosSubtableAccelerator = accelerator_core.model.PairPositionSubtable;
const PairPosRecord = accelerator_core.model.PairPositionRecord;
const PairClassEntry = accelerator_core.model.PairClassEntry;
const appendAdjustment = runtime_output.adjustments.append;
const appendAdjustmentEx = runtime_output.adjustments.appendWithFlags;
const findAdjustment = runtime_output.adjustments.find;
const markUnsafePositioningPair = runtime_output.safety.markPair;
const markUnsafePairApplication = runtime_output.safety.markPairApplication;
const markUnsafePositioningChainingContext =
    runtime_output.safety.markChainingContext;
const context_runtime = runtime_lookup.contextual.context;
const chaining_runtime = runtime_lookup.contextual.chaining;
const collectCursiveAdjustment = runtime_lookup.cursive.collect;
const collectCursiveAdjustmentParsed = runtime_lookup.cursive.collectParsed;
const collectCursiveAdjustmentAt = runtime_lookup.cursive.collectAt;
const CursivePositionSubtable = runtime_lookup.cursive.Parsed;
const collectMarkToBaseAdjustment = runtime_lookup.marks.base.collect;
const collectMarkToBaseAdjustmentParsed =
    runtime_lookup.marks.base.collectParsed;
const collectMarkToBaseAdjustmentAt = runtime_lookup.marks.base.collectAt;
const MarkToBaseSubtable = runtime_lookup.marks.base.Parsed;
const appendMarkAttachmentAdjustment = runtime_lookup.marks.output.append;
const previousUnignoredCoveredGlyph =
    runtime_lookup.marks.search.previousUnignoredCoveredGlyph;
const markGlyphForAttachmentSearch = runtime_lookup.marks.search.markGlyph;
const markAttachmentSearchSkipsNonCoveredGlyph =
    runtime_lookup.marks.search.skipsNonCoveredGlyph;
const isMultipleSubstContinuationForMarkSearch =
    runtime_lookup.marks.search.isMultipleSubstContinuation;
const collectMarkToLigatureAdjustment =
    runtime_lookup.marks.ligature.collect;
const collectMarkToLigatureAdjustmentAt =
    runtime_lookup.marks.ligature.collectAt;
const collectMarkToMarkAdjustment = runtime_lookup.marks.mark.collect;
const collectMarkToMarkAdjustmentAt = runtime_lookup.marks.mark.collectAt;
const collectSingleAdjustmentLookup = runtime_lookup.single.collectLookup;
const collectSingleAdjustmentSubtable = runtime_lookup.single.collectSubtable;
const collectSingleAdjustment = runtime_lookup.single.collect;
const collectSingleAdjustmentAt = runtime_lookup.single.collectAt;
const collectSingleAdjustmentAtAccelerated =
    runtime_lookup.single.collectAtAccelerated;
const SinglePosSubtable = runtime_lookup.single.Parsed;
const collectPairAdjustmentLookup =
    runtime_lookup.pair.generic.collectLookup;
const collectExtensionPairAdjustmentLookup =
    runtime_lookup.pair.generic.collectExtensionLookup;
const collectPairAdjustment = runtime_lookup.pair.generic.collect;
const collectPairAdjustmentAt = runtime_lookup.pair.generic.collectAt;
const collectPairAdjustmentAtParsed =
    runtime_lookup.pair.generic.collectAtParsed;
const advanceAfterPairPosition =
    runtime_lookup.pair.generic.advanceAfterPair;
const pairPosSubtablesHaveNativeData =
    runtime_lookup.pair.accelerated.hasNativeData;
const collectPairAdjustmentLookupAccelerated =
    runtime_lookup.pair.accelerated.collectLookup;
const acceleratedDenseClassPairAdvance =
    runtime_lookup.pair.accelerated.denseClassAdvance;
const PairPositionSubtable = runtime_lookup.pair.generic.Parsed;
const buildLookupAccelerator = accelerator_core.build.lookup.one;
const deinitLookupAcceleratorContents =
    accelerator_core.build.lookup.deinitContents;
const buildChainingCoverageSubtable =
    accelerator_core.build.chaining.coverageSubtable;
const deinitChainingCoverageSubtables =
    accelerator_core.build.chaining.deinitCoverageSubtables;
const deinitChainingCoverageSubtableContents =
    accelerator_core.build.chaining.deinitCoverageSubtableContents;

const max_run_digest_cache_entries = 16;

const RunDigestCache = struct {
    const Entry = struct {
        lookup_flag: u16,
        active_mark_filtering_set: ?u16,
        digest: GlyphDigest,
    };

    entries: [max_run_digest_cache_entries]Entry = undefined,
    len: usize = 0,

    fn init() RunDigestCache {
        // Entries become readable only after `get` fully assigns them and
        // increments `len`. Leave inactive storage undefined instead of
        // clearing the complete 16-entry cache for every short shaping run.
        var cache: RunDigestCache = undefined;
        cache.len = 0;
        return cache;
    }

    fn get(self: *RunDigestCache, glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GlyphDigest {
        const active_mark_filtering_set = options.active_mark_filtering_set;
        for (self.entries[0..self.len]) |entry| {
            if (entry.lookup_flag == lookup_flag and entry.active_mark_filtering_set == active_mark_filtering_set) {
                return entry.digest;
            }
        }

        const digest = glyphRunDigest(glyphs, lookup_flag, options);
        if (self.len < self.entries.len) {
            self.entries[self.len] = .{
                .lookup_flag = lookup_flag,
                .active_mark_filtering_set = active_mark_filtering_set,
                .digest = digest,
            };
            self.len += 1;
        }
        return digest;
    }
};

const ChainingClassSubtableAccelerator =
    accelerator_core.model.ChainingClassSubtable;
const max_chaining_class_region_glyphs = 64;

const ChainingSubtableGroup = accelerator_core.glyph_groups.Group;
const max_context_preflight_depth = validation.lookup.max_context_depth;
const ensurePositionRecordsWithin = validation.lookup.records;
const ensurePositionRecordMarkFilteringSetsValid =
    validation.lookup.recordMarkFilteringSets;
const ensurePositionLookupHeaderAndExtensionPayloadsWithin =
    validation.lookup.headerAndExtensions;
const ensurePositionLookupSubtablesWithin =
    validation.lookup.lookupSubtables;
const ensurePositionSubtableVariableDataWithin =
    validation.lookup.subtableVariableData;
const ensureContextPositionSubtableWithin =
    validation.lookup.contextSubtable;
const ensurePositionRuleSetWithin = validation.lookup.contextRuleSet;
const ensureChainingContextPositionSubtableWithin =
    validation.lookup.chainingSubtable;
const ensureChainingPositionRuleSetWithin =
    validation.lookup.chainingRuleSet;
const ensureCoverageTableWithin = validation.lookup.coverage;
const ensureClassDefTableWithin = validation.lookup.classDef;
const ensureClassDefTableWithinLimit =
    validation.lookup.classDefWithLimit;
const contextual_matching =
    @import("gpos/runtime/lookup/contextual/matching.zig");
const collectForwardUnignoredGlyphs =
    contextual_matching.forward;

/// Validate GPOS glyph references that are meaningful at font-load time.
///
/// Shaping only visits records whose coverage matches a supplied glyph run, so
/// an out-of-range glyph id in an otherwise well-formed GPOS table could remain
/// latent until later code assumes every advertised glyph has metrics and
/// outline/bitmap contracts. This pass reuses the supported-subtable preflight
/// walker with maxp.numGlyphs attached to the table. Unsupported lookup types
/// remain ignorable, matching the shaping path, while malformed supported
/// lookups and glyph ids outside maxp are rejected.
pub fn validateGlyphBounds(data: []const u8, offset: usize, length: usize, glyph_count: u16) GposError!void {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGpos;
    const table = Table{
        .data = data,
        .offset = offset,
        .length = length,
        .validating_full_lookup_list = true,
        .glyph_count = glyph_count,
    };
    const major = try readU16BadGpos(table, 0);
    if (major != 1) return error.UnsupportedGpos;

    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16BadGpos(table, lookup_list_offset);
    try ensureBytesWithin(table, lookup_list_offset + 2, @as(usize, lookup_count) * 2);
    const feature_count =
        try feature_core.validation.lookupReferences(table, lookup_count);
    try feature_core.validation.scriptReferences(table, feature_count);
    for (0..lookup_count) |lookup_i| {
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16BadGpos(table, lookup_list_offset + 2 + lookup_i * 2));
        try ensurePositionLookupHeaderAndExtensionPayloadsWithin(table, lookup_offset);
        const lookup_type = try readU16BadGpos(table, lookup_offset);
        const subtable_count = try readU16BadGpos(table, lookup_offset + 4);
        try ensurePositionLookupSubtablesWithin(table, lookup_offset, lookup_type, subtable_count);
    }
}

/// Collect positioning adjustments for a post-GSUB glyph stream.
pub fn collectAdjustments(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    return try collectAdjustmentsWithOptions(data, offset, length, glyphs, adjustments, allocator, .{});
}

pub fn collectAdjustmentsWithOptions(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGpos;
    try runtime.matching.validate(options, glyphs.len);
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGpos;
    // GPOS uses the same ScriptList/FeatureList/LookupList topology as GSUB,
    // but feature defaults differ: positioning lookups are generally active
    // unless an explicit feature override disables them.
    const select_start = shapeProfileNow(options.shape_profile, options.profile_io);
    var selected_lookups_owned = if (options.selected_lookups == null)
        try selectedLookupIndices(table, allocator, options)
    else
        std.ArrayList(u16).empty;
    if (options.shape_profile) |profile| profile.gpos_select_ns += shapeProfileElapsed(select_start, options.profile_io);
    defer selected_lookups_owned.deinit(allocator);
    const selected_lookups = options.selected_lookups orelse selected_lookups_owned.items;
    const script_list_offset = try readU16(table, 4);
    const feature_list_offset = try readU16(table, 6);
    const has_feature_topology = script_list_offset != 0 and
        feature_list_offset != 0 and
        try readU16(table, script_list_offset) != 0 and
        try readU16(table, feature_list_offset) != 0;
    // As with GSUB, an empty active-feature selection means no lookup applies
    // for this Script/LangSys. Executing the full lookup list would leak
    // optional or unrelated-script positioning into the run. Low-level callers
    // can opt into the historical all-lookup fallback.
    if (selected_lookups.len == 0 and
        (options.features.len != 0 or (!options.apply_all_if_unselected and has_feature_topology))) return;

    const apply_start = shapeProfileNow(options.shape_profile, options.profile_io);
    defer {
        if (options.shape_profile) |profile| profile.gpos_apply_ns += shapeProfileElapsed(apply_start, options.profile_io);
    }
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    var run_digest_cache = RunDigestCache.init();
    if (selected_lookups.len != 0) {
        for (selected_lookups) |lookup_index| {
            if (lookup_index >= lookup_count) continue;
            const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
            try collectLookupWithIndex(table, lookup_offset, lookup_index, glyphs, adjustments, allocator, options, &run_digest_cache);
        }
    } else {
        for (0..lookup_count) |i| {
            const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + i * 2));
            try collectLookupWithIndex(table, lookup_offset, @intCast(i), glyphs, adjustments, allocator, options, &run_digest_cache);
        }
    }
}

pub fn selectedLookupIndicesForOptions(data: []const u8, offset: usize, length: usize, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)![]u16 {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGpos;
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = options.assume_validated };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGpos;
    var lookups = try selectedLookupIndices(table, allocator, options);
    return try lookups.toOwnedSlice(allocator);
}

pub fn buildLookupAccelerators(data: []const u8, offset: usize, length: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)![]LookupAccelerator {
    return accelerator_core.build.lookup.all(
        data,
        offset,
        length,
        allocator,
    );
}

pub fn deinitLookupAccelerators(allocator: std.mem.Allocator, accelerators: []LookupAccelerator) void {
    accelerator_core.build.lookup.deinit(allocator, accelerators);
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var lookups = try feature_core.selection.lookupIndices(
        table,
        allocator,
        .{
            .script_tag = options.script_tag,
            .language_tag = options.language_tag,
            .overrides = options.features,
        },
    );
    errdefer lookups.deinit(allocator);

    // Filter in place so separating activation-graph parsing from execution
    // does not add another allocation to every uncached shaping selection.
    var write: usize = 0;
    for (lookups.items) |lookup_index| {
        if (!try selectedLookupMayApply(table, lookup_index, options)) continue;
        lookups.items[write] = lookup_index;
        write += 1;
    }
    lookups.shrinkRetainingCapacity(write);

    sortUniqueLookupIndices(&lookups);
    return lookups;
}

fn selectedLookupMayApply(table: Table, lookup_index: u16, options: LookupOptions) GposError!bool {
    if (options.run_may_have_mark_attachments orelse true) return true;
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    if (lookup_index >= lookup_count) return true;
    const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
    const lookup_type = try readU16(table, lookup_offset);
    return switch (lookup_type) {
        4, 5, 6 => false,
        9 => try extensionLookupMayApplyWithoutGdefMarks(table, lookup_offset),
        else => true,
    };
}

fn extensionLookupMayApplyWithoutGdefMarks(table: Table, lookup_offset: usize) GposError!bool {
    const subtable_count = try readU16(table, lookup_offset + 4);
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        if (try readU16(table, subtable_offset) != 1) return true;
        const wrapped_type = try readU16(table, subtable_offset + 2);
        switch (wrapped_type) {
            4, 5, 6 => {},
            else => return true,
        }
    }
    return false;
}

fn lookupIndexLessThan(_: void, lhs: u16, rhs: u16) bool {
    return lhs < rhs;
}

fn recordGposLookupProfile(profile: ?*shape_profile_mod.ShapeStageProfile, lookup_type: u16) void {
    const p = profile orelse return;
    p.gpos_lookup_count += 1;
    switch (lookup_type) {
        1 => p.gpos_single_lookup_count += 1,
        2 => p.gpos_pair_lookup_count += 1,
        4, 5, 6 => p.gpos_mark_lookup_count += 1,
        7, 8 => p.gpos_context_lookup_count += 1,
        9 => p.gpos_extension_lookup_count += 1,
        else => {},
    }
}

fn sortUniqueLookupIndices(lookups: *std.ArrayList(u16)) void {
    if (lookups.items.len < 2) return;

    std.sort.heap(u16, lookups.items, {}, lookupIndexLessThan);
    var write: usize = 1;
    var previous = lookups.items[0];
    for (lookups.items[1..]) |lookup_index| {
        if (lookup_index == previous) continue;
        lookups.items[write] = lookup_index;
        write += 1;
        previous = lookup_index;
    }
    lookups.shrinkRetainingCapacity(write);
}

fn collectLookup(table: Table, lookup_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    try collectLookupWithIndex(table, lookup_offset, null, glyphs, adjustments, allocator, options, null);
}

fn collectLookupWithIndex(table: Table, lookup_offset: usize, lookup_index: ?u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions, run_digest_cache: ?*RunDigestCache) (GposError || std.mem.Allocator.Error)!void {
    const lookup_start = shapeProfileNow(options.shape_profile, options.profile_io);
    defer {
        if (options.shape_profile) |profile| {
            profile.recordGposLookupTime(lookup_index, shapeProfileElapsed(lookup_start, options.profile_io));
        }
    }
    // The public Font path validates and checksums GPOS before setting
    // assume_validated. Keep this hot-path proof to fixed Lookup header fields;
    // full direct/ExtensionPos payload validation below is only needed for
    // untrusted tables and parse-time glyph-bound walks.
    const dispatch = try runtime.dispatch.header(
        table,
        lookup_offset,
        lookup_index,
        options,
    );
    const lookup_type = dispatch.lookup_type;
    const lookup_flag = dispatch.lookup_flag;
    recordGposLookupProfile(options.shape_profile, lookup_type);
    if (lookupNeedsCustomizedOptions(lookup_flag)) {
        // UseMarkFilteringSet stores its set index after the variable-length
        // SubTable offset array. The high byte remains reserved for the older
        // MarkAttachmentType mechanism when bit 4 is clear.
        // LookupOptions includes all post-GSUB source metadata. Copy it only
        // for this lookup-local override; ordinary positioning lookups pass
        // the caller's immutable value directly to the prepared worker.
        var customized_options = options;
        customized_options.active_mark_filtering_set = dispatch.mark_filtering_set;
        try runtime.matching.validateMarkFilteringSetIndex(customized_options);
        return collectLookupWithIndexPrepared(
            table,
            lookup_offset,
            lookup_index,
            glyphs,
            adjustments,
            allocator,
            customized_options,
            run_digest_cache,
            dispatch,
        );
    }
    return collectLookupWithIndexPrepared(
        table,
        lookup_offset,
        lookup_index,
        glyphs,
        adjustments,
        allocator,
        options,
        run_digest_cache,
        dispatch,
    );
}

fn lookupNeedsCustomizedOptions(lookup_flag: u16) bool {
    return (lookup_flag & 0x0010) != 0;
}

test "GPOS lookup customization is limited to mark filtering sets" {
    try std.testing.expect(!lookupNeedsCustomizedOptions(0));
    try std.testing.expect(!lookupNeedsCustomizedOptions(0xff00));
    try std.testing.expect(lookupNeedsCustomizedOptions(0x0010));
    try std.testing.expect(lookupNeedsCustomizedOptions(0xff10));
}

noinline fn collectLookupWithIndexPrepared(
    table: Table,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_options: LookupOptions,
    run_digest_cache: ?*RunDigestCache,
    dispatch: runtime.dispatch.Header,
) (GposError || std.mem.Allocator.Error)!void {
    const lookup_type = dispatch.lookup_type;
    const lookup_flag = dispatch.lookup_flag;
    const subtable_count = dispatch.subtable_count;
    // Positioning results are appended incrementally, but OpenType lookups are
    // atomic units. Preflight supported direct subtables before collecting any
    // adjustment so malformed later subtables cannot leave partial positioning.
    if (!table.assume_validated) try ensurePositionLookupSubtablesWithin(table, lookup_offset, lookup_type, subtable_count);
    if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
        const run_digest = if (run_digest_cache) |cache|
            cache.get(glyphs, lookup_flag, lookup_options)
        else
            glyphRunDigest(glyphs, lookup_flag, lookup_options);
        if (run_digest.isEmpty() or !accelerator.coverage_digest.mayIntersect(run_digest)) return;
        // The coverage-only chaining collector performs this same exact group
        // lookup as its first action for every glyph. Running a whole-run exact
        // preflight here only duplicates the scan: a miss costs the same work,
        // while a hit scans the prefix twice. Other lookup kinds do not own an
        // equivalent grouped dispatcher and retain the preflight.
        if (!accelerator.chaining_coverage_only and
            accelerator.coverage_groups.len != 0 and
            !lookupCoverageGroupsMayMatchRun(accelerator.coverage_groups, accelerator.coverage_group_slots, glyphs, lookup_flag, lookup_options))
        {
            return;
        }
    }
    if (lookup_type == 1) {
        try collectSingleAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 2) {
        if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.pair_pos_subtables.len == subtable_count and
                pairPosSubtablesHaveNativeData(accelerator.pair_pos_subtables))
            {
                try collectPairAdjustmentLookupAccelerated(
                    table,
                    lookup_offset,
                    subtable_count,
                    accelerator,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    lookup_options,
                );
                return;
            }
        }
        try collectPairAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 9) {
        // ExtensionPos only widens offsets, but a lookup still applies as an
        // all-or-nothing unit. Preflight wrapped variable-length arrays before
        // collecting any adjustments so a later malformed wrapper cannot leave
        // earlier wrapper results visible to the caller.
        if (!table.assume_validated) {
            // ExtensionPos lookups must preflight every wrapped variable
            // payload before applying the first subtable. Fixed wrapper checks
            // alone would allow a later malformed value array to leave earlier
            // positioning adjustments visible.
            try ensurePositionLookupHeaderAndExtensionPayloadsWithin(
                table,
                lookup_offset,
            );
        }
        const wrapped_type = try runtime.dispatch.resolvedExtensionType(
            table,
            lookup_offset,
            lookup_type,
            subtable_count,
            lookup_index,
            lookup_options,
        );
        if (wrapped_type) |resolved_type| {
            switch (resolved_type) {
                1 => {
                    try collectExtensionSingleAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
                    return;
                },
                2 => {
                    if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
                        if (accelerator.pair_pos_extension and
                            accelerator.pair_pos_subtables.len == subtable_count)
                        {
                            try collectPairAdjustmentLookupAccelerated(
                                table,
                                lookup_offset,
                                subtable_count,
                                accelerator,
                                glyphs,
                                adjustments,
                                allocator,
                                lookup_flag,
                                lookup_options,
                            );
                            return;
                        }
                    }
                    try collectExtensionPairAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
                    return;
                },
                // Wrapped ChainContextPos subtables are not always the format-3
                // coverage-only shape handled by the homogeneous fast path
                // below. Let the generic ExtensionPos dispatcher preserve
                // ordering while supporting glyph/class chaining formats too.
                8 => {
                    if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
                        if (accelerator.chaining_class_subtables.len != 0) {
                            try collectExtensionChainingClassPositioningLookup(table, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options, accelerator);
                            return;
                        }
                    }
                },
                else => {},
            }
        }
        try collectExtensionAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 8) {
        if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.chaining_coverage_only) {
                try chaining_runtime.coverage.lookup.collect(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options, accelerator, collectPositionRecordsMapped, collectNestedAdjustment);
                return;
            }
        }
    }
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => {}, // SinglePos needs whole-lookup subtable ordering; handled above.
            2 => {}, // PairPos needs whole-lookup subtable ordering; handled above.
            3 => if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
                if (i < accelerator.cursive_subtables.len) {
                    try collectCursiveAdjustmentParsed(table, accelerator.cursive_subtables[i], glyphs, adjustments, allocator, lookup_flag, lookup_options);
                    continue;
                }
                try collectCursiveAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options);
            } else try collectCursiveAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            4 => if (runtime.matching.runMayHaveMarkAttachments(glyphs, lookup_options)) {
                if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
                    if (i < accelerator.mark_to_base_subtables.len) {
                        try collectMarkToBaseAdjustmentParsed(table, accelerator.mark_to_base_subtables[i], glyphs, adjustments, allocator, lookup_flag, lookup_options);
                        continue;
                    }
                }
                try collectMarkToBaseAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options);
            },
            5 => if (runtime.matching.runMayHaveMarkAttachments(glyphs, lookup_options)) try collectMarkToLigatureAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            6 => if (runtime.matching.runMayHaveMarkAttachments(glyphs, lookup_options)) try collectMarkToMarkAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            7 => try context_runtime.collect(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options, collectPositionRecordsMapped),
            8 => try collectChainingContextAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            9 => try collectExtensionAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            else => {},
        }
    }
}

fn lookupCoverageGroupsMayMatchRun(groups: []const ChainingSubtableGroup, slots: []const u16, glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) bool {
    for (glyphs) |glyph| {
        if (runtime.matching.lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
        if (accelerator_core.glyph_groups.find(groups, slots, glyph) != null) return true;
    }
    return false;
}

fn glyphRunDigest(glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GlyphDigest {
    var digest = GlyphDigest.empty();
    for (glyphs) |glyph| {
        if (runtime.matching.lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
        digest.add(glyph);
    }
    return digest;
}

const stack_matched_capacity = 128;

const BoolScratch = struct {
    items: []bool,
    heap: ?[]bool = null,

    fn init(allocator: std.mem.Allocator, len: usize, stack: *[stack_matched_capacity]bool) (GposError || std.mem.Allocator.Error)!BoolScratch {
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

fn collectExtensionSingleAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // Preserve SinglePos lookup ordering through ExtensionPos. Without a
    // lookup-level matched set, overlapping wrapped subtables would stack their
    // deltas even though OpenType treats subtables in one lookup as ordered
    // alternatives for each original glyph position.
    if (glyphs.len == 0) return;
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const matched_scratch = try BoolScratch.init(allocator, glyphs.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    const matched = matched_scratch.items;
    @memset(matched, false);

    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const extension_subtable = try positioning.lookup.dispatch.extensionPayload(table, subtable_offset, 1);
        try collectSingleAdjustmentSubtable(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options, matched);
    }
}

fn collectExtensionAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // Mixed ExtensionPos lookups are uncommon, but preserving ordering for each
    // wrapped positioning kind still matters. In particular, two wrapped
    // PairPos subtables remain alternatives for the same first glyph even when
    // another wrapped type prevents the homogeneous fast path above.
    var single_matched_stack: [stack_matched_capacity]bool = undefined;
    const single_matched_scratch = try BoolScratch.init(allocator, glyphs.len, &single_matched_stack);
    defer single_matched_scratch.deinit(allocator);
    const single_matched = single_matched_scratch.items;
    @memset(single_matched, false);

    var pair_matched_stack: [stack_matched_capacity]bool = undefined;
    const pair_matched_scratch = try BoolScratch.init(allocator, glyphs.len, &pair_matched_stack);
    defer pair_matched_scratch.deinit(allocator);
    const pair_matched = pair_matched_scratch.items;
    @memset(pair_matched, false);

    var pair_consumes_second_stack: [stack_matched_capacity]bool = undefined;
    const pair_consumes_second_scratch = try BoolScratch.init(allocator, glyphs.len, &pair_consumes_second_stack);
    defer pair_consumes_second_scratch.deinit(allocator);
    const pair_consumes_second = pair_consumes_second_scratch.items;
    @memset(pair_consumes_second, false);

    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const pos_format = try readU16(table, subtable_offset);
        if (pos_format != 1) return error.UnsupportedGpos;
        const extension_lookup_type = try readU16(table, subtable_offset + 2);
        if (extension_lookup_type == 9) return error.UnsupportedGpos;
        const extension_subtable = try checkedExtensionPositionPayloadOffset(table, subtable_offset, try readU32(table, subtable_offset + 4));

        switch (extension_lookup_type) {
            1 => try collectSingleAdjustmentSubtable(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options, single_matched),
            2 => {
                if (glyphs.len < 2) continue;
                var first_index: usize = 0;
                const parsed = try positioning.lookup.pair.parse(table, extension_subtable);
                while (first_index + 1 < glyphs.len) {
                    var matched_value_2 = pair_matched[first_index] and pair_consumes_second[first_index];
                    if (!pair_matched[first_index] and
                        try collectPairAdjustmentAtParsed(table, parsed, glyphs, first_index, adjustments, allocator, lookup_flag, options))
                    {
                        pair_matched[first_index] = true;
                        matched_value_2 = parsed.value_format_2 != 0;
                        pair_consumes_second[first_index] = matched_value_2;
                    }
                    first_index = advanceAfterPairPosition(glyphs, first_index, lookup_flag, options, matched_value_2);
                }
            },
            3 => try collectCursiveAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            4 => try collectMarkToBaseAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            5 => try collectMarkToLigatureAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            6 => try collectMarkToMarkAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            7 => try context_runtime.collect(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped),
            8 => try collectChainingContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            else => {},
        }
    }
}

fn shapeProfileNow(profile: ?*shape_profile_mod.ShapeStageProfile, io: ?std.Io) i128 {
    return if (profile != null) std.Io.Clock.now(.awake, io.?).nanoseconds else 0;
}

fn shapeProfileElapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}

fn collectExtensionAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    const extension_subtable = try checkedExtensionPositionPayloadOffset(table, subtable_offset, try readU32(table, subtable_offset + 4));
    // The extension wrapper extends addressing only; LookupFlag still belongs
    // to the outer lookup and must filter glyph classes in the delegated body.
    switch (extension_lookup_type) {
        1 => try collectSingleAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        2 => try collectPairAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        3 => try collectCursiveAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        4 => try collectMarkToBaseAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        5 => try collectMarkToLigatureAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        6 => try collectMarkToMarkAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        7 => try context_runtime.collect(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped),
        8 => try collectChainingContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        else => {},
    }
}

test "GPOS native Coverage preserves format 1 and 2 indexes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;

    writeCoverage1ListTest(&bytes, 0, &.{ 3, 8, 20 });
    writeU16Test(&bytes, 10, 2); // Coverage format 2.
    writeU16Test(&bytes, 12, 2);
    writeU16Test(&bytes, 14, 30);
    writeU16Test(&bytes, 16, 32);
    writeU16Test(&bytes, 18, 0);
    writeU16Test(&bytes, 20, 40);
    writeU16Test(&bytes, 22, 42);
    writeU16Test(&bytes, 24, 3);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const glyph_coverage = try accelerator_core.coverage.Owned.build(table, 0, allocator);
    defer glyph_coverage.deinit(allocator);
    try std.testing.expectEqual(@as(?usize, 0), glyph_coverage.index(3));
    try std.testing.expectEqual(@as(?usize, 2), glyph_coverage.index(20));
    try std.testing.expectEqual(@as(?usize, null), glyph_coverage.index(9));

    const range_coverage = try accelerator_core.coverage.Owned.build(table, 10, allocator);
    defer range_coverage.deinit(allocator);
    try std.testing.expectEqual(@as(?usize, 0), range_coverage.index(30));
    try std.testing.expectEqual(@as(?usize, 2), range_coverage.index(32));
    try std.testing.expectEqual(@as(?usize, 3), range_coverage.index(40));
    try std.testing.expectEqual(@as(?usize, 5), range_coverage.index(42));
    try std.testing.expectEqual(@as(?usize, null), range_coverage.index(33));
}

test "GPOS chaining accelerator caches all Coverage regions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 44;

    writeU16Test(&bytes, 0, 3); // ChainContextPos format 3.
    writeU16Test(&bytes, 2, 1); // Backtrack count.
    writeU16Test(&bytes, 4, 20);
    writeU16Test(&bytes, 6, 2); // Input count.
    writeU16Test(&bytes, 8, 26);
    writeU16Test(&bytes, 10, 32);
    writeU16Test(&bytes, 12, 1); // Lookahead count.
    writeU16Test(&bytes, 14, 38);
    writeU16Test(&bytes, 16, 0); // No positioning records.
    writeCoverage1Test(&bytes, 20, 2);
    writeCoverage1Test(&bytes, 26, 3);
    writeCoverage1Test(&bytes, 32, 4);
    writeCoverage1Test(&bytes, 38, 5);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const subtable = (try buildChainingCoverageSubtable(table, 0, allocator)) orelse return error.TestUnexpectedResult;
    defer deinitChainingCoverageSubtableContents(allocator, subtable);

    try std.testing.expectEqual(@as(usize, 1), subtable.backtrack_coverages.len);
    try std.testing.expectEqual(@as(usize, 2), subtable.input_coverages.len);
    try std.testing.expectEqual(@as(usize, 1), subtable.lookahead_coverages.len);
    try std.testing.expectEqual(@as(?usize, 0), subtable.backtrack_coverages[0].index(2));
    try std.testing.expectEqual(@as(?usize, 0), subtable.input_coverages[0].index(3));
    try std.testing.expectEqual(@as(?usize, 0), subtable.input_coverages[1].index(4));
    try std.testing.expectEqual(@as(?usize, 0), subtable.lookahead_coverages[0].index(5));
    try std.testing.expect(subtable.second_input_digest.mayHave(4));

    const glyphs = [_]GlyphId{ 2, 3, 4, 5 };
    try std.testing.expect(try chaining_runtime.coverage.matching.indices(
        table,
        0,
        &glyphs,
        &.{ 1, 2 },
        subtable.input_offsets_pos,
        subtable.input_coverages,
        0,
    ));
}

fn collectChainingContextAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    switch (try positioning.lookup.contextual.parseChaining(table, subtable_offset)) {
        .glyph => |subtable| try chaining_runtime.glyph.collect(table, subtable, glyphs, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped),
        .class => |subtable| try chaining_runtime.class.collect(table, subtable, glyphs, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped),
        .coverage => |parsed| {
            if (parsed.records.input_count == 0) return;
            try chaining_runtime.coverage.execute.collect(
                table,
                chaining_runtime.coverage.execute.fromParsed(parsed),
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                options,
                collectPositionRecordsMapped,
                collectNestedAdjustment,
            );
        },
    }
}

fn collectChainingContextAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (pos >= glyphs.len) return false;
    switch (try positioning.lookup.contextual.parseChaining(table, subtable_offset)) {
        .glyph => |subtable| return try chaining_runtime.glyph.collectAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped),
        .class => |subtable| return try chaining_runtime.class.collectAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped),
        .coverage => |parsed| {
            if (parsed.records.input_count == 0) return false;
            return (try chaining_runtime.coverage.execute.collectAt(false, table, chaining_runtime.coverage.execute.fromParsed(parsed), glyphs, pos, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped, collectNestedAdjustment)).matched;
        },
    }
}

fn collectNestedExtensionChainingClassPositioningAt(table: Table, subtable_count: u16, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GposError || std.mem.Allocator.Error)!bool {
    if (runtime.matching.lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) return false;
    var subtable_i: usize = 0;
    while (subtable_i < subtable_count and subtable_i < accelerator.chaining_class_subtables.len) : (subtable_i += 1) {
        const subtable = accelerator.chaining_class_subtables[subtable_i];
        if (subtable.rules.len == 0) continue;
        if ((try collectAcceleratedChainingClassPositioningAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options)).matched) return true;
    }
    return false;
}

fn collectExtensionChainingClassPositioningLookup(table: Table, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GposError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (runtime.matching.lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        var subtable_i: usize = 0;
        while (subtable_i < subtable_count and subtable_i < accelerator.chaining_class_subtables.len) : (subtable_i += 1) {
            const subtable = accelerator.chaining_class_subtables[subtable_i];
            if (subtable.rules.len == 0) continue;
            const result = try collectAcceleratedChainingClassPositioningAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options);
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
    }
}

fn collectAcceleratedChainingClassPositioningAt(table: Table, subtable: ChainingClassSubtableAccelerator, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!PositionContextResult {
    if (try table_core.coverage.index(table, subtable.coverage_offset, glyphs[pos]) == null) return .{};
    const input_class = try table_core.class_def.value(table, subtable.input_class_def, glyphs[pos]);
    const group = class_context.groupForClass(subtable.groups, input_class) orelse return .{};
    if (group.max_input_count == 0 or group.max_input_count > max_chaining_class_region_glyphs or group.max_lookahead_count > max_chaining_class_region_glyphs) return error.UnsupportedGpos;

    var input_indices: [max_chaining_class_region_glyphs]usize = undefined;
    if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices[0..group.max_input_count])) return .{};
    var input_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    for (1..group.max_input_count) |input_i| {
        input_classes[input_i - 1] = try table_core.class_def.value(table, subtable.input_class_def, glyphs[input_indices[input_i]]);
    }

    var lookahead_indices: [max_chaining_class_region_glyphs]usize = undefined;
    var lookahead_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    var lookahead_count: usize = 0;
    var glyph_i = input_indices[group.max_input_count - 1] + 1;
    while (glyph_i < glyphs.len and lookahead_count < group.max_lookahead_count) : (glyph_i += 1) {
        if (runtime.matching.matchSkipsGlyph(lookup_flag, options, glyphs, glyph_i)) continue;
        lookahead_indices[lookahead_count] = glyph_i;
        lookahead_classes[lookahead_count] = try table_core.class_def.value(table, subtable.lookahead_class_def, glyphs[glyph_i]);
        lookahead_count += 1;
    }

    const rules = subtable.rules[group.start .. group.start + group.len];
    for (rules) |rule| {
        if (rule.input_count > group.max_input_count) return error.BadGpos;
        if (rule.input_count == 0) continue;
        if (rule.lookahead_count > group.max_lookahead_count) return error.BadGpos;
        if (rule.lookahead_count > lookahead_count) continue;
        const extra_input_count = @as(usize, rule.input_count) - 1;
        var hash = class_context.sequenceHash(input_classes[0..extra_input_count]);
        for (lookahead_classes[0..rule.lookahead_count]) |class| hash = class_context.sequenceHashAppend(hash, class);
        if (rule.hash != hash) continue;
        const expected_input = subtable.classes[rule.classes_start .. rule.classes_start + extra_input_count];
        if (!std.mem.eql(u16, expected_input, input_classes[0..extra_input_count])) continue;
        const expected_lookahead = subtable.classes[rule.classes_start + extra_input_count .. rule.classes_start + extra_input_count + rule.lookahead_count];
        if (!std.mem.eql(u16, expected_lookahead, lookahead_classes[0..rule.lookahead_count])) continue;

        const matched_inputs = input_indices[0..rule.input_count];
        try markUnsafePositioningChainingContext(
            allocator,
            &options,
            &.{},
            matched_inputs,
            lookahead_indices[0..rule.lookahead_count],
        );
        try collectNestedAdjustment(table, glyphs, matched_inputs[0], rule.lookup_index, adjustments, allocator, options);
        return .{ .matched = true, .next_pos = matched_inputs[matched_inputs.len - 1] + 1 };
    }
    return .{};
}

fn collectPositionRecordsMapped(table: Table, records_pos: usize, record_count: usize, input_indices: []const usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (!table.assume_validated) {
        try ensurePositionRecordsWithin(table, records_pos, record_count, input_indices.len);
        try ensurePositionRecordMarkFilteringSetsValid(table, records_pos, record_count, options);
    }

    // Context positioning records name a glyph in the matched input sequence
    // and a lookup-list index. Nested lookups own their own LookupFlag, so a
    // mark/base/ligature ignored by that nested flag must not receive deltas.
    for (0..record_count) |record_i| {
        const record_offset = records_pos + record_i * 4;
        const sequence_index = try readU16(table, record_offset);
        const lookup_index = try readU16(table, record_offset + 2);
        if (sequence_index >= input_indices.len) return error.BadGpos;
        const target_index = input_indices[sequence_index];
        try collectNestedAdjustment(table, glyphs, target_index, lookup_index, adjustments, allocator, options);
    }
}

fn checkedRequiredPositionOffset(table: Table, base_offset: usize, relative_offset: u16) GposError!usize {
    return table_core.offset.required16(table, base_offset, relative_offset);
}

fn checkedExtensionPositionPayloadOffset(table: Table, extension_offset: usize, relative_offset: u32) GposError!usize {
    return table_core.offset.extensionPayload(table, extension_offset, relative_offset);
}

fn checkedRequiredScriptListOffset(table: Table) GposError!usize {
    // ScriptList is a mandatory top-level OpenType Layout table. Null would
    // reinterpret the GPOS version/header words as script records, so reject it
    // instead of letting selection and validation reason over aliased metadata.
    return checkedRequiredPositionOffset(table, 0, try readU16BadGpos(table, 4));
}

fn checkedRequiredFeatureListOffset(table: Table) GposError!usize {
    // FeatureList is required even when empty. Accepting zero as "no features"
    // would bypass the activation graph and can make callers apply every
    // positioning lookup from an otherwise malformed table.
    return checkedRequiredPositionOffset(table, 0, try readU16BadGpos(table, 6));
}

fn checkedRequiredLookupListOffset(table: Table) GposError!usize {
    // The top-level LookupList offset is mandatory for GPOS. Treating zero as
    // table-relative would reinterpret the GPOS header/version fields as a
    // LookupList and lets malformed fonts pass validation with no real lookup
    // topology or with lookup records derived from unrelated header bytes.
    return checkedRequiredPositionOffset(table, 0, try readU16BadGpos(table, 8));
}

fn checkedRequiredLookupOffset(table: Table, lookup_list_offset: usize, relative_offset: u16) GposError!usize {
    // LookupList offsets are required children. A zero entry aliases the
    // LookupList's count/offset array as a Lookup header and can turn layout
    // directory metadata into positioning operations or mark-filtering state.
    return checkedRequiredPositionOffset(table, lookup_list_offset, relative_offset);
}

fn checkedRequiredCoverageOffset(table: Table, base_offset: usize, relative_offset: u16) GposError!usize {
    // Coverage offsets are mandatory in GPOS subtables and contextual coverage
    // arrays. A null coverage pointer aliases the parent header as Coverage
    // format/count data, which can make malformed positioning silently vanish
    // or bind value records to unrelated layout metadata.
    return checkedRequiredPositionOffset(table, base_offset, relative_offset);
}

fn checkedRequiredClassDefOffset(table: Table, base_offset: usize, relative_offset: u16) GposError!usize {
    // Class-based GPOS subtables use ClassDef offsets as required child tables.
    // A zero offset aliases the subtable header as class data; that can steer
    // PairPos matrices or contextual rule sets from value-format and coverage
    // metadata rather than from an explicit class definition.
    return checkedRequiredPositionOffset(table, base_offset, relative_offset);
}

fn ensureBytesWithin(table: Table, offset: usize, len: usize) GposError!void {
    return table.ensure(offset, len);
}

fn readU16BadGpos(table: Table, relative: usize) GposError!u16 {
    return readU16(table, relative) catch |err| {
        return switch (err) {
            error.EndOfStream => error.BadGpos,
            else => err,
        };
    };
}

fn readU32BadGpos(table: Table, relative: usize) GposError!u32 {
    return readU32(table, relative) catch |err| {
        return switch (err) {
            error.EndOfStream => error.BadGpos,
            else => err,
        };
    };
}

fn collectNestedAdjustment(table: Table, glyphs: []const GlyphId, target_index: usize, lookup_index: u16, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (options.context_depth > max_context_preflight_depth) return error.UnsupportedGpos;
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    if (lookup_index >= lookup_count) return error.BadGpos;
    const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
    const lookup_type = try readU16(table, lookup_offset);
    const lookup_flag = try readU16(table, lookup_offset + 2);
    const subtable_count = try readU16(table, lookup_offset + 4);
    var lookup_options = options;
    if ((lookup_flag & 0x0010) != 0) {
        lookup_options.active_mark_filtering_set = try readU16(table, lookup_offset + 6 + @as(usize, subtable_count) * 2);
        try runtime.matching.validateMarkFilteringSetIndex(lookup_options);
    }
    lookup_options.context_depth = options.context_depth + 1;
    if (lookup_type == 1) {
        if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.single_pos_subtables.len != 0) {
                if (try collectSingleAdjustmentAtAccelerated(table, accelerator.single_pos_subtables, glyphs[target_index], target_index, adjustments, allocator, lookup_flag, lookup_options)) return;
                return;
            }
        }
    }
    if (lookup_type == 8) {
        if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.chaining_coverage_only) {
                _ = try chaining_runtime.coverage.lookup.collectNestedAt(table, lookup_offset, subtable_count, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options, accelerator, collectPositionRecordsMapped, collectNestedAdjustment);
                return;
            }
        }
    }
    if (lookup_type == 9) {
        if (runtime.dispatch.acceleratorWithCoverage(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.chaining_class_subtables.len != 0) {
                _ = try collectNestedExtensionChainingClassPositioningAt(table, subtable_count, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options, accelerator);
                return;
            }
        }
    }
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => if (try collectSingleAdjustmentAt(table, subtable_offset, glyphs[target_index], target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
            2 => if (try collectPairAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
            3 => _ = try collectCursiveAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options),
            4 => _ = try collectMarkToBaseAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options, &.{}),
            5 => _ = try collectMarkToLigatureAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options),
            6 => _ = try collectMarkToMarkAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options),
            7 => if (try context_runtime.collectAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options, collectPositionRecordsMapped)) return,
            8 => if (try collectChainingContextAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
            9 => if (try collectNestedExtensionAdjustment(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
            else => {},
        }
    }
}

fn collectNestedExtensionAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, target_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    const extension_subtable = try checkedExtensionPositionPayloadOffset(table, subtable_offset, try readU32(table, subtable_offset + 4));

    // PosLookupRecord names one glyph in an already-matched input sequence.
    // ExtensionPos only widens the subtable address, so keep using the
    // contextual target index when delegating to the wrapped lookup body.
    switch (extension_lookup_type) {
        // SinglePos subtables inside one lookup are ordered alternatives for a
        // target glyph. Returning the match status here lets the parent lookup
        // stop after the first matching ExtensionPos(SinglePos) wrapper,
        // matching the top-level lookup-level SinglePos collector.
        1 => return try collectSingleAdjustmentAt(table, extension_subtable, glyphs[target_index], target_index, adjustments, allocator, lookup_flag, options),
        // PairPos subtables are ordered alternatives even when the PairPos is
        // reached through ExtensionPos from a PosLookupRecord. Return the
        // wrapped pair match so the containing nested lookup can stop before a
        // later ExtensionPos(PairPos) subtable cascades onto the same pair.
        2 => return try collectPairAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        3 => _ = try collectCursiveAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        4 => _ = try collectMarkToBaseAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options, &.{}),
        5 => _ = try collectMarkToLigatureAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        6 => _ = try collectMarkToMarkAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        7 => return try context_runtime.collectAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options, collectPositionRecordsMapped),
        8 => return try collectChainingContextAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        else => {},
    }
    return false;
}

const Anchor = positioning.anchor.Value;

fn readAnchor(table: Table, anchor_offset: usize, options: LookupOptions) GposError!Anchor {
    return positioning.anchor.read(table, anchor_offset, .{
        .normalized_coords = options.normalized_variation_coords,
        .variation_store = options.gdef_variation_store,
    });
}

test "GPOS chaining group slots preserve hits and misses" {
    const allocator = std.testing.allocator;
    var groups: [accelerator_core.glyph_groups.min_groups_for_hash]ChainingSubtableGroup = undefined;
    var group_indices: [accelerator_core.glyph_groups.min_groups_for_hash][1]u16 = undefined;
    for (&groups, 0..) |*group, i| {
        group_indices[i][0] = @intCast(i);
        group.* = .{
            .glyph = @intCast(13 + i * 19),
            .subtable_indices = &group_indices[i],
        };
    }
    const slots = try accelerator_core.glyph_groups.buildSlots(&groups, allocator);
    defer allocator.free(slots);
    for (groups, 0..) |group, i| {
        const indices = accelerator_core.glyph_groups.find(&groups, slots, group.glyph) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualSlices(u16, &.{@intCast(i)}, indices);
    }
    try std.testing.expect(accelerator_core.glyph_groups.find(&groups, slots, 12) == null);

    const small_groups =
        groups[0 .. accelerator_core.glyph_groups.min_groups_for_hash - 1];
    const small_slots = try accelerator_core.glyph_groups.buildSlots(small_groups, allocator);
    defer allocator.free(small_slots);
    try std.testing.expectEqual(@as(usize, 0), small_slots.len);
    const fallback = accelerator_core.glyph_groups.find(small_groups, small_slots, small_groups[3].glyph) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u16, &group_indices[3], fallback);
}

test "GPOS chaining glyph digest activates only for amortized runs" {
    var digest = GlyphDigest.empty();
    digest.add(20);
    const definite_miss: GlyphId = 21;
    try std.testing.expect(!digest.mayHave(definite_miss));
    try std.testing.expect(!chaining_runtime.coverage.lookup.usesGlyphDigest(15));
    try std.testing.expect(chaining_runtime.coverage.lookup.usesGlyphDigest(16));

    // A digest is approximate: exact group lookup remains authoritative for
    // survivors, while a definite miss can bypass it on an amortized run.
    var collision: ?GlyphId = null;
    var glyph: usize = 0;
    while (glyph <= std.math.maxInt(GlyphId)) : (glyph += 1) {
        const candidate: GlyphId = @intCast(glyph);
        if (candidate != 20 and digest.mayHave(candidate)) {
            collision = candidate;
            break;
        }
    }
    try std.testing.expect(collision != null);
    const groups = [_]ChainingSubtableGroup{
        .{ .glyph = 20, .subtable_indices = &.{0} },
    };
    try std.testing.expect(accelerator_core.glyph_groups.find(&groups, &.{}, collision.?) == null);
}

test "GPOS rejects ExtensionPos payload offsets outside the table during shaping" {
    var bytes = [_]u8{0} ** 8;
    writeU16Test(&bytes, 0, 1); // ExtensionPos format 1.
    writeU16Test(&bytes, 2, 1); // Wrapped SinglePos.
    writeU32Test(&bytes, 4, 0xffff_fffe); // Far beyond this table.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    // This calls the shaping collectors directly, bypassing load-time preflight,
    // so malformed ExtensionPos addresses must be checked at the point where
    // the wrapper is followed rather than leaking as EndOfStream/traps.
    try std.testing.expectError(error.BadGpos, positioning.lookup.dispatch.extensionPayload(table, 0, 1));
    try std.testing.expectError(error.BadGpos, collectExtensionAdjustment(table, 0, &.{5}, &adjustments, std.testing.allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS rejects ExtensionPos payload offsets that alias the wrapper header" {
    var bytes = [_]u8{0} ** 8;
    writeU16Test(&bytes, 0, 1); // ExtensionPos format 1.
    writeU16Test(&bytes, 2, 1); // Wrapped SinglePos.
    writeU32Test(&bytes, 4, 4); // Points into the ExtensionOffset field itself.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    // In-range ExtensionOffset values still have to name child subtable data,
    // not the wrapper's own format/type/offset words.
    try std.testing.expectError(error.BadGpos, positioning.lookup.dispatch.extensionPayload(table, 0, 1));
    try std.testing.expectError(error.BadGpos, positioning.lookup.dispatch.validateExtensionWrapper(table, 0));
    try std.testing.expectError(error.BadGpos, collectExtensionAdjustment(table, 0, &.{5}, &adjustments, std.testing.allocator, 0, .{}));
    try std.testing.expectError(error.BadGpos, collectNestedExtensionAdjustment(table, 0, &.{5}, 0, &adjustments, std.testing.allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS validates AnchorFormat3 device offsets" {
    var bytes = [_]u8{0} ** 18;
    writeU16Test(&bytes, 0, 3); // AnchorFormat3.
    writeI16Test(&bytes, 2, 20);
    writeI16Test(&bytes, 4, -10);
    writeU16Test(&bytes, 6, 10); // XDeviceTable offset.
    writeU16Test(&bytes, 8, 0);
    writeU16Test(&bytes, 10, 12); // startSize.
    writeU16Test(&bytes, 12, 14); // endSize: three 2-bit deltas fit in one word.
    writeU16Test(&bytes, 14, 1); // deltaFormat.
    writeU16Test(&bytes, 16, 0);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try positioning.anchor.validate(table, 0);

    writeU16Test(&bytes, 6, 14); // Points inside an incomplete child DeviceTable.
    try std.testing.expectError(error.BadGpos, positioning.anchor.validate(table, 0));

    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 12, 11); // endSize must not precede startSize.
    try std.testing.expectError(error.BadGpos, positioning.anchor.validate(table, 0));

    writeU16Test(&bytes, 12, 14);
    writeU16Test(&bytes, 14, 4); // Unknown delta formats cannot be sized safely.
    try std.testing.expectError(error.UnsupportedGpos, positioning.anchor.validate(table, 0));

    writeU16Test(&bytes, 14, 0x8000); // VariationIndex table: three uint16 fields only.
    try positioning.anchor.validate(table, 0);
}

test "GPOS AnchorFormat3 resolves GDEF VariationIndex deltas" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16Test(&bytes, 0, 3);
    writeI16Test(&bytes, 2, 20);
    writeI16Test(&bytes, 4, -10);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 16);
    // Two VariationIndex records select ItemVariationData rows 0 and 1.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 0x8000);
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 1);
    writeU16Test(&bytes, 20, 0x8000);

    const store = 24;
    writeU16Test(&bytes, store + 0, 1);
    writeU32Test(&bytes, store + 2, 12);
    writeU16Test(&bytes, store + 6, 1);
    writeU32Test(&bytes, store + 8, 24);
    writeU16Test(&bytes, store + 12, 1);
    writeU16Test(&bytes, store + 14, 1);
    writeI16Test(&bytes, store + 16, 0);
    writeI16Test(&bytes, store + 18, 0x4000);
    writeI16Test(&bytes, store + 20, 0x4000);
    writeU16Test(&bytes, store + 24, 2);
    writeU16Test(&bytes, store + 26, 1);
    writeU16Test(&bytes, store + 28, 1);
    writeU16Test(&bytes, store + 30, 0);
    writeI16Test(&bytes, store + 32, 8);
    writeI16Test(&bytes, store + 34, -6);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(Anchor{ .x = 20, .y = -10 }, try readAnchor(table, 0, .{}));
    const options = LookupOptions{
        .normalized_variation_coords = &.{0.5},
        .gdef_variation_store = .{
            .data = &bytes,
            .table_offset = 0,
            .table_length = bytes.len,
            .store_offset = store,
        },
    };
    try std.testing.expectEqual(Anchor{ .x = 24, .y = -13 }, try readAnchor(table, 0, options));

    // A legal Device table is PPEM-dependent, not a VariationIndex. It remains
    // a zero delta in this font-unit shaping API even when coordinates exist.
    writeU16Test(&bytes, 14, 1);
    try std.testing.expectEqual(Anchor{ .x = 20, .y = -13 }, try readAnchor(table, 0, options));
}

test "GPOS coverage format 2 handles full glyph-space index boundary" {
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

test "GPOS coverage format 2 rejects inconsistent start coverage indexes" {
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
    try std.testing.expectError(error.BadGpos, ensureCoverageTableWithin(table, 0));
    try std.testing.expectError(error.BadGpos, table_core.coverage.index(table, 0, 3));
}

test "GPOS rejects malformed coverage ordering before positioning" {
    var bytes = [_]u8{0} ** 20;
    writeU16Test(&bytes, 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, 2, 10); // Coverage table.
    writeU16Test(&bytes, 4, 0x0004); // ValueFormat: xAdvance.
    writeU16Test(&bytes, 6, 30);
    writeU16Test(&bytes, 10, 1); // Coverage format 1.
    writeU16Test(&bytes, 12, 2);
    writeU16Test(&bytes, 14, 10);
    writeU16Test(&bytes, 16, 5); // Out-of-order; binary search would be unsound.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expectError(error.BadGpos, collectSingleAdjustment(table, 0, &.{10}, &adjustments, std.testing.allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual membership coverage tolerates duplicate glyphs" {
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 1); // Coverage format 1.
    writeU16Test(&bytes, 2, 3);
    writeU16Test(&bytes, 4, 5);
    writeU16Test(&bytes, 6, 5); // Harmless duplicate in a membership-only set.
    writeU16Test(&bytes, 8, 7);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .glyph_count = 8 };
    try table_core.coverage.validate(table, 0, .membership);
    try std.testing.expect(try table_core.coverage.contains(table, 0, 5, .membership));
    try std.testing.expect(!(try table_core.coverage.contains(table, 0, 6, .membership)));
    try std.testing.expect(try table_core.coverage.contains(table, 0, 7, .membership));

    // Indexed consumers still reject duplicate CoverageIndex values because
    // they select parallel arrays and cannot discard an index deterministically.
    try std.testing.expectError(error.BadGpos, ensureCoverageTableWithin(table, 0));
    try std.testing.expectError(error.BadGpos, table_core.coverage.index(table, 0, 5));

    writeU16Test(&bytes, 8, 4);
    try std.testing.expectError(error.BadGpos, table_core.coverage.validate(table, 0, .membership));
    try std.testing.expectError(error.BadGpos, table_core.coverage.contains(table, 0, 5, .membership));
}

test "GPOS rejects reserved ValueFormat bits" {
    var bytes = [_]u8{0} ** 18;
    writeU16Test(&bytes, 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, 2, 8);
    writeU16Test(&bytes, 4, 0x0100); // Reserved ValueFormat bit.
    writeCoverage1Test(&bytes, 8, 5);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.single.validate(table, 0));
}

test "GPOS SinglePos format 2 rejects dangling coverage indexes" {
    var bytes = [_]u8{0} ** 20;
    writeU16Test(&bytes, 0, 2); // SinglePos format 2.
    writeU16Test(&bytes, 2, 12); // Coverage table.
    writeU16Test(&bytes, 4, 0x0004); // ValueFormat: xAdvance.
    writeU16Test(&bytes, 6, 1); // One ValueRecord.
    writeI16Test(&bytes, 8, 40);
    writeU16Test(&bytes, 12, 1); // Coverage format 1.
    writeU16Test(&bytes, 14, 2); // But two covered glyphs need value records.
    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 18, 6);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.single.validate(table, 0));
}

test "GPOS class format 1 handles upper glyph boundary" {
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

test "GPOS cached lookup dispatch requires validated matching metadata" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 0xffff);

    const accelerators = [_]LookupAccelerator{.{
        .lookup_offset = 0,
        .lookup_type = 8,
        .lookup_flag = 0,
        .subtable_count = 4,
        .mark_filtering_set = 7,
    }};
    const cached = try runtime.dispatch.header(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, 0, .{ .lookup_accelerators = &accelerators });
    try std.testing.expectEqual(@as(u16, 8), cached.lookup_type);
    try std.testing.expectEqual(@as(u16, 4), cached.subtable_count);
    try std.testing.expectEqual(@as(?u16, 7), cached.mark_filtering_set);

    const parsed = try runtime.dispatch.header(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, 0, 0, .{ .lookup_accelerators = &accelerators });
    try std.testing.expectEqual(@as(u16, 1), parsed.lookup_type);
    try std.testing.expectEqual(@as(u16, 0x0010), parsed.lookup_flag);
    try std.testing.expectEqual(@as(?u16, 0xffff), parsed.mark_filtering_set);

    var stale = accelerators;
    stale[0].lookup_offset = 2;
    const stale_fallback = try runtime.dispatch.header(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, 0, .{ .lookup_accelerators = &stale });
    try std.testing.expectEqual(@as(u16, 1), stale_fallback.lookup_type);
}

test "GPOS cached ExtensionPos type requires validated matching metadata" {
    var bytes = [_]u8{0} ** 28;
    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);
    writeU16Test(&bytes, 8, 1); // ExtensionPos format.
    writeU16Test(&bytes, 10, 2); // PairPos.
    writeU32Test(&bytes, 12, 8);
    writeU16Test(&bytes, 16, 1); // Minimal PairPos payload header.

    const accelerators = [_]LookupAccelerator{.{
        .lookup_offset = 0,
        .lookup_type = 9,
        .subtable_count = 1,
        .extension_lookup_type = 2,
    }};
    const validated = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    try std.testing.expectEqual(
        @as(?u16, 2),
        try runtime.dispatch.resolvedExtensionType(validated, 0, 9, 1, 0, .{
            .lookup_accelerators = &accelerators,
        }),
    );

    // Mutating the borrowed wrapper proves whether parsing actually occurred.
    // An unvalidated call and a stale header identity must observe the bytes,
    // not the cached type from the original lookup.
    writeU16Test(&bytes, 10, 1);
    const unvalidated = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(?u16, 1),
        try runtime.dispatch.resolvedExtensionType(unvalidated, 0, 9, 1, 0, .{
            .lookup_accelerators = &accelerators,
        }),
    );
    var stale = accelerators;
    stale[0].lookup_offset = 2;
    try std.testing.expectEqual(
        @as(?u16, 1),
        try runtime.dispatch.resolvedExtensionType(validated, 0, 9, 1, 0, .{
            .lookup_accelerators = &stale,
        }),
    );
}

test "GPOS rejects reserved LookupFlag bits" {
    var bytes = [_]u8{0} ** 42;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 38); // Empty ScriptList.
    writeU16Test(&bytes, 6, 40); // Empty FeatureList.
    writeU16Test(&bytes, 8, 10); // LookupList offset.
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeU16Test(&bytes, 14, 1); // SinglePos lookup.
    writeU16Test(&bytes, 16, 0x0020); // Reserved middle-bit range in LookupFlag.
    writeU16Test(&bytes, 18, 1);
    writeU16Test(&bytes, 20, 10); // Leave room for MarkFilteringSet when bit 4 is set.
    const subtable: usize = 24;
    writeU16Test(&bytes, subtable + 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, subtable + 2, 8);
    writeU16Test(&bytes, subtable + 4, 0x0004); // xAdvance.
    writeI16Test(&bytes, subtable + 6, 20);
    writeU16Test(&bytes, subtable + 8, 1); // Coverage format 1.
    writeU16Test(&bytes, subtable + 10, 1);
    writeU16Test(&bytes, subtable + 12, 1);
    writeU16Test(&bytes, 38, 0); // ScriptCount.
    writeU16Test(&bytes, 40, 0); // FeatureCount.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.dispatch.validateHeader(table, 14));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 16, 0xff10); // MarkAttachmentType plus UseMarkFilteringSet are valid.
    writeU16Test(&bytes, 22, 0); // MarkFilteringSet index follows the subtable-offset array.
    try positioning.lookup.dispatch.validateHeader(table, 14);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GPOS rejects null top-level LookupList offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 36); // Empty ScriptList.
    writeU16Test(&bytes, 6, 38); // Empty FeatureList.
    writeU16Test(&bytes, 8, 10); // LookupList offset.
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeSinglePositionLookup(&bytes, 14, 1, 0, 20);
    writeU16Test(&bytes, 36, 0); // ScriptCount.
    writeU16Test(&bytes, 38, 0); // FeatureCount.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    writeU16Test(&bytes, 8, 0); // Invalid: LookupList is a required top-level table.
    try std.testing.expectError(error.BadGpos, checkedRequiredLookupListOffset(table));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGpos, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // With the LookupList restored, the same SinglePos lookup is valid and
    // still applies normally; only the header-aliasing null offset is invalid.
    writeU16Test(&bytes, 8, 10);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    try collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[0].x_placement);
}

test "GPOS rejects null LookupList child offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 38); // Empty ScriptList.
    writeU16Test(&bytes, 6, 40); // Empty FeatureList.
    writeU16Test(&bytes, 8, 10); // LookupList.
    writeU16Test(&bytes, 10, 1); // LookupCount.
    writeU16Test(&bytes, 12, 0); // Invalid: LookupList child offsets are required.

    // Without the required-child check, offset zero aliases the LookupList
    // header as a SinglePos lookup: LookupCount becomes LookupType, the null
    // offset slot becomes LookupFlag, and following words supply a plausible
    // SubTable offset and payload. This keeps the regression focused on the
    // child pointer instead of depending on accidental truncation.
    writeU16Test(&bytes, 14, 1); // Aliased SubTableCount.
    writeU16Test(&bytes, 16, 8); // Aliased SubTable offset: 10 + 8 == 18.
    writeU16Test(&bytes, 18, 1); // SinglePos format 1.
    writeU16Test(&bytes, 20, 8);
    writeU16Test(&bytes, 22, 0x0001); // xPlacement.
    writeI16Test(&bytes, 24, 20);
    writeCoverage1Test(&bytes, 26, 1);
    writeU16Test(&bytes, 38, 0); // ScriptCount.
    writeU16Test(&bytes, 40, 0); // FeatureCount.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, checkedRequiredLookupOffset(table, 10, 0));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // Rebuild the lookup with a non-null child offset. The repaired table keeps
    // the same logical positioning operation and applies normally.
    @memset(&bytes, 0);
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 38);
    writeU16Test(&bytes, 6, 40);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeSinglePositionLookup(&bytes, 14, 1, 0, 20);
    writeU16Test(&bytes, 38, 0);
    writeU16Test(&bytes, 40, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    try collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[0].x_placement);
}

test "GPOS rejects null top-level ScriptList and FeatureList offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 36); // ScriptList.
    writeU16Test(&bytes, 6, 38); // FeatureList.
    writeU16Test(&bytes, 8, 10); // LookupList.
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeSinglePositionLookup(&bytes, 14, 1, 0, 20);
    writeU16Test(&bytes, 36, 0); // Empty ScriptList.
    writeU16Test(&bytes, 38, 0); // Empty FeatureList.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    writeU16Test(&bytes, 4, 0); // Invalid: ScriptList is required, even when empty.
    try std.testing.expectError(error.BadGpos, checkedRequiredScriptListOffset(table));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGpos, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, 4, 36);
    writeU16Test(&bytes, 6, 0); // Invalid: FeatureList is required, even when empty.
    try std.testing.expectError(error.BadGpos, checkedRequiredFeatureListOffset(table));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGpos, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // Non-null empty ScriptList/FeatureList tables are valid. With no selected
    // feature topology, the low-level collector retains the all-lookup fallback
    // and applies this SinglePos adjustment normally.
    writeU16Test(&bytes, 6, 38);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    try collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[0].x_placement);
}

test "GPOS rejects null Lookup SubTable offsets" {
    var bytes = [_]u8{0} ** 42;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 38); // Empty ScriptList.
    writeU16Test(&bytes, 6, 40); // Empty FeatureList.
    writeU16Test(&bytes, 8, 10); // LookupList offset.
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeU16Test(&bytes, 14, 1); // SinglePos lookup.
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 1);
    writeU16Test(&bytes, 20, 0); // Invalid: Lookup.SubTable offsets are required.
    const subtable: usize = 24;
    writeU16Test(&bytes, subtable + 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, subtable + 2, 8);
    writeU16Test(&bytes, subtable + 4, 0x0001); // xPlacement.
    writeI16Test(&bytes, subtable + 6, 20);
    writeCoverage1Test(&bytes, subtable + 8, 1);
    writeU16Test(&bytes, 38, 0); // ScriptCount.
    writeU16Test(&bytes, 40, 0); // FeatureCount.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, ensurePositionLookupSubtablesWithin(table, 14, 1, 1));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    try std.testing.expectError(error.BadGpos, collectLookup(table, 14, &.{1}, &adjustments, std.testing.allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // A non-null child pointer to an otherwise ordinary SinglePos subtable
    // remains valid; only the aliasing null offset is rejected.
    writeU16Test(&bytes, 20, 10);
    try ensurePositionLookupSubtablesWithin(table, 14, 1, 1);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GPOS rejects null required Coverage offsets" {
    var bytes = [_]u8{0} ** 42;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 38); // Empty ScriptList.
    writeU16Test(&bytes, 6, 40); // Empty FeatureList.
    writeU16Test(&bytes, 8, 10); // LookupList offset.
    writeU16Test(&bytes, 10, 1);
    writeU16Test(&bytes, 12, 4);
    writeU16Test(&bytes, 14, 1); // SinglePos lookup.
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 1);
    writeU16Test(&bytes, 20, 10);
    const subtable: usize = 24;
    writeU16Test(&bytes, subtable + 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, subtable + 2, 0); // Invalid: Coverage offsets are required.
    writeU16Test(&bytes, subtable + 4, 0x0001); // xPlacement.
    writeI16Test(&bytes, subtable + 6, 20);
    writeCoverage1Test(&bytes, subtable + 8, 1);
    writeU16Test(&bytes, 38, 0); // ScriptCount.
    writeU16Test(&bytes, 40, 0); // FeatureCount.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.single.validate(table, subtable));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    try std.testing.expectError(error.BadGpos, collectSingleAdjustment(table, subtable, &.{1}, &adjustments, std.testing.allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    try std.testing.expectError(error.BadGpos, collectLookup(table, 14, &.{1}, &adjustments, std.testing.allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // With the Coverage pointer repaired, the same subtable is a normal
    // SinglePos; only the aliasing null child pointer is invalid.
    writeU16Test(&bytes, subtable + 2, 8);
    try positioning.lookup.single.validate(table, subtable);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GPOS validates FeatureList lookup indexes against LookupList" {
    var bytes = [_]u8{0} ** 56;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 54); // Empty ScriptList; this test targets FeatureList topology.
    writeU16Test(&bytes, 6, 10); // FeatureList.
    writeU16Test(&bytes, 8, 24); // LookupList.

    writeU16Test(&bytes, 10, 1); // FeatureCount.
    writeU32Test(&bytes, 12, unicode.tag("kern"));
    writeU16Test(&bytes, 16, 8); // FeatureTable at offset 18.
    writeU16Test(&bytes, 20, 1); // LookupIndexCount.
    writeU16Test(&bytes, 22, 1); // Dangling: LookupList has only index 0.

    writeU16Test(&bytes, 24, 1);
    writeU16Test(&bytes, 26, 4);
    writeSinglePositionLookup(&bytes, 28, 1, 0, 0);
    writeU16Test(&bytes, 54, 0); // ScriptCount.

    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 22, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GPOS validates ScriptList LangSys feature indexes against FeatureList" {
    var bytes = [_]u8{0} ** 86;
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
    writeFeatureRecordTest(&bytes, 42, unicode.tag("kern"), 8);
    writeFeatureTest(&bytes, 50, 0);

    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 4);
    writeSinglePositionLookup(&bytes, 60, 1, 0, 0);

    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 28, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);

    writeU16Test(&bytes, 24, 1); // ReqFeatureIndex is checked too.
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
}

test "GPOS rejects malformed ClassDef format 2 ranges" {
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
    try std.testing.expectError(error.BadGpos, table_core.class_def.value(table, 0, 12));
    const validated_table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true };
    try std.testing.expectEqual(@as(u16, 1), try table_core.class_def.value(validated_table, 0, 12));

    writeU16Test(&bytes, 10, 13); // Repair overlap so the reversed range is checked.
    try std.testing.expectError(error.BadGpos, table_core.class_def.value(table, 0, 18));
}

test "GPOS ContextPos rejects null required rule offsets" {
    var bytes = [_]u8{0} ** 36;
    writeU16Test(&bytes, 8, 12); // LookupList offset for record preflight.
    writeU16Test(&bytes, 12, 0); // Empty LookupList; the repaired rule has no records.

    const rule_set = 20;
    writeU16Test(&bytes, rule_set + 0, 1); // One PosRule offset follows.
    writeU16Test(&bytes, rule_set + 2, 0); // Invalid: PosRule offsets are not nullable.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, ensurePositionRuleSetWithin(table, rule_set, 0));

    // A real rule may still be empty of positioning records; only the child
    // pointer itself must be non-null so the parser reads an actual PosRule.
    const rule = rule_set + 4;
    writeU16Test(&bytes, rule_set + 2, 4);
    writeU16Test(&bytes, rule + 0, 1); // GlyphCount includes the first covered glyph.
    writeU16Test(&bytes, rule + 2, 0); // PosCount.
    try ensurePositionRuleSetWithin(table, rule_set, 0);
}

test "GPOS ChainingContextPos rejects null required rule offsets" {
    var bytes = [_]u8{0} ** 40;
    writeU16Test(&bytes, 8, 12); // LookupList offset for record preflight.
    writeU16Test(&bytes, 12, 0); // Empty LookupList; the repaired rule has no records.

    const rule_set = 20;
    writeU16Test(&bytes, rule_set + 0, 1); // One ChainPosRule offset follows.
    writeU16Test(&bytes, rule_set + 2, 0); // Invalid: ChainPosRule offsets are not nullable.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, ensureChainingPositionRuleSetWithin(table, rule_set, 0));

    // Minimal valid ChainPosRule: no backtrack, one input glyph (the covered
    // glyph), no lookahead, and no positioning records.
    const rule = rule_set + 4;
    writeU16Test(&bytes, rule_set + 2, 4);
    writeU16Test(&bytes, rule + 0, 0); // BacktrackGlyphCount.
    writeU16Test(&bytes, rule + 2, 1); // InputGlyphCount.
    writeU16Test(&bytes, rule + 4, 0); // LookaheadGlyphCount.
    writeU16Test(&bytes, rule + 6, 0); // PosCount.
    try ensureChainingPositionRuleSetWithin(table, rule_set, 0);
}

test "GPOS anchors validate format-specific record sizes" {
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 1);
    writeI16Test(&bytes, 2, 10);
    writeI16Test(&bytes, 4, 20);
    try std.testing.expectEqual(Anchor{ .x = 10, .y = 20 }, try readAnchor(.{ .data = &bytes, .offset = 0, .length = 6 }, 0, .{}));

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 6, 3);
    try std.testing.expectError(error.EndOfStream, readAnchor(.{ .data = &bytes, .offset = 0, .length = 6 }, 0, .{}));
    try std.testing.expectEqual(Anchor{ .x = 10, .y = 20 }, try readAnchor(.{ .data = &bytes, .offset = 0, .length = 8 }, 0, .{}));

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 8, 0);
    try std.testing.expectError(error.EndOfStream, readAnchor(.{ .data = &bytes, .offset = 0, .length = 8 }, 0, .{}));
    try std.testing.expectEqual(Anchor{ .x = 10, .y = 20 }, try readAnchor(.{ .data = &bytes, .offset = 0, .length = 10 }, 0, .{}));
}

test "GPOS scalar reads reject overflowing relative offsets" {
    const bytes = [_]u8{ 0, 1, 2, 3 };
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectError(error.EndOfStream, readU16(table, std.math.maxInt(usize)));
    try std.testing.expectError(error.EndOfStream, readI16(table, std.math.maxInt(usize)));
    try std.testing.expectError(error.EndOfStream, readU32(table, std.math.maxInt(usize)));
}

test "GPOS value records tolerate device and variation offset fields" {
    var bytes = [_]u8{0} ** 32;
    writeI16Test(&bytes, 0, 50);
    writeI16Test(&bytes, 2, -25);
    writeI16Test(&bytes, 4, 30);
    writeI16Test(&bytes, 6, -10);
    writeU16Test(&bytes, 8, 16);
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 22);
    writeU16Test(&bytes, 14, 0);
    writeU16Test(&bytes, 16, 12);
    writeU16Test(&bytes, 18, 12);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 7);
    writeU16Test(&bytes, 24, 3);
    writeU16Test(&bytes, 26, 0x8000);

    const value = try positioning.value_record.read(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, 0x00ff, 0);
    try std.testing.expectEqual(@as(i16, 50), value.x_placement);
    try std.testing.expectEqual(@as(i16, -25), value.y_placement);
    try std.testing.expectEqual(@as(i16, 30), value.x_advance);
    try std.testing.expectEqual(@as(i16, -10), value.y_advance);
}

test "GPOS value records reject overflowing offset plus size" {
    const table = Table{ .data = &.{}, .offset = 0, .length = 8 };

    // The value record itself is small, but callers may hand us an already
    // corrupted absolute table-relative offset. Validate the offset/size pair
    // before reading any field so malformed subtables fail cleanly instead of
    // wrapping `offset + size` in safety builds.
    try std.testing.expectError(error.BadGpos, positioning.value_record.validate(table, std.math.maxInt(usize) - 1, 0x0004, 0));
    try std.testing.expectError(error.BadGpos, positioning.value_record.read(table, std.math.maxInt(usize) - 1, 0x0004, 0));
}

test "GPOS value records validate device offsets against parent base" {
    var bytes = [_]u8{0} ** 22;
    writeU16Test(&bytes, 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, 2, 16); // Coverage table.
    writeU16Test(&bytes, 4, 0x0011); // xPlacement and xPlaDeviceOffset.
    writeI16Test(&bytes, 6, 25);
    writeU16Test(&bytes, 8, 10); // Device offset from SinglePos, not ValueRecord.
    writeU16Test(&bytes, 10, 9); // Truncated Device table when base is correct.
    writeCoverage1Test(&bytes, 16, 5);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.single.validate(table, 0));

    // If the same offset were incorrectly interpreted relative to the
    // ValueRecord at byte 6 it would point into this valid Coverage table.
    // Repairing the parent-relative Device table makes the subtable valid.
    writeU16Test(&bytes, 10, 12);
    writeU16Test(&bytes, 12, 12);
    writeU16Test(&bytes, 14, 1);
    try positioning.lookup.single.validate(table, 0);
}

test "GPOS PairPos format 1 value device offsets use PairSet base" {
    var bytes = [_]u8{0} ** 46;
    writeU16Test(&bytes, 0, 1); // PairPos format 1.
    writeU16Test(&bytes, 2, 22); // Coverage table.
    writeU16Test(&bytes, 4, 0x0011); // First glyph has placement + device.
    writeU16Test(&bytes, 6, 0);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 28); // PairSet.
    writeCoverage1Test(&bytes, 22, 10);
    const pair_set = 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 11);
    writeI16Test(&bytes, pair_set + 4, -30);
    writeU16Test(&bytes, pair_set + 6, 10); // Device offset from PairSet.
    writeU16Test(&bytes, pair_set + 10, 12);
    writeU16Test(&bytes, pair_set + 12, 12);
    writeU16Test(&bytes, pair_set + 14, 1);
    writeU16Test(&bytes, pair_set + 16, 0);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try positioning.lookup.pair.validate(table, 0);

    writeU16Test(&bytes, pair_set + 6, 16); // Points at the Device payload word.
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));
}

test "GPOS PairPos format 1 rejects dangling coverage indexes" {
    var bytes = [_]u8{0} ** 24;
    writeU16Test(&bytes, 0, 1); // PairPos format 1.
    writeU16Test(&bytes, 2, 16); // Coverage table.
    writeU16Test(&bytes, 4, 0); // Empty ValueFormat1.
    writeU16Test(&bytes, 6, 0); // Empty ValueFormat2.
    writeU16Test(&bytes, 8, 1); // One PairSet offset.
    writeU16Test(&bytes, 10, 12);
    writeU16Test(&bytes, 12, 0); // Empty PairSet is structurally valid.
    writeU16Test(&bytes, 16, 1); // Coverage format 1.
    writeU16Test(&bytes, 18, 2); // But two covered first glyphs need PairSet slots.
    writeU16Test(&bytes, 20, 10);
    writeU16Test(&bytes, 22, 20);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));
}

test "GPOS PairPos accelerator ignores unreachable trailing pair sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 30); // Coverage.
    writeU16Test(&bytes, 4, 0x0004); // ValueFormat1: xAdvance.
    writeU16Test(&bytes, 6, 0);
    writeU16Test(&bytes, 8, 2); // Two PairSets, but only index zero is covered.
    writeU16Test(&bytes, 10, 14);
    writeU16Test(&bytes, 12, 22);

    writeU16Test(&bytes, 14, 1);
    writeU16Test(&bytes, 16, 7);
    writeI16Test(&bytes, 18, -30);
    writeU16Test(&bytes, 22, 1);
    writeU16Test(&bytes, 24, 7);
    writeI16Test(&bytes, 26, 200);
    writeCoverage1Test(&bytes, 30, 5);

    var records = std.ArrayList(PairPosRecord).empty;
    defer records.deinit(allocator);
    const accelerator = try accelerator_core.pair.appendFormat1(
        .{ .data = &bytes, .offset = 0, .length = bytes.len },
        0,
        2,
        &records,
        allocator,
    );
    try std.testing.expectEqual(@as(usize, 1), accelerator.record_len);
    try std.testing.expectEqual(PairPosRecord{
        .first = 5,
        .second = 7,
        .x_advance = -30,
    }, records.items[0]);
}

test "GPOS PairPos format 1 rejects null PairSet offsets" {
    var bytes = [_]u8{0} ** 22;
    writeU16Test(&bytes, 0, 1); // PairPos format 1.
    writeU16Test(&bytes, 2, 16); // Coverage table.
    writeU16Test(&bytes, 4, 0); // Empty ValueFormat1.
    writeU16Test(&bytes, 6, 0); // Empty ValueFormat2.
    writeU16Test(&bytes, 8, 1); // One covered first glyph requires one PairSet.
    writeU16Test(&bytes, 10, 0); // Invalid: PairSet offsets are not nullable.
    writeCoverage1Test(&bytes, 16, 10);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));

    // A real, non-null empty PairSet remains valid. The parser must reject
    // only the aliasing offset, not empty pair data.
    writeU16Test(&bytes, 10, 12);
    writeU16Test(&bytes, 12, 0);
    try positioning.lookup.pair.validate(table, 0);
}

test "GPOS PairPos format 1 rejects unsorted PairValue records" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 34;
    writeU16Test(&bytes, 0, 1); // PairPos format 1.
    writeU16Test(&bytes, 2, 22); // Coverage table.
    writeU16Test(&bytes, 4, 0x0004); // ValueFormat1: xAdvance.
    writeU16Test(&bytes, 6, 0); // Empty ValueFormat2.
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 12); // PairSet.

    const pair_set = 12;
    writeU16Test(&bytes, pair_set + 0, 2);
    writeU16Test(&bytes, pair_set + 2, 11);
    writeI16Test(&bytes, pair_set + 4, -20);
    writeU16Test(&bytes, pair_set + 6, 10); // Invalid: SecondGlyph order regresses.
    writeI16Test(&bytes, pair_set + 8, -40);
    writeCoverage1Test(&bytes, 22, 5);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectPairAdjustment(table, 0, &.{ 5, 11 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, pair_set + 6, 12);
    try positioning.lookup.pair.validate(table, 0);
    try collectPairAdjustment(table, 0, &.{ 5, 11 }, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, -20), adjustments.items[0].x_advance);
}

test "GPOS validated PairSet lookup binary searches second glyph records" {
    var bytes = [_]u8{0} ** 18;
    const pair_set = 0;
    writeU16Test(&bytes, pair_set + 0, 3);
    writeU16Test(&bytes, pair_set + 2, 10);
    writeI16Test(&bytes, pair_set + 4, -10);
    writeU16Test(&bytes, pair_set + 6, 12);
    writeI16Test(&bytes, pair_set + 8, -12);
    writeU16Test(&bytes, pair_set + 10, 20);
    writeI16Test(&bytes, pair_set + 12, -20);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true };
    const hit = try positioning.lookup.pair.findAfterProof(table, pair_set, 3, 2, 0, 12) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, pair_set + 6), hit);
    try std.testing.expectEqual(@as(?usize, null), try positioning.lookup.pair.findAfterProof(table, pair_set, 3, 2, 0, 11));
}

test "GPOS simple PairPos accelerator preserves zero adjustment precedence" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    // Lookup with two PairPos alternatives.
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 40);

    // First format-1 subtable explicitly handles (5, 7) with xAdvance=0.
    const first = 10;
    writeU16Test(&bytes, first + 0, 1);
    writeU16Test(&bytes, first + 2, 20);
    writeU16Test(&bytes, first + 4, 0x0004);
    writeU16Test(&bytes, first + 6, 0);
    writeU16Test(&bytes, first + 8, 1);
    writeU16Test(&bytes, first + 10, 12);
    const pair_set = first + 12;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 7);
    writeI16Test(&bytes, pair_set + 4, 0);
    writeCoverage1Test(&bytes, first + 20, 5);

    // Later format-2 fallback would kern the same pair by -40 if precedence is
    // lost. It remains generic in the accelerator.
    const second = 40;
    writeU16Test(&bytes, second + 0, 2);
    writeU16Test(&bytes, second + 2, 24);
    writeU16Test(&bytes, second + 4, 0x0004);
    writeU16Test(&bytes, second + 6, 0);
    writeU16Test(&bytes, second + 8, 30);
    writeU16Test(&bytes, second + 10, 38);
    writeU16Test(&bytes, second + 12, 2);
    writeU16Test(&bytes, second + 14, 2);
    writeI16Test(&bytes, second + 16, 0);
    writeI16Test(&bytes, second + 18, 0);
    writeI16Test(&bytes, second + 20, 0);
    writeI16Test(&bytes, second + 22, -40);
    writeCoverage1Test(&bytes, second + 24, 5);
    writeClassDef1Test(&bytes, second + 30, 5, 1);
    writeClassDef1Test(&bytes, second + 38, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 1), accelerator.pair_pos_records.len);
    try std.testing.expectEqual(@as(i16, 0), accelerator.pair_pos_records[0].x_advance);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{ .lookup_accelerators = &accelerators },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
}

test "GPOS ExtensionPos PairPos accelerator preserves device stride and precedence" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 106;

    // One homogeneous ExtensionPos lookup wrapping two ordered PairPos
    // alternatives.
    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 44);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 20);
    // xAdvance plus a nullable xAdvanceDeviceOffset. The latter makes each
    // ValueRecord four bytes rather than two and exercises predecoded strides.
    writeU16Test(&bytes, first_pair + 4, 0x0044);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 12);
    const first_set = first_pair + 12;
    writeU16Test(&bytes, first_set + 0, 1);
    writeU16Test(&bytes, first_set + 2, 7);
    writeI16Test(&bytes, first_set + 4, 0);
    writeU16Test(&bytes, first_set + 6, 0);
    writeCoverage1Test(&bytes, first_pair + 20, 5);

    const second_extension = 44;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 2);
    writeU16Test(&bytes, second_pair + 2, 32);
    writeU16Test(&bytes, second_pair + 4, 0x0044);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 38);
    writeU16Test(&bytes, second_pair + 10, 46);
    writeU16Test(&bytes, second_pair + 12, 2);
    writeU16Test(&bytes, second_pair + 14, 2);
    // Four class matrix records, each xAdvance followed by a null device
    // offset. The final record would apply -40 to class (1, 1).
    for (0..4) |record_index| {
        writeI16Test(&bytes, second_pair + 16 + record_index * 4, if (record_index == 3) -40 else 0);
        writeU16Test(&bytes, second_pair + 18 + record_index * 4, 0);
    }
    writeCoverage1Test(&bytes, second_pair + 32, 5);
    writeClassDef1Test(&bytes, second_pair + 38, 5, 1);
    writeClassDef1Test(&bytes, second_pair + 46, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expect(accelerator.pair_pos_extension);
    try std.testing.expectEqual(@as(usize, 2), accelerator.pair_pos_subtables.len);
    try std.testing.expectEqual(PairPosAcceleratorKind.format_1_x_advance, accelerator.pair_pos_subtables[0].kind);
    try std.testing.expectEqual(PairPosAcceleratorKind.format_2_dense_x_advance, accelerator.pair_pos_subtables[1].kind);
    const candidates = accelerator_core.glyph_groups.find(
        accelerator.coverage_groups,
        accelerator.coverage_group_slots,
        5,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, candidates);
    try std.testing.expect(accelerator_core.glyph_groups.find(
        accelerator.coverage_groups,
        accelerator.coverage_group_slots,
        6,
    ) == null);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = &accelerators,
            .run_has_default_ignorables = false,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    // The first wrapper explicitly handled this pair with zero adjustment.
    // The later class fallback must not override it with -40.
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
}

test "GPOS adjacent PairPos fast path respects the run default-ignorable proof" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;

    // One xAdvance-only PairPos lookup for glyph pair (5, 7).
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);
    const pair = 8;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 18);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 12);
    writeU16Test(&bytes, pair + 12, 1);
    writeU16Test(&bytes, pair + 14, 7);
    writeI16Test(&bytes, pair + 16, -25);
    writeCoverage1Test(&bytes, pair + 18, 5);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    const accelerators = [_]LookupAccelerator{accelerator};

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = &accelerators,
            .run_has_default_ignorables = false,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -25), adjustments.items[0].x_advance);

    // When the source metadata says a middle glyph is default-ignorable, the
    // same lookup must retain the general skip-aware path and kern across it.
    adjustments.clearRetainingCapacity();
    const sources = [_]usize{ 0, 1, 2 };
    const codepoints = [_]u21{ 'A', 0x034f, 'B' };
    const substituted = [_]bool{ false, false, false };
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 9, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = &accelerators,
            .run_has_default_ignorables = true,
            .run_metadata = &.{
                .glyph_source_indices = &sources,
                .source_codepoints = &codepoints,
                .glyph_substituted = &substituted,
            },
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -25), adjustments.items[0].x_advance);
}

test "GPOS class PairPos accelerator honors coverage and implicit class zero" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    const pair = 0;
    writeU16Test(&bytes, pair + 0, 2);
    writeU16Test(&bytes, pair + 2, 32);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0);
    writeU16Test(&bytes, pair + 8, 38);
    writeU16Test(&bytes, pair + 10, 46);
    writeU16Test(&bytes, pair + 12, 2);
    writeU16Test(&bytes, pair + 14, 2);
    // [class1][class2] xAdvance matrix.
    writeI16Test(&bytes, pair + 16, 0);
    writeI16Test(&bytes, pair + 18, 0);
    writeI16Test(&bytes, pair + 20, -15); // class1=1, implicit class2=0.
    writeI16Test(&bytes, pair + 22, -35); // class1=1, class2=1.
    writeCoverage1Test(&bytes, pair + 32, 5);
    writeClassDef1Test(&bytes, pair + 38, 5, 1);
    writeClassDef1Test(&bytes, pair + 46, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    var records = std.ArrayList(PairPosRecord).empty;
    defer records.deinit(allocator);
    var coverage = std.ArrayList(PairClassEntry).empty;
    defer coverage.deinit(allocator);
    var classes = std.ArrayList(PairClassEntry).empty;
    defer classes.deinit(allocator);
    var matrix = std.ArrayList(i16).empty;
    defer matrix.deinit(allocator);
    const accelerator = try accelerator_core.pair.append(
        table,
        pair,
        &records,
        &coverage,
        &classes,
        &matrix,
        allocator,
    );
    try std.testing.expectEqual(PairPosAcceleratorKind.format_2_dense_x_advance, accelerator.kind);
    try std.testing.expectEqual(@as(usize, 1), coverage.items.len);
    try std.testing.expectEqual(PairClassEntry{ .glyph = 5, .class = 1 }, coverage.items[0]);
    try std.testing.expectEqual(@as(?i16, -35), acceleratedDenseClassPairAdvance(&.{
        .pair_pos_coverage_classes = coverage.items,
        .pair_pos_class_entries = classes.items,
        .pair_pos_class_matrix = matrix.items,
    }, accelerator, 5, 7));
    try std.testing.expectEqual(@as(?i16, -15), acceleratedDenseClassPairAdvance(&.{
        .pair_pos_coverage_classes = coverage.items,
        .pair_pos_class_entries = classes.items,
        .pair_pos_class_matrix = matrix.items,
    }, accelerator, 5, 8));
    try std.testing.expectEqual(@as(?i16, null), acceleratedDenseClassPairAdvance(&.{
        .pair_pos_coverage_classes = coverage.items,
        .pair_pos_class_entries = classes.items,
        .pair_pos_class_matrix = matrix.items,
    }, accelerator, 6, 7));
}

test "GPOS pure class PairPos lookup activates native matrix without format 1 records" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 2); // PairPos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);
    const pair = 8;
    writeU16Test(&bytes, pair + 0, 2);
    writeU16Test(&bytes, pair + 2, 32);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0);
    writeU16Test(&bytes, pair + 8, 38);
    writeU16Test(&bytes, pair + 10, 46);
    writeU16Test(&bytes, pair + 12, 2);
    writeU16Test(&bytes, pair + 14, 2);
    writeI16Test(&bytes, pair + 16, 0);
    writeI16Test(&bytes, pair + 18, 0);
    writeI16Test(&bytes, pair + 20, 0);
    writeI16Test(&bytes, pair + 22, -31);
    writeCoverage1Test(&bytes, pair + 32, 5);
    writeClassDef1Test(&bytes, pair + 38, 5, 1);
    writeClassDef1Test(&bytes, pair + 46, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 0), accelerator.pair_pos_records.len);
    try std.testing.expect(pairPosSubtablesHaveNativeData(accelerator.pair_pos_subtables));
    // Distinguish actual native-matrix dispatch from a generic parser that
    // happens to produce the same result. Public Font shaping would reject
    // this post-proof mutation by checksum; this detached test deliberately
    // mutates only the borrowed matrix after the accelerator copied `-31`.
    writeI16Test(&bytes, pair + 22, 99);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = &accelerators,
            .run_has_default_ignorables = false,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -31), adjustments.items[0].x_advance);
}

test "GPOS dense class PairPos distinguishes coverage holes from class zero" {
    const missing = std.math.maxInt(u16);
    const accelerator = LookupAccelerator{
        .pair_pos_coverage_classes = &.{
            .{ .glyph = 5, .class = 0 },
            .{ .glyph = 6, .class = missing },
            .{ .glyph = 7, .class = 1 },
        },
        .pair_pos_class_entries = &.{
            .{ .glyph = 9, .class = 2 },
            .{ .glyph = 10, .class = 0 },
        },
        // [class1][class2], with three Class2 columns.
        .pair_pos_class_matrix = &.{
            -10, -11, -12,
            -20, -21, -22,
        },
    };
    const subtable = PairPosSubtableAccelerator{
        .kind = .format_2_dense_x_advance,
        .record_start = 5,
        .record_len = 9,
        .coverage_start = 0,
        .coverage_len = 3,
        .class_2_start = 0,
        .class_2_len = 2,
        .class_1_count = 2,
        .class_2_count = 3,
        .matrix_start = 0,
    };

    // Covered class zero is valid, but the explicit sentinel remains a miss.
    try std.testing.expectEqual(@as(?i16, -12), acceleratedDenseClassPairAdvance(&accelerator, subtable, 5, 9));
    try std.testing.expectEqual(@as(?i16, null), acceleratedDenseClassPairAdvance(&accelerator, subtable, 6, 9));
    // A glyph outside the explicit ClassDef2 span uses implicit class zero.
    try std.testing.expectEqual(@as(?i16, -20), acceleratedDenseClassPairAdvance(&accelerator, subtable, 7, 11));
}

test "GPOS dense class PairPos respects its total entry cap" {
    try std.testing.expect(accelerator_core.pair.shouldBuildDense(.{
        .coverage_base = 0,
        .coverage_len = accelerator_core.pair.max_dense_class_entries - 1,
        .class_2_base = 0,
        .class_2_len = 1,
    }));
    try std.testing.expect(!accelerator_core.pair.shouldBuildDense(.{
        .coverage_base = 0,
        .coverage_len = accelerator_core.pair.max_dense_class_entries,
        .class_2_base = 0,
        .class_2_len = 1,
    }));
    try std.testing.expect(!accelerator_core.pair.shouldBuildDense(.{
        .coverage_base = 0,
        .coverage_len = accelerator_core.pair.max_dense_class_entries + 1,
        .class_2_base = 0,
        .class_2_len = 0,
    }));
}

test "GPOS dense class PairPos rejects entries outside endpoint ranges" {
    try std.testing.expect(accelerator_core.pair.denseRanges(
        &.{
            .{ .glyph = 20, .class = 1 },
            .{ .glyph = 5, .class = 0 },
            .{ .glyph = 12, .class = 2 },
        },
        &.{
            .{ .glyph = 100, .class = 1 },
            .{ .glyph = 7, .class = 2 },
        },
    ) == null);

    const ranges = accelerator_core.pair.DenseRanges{
        .coverage_base = 5,
        .coverage_len = 16,
        .class_2_base = 7,
        .class_2_len = 94,
    };
    try std.testing.expect(!accelerator_core.pair.entriesFitDenseRanges(
        &.{
            .{ .glyph = 5, .class = 0 },
            .{ .glyph = 30, .class = 1 },
            .{ .glyph = 20, .class = 2 },
        },
        &.{.{ .glyph = 7, .class = 1 }},
        ranges,
    ));
}

test "GPOS PairPos format 2 rejects class values outside matrix" {
    var bytes = [_]u8{0} ** 40;
    writeU16Test(&bytes, 0, 2); // PairPos format 2.
    writeU16Test(&bytes, 2, 28); // Coverage table.
    writeU16Test(&bytes, 4, 0); // Empty ValueFormat1.
    writeU16Test(&bytes, 6, 0); // Empty ValueFormat2.
    writeU16Test(&bytes, 8, 16); // ClassDef1.
    writeU16Test(&bytes, 10, 24); // ClassDef2.
    writeU16Test(&bytes, 12, 2); // Class1Count: classes 0 and 1 only.
    writeU16Test(&bytes, 14, 1); // Class2Count: class 0 only.

    writeU16Test(&bytes, 16, 1); // ClassDef1 format 1.
    writeU16Test(&bytes, 18, 10);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 2); // Explicit class equals Class1Count: invalid.

    writeU16Test(&bytes, 24, 1); // ClassDef2 format 1, valid class 0.
    writeU16Test(&bytes, 26, 20);
    writeU16Test(&bytes, 28, 1);
    writeU16Test(&bytes, 30, 0);

    writeCoverage1Test(&bytes, 32, 10);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));

    writeU16Test(&bytes, 22, 1);
    try positioning.lookup.pair.validate(table, 0);

    writeU16Test(&bytes, 30, 1); // Now ClassDef2 exceeds Class2Count.
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));
}

test "GPOS contextual class subtables allow covered class indexes outside set arrays" {
    var context_bytes = [_]u8{0} ** 32;
    writeU16Test(&context_bytes, 0, 2); // ContextPos format 2.
    writeU16Test(&context_bytes, 2, 12); // Coverage.
    writeU16Test(&context_bytes, 4, 18); // ClassDef.
    writeU16Test(&context_bytes, 6, 1); // Only class 0 has a PosClassSet slot.
    writeU16Test(&context_bytes, 8, 0); // Nullable class-0 PosClassSet.
    writeCoverage1Test(&context_bytes, 12, 5);
    writeU16Test(&context_bytes, 18, 1); // ClassDef format 1.
    writeU16Test(&context_bytes, 20, 5);
    writeU16Test(&context_bytes, 22, 1);
    writeU16Test(&context_bytes, 24, 1); // Covered glyph indexes past PosClassSetCount.

    var table = Table{ .data = &context_bytes, .offset = 0, .length = context_bytes.len };
    try ensureContextPositionSubtableWithin(table, 0, 0);

    writeU16Test(&context_bytes, 24, 0);
    try ensureContextPositionSubtableWithin(table, 0, 0);

    var chaining_bytes = [_]u8{0} ** 48;
    writeU16Test(&chaining_bytes, 0, 2); // ChainingContextPos format 2.
    writeU16Test(&chaining_bytes, 2, 16); // Coverage.
    writeU16Test(&chaining_bytes, 4, 22); // BacktrackClassDef.
    writeU16Test(&chaining_bytes, 6, 30); // InputClassDef.
    writeU16Test(&chaining_bytes, 8, 38); // LookaheadClassDef.
    writeU16Test(&chaining_bytes, 10, 1); // Only class 0 has a ChainPosClassSet slot.
    writeU16Test(&chaining_bytes, 12, 0); // Nullable class-0 ChainPosClassSet.
    writeCoverage1Test(&chaining_bytes, 16, 5);
    writeU16Test(&chaining_bytes, 22, 1);
    writeU16Test(&chaining_bytes, 24, 0);
    writeU16Test(&chaining_bytes, 26, 1);
    writeU16Test(&chaining_bytes, 28, 0);
    writeU16Test(&chaining_bytes, 30, 1);
    writeU16Test(&chaining_bytes, 32, 5);
    writeU16Test(&chaining_bytes, 34, 1);
    writeU16Test(&chaining_bytes, 36, 1); // Covered input glyph indexes past ChainPosClassSetCount.
    writeU16Test(&chaining_bytes, 38, 1);
    writeU16Test(&chaining_bytes, 40, 0);
    writeU16Test(&chaining_bytes, 42, 1);
    writeU16Test(&chaining_bytes, 44, 0);

    table = .{ .data = &chaining_bytes, .offset = 0, .length = chaining_bytes.len };
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);

    writeU16Test(&chaining_bytes, 36, 0);
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);
}

test "GPOS class-based positioning rejects null ClassDef offsets" {
    const allocator = std.testing.allocator;

    var pair_bytes = [_]u8{0} ** 40;
    writeU16Test(&pair_bytes, 0, 2); // PairPos format 2.
    writeU16Test(&pair_bytes, 2, 34); // Coverage.
    writeU16Test(&pair_bytes, 4, 0x0004); // ValueFormat1: xAdvance.
    writeU16Test(&pair_bytes, 6, 0); // Empty ValueFormat2.
    writeU16Test(&pair_bytes, 8, 0); // Invalid: ClassDef1 offsets are required.
    writeU16Test(&pair_bytes, 10, 26); // ClassDef2.
    writeU16Test(&pair_bytes, 12, 1); // Class1Count.
    writeU16Test(&pair_bytes, 14, 1); // Class2Count.
    writeI16Test(&pair_bytes, 16, -15); // Single matrix ValueRecord.
    writeU16Test(&pair_bytes, 18, 1);
    writeU16Test(&pair_bytes, 20, 10);
    writeU16Test(&pair_bytes, 22, 1);
    writeU16Test(&pair_bytes, 24, 0);
    writeU16Test(&pair_bytes, 26, 1);
    writeU16Test(&pair_bytes, 28, 11);
    writeU16Test(&pair_bytes, 30, 1);
    writeU16Test(&pair_bytes, 32, 0);
    writeCoverage1Test(&pair_bytes, 34, 10);

    var table = Table{ .data = &pair_bytes, .offset = 0, .length = pair_bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectPairAdjustment(table, 0, &.{ 10, 11 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&pair_bytes, 8, 18);
    writeU16Test(&pair_bytes, 10, 0); // ClassDef2 is required too.
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));

    writeU16Test(&pair_bytes, 10, 26);
    try positioning.lookup.pair.validate(table, 0);
    try collectPairAdjustment(table, 0, &.{ 10, 11 }, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -15), adjustments.items[0].x_advance);
    adjustments.clearRetainingCapacity();

    var context_bytes = [_]u8{0} ** 26;
    writeU16Test(&context_bytes, 0, 2); // ContextPos format 2.
    writeU16Test(&context_bytes, 2, 12); // Coverage.
    writeU16Test(&context_bytes, 4, 0); // Invalid: ClassDef offsets are required.
    writeU16Test(&context_bytes, 6, 1); // One nullable PosClassSet slot.
    writeU16Test(&context_bytes, 8, 0);
    writeCoverage1Test(&context_bytes, 12, 5);
    writeU16Test(&context_bytes, 18, 1);
    writeU16Test(&context_bytes, 20, 5);
    writeU16Test(&context_bytes, 22, 1);
    writeU16Test(&context_bytes, 24, 0);

    table = .{ .data = &context_bytes, .offset = 0, .length = context_bytes.len };
    try std.testing.expectError(error.BadGpos, ensureContextPositionSubtableWithin(table, 0, 0));
    try std.testing.expectError(error.BadGpos, context_runtime.collect(table, 0, &.{5}, &adjustments, allocator, 0, .{}, collectPositionRecordsMapped));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&context_bytes, 4, 18);
    try ensureContextPositionSubtableWithin(table, 0, 0);
    try context_runtime.collect(table, 0, &.{5}, &adjustments, allocator, 0, .{}, collectPositionRecordsMapped);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    var chaining_bytes = [_]u8{0} ** 46;
    writeU16Test(&chaining_bytes, 0, 2); // ChainingContextPos format 2.
    writeU16Test(&chaining_bytes, 2, 16); // Coverage.
    writeU16Test(&chaining_bytes, 4, 22); // BacktrackClassDef.
    writeU16Test(&chaining_bytes, 6, 30); // InputClassDef.
    writeU16Test(&chaining_bytes, 8, 38); // LookaheadClassDef.
    writeU16Test(&chaining_bytes, 10, 1); // One nullable ChainPosClassSet slot.
    writeU16Test(&chaining_bytes, 12, 0);
    writeCoverage1Test(&chaining_bytes, 16, 5);
    writeU16Test(&chaining_bytes, 22, 1);
    writeU16Test(&chaining_bytes, 24, 0);
    writeU16Test(&chaining_bytes, 26, 1);
    writeU16Test(&chaining_bytes, 28, 0);
    writeU16Test(&chaining_bytes, 30, 1);
    writeU16Test(&chaining_bytes, 32, 5);
    writeU16Test(&chaining_bytes, 34, 1);
    writeU16Test(&chaining_bytes, 36, 0);
    writeU16Test(&chaining_bytes, 38, 1);
    writeU16Test(&chaining_bytes, 40, 0);
    writeU16Test(&chaining_bytes, 42, 1);
    writeU16Test(&chaining_bytes, 44, 0);

    table = .{ .data = &chaining_bytes, .offset = 0, .length = chaining_bytes.len };
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);

    writeU16Test(&chaining_bytes, 4, 0);
    try std.testing.expectError(error.BadGpos, ensureChainingContextPositionSubtableWithin(table, 0, 0));
    writeU16Test(&chaining_bytes, 4, 22);

    writeU16Test(&chaining_bytes, 6, 0);
    try std.testing.expectError(error.BadGpos, ensureChainingContextPositionSubtableWithin(table, 0, 0));
    try std.testing.expectError(error.BadGpos, collectChainingContextAdjustment(table, 0, &.{5}, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    writeU16Test(&chaining_bytes, 6, 30);

    writeU16Test(&chaining_bytes, 8, 0);
    try std.testing.expectError(error.BadGpos, ensureChainingContextPositionSubtableWithin(table, 0, 0));
    writeU16Test(&chaining_bytes, 8, 38);

    try ensureChainingContextPositionSubtableWithin(table, 0, 0);
    try collectChainingContextAdjustment(table, 0, &.{5}, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS MarkBasePos rejects null required array offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;
    writeU16Test(&bytes, 0, 1); // MarkBasePos format 1.
    writeU16Test(&bytes, 2, 12); // MarkCoverage.
    writeU16Test(&bytes, 4, 18); // BaseCoverage.
    writeU16Test(&bytes, 6, 1); // ClassCount.
    writeU16Test(&bytes, 8, 24); // MarkArray.
    writeU16Test(&bytes, 10, 36); // BaseArray.
    writeCoverage1Test(&bytes, 12, 22);
    writeCoverage1Test(&bytes, 18, 20);

    const mark_array = 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const base_array = 36;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 100, 120);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try positioning.lookup.marks.validateMarkToBase(table, 0);

    writeU16Test(&bytes, 8, 0); // Invalid: MarkArray offsets are not nullable.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToBase(table, 0));
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectMarkToBaseAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, 8, 24);
    writeU16Test(&bytes, 10, 0); // Invalid: BaseArray offsets are not nullable.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToBase(table, 0));

    writeU16Test(&bytes, 10, 36);
    writeU16Test(&bytes, mark_array + 4, 0); // Invalid: MarkRecord anchors are required.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToBase(table, 0));
    try std.testing.expectError(error.BadGpos, collectMarkToBaseAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, mark_array + 4, 6);
    try collectMarkToBaseAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
}

test "GPOS skips direct mark lookups when GDEF classes show no marks" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 56;

    writeU16Test(&bytes, 0, 4); // MarkBasePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_base = 8;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 18);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 24);
    writeU16Test(&bytes, mark_base + 10, 36);
    writeCoverage1Test(&bytes, mark_base + 12, 22);
    writeCoverage1Test(&bytes, mark_base + 18, 20);

    const mark_array = mark_base + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const base_array = mark_base + 36;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 100, 120);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    const glyphs = [_]GlyphId{ 20, 22 };

    var fallback_adjustments = std.ArrayList(Adjustment).empty;
    defer fallback_adjustments.deinit(allocator);
    try collectLookup(table, 0, &glyphs, &fallback_adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), fallback_adjustments.items.len);

    const accelerator = try buildLookupAccelerator(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 1), accelerator.mark_to_base_subtables.len);
    try std.testing.expectEqual(@as(?usize, 0), accelerator.mark_to_base_subtables[0].mark_coverage.?.index(22));
    try std.testing.expectEqual(@as(?usize, 0), accelerator.mark_to_base_subtables[0].base_coverage.?.index(20));

    var accelerated_adjustments = std.ArrayList(Adjustment).empty;
    defer accelerated_adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        0,
        &glyphs,
        &accelerated_adjustments,
        allocator,
        .{ .lookup_accelerators = &accelerators },
        null,
    );
    try std.testing.expectEqualSlices(Adjustment, fallback_adjustments.items, accelerated_adjustments.items);

    var glyph_classes = [_]u16{0} ** 24;
    glyph_classes[20] = 1; // Base.
    glyph_classes[22] = 1; // GDEF says this covered glyph is not a mark.
    var classified_adjustments = std.ArrayList(Adjustment).empty;
    defer classified_adjustments.deinit(allocator);
    try collectLookup(table, 0, &glyphs, &classified_adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expectEqual(@as(usize, 0), classified_adjustments.items.len);

    glyph_classes[22] = 3;
    try collectLookup(table, 0, &glyphs, &classified_adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expectEqual(@as(usize, 1), classified_adjustments.items.len);
}

test "GPOS MarkLigPos rejects null LigatureAttach offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 52;
    writeU16Test(&bytes, 0, 1); // MarkLigPos format 1.
    writeU16Test(&bytes, 2, 12); // MarkCoverage.
    writeU16Test(&bytes, 4, 18); // LigatureCoverage.
    writeU16Test(&bytes, 6, 1); // ClassCount.
    writeU16Test(&bytes, 8, 24); // MarkArray.
    writeU16Test(&bytes, 10, 36); // LigatureArray.
    writeCoverage1Test(&bytes, 12, 22);
    writeCoverage1Test(&bytes, 18, 20);

    const mark_array = 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const ligature_array = 36;
    writeU16Test(&bytes, ligature_array + 0, 1);
    writeU16Test(&bytes, ligature_array + 2, 0); // Invalid: LigatureAttach offsets are not nullable.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    writeU16Test(&bytes, 8, 0); // Invalid: MarkArray offsets are not nullable.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToLigature(table, 0));
    try std.testing.expectError(error.BadGpos, collectMarkToLigatureAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    writeU16Test(&bytes, 8, 24);

    writeU16Test(&bytes, 10, 0); // Invalid: LigatureArray offsets are not nullable.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToLigature(table, 0));
    try std.testing.expectError(error.BadGpos, collectMarkToLigatureAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    writeU16Test(&bytes, 10, 36);

    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToLigature(table, 0));

    // A real LigatureAttach may still omit individual class anchors with null
    // offsets; only the LigatureAttach child pointer itself is mandatory.
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 1);
    writeU16Test(&bytes, ligature_attach + 2, 0);
    try positioning.lookup.marks.validateMarkToLigature(table, 0);

    writeU16Test(&bytes, ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, ligature_attach + 4, 100, 120);
    try positioning.lookup.marks.validateMarkToLigature(table, 0);

    writeU16Test(&bytes, mark_array + 4, 0); // Invalid: MarkRecord anchors are required.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToLigature(table, 0));
    try std.testing.expectError(error.BadGpos, collectMarkToLigatureAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, mark_array + 4, 6);
    try collectMarkToLigatureAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
}

test "GPOS MarkMarkPos rejects null required array offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;
    writeU16Test(&bytes, 0, 1); // MarkMarkPos format 1.
    writeU16Test(&bytes, 2, 12); // Mark1Coverage.
    writeU16Test(&bytes, 4, 18); // Mark2Coverage.
    writeU16Test(&bytes, 6, 1); // ClassCount.
    writeU16Test(&bytes, 8, 24); // Mark1Array.
    writeU16Test(&bytes, 10, 36); // Mark2Array.
    writeCoverage1Test(&bytes, 12, 22);
    writeCoverage1Test(&bytes, 18, 20);

    const mark_1_array = 24;
    writeU16Test(&bytes, mark_1_array + 0, 1);
    writeU16Test(&bytes, mark_1_array + 2, 0);
    writeU16Test(&bytes, mark_1_array + 4, 6);
    writeAnchor1Test(&bytes, mark_1_array + 6, 10, 15);

    const mark_2_array = 36;
    writeU16Test(&bytes, mark_2_array + 0, 1);
    writeU16Test(&bytes, mark_2_array + 2, 4);
    writeAnchor1Test(&bytes, mark_2_array + 4, 50, 70);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try positioning.lookup.marks.validateMarkToMark(table, 0);

    writeU16Test(&bytes, 8, 0); // Invalid: Mark1Array offsets are not nullable.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToMark(table, 0));
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectMarkToMarkAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, 8, 24);
    writeU16Test(&bytes, 10, 0); // Invalid: Mark2Array offsets are not nullable.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToMark(table, 0));

    writeU16Test(&bytes, 10, 36);
    writeU16Test(&bytes, mark_1_array + 4, 0); // Invalid: MarkRecord anchors are required.
    try std.testing.expectError(error.BadGpos, positioning.lookup.marks.validateMarkToMark(table, 0));
    try std.testing.expectError(error.BadGpos, collectMarkToMarkAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, mark_1_array + 4, 6);
    try collectMarkToMarkAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 40), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 55), adjustments.items[0].y_placement);
}

test "GPOS LangSys required feature bypasses feature overrides" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;
    writeRequiredFeatureSelectionTable(&bytes, unicode.tag("kern"), unicode.tag("mark"));
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var lookups = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        // Required features are mandatory LangSys data, while overrides only
        // opt optional/default feature tags in or out.
        .features = &.{
            .{ .tag = unicode.tag("kern"), .enabled = false },
            .{ .tag = unicode.tag("mark"), .enabled = false },
        },
    });
    defer lookups.deinit(allocator);

    try std.testing.expectEqualSlices(u16, &.{0}, lookups.items);
}

test "GPOS lookup selection sorts and deduplicates repeated feature lookups" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 78;
    writeRepeatedLookupSelectionTable(&bytes, unicode.tag("kern"));
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var lookups = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer lookups.deinit(allocator);

    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, lookups.items);
}

test "GPOS default feature selection matches shaping defaults" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 78;
    writeRepeatedLookupSelectionTable(&bytes, unicode.tag("ordn"));
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var default_lookups = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer default_lookups.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), default_lookups.items.len);

    var enabled_lookups = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        .features = &.{.{ .tag = unicode.tag("ordn"), .enabled = true }},
    });
    defer enabled_lookups.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, enabled_lookups.items);
}

test "GPOS lookup selection skips mark positioning for runs without attachment targets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 104;
    writeMarkLookupSelectionTable(&bytes);
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var unmarked = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        .run_may_have_mark_attachments = false,
    });
    defer unmarked.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{0}, unmarked.items);

    var marked = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        .run_may_have_mark_attachments = true,
    });
    defer marked.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1, 2 }, marked.items);
}

test "GPOS validates layout tag record ordering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 92;
    writeLayoutTagOrderingTable(&bytes);
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    var selected = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer selected.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), selected.items.len);

    // Adjacent duplicate ScriptRecords are tolerated and every child remains
    // validated. Runtime selection keeps the first authored record.
    writeU32Test(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    var duplicate = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer duplicate.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), duplicate.items.len);

    // A decreasing tag still violates the searchable ScriptList topology.
    writeU32Test(&bytes, 18, unicode.tag("AAAA"));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGpos, selectedLookupIndices(table, allocator, .{ .script_tag = .dflt }));
    writeU32Test(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));

    writeU32Test(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.ara));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    writeU32Test(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.kor));

    writeU32Test(&bytes, 76, unicode.tag("aalt"));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GPOS cursive attachment skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 2, 0x0008); // IgnoreMarks: transparent marks must not break cursive joins.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const cursive = 8;
    writeU16Test(&bytes, cursive + 0, 1);
    writeU16Test(&bytes, cursive + 2, 14);
    writeU16Test(&bytes, cursive + 4, 2);
    // Glyph 10 contributes only an exit anchor; glyph 12 contributes only an
    // entry anchor. The ignored mark between them should be transparent.
    writeU16Test(&bytes, cursive + 6, 0);
    writeU16Test(&bytes, cursive + 8, 22);
    writeU16Test(&bytes, cursive + 10, 28);
    writeU16Test(&bytes, cursive + 12, 0);
    writeCoverage1ListTest(&bytes, cursive + 14, &.{ 10, 12 });
    writeAnchor1Test(&bytes, cursive + 22, 100, 30);
    writeAnchor1Test(&bytes, cursive + 28, 20, 5);

    const glyphs = [_]GlyphId{ 10, 11, 12 };
    const glyph_classes = [_]u16{0} ** 13;
    var mutable_classes = glyph_classes;
    mutable_classes[11] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &mutable_classes,
    });

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].x_advance_absolute);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -20), adjustments.items[1].x_advance);
    try std.testing.expectEqual(@as(i16, -20), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[1].y_placement);
}

test "GPOS parsed cursive subtable reuses native coverage" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    const cursive = 0;
    writeU16Test(&bytes, cursive + 0, 1);
    writeU16Test(&bytes, cursive + 2, 14);
    writeU16Test(&bytes, cursive + 4, 2);
    writeU16Test(&bytes, cursive + 6, 0);
    writeU16Test(&bytes, cursive + 8, 22);
    writeU16Test(&bytes, cursive + 10, 28);
    writeU16Test(&bytes, cursive + 12, 0);
    writeCoverage1ListTest(&bytes, cursive + 14, &.{ 10, 12 });
    writeAnchor1Test(&bytes, cursive + 22, 100, 30);
    writeAnchor1Test(&bytes, cursive + 28, 20, 5);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true };
    const parsed = try runtime_lookup.cursive.build(
        table,
        cursive,
        allocator,
    );
    defer if (parsed.coverage) |coverage| coverage.deinit(allocator);

    const glyphs = [_]GlyphId{ 10, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try collectCursiveAdjustmentParsed(table, parsed, &glyphs, &adjustments, allocator, 0, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -20), adjustments.items[1].x_advance);
}

test "GPOS cursive attachment skips only unsubstituted default ignorables" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const cursive = 8;
    writeU16Test(&bytes, cursive + 0, 1);
    writeU16Test(&bytes, cursive + 2, 14);
    writeU16Test(&bytes, cursive + 4, 2);
    writeU16Test(&bytes, cursive + 6, 0);
    writeU16Test(&bytes, cursive + 8, 22);
    writeU16Test(&bytes, cursive + 10, 28);
    writeU16Test(&bytes, cursive + 12, 0);
    writeCoverage1ListTest(&bytes, cursive + 14, &.{ 10, 12 });
    writeAnchor1Test(&bytes, cursive + 22, 100, 30);
    writeAnchor1Test(&bytes, cursive + 28, 20, 5);

    const glyphs = [_]GlyphId{ 10, 11, 12 };
    const sources = [_]usize{ 0, 1, 2 };
    const codepoints = [_]u21{ 'A', 0x034f, 'B' };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .run_metadata = &.{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
            .glyph_substituted = &.{ false, false, false },
        },
    });
    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);

    adjustments.clearRetainingCapacity();
    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .run_metadata = &.{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
            .glyph_substituted = &.{ false, true, false },
        },
    });
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS mark-to-base stops at intervening non-covered base" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 4);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_base = 8;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 18);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 24);
    writeU16Test(&bytes, mark_base + 10, 38);

    writeCoverage1Test(&bytes, mark_base + 12, 12);
    writeCoverage1Test(&bytes, mark_base + 18, 10);

    const mark_array = mark_base + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 8);
    writeAnchor1Test(&bytes, mark_array + 8, 0, 0);

    const base_array = mark_base + 38;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 100, 120);

    const glyphs = [_]GlyphId{ 10, 11, 12 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[10] = 1;
    glyph_classes[11] = 1;
    glyph_classes[12] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS mark-to-base cached search keeps attached marks transparent" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 88;

    writeU16Test(&bytes, 0, 4);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_base = 8;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 20);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 26);
    writeU16Test(&bytes, mark_base + 10, 50);

    writeCoverage1ListTest(&bytes, mark_base + 12, &.{ 12, 13 });
    writeCoverage1Test(&bytes, mark_base + 20, 10);

    const mark_array = mark_base + 26;
    writeU16Test(&bytes, mark_array + 0, 2);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 10);
    writeU16Test(&bytes, mark_array + 6, 0);
    writeU16Test(&bytes, mark_array + 8, 16);
    writeAnchor1Test(&bytes, mark_array + 10, 10, 15);
    writeAnchor1Test(&bytes, mark_array + 16, 30, 35);

    const base_array = mark_base + 50;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 100, 120);

    const glyphs = [_]GlyphId{ 10, 12, 13 };
    var glyph_classes = [_]u16{0} ** 14;
    glyph_classes[10] = 1;
    glyph_classes[12] = 3;
    glyph_classes[13] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[1].index);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[1].attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, 85), adjustments.items[1].y_placement);
}

test "GPOS MarkAttachmentType uses MarkAttachClassDef without glyph classes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 26;

    writeSinglePositionLookup(&bytes, 0, 5, 0x0100, 33); // MarkAttachmentType 1.
    writeU16Test(&bytes, 16, 1);
    writeU16Test(&bytes, 18, 2);
    writeU16Test(&bytes, 20, 5);
    writeU16Test(&bytes, 22, 8);

    const glyphs = [_]GlyphId{ 5, 7, 8 };
    var mark_attach_classes = [_]u16{0} ** 9;
    mark_attach_classes[5] = 2;
    mark_attach_classes[7] = 1;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_attach_classes = &mark_attach_classes,
    });

    // Non-zero MarkAttachClassDef entries identify marks even when GlyphClassDef
    // is absent or incomplete. Glyph 5 is a mark of the wrong attachment type,
    // so the covered SinglePos adjustment must not apply to it. Glyph 8 has no
    // attachment class and still participates as an ordinary glyph.
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

test "GPOS lookup flags honor GDEF mark filtering sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 1); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 33);
    writeCoverage1Test(&bytes, single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{7}, &.{5} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);

    // Exercise the cached dispatch path used after Font validation.
    adjustments.clearRetainingCapacity();
    const accelerator = try buildLookupAccelerator(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        0,
        &glyphs,
        &adjustments,
        allocator,
        .{
            .mark_filtering_sets = &mark_sets,
            .lookup_accelerators = &accelerators,
            .assume_validated = true,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

test "GPOS rejects missing GDEF mark filtering set indexes during shaping" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 1); // Invalid: only set 0 is supplied below.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 33);
    writeCoverage1Test(&bytes, single + 8, 5);

    const glyphs = [_]GlyphId{5};
    const mark_sets = [_][]const GlyphId{&.{5}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    // The MarkFilteringSet field is a direct index into GDEF MarkGlyphSetsDef.
    // Once those sets are available, accepting an out-of-range index would
    // turn malformed positioning into a silent no-op or a glyph-class fallback.
    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    }));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS lookup flags combine mark filtering set and attachment type" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 28;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0210); // MarkAttachmentType 2 + UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 0); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 41);
    writeCoverage1ListTest(&bytes, single + 8, &.{ 5, 7 });

    const glyphs = [_]GlyphId{ 5, 7 };
    var glyph_classes = [_]u16{0} ** 8;
    glyph_classes[5] = 3;
    glyph_classes[7] = 3;
    var mark_attach_classes = [_]u16{0} ** 8;
    mark_attach_classes[5] = 1;
    mark_attach_classes[7] = 2;
    const mark_sets = [_][]const GlyphId{&.{ 5, 7 }};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 41), adjustments.items[0].x_placement);
}

test "GPOS context nested lookup honors nested lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 74;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 18, 0);
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

    writeCoverage1Test(&bytes, context + 22, 1);
    writeSinglePositionLookup(&bytes, 52, 2, 0x0008, 50);

    const glyphs = [_]GlyphId{ 1, 2 };
    const glyph_classes = [_]u16{ 0, 1, 3 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual record truncation is atomic" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 14);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 28);

    writeSinglePositionLookup(&bytes, 24, 1, 0, 40);

    const context = 44;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1Test(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    // The second declared PosLookupRecord is beyond table.length below.

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    const table = Table{ .data = &bytes, .offset = 0, .length = rule + 8 };
    try std.testing.expectError(error.BadGpos, collectLookup(table, 16, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual lookup preflight rejects later truncated lookup atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
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
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    // Lookup 2 is referenced only after lookup 1 would append an adjustment.
    // Its truncated SubTable offset array must be caught before collecting any
    // nested result from the contextual match.
    writeU16Test(&bytes, 90, 1);
    writeU16Test(&bytes, 94, 1);

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual lookup preflight rejects missing nested mark filtering sets atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18); // Lookup 0: ContextPos.
    writeU16Test(&bytes, 14, 60); // Lookup 1: valid SinglePos.
    writeU16Test(&bytes, 16, 84); // Lookup 2: SinglePos with a bad MarkFilteringSet index.

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
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
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    const bad_lookup = 94;
    writeU16Test(&bytes, bad_lookup + 0, 1);
    writeU16Test(&bytes, bad_lookup + 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, bad_lookup + 4, 1);
    writeU16Test(&bytes, bad_lookup + 6, 10);
    writeU16Test(&bytes, bad_lookup + 8, 1); // Invalid: only set 0 is supplied below.
    const single = bad_lookup + 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 33);
    writeCoverage1Test(&bytes, single + 8, 1);

    const glyphs = [_]GlyphId{1};
    const mark_sets = [_][]const GlyphId{&.{1}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    }));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual lookup records reject dangling lookup indexes atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 94;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0: ContextPos.
    writeU16Test(&bytes, 18, 50); // Lookup 1: SinglePos.

    const context_lookup = 20;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1Test(&bytes, context + 8, 1);

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

    writeSinglePositionLookup(&bytes, 64, 1, 0, 45);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 20));
    try std.testing.expectError(error.BadGpos, collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // With every PosLookupRecord targeting an existing lookup, the context
    // preflight succeeds and both nested SinglePos adjustments are visible.
    writeU16Test(&bytes, rule + 10, 1);
    try validateGlyphBounds(&bytes, 0, bytes.len, 20);
    try collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
}

test "GPOS contextual lookup records reject sequence indexes outside matched input" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 88;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0: ContextPos.
    writeU16Test(&bytes, 18, 50); // Lookup 1: SinglePos.

    const context_lookup = 20;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1Test(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1); // One input glyph is matched.
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 1); // Invalid: only sequence index 0 exists.
    writeU16Test(&bytes, rule + 6, 1);

    writeSinglePositionLookup(&bytes, 64, 1, 0, 45);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 20));
    try std.testing.expectError(error.BadGpos, collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // With a valid SequenceIndex, the same context applies its nested SinglePos
    // and appends a real adjustment for the matched glyph.
    writeU16Test(&bytes, rule + 4, 0);
    try validateGlyphBounds(&bytes, 0, bytes.len, 20);
    try collectLookup(table, context_lookup, &glyphs, &adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 45), adjustments.items[0].x_placement);
}

test "GPOS contextual lookup preflight rejects nested extension payload atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
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
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    writeU16Test(&bytes, 90, 9);
    writeU16Test(&bytes, 94, 1);
    writeU16Test(&bytes, 96, 8);
    const extension = 98;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    // The ExtensionPos wrapper header is present, but its wrapped SinglePos
    // payload is outside this table. Reject the whole contextual match before
    // the preceding record appends its adjustment.
    writeU32Test(&bytes, extension + 4, 20);

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS extension single positioning preflights wrapped value arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 60;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 32);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 45);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_extension = 32;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 2);
    writeU16Test(&bytes, second_single + 2, 14);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeU16Test(&bytes, second_single + 6, 7);
    writeCoverage1Test(&bytes, second_single + 14, 30);
    // The second wrapped SinglePos declares seven value records, extending past
    // table.length. Reject the whole ExtensionPos lookup before the first
    // wrapper appends its otherwise valid adjustment for glyph 10.

    const glyphs = [_]GlyphId{ 10, 30 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct single positioning preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 46;

    writeU16Test(&bytes, 0, 1); // SinglePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 26);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 45);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_single = 26;
    writeU16Test(&bytes, second_single + 0, 2);
    writeU16Test(&bytes, second_single + 2, 14);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeU16Test(&bytes, second_single + 6, 7);
    writeCoverage1Test(&bytes, second_single + 14, 30);
    // The second SinglePos subtable declares seven ValueRecords, extending past
    // table.length. Reject the lookup before collecting the first subtable's
    // otherwise valid xAdvance adjustment.

    const glyphs = [_]GlyphId{ 10, 30 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct cursive positioning preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 58;

    writeU16Test(&bytes, 0, 3); // CursivePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 46);

    const first_cursive = 10;
    writeU16Test(&bytes, first_cursive + 0, 1);
    writeU16Test(&bytes, first_cursive + 2, 14);
    writeU16Test(&bytes, first_cursive + 4, 2);
    writeU16Test(&bytes, first_cursive + 6, 0);
    writeU16Test(&bytes, first_cursive + 8, 22);
    writeU16Test(&bytes, first_cursive + 10, 28);
    writeU16Test(&bytes, first_cursive + 12, 0);
    writeCoverage1ListTest(&bytes, first_cursive + 14, &.{ 10, 11 });
    writeAnchor1Test(&bytes, first_cursive + 22, 100, 50);
    writeAnchor1Test(&bytes, first_cursive + 28, 20, 10);

    const second_cursive = 46;
    writeU16Test(&bytes, second_cursive + 0, 1);
    writeU16Test(&bytes, second_cursive + 2, 6);
    writeU16Test(&bytes, second_cursive + 4, 1);
    writeU16Test(&bytes, second_cursive + 6, 1); // Truncated Coverage format 1.
    writeU16Test(&bytes, second_cursive + 8, 2);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct mark-to-base positioning preflights anchor arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU16Test(&bytes, 0, 4); // MarkBasePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 58);

    const first_mark_base = 10;
    writeU16Test(&bytes, first_mark_base + 0, 1);
    writeU16Test(&bytes, first_mark_base + 2, 12);
    writeU16Test(&bytes, first_mark_base + 4, 18);
    writeU16Test(&bytes, first_mark_base + 6, 1);
    writeU16Test(&bytes, first_mark_base + 8, 24);
    writeU16Test(&bytes, first_mark_base + 10, 36);
    writeCoverage1Test(&bytes, first_mark_base + 12, 2);
    writeCoverage1Test(&bytes, first_mark_base + 18, 1);
    const first_mark_array = first_mark_base + 24;
    writeU16Test(&bytes, first_mark_array + 0, 1);
    writeU16Test(&bytes, first_mark_array + 2, 0);
    writeU16Test(&bytes, first_mark_array + 4, 6);
    writeAnchor1Test(&bytes, first_mark_array + 6, 20, 30);
    const first_base_array = first_mark_base + 36;
    writeU16Test(&bytes, first_base_array + 0, 1);
    writeU16Test(&bytes, first_base_array + 2, 4);
    writeAnchor1Test(&bytes, first_base_array + 4, 100, 100);

    const second_mark_base = 58;
    writeU16Test(&bytes, second_mark_base + 0, 1);
    writeU16Test(&bytes, second_mark_base + 2, 12);
    writeU16Test(&bytes, second_mark_base + 4, 18);
    writeU16Test(&bytes, second_mark_base + 6, 1);
    writeU16Test(&bytes, second_mark_base + 8, 24);
    writeU16Test(&bytes, second_mark_base + 10, 30);
    writeCoverage1Test(&bytes, second_mark_base + 12, 2);
    writeCoverage1Test(&bytes, second_mark_base + 18, 1);
    const second_mark_array = second_mark_base + 24;
    writeU16Test(&bytes, second_mark_array + 0, 1);
    writeU16Test(&bytes, second_mark_array + 2, 0);
    writeU16Test(&bytes, second_mark_array + 4, 8); // Anchor starts exactly at table.length.

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS context lookup preflights later malformed subtable atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6); // Lookup 0: ContextPos with two subtables.
    writeU16Test(&bytes, 14, 30); // Lookup 1: nested SinglePos.

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 2);
    writeU16Test(&bytes, 22, 48);
    writeU16Test(&bytes, 24, 80);
    writeSinglePositionLookup(&bytes, 40, 5, 0, 33);

    const first_context = 64;
    writeU16Test(&bytes, first_context + 0, 1);
    writeU16Test(&bytes, first_context + 2, 22);
    writeU16Test(&bytes, first_context + 4, 1);
    writeU16Test(&bytes, first_context + 6, 8);
    writeU16Test(&bytes, first_context + 8, 1);
    writeU16Test(&bytes, first_context + 10, 4);
    writeU16Test(&bytes, first_context + 12, 1);
    writeU16Test(&bytes, first_context + 14, 1);
    writeU16Test(&bytes, first_context + 16, 0);
    writeU16Test(&bytes, first_context + 18, 1);
    writeCoverage1Test(&bytes, first_context + 22, 5);

    const malformed_context = 96;
    writeU16Test(&bytes, malformed_context + 0, 1);
    writeU16Test(&bytes, malformed_context + 2, 16);
    writeU16Test(&bytes, malformed_context + 4, 1);
    writeU16Test(&bytes, malformed_context + 6, 24);
    writeCoverage1Test(&bytes, malformed_context + 16, 5);
    writeU16Test(&bytes, malformed_context + 24, 1);
    writeU16Test(&bytes, malformed_context + 26, 4);
    writeU16Test(&bytes, malformed_context + 28, 1);
    writeU16Test(&bytes, malformed_context + 30, 2);
    writeU16Test(&bytes, malformed_context + 32, 0);
    writeU16Test(&bytes, malformed_context + 34, 1);
    // The second declared PosLookupRecord begins exactly at table.length below.

    const glyphs = [_]GlyphId{5};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = 132 }, 16, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS context nested lookup can apply pair positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    // PosLookupRecord sequenceIndex=0 intentionally invokes PairPos on the
    // first glyph of the matched input. The nested lookup must still inspect
    // the following glyph in the real run and produce both pair adjustments.
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 1);

    writeU16Test(&bytes, 52, 2);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const pair = 60;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0x0001);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 1);
    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 2);
    writeI16Test(&bytes, pair_set + 4, -50);
    writeI16Test(&bytes, pair_set + 6, 20);

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[1].x_placement);
}

test "GPOS context nested lookup can apply cursive positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 124;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 22);
    // The PosLookupRecord targets sequenceIndex 1. A nested CursivePos must
    // use glyph 20 as the previous cursive glyph, while leaving the unrelated
    // earlier 10-12 join untouched.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 20);

    writeU16Test(&bytes, 52, 3);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const cursive = 60;
    writeU16Test(&bytes, cursive + 0, 1);
    writeU16Test(&bytes, cursive + 2, 22);
    writeU16Test(&bytes, cursive + 4, 4);
    writeU16Test(&bytes, cursive + 6, 0);
    writeU16Test(&bytes, cursive + 8, 34);
    writeU16Test(&bytes, cursive + 10, 40);
    writeU16Test(&bytes, cursive + 12, 0);
    writeU16Test(&bytes, cursive + 14, 0);
    writeU16Test(&bytes, cursive + 16, 46);
    writeU16Test(&bytes, cursive + 18, 52);
    writeU16Test(&bytes, cursive + 20, 0);
    writeCoverage1ListTest(&bytes, cursive + 22, &.{ 10, 12, 20, 22 });
    writeAnchor1Test(&bytes, cursive + 34, 100, 30);
    writeAnchor1Test(&bytes, cursive + 40, 20, 5);
    writeAnchor1Test(&bytes, cursive + 46, 200, 70);
    writeAnchor1Test(&bytes, cursive + 52, 50, 10);

    const glyphs = [_]GlyphId{ 10, 12, 20, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 200), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].x_advance_absolute);
    try std.testing.expectEqual(@as(usize, 3), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[1].x_advance);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, 60), adjustments.items[1].y_placement);
}

test "GPOS single positioning subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 24);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 20);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_single = 24;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeI16Test(&bytes, second_single + 6, 30);
    writeCoverage1Test(&bytes, second_single + 8, 10);

    const glyphs = [_]GlyphId{10};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    // Lookup subtables are ordered alternatives. The second overlapping
    // SinglePos subtable must not add another xPlacement after the first match.
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[0].x_placement);
}

test "GPOS pair positioning records precedence when first value is empty" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const pair = 8;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0000); // Empty valueFormat1 is common when only the second glyph moves.
    writeU16Test(&bytes, pair + 6, 0x0001);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 10);

    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 11);
    writeI16Test(&bytes, pair_set + 4, 25);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[1].x_placement);
}

test "GPOS PairPos second ValueRecord consumes overlapping second glyph" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const pair = 8;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0001); // First glyph xPlacement.
    writeU16Test(&bytes, pair + 6, 0x0002); // Second glyph yPlacement.
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 18);

    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 18);
    writeI16Test(&bytes, pair_set + 4, -100);
    writeI16Test(&bytes, pair_set + 6, -100);

    const glyphs = [_]GlyphId{ 18, 18, 18, 18 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 4), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[1].y_placement);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[2].x_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[2].y_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[3].x_placement);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[3].y_placement);
}

test "GPOS pair positioning subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 44);

    const first_pair = 10;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const second_pair = 44;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // Subtables in a lookup are alternatives. The first matching PairPos
    // subtable wins for this pair; the later matching subtable must not add its
    // xAdvance on top.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS context nested lookup can apply extension positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 1);
    // PosLookupRecord invokes lookup 1, an ExtensionPos wrapping SinglePos, at
    // sequenceIndex 0. Nested extension handling must preserve the context
    // target index rather than ignoring the lookup or applying it globally.
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeCoverage1Test(&bytes, context + 22, 3);

    writeU16Test(&bytes, 52, 9);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const extension = 60;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    writeU32Test(&bytes, extension + 4, 8);
    const single = extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0004);
    writeI16Test(&bytes, single + 6, 70);
    writeCoverage1Test(&bytes, single + 8, 3);

    const glyphs = [_]GlyphId{3};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_advance);
}

test "GPOS accelerates nested extension chaining class positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 142;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0.
    writeU16Test(&bytes, 18, 106); // Lookup 1.

    const extension_lookup = 20;
    writeU16Test(&bytes, extension_lookup + 0, 9); // ExtensionPos.
    writeU16Test(&bytes, extension_lookup + 2, 0);
    writeU16Test(&bytes, extension_lookup + 4, 1);
    writeU16Test(&bytes, extension_lookup + 6, 8);

    const extension = 28;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 8); // ChainContextPos.
    writeU32Test(&bytes, extension + 4, 8);

    const chain = 36;
    writeU16Test(&bytes, chain + 0, 2); // Chaining class format.
    writeU16Test(&bytes, chain + 2, 50); // Coverage.
    writeU16Test(&bytes, chain + 4, 56); // Empty backtrack ClassDef.
    writeU16Test(&bytes, chain + 6, 62); // Input ClassDef.
    writeU16Test(&bytes, chain + 8, 70); // Lookahead ClassDef.
    writeU16Test(&bytes, chain + 10, 2);
    writeU16Test(&bytes, chain + 12, 0);
    writeU16Test(&bytes, chain + 14, 16); // Class 1 rule set.

    const set = chain + 16;
    writeU16Test(&bytes, set + 0, 2);
    writeU16Test(&bytes, set + 2, 6);
    writeU16Test(&bytes, set + 4, 20);
    const first_rule = set + 6;
    writeU16Test(&bytes, first_rule + 0, 0); // BacktrackCount.
    writeU16Test(&bytes, first_rule + 2, 1); // InputCount.
    writeU16Test(&bytes, first_rule + 4, 1); // LookaheadCount.
    writeU16Test(&bytes, first_rule + 6, 3); // Non-matching lookahead class.
    writeU16Test(&bytes, first_rule + 8, 1);
    writeU16Test(&bytes, first_rule + 10, 0);
    writeU16Test(&bytes, first_rule + 12, 1);
    const second_rule = set + 20;
    writeU16Test(&bytes, second_rule + 0, 0);
    writeU16Test(&bytes, second_rule + 2, 1);
    writeU16Test(&bytes, second_rule + 4, 1);
    writeU16Test(&bytes, second_rule + 6, 2); // Matching lookahead class.
    writeU16Test(&bytes, second_rule + 8, 1);
    writeU16Test(&bytes, second_rule + 10, 0);
    writeU16Test(&bytes, second_rule + 12, 1);

    writeCoverage1Test(&bytes, chain + 50, 10);
    writeU16Test(&bytes, chain + 56, 1); // Empty ClassDef format 1.
    writeU16Test(&bytes, chain + 58, 0);
    writeU16Test(&bytes, chain + 60, 0);
    writeClassDef1Test(&bytes, chain + 62, 10, 1);
    writeClassDef1Test(&bytes, chain + 70, 20, 2);

    writeSinglePositionLookup(&bytes, 120, 10, 0, 50);

    const glyphs = [_]GlyphId{ 10, 20 };
    const accelerators = try buildLookupAccelerators(&bytes, 0, bytes.len, allocator);
    defer deinitLookupAccelerators(allocator, accelerators);
    try std.testing.expect(accelerators[0].chaining_class_subtables.len != 0);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try collectNestedAdjustment(.{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true }, &glyphs, 0, 0, &adjustments, allocator, .{
        .lookup_accelerators = accelerators,
        .assume_validated = true,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 50), adjustments.items[0].x_placement);
}

test "GPOS chaining coverage nested ExtensionPos SinglePos respects alternatives" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 70);

    writeU16Test(&bytes, 16, 8);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const chaining = 24;
    writeU16Test(&bytes, chaining + 0, 3);
    writeU16Test(&bytes, chaining + 2, 1);
    writeU16Test(&bytes, chaining + 4, 24);
    writeU16Test(&bytes, chaining + 6, 2);
    writeU16Test(&bytes, chaining + 8, 30);
    writeU16Test(&bytes, chaining + 10, 36);
    writeU16Test(&bytes, chaining + 12, 1);
    writeU16Test(&bytes, chaining + 14, 42);
    writeU16Test(&bytes, chaining + 16, 1);
    // Match [10, 11] only when preceded by 7 and followed by 12, then apply
    // lookup 1 to input sequenceIndex 1. The nested lookup contains two
    // ExtensionPos(SinglePos) subtables for glyph 11; the first matching
    // wrapper must win instead of cascading both SinglePos adjustments.
    writeU16Test(&bytes, chaining + 18, 1);
    writeU16Test(&bytes, chaining + 20, 1);
    writeCoverage1Test(&bytes, chaining + 24, 7);
    writeCoverage1Test(&bytes, chaining + 30, 10);
    writeCoverage1Test(&bytes, chaining + 36, 11);
    writeCoverage1Test(&bytes, chaining + 42, 12);

    writeU16Test(&bytes, 80, 9);
    writeU16Test(&bytes, 84, 2);
    writeU16Test(&bytes, 86, 10);
    writeU16Test(&bytes, 88, 32);

    const first_extension = 90;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0004);
    writeI16Test(&bytes, first_single + 6, 40);
    writeCoverage1Test(&bytes, first_single + 8, 11);

    const second_extension = 112;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0004);
    writeI16Test(&bytes, second_single + 6, 90);
    writeCoverage1Test(&bytes, second_single + 8, 11);

    const glyphs = [_]GlyphId{ 7, 10, 11, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 40), adjustments.items[0].x_advance);
}

test "GPOS context nested ExtensionPos PairPos respects alternatives with mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 170;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 54);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 18, 0x0010);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 10);
    writeU16Test(&bytes, 24, 0);

    const context = 26;
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
    writeU16Test(&bytes, rule + 4, 11);
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 64, 9);
    writeU16Test(&bytes, 66, 0x0010);
    writeU16Test(&bytes, 68, 2);
    writeU16Test(&bytes, 70, 12);
    writeU16Test(&bytes, 72, 56);
    writeU16Test(&bytes, 74, 0);

    const first_extension = 76;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const second_extension = 120;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The unselected mark is transparent for both the outer ContextPos match
    // and the wrapped PairPos lookup. Once the first ExtensionPos(PairPos)
    // subtable matches that filtered pair, the second wrapper in the same
    // lookup must remain an alternative rather than adding another adjustment.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS nested chaining context can recurse into PairPos" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 220;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 4);
    writeU16Test(&bytes, 12, 10); // Lookup 0: outer ChainContextPos.
    writeU16Test(&bytes, 14, 50); // Lookup 1: ExtensionPos(ChainContextPos).
    writeU16Test(&bytes, 16, 110); // Lookup 2: ChainContextPos.
    writeU16Test(&bytes, 18, 160); // Lookup 3: PairPos.

    writeU16Test(&bytes, 20, 8);
    writeU16Test(&bytes, 22, 0);
    writeU16Test(&bytes, 24, 1);
    writeU16Test(&bytes, 26, 8);
    const outer = 28;
    writeU16Test(&bytes, outer + 0, 3);
    writeU16Test(&bytes, outer + 2, 0); // BacktrackCount.
    writeU16Test(&bytes, outer + 4, 1); // InputGlyphCount.
    writeU16Test(&bytes, outer + 6, 18);
    writeU16Test(&bytes, outer + 8, 0); // LookAheadCount.
    writeU16Test(&bytes, outer + 10, 1); // PosCount.
    writeU16Test(&bytes, outer + 12, 0); // SequenceIndex 0.
    writeU16Test(&bytes, outer + 14, 1); // Lookup 1.
    writeCoverage1Test(&bytes, outer + 18, 10);

    writeU16Test(&bytes, 60, 9);
    writeU16Test(&bytes, 62, 0);
    writeU16Test(&bytes, 64, 1);
    writeU16Test(&bytes, 66, 8);
    const extension = 68;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 8);
    writeU32Test(&bytes, extension + 4, 8);
    const middle = extension + 8;
    writeU16Test(&bytes, middle + 0, 3);
    writeU16Test(&bytes, middle + 2, 0);
    writeU16Test(&bytes, middle + 4, 2);
    writeU16Test(&bytes, middle + 6, 22);
    writeU16Test(&bytes, middle + 8, 28);
    writeU16Test(&bytes, middle + 10, 0);
    writeU16Test(&bytes, middle + 12, 1);
    writeU16Test(&bytes, middle + 14, 0);
    writeU16Test(&bytes, middle + 16, 2);
    writeCoverage1Test(&bytes, middle + 22, 10);
    writeCoverage1Test(&bytes, middle + 28, 11);

    writeU16Test(&bytes, 120, 8);
    writeU16Test(&bytes, 122, 0);
    writeU16Test(&bytes, 124, 1);
    writeU16Test(&bytes, 126, 8);
    const inner = 128;
    writeU16Test(&bytes, inner + 0, 3);
    writeU16Test(&bytes, inner + 2, 0);
    writeU16Test(&bytes, inner + 4, 1);
    writeU16Test(&bytes, inner + 6, 18);
    writeU16Test(&bytes, inner + 8, 1);
    writeU16Test(&bytes, inner + 10, 24);
    writeU16Test(&bytes, inner + 12, 1);
    writeU16Test(&bytes, inner + 14, 0);
    writeU16Test(&bytes, inner + 16, 3);
    writeCoverage1Test(&bytes, inner + 18, 10);
    writeCoverage1Test(&bytes, inner + 24, 11);

    writeU16Test(&bytes, 170, 2);
    writeU16Test(&bytes, 172, 0);
    writeU16Test(&bytes, 174, 1);
    writeU16Test(&bytes, 176, 8);
    const pair = 178;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0);
    writeU16Test(&bytes, pair + 6, 0x0004);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 10);
    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 11);
    writeI16Test(&bytes, pair_set + 4, -70);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 20, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -70), adjustments.items[1].x_advance);
}

test "GPOS context nested lookup can apply MarkBasePos" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 106;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 12);
    // PosLookupRecord sequenceIndex=1 invokes MarkBasePos on the matched mark.
    // The nested lookup still needs the full run so it can locate glyph 10 as
    // the previous base, but it must not position marks outside this record.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 52, 4);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_base = 60;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 18);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 24);
    writeU16Test(&bytes, mark_base + 10, 36);

    writeCoverage1Test(&bytes, mark_base + 12, 12);
    writeCoverage1Test(&bytes, mark_base + 18, 10);

    const mark_array = mark_base + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const base_array = mark_base + 36;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 80, 120);

    const glyphs = [_]GlyphId{ 10, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS context nested lookup applies MarkLigPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 22);
    // The context matches only [20, 22], but the nested MarkLigPos subtable
    // also covers the later [21, 22] cluster. PosLookupRecord sequenceIndex=1
    // must therefore attach just the matched mark while still using the full
    // run to find glyph 20 as its preceding ligature.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 20);

    writeU16Test(&bytes, 52, 5);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_lig = 60;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 18);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 26);
    writeU16Test(&bytes, mark_lig + 10, 38);

    writeCoverage1Test(&bytes, mark_lig + 12, 22);
    writeCoverage1ListTest(&bytes, mark_lig + 18, &.{ 20, 21 });

    const mark_array = mark_lig + 26;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const ligature_array = mark_lig + 38;
    writeU16Test(&bytes, ligature_array + 0, 2);
    writeU16Test(&bytes, ligature_array + 2, 6);
    writeU16Test(&bytes, ligature_array + 4, 16);

    const first_ligature_attach = ligature_array + 6;
    writeU16Test(&bytes, first_ligature_attach + 0, 1);
    writeU16Test(&bytes, first_ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, first_ligature_attach + 4, 100, 120);

    const second_ligature_attach = ligature_array + 16;
    writeU16Test(&bytes, second_ligature_attach + 0, 1);
    writeU16Test(&bytes, second_ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, second_ligature_attach + 4, 200, 220);

    const glyphs = [_]GlyphId{ 20, 22, 21, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS context nested lookup applies MarkToMarkPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 116;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 12);
    // The matched input is [10, 12], and sequenceIndex=1 targets only that
    // second glyph. A later [13, 12] mark pair is covered by MarkToMarkPos too,
    // so a nested implementation that rescans the entire run would incorrectly
    // attach the final glyph as well.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 52, 6);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_mark = 60;
    writeU16Test(&bytes, mark_mark + 0, 1);
    writeU16Test(&bytes, mark_mark + 2, 12);
    writeU16Test(&bytes, mark_mark + 4, 18);
    writeU16Test(&bytes, mark_mark + 6, 1);
    writeU16Test(&bytes, mark_mark + 8, 26);
    writeU16Test(&bytes, mark_mark + 10, 38);

    writeCoverage1Test(&bytes, mark_mark + 12, 12);
    writeCoverage1ListTest(&bytes, mark_mark + 18, &.{ 10, 13 });

    const mark_1_array = mark_mark + 26;
    writeU16Test(&bytes, mark_1_array + 0, 1);
    writeU16Test(&bytes, mark_1_array + 2, 0);
    writeU16Test(&bytes, mark_1_array + 4, 6);
    writeAnchor1Test(&bytes, mark_1_array + 6, 10, 15);

    const mark_2_array = mark_mark + 38;
    writeU16Test(&bytes, mark_2_array + 0, 2);
    writeU16Test(&bytes, mark_2_array + 2, 6);
    writeU16Test(&bytes, mark_2_array + 4, 12);
    writeAnchor1Test(&bytes, mark_2_array + 6, 80, 120);
    writeAnchor1Test(&bytes, mark_2_array + 12, 200, 220);

    const glyphs = [_]GlyphId{ 10, 12, 13, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS ExtensionPos single positioning subtables respect mark filtering ordering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 36);
    writeU16Test(&bytes, 10, 0);

    const first_extension = 12;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 25);
    writeCoverage1Test(&bytes, first_single + 8, 5);

    const second_extension = 36;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeI16Test(&bytes, second_single + 6, 40);
    writeCoverage1Test(&bytes, second_single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{5}, &.{7} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    // Homogeneous ExtensionPos(SinglePos) subtables must behave like direct
    // SinglePos alternatives: the first matching wrapper wins for the original
    // mark, while the unselected mark filtering-set member remains transparent.
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[0].x_placement);
}

test "GPOS mixed ExtensionPos PairPos alternatives respect mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 3);
    writeU16Test(&bytes, 6, 14);
    writeU16Test(&bytes, 8, 58);
    writeU16Test(&bytes, 10, 82);
    writeU16Test(&bytes, 12, 0);

    const first_extension = 14;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const middle_extension = 58;
    writeU16Test(&bytes, middle_extension + 0, 1);
    writeU16Test(&bytes, middle_extension + 2, 1);
    writeU32Test(&bytes, middle_extension + 4, 8);
    const single = middle_extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 25);
    writeCoverage1Test(&bytes, single + 8, 99);

    const second_extension = 82;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    var mark_attach_classes = [_]u16{0} ** 13;
    mark_attach_classes[12] = 2;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The middle ExtensionPos(SinglePos) makes the lookup heterogeneous, so it
    // cannot use the homogeneous PairPos fast path. PairPos wrappers are still
    // ordered alternatives for glyph 10, and mark filtering keeps glyph 12
    // transparent when searching for the second glyph of the pair.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS extension positioning preserves wrapper lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0008);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const extension = 8;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    writeU32Test(&bytes, extension + 4, 8);

    const single = extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 50);
    writeCoverage1Test(&bytes, single + 8, 3);

    const glyphs = [_]GlyphId{3};
    const glyph_classes = [_]u16{ 0, 1, 2, 3 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS mark-to-ligature uses source metadata for component choice" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 5);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_lig = 8;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 18);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 24);
    writeU16Test(&bytes, mark_lig + 10, 36);

    writeCoverage1Test(&bytes, mark_lig + 12, 22);
    writeCoverage1Test(&bytes, mark_lig + 18, 20);

    const mark_array = mark_lig + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const ligature_array = mark_lig + 36;
    writeU16Test(&bytes, ligature_array + 0, 1);
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 2);
    writeU16Test(&bytes, ligature_attach + 2, 8);
    writeU16Test(&bytes, ligature_attach + 4, 14);
    writeAnchor1Test(&bytes, ligature_attach + 8, 100, 120);
    writeAnchor1Test(&bytes, ligature_attach + 14, 260, 300);

    const glyphs = [_]GlyphId{ 20, 22 };
    const sources = [_]usize{ 0, 2 };
    var ligature_components = ligature_provenance.Store{};
    defer ligature_components.deinit(allocator);
    const ligature_info = try ligature_components.addLigature(allocator, &.{ 0, 1 });
    try ligature_components.infos.appendSlice(allocator, &.{ ligature_info, .{} });
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .run_metadata = &.{
            .glyph_source_indices = &sources,
            .ligature_components = &ligature_components,
        },
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    // This is the first mark after the ligature in the post-GSUB stream, so
    // the mark-order fallback would choose component 0. Source metadata shows
    // that it originated after the second component's source position, so it
    // must use component 1.
    try std.testing.expectEqual(@as(i16, 250), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 285), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS mark-to-ligature attachment skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 5);
    writeU16Test(&bytes, 2, 0x0002); // IgnoreBaseGlyphs between the ligature and mark.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_lig = 8;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 18);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 24);
    writeU16Test(&bytes, mark_lig + 10, 44);

    writeCoverage1Test(&bytes, mark_lig + 12, 22);
    writeCoverage1Test(&bytes, mark_lig + 18, 20);

    const mark_array = mark_lig + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 8);
    writeAnchor1Test(&bytes, mark_array + 8, 0, 0);

    const ligature_array = mark_lig + 44;
    writeU16Test(&bytes, ligature_array + 0, 1);
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 1);
    writeU16Test(&bytes, ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, ligature_attach + 4, 100, 120);

    const glyphs = [_]GlyphId{ 20, 21, 22 };
    var glyph_classes = [_]u16{0} ** 23;
    glyph_classes[20] = 2;
    glyph_classes[21] = 1;
    glyph_classes[22] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 120), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS mark-to-ligature selects component anchors from mark order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 104;

    writeU16Test(&bytes, 0, 5);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_lig = 8;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 20);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 26);
    writeU16Test(&bytes, mark_lig + 10, 54);

    writeCoverage1ListTest(&bytes, mark_lig + 12, &.{ 22, 23 });
    writeCoverage1Test(&bytes, mark_lig + 20, 20);

    const mark_array = mark_lig + 26;
    writeU16Test(&bytes, mark_array + 0, 2);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 10);
    writeU16Test(&bytes, mark_array + 6, 0);
    writeU16Test(&bytes, mark_array + 8, 16);
    writeAnchor1Test(&bytes, mark_array + 10, 0, 0);
    writeAnchor1Test(&bytes, mark_array + 16, 0, 0);

    const ligature_array = mark_lig + 54;
    writeU16Test(&bytes, ligature_array + 0, 1);
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 2);
    writeU16Test(&bytes, ligature_attach + 2, 6);
    writeU16Test(&bytes, ligature_attach + 4, 12);
    writeAnchor1Test(&bytes, ligature_attach + 6, 100, 110);
    writeAnchor1Test(&bytes, ligature_attach + 12, 300, 330);

    const glyphs = [_]GlyphId{ 20, 22, 23 };
    var glyph_classes = [_]u16{0} ** 24;
    glyph_classes[20] = 2;
    glyph_classes[22] = 3;
    glyph_classes[23] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 110), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 300), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, 330), adjustments.items[1].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[1].attachment_parent_index);
}

test "GPOS mark-to-mark attachment skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 6);
    writeU16Test(&bytes, 2, 0x0002); // IgnoreBaseGlyphs between the two marks.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_mark = 8;
    writeU16Test(&bytes, mark_mark + 0, 1);
    writeU16Test(&bytes, mark_mark + 2, 12);
    writeU16Test(&bytes, mark_mark + 4, 18);
    writeU16Test(&bytes, mark_mark + 6, 1);
    writeU16Test(&bytes, mark_mark + 8, 24);
    writeU16Test(&bytes, mark_mark + 10, 44);

    writeCoverage1Test(&bytes, mark_mark + 12, 12);
    writeCoverage1Test(&bytes, mark_mark + 18, 10);

    const mark_1_array = mark_mark + 24;
    writeU16Test(&bytes, mark_1_array + 0, 1);
    writeU16Test(&bytes, mark_1_array + 2, 0);
    writeU16Test(&bytes, mark_1_array + 4, 8);
    writeAnchor1Test(&bytes, mark_1_array + 8, 0, 0);

    const mark_2_array = mark_mark + 44;
    writeU16Test(&bytes, mark_2_array + 0, 1);
    writeU16Test(&bytes, mark_2_array + 2, 6);
    writeAnchor1Test(&bytes, mark_2_array + 6, 50, 70);

    const glyphs = [_]GlyphId{ 10, 11, 12 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[10] = 3;
    glyph_classes[11] = 1;
    glyph_classes[12] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 50), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

fn writeSinglePositionLookup(bytes: []u8, lookup_offset: usize, glyph: GlyphId, lookup_flag: u16, x_placement: i16) void {
    writeU16Test(bytes, lookup_offset + 0, 1);
    writeU16Test(bytes, lookup_offset + 2, lookup_flag);
    writeU16Test(bytes, lookup_offset + 4, 1);
    writeU16Test(bytes, lookup_offset + 6, 8);

    const single = lookup_offset + 8;
    writeU16Test(bytes, single + 0, 1);
    writeU16Test(bytes, single + 2, 8);
    writeU16Test(bytes, single + 4, 0x0001);
    writeI16Test(bytes, single + 6, x_placement);
    writeCoverage1Test(bytes, single + 8, glyph);
}

fn writeCoverage1Test(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, glyph);
}

fn writeCoverage1ListTest(bytes: []u8, offset: usize, glyphs: []const GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, i| {
        writeU16Test(bytes, offset + 4 + i * 2, glyph);
    }
}

fn writeClassDef1Test(bytes: []u8, offset: usize, start: GlyphId, class: u16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, start);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, class);
}

fn writeAnchor1Test(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeI16Test(bytes, offset + 2, x);
    writeI16Test(bytes, offset + 4, y);
}

fn writeLangSysTest(bytes: []u8, offset: usize, feature_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 0xffff);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, feature_index);
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
    writeLangSysTest(bytes, 40, 0);
    writeLangSysTest(bytes, 48, 1);
    writeLangSysTest(bytes, 56, 1);

    writeU16Test(bytes, 64, 0);
    writeU16Test(bytes, 66, 0);

    writeU16Test(bytes, 68, 2);
    writeFeatureRecordTest(bytes, 70, unicode.tag("kern"), 14);
    writeFeatureRecordTest(bytes, 76, unicode.tag("mark"), 18);
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
        writeFeatureRecordTest(bytes, 36, required_tag, 14);
        writeFeatureRecordTest(bytes, 42, optional_tag, 20);
    } else {
        writeFeatureRecordTest(bytes, 36, optional_tag, 20);
        writeFeatureRecordTest(bytes, 42, required_tag, 14);
    }
    writeFeatureTest(bytes, 48, 0);
    writeFeatureTest(bytes, 54, 1);

    writeU16Test(bytes, 60, 2);
    writeU16Test(bytes, 62, 0);
    writeU16Test(bytes, 64, 0);
}

fn writeFeatureRecordTest(bytes: []u8, offset: usize, tag_value: u32, feature_offset: u16) void {
    writeU32Test(bytes, offset, tag_value);
    writeU16Test(bytes, offset + 4, feature_offset);
}

fn writeFeatureTest(bytes: []u8, offset: usize, lookup_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, lookup_index);
}

fn writeFeatureListTest(bytes: []u8, offset: usize, lookups: []const u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, @intCast(lookups.len));
    for (lookups, 0..) |lookup_index, index| {
        writeU16Test(bytes, offset + 4 + index * 2, lookup_index);
    }
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
    writeFeatureRecordTest(bytes, 36, feature_tag, 14);
    writeFeatureRecordTest(bytes, 42, feature_tag, 24);
    writeFeatureListTest(bytes, 48, &.{ 3, 1, 3 });
    writeFeatureListTest(bytes, 58, &.{ 2, 1 });

    writeU16Test(bytes, 66, 4);
    writeU16Test(bytes, 68, 0);
    writeU16Test(bytes, 70, 0);
    writeU16Test(bytes, 72, 0);
    writeU16Test(bytes, 74, 0);
}

fn writeMarkLookupSelectionTable(bytes: []u8) void {
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
    writeFeatureRecordTest(bytes, 36, unicode.tag("kern"), 14);
    writeFeatureRecordTest(bytes, 42, unicode.tag("mark"), 20);
    writeFeatureListTest(bytes, 48, &.{0});
    writeFeatureListTest(bytes, 54, &.{ 1, 2 });

    writeU16Test(bytes, 66, 3);
    writeU16Test(bytes, 68, 8);
    writeU16Test(bytes, 70, 14);
    writeU16Test(bytes, 72, 20);

    writeU16Test(bytes, 74, 2);
    writeU16Test(bytes, 76, 0);
    writeU16Test(bytes, 78, 0);

    writeU16Test(bytes, 80, 4);
    writeU16Test(bytes, 82, 0);
    writeU16Test(bytes, 84, 0);

    writeU16Test(bytes, 86, 9);
    writeU16Test(bytes, 88, 0);
    writeU16Test(bytes, 90, 1);
    writeU16Test(bytes, 92, 8);

    const extension = 94;
    writeU16Test(bytes, extension + 0, 1);
    writeU16Test(bytes, extension + 2, 5);
    writeU32Test(bytes, extension + 4, 8);
}

test "GPOS public adjustment collection validates source metadata cardinality" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 1);

    const glyphs = [_]GlyphId{ 1, 2 };
    const sources = [_]usize{0};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.InvalidShapingInput, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &glyphs, &adjustments, allocator, .{
        .run_metadata = &.{ .glyph_source_indices = &sources },
    }));
}

test "GPOS public adjustment collection validates variation coordinates" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU32Test(&bytes, 0, 0x00010000);
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.InvalidShapingInput, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{
        .normalized_variation_coords = &.{std.math.nan(f32)},
    }));
    try std.testing.expectError(error.InvalidShapingInput, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &.{1}, &adjustments, allocator, .{
        .normalized_variation_coords = &.{1.01},
    }));
}

test "GPOS public adjustment collection validates ligature component source order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 1);

    const glyphs = [_]GlyphId{10};
    var ligature_components = ligature_provenance.Store{};
    defer ligature_components.deinit(allocator);
    try ligature_components.sources.appendSlice(allocator, &.{ 3, 2 });
    try ligature_components.infos.append(allocator, .{ .component_count = 2 });
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.InvalidShapingInput, collectAdjustmentsWithOptions(&bytes, 0, bytes.len, &glyphs, &adjustments, allocator, .{
        .run_metadata = &.{ .ligature_components = &ligature_components },
    }));
}

test {
    _ = @import("gpos/tests/accelerator/root.zig");
    _ = @import("gpos/tests/feature/root.zig");
    _ = @import("gpos/tests/positioning/root.zig");
    _ = @import("gpos/tests/runtime/root.zig");
    _ = @import("gpos/tests/table/root.zig");
    _ = @import("gpos/tests/validation/root.zig");
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn readU16(table: Table, relative: usize) GposError!u16 {
    return table.readU16(relative);
}

fn readI16(table: Table, relative: usize) GposError!i16 {
    return table.readI16(relative);
}

fn readU32(table: Table, relative: usize) GposError!u32 {
    return table.readU32(relative);
}
