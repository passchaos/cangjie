const std = @import("std");
const bin = @import("binary.zig");
const GlyphDigest = @import("glyph_digest.zig").GlyphDigest;
const GlyphId = @import("glyph.zig").GlyphId;
const ot_layout = @import("opentype/layout.zig");
const class_context = @import("opentype/class_context.zig");
const metric_variation = @import("opentype/metric_variation.zig");
const ligature_provenance = @import("ligature_provenance.zig");
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

pub const Adjustment = struct {
    index: usize,
    x_advance: i16 = 0,
    x_placement: i16 = 0,
    y_placement: i16 = 0,
    y_advance: i16 = 0,
    pair_positioned: bool = false,
    attachment_type: AttachmentType = .none,
    attachment_parent_index: ?usize = null,
    x_advance_absolute: bool = false,
    y_advance_absolute: bool = false,

    pub fn markAttachment(self: Adjustment) bool {
        return self.attachment_type == .mark;
    }

    pub fn attachmentParentIndex(self: Adjustment) ?usize {
        return self.attachment_parent_index;
    }
};

pub const AttachmentType = enum {
    none,
    mark,
    cursive,
};

const PositionContextResult = struct {
    matched: bool = false,
    next_pos: usize = 0,
};

const Table = struct {
    data: []const u8,
    offset: usize,
    length: usize,
    assume_validated: bool = false,
    /// True only during Font.parse's exhaustive LookupList validation. In that
    /// mode every lookup's payload is visited by the outer pass, so contextual
    /// PosLookupRecords only need to prove that their indexes are in range.
    /// Runtime shaping leaves this false because a matched context must
    /// preflight nested lookups before appending any partial adjustments.
    validating_full_lookup_list: bool = false,
    /// Optional maxp.numGlyphs bound supplied by Font.parse. Runtime shaping
    /// callers do not know the SFNT maxp table, so their Table values leave
    /// this null and keep the historical structural-only validation.
    glyph_count: ?u16 = null,
};

const FeatureSelection = struct {
    index: u16,
    required: bool = false,
};

pub const LookupOptions = struct {
    pub const Direction = enum {
        ltr,
        rtl,
    };

    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    direction: Direction = .ltr,
    features: []const unicode.FeatureOverride = &.{},
    /// Normalized fvar-axis coordinates after avar mapping. AnchorFormat3
    /// VariationIndex children resolve through the GDEF ItemVariationStore in
    /// this same axis order.
    normalized_variation_coords: []const f32 = &.{},
    gdef_variation_store: ?VariationStore = null,
    apply_all_if_unselected: bool = true,
    glyph_classes: ?[]const u16 = null,
    mark_attach_classes: ?[]const u16 = null,
    mark_filtering_sets: ?[]const []const GlyphId = null,
    active_mark_filtering_set: ?u16 = null,
    /// Cached run-level mark attachment possibility after GSUB. This includes
    /// GDEF mark glyph classes and Unicode marks; some fonts cover a mark glyph
    /// in MarkBasePos while misclassifying it in GDEF.
    run_may_have_mark_attachments: ?bool = null,
    /// Cached source-level default-ignorable presence. A known-false value
    /// proves that LookupFlag=0 matching can advance to the adjacent glyph
    /// without consulting source metadata or Unicode properties.
    run_has_default_ignorables: ?bool = null,
    /// Optional source-order index per shaped glyph. MarkLigPos uses this with
    /// `ligature_components` to attach marks to the logical component whose
    /// source position most closely precedes the mark. Without this metadata,
    /// the parser falls back to a conservative positional heuristic.
    glyph_source_indices: ?[]const usize = null,
    /// Original Unicode scalars indexed by `glyph_source_indices`. GPOS mark
    /// attachment searches use this to keep hidden default-ignorables
    /// transparent after they have been mapped to visible fallback glyph ids.
    source_codepoints: ?[]const u21 = null,
    /// HarfBuzz-compatible parity switch: an unsupported variation selector
    /// mapped to a synthetic not-found glyph remains visible to positioning
    /// lookups instead of being skipped as a hidden default-ignorable.
    visible_variation_selectors: bool = false,
    /// GSUB substitution state parallel to the post-GSUB glyph stream. GPOS
    /// treats untouched default-ignorables as transparent, but substituted
    /// glyphs must remain visible to matching just like HarfBuzz.
    glyph_substituted: ?[]const bool = null,
    /// Optional compact ligature provenance. Its `infos` array is parallel to
    /// the post-GSUB glyph stream; component source slices live in the store's
    /// append-only pool.
    ligature_components: ?*const ligature_provenance.Store = null,
    /// Preselected lookup indices for the active script/language/features.
    /// This is a shaping fast path; callers that supply it must keep it in
    /// sync with the other selection options.
    selected_lookups: ?[]const u16 = null,
    /// Optional per-lookup prefilters built once for the validated GPOS table.
    /// The slice is indexed by LookupList index and may be shared across runs.
    lookup_accelerators: ?[]const LookupAccelerator = null,
    assume_validated: bool = false,
    shape_profile: ?*shape_profile_mod.ShapeStageProfile = null,
    profile_io: ?std.Io = null,
    /// PosLookupRecord recursion depth for contextual lookups. Public callers
    /// leave this at zero; nested contextual dispatch increments it so cyclic
    /// lookup graphs are rejected instead of recursing indefinitely.
    context_depth: usize = 0,
};

pub const VariationStore = struct {
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    store_offset: usize,
};

pub const LookupAccelerator = struct {
    /// Dispatch fields decoded once from the validated Lookup table. Runtime
    /// use is guarded by the lookup offset so mismatched cache entries fall
    /// back to normal bounds-checked parsing.
    lookup_offset: usize = 0,
    lookup_type: u16 = 0,
    lookup_flag: u16 = 0,
    subtable_count: u16 = 0,
    mark_filtering_set: ?u16 = null,
    extension_lookup_type: ?u16 = null,
    coverage_digest: GlyphDigest = .{},
    coverage_groups: []const ChainingSubtableGroup = &.{},
    coverage_group_slots: []const u16 = &.{},
    single_pos_subtables: []const SinglePosSubtable = &.{},
    pair_pos_subtables: []const PairPosSubtableAccelerator = &.{},
    pair_pos_records: []const PairPosRecord = &.{},
    pair_pos_coverage_classes: []const PairClassEntry = &.{},
    pair_pos_class_entries: []const PairClassEntry = &.{},
    pair_pos_class_matrix: []const i16 = &.{},
    pair_pos_extension: bool = false,
    cursive_subtables: []const CursivePositionSubtable = &.{},
    mark_to_base_subtables: []const MarkToBaseSubtable = &.{},
    chaining_coverage_only: bool = false,
    chaining_subtables: []const ChainingCoverageSubtable = &.{},
    chaining_groups: []const ChainingSubtableGroup = &.{},
    chaining_group_slots: []const u16 = &.{},
    chaining_class_subtables: []const ChainingClassSubtableAccelerator = &.{},
};

const PairPosAcceleratorKind = enum(u8) {
    generic,
    format_1_x_advance,
    format_2_x_advance,
    format_2_dense_x_advance,
};

const PairPosSubtableAccelerator = struct {
    kind: PairPosAcceleratorKind = .generic,
    // Format 1 uses these as the global record slice. Dense format 2 has no
    // PairPosRecord slice, so it reuses the same otherwise-idle words for the
    // ClassDef1-coverage and ClassDef2 base glyphs without widening the hot
    // LookupAccelerator sidecar.
    record_start: usize = 0,
    record_len: usize = 0,
    coverage_start: usize = 0,
    coverage_len: usize = 0,
    class_2_start: usize = 0,
    class_2_len: usize = 0,
    class_1_count: u16 = 0,
    class_2_count: u16 = 0,
    matrix_start: usize = 0,
};

const PairPosRecord = struct {
    first: GlyphId,
    second: GlyphId,
    x_advance: i16,
};

const PairClassEntry = struct {
    glyph: GlyphId,
    class: u16,
};

const NativeCoverage = union(enum) {
    glyphs: []const GlyphId,
    ranges: []const ot_layout.GlyphRangeRecord,

    fn index(self: NativeCoverage, glyph: GlyphId) ?usize {
        switch (self) {
            .glyphs => |glyphs| {
                var lo: usize = 0;
                var hi = glyphs.len;
                while (lo < hi) {
                    const mid = lo + (hi - lo) / 2;
                    if (glyph < glyphs[mid]) {
                        hi = mid;
                    } else if (glyph > glyphs[mid]) {
                        lo = mid + 1;
                    } else {
                        return mid;
                    }
                }
                return null;
            },
            .ranges => |ranges| {
                var lo: usize = 0;
                var hi = ranges.len;
                while (lo < hi) {
                    const mid = lo + (hi - lo) / 2;
                    if (glyph <= ranges[mid].end) {
                        hi = mid;
                    } else {
                        lo = mid + 1;
                    }
                }
                if (lo >= ranges.len or glyph < ranges[lo].start) return null;
                return @as(usize, ranges[lo].value) + (@as(usize, glyph) - ranges[lo].start);
            },
        }
    }
};

const SinglePosSubtable = struct {
    subtable_offset: usize = 0,
    pos_format: u16 = 0,
    coverage_offset: usize = 0,
    value_format: u16 = 0,
    value_count: u16 = 0,
    value_size: usize = 0,
    values_pos: usize = 0,
    value: Adjustment = .{ .index = 0 },
};

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

const ChainingCoverageSubtable = struct {
    const max_fast_records = 4;

    subtable_offset: usize = 0,
    backtrack_offsets_pos: usize = 0,
    backtrack_count: u16 = 0,
    backtrack_coverages: []const NativeCoverage = &.{},
    input_offsets_pos: usize = 0,
    input_count: u16 = 0,
    input_coverages: []const NativeCoverage = &.{},
    second_input_digest: GlyphDigest = .{},
    lookahead_offsets_pos: usize = 0,
    lookahead_count: u16 = 0,
    lookahead_coverages: []const NativeCoverage = &.{},
    records_pos: usize = 0,
    pos_count: u16 = 0,
    fast_record_count: u16 = 0,
    fast_records: [max_fast_records]FastSinglePosRecord = [_]FastSinglePosRecord{.{}} ** max_fast_records,
};

const FastSinglePosRecord = struct {
    sequence_index: u16 = 0,
    lookup_index: u16 = 0,
    lookup_flag: u16 = 0,
};

const ChainingClassSubtableAccelerator = struct {
    subtable_offset: usize = 0,
    coverage_offset: usize = 0,
    input_class_def: usize = 0,
    lookahead_class_def: usize = 0,
    uniform_input_count: u16 = 0,
    rules: []const class_context.Rule = &.{},
    classes: []const u16 = &.{},
    groups: []const class_context.RuleGroup = &.{},
};

const ChainingSubtableGroup = struct {
    glyph: GlyphId,
    subtable_indices: []const u16,
};

const ChainingSubtablePair = struct {
    glyph: GlyphId,
    subtable_index: u16,
};

const max_context_preflight_depth = 16;

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
    const feature_count = try ensureFeatureLookupReferencesWithin(table, lookup_count);
    try ensureScriptFeatureReferencesWithin(table, feature_count);
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
    try validateShapingMetadata(options, glyphs.len);
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
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGpos;
    const table = Table{ .data = data, .offset = offset, .length = length, .assume_validated = true };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGpos;

    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);
    const accelerators = try allocator.alloc(LookupAccelerator, lookup_count);
    @memset(accelerators, .{});
    var built_count: usize = 0;
    errdefer {
        deinitLookupAcceleratorContents(allocator, accelerators[0..built_count]);
        allocator.free(accelerators);
    }
    for (accelerators, 0..) |*accelerator, lookup_i| {
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + lookup_i * 2));
        // Cached dispatch bypasses runtime header reads. Re-prove the complete
        // fixed header here so malformed direct accelerator input cannot turn
        // that optimization into a trust-boundary change.
        try ensurePositionLookupHeaderWithin(table, lookup_offset);
        accelerator.* = try buildLookupAccelerator(table, lookup_offset, allocator);
        built_count += 1;
    }
    return accelerators;
}

pub fn deinitLookupAccelerators(allocator: std.mem.Allocator, accelerators: []LookupAccelerator) void {
    deinitLookupAcceleratorContents(allocator, accelerators);
    allocator.free(accelerators);
}

fn deinitLookupAcceleratorContents(allocator: std.mem.Allocator, accelerators: []LookupAccelerator) void {
    for (accelerators) |accelerator| {
        for (accelerator.coverage_groups) |group| allocator.free(group.subtable_indices);
        allocator.free(accelerator.coverage_groups);
        allocator.free(accelerator.coverage_group_slots);
        allocator.free(accelerator.single_pos_subtables);
        allocator.free(accelerator.pair_pos_subtables);
        allocator.free(accelerator.pair_pos_records);
        allocator.free(accelerator.pair_pos_coverage_classes);
        allocator.free(accelerator.pair_pos_class_entries);
        allocator.free(accelerator.pair_pos_class_matrix);
        deinitCursivePositionSubtables(allocator, accelerator.cursive_subtables);
        deinitMarkToBaseSubtables(allocator, accelerator.mark_to_base_subtables);
        for (accelerator.chaining_groups) |group| allocator.free(group.subtable_indices);
        allocator.free(accelerator.chaining_groups);
        allocator.free(accelerator.chaining_group_slots);
        deinitChainingCoverageSubtables(allocator, accelerator.chaining_subtables);
        deinitChainingClassSubtableAccelerators(allocator, accelerator.chaining_class_subtables);
    }
}

fn deinitChainingClassSubtableAccelerators(allocator: std.mem.Allocator, subtables: []const ChainingClassSubtableAccelerator) void {
    deinitChainingClassSubtableAcceleratorContents(allocator, subtables);
    allocator.free(subtables);
}

fn deinitChainingClassSubtableAcceleratorContents(allocator: std.mem.Allocator, subtables: []const ChainingClassSubtableAccelerator) void {
    for (subtables) |subtable| {
        allocator.free(subtable.rules);
        allocator.free(subtable.classes);
        allocator.free(subtable.groups);
    }
}

fn buildLookupAccelerator(table: Table, lookup_offset: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!LookupAccelerator {
    const lookup_type = try readU16(table, lookup_offset);
    const lookup_flag = try readU16(table, lookup_offset + 2);
    const subtable_count = try readU16(table, lookup_offset + 4);
    const extension_type = if (lookup_type == 9)
        try extensionPositionLookupType(table, lookup_offset, subtable_count)
    else
        null;
    const accelerates_pair_pos = lookup_type == 2 or extension_type == 2;
    var digest = GlyphDigest.empty();
    var accelerator = LookupAccelerator{
        .lookup_offset = lookup_offset,
        .lookup_type = lookup_type,
        .lookup_flag = lookup_flag,
        .subtable_count = subtable_count,
        .mark_filtering_set = if ((lookup_flag & 0x0010) != 0)
            try readU16(table, lookup_offset + 6 + @as(usize, subtable_count) * 2)
        else
            null,
        .extension_lookup_type = extension_type,
    };
    const single_pos_subtables = if (lookup_type == 1)
        try allocator.alloc(SinglePosSubtable, subtable_count)
    else
        try allocator.alloc(SinglePosSubtable, 0);
    errdefer allocator.free(single_pos_subtables);
    @memset(single_pos_subtables, .{});
    const pair_pos_subtables = if (accelerates_pair_pos)
        try allocator.alloc(PairPosSubtableAccelerator, subtable_count)
    else
        try allocator.alloc(PairPosSubtableAccelerator, 0);
    errdefer allocator.free(pair_pos_subtables);
    @memset(pair_pos_subtables, .{});
    var pair_pos_records = std.ArrayList(PairPosRecord).empty;
    errdefer pair_pos_records.deinit(allocator);
    var pair_pos_coverage_classes = std.ArrayList(PairClassEntry).empty;
    errdefer pair_pos_coverage_classes.deinit(allocator);
    var pair_pos_class_entries = std.ArrayList(PairClassEntry).empty;
    errdefer pair_pos_class_entries.deinit(allocator);
    var pair_pos_class_matrix = std.ArrayList(i16).empty;
    errdefer pair_pos_class_matrix.deinit(allocator);
    const mark_to_base_subtables = if (lookup_type == 4)
        try allocator.alloc(MarkToBaseSubtable, subtable_count)
    else
        try allocator.alloc(MarkToBaseSubtable, 0);
    @memset(mark_to_base_subtables, .{});
    errdefer deinitMarkToBaseSubtables(allocator, mark_to_base_subtables);
    const cursive_subtables = if (lookup_type == 3)
        try allocator.alloc(CursivePositionSubtable, subtable_count)
    else
        try allocator.alloc(CursivePositionSubtable, 0);
    @memset(cursive_subtables, .{ .subtable_offset = 0, .coverage_offset = 0, .entry_exit_count = 0 });
    errdefer deinitCursivePositionSubtables(allocator, cursive_subtables);
    var coverage_pairs = std.ArrayList(ChainingSubtablePair).empty;
    errdefer coverage_pairs.deinit(allocator);
    var group_pairs = std.ArrayList(ChainingSubtablePair).empty;
    errdefer group_pairs.deinit(allocator);
    const chaining_subtables = if (lookup_type == 8 and try chainingPositionLookupUsesCoverageOnly(table, lookup_offset, subtable_count))
        try allocator.alloc(ChainingCoverageSubtable, subtable_count)
    else
        try allocator.alloc(ChainingCoverageSubtable, 0);
    @memset(chaining_subtables, .{});
    errdefer deinitChainingCoverageSubtables(allocator, chaining_subtables);
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        if (try lookupSubtableCoverageOffset(table, subtable_offset, lookup_type)) |coverage_offset| {
            digest.unionWith(try coverageDigest(table, coverage_offset));
            try appendChainingSubtablePairs(table, coverage_offset, @intCast(subtable_i), &coverage_pairs, allocator);
            if (single_pos_subtables.len != 0) {
                single_pos_subtables[subtable_i] = try parseSinglePositionSubtable(table, subtable_offset);
            }
            if (pair_pos_subtables.len != 0) {
                const pair_subtable_offset = if (extension_type == 2)
                    try extensionPositionSubtablePayload(table, subtable_offset, 2)
                else
                    subtable_offset;
                pair_pos_subtables[subtable_i] = try appendSimplePairPosRecords(
                    table,
                    pair_subtable_offset,
                    &pair_pos_records,
                    &pair_pos_coverage_classes,
                    &pair_pos_class_entries,
                    &pair_pos_class_matrix,
                    allocator,
                );
            }
            if (mark_to_base_subtables.len != 0) {
                mark_to_base_subtables[subtable_i] = try buildMarkToBaseSubtable(table, subtable_offset, allocator);
            }
            if (cursive_subtables.len != 0) {
                cursive_subtables[subtable_i] = try buildCursivePositionSubtable(table, subtable_offset, allocator);
            }
            if (chaining_subtables.len != 0) {
                chaining_subtables[subtable_i] = try buildChainingCoverageSubtable(table, subtable_offset, allocator) orelse continue;
                try appendChainingSubtablePairs(table, coverage_offset, @intCast(subtable_i), &group_pairs, allocator);
            }
        }
    }
    accelerator.coverage_digest = digest;
    accelerator.single_pos_subtables = single_pos_subtables;
    accelerator.pair_pos_subtables = pair_pos_subtables;
    accelerator.pair_pos_records = try pair_pos_records.toOwnedSlice(allocator);
    errdefer allocator.free(accelerator.pair_pos_records);
    accelerator.pair_pos_coverage_classes = try pair_pos_coverage_classes.toOwnedSlice(allocator);
    errdefer allocator.free(accelerator.pair_pos_coverage_classes);
    accelerator.pair_pos_class_entries = try pair_pos_class_entries.toOwnedSlice(allocator);
    errdefer allocator.free(accelerator.pair_pos_class_entries);
    accelerator.pair_pos_class_matrix = try pair_pos_class_matrix.toOwnedSlice(allocator);
    accelerator.pair_pos_extension = extension_type == 2;
    errdefer allocator.free(accelerator.pair_pos_class_matrix);
    accelerator.cursive_subtables = cursive_subtables;
    accelerator.mark_to_base_subtables = mark_to_base_subtables;
    if (coverage_pairs.items.len != 0) {
        accelerator.coverage_groups = try buildChainingSubtableGroups(coverage_pairs.items, allocator);
        accelerator.coverage_group_slots = try buildChainingGroupSlots(accelerator.coverage_groups, allocator);
    }
    coverage_pairs.deinit(allocator);
    errdefer {
        for (accelerator.coverage_groups) |group| allocator.free(group.subtable_indices);
        allocator.free(accelerator.coverage_groups);
        allocator.free(accelerator.coverage_group_slots);
    }
    if (chaining_subtables.len != 0 and group_pairs.items.len != 0) {
        accelerator.chaining_coverage_only = true;
        accelerator.chaining_subtables = chaining_subtables;
        accelerator.chaining_groups = try buildChainingSubtableGroups(group_pairs.items, allocator);
        accelerator.chaining_group_slots = try buildChainingGroupSlots(accelerator.chaining_groups, allocator);
        errdefer {
            for (accelerator.chaining_groups) |group| allocator.free(group.subtable_indices);
            allocator.free(accelerator.chaining_groups);
            allocator.free(accelerator.chaining_group_slots);
        }
    }
    group_pairs.deinit(allocator);
    accelerator.chaining_class_subtables = try buildExtensionChainingClassSubtableAccelerators(table, lookup_offset, lookup_type, subtable_count, allocator);
    return accelerator;
}

const max_predecoded_pair_class_glyphs = 16_384;
const max_predecoded_pair_class_matrix = 16_384;
const max_dense_pair_class_entries = 8_192;

fn appendSimplePairPosRecords(
    table: Table,
    subtable_offset: usize,
    records: *std.ArrayList(PairPosRecord),
    coverage_classes: *std.ArrayList(PairClassEntry),
    class_entries: *std.ArrayList(PairClassEntry),
    class_matrix: *std.ArrayList(i16),
    allocator: std.mem.Allocator,
) (GposError || std.mem.Allocator.Error)!PairPosSubtableAccelerator {
    const pos_format = try readU16(table, subtable_offset);
    const value_format_1 = try readU16(table, subtable_offset + 4);
    const value_format_2 = try readU16(table, subtable_offset + 6);
    // Device/VariationIndex fields are currently validated but ignored by
    // readValueRecord. They follow the scalar fields, so an xAdvance-only
    // record remains safe to predecode as long as no other scalar is present.
    if ((value_format_1 & 0x000f) != 0x0004 or
        (value_format_1 & 0xff00) != 0 or
        value_format_2 != 0)
    {
        return .{};
    }
    const value_size_1 = try valueRecordSize(value_format_1);
    return switch (pos_format) {
        1 => try appendSimplePairPosFormat1Records(table, subtable_offset, value_size_1, records, allocator),
        2 => try appendSimplePairPosFormat2Records(
            table,
            subtable_offset,
            value_size_1,
            coverage_classes,
            class_entries,
            class_matrix,
            allocator,
        ),
        else => .{},
    };
}

fn appendSimplePairPosFormat1Records(
    table: Table,
    subtable_offset: usize,
    value_size_1: usize,
    records: *std.ArrayList(PairPosRecord),
    allocator: std.mem.Allocator,
) (GposError || std.mem.Allocator.Error)!PairPosSubtableAccelerator {
    const coverage_offset = try checkedRequiredCoverageOffset(
        table,
        subtable_offset,
        try readU16(table, subtable_offset + 2),
    );
    const pair_set_count = try readU16(table, subtable_offset + 8);
    const record_start = records.items.len;
    for (0..pair_set_count) |set_index| {
        // PairSetCount may exceed the first-glyph Coverage count. OpenType
        // indexes PairSet only through Coverage, so those trailing sets are
        // unreachable; HarfBuzz ignores them and TestGPOSTwo.otf relies on
        // that behavior. The defensive validator still rejects the opposite
        // shape (a Coverage index with no PairSet).
        const first = (try coverageGlyphAt(table, coverage_offset, set_index)) orelse break;
        const pair_set_offset = try checkedRequiredPositionOffset(
            table,
            subtable_offset,
            try readU16(table, subtable_offset + 10 + set_index * 2),
        );
        const pair_value_count = try readU16(table, pair_set_offset);
        for (0..pair_value_count) |pair_index| {
            const pair_record = pair_set_offset + 2 + pair_index * (2 + value_size_1);
            try records.append(allocator, .{
                .first = first,
                .second = try readU16(table, pair_record),
                .x_advance = try readI16(table, pair_record + 2),
            });
        }
    }
    return .{
        .kind = .format_1_x_advance,
        .record_start = record_start,
        .record_len = records.items.len - record_start,
    };
}

fn appendSimplePairPosFormat2Records(
    table: Table,
    subtable_offset: usize,
    value_size_1: usize,
    coverage_classes: *std.ArrayList(PairClassEntry),
    class_entries: *std.ArrayList(PairClassEntry),
    class_matrix: *std.ArrayList(i16),
    allocator: std.mem.Allocator,
) (GposError || std.mem.Allocator.Error)!PairPosSubtableAccelerator {
    const coverage_offset = try checkedRequiredCoverageOffset(
        table,
        subtable_offset,
        try readU16(table, subtable_offset + 2),
    );
    const class_def_1 = try checkedRequiredClassDefOffset(
        table,
        subtable_offset,
        try readU16(table, subtable_offset + 8),
    );
    const class_def_2 = try checkedRequiredClassDefOffset(
        table,
        subtable_offset,
        try readU16(table, subtable_offset + 10),
    );
    const class_1_count = try readU16(table, subtable_offset + 12);
    const class_2_count = try readU16(table, subtable_offset + 14);
    const matrix_len = @as(usize, class_1_count) * @as(usize, class_2_count);
    if (matrix_len > max_predecoded_pair_class_matrix) return .{};

    const coverage_start = coverage_classes.items.len;
    const coverage_count = try coverageGlyphCount(table, coverage_offset);
    if (coverage_count > max_predecoded_pair_class_glyphs) return .{};
    for (0..coverage_count) |coverage_index| {
        const glyph = (try coverageGlyphAt(table, coverage_offset, coverage_index)) orelse return error.BadGpos;
        const class = try classValue(table, class_def_1, glyph);
        if (class >= class_1_count) return error.BadGpos;
        try coverage_classes.append(allocator, .{ .glyph = glyph, .class = class });
    }
    const class_2_start = class_entries.items.len;
    if (!(try appendClassDefEntries(table, class_def_2, class_entries, allocator))) {
        coverage_classes.shrinkRetainingCapacity(coverage_start);
        return .{};
    }
    const coverage_entries = coverage_classes.items[coverage_start..];
    const class_2_entries = class_entries.items[class_2_start..];
    const dense_ranges = pairClassDenseRanges(coverage_entries, class_2_entries);
    var dense = false;
    if (dense_ranges) |ranges| {
        if (shouldBuildDensePairClasses(ranges) and
            pairClassEntriesFitDenseRanges(coverage_entries, class_2_entries, ranges))
        {
            const dense_coverage = try allocator.alloc(PairClassEntry, ranges.coverage_len);
            defer allocator.free(dense_coverage);
            for (dense_coverage, 0..) |*entry, index| {
                entry.* = .{
                    .glyph = @intCast(@as(usize, ranges.coverage_base) + index),
                    // Class zero is a valid covered class. Reserve the one
                    // value Class1Count cannot admit as an uncovered sentinel.
                    .class = std.math.maxInt(u16),
                };
            }
            for (coverage_entries) |entry| {
                dense_coverage[entry.glyph - ranges.coverage_base] = entry;
            }
            coverage_classes.shrinkRetainingCapacity(coverage_start);
            try coverage_classes.appendSlice(allocator, dense_coverage);

            const dense_class_2 = try allocator.alloc(PairClassEntry, ranges.class_2_len);
            defer allocator.free(dense_class_2);
            for (dense_class_2, 0..) |*entry, index| {
                entry.* = .{ .glyph = @intCast(@as(usize, ranges.class_2_base) + index), .class = 0 };
            }
            for (class_2_entries) |entry| {
                dense_class_2[entry.glyph - ranges.class_2_base] = entry;
            }
            class_entries.shrinkRetainingCapacity(class_2_start);
            try class_entries.appendSlice(allocator, dense_class_2);
            dense = true;
        }
    }

    const matrix_start = class_matrix.items.len;
    for (0..matrix_len) |record_index| {
        try class_matrix.append(
            allocator,
            try readI16(table, subtable_offset + 16 + record_index * value_size_1),
        );
    }
    return .{
        .kind = if (dense) .format_2_dense_x_advance else .format_2_x_advance,
        .record_start = if (dense) dense_ranges.?.coverage_base else 0,
        .record_len = if (dense) dense_ranges.?.class_2_base else 0,
        .coverage_start = coverage_start,
        .coverage_len = coverage_classes.items.len - coverage_start,
        .class_2_start = class_2_start,
        .class_2_len = class_entries.items.len - class_2_start,
        .class_1_count = class_1_count,
        .class_2_count = class_2_count,
        .matrix_start = matrix_start,
    };
}

const PairClassDenseRanges = struct {
    coverage_base: GlyphId,
    coverage_len: usize,
    class_2_base: GlyphId,
    class_2_len: usize,
};

fn pairClassDenseRanges(coverage: []const PairClassEntry, class_2: []const PairClassEntry) ?PairClassDenseRanges {
    if (coverage.len == 0) return null;
    const coverage_base = coverage[0].glyph;
    const coverage_end = coverage[coverage.len - 1].glyph;
    if (coverage_end < coverage_base) return null;
    const class_2_base = if (class_2.len != 0) class_2[0].glyph else 0;
    const class_2_end = if (class_2.len != 0) class_2[class_2.len - 1].glyph else 0;
    if (class_2_end < class_2_base) return null;
    return .{
        .coverage_base = coverage_base,
        .coverage_len = @as(usize, coverage_end) - coverage_base + 1,
        .class_2_base = class_2_base,
        .class_2_len = if (class_2.len != 0)
            @as(usize, class_2_end) - class_2_base + 1
        else
            0,
    };
}

fn pairClassEntriesFitDenseRanges(
    coverage: []const PairClassEntry,
    class_2: []const PairClassEntry,
    ranges: PairClassDenseRanges,
) bool {
    const coverage_end = @as(usize, ranges.coverage_base) + ranges.coverage_len;
    for (coverage) |entry| {
        if (entry.glyph < ranges.coverage_base or entry.glyph >= coverage_end) return false;
    }
    const class_2_end = @as(usize, ranges.class_2_base) + ranges.class_2_len;
    for (class_2) |entry| {
        if (entry.glyph < ranges.class_2_base or entry.glyph >= class_2_end) return false;
    }
    return true;
}

fn shouldBuildDensePairClasses(ranges: PairClassDenseRanges) bool {
    return ranges.coverage_len <= max_dense_pair_class_entries and
        ranges.class_2_len <= max_dense_pair_class_entries - ranges.coverage_len;
}

fn coverageGlyphCount(table: Table, coverage_offset: usize) GposError!usize {
    return switch (try readU16(table, coverage_offset)) {
        1 => try readU16(table, coverage_offset + 2),
        2 => count: {
            const range_count = try readU16(table, coverage_offset + 2);
            var count: usize = 0;
            for (0..range_count) |range_i| {
                const range_offset = coverage_offset + 4 + range_i * 6;
                const start = try readU16(table, range_offset);
                const end = try readU16(table, range_offset + 2);
                count += @as(usize, end) - @as(usize, start) + 1;
            }
            break :count count;
        },
        else => error.UnsupportedGpos,
    };
}

fn appendClassDefEntries(
    table: Table,
    class_def_offset: usize,
    entries: *std.ArrayList(PairClassEntry),
    allocator: std.mem.Allocator,
) (GposError || std.mem.Allocator.Error)!bool {
    const start_len = entries.items.len;
    switch (try readU16(table, class_def_offset)) {
        1 => {
            const start = try readU16(table, class_def_offset + 2);
            const count = try readU16(table, class_def_offset + 4);
            if (count > max_predecoded_pair_class_glyphs) return false;
            for (0..count) |index| {
                const class = try readU16(table, class_def_offset + 6 + index * 2);
                if (class == 0) continue;
                try entries.append(allocator, .{
                    .glyph = @intCast(@as(usize, start) + index),
                    .class = class,
                });
            }
        },
        2 => {
            const range_count = try readU16(table, class_def_offset + 2);
            for (0..range_count) |range_i| {
                const range_offset = class_def_offset + 4 + range_i * 6;
                const start = try readU16(table, range_offset);
                const end = try readU16(table, range_offset + 2);
                const class = try readU16(table, range_offset + 4);
                if (class == 0) continue;
                const len = @as(usize, end) - @as(usize, start) + 1;
                if (entries.items.len - start_len + len > max_predecoded_pair_class_glyphs) {
                    entries.shrinkRetainingCapacity(start_len);
                    return false;
                }
                for (0..len) |index| {
                    try entries.append(allocator, .{
                        .glyph = @intCast(@as(usize, start) + index),
                        .class = class,
                    });
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
    return true;
}

fn coverageGlyphAt(table: Table, coverage_offset: usize, index: usize) GposError!?GlyphId {
    const format = try readU16(table, coverage_offset);
    return switch (format) {
        1 => glyph: {
            const glyph_count = try readU16(table, coverage_offset + 2);
            if (index >= glyph_count) break :glyph null;
            break :glyph try readU16(table, coverage_offset + 4 + index * 2);
        },
        2 => glyph: {
            const range_count = try readU16(table, coverage_offset + 2);
            for (0..range_count) |range_i| {
                const range_offset = coverage_offset + 4 + range_i * 6;
                const start = try readU16(table, range_offset);
                const end = try readU16(table, range_offset + 2);
                const start_index = try readU16(table, range_offset + 4);
                const len = @as(usize, end) - @as(usize, start) + 1;
                if (index < start_index or index >= @as(usize, start_index) + len) continue;
                break :glyph @intCast(@as(usize, start) + index - @as(usize, start_index));
            }
            break :glyph null;
        },
        else => error.UnsupportedGpos,
    };
}

fn fillFastChainingSinglePosRecords(table: Table, subtable: *ChainingCoverageSubtable) GposError!void {
    if (subtable.pos_count == 0 or subtable.pos_count > ChainingCoverageSubtable.max_fast_records) return;
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16(table, lookup_list_offset);

    var records: [ChainingCoverageSubtable.max_fast_records]FastSinglePosRecord = [_]FastSinglePosRecord{.{}} ** ChainingCoverageSubtable.max_fast_records;
    for (0..subtable.pos_count) |record_i| {
        const record_offset = subtable.records_pos + record_i * 4;
        const sequence_index = try readU16(table, record_offset);
        if (sequence_index >= subtable.input_count) return;
        const lookup_index = try readU16(table, record_offset + 2);
        if (lookup_index >= lookup_count) return;
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2));
        if (try readU16(table, lookup_offset) != 1) return;
        const lookup_flag = try readU16(table, lookup_offset + 2);
        if ((lookup_flag & 0x0010) != 0) return;
        const subtable_count = try readU16(table, lookup_offset + 4);
        if (subtable_count == 0) return;
        records[record_i] = .{
            .sequence_index = sequence_index,
            .lookup_index = lookup_index,
            .lookup_flag = lookup_flag,
        };
    }
    subtable.fast_record_count = subtable.pos_count;
    subtable.fast_records = records;
}

fn buildExtensionChainingClassSubtableAccelerators(table: Table, lookup_offset: usize, lookup_type: u16, subtable_count: u16, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)![]ChainingClassSubtableAccelerator {
    if (lookup_type != 9) return try allocator.alloc(ChainingClassSubtableAccelerator, 0);
    if ((try extensionPositionLookupType(table, lookup_offset, subtable_count)) != 8) return try allocator.alloc(ChainingClassSubtableAccelerator, 0);

    const subtables = try allocator.alloc(ChainingClassSubtableAccelerator, subtable_count);
    @memset(subtables, .{});
    var built_count: usize = 0;
    errdefer {
        deinitChainingClassSubtableAcceleratorContents(allocator, subtables[0..built_count]);
        allocator.free(subtables);
    }

    for (0..subtable_count) |subtable_i| {
        const wrapper_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const payload_offset = try extensionPositionSubtablePayload(table, wrapper_offset, 8);
        const parsed = try buildChainingClassSubtableAccelerator(table, payload_offset, allocator) orelse {
            deinitChainingClassSubtableAcceleratorContents(allocator, subtables[0..built_count]);
            allocator.free(subtables);
            return try allocator.alloc(ChainingClassSubtableAccelerator, 0);
        };
        subtables[subtable_i] = parsed;
        built_count += 1;
    }
    return subtables;
}

fn buildChainingClassSubtableAccelerator(table: Table, subtable_offset: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!?ChainingClassSubtableAccelerator {
    if (try readU16(table, subtable_offset) != 2) return null;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    _ = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const input_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 6));
    const lookahead_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
    const set_count = try readU16(table, subtable_offset + 10);

    var rules = std.ArrayList(class_context.Rule).empty;
    var classes = std.ArrayList(u16).empty;
    var groups = std.ArrayList(class_context.RuleGroup).empty;
    var success = false;
    defer if (!success) {
        rules.deinit(allocator);
        classes.deinit(allocator);
        groups.deinit(allocator);
    };

    var order: u32 = 0;
    for (0..set_count) |set_i| {
        const set_relative = try readU16(table, subtable_offset + 12 + set_i * 2);
        if (set_relative == 0) continue;
        const set_offset = subtable_offset + set_relative;
        const rule_count = try readU16(table, set_offset);
        for (0..rule_count) |rule_i| {
            const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
            var cursor = rule_offset;

            const backtrack_count = try readU16(table, cursor);
            cursor += 2 + @as(usize, backtrack_count) * 2;
            if (backtrack_count != 0) return null;

            const input_count = try readU16(table, cursor);
            cursor += 2;
            if (input_count == 0 or input_count > max_chaining_class_region_glyphs) return null;
            const classes_start = classes.items.len;
            var hash = class_context.sequenceHashEmpty();
            for (1..input_count) |input_i| {
                const class = try readU16(table, cursor + (input_i - 1) * 2);
                try classes.append(allocator, class);
                hash = class_context.sequenceHashAppend(hash, class);
            }
            cursor += (@as(usize, input_count) - 1) * 2;

            const lookahead_count = try readU16(table, cursor);
            cursor += 2;
            if (lookahead_count > max_chaining_class_region_glyphs) return null;

            for (0..lookahead_count) |lookahead_i| {
                const class = try readU16(table, cursor + lookahead_i * 2);
                try classes.append(allocator, class);
                hash = class_context.sequenceHashAppend(hash, class);
            }
            cursor += @as(usize, lookahead_count) * 2;

            const pos_count = try readU16(table, cursor);
            cursor += 2;
            if (pos_count != 1) return null;
            const sequence_index = try readU16(table, cursor);
            if (sequence_index != 0) return null;
            const nested_lookup_index = try readU16(table, cursor + 2);

            try rules.append(allocator, .{
                .class_set = @intCast(set_i),
                .input_count = input_count,
                .lookahead_count = lookahead_count,
                .hash = hash,
                .order = order,
                .lookup_index = nested_lookup_index,
                .classes_start = @intCast(classes_start),
            });
            order += 1;
        }
    }
    if (rules.items.len == 0) return null;

    std.sort.heap(class_context.Rule, rules.items, {}, class_context.ruleLessThan);
    var group_start: usize = 0;
    while (group_start < rules.items.len) {
        const class_set = rules.items[group_start].class_set;
        var group_end = group_start;
        var max_input_count: u16 = 0;
        var max_lookahead_count: u16 = 0;
        while (group_end < rules.items.len and rules.items[group_end].class_set == class_set) : (group_end += 1) {
            max_input_count = @max(max_input_count, rules.items[group_end].input_count);
            max_lookahead_count = @max(max_lookahead_count, rules.items[group_end].lookahead_count);
        }
        try groups.append(allocator, .{
            .class_set = class_set,
            .start = group_start,
            .len = group_end - group_start,
            .max_input_count = max_input_count,
            .max_lookahead_count = max_lookahead_count,
        });
        group_start = group_end;
    }

    const rules_slice = try rules.toOwnedSlice(allocator);
    errdefer allocator.free(rules_slice);
    const classes_slice = try classes.toOwnedSlice(allocator);
    errdefer allocator.free(classes_slice);
    const groups_slice = try groups.toOwnedSlice(allocator);
    success = true;

    return .{
        .subtable_offset = subtable_offset,
        .coverage_offset = coverage_offset,
        .input_class_def = input_class_def,
        .lookahead_class_def = lookahead_class_def,
        .uniform_input_count = if (groups_slice.len == 1) groups_slice[0].max_input_count else 0,
        .rules = rules_slice,
        .classes = classes_slice,
        .groups = groups_slice,
    };
}

fn chainingPositionLookupUsesCoverageOnly(table: Table, lookup_offset: usize, subtable_count: u16) GposError!bool {
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        if (try readU16(table, subtable_offset) != 3) return false;
    }
    return true;
}

fn lookupSubtableCoverageOffset(table: Table, subtable_offset: usize, lookup_type: u16) GposError!?usize {
    switch (lookup_type) {
        1, 2, 3 => return try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
        4, 5, 6 => return try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
        7 => {
            const pos_format = try readU16(table, subtable_offset);
            switch (pos_format) {
                1, 2 => return try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
                3 => {
                    const glyph_count = try readU16(table, subtable_offset + 2);
                    if (glyph_count == 0) return null;
                    return try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 6));
                },
                else => return error.UnsupportedGpos,
            }
        },
        8 => {
            const pos_format = try readU16(table, subtable_offset);
            switch (pos_format) {
                1 => return try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
                2 => return try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
                3 => {
                    var cursor = subtable_offset + 2;
                    const backtrack_count = try readU16(table, cursor);
                    cursor += 2 + backtrack_count * 2;
                    const input_count = try readU16(table, cursor);
                    cursor += 2;
                    if (input_count == 0) return null;
                    return try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, cursor));
                },
                else => return error.UnsupportedGpos,
            }
        },
        9 => {
            const pos_format = try readU16(table, subtable_offset);
            if (pos_format != 1) return error.UnsupportedGpos;
            const extension_lookup_type = try readU16(table, subtable_offset + 2);
            if (extension_lookup_type == 9) return error.UnsupportedGpos;
            const extension_subtable = try checkedExtensionPositionPayloadOffset(table, subtable_offset, try readU32(table, subtable_offset + 4));
            return try lookupSubtableCoverageOffset(table, extension_subtable, extension_lookup_type);
        },
        else => return null,
    }
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var feature_indices = std.ArrayList(FeatureSelection).empty;
    defer feature_indices.deinit(allocator);
    var lookups = std.ArrayList(u16).empty;
    errdefer lookups.deinit(allocator);

    const script_list_offset = try checkedRequiredScriptListOffset(table);
    const feature_list_offset = try checkedRequiredFeatureListOffset(table);

    const script_count = try readU16(table, script_list_offset);
    try validateScriptRecordOrder(table, script_list_offset, script_count);
    const script_offset = try findScriptOffset(table, script_list_offset, script_count, @intFromEnum(options.script_tag)) orelse
        try findScriptOffset(table, script_list_offset, script_count, @intFromEnum(unicode.OpenTypeScriptTag.dflt)) orelse
        0;
    if (script_offset != 0) {
        try collectScriptFeatures(table, script_offset, options.language_tag, &feature_indices, allocator);
    }

    const feature_count = try readU16(table, feature_list_offset);
    try validateFeatureRecordOrder(table, feature_list_offset, feature_count);
    for (feature_indices.items) |selection| {
        const feature_index = selection.index;
        if (feature_index >= feature_count) continue;
        const feature_record = feature_list_offset + 2 + @as(usize, feature_index) * 6;
        const feature_tag = try readU32(table, feature_record);
        // LangSys.ReqFeatureIndex is mandatory for the active language system.
        // Feature overrides model user-controllable optional/default features;
        // they must not suppress required positioning lookups.
        if (!selection.required and !featureEnabled(feature_tag, options.features)) continue;
        const feature_offset = feature_list_offset + try readU16(table, feature_record + 4);
        const lookup_index_count = try readU16(table, feature_offset + 2);
        for (0..lookup_index_count) |i| {
            const lookup_index = try readU16(table, feature_offset + 4 + i * 2);
            if (!try selectedLookupMayApply(table, lookup_index, options)) continue;
            try lookups.append(allocator, lookup_index);
        }
    }

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

fn featureEnabled(feature_tag: u32, overrides: []const unicode.FeatureOverride) bool {
    for (overrides) |override| {
        if (override.tag == feature_tag) return override.enabled;
    }
    return defaultFeatureEnabled(feature_tag);
}

fn defaultFeatureEnabled(feature_tag: u32) bool {
    return feature_tag == unicode.tag("abvm") or
        feature_tag == unicode.tag("blwm") or
        feature_tag == unicode.tag("ccmp") or
        feature_tag == unicode.tag("locl") or
        feature_tag == unicode.tag("mark") or
        feature_tag == unicode.tag("mkmk") or
        feature_tag == unicode.tag("rlig") or
        feature_tag == unicode.tag("calt") or
        feature_tag == unicode.tag("clig") or
        feature_tag == unicode.tag("curs") or
        feature_tag == unicode.tag("dist") or
        feature_tag == unicode.tag("kern") or
        feature_tag == unicode.tag("liga") or
        feature_tag == unicode.tag("rclt");
}

fn findScriptOffset(table: Table, script_list_offset: usize, script_count: u16, script_tag: u32) GposError!?usize {
    for (0..script_count) |script_i| {
        const script_record = script_list_offset + 2 + script_i * 6;
        if (try readU32(table, script_record) != script_tag) continue;
        return script_list_offset + try readU16(table, script_record + 4);
    }
    return null;
}

fn collectScriptFeatures(table: Table, script_offset: usize, language_tag: unicode.OpenTypeLanguageTag, feature_indices: *std.ArrayList(FeatureSelection), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const default_lang_sys_offset = try readU16(table, script_offset);
    const lang_sys_count = try readU16(table, script_offset + 2);
    try validateLangSysRecordOrder(table, script_offset, lang_sys_count);
    if (language_tag != .dflt) {
        if (try findLangSysOffset(table, script_offset, lang_sys_count, @intFromEnum(language_tag))) |lang_sys_offset| {
            try collectLangSysFeatures(table, lang_sys_offset, feature_indices, allocator);
            return;
        }
    }
    if (default_lang_sys_offset != 0) {
        try collectLangSysFeatures(table, script_offset + default_lang_sys_offset, feature_indices, allocator);
    }
}

fn findLangSysOffset(table: Table, script_offset: usize, lang_sys_count: u16, language_tag: u32) GposError!?usize {
    for (0..lang_sys_count) |lang_i| {
        const lang_record = script_offset + 4 + lang_i * 6;
        if (try readU32(table, lang_record) != language_tag) continue;
        return script_offset + try readU16(table, lang_record + 4);
    }
    return null;
}

fn collectLangSysFeatures(table: Table, lang_sys_offset: usize, feature_indices: *std.ArrayList(FeatureSelection), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const required_feature_index = try readU16(table, lang_sys_offset + 2);
    if (required_feature_index != 0xffff) {
        try appendFeatureSelection(feature_indices, allocator, required_feature_index, true);
    }
    const feature_count = try readU16(table, lang_sys_offset + 4);
    for (0..feature_count) |i| {
        const feature_index = try readU16(table, lang_sys_offset + 6 + i * 2);
        try appendFeatureSelection(feature_indices, allocator, feature_index, false);
    }
}

fn appendFeatureSelection(feature_indices: *std.ArrayList(FeatureSelection), allocator: std.mem.Allocator, index: u16, required: bool) std.mem.Allocator.Error!void {
    for (feature_indices.items) |*selection| {
        if (selection.index != index) continue;
        selection.required = selection.required or required;
        return;
    }
    try feature_indices.append(allocator, .{ .index = index, .required = required });
}

fn lookupIndexLessThan(_: void, lhs: u16, rhs: u16) bool {
    return lhs < rhs;
}

fn chainingSubtablePairLessThan(_: void, lhs: ChainingSubtablePair, rhs: ChainingSubtablePair) bool {
    if (lhs.glyph != rhs.glyph) return lhs.glyph < rhs.glyph;
    return lhs.subtable_index < rhs.subtable_index;
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
    const dispatch = try lookupDispatch(lookup_offset, lookup_index, table, options);
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
        try validateMarkFilteringSetIndex(customized_options);
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
    dispatch: LookupDispatch,
) (GposError || std.mem.Allocator.Error)!void {
    const lookup_type = dispatch.lookup_type;
    const lookup_flag = dispatch.lookup_flag;
    const subtable_count = dispatch.subtable_count;
    // Positioning results are appended incrementally, but OpenType lookups are
    // atomic units. Preflight supported direct subtables before collecting any
    // adjustment so malformed later subtables cannot leave partial positioning.
    if (!table.assume_validated) try ensurePositionLookupSubtablesWithin(table, lookup_offset, lookup_type, subtable_count);
    if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
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
        if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.pair_pos_subtables.len == subtable_count and accelerator.pair_pos_records.len != 0) {
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
        if (!table.assume_validated) try ensureExtensionPositionLookupPayloadsWithin(table, lookup_offset, subtable_count);
        const wrapped_type = try resolvedExtensionPositionLookupType(
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
                    if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
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
                    if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
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
        if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.chaining_coverage_only) {
                try collectChainingCoveragePositioningLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options, accelerator);
                return;
            }
        }
    }
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => {}, // SinglePos needs whole-lookup subtable ordering; handled above.
            2 => {}, // PairPos needs whole-lookup subtable ordering; handled above.
            3 => if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
                if (i < accelerator.cursive_subtables.len) {
                    try collectCursiveAdjustmentParsed(table, accelerator.cursive_subtables[i], glyphs, adjustments, allocator, lookup_flag, lookup_options);
                    continue;
                }
                try collectCursiveAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options);
            } else try collectCursiveAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            4 => if (runMayHaveMarkAttachments(glyphs, lookup_options)) {
                if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
                    if (i < accelerator.mark_to_base_subtables.len) {
                        try collectMarkToBaseAdjustmentParsed(table, accelerator.mark_to_base_subtables[i], glyphs, adjustments, allocator, lookup_flag, lookup_options);
                        continue;
                    }
                }
                try collectMarkToBaseAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options);
            },
            5 => if (runMayHaveMarkAttachments(glyphs, lookup_options)) try collectMarkToLigatureAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            6 => if (runMayHaveMarkAttachments(glyphs, lookup_options)) try collectMarkToMarkAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            7 => try collectContextAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            8 => try collectChainingContextAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            9 => try collectExtensionAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            else => {},
        }
    }
}

const LookupDispatch = struct {
    lookup_type: u16,
    lookup_flag: u16,
    subtable_count: u16,
    mark_filtering_set: ?u16,
};

fn lookupDispatch(
    lookup_offset: usize,
    lookup_index: ?u16,
    table: Table,
    options: LookupOptions,
) GposError!LookupDispatch {
    if (table.assume_validated) {
        if (lookupAcceleratorAny(lookup_index, options)) |accelerator| {
            if (accelerator.lookup_offset == lookup_offset and accelerator.lookup_type != 0) {
                return .{
                    .lookup_type = accelerator.lookup_type,
                    .lookup_flag = accelerator.lookup_flag,
                    .subtable_count = accelerator.subtable_count,
                    .mark_filtering_set = accelerator.mark_filtering_set,
                };
            }
        }
    }

    try ensurePositionLookupHeaderWithin(table, lookup_offset);
    const lookup_flag = try readU16(table, lookup_offset + 2);
    const subtable_count = try readU16(table, lookup_offset + 4);
    return .{
        .lookup_type = try readU16(table, lookup_offset),
        .lookup_flag = lookup_flag,
        .subtable_count = subtable_count,
        .mark_filtering_set = if ((lookup_flag & 0x0010) != 0)
            try readU16(table, lookup_offset + 6 + @as(usize, subtable_count) * 2)
        else
            null,
    };
}

fn lookupAccelerator(lookup_index: ?u16, options: LookupOptions) ?*const LookupAccelerator {
    const accelerator = lookupAcceleratorAny(lookup_index, options) orelse return null;
    if (accelerator.coverage_digest.isEmpty()) return null;
    return accelerator;
}

fn lookupAcceleratorAny(lookup_index: ?u16, options: LookupOptions) ?*const LookupAccelerator {
    const accelerators = options.lookup_accelerators orelse return null;
    const index = lookup_index orelse return null;
    if (index >= accelerators.len) return null;
    return &accelerators[index];
}

fn lookupCoverageGroupsMayMatchRun(groups: []const ChainingSubtableGroup, slots: []const u16, glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) bool {
    for (glyphs) |glyph| {
        if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
        if (chainingSubtableGroupForGlyph(groups, slots, glyph) != null) return true;
    }
    return false;
}

fn glyphRunDigest(glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GlyphDigest {
    var digest = GlyphDigest.empty();
    for (glyphs) |glyph| {
        if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
        digest.add(glyph);
    }
    return digest;
}

fn extensionPositionLookupType(table: Table, lookup_offset: usize, subtable_count: u16) GposError!?u16 {
    // ExtensionPos is an addressing wrapper. When one lookup contains only
    // ExtensionPos subtables around the same order-sensitive type, we can keep
    // direct lookup semantics instead of delegating each wrapper over the whole
    // glyph run independently. Mixed wrapped types intentionally fall back to
    // generic per-subtable collection because their interactions are not simple
    // alternatives for one positioning kind.
    var common_type: ?u16 = null;
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        if (try readU16(table, subtable_offset) != 1) return null;
        const wrapped_type = try readU16(table, subtable_offset + 2);
        if (wrapped_type == 9) return error.UnsupportedGpos;
        if (common_type) |existing| {
            if (existing != wrapped_type) return null;
        } else {
            common_type = wrapped_type;
        }
    }
    return common_type;
}

fn resolvedExtensionPositionLookupType(
    table: Table,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
    lookup_index: ?u16,
    options: LookupOptions,
) GposError!?u16 {
    if (table.assume_validated) {
        if (lookupAcceleratorAny(lookup_index, options)) |accelerator| {
            // A cache entry belongs to one exact Lookup header. Any mismatch
            // can indicate a foreign/stale accelerator slice and must retain
            // the authoritative wrapper parser instead of trusting its type.
            if (accelerator.lookup_offset == lookup_offset and
                accelerator.lookup_type == lookup_type and
                accelerator.subtable_count == subtable_count)
            {
                return accelerator.extension_lookup_type;
            }
        }
    }
    return try extensionPositionLookupType(table, lookup_offset, subtable_count);
}

fn extensionPositionSubtablePayload(table: Table, subtable_offset: usize, expected_lookup_type: u16) GposError!usize {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    if (extension_lookup_type != expected_lookup_type) return error.UnsupportedGpos;
    return checkedExtensionPositionPayloadOffset(table, subtable_offset, try readU32(table, subtable_offset + 4));
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
        const extension_subtable = try extensionPositionSubtablePayload(table, subtable_offset, 1);
        try collectSingleAdjustmentSubtable(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options, matched);
    }
}

fn collectExtensionPairAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // PairPos has the same lookup-subtable alternative rule under ExtensionPos
    // as it does directly: the first matching wrapped PairPos handles the pair.
    if (glyphs.len < 2) return;
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) : (first_index += 1) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const extension_subtable = try extensionPositionSubtablePayload(table, subtable_offset, 2);
            if (try collectPairAdjustmentAt(table, extension_subtable, glyphs, first_index, adjustments, allocator, lookup_flag, options)) break;
        }
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
                while (first_index + 1 < glyphs.len) : (first_index += 1) {
                    if (pair_matched[first_index]) continue;
                    if (try collectPairAdjustmentAt(table, extension_subtable, glyphs, first_index, adjustments, allocator, lookup_flag, options)) {
                        pair_matched[first_index] = true;
                    }
                }
            },
            3 => try collectCursiveAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            4 => try collectMarkToBaseAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            5 => try collectMarkToLigatureAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            6 => try collectMarkToMarkAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            7 => try collectContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            8 => try collectChainingContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            else => {},
        }
    }
}

fn collectPairAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // PairPos subtables within one lookup are ordered alternatives for a
    // position. Once a subtable handles a pair, later subtables in the same
    // lookup must not add more deltas for that same first glyph; otherwise
    // split pair data cascades instead of following OpenType lookup ordering.
    if (glyphs.len < 2) return;
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const matched_scratch = try BoolScratch.init(allocator, glyphs.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    const matched = matched_scratch.items;
    @memset(matched, false);

    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const parsed = try parsePairPositionSubtable(table, subtable_offset);
        var first_index: usize = 0;
        while (first_index + 1 < glyphs.len) : (first_index += 1) {
            if (matched[first_index]) continue;
            if (try collectPairAdjustmentAtParsed(table, parsed, glyphs, first_index, adjustments, allocator, lookup_flag, options)) {
                matched[first_index] = true;
            }
        }
    }
}

fn collectPairAdjustmentLookupAccelerated(
    table: Table,
    lookup_offset: usize,
    subtable_count: u16,
    accelerator: *const LookupAccelerator,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    options: LookupOptions,
) (GposError || std.mem.Allocator.Error)!void {
    if (lookup_flag == 0 and options.run_has_default_ignorables == false) {
        return try collectPairAdjustmentLookupAcceleratedImpl(
            true,
            table,
            lookup_offset,
            subtable_count,
            accelerator,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            options,
        );
    }
    return try collectPairAdjustmentLookupAcceleratedImpl(
        false,
        table,
        lookup_offset,
        subtable_count,
        accelerator,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        options,
    );
}

fn collectPairAdjustmentLookupAcceleratedImpl(
    comptime adjacent_pairs: bool,
    table: Table,
    lookup_offset: usize,
    subtable_count: u16,
    accelerator: *const LookupAccelerator,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    options: LookupOptions,
) (GposError || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) : (first_index += 1) {
        if (!adjacent_pairs and lookupIgnoresGlyph(lookup_flag, options, glyphs[first_index])) continue;
        const second_index = if (adjacent_pairs)
            first_index + 1
        else
            nextUnignoredGlyph(glyphs, first_index + 1, lookup_flag, options) orelse continue;
        // PairPos coverage is a necessary and exact first-glyph condition.
        // Accelerator construction already groups those coverages in authored
        // subtable order, so probe only possible alternatives rather than all
        // subtables for every adjacent pair.
        const candidate_subtables = chainingSubtableGroupForGlyph(
            accelerator.coverage_groups,
            accelerator.coverage_group_slots,
            glyphs[first_index],
        ) orelse continue;
        for (candidate_subtables) |subtable_index| {
            const subtable_i: usize = subtable_index;
            if (subtable_i >= subtable_count or subtable_i >= accelerator.pair_pos_subtables.len) return error.BadGpos;
            const pair_accelerator = accelerator.pair_pos_subtables[subtable_i];
            switch (pair_accelerator.kind) {
                .format_1_x_advance => {
                    if (simplePairPosRecord(
                        accelerator.pair_pos_records,
                        pair_accelerator,
                        glyphs[first_index],
                        glyphs[second_index],
                    )) |record| {
                        try appendAdjustment(adjustments, allocator, first_index, .{
                            .index = first_index,
                            .x_advance = record.x_advance,
                        }, true);
                        break;
                    }
                    continue;
                },
                .format_2_x_advance => {
                    const x_advance = acceleratedClassPairAdvance(
                        accelerator,
                        pair_accelerator,
                        glyphs[first_index],
                        glyphs[second_index],
                    ) orelse continue;
                    try appendAdjustment(adjustments, allocator, first_index, .{
                        .index = first_index,
                        .x_advance = x_advance,
                    }, true);
                    break;
                },
                .format_2_dense_x_advance => {
                    const x_advance = acceleratedDenseClassPairAdvance(
                        accelerator,
                        pair_accelerator,
                        glyphs[first_index],
                        glyphs[second_index],
                    ) orelse continue;
                    try appendAdjustment(adjustments, allocator, first_index, .{
                        .index = first_index,
                        .x_advance = x_advance,
                    }, true);
                    break;
                },
                .generic => {},
            }
            const lookup_subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const pair_subtable_offset = if (accelerator.pair_pos_extension)
                try extensionPositionSubtablePayload(table, lookup_subtable_offset, 2)
            else
                lookup_subtable_offset;
            if (try collectPairAdjustmentAt(table, pair_subtable_offset, glyphs, first_index, adjustments, allocator, lookup_flag, options)) break;
        }
    }
}

fn simplePairPosRecord(records: []const PairPosRecord, subtable: PairPosSubtableAccelerator, first: GlyphId, second: GlyphId) ?PairPosRecord {
    const slice = records[subtable.record_start .. subtable.record_start + subtable.record_len];
    var low: usize = 0;
    var high: usize = slice.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const record = slice[mid];
        if (first < record.first or (first == record.first and second < record.second)) {
            high = mid;
        } else if (first > record.first or (first == record.first and second > record.second)) {
            low = mid + 1;
        } else {
            return record;
        }
    }
    return null;
}

fn acceleratedClassPairAdvance(accelerator: *const LookupAccelerator, subtable: PairPosSubtableAccelerator, first: GlyphId, second: GlyphId) ?i16 {
    const class_1 = coveredPairClassForGlyph(
        accelerator.pair_pos_coverage_classes[subtable.coverage_start .. subtable.coverage_start + subtable.coverage_len],
        first,
    ) orelse return null;
    const class_2 = pairClassForGlyph(
        accelerator.pair_pos_class_entries[subtable.class_2_start .. subtable.class_2_start + subtable.class_2_len],
        second,
    );
    if (class_1 >= subtable.class_1_count or class_2 >= subtable.class_2_count) return null;
    return accelerator.pair_pos_class_matrix[
        subtable.matrix_start + @as(usize, class_1) * subtable.class_2_count + class_2
    ];
}

fn acceleratedDenseClassPairAdvance(accelerator: *const LookupAccelerator, subtable: PairPosSubtableAccelerator, first: GlyphId, second: GlyphId) ?i16 {
    const first_index: usize = first;
    if (first_index < subtable.record_start or first_index - subtable.record_start >= subtable.coverage_len) return null;
    const coverage_entry = accelerator.pair_pos_coverage_classes[
        subtable.coverage_start + first_index - subtable.record_start
    ];
    if (coverage_entry.class == std.math.maxInt(u16)) return null;
    const class_1 = coverage_entry.class;

    const second_index: usize = second;
    const class_2 = if (second_index >= subtable.record_len and second_index - subtable.record_len < subtable.class_2_len)
        accelerator.pair_pos_class_entries[
            subtable.class_2_start + second_index - subtable.record_len
        ].class
    else
        0;
    if (class_1 >= subtable.class_1_count or class_2 >= subtable.class_2_count) return null;
    return accelerator.pair_pos_class_matrix[
        subtable.matrix_start + @as(usize, class_1) * subtable.class_2_count + class_2
    ];
}

fn coveredPairClassForGlyph(entries: []const PairClassEntry, glyph: GlyphId) ?u16 {
    var low: usize = 0;
    var high = entries.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (glyph < entries[mid].glyph) {
            high = mid;
        } else if (glyph > entries[mid].glyph) {
            low = mid + 1;
        } else {
            return entries[mid].class;
        }
    }
    return null;
}

fn pairClassForGlyph(entries: []const PairClassEntry, glyph: GlyphId) u16 {
    var low: usize = 0;
    var high = entries.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (glyph < entries[mid].glyph) {
            high = mid;
        } else if (glyph > entries[mid].glyph) {
            low = mid + 1;
        } else {
            return entries[mid].class;
        }
    }
    return 0;
}

fn collectSingleAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // Lookup subtables are tried in order as alternatives for each glyph. Track
    // which input positions have already matched so overlapping SinglePos
    // subtables do not accumulate deltas in the same lookup.
    if (glyphs.len == 0) return;
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const matched_scratch = try BoolScratch.init(allocator, glyphs.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    const matched = matched_scratch.items;
    @memset(matched, false);

    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        try collectSingleAdjustmentSubtable(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options, matched);
    }
}

fn parseSinglePositionSubtable(table: Table, subtable_offset: usize) GposError!SinglePosSubtable {
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const value_format = try readU16(table, subtable_offset + 4);
    const value_size = try valueRecordSize(value_format);
    return switch (pos_format) {
        1 => .{
            .subtable_offset = subtable_offset,
            .pos_format = pos_format,
            .coverage_offset = coverage_offset,
            .value_format = value_format,
            .value_size = value_size,
            .values_pos = subtable_offset + 6,
            .value = try readValueRecord(table, subtable_offset + 6, value_format, subtable_offset),
        },
        2 => .{
            .subtable_offset = subtable_offset,
            .pos_format = pos_format,
            .coverage_offset = coverage_offset,
            .value_format = value_format,
            .value_count = try readU16(table, subtable_offset + 6),
            .value_size = value_size,
            .values_pos = subtable_offset + 8,
        },
        else => error.UnsupportedGpos,
    };
}

fn collectSingleAdjustmentSubtable(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, matched: []bool) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const value_format = try readU16(table, subtable_offset + 4);
    switch (pos_format) {
        1 => {
            const value = try readValueRecord(table, subtable_offset + 6, value_format, subtable_offset);
            for (glyphs, 0..) |glyph, i| {
                if (matched[i]) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph) != null) {
                    try appendAdjustment(adjustments, allocator, i, value, false);
                    matched[i] = true;
                }
            }
        },
        2 => {
            const value_count = try readU16(table, subtable_offset + 6);
            const value_size = try valueRecordSize(value_format);
            for (glyphs, 0..) |glyph, i| {
                if (matched[i]) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph)) |coverage| {
                    if (coverage < value_count) {
                        const value = try readValueRecord(table, subtable_offset + 8 + coverage * value_size, value_format, subtable_offset);
                        try appendAdjustment(adjustments, allocator, i, value, false);
                        matched[i] = true;
                    }
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn collectSingleAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const value_format = try readU16(table, subtable_offset + 4);
    switch (pos_format) {
        1 => {
            const value = try readValueRecord(table, subtable_offset + 6, value_format, subtable_offset);
            for (glyphs, 0..) |glyph, i| {
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph) != null) {
                    try appendAdjustment(adjustments, allocator, i, value, false);
                }
            }
        },
        2 => {
            const value_count = try readU16(table, subtable_offset + 6);
            const value_size = try valueRecordSize(value_format);
            for (glyphs, 0..) |glyph, i| {
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph)) |coverage| {
                    if (coverage < value_count) {
                        const value = try readValueRecord(table, subtable_offset + 8 + coverage * value_size, value_format, subtable_offset);
                        try appendAdjustment(adjustments, allocator, i, value, false);
                    }
                }
            }
        },
        else => return error.UnsupportedGpos,
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

fn glyphInAnyMarkFilteringSet(mark_sets: []const []const GlyphId, glyph: GlyphId) bool {
    for (mark_sets) |set| {
        if (glyphInMarkFilteringSet(set, glyph)) return true;
    }
    return false;
}

fn glyphInMarkFilteringSet(glyphs: []const GlyphId, glyph: GlyphId) bool {
    for (glyphs) |candidate| {
        if (candidate == glyph) return true;
    }
    return false;
}

fn validateMarkFilteringSetIndex(options: LookupOptions) GposError!void {
    const mark_filtering_set_index = options.active_mark_filtering_set orelse return;
    const mark_sets = options.mark_filtering_sets orelse return;
    // A lookup that names a non-existent GDEF MarkGlyphSetsDef entry is
    // malformed. Silently falling back to glyph-class metadata makes
    // positioning depend on missing state instead of the font's declared lookup
    // flag contract.
    if (mark_filtering_set_index >= mark_sets.len) return error.BadGpos;
}

fn runMayHaveMarkAttachments(glyphs: []const GlyphId, options: LookupOptions) bool {
    if (options.run_may_have_mark_attachments) |has_marks| return has_marks;
    const classes = options.glyph_classes orelse return true;
    for (glyphs) |glyph| {
        if (glyph < classes.len and classes[glyph] == 3) return true;
    }
    return false;
}

fn shapeProfileNow(profile: ?*shape_profile_mod.ShapeStageProfile, io: ?std.Io) i128 {
    return if (profile != null) std.Io.Clock.now(.awake, io.?).nanoseconds else 0;
}

fn shapeProfileElapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}

fn validateShapingMetadata(options: LookupOptions, glyph_count: usize) GposError!void {
    for (options.normalized_variation_coords) |coord| {
        if (!std.math.isFinite(coord) or coord < -1 or coord > 1) return error.InvalidShapingInput;
    }
    if (options.glyph_source_indices) |sources| {
        if (sources.len != glyph_count) return error.InvalidShapingInput;
    }
    if (options.glyph_substituted) |substituted| {
        if (substituted.len != glyph_count) return error.InvalidShapingInput;
    }
    if (options.source_codepoints != null and options.glyph_source_indices == null) return error.InvalidShapingInput;
    if (options.ligature_components) |store| {
        if (store.infos.items.len != glyph_count or !store.isValid()) return error.InvalidShapingInput;
    }
}

fn sourceForGlyph(options: LookupOptions, glyph_index: usize) usize {
    const sources = options.glyph_source_indices orelse return glyph_index;
    if (glyph_index >= sources.len) return glyph_index;
    return sources[glyph_index];
}

fn sourceCodepointForGlyph(options: LookupOptions, glyph_index: usize) ?u21 {
    const codepoints = options.source_codepoints orelse return null;
    const source = sourceForGlyph(options, glyph_index);
    if (source >= codepoints.len) return null;
    return codepoints[source];
}

fn glyphWasSubstituted(options: LookupOptions, glyph_index: usize) bool {
    const substituted = options.glyph_substituted orelse return false;
    return glyph_index < substituted.len and substituted[glyph_index];
}

fn markAttachmentSearchSkipsGlyph(options: LookupOptions, glyph_index: usize) bool {
    if (options.run_has_default_ignorables == false) return false;
    const codepoint = sourceCodepointForGlyph(options, glyph_index) orelse return false;
    if (options.visible_variation_selectors and isVariationSelector(codepoint)) return false;
    return unicode.isDefaultIgnorableForShaping(codepoint) and !glyphWasSubstituted(options, glyph_index);
}

fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}

fn matchSkipsGlyph(lookup_flag: u16, options: LookupOptions, glyphs: []const GlyphId, glyph_index: usize) bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[glyph_index])) return true;
    return markAttachmentSearchSkipsGlyph(options, glyph_index);
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
        7 => try collectContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        8 => try collectChainingContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        else => {},
    }
}

fn collectPairAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;
    const parsed = try parsePairPositionSubtable(table, subtable_offset);
    var i: usize = 0;
    while (i + 1 < glyphs.len) : (i += 1) {
        _ = try collectPairAdjustmentAtParsed(table, parsed, glyphs, i, adjustments, allocator, lookup_flag, options);
    }
}

const PairPositionSubtable = struct {
    subtable_offset: usize,
    pos_format: u16,
    coverage_offset: usize,
    value_format_1: u16,
    value_format_2: u16,
    value_size_1: usize,
    value_size_2: usize,
    class_def_1: usize = 0,
    class_def_2: usize = 0,
    class_1_count: u16 = 0,
    class_2_count: u16 = 0,
    matrix_offset: usize = 0,
};

fn parsePairPositionSubtable(table: Table, subtable_offset: usize) GposError!PairPositionSubtable {
    const pos_format = try readU16(table, subtable_offset);
    var parsed = PairPositionSubtable{
        .subtable_offset = subtable_offset,
        .pos_format = pos_format,
        .coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
        .value_format_1 = try readU16(table, subtable_offset + 4),
        .value_format_2 = try readU16(table, subtable_offset + 6),
        .value_size_1 = try valueRecordSize(try readU16(table, subtable_offset + 4)),
        .value_size_2 = try valueRecordSize(try readU16(table, subtable_offset + 6)),
    };
    if (pos_format == 2) {
        parsed.class_def_1 = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
        parsed.class_def_2 = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 10));
        parsed.class_1_count = try readU16(table, subtable_offset + 12);
        parsed.class_2_count = try readU16(table, subtable_offset + 14);
        parsed.matrix_offset = subtable_offset + 16;
    }
    return parsed;
}

fn collectPairAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, first_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const parsed = try parsePairPositionSubtable(table, subtable_offset);
    return try collectPairAdjustmentAtParsed(table, parsed, glyphs, first_index, adjustments, allocator, lookup_flag, options);
}

fn collectPairAdjustmentAtParsed(table: Table, parsed: PairPositionSubtable, glyphs: []const GlyphId, first_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual positioning can invoke a PairPos lookup at a specific matched
    // sequence index. Keep the pair matcher index-addressable so top-level
    // PairPos and nested PosLookupRecord application share the same semantics,
    // including transparent lookup-flag ignored glyphs between the pair.
    if (first_index + 1 >= glyphs.len) return false;
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[first_index])) return false;
    const second_index = nextUnignoredGlyph(glyphs, first_index + 1, lookup_flag, options) orelse return false;

    switch (parsed.pos_format) {
        1 => {
            // PairPos format 1 is a sparse list keyed by the first glyph's
            // coverage index, then searched by the second glyph.
            const pair_set_count = try readU16(table, parsed.subtable_offset + 8);
            const coverage = try coverageIndex(table, parsed.coverage_offset, glyphs[first_index]) orelse return false;
            if (coverage >= pair_set_count) return false;
            const pair_set_offset = parsed.subtable_offset + try readU16(table, parsed.subtable_offset + 10 + coverage * 2);
            const pair_value_count = try readU16(table, pair_set_offset);
            const pair_record = if (table.assume_validated)
                try findValidatedPairValueRecord(table, pair_set_offset, pair_value_count, parsed.value_size_1, parsed.value_size_2, glyphs[second_index]) orelse return false
            else
                try ensurePairValueRecordsWithin(
                    table,
                    pair_set_offset,
                    pair_value_count,
                    parsed.value_format_1,
                    parsed.value_format_2,
                    parsed.value_size_1,
                    parsed.value_size_2,
                    glyphs[second_index],
                ) orelse return false;
            const value_1 = try readValueRecord(table, pair_record + 2, parsed.value_format_1, pair_set_offset);
            const value_2 = try readValueRecord(table, pair_record + 2 + parsed.value_size_1, parsed.value_format_2, pair_set_offset);
            try appendAdjustment(adjustments, allocator, first_index, value_1, true);
            try appendAdjustment(adjustments, allocator, second_index, value_2, false);
            return true;
        },
        2 => {
            // PairPos format 2 maps both glyphs through class definitions and
            // indexes a dense class1 x class2 value matrix.
            const record_size = parsed.value_size_1 + parsed.value_size_2;
            if (try coverageIndex(table, parsed.coverage_offset, glyphs[first_index]) == null) return false;
            const class_1 = try classValue(table, parsed.class_def_1, glyphs[first_index]);
            const class_2 = try classValue(table, parsed.class_def_2, glyphs[second_index]);
            if (class_1 >= parsed.class_1_count or class_2 >= parsed.class_2_count) return false;
            const record_offset = parsed.matrix_offset + (@as(usize, class_1) * parsed.class_2_count + class_2) * record_size;
            const value_1 = try readValueRecord(table, record_offset, parsed.value_format_1, parsed.subtable_offset);
            const value_2 = try readValueRecord(table, record_offset + parsed.value_size_1, parsed.value_format_2, parsed.subtable_offset);
            try appendAdjustment(adjustments, allocator, first_index, value_1, true);
            try appendAdjustment(adjustments, allocator, second_index, value_2, false);
            return true;
        },
        else => return error.UnsupportedGpos,
    }
}

fn nextUnignoredGlyph(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions) ?usize {
    var i = start;
    while (i < glyphs.len) : (i += 1) {
        if (!matchSkipsGlyph(lookup_flag, options, glyphs, i)) return i;
    }
    return null;
}

fn collectForwardUnignoredGlyphs(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions, out: []usize) bool {
    var out_i: usize = 0;
    var glyph_i = start;
    while (glyph_i < glyphs.len and out_i < out.len) : (glyph_i += 1) {
        if (matchSkipsGlyph(lookup_flag, options, glyphs, glyph_i)) continue;
        out[out_i] = glyph_i;
        out_i += 1;
    }
    return out_i == out.len;
}

fn collectBacktrackUnignoredGlyphs(glyphs: []const GlyphId, pos: usize, lookup_flag: u16, options: LookupOptions, out: []usize) bool {
    var out_i: usize = 0;
    var glyph_i = pos;
    while (glyph_i > 0 and out_i < out.len) {
        glyph_i -= 1;
        if (matchSkipsGlyph(lookup_flag, options, glyphs, glyph_i)) continue;
        out[out_i] = glyph_i;
        out_i += 1;
    }
    return out_i == out.len;
}

fn appendAdjustment(adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, index: usize, value: Adjustment, pair_positioned: bool) std.mem.Allocator.Error!void {
    return try appendAdjustmentEx(adjustments, allocator, index, value, .{ .pair_positioned = pair_positioned });
}

const AdjustmentFlags = struct {
    pair_positioned: bool = false,
    attachment_type: AttachmentType = .none,
    attachment_parent_index: ?usize = null,
    x_placement_absolute: bool = false,
    y_placement_absolute: bool = false,
    x_advance_absolute: bool = false,
    y_advance_absolute: bool = false,
};

fn appendAdjustmentEx(adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, index: usize, value: Adjustment, flags: AdjustmentFlags) std.mem.Allocator.Error!void {
    // Multiple positioning subtables can target the same glyph. Accumulate all
    // deltas into one adjustment record per glyph index.
    const has_delta = value.x_advance != 0 or value.x_placement != 0 or value.y_placement != 0 or value.y_advance != 0;
    // PairPos is also a precedence signal for higher-level shaping: when a
    // GPOS pair matches, legacy 'kern' must not be applied to that same pair
    // even if the first ValueRecord is empty and all numeric deltas live on the
    // second glyph. Keep a zero-valued record when metadata carries that fact.
    if (!has_delta and
        !flags.pair_positioned and
        flags.attachment_type == .none and
        !flags.x_advance_absolute and
        !flags.y_advance_absolute) return;
    var existing_i = adjustments.items.len;
    while (existing_i > 0) {
        existing_i -= 1;
        if (adjustments.items[existing_i].index != index) continue;
        const existing = &adjustments.items[existing_i];
        if (flags.x_advance_absolute) {
            existing.x_advance = value.x_advance;
        } else {
            existing.x_advance += value.x_advance;
        }
        if (flags.attachment_type == .mark or flags.x_placement_absolute) {
            existing.x_placement = value.x_placement;
        } else {
            existing.x_placement += value.x_placement;
        }
        if (flags.attachment_type == .mark or flags.y_placement_absolute) {
            existing.y_placement = value.y_placement;
        } else {
            existing.y_placement += value.y_placement;
        }
        if (flags.y_advance_absolute) {
            existing.y_advance = value.y_advance;
        } else {
            existing.y_advance += value.y_advance;
        }
        existing.pair_positioned = existing.pair_positioned or flags.pair_positioned;
        existing.x_advance_absolute = existing.x_advance_absolute or flags.x_advance_absolute;
        existing.y_advance_absolute = existing.y_advance_absolute or flags.y_advance_absolute;
        if (flags.attachment_type != .none) existing.attachment_type = flags.attachment_type;
        if (flags.attachment_parent_index) |parent_index| existing.attachment_parent_index = parent_index;
        return;
    }
    try adjustments.append(allocator, .{
        .index = index,
        .x_advance = value.x_advance,
        .x_placement = value.x_placement,
        .y_placement = value.y_placement,
        .y_advance = value.y_advance,
        .pair_positioned = flags.pair_positioned,
        .attachment_type = flags.attachment_type,
        .attachment_parent_index = flags.attachment_parent_index,
        .x_advance_absolute = flags.x_advance_absolute,
        .y_advance_absolute = flags.y_advance_absolute,
    });
}

test "GPOS keeps zero-valued absolute advance adjustments" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try appendAdjustmentEx(&adjustments, allocator, 2, .{ .index = 2, .x_advance = 0 }, .{ .x_advance_absolute = true });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].x_advance_absolute);
}

test "GPOS absolute advance adjustments replace previous advance" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try appendAdjustmentEx(&adjustments, allocator, 2, .{ .index = 2, .x_advance = 120 }, .{ .x_advance_absolute = true });
    try appendAdjustmentEx(&adjustments, allocator, 2, .{ .index = 2, .x_advance = 240 }, .{ .x_advance_absolute = true });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 240), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].x_advance_absolute);
}

test "GPOS cursive positioning uses previous placement for overlapping joins" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try appendCursiveAdjustments(&adjustments, allocator, 0, 1, .{ .x = 120, .y = 35 }, .{ .x = 120, .y = 185 }, 0, .ltr);
    try appendCursiveAdjustments(&adjustments, allocator, 1, 2, .{ .x = 268, .y = 139 }, .{ .x = 0, .y = 0 }, 0, .ltr);

    var found = false;
    for (adjustments.items) |adjustment| {
        if (adjustment.index != 1) continue;
        found = true;
        try std.testing.expectEqual(@as(i16, 148), adjustment.x_advance);
        try std.testing.expectEqual(@as(i16, -120), adjustment.x_placement);
        try std.testing.expect(adjustment.x_advance_absolute);
    }
    try std.testing.expect(found);
}

test "GPOS cursive positioning reverses previous attachment chains" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try appendCursiveAdjustments(&adjustments, allocator, 0, 1, .{ .x = 120, .y = 44 }, .{ .x = 120, .y = 152 }, 0, .ltr);
    try appendCursiveAdjustments(&adjustments, allocator, 2, 1, .{ .x = 376, .y = 79 }, .{ .x = 239, .y = 152 }, 0, .ltr);

    var old_parent: ?Adjustment = null;
    var middle: ?Adjustment = null;
    for (adjustments.items) |adjustment| {
        if (adjustment.index == 0) old_parent = adjustment;
        if (adjustment.index == 1) middle = adjustment;
    }

    try std.testing.expectEqual(@as(?usize, 1), old_parent.?.attachment_parent_index);
    try std.testing.expectEqual(AttachmentType.cursive, old_parent.?.attachment_type);
    try std.testing.expectEqual(@as(i16, 108), old_parent.?.y_placement);
    try std.testing.expectEqual(@as(?usize, 2), middle.?.attachment_parent_index);
    try std.testing.expectEqual(AttachmentType.cursive, middle.?.attachment_type);
    try std.testing.expectEqual(@as(i16, -73), middle.?.y_placement);
}

test "GPOS later cursive lookup replaces reciprocal attachment" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try appendCursiveAdjustments(&adjustments, allocator, 0, 1, .{ .x = 218, .y = 40 }, .{ .x = 82, .y = 184 }, 0x0001, .ltr);
    try appendCursiveAdjustments(&adjustments, allocator, 0, 1, .{ .x = 218, .y = 40 }, .{ .x = 82, .y = 184 }, 0, .ltr);

    var first: ?Adjustment = null;
    var second: ?Adjustment = null;
    for (adjustments.items) |adjustment| {
        if (adjustment.index == 0) first = adjustment;
        if (adjustment.index == 1) second = adjustment;
    }

    try std.testing.expectEqual(AttachmentType.none, first.?.attachment_type);
    try std.testing.expectEqual(@as(?usize, null), first.?.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 0), first.?.y_placement);
    try std.testing.expectEqual(AttachmentType.cursive, second.?.attachment_type);
    try std.testing.expectEqual(@as(?usize, 0), second.?.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, -144), second.?.y_placement);
}

fn collectCursiveAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const parsed = try parseCursivePositionSubtable(table, subtable_offset);
    try collectCursiveAdjustmentParsed(table, parsed, glyphs, adjustments, allocator, lookup_flag, options);
}

const CursivePositionSubtable = struct {
    subtable_offset: usize,
    coverage_offset: usize,
    entry_exit_count: u16,
    coverage: ?NativeCoverage = null,
};

fn parseCursivePositionSubtable(table: Table, subtable_offset: usize) GposError!CursivePositionSubtable {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    return .{
        .subtable_offset = subtable_offset,
        .coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
        .entry_exit_count = try readU16(table, subtable_offset + 4),
    };
}

fn buildCursivePositionSubtable(table: Table, subtable_offset: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!CursivePositionSubtable {
    var subtable = try parseCursivePositionSubtable(table, subtable_offset);
    errdefer if (subtable.coverage) |coverage| deinitNativeCoverage(allocator, coverage);
    subtable.coverage = try buildNativeCoverage(table, subtable.coverage_offset, allocator);
    return subtable;
}

fn deinitCursivePositionSubtables(allocator: std.mem.Allocator, subtables: []const CursivePositionSubtable) void {
    for (subtables) |subtable| {
        if (subtable.coverage) |coverage| deinitNativeCoverage(allocator, coverage);
    }
    allocator.free(subtables);
}

fn collectCursiveAdjustmentParsed(table: Table, parsed: CursivePositionSubtable, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;

    var previous_covered_position: ?usize = null;
    var previous_coverage_index: usize = 0;
    for (glyphs, 0..) |glyph, i| {
        if (matchSkipsGlyph(lookup_flag, options, glyphs, i)) continue;
        const current_index = (if (parsed.coverage) |coverage|
            coverage.index(glyph)
        else
            try coverageIndex(table, parsed.coverage_offset, glyph)) orelse {
            // A non-ignored, non-covered glyph breaks cursive adjacency. Ignored
            // glyphs are skipped above, matching OpenType LookupFlag semantics.
            previous_covered_position = null;
            continue;
        };
        if (current_index >= parsed.entry_exit_count) {
            previous_covered_position = null;
            continue;
        }

        if (previous_covered_position) |previous_position| {
            const current_record = parsed.subtable_offset + 6 + current_index * 4;
            const previous_record = parsed.subtable_offset + 6 + previous_coverage_index * 4;
            const entry_relative = try readU16(table, current_record);
            const exit_relative = try readU16(table, previous_record + 2);
            if (entry_relative != 0 and exit_relative != 0) {
                const entry = try readAnchor(table, parsed.subtable_offset + entry_relative, options);
                const exit = try readAnchor(table, parsed.subtable_offset + exit_relative, options);
                try appendCursiveAdjustments(adjustments, allocator, previous_position, i, exit, entry, lookup_flag, options.direction);
            }
        }
        previous_covered_position = i;
        previous_coverage_index = current_index;
    }
}

fn collectCursiveAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, target_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecords target exactly one matched input glyph.
    // CursivePos still needs the preceding participating glyph from the real
    // run, but a nested context lookup must not rescan and position every
    // covered cursive join in the run.
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    if (target_index >= glyphs.len) return false;
    const glyph = glyphs[target_index];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const entry_exit_count = try readU16(table, subtable_offset + 4);
    const current_index = try coverageIndex(table, coverage_offset, glyph) orelse return false;
    if (current_index >= entry_exit_count) return false;
    const previous_position = try previousCoveredCursiveGlyph(table, coverage_offset, glyphs, target_index, entry_exit_count, lookup_flag, options) orelse return false;
    const previous_index = (try coverageIndex(table, coverage_offset, glyphs[previous_position])) orelse return false;

    const current_record = subtable_offset + 6 + current_index * 4;
    const previous_record = subtable_offset + 6 + previous_index * 4;
    const entry_relative = try readU16(table, current_record);
    const exit_relative = try readU16(table, previous_record + 2);
    if (entry_relative == 0 or exit_relative == 0) return false;

    const entry = try readAnchor(table, subtable_offset + entry_relative, options);
    const exit = try readAnchor(table, subtable_offset + exit_relative, options);
    try appendCursiveAdjustments(adjustments, allocator, previous_position, target_index, exit, entry, lookup_flag, options.direction);
    return true;
}

fn appendCursiveAdjustments(adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, previous_position: usize, current_position: usize, exit: Anchor, entry: Anchor, lookup_flag: u16, direction: LookupOptions.Direction) std.mem.Allocator.Error!void {
    const previous_placement = currentAdjustmentPlacement(adjustments.items, previous_position);
    const current_placement = currentAdjustmentPlacement(adjustments.items, current_position);
    const right_to_left = (lookup_flag & 0x0001) != 0;
    const child_position = if (right_to_left) previous_position else current_position;
    const parent_position = if (right_to_left) current_position else previous_position;
    try reverseCursiveAttachmentChain(adjustments, allocator, child_position, parent_position);
    clearCursiveAttachmentTo(adjustments.items, parent_position, child_position);

    if (direction == .rtl) {
        const previous_x_delta = -exit.x - previous_placement.x;
        try appendAdjustmentEx(adjustments, allocator, previous_position, .{
            .index = previous_position,
            .x_advance = previous_x_delta,
            .x_placement = -exit.x,
        }, .{
            .attachment_type = if (right_to_left) .cursive else .none,
            .attachment_parent_index = if (right_to_left) current_position else null,
            .x_placement_absolute = true,
        });
        try appendAdjustmentEx(adjustments, allocator, current_position, .{
            .index = current_position,
            .x_advance = entry.x + current_placement.x,
        }, .{ .x_advance_absolute = true });
    } else {
        try appendAdjustmentEx(adjustments, allocator, previous_position, .{
            .index = previous_position,
            .x_advance = exit.x + previous_placement.x,
        }, .{ .x_advance_absolute = true });
        const current_x_delta = -entry.x - current_placement.x;
        try appendAdjustmentEx(adjustments, allocator, current_position, .{
            .index = current_position,
            .x_advance = current_x_delta,
            .x_placement = -entry.x,
        }, .{
            .attachment_type = if (right_to_left) .none else .cursive,
            .attachment_parent_index = if (right_to_left) null else previous_position,
            .x_placement_absolute = true,
        });
    }

    if (right_to_left) {
        try appendAdjustmentEx(adjustments, allocator, previous_position, .{
            .index = previous_position,
            .y_placement = entry.y - exit.y,
        }, .{ .attachment_type = .cursive, .attachment_parent_index = current_position, .y_placement_absolute = true });
    } else {
        try appendAdjustmentEx(adjustments, allocator, current_position, .{
            .index = current_position,
            .y_placement = exit.y - entry.y,
        }, .{ .attachment_type = .cursive, .attachment_parent_index = previous_position, .y_placement_absolute = true });
    }
}

fn clearCursiveAttachmentTo(adjustments: []Adjustment, child_index: usize, parent_index: usize) void {
    var record = findAdjustmentMutable(adjustments, child_index) orelse return;
    if (record.attachment_type != .cursive) return;
    if (record.attachment_parent_index != parent_index) return;
    record.attachment_type = .none;
    record.attachment_parent_index = null;
    record.y_placement = 0;
}

fn reverseCursiveAttachmentChain(adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, child_index: usize, new_parent_index: usize) std.mem.Allocator.Error!void {
    var child_record = findAdjustmentMutable(adjustments.items, child_index) orelse return;
    if (child_record.attachment_type != .cursive) return;
    const old_parent_index = child_record.attachment_parent_index orelse return;
    const child_placement = currentAdjustmentPlacement(adjustments.items, child_index);
    child_record.attachment_type = .none;
    child_record.attachment_parent_index = null;
    if (old_parent_index == new_parent_index) return;

    try reverseCursiveAttachmentChain(adjustments, allocator, old_parent_index, new_parent_index);
    try appendAdjustmentEx(adjustments, allocator, old_parent_index, .{
        .index = old_parent_index,
        .y_placement = -child_placement.y,
    }, .{ .attachment_type = .cursive, .attachment_parent_index = child_index, .y_placement_absolute = true });
}

const AdjustmentPlacement = struct {
    x: i16 = 0,
    y: i16 = 0,
};

fn currentAdjustmentPlacement(adjustments: []const Adjustment, index: usize) AdjustmentPlacement {
    var i = adjustments.len;
    while (i > 0) {
        i -= 1;
        if (adjustments[i].index == index) return .{
            .x = adjustments[i].x_placement,
            .y = adjustments[i].y_placement,
        };
    }
    return .{};
}

fn findAdjustmentMutable(adjustments: []Adjustment, index: usize) ?*Adjustment {
    var i = adjustments.len;
    while (i > 0) {
        i -= 1;
        if (adjustments[i].index == index) return &adjustments[i];
    }
    return null;
}

fn previousCoveredCursiveGlyph(table: Table, coverage_offset: usize, glyphs: []const GlyphId, target_index: usize, entry_exit_count: usize, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = target_index;
    while (i > 0) {
        i -= 1;
        if (matchSkipsGlyph(lookup_flag, options, glyphs, i)) continue;
        const coverage = try coverageIndex(table, coverage_offset, glyphs[i]) orelse return null;
        return if (coverage < entry_exit_count) i else null;
    }
    return null;
}

const MarkToBaseSubtable = struct {
    mark_coverage_offset: usize = 0,
    base_coverage_offset: usize = 0,
    class_count: u16 = 0,
    mark_array_offset: usize = 0,
    base_array_offset: usize = 0,
    mark_coverage: ?NativeCoverage = null,
    base_coverage: ?NativeCoverage = null,
};

const MarkBaseSearchState = struct {
    last_candidate: ?usize = null,
    last_candidate_until: usize = 0,
};

fn parseMarkToBaseSubtable(table: Table, subtable_offset: usize) GposError!MarkToBaseSubtable {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    return .{
        .mark_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2)),
        .base_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 4)),
        .class_count = try readU16(table, subtable_offset + 6),
        .mark_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16(table, subtable_offset + 8)),
        .base_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16(table, subtable_offset + 10)),
    };
}

fn buildMarkToBaseSubtable(table: Table, subtable_offset: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!MarkToBaseSubtable {
    var subtable = try parseMarkToBaseSubtable(table, subtable_offset);
    errdefer {
        if (subtable.mark_coverage) |coverage| deinitNativeCoverage(allocator, coverage);
    }
    subtable.mark_coverage = try buildNativeCoverage(table, subtable.mark_coverage_offset, allocator);
    subtable.base_coverage = try buildNativeCoverage(table, subtable.base_coverage_offset, allocator);
    return subtable;
}

fn buildNativeCoverage(table: Table, coverage_offset: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!NativeCoverage {
    return switch (try readU16(table, coverage_offset)) {
        1 => coverage: {
            const count = try readU16(table, coverage_offset + 2);
            const glyphs = try allocator.alloc(GlyphId, count);
            errdefer allocator.free(glyphs);
            for (glyphs, 0..) |*glyph, i| {
                glyph.* = try readU16(table, coverage_offset + 4 + i * 2);
            }
            break :coverage .{ .glyphs = glyphs };
        },
        2 => coverage: {
            const count = try readU16(table, coverage_offset + 2);
            const ranges = try allocator.alloc(ot_layout.GlyphRangeRecord, count);
            errdefer allocator.free(ranges);
            for (ranges, 0..) |*range, i| {
                const record = coverage_offset + 4 + i * 6;
                range.* = .{
                    .start = try readU16(table, record),
                    .end = try readU16(table, record + 2),
                    .value = try readU16(table, record + 4),
                };
            }
            break :coverage .{ .ranges = ranges };
        },
        else => error.UnsupportedGpos,
    };
}

fn buildNativeCoverageSequence(table: Table, base_offset: usize, offsets_pos: usize, count: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)![]const NativeCoverage {
    const coverages = try allocator.alloc(NativeCoverage, count);
    var built_count: usize = 0;
    errdefer {
        for (coverages[0..built_count]) |coverage| deinitNativeCoverage(allocator, coverage);
        allocator.free(coverages);
    }
    for (coverages, 0..) |*coverage, i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16(table, offsets_pos + i * 2));
        coverage.* = try buildNativeCoverage(table, coverage_offset, allocator);
        built_count += 1;
    }
    return coverages;
}

fn buildChainingCoverageSubtable(table: Table, subtable_offset: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!?ChainingCoverageSubtable {
    var subtable = try parseChainingCoveragePositioningSubtable(table, subtable_offset) orelse return null;
    errdefer deinitChainingCoverageSubtableContents(allocator, subtable);

    subtable.backtrack_coverages = try buildNativeCoverageSequence(table, subtable_offset, subtable.backtrack_offsets_pos, subtable.backtrack_count, allocator);
    subtable.input_coverages = try buildNativeCoverageSequence(table, subtable_offset, subtable.input_offsets_pos, subtable.input_count, allocator);
    subtable.lookahead_coverages = try buildNativeCoverageSequence(table, subtable_offset, subtable.lookahead_offsets_pos, subtable.lookahead_count, allocator);
    try fillFastChainingSinglePosRecords(table, &subtable);
    if (subtable.input_count > 1) {
        const second_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable.input_offsets_pos + 2));
        subtable.second_input_digest = try coverageDigest(table, second_coverage_offset);
    }
    return subtable;
}

fn deinitNativeCoverage(allocator: std.mem.Allocator, coverage: NativeCoverage) void {
    switch (coverage) {
        inline else => |items| allocator.free(items),
    }
}

fn deinitMarkToBaseSubtableContents(allocator: std.mem.Allocator, subtables: []const MarkToBaseSubtable) void {
    for (subtables) |subtable| {
        if (subtable.mark_coverage) |coverage| deinitNativeCoverage(allocator, coverage);
        if (subtable.base_coverage) |coverage| deinitNativeCoverage(allocator, coverage);
    }
}

fn deinitMarkToBaseSubtables(allocator: std.mem.Allocator, subtables: []const MarkToBaseSubtable) void {
    deinitMarkToBaseSubtableContents(allocator, subtables);
    allocator.free(subtables);
}

fn deinitChainingCoverageSubtables(allocator: std.mem.Allocator, subtables: []const ChainingCoverageSubtable) void {
    for (subtables) |subtable| {
        deinitChainingCoverageSubtableContents(allocator, subtable);
    }
    allocator.free(subtables);
}

fn deinitChainingCoverageSubtableContents(allocator: std.mem.Allocator, subtable: ChainingCoverageSubtable) void {
    for (subtable.backtrack_coverages) |coverage| deinitNativeCoverage(allocator, coverage);
    allocator.free(subtable.backtrack_coverages);
    for (subtable.input_coverages) |coverage| deinitNativeCoverage(allocator, coverage);
    allocator.free(subtable.input_coverages);
    for (subtable.lookahead_coverages) |coverage| deinitNativeCoverage(allocator, coverage);
    allocator.free(subtable.lookahead_coverages);
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
    const glyph_coverage = try buildNativeCoverage(table, 0, allocator);
    defer deinitNativeCoverage(allocator, glyph_coverage);
    try std.testing.expectEqual(@as(?usize, 0), glyph_coverage.index(3));
    try std.testing.expectEqual(@as(?usize, 2), glyph_coverage.index(20));
    try std.testing.expectEqual(@as(?usize, null), glyph_coverage.index(9));

    const range_coverage = try buildNativeCoverage(table, 10, allocator);
    defer deinitNativeCoverage(allocator, range_coverage);
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
    try std.testing.expect(try gposCoverageIndicesMatchCached(
        table,
        0,
        &glyphs,
        &.{ 1, 2 },
        subtable.input_offsets_pos,
        subtable.input_coverages,
        0,
    ));
}

fn collectMarkToBaseAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const subtable = try parseMarkToBaseSubtable(table, subtable_offset);
    return try collectMarkToBaseAdjustmentParsed(table, subtable, glyphs, adjustments, allocator, lookup_flag, options);
}

fn collectMarkToBaseAdjustmentParsed(table: Table, subtable: MarkToBaseSubtable, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (subtable.class_count == 0 or glyphs.len < 2) return;

    const attached_marks = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(attached_marks);
    @memset(attached_marks, false);

    var search_state = MarkBaseSearchState{};
    for (0..glyphs.len) |i| {
        if (try collectMarkToBaseAdjustmentAtParsed(table, subtable, glyphs, i, adjustments, allocator, lookup_flag, options, attached_marks, &search_state)) {
            attached_marks[i] = true;
        }
    }
}

fn collectMarkToBaseAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, mark_position: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, attached_marks: []const bool) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecord application names one glyph in the matched
    // input sequence. MarkBasePos still needs the surrounding run to find the
    // preceding base, but it must attach only that named mark instead of
    // rescanning and positioning every mark covered by the nested lookup.
    const subtable = try parseMarkToBaseSubtable(table, subtable_offset);
    return try collectMarkToBaseAdjustmentAtParsed(table, subtable, glyphs, mark_position, adjustments, allocator, lookup_flag, options, attached_marks, null);
}

fn collectMarkToBaseAdjustmentAtParsed(table: Table, subtable: MarkToBaseSubtable, glyphs: []const GlyphId, mark_position: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, attached_marks: []const bool, search_state: ?*MarkBaseSearchState) (GposError || std.mem.Allocator.Error)!bool {
    if (mark_position >= glyphs.len) return false;
    const glyph = glyphs[mark_position];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;
    if (subtable.class_count == 0 or glyphs.len < 2) return false;

    const mark_index = if (subtable.mark_coverage) |coverage|
        coverage.index(glyph) orelse return false
    else
        try coverageIndex(table, subtable.mark_coverage_offset, glyph) orelse return false;
    const base_position = (if (search_state) |state|
        try previousCoveredBaseGlyphParsedCached(table, subtable, glyphs, mark_position, attached_marks, lookup_flag, options, state)
    else
        try previousCoveredBaseGlyphParsed(table, subtable, glyphs, mark_position, attached_marks, lookup_flag, options)) orelse return false;
    const base_glyph = glyphs[base_position];
    const base_index = if (subtable.base_coverage) |coverage|
        coverage.index(base_glyph) orelse return false
    else
        try coverageIndex(table, subtable.base_coverage_offset, base_glyph) orelse return false;
    const mark_record_offset = subtable.mark_array_offset + 2 + mark_index * 4;
    const mark_class = try readU16(table, mark_record_offset);
    if (mark_class >= subtable.class_count) return false;
    const mark_anchor_offset = try checkedRequiredPositionOffset(table, subtable.mark_array_offset, try readU16(table, mark_record_offset + 2));
    const base_anchor_record = subtable.base_array_offset + 2 + (base_index * subtable.class_count + mark_class) * 2;
    const base_anchor_relative = try readU16(table, base_anchor_record);
    if (base_anchor_relative == 0) return false;
    const base_anchor_offset = subtable.base_array_offset + base_anchor_relative;
    const mark_anchor = try readAnchor(table, mark_anchor_offset, options);
    const base_anchor = try readAnchor(table, base_anchor_offset, options);
    try appendAdjustmentEx(adjustments, allocator, mark_position, .{
        .index = mark_position,
        .x_placement = base_anchor.x - mark_anchor.x,
        .y_placement = base_anchor.y - mark_anchor.y,
    }, .{ .attachment_type = .mark, .attachment_parent_index = base_position });
    return true;
}

fn previousCoveredBaseGlyphParsedCached(table: Table, subtable: MarkToBaseSubtable, glyphs: []const GlyphId, mark_index: usize, attached_marks: []const bool, lookup_flag: u16, options: LookupOptions, state: *MarkBaseSearchState) GposError!?usize {
    if (state.last_candidate_until > mark_index) state.* = .{};

    var candidate = state.last_candidate;
    var i = mark_index;
    while (i > state.last_candidate_until) {
        i -= 1;
        if (try markBaseSearchSkipsGlyphParsed(table, subtable, glyphs, i, attached_marks, lookup_flag, options)) continue;
        candidate = i;
        break;
    }

    state.last_candidate = candidate;
    state.last_candidate_until = mark_index;
    return candidate;
}

fn previousCoveredBaseGlyphParsed(table: Table, subtable: MarkToBaseSubtable, glyphs: []const GlyphId, mark_index: usize, attached_marks: []const bool, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = mark_index;
    while (i > 0) {
        i -= 1;
        if (try markBaseSearchSkipsGlyphParsed(table, subtable, glyphs, i, attached_marks, lookup_flag, options)) continue;
        return i;
    }
    return null;
}

fn markBaseSearchSkipsGlyphParsed(table: Table, subtable: MarkToBaseSubtable, glyphs: []const GlyphId, index: usize, attached_marks: []const bool, lookup_flag: u16, options: LookupOptions) GposError!bool {
    if (index < attached_marks.len and attached_marks[index]) return true;
    if (matchSkipsGlyph(lookup_flag, options, glyphs, index)) return true;

    // MarkBasePos attaches to the nearest previous participating base. A
    // non-mark glyph that is not in BaseCoverage is a real blocker for this
    // subtable; HarfBuzz records that nearest non-mark and lets the subtable
    // fail its BaseCoverage check rather than walking back to an older covered
    // base. Marks remain transparent for stacked-mark clusters; use GDEF
    // classes when present and fall back to this subtable's MarkCoverage for
    // minimal fonts that omit GDEF.
    const base_covered = if (subtable.base_coverage) |coverage|
        coverage.index(glyphs[index]) != null
    else
        try coverageIndex(table, subtable.base_coverage_offset, glyphs[index]) != null;
    if (base_covered) return false;
    return try markAttachmentSearchSkipsNonCoveredGlyphParsed(table, subtable, glyphs, index, options);
}

fn previousUnignoredCoveredGlyph(table: Table, coverage_offset: usize, glyphs: []const GlyphId, mark_index: usize, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = mark_index;
    while (i > 0) {
        i -= 1;
        // Mark attachment lookups test the previous glyph after applying the
        // lookup flag. Ignored glyphs are transparent for this adjacency check;
        // the first non-ignored glyph either matches the target coverage or
        // blocks the attachment.
        if (matchSkipsGlyph(lookup_flag, options, glyphs, i)) continue;
        return if (try coverageIndex(table, coverage_offset, glyphs[i]) != null) i else null;
    }
    return null;
}

fn collectContextAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    switch (pos_format) {
        1 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
            const rule_set_count = try readU16(table, subtable_offset + 4);
            var pos: usize = 0;
            while (pos < glyphs.len) : (pos += 1) {
                if (matchSkipsGlyph(lookup_flag, options, glyphs, pos)) continue;
                const coverage = try coverageIndex(table, coverage_offset, glyphs[pos]) orelse continue;
                if (coverage >= rule_set_count) continue;
                const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
                if (set_relative == 0) continue;
                if (try collectPositionRuleSet(table, subtable_offset + set_relative, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
                    pos += 1;
                }
            }
        },
        2 => try collectClassPositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        3 => try collectCoveragePositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        else => return error.UnsupportedGpos,
    }
}

fn collectContextAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (pos >= glyphs.len) return false;
    const pos_format = try readU16(table, subtable_offset);
    switch (pos_format) {
        1 => {
            if (matchSkipsGlyph(lookup_flag, options, glyphs, pos)) return false;
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
            const coverage = try coverageIndex(table, coverage_offset, glyphs[pos]) orelse return false;
            const rule_set_count = try readU16(table, subtable_offset + 4);
            if (coverage >= rule_set_count) return false;
            const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
            if (set_relative == 0) return false;
            return try collectPositionRuleSet(table, subtable_offset + set_relative, glyphs, pos, adjustments, allocator, lookup_flag, options);
        },
        2 => return try collectClassPositioningAt(table, subtable_offset, glyphs, pos, adjustments, allocator, lookup_flag, options),
        3 => return try collectCoveragePositioningAt(table, subtable_offset, glyphs, pos, adjustments, allocator, lookup_flag, options),
        else => return error.UnsupportedGpos,
    }
}

fn collectClassPositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const class_def_offset = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const class_set_count = try readU16(table, subtable_offset + 6);
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (matchSkipsGlyph(lookup_flag, options, glyphs, pos)) continue;
        if (try coverageIndex(table, coverage_offset, glyphs[pos]) == null) continue;
        const class = try classValue(table, class_def_offset, glyphs[pos]);
        if (class >= class_set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 8 + @as(usize, class) * 2);
        if (set_relative == 0) continue;
        if (try collectClassPositionRuleSet(table, subtable_offset + set_relative, class_def_offset, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn collectClassPositioningAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (pos >= glyphs.len) return false;
    if (matchSkipsGlyph(lookup_flag, options, glyphs, pos)) return false;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    if (try coverageIndex(table, coverage_offset, glyphs[pos]) == null) return false;
    const class_def_offset = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const class_set_count = try readU16(table, subtable_offset + 6);
    const class = try classValue(table, class_def_offset, glyphs[pos]);
    if (class >= class_set_count) return false;
    const set_relative = try readU16(table, subtable_offset + 8 + @as(usize, class) * 2);
    if (set_relative == 0) return false;
    return try collectClassPositionRuleSet(table, subtable_offset + set_relative, class_def_offset, glyphs, pos, adjustments, allocator, lookup_flag, options);
}

fn collectCoveragePositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const glyph_count = try readU16(table, subtable_offset + 2);
    const pos_count = try readU16(table, subtable_offset + 4);
    if (glyph_count == 0) return;
    const coverage_offsets_pos = subtable_offset + 6;
    const records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (0..glyph_count) |i| {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, coverage_offsets_pos + i * 2));
            if (!try contextCoverageContains(table, coverage_offset, glyphs[input_indices_buf[i]])) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator, options);
        pos += glyph_count - 1;
    }
}

fn collectCoveragePositioningAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (pos >= glyphs.len) return false;
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) return false;
    const glyph_count = try readU16(table, subtable_offset + 2);
    if (glyph_count == 0) return false;
    var input_indices_buf: [64]usize = undefined;
    if (glyph_count > input_indices_buf.len) return error.UnsupportedGpos;
    if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) return false;

    const coverage_offsets_pos = subtable_offset + 6;
    for (0..glyph_count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, coverage_offsets_pos + i * 2));
        if (!try contextCoverageContains(table, coverage_offset, glyphs[input_indices_buf[i]])) return false;
    }
    const pos_count = try readU16(table, subtable_offset + 4);
    const records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
    try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator, options);
    return true;
}

fn collectChainingContextAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    switch (pos_format) {
        1 => try collectChainingGlyphPositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        2 => try collectChainingClassPositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        3 => try collectChainingCoveragePositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        else => return error.UnsupportedGpos,
    }
}

fn collectChainingContextAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (pos >= glyphs.len) return false;
    const pos_format = try readU16(table, subtable_offset);
    switch (pos_format) {
        1 => return try collectChainingGlyphPositioningAt(table, subtable_offset, glyphs, pos, adjustments, allocator, lookup_flag, options),
        2 => return try collectChainingClassPositioningAt(table, subtable_offset, glyphs, pos, adjustments, allocator, lookup_flag, options),
        3 => {
            const parsed = try parseChainingCoveragePositioningSubtable(table, subtable_offset) orelse return false;
            return (try collectChainingCoveragePositioningAt(table, parsed, glyphs, pos, adjustments, allocator, lookup_flag, options)).matched;
        },
        else => return error.UnsupportedGpos,
    }
}

fn parseChainingCoveragePositioningSubtable(table: Table, subtable_offset: usize) GposError!?ChainingCoverageSubtable {
    if (try readU16(table, subtable_offset) != 3) return null;
    var cursor = subtable_offset + 2;
    const backtrack_count = try readU16(table, cursor);
    cursor += 2;
    const backtrack_offsets_pos = cursor;
    cursor += backtrack_count * 2;

    const input_count = try readU16(table, cursor);
    cursor += 2;
    if (input_count == 0) return null;
    const input_offsets_pos = cursor;
    cursor += input_count * 2;

    const lookahead_count = try readU16(table, cursor);
    cursor += 2;
    const lookahead_offsets_pos = cursor;
    cursor += lookahead_count * 2;

    const pos_count = try readU16(table, cursor);
    cursor += 2;
    return .{
        .subtable_offset = subtable_offset,
        .backtrack_offsets_pos = backtrack_offsets_pos,
        .backtrack_count = backtrack_count,
        .input_offsets_pos = input_offsets_pos,
        .input_count = input_count,
        .lookahead_offsets_pos = lookahead_offsets_pos,
        .lookahead_count = lookahead_count,
        .records_pos = cursor,
        .pos_count = pos_count,
    };
}

fn collectChainingGlyphPositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const chain_set_count = try readU16(table, subtable_offset + 4);
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        const coverage = try coverageIndex(table, coverage_offset, glyphs[pos]) orelse continue;
        if (coverage >= chain_set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
        if (set_relative == 0) continue;
        if (try collectChainingGlyphRuleSet(table, subtable_offset + set_relative, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn collectChainingGlyphPositioningAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (pos >= glyphs.len) return false;
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) return false;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const coverage = try coverageIndex(table, coverage_offset, glyphs[pos]) orelse return false;
    const chain_set_count = try readU16(table, subtable_offset + 4);
    if (coverage >= chain_set_count) return false;
    const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
    if (set_relative == 0) return false;
    return try collectChainingGlyphRuleSet(table, subtable_offset + set_relative, glyphs, pos, adjustments, allocator, lookup_flag, options);
}

fn collectChainingGlyphRuleSet(table: Table, set_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;
        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGpos;
        if (!collectBacktrackUnignoredGlyphs(glyphs, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count])) continue;
        var matched = true;
        for (0..backtrack_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs[backtrack_indices_buf[i]] != expected) {
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
        if (input_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..input_count])) continue;
        for (1..input_count) |i| {
            const expected = try readU16(table, cursor + (i - 1) * 2);
            if (glyphs[input_indices_buf[i]] != expected) {
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
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count])) continue;
        for (0..lookahead_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs[lookahead_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += lookahead_count * 2;

        const pos_count = try readU16(table, cursor);
        cursor += 2;
        try collectPositionRecordsMapped(table, cursor, pos_count, input_indices_buf[0..input_count], glyphs, adjustments, allocator, options);
        return true;
    }
    return false;
}

fn collectChainingClassPositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const backtrack_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const input_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 6));
    const lookahead_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
    const set_count = try readU16(table, subtable_offset + 10);
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        if (try coverageIndex(table, coverage_offset, glyphs[pos]) == null) continue;
        const input_class = try classValue(table, input_class_def, glyphs[pos]);
        if (input_class >= set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 12 + @as(usize, input_class) * 2);
        if (set_relative == 0) continue;
        if (try collectChainingClassRuleSet(table, subtable_offset + set_relative, backtrack_class_def, input_class_def, lookahead_class_def, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn collectChainingClassPositioningAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (pos >= glyphs.len) return false;
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) return false;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    if (try coverageIndex(table, coverage_offset, glyphs[pos]) == null) return false;
    const input_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 6));
    const input_class = try classValue(table, input_class_def, glyphs[pos]);
    const set_count = try readU16(table, subtable_offset + 10);
    if (input_class >= set_count) return false;
    const set_relative = try readU16(table, subtable_offset + 12 + @as(usize, input_class) * 2);
    if (set_relative == 0) return false;
    const backtrack_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const lookahead_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
    return try collectChainingClassRuleSet(table, subtable_offset + set_relative, backtrack_class_def, input_class_def, lookahead_class_def, glyphs, pos, adjustments, allocator, lookup_flag, options);
}

const ChainingClassMatchContext = struct {
    table: Table,
    backtrack_class_def: usize,
    input_class_def: usize,
    lookahead_class_def: usize,
    lookup_flag: u16,
    options: LookupOptions,

    fn classValueForRole(self: *ChainingClassMatchContext, role: class_context.ClassRole, glyph: GlyphId) GposError!u16 {
        const class_def = switch (role) {
            .backtrack => self.backtrack_class_def,
            .input => self.input_class_def,
            .lookahead => self.lookahead_class_def,
        };
        return try classValue(self.table, class_def, glyph);
    }

    fn skipsGlyph(self: *ChainingClassMatchContext, glyphs: []const GlyphId, glyph_index: usize) bool {
        return matchSkipsGlyph(self.lookup_flag, self.options, glyphs, glyph_index);
    }
};

const max_chaining_class_region_glyphs = 64;
const ChainingClassMatchWindow = class_context.MatchWindow(
    ChainingClassMatchContext,
    GposError,
    error.UnsupportedGpos,
    max_chaining_class_region_glyphs,
    ChainingClassMatchContext.classValueForRole,
    ChainingClassMatchContext.skipsGlyph,
);

fn chainingClassMatchContext(table: Table, backtrack_class_def: usize, input_class_def: usize, lookahead_class_def: usize, lookup_flag: u16, options: LookupOptions) ChainingClassMatchContext {
    return .{
        .table = table,
        .backtrack_class_def = backtrack_class_def,
        .input_class_def = input_class_def,
        .lookahead_class_def = lookahead_class_def,
        .lookup_flag = lookup_flag,
        .options = options,
    };
}

fn collectChainingClassRuleSet(table: Table, set_offset: usize, backtrack_class_def: usize, input_class_def: usize, lookahead_class_def: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, set_offset);
    var match_context = chainingClassMatchContext(table, backtrack_class_def, input_class_def, lookahead_class_def, lookup_flag, options);
    var window = ChainingClassMatchWindow.init(&match_context, glyphs, pos);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;

        // Chaining positioning checks the same three regions as GSUB chaining:
        // backtrack, input, and lookahead. Only the input region receives
        // position records.
        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        if (backtrack_count > max_chaining_class_region_glyphs) return error.UnsupportedGpos;
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
        if (input_count > max_chaining_class_region_glyphs) return error.UnsupportedGpos;
        const input_indices = (try window.inputIndices(input_count)) orelse continue;
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
        if (lookahead_count > max_chaining_class_region_glyphs) return error.UnsupportedGpos;
        const lookahead_forward_start = @as(usize, input_count);
        if (!try window.ensureForwardCount(lookahead_forward_start + @as(usize, lookahead_count))) continue;
        for (0..lookahead_count) |i| {
            const expected_class = try readU16(table, cursor + i * 2);
            const actual_class = (try window.lookaheadClassAt(lookahead_forward_start + i)) orelse {
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

        const pos_count = try readU16(table, cursor);
        cursor += 2;
        try collectPositionRecordsMapped(table, cursor, pos_count, input_indices, glyphs, adjustments, allocator, options);
        return true;
    }
    return false;
}

fn collectChainingCoveragePositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const parsed = try parseChainingCoveragePositioningSubtable(table, subtable_offset) orelse return;

    var pos: usize = 0;
    while (pos < glyphs.len) {
        const result = try collectChainingCoveragePositioningAt(table, parsed, glyphs, pos, adjustments, allocator, lookup_flag, options);
        pos = if (result.matched) @max(pos + 1, result.next_pos) else pos + 1;
    }
}

fn collectChainingCoveragePositioningLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GposError || std.mem.Allocator.Error)!void {
    // Three digest bit-tests amortize over paragraph-sized runs by avoiding
    // exact group probes for most glyphs. Word-sized runs usually hit quickly,
    // so keep them on the old direct path without the extra filter.
    if (chainingLookupUsesGlyphDigest(glyphs.len)) {
        return try collectChainingCoveragePositioningLookupImpl(true, table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, options, accelerator);
    }
    return try collectChainingCoveragePositioningLookupImpl(false, table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, options, accelerator);
}

fn collectChainingCoveragePositioningLookupImpl(comptime use_glyph_digest: bool, table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GposError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        if (use_glyph_digest and !accelerator.coverage_digest.mayHave(glyphs[pos])) continue;
        const grouped_subtables = chainingSubtableGroupForGlyph(accelerator.chaining_groups, accelerator.chaining_group_slots, glyphs[pos]) orelse continue;
        const second_glyph_index = nextUnignoredGlyph(glyphs, pos + 1, lookup_flag, options);
        for (grouped_subtables) |subtable_i| {
            const parsed = if (subtable_i < accelerator.chaining_subtables.len and accelerator.chaining_subtables[subtable_i].input_count != 0)
                accelerator.chaining_subtables[subtable_i]
            else
                try parseChainingCoveragePositioningSubtable(table, lookup_offset + try readU16(table, lookup_offset + 6 + @as(usize, subtable_i) * 2)) orelse continue;
            if (parsed.input_count > 1) {
                const index = second_glyph_index orelse continue;
                if (!parsed.second_input_digest.mayHave(glyphs[index])) continue;
            }
            const result = try collectAcceleratedChainingCoveragePositioningAt(table, parsed, glyphs, pos, adjustments, allocator, lookup_flag, options);
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
        _ = subtable_count;
    }
}

fn collectNestedChainingCoveragePositioningAt(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GposError || std.mem.Allocator.Error)!bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) return false;
    if (chainingLookupUsesGlyphDigest(glyphs.len) and
        !accelerator.coverage_digest.mayHave(glyphs[pos])) return false;
    const grouped_subtables = chainingSubtableGroupForGlyph(accelerator.chaining_groups, accelerator.chaining_group_slots, glyphs[pos]) orelse return false;
    const second_glyph_index = nextUnignoredGlyph(glyphs, pos + 1, lookup_flag, options);
    for (grouped_subtables) |subtable_i| {
        if (subtable_i >= subtable_count) return error.BadGpos;
        const parsed = if (subtable_i < accelerator.chaining_subtables.len and accelerator.chaining_subtables[subtable_i].input_count != 0)
            accelerator.chaining_subtables[subtable_i]
        else
            try parseChainingCoveragePositioningSubtable(table, lookup_offset + try readU16(table, lookup_offset + 6 + @as(usize, subtable_i) * 2)) orelse continue;
        if (parsed.input_count > 1) {
            const index = second_glyph_index orelse continue;
            if (!parsed.second_input_digest.mayHave(glyphs[index])) continue;
        }
        const result = try collectAcceleratedChainingCoveragePositioningAt(table, parsed, glyphs, pos, adjustments, allocator, lookup_flag, options);
        if (result.matched) return true;
    }
    return false;
}

fn collectNestedExtensionChainingClassPositioningAt(table: Table, subtable_count: u16, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GposError || std.mem.Allocator.Error)!bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) return false;
    var subtable_i: usize = 0;
    while (subtable_i < subtable_count and subtable_i < accelerator.chaining_class_subtables.len) : (subtable_i += 1) {
        const subtable = accelerator.chaining_class_subtables[subtable_i];
        if (subtable.rules.len == 0) continue;
        if (try collectAcceleratedChainingClassPositioningAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options)) return true;
    }
    return false;
}

fn collectExtensionChainingClassPositioningLookup(table: Table, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, accelerator: *const LookupAccelerator) (GposError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        var subtable_i: usize = 0;
        while (subtable_i < subtable_count and subtable_i < accelerator.chaining_class_subtables.len) : (subtable_i += 1) {
            const subtable = accelerator.chaining_class_subtables[subtable_i];
            if (subtable.rules.len == 0) continue;
            const result = try collectAcceleratedChainingClassPositioningAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options);
            if (result) {
                next_pos = pos + 1;
                break;
            }
        }
    }
}

fn collectAcceleratedChainingClassPositioningAt(table: Table, subtable: ChainingClassSubtableAccelerator, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (try coverageIndex(table, subtable.coverage_offset, glyphs[pos]) == null) return false;
    const input_class = try classValue(table, subtable.input_class_def, glyphs[pos]);
    const group = class_context.groupForClass(subtable.groups, input_class) orelse return false;
    if (group.max_input_count == 0 or group.max_input_count > max_chaining_class_region_glyphs or group.max_lookahead_count > max_chaining_class_region_glyphs) return error.UnsupportedGpos;

    var input_indices: [max_chaining_class_region_glyphs]usize = undefined;
    if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices[0..group.max_input_count])) return false;
    var input_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    for (1..group.max_input_count) |input_i| {
        input_classes[input_i - 1] = try classValue(table, subtable.input_class_def, glyphs[input_indices[input_i]]);
    }

    var lookahead_classes: [max_chaining_class_region_glyphs]u16 = undefined;
    var lookahead_count: usize = 0;
    var glyph_i = input_indices[group.max_input_count - 1] + 1;
    while (glyph_i < glyphs.len and lookahead_count < group.max_lookahead_count) : (glyph_i += 1) {
        if (matchSkipsGlyph(lookup_flag, options, glyphs, glyph_i)) continue;
        lookahead_classes[lookahead_count] = try classValue(table, subtable.lookahead_class_def, glyphs[glyph_i]);
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
        try collectNestedAdjustment(table, glyphs, matched_inputs[0], rule.lookup_index, adjustments, allocator, options);
        return true;
    }
    return false;
}

fn collectExtensionChainingCoveragePositioningLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    var pos: usize = 0;
    while (pos < glyphs.len) {
        var next_pos = pos + 1;
        defer pos = next_pos;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const extension_subtable = try extensionPositionSubtablePayload(table, subtable_offset, 8);
            const parsed = try parseChainingCoveragePositioningSubtable(table, extension_subtable) orelse return error.UnsupportedGpos;
            const result = try collectChainingCoveragePositioningAt(table, parsed, glyphs, pos, adjustments, allocator, lookup_flag, options);
            if (result.matched) {
                next_pos = @max(next_pos, result.next_pos);
                break;
            }
        }
    }
}

fn collectChainingCoveragePositioningAt(table: Table, subtable: ChainingCoverageSubtable, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!PositionContextResult {
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) return .{};
    if (table.assume_validated and subtable.input_count == 1 and subtable.backtrack_count == 0 and subtable.lookahead_count == 1 and subtable.pos_count == 1) {
        return try collectSimpleChainingCoveragePositioningAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options);
    }
    var input_indices_buf: [64]usize = undefined;
    if (subtable.input_count > input_indices_buf.len) return error.UnsupportedGpos;
    if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..subtable.input_count])) return .{};
    if (!try gposCoverageIndicesMatchCached(table, subtable.subtable_offset, glyphs, input_indices_buf[0..subtable.input_count], subtable.input_offsets_pos, subtable.input_coverages, 0)) return .{};
    var backtrack_indices_buf: [64]usize = undefined;
    if (subtable.backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGpos;
    if (!collectBacktrackUnignoredGlyphs(glyphs, pos, lookup_flag, options, backtrack_indices_buf[0..subtable.backtrack_count])) return .{};
    const lookahead_start = input_indices_buf[subtable.input_count - 1] + 1;
    var lookahead_indices_buf: [64]usize = undefined;
    if (subtable.lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGpos;
    if (!collectForwardUnignoredGlyphs(glyphs, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..subtable.lookahead_count])) return .{};
    if (!try gposCoverageIndicesMatchCached(table, subtable.subtable_offset, glyphs, backtrack_indices_buf[0..subtable.backtrack_count], subtable.backtrack_offsets_pos, subtable.backtrack_coverages, 0)) return .{};
    if (!try gposCoverageIndicesMatchCached(table, subtable.subtable_offset, glyphs, lookahead_indices_buf[0..subtable.lookahead_count], subtable.lookahead_offsets_pos, subtable.lookahead_coverages, 0)) return .{};
    if (try collectFastChainingSinglePosRecords(table, subtable, glyphs, input_indices_buf[0..subtable.input_count], adjustments, allocator, options)) {
        return .{ .matched = true, .next_pos = input_indices_buf[subtable.input_count - 1] + 1 };
    }
    try collectPositionRecordsMapped(table, subtable.records_pos, subtable.pos_count, input_indices_buf[0..subtable.input_count], glyphs, adjustments, allocator, options);
    return .{ .matched = true, .next_pos = input_indices_buf[subtable.input_count - 1] + 1 };
}

fn collectAcceleratedChainingCoveragePositioningAt(table: Table, subtable: ChainingCoverageSubtable, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!PositionContextResult {
    // The lookup accelerator groups format-3 chaining subtables by their first
    // input Coverage. Reuse that proof instead of checking the same first
    // Coverage again on every candidate position.
    if (subtable.input_count == 0) return .{};
    if (table.assume_validated and subtable.input_count == 1 and subtable.backtrack_count == 0 and subtable.lookahead_count == 1 and subtable.pos_count == 1) {
        return try collectSimpleAcceleratedChainingCoveragePositioningAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options);
    }
    var input_indices_buf: [64]usize = undefined;
    if (subtable.input_count > input_indices_buf.len) return error.UnsupportedGpos;
    if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..subtable.input_count])) return .{};
    if (input_indices_buf[0] != pos) return .{};
    if (!try gposCoverageIndicesMatchCached(table, subtable.subtable_offset, glyphs, input_indices_buf[0..subtable.input_count], subtable.input_offsets_pos, subtable.input_coverages, 1)) return .{};
    var backtrack_indices_buf: [64]usize = undefined;
    if (subtable.backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGpos;
    if (!collectBacktrackUnignoredGlyphs(glyphs, pos, lookup_flag, options, backtrack_indices_buf[0..subtable.backtrack_count])) return .{};
    const lookahead_start = input_indices_buf[subtable.input_count - 1] + 1;
    var lookahead_indices_buf: [64]usize = undefined;
    if (subtable.lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGpos;
    if (!collectForwardUnignoredGlyphs(glyphs, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..subtable.lookahead_count])) return .{};
    if (!try gposCoverageIndicesMatchCached(table, subtable.subtable_offset, glyphs, backtrack_indices_buf[0..subtable.backtrack_count], subtable.backtrack_offsets_pos, subtable.backtrack_coverages, 0)) return .{};
    if (!try gposCoverageIndicesMatchCached(table, subtable.subtable_offset, glyphs, lookahead_indices_buf[0..subtable.lookahead_count], subtable.lookahead_offsets_pos, subtable.lookahead_coverages, 0)) return .{};
    if (try collectFastChainingSinglePosRecords(table, subtable, glyphs, input_indices_buf[0..subtable.input_count], adjustments, allocator, options)) {
        return .{ .matched = true, .next_pos = input_indices_buf[subtable.input_count - 1] + 1 };
    }
    try collectPositionRecordsMapped(table, subtable.records_pos, subtable.pos_count, input_indices_buf[0..subtable.input_count], glyphs, adjustments, allocator, options);
    return .{ .matched = true, .next_pos = input_indices_buf[subtable.input_count - 1] + 1 };
}

fn collectFastChainingSinglePosRecords(table: Table, subtable: ChainingCoverageSubtable, glyphs: []const GlyphId, input_indices: []const usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (subtable.fast_record_count == 0) return false;
    const accelerators = options.lookup_accelerators orelse return false;
    for (subtable.fast_records[0..subtable.fast_record_count]) |record| {
        if (record.sequence_index >= input_indices.len) return false;
        if (record.lookup_index >= accelerators.len) return false;
        const target_index = input_indices[record.sequence_index];
        if (target_index >= glyphs.len) continue;
        const nested = accelerators[record.lookup_index];
        if (nested.single_pos_subtables.len == 0) return false;
        var lookup_options = options;
        lookup_options.context_depth = options.context_depth + 1;
        if (try collectSingleAdjustmentAtAccelerated(table, nested.single_pos_subtables, glyphs[target_index], target_index, adjustments, allocator, record.lookup_flag, lookup_options)) continue;
    }
    return true;
}

fn collectSimpleChainingCoveragePositioningAt(table: Table, subtable: ChainingCoverageSubtable, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!PositionContextResult {
    if (subtable.input_coverages.len != 0) {
        if (subtable.input_coverages[0].index(glyphs[pos]) == null) return .{};
    } else {
        const input_coverage_offset = try checkedRequiredCoverageOffset(table, subtable.subtable_offset, try readU16(table, subtable.input_offsets_pos));
        if (!try contextCoverageContains(table, input_coverage_offset, glyphs[pos])) return .{};
    }
    return try collectSimpleAcceleratedChainingCoveragePositioningAt(table, subtable, glyphs, pos, adjustments, allocator, lookup_flag, options);
}

fn collectSimpleAcceleratedChainingCoveragePositioningAt(table: Table, subtable: ChainingCoverageSubtable, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!PositionContextResult {
    const lookahead_index = nextUnignoredGlyph(glyphs, pos + 1, lookup_flag, options) orelse return .{};
    if (subtable.lookahead_coverages.len != 0) {
        if (subtable.lookahead_coverages[0].index(glyphs[lookahead_index]) == null) return .{};
    } else {
        const lookahead_coverage_offset = try checkedRequiredCoverageOffset(table, subtable.subtable_offset, try readU16(table, subtable.lookahead_offsets_pos));
        if (!try contextCoverageContains(table, lookahead_coverage_offset, glyphs[lookahead_index])) return .{};
    }
    const sequence_index = try readU16(table, subtable.records_pos);
    if (sequence_index != 0) return .{};
    const lookup_index = try readU16(table, subtable.records_pos + 2);
    try collectNestedAdjustment(table, glyphs, pos, lookup_index, adjustments, allocator, options);
    return .{ .matched = true, .next_pos = lookahead_index };
}

fn gposCoverageSequenceMatches(table: Table, base_offset: usize, glyphs: []const GlyphId, pos: usize, offsets_pos: usize, count: usize, backtrack: bool) GposError!bool {
    if (backtrack and pos < count) return false;
    if (!backtrack and pos + count > glyphs.len) return false;
    for (0..count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16(table, offsets_pos + i * 2));
        const glyph = if (backtrack) glyphs[pos - 1 - i] else glyphs[pos + i];
        if (!try contextCoverageContains(table, coverage_offset, glyph)) return false;
    }
    return true;
}

fn gposLookaheadCoverageMatches(table: Table, base_offset: usize, glyphs: []const GlyphId, start: usize, offsets_pos: usize, count: usize) GposError!bool {
    if (start + count > glyphs.len) return false;
    for (0..count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16(table, offsets_pos + i * 2));
        if (!try contextCoverageContains(table, coverage_offset, glyphs[start + i])) return false;
    }
    return true;
}

fn gposCoverageIndicesMatchCached(table: Table, base_offset: usize, glyphs: []const GlyphId, indices: []const usize, offsets_pos: usize, coverages: []const NativeCoverage, start: usize) GposError!bool {
    var i = start;
    while (i < indices.len) : (i += 1) {
        const glyph = glyphs[indices[i]];
        if (i < coverages.len) {
            if (coverages[i].index(glyph) == null) return false;
        } else {
            const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16(table, offsets_pos + i * 2));
            if (!try contextCoverageContains(table, coverage_offset, glyph)) return false;
        }
    }
    return true;
}

fn collectPositionRuleSet(table: Table, rule_set_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, rule_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = rule_set_offset + try readU16(table, rule_set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const pos_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (1..glyph_count) |i| {
            const expected = try readU16(table, rule_offset + 4 + (i - 1) * 2);
            if (glyphs[input_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        const records_pos = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator, options);
        return true;
    }
    return false;
}

fn collectClassPositionRuleSet(table: Table, set_offset: usize, class_def_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const pos_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (1..glyph_count) |i| {
            const expected_class = try readU16(table, rule_offset + 4 + (i - 1) * 2);
            const actual_class = try classValue(table, class_def_offset, glyphs[input_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        const records_pos = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator, options);
        return true;
    }
    return false;
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

fn ensurePositionRecordListWithin(table: Table, records_pos: usize, record_count: usize) GposError!void {
    // PosLookupRecord arrays are an all-or-nothing part of a contextual match:
    // detect truncation before appending any nested adjustment so a malformed
    // table cannot expose a partly-applied positioning result to the caller.
    if (records_pos > table.length) return error.BadGpos;
    if (record_count > (table.length - records_pos) / 4) return error.BadGpos;
}

fn ensurePositionRecordsWithin(table: Table, records_pos: usize, record_count: usize, input_count: usize) GposError!void {
    try ensurePositionRecordListWithin(table, records_pos, record_count);
    try ensurePositionRecordReferencesWithinDepth(table, records_pos, record_count, input_count, 0);
}

fn ensurePositionRecordsWithinDepth(table: Table, records_pos: usize, record_count: usize, input_count: usize, depth: usize) GposError!void {
    try ensurePositionRecordListWithin(table, records_pos, record_count);
    try ensurePositionRecordReferencesWithinDepth(table, records_pos, record_count, input_count, depth);
}

fn ensurePositionRecordReferencesWithinDepth(table: Table, records_pos: usize, record_count: usize, input_count: usize, depth: usize) GposError!void {
    // Contextual positioning appends adjustments as it walks PosLookupRecords.
    // Preflight both record fields: the sequence index must target the matched
    // input sequence, and the lookup index/header must resolve. Otherwise a
    // malformed later record could be silently skipped or could leave earlier
    // nested adjustments visible to the caller.
    // Contextual lookups are allowed to reference other contextual lookups; cap
    // validation recursion so cyclic lookup graphs are reported as unsupported
    // instead of overflowing the validator stack.
    if (depth > max_context_preflight_depth) return error.UnsupportedGpos;
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    const lookup_count = try readU16BadGpos(table, lookup_list_offset);
    for (0..record_count) |record_i| {
        const record_offset = records_pos + record_i * 4;
        const sequence_index = try readU16BadGpos(table, record_offset);
        if (sequence_index >= input_count) return error.BadGpos;
        const lookup_index = try readU16BadGpos(table, record_offset + 2);
        if (lookup_index >= lookup_count) return error.BadGpos;
        if (table.validating_full_lookup_list) continue;
        const lookup_offset_pos = lookup_list_offset + 2 + @as(usize, lookup_index) * 2;
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16BadGpos(table, lookup_offset_pos));
        try ensurePositionLookupHeaderAndExtensionPayloadsWithin(table, lookup_offset);
        const lookup_type = try readU16BadGpos(table, lookup_offset);
        const subtable_count = try readU16BadGpos(table, lookup_offset + 4);
        try ensurePositionLookupSubtablesWithinDepth(table, lookup_offset, lookup_type, subtable_count, depth + 1);
    }
}

fn ensurePositionRecordMarkFilteringSetsValid(table: Table, records_pos: usize, record_count: usize, options: LookupOptions) GposError!void {
    const lookup_list_offset = try checkedRequiredLookupListOffset(table);
    for (0..record_count) |record_i| {
        const record_offset = records_pos + record_i * 4;
        const lookup_index = try readU16BadGpos(table, record_offset + 2);
        const lookup_offset_pos = lookup_list_offset + 2 + @as(usize, lookup_index) * 2;
        const lookup_offset = try checkedRequiredLookupOffset(table, lookup_list_offset, try readU16BadGpos(table, lookup_offset_pos));
        const lookup_flag = try readU16BadGpos(table, lookup_offset + 2);
        if ((lookup_flag & 0x0010) == 0) continue;
        const subtable_count = try readU16BadGpos(table, lookup_offset + 4);
        try validateMarkFilteringSetIndex(.{
            .mark_filtering_sets = options.mark_filtering_sets,
            .active_mark_filtering_set = try readU16BadGpos(table, lookup_offset + 6 + @as(usize, subtable_count) * 2),
        });
    }
}

fn ensurePositionLookupHeaderWithin(table: Table, lookup_offset: usize) GposError!void {
    if (lookup_offset > table.length or table.length - lookup_offset < 6) return error.BadGpos;
    const lookup_type = try readU16BadGpos(table, lookup_offset);
    const lookup_flag = try readU16BadGpos(table, lookup_offset + 2);
    const subtable_count = try readU16BadGpos(table, lookup_offset + 4);
    try validateLookupFlag(lookup_flag);
    const subtable_offsets_pos = lookup_offset + 6;
    const subtable_offsets_len = @as(usize, subtable_count) * 2;
    if (subtable_offsets_pos > table.length or subtable_offsets_len > table.length - subtable_offsets_pos) return error.BadGpos;
    if ((lookup_flag & 0x0010) != 0) {
        const mark_filtering_set_pos = subtable_offsets_pos + subtable_offsets_len;
        if (mark_filtering_set_pos > table.length or table.length - mark_filtering_set_pos < 2) return error.BadGpos;
    }
    _ = lookup_type;
}

fn ensurePositionLookupHeaderAndExtensionPayloadsWithin(table: Table, lookup_offset: usize) GposError!void {
    try ensurePositionLookupHeaderWithin(table, lookup_offset);
    const lookup_type = try readU16BadGpos(table, lookup_offset);
    if (lookup_type == 9) {
        const subtable_count = try readU16BadGpos(table, lookup_offset + 4);
        try ensureExtensionPositionLookupPayloadsWithin(table, lookup_offset, subtable_count);
    }
}

fn validateLookupFlag(lookup_flag: u16) GposError!void {
    // OpenType currently defines only low bits 0..4 and the high-byte
    // MarkAttachmentType. Rejecting reserved middle bits at lookup preflight
    // keeps positioning behavior deterministic if future/private flags appear.
    if ((lookup_flag & 0x00e0) != 0) return error.BadGpos;
}

fn ensurePositionLookupSubtablesWithin(table: Table, lookup_offset: usize, lookup_type: u16, subtable_count: u16) GposError!void {
    return ensurePositionLookupSubtablesWithinDepth(table, lookup_offset, lookup_type, subtable_count, 0);
}

fn ensurePositionLookupSubtablesWithinDepth(table: Table, lookup_offset: usize, lookup_type: u16, subtable_count: u16, depth: usize) GposError!void {
    switch (lookup_type) {
        1, 2, 3, 4, 5, 6, 7, 8 => {},
        else => return,
    }
    for (0..subtable_count) |subtable_i| {
        // Lookup.SubTable offsets are required child pointers for supported
        // positioning lookups. Offset zero would reinterpret the Lookup header
        // as a subtable and can make malformed data appear valid or derive
        // value sizes from lookup metadata.
        const subtable_offset = try checkedRequiredPositionOffset(table, lookup_offset, try readU16BadGpos(table, lookup_offset + 6 + subtable_i * 2));
        try ensurePositionSubtableFixedHeaderWithin(table, subtable_offset, lookup_type);
        try ensurePositionSubtableVariableDataWithinDepth(table, subtable_offset, lookup_type, depth);
    }
}

fn ensureExtensionPositionLookupPayloadsWithin(table: Table, lookup_offset: usize, subtable_count: u16) GposError!void {
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = try checkedRequiredPositionOffset(table, lookup_offset, try readU16BadGpos(table, lookup_offset + 6 + subtable_i * 2));
        try ensureExtensionPositionPayloadWithin(table, subtable_offset);
    }
}

fn ensureFeatureLookupReferencesWithin(table: Table, lookup_count: u16) GposError!u16 {
    const feature_list_offset = try checkedRequiredFeatureListOffset(table);
    const feature_count = try readU16BadGpos(table, feature_list_offset);
    try ensureBytesWithin(table, feature_list_offset + 2, @as(usize, feature_count) * 6);

    for (0..feature_count) |feature_i| {
        const feature_record = feature_list_offset + 2 + feature_i * 6;
        const feature_offset = try checkedPositionOffset(table, feature_list_offset, try readU16BadGpos(table, feature_record + 4));
        const lookup_index_count = try readU16BadGpos(table, feature_offset + 2);
        try ensureBytesWithin(table, feature_offset + 4, @as(usize, lookup_index_count) * 2);

        for (0..lookup_index_count) |lookup_i| {
            const lookup_index = try readU16BadGpos(table, feature_offset + 4 + lookup_i * 2);
            // Feature selection is the public activation graph for GPOS. Reject
            // dangling LookupList indexes at parse time instead of letting a
            // requested positioning feature disappear later during shaping.
            if (lookup_index >= lookup_count) return error.BadGpos;
        }
    }
    return feature_count;
}

fn ensureScriptFeatureReferencesWithin(table: Table, feature_count: u16) GposError!void {
    const script_list_offset = try checkedRequiredScriptListOffset(table);
    const script_count = try readU16BadGpos(table, script_list_offset);
    try ensureBytesWithin(table, script_list_offset + 2, @as(usize, script_count) * 6);
    try validateScriptRecordOrder(table, script_list_offset, script_count);

    for (0..script_count) |script_i| {
        const script_record = script_list_offset + 2 + script_i * 6;
        const script_offset = try checkedPositionOffset(table, script_list_offset, try readU16BadGpos(table, script_record + 4));
        const default_lang_sys_relative = try readU16BadGpos(table, script_offset);
        const lang_sys_count = try readU16BadGpos(table, script_offset + 2);
        try ensureBytesWithin(table, script_offset + 4, @as(usize, lang_sys_count) * 6);
        try validateLangSysRecordOrder(table, script_offset, lang_sys_count);

        if (default_lang_sys_relative != 0) {
            try ensureLangSysFeatureReferencesWithin(table, try checkedPositionOffset(table, script_offset, default_lang_sys_relative), feature_count);
        }
        for (0..lang_sys_count) |lang_i| {
            const lang_record = script_offset + 4 + lang_i * 6;
            const lang_sys_offset = try checkedPositionOffset(table, script_offset, try readU16BadGpos(table, lang_record + 4));
            try ensureLangSysFeatureReferencesWithin(table, lang_sys_offset, feature_count);
        }
    }
}

fn ensureLangSysFeatureReferencesWithin(table: Table, lang_sys_offset: usize, feature_count: u16) GposError!void {
    // ScriptList is the public activation graph for language-specific
    // positioning. A dangling feature index would be silently ignored during
    // selection, dropping required kerning/mark data rather than reporting a
    // malformed font, so validate LangSys topology while loading the table.
    try ensureBytesWithin(table, lang_sys_offset, 6);
    const required_feature_index = try readU16BadGpos(table, lang_sys_offset + 2);
    if (required_feature_index != 0xffff and required_feature_index >= feature_count) return error.BadGpos;

    const lang_feature_count = try readU16BadGpos(table, lang_sys_offset + 4);
    try ensureBytesWithin(table, lang_sys_offset + 6, @as(usize, lang_feature_count) * 2);
    for (0..lang_feature_count) |feature_i| {
        const feature_index = try readU16BadGpos(table, lang_sys_offset + 6 + feature_i * 2);
        if (feature_index >= feature_count) return error.BadGpos;
    }
}

fn validateScriptRecordOrder(table: Table, script_list_offset: usize, script_count: u16) GposError!void {
    // Real text-rendering fixtures can carry adjacent duplicate ScriptRecords.
    // Selection remains deterministic because findScriptOffset returns the
    // first record, while the validation walk below still proves every child
    // Script/LangSys graph before shaping.
    return validateTagRecordOrder(table, script_list_offset + 2, script_count, 6, true);
}

fn validateFeatureRecordOrder(table: Table, feature_list_offset: usize, feature_count: u16) GposError!void {
    _ = table;
    _ = feature_list_offset;
    _ = feature_count;
}

fn validateLangSysRecordOrder(table: Table, script_offset: usize, lang_sys_count: u16) GposError!void {
    return validateTagRecordOrder(table, script_offset + 4, lang_sys_count, 6, false);
}

fn validateTagRecordOrder(table: Table, records_offset: usize, record_count: u16, record_stride: usize, allow_equal_tags: bool) GposError!void {
    // OpenType Layout tag records are sorted by tag. FeatureList records in
    // widely deployed fonts may repeat a feature or Script tag with different
    // payloads. Those lists are nondecreasing and use their caller's stable
    // first-match semantics; LangSys records remain strict because a duplicate
    // language would make one branch of the selected Script unreachable.
    var previous_tag: ?u32 = null;
    for (0..record_count) |record_i| {
        const tag_value = try readU32BadGpos(table, records_offset + record_i * record_stride);
        if (previous_tag) |previous| {
            if (if (allow_equal_tags) tag_value < previous else tag_value <= previous) return error.BadGpos;
        }
        previous_tag = tag_value;
    }
}

fn ensureExtensionPositionPayloadWithin(table: Table, subtable_offset: usize) GposError!void {
    // PosLookupRecords are applied eagerly. If a later record references a
    // malformed ExtensionPos wrapper, reject the entire contextual match before
    // earlier records can append partial adjustments.
    if (subtable_offset > table.length or table.length - subtable_offset < 8) return error.BadGpos;
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16BadGpos(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    const extension_subtable = try checkedExtensionPositionPayloadOffset(table, subtable_offset, try readU32BadGpos(table, subtable_offset + 4));
    try ensurePositionSubtableFixedHeaderWithin(table, extension_subtable, extension_lookup_type);
    try ensurePositionSubtableVariableDataWithin(table, extension_subtable, extension_lookup_type);
}

fn ensurePositionSubtableFixedHeaderWithin(table: Table, subtable_offset: usize, lookup_type: u16) GposError!void {
    if (subtable_offset > table.length or table.length - subtable_offset < 2) return error.BadGpos;
    const pos_format = try readU16BadGpos(table, subtable_offset);
    const min_len: usize = switch (lookup_type) {
        1 => 6,
        2 => 8,
        3 => 6,
        4, 5, 6 => 12,
        7 => switch (pos_format) {
            1, 3 => 6,
            2 => 8,
            else => return error.UnsupportedGpos,
        },
        8 => switch (pos_format) {
            1 => 6,
            2 => 12,
            3 => 4,
            else => return error.UnsupportedGpos,
        },
        else => return,
    };
    if (table.length - subtable_offset < min_len) return error.BadGpos;
}

fn ensurePositionSubtableVariableDataWithin(table: Table, subtable_offset: usize, lookup_type: u16) GposError!void {
    return ensurePositionSubtableVariableDataWithinDepth(table, subtable_offset, lookup_type, 0);
}

fn ensurePositionSubtableVariableDataWithinDepth(table: Table, subtable_offset: usize, lookup_type: u16, depth: usize) GposError!void {
    switch (lookup_type) {
        1 => try ensureSinglePositionSubtableWithin(table, subtable_offset),
        2 => try ensurePairPositionSubtableWithin(table, subtable_offset),
        3 => try ensureCursivePositionSubtableWithin(table, subtable_offset),
        4 => try ensureMarkToBasePositionSubtableWithin(table, subtable_offset),
        5 => try ensureMarkToLigaturePositionSubtableWithin(table, subtable_offset),
        6 => try ensureMarkToMarkPositionSubtableWithin(table, subtable_offset),
        7 => try ensureContextPositionSubtableWithin(table, subtable_offset, depth),
        8 => try ensureChainingContextPositionSubtableWithin(table, subtable_offset, depth),
        else => {},
    }
}

fn ensureSinglePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const value_format = try readU16BadGpos(table, subtable_offset + 4);
    const value_size = try valueRecordSize(value_format);
    switch (pos_format) {
        1 => try ensureValueRecordWithin(table, subtable_offset + 6, value_format, subtable_offset),
        2 => {
            const value_count = try readU16BadGpos(table, subtable_offset + 6);
            // Coverage indexes are direct indexes into the ValueRecord array.
            // Reject dangling coverage entries during preflight instead of
            // letting shaping silently skip a covered glyph whose record is
            // absent from a malformed SinglePos format 2 subtable.
            try ensureCoverageIndicesWithin(table, coverage_offset, value_count);
            try ensureBytesWithin(table, subtable_offset + 8, @as(usize, value_count) * value_size);
            if (valueRecordHasDeviceOffsets(value_format)) {
                for (0..value_count) |value_i| {
                    try ensureValueRecordWithin(table, subtable_offset + 8 + value_i * value_size, value_format, subtable_offset);
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensurePairPositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const value_format_1 = try readU16BadGpos(table, subtable_offset + 4);
    const value_format_2 = try readU16BadGpos(table, subtable_offset + 6);
    const value_size_1 = try valueRecordSize(value_format_1);
    const value_size_2 = try valueRecordSize(value_format_2);

    switch (pos_format) {
        1 => {
            const pair_set_count = try readU16BadGpos(table, subtable_offset + 8);
            // PairSet offsets are selected by the first glyph's coverage index.
            // Every covered first glyph must therefore have a corresponding
            // PairSet slot; otherwise positioning becomes data-dependent on a
            // malformed coverage table and silently drops declared pairs.
            try ensureCoverageIndicesWithin(table, coverage_offset, pair_set_count);
            const pair_set_offsets_pos = subtable_offset + 10;
            try ensureBytesWithin(table, pair_set_offsets_pos, @as(usize, pair_set_count) * 2);
            for (0..pair_set_count) |pair_set_i| {
                const pair_set_relative = try readU16BadGpos(table, pair_set_offsets_pos + pair_set_i * 2);
                // PairSet offsets are required child tables. A zero offset
                // aliases the PairPos header as PairSet.PairValueCount, which
                // can make malformed fonts appear structurally valid or derive
                // record bounds from unrelated header fields.
                if (pair_set_relative == 0) return error.BadGpos;
                const pair_set_offset = try checkedPositionOffset(table, subtable_offset, pair_set_relative);
                const pair_value_count = try readU16BadGpos(table, pair_set_offset);
                _ = try ensurePairValueRecordsWithin(table, pair_set_offset, pair_value_count, value_format_1, value_format_2, value_size_1, value_size_2, null);
            }
        },
        2 => {
            const class_def_1 = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
            const class_def_2 = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
            const class_1_count = try readU16BadGpos(table, subtable_offset + 12);
            const class_2_count = try readU16BadGpos(table, subtable_offset + 14);
            try ensureClassDefTableWithinLimit(table, class_def_1, class_1_count);
            try ensureClassDefTableWithinLimit(table, class_def_2, class_2_count);
            const record_size = value_size_1 + value_size_2;
            try ensureBytesWithin(table, subtable_offset + 16, try checkedMul(try checkedMul(@as(usize, class_1_count), class_2_count), record_size));
            if (valueRecordHasDeviceOffsets(value_format_1) or valueRecordHasDeviceOffsets(value_format_2)) {
                const record_count = try checkedMul(@as(usize, class_1_count), class_2_count);
                for (0..record_count) |record_i| {
                    const record_offset = subtable_offset + 16 + record_i * record_size;
                    if (valueRecordHasDeviceOffsets(value_format_1)) {
                        try ensureValueRecordWithin(table, record_offset, value_format_1, subtable_offset);
                    }
                    if (valueRecordHasDeviceOffsets(value_format_2)) {
                        try ensureValueRecordWithin(table, record_offset + value_size_1, value_format_2, subtable_offset);
                    }
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensurePairValueRecordsWithin(table: Table, pair_set_offset: usize, pair_value_count: u16, value_format_1: u16, value_format_2: u16, value_size_1: usize, value_size_2: usize, target_second_glyph: ?GlyphId) GposError!?usize {
    const pair_record_size = 2 + value_size_1 + value_size_2;
    try ensureBytesWithin(table, pair_set_offset + 2, try checkedMul(@as(usize, pair_value_count), pair_record_size));

    var previous_second: ?GlyphId = null;
    var matched_record: ?usize = null;
    for (0..pair_value_count) |pair_i| {
        const pair_record_offset = pair_set_offset + 2 + pair_i * pair_record_size;
        const second_glyph = try readU16BadGpos(table, pair_record_offset);
        // OpenType requires each PairSet to be sorted by SecondGlyph. Enforce
        // the strict order while preflighting so duplicate or descending
        // records cannot make positioning depend on a linear-search accident.
        if (previous_second) |previous| {
            if (second_glyph <= previous) return error.BadGpos;
        }
        previous_second = second_glyph;

        try ensureGlyphIdWithinMaxp(table, second_glyph);
        if (valueRecordHasDeviceOffsets(value_format_1)) {
            try ensureValueRecordWithin(table, pair_record_offset + 2, value_format_1, pair_set_offset);
        }
        if (valueRecordHasDeviceOffsets(value_format_2)) {
            try ensureValueRecordWithin(table, pair_record_offset + 2 + value_size_1, value_format_2, pair_set_offset);
        }
        if (target_second_glyph) |target| {
            if (second_glyph == target) matched_record = pair_record_offset;
        }
    }
    return matched_record;
}

fn findValidatedPairValueRecord(table: Table, pair_set_offset: usize, pair_value_count: u16, value_size_1: usize, value_size_2: usize, target_second_glyph: GlyphId) GposError!?usize {
    const pair_record_size = 2 + value_size_1 + value_size_2;
    var lo: usize = 0;
    var hi: usize = pair_value_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const pair_record_offset = pair_set_offset + 2 + mid * pair_record_size;
        const second_glyph = try readU16(table, pair_record_offset);
        if (target_second_glyph < second_glyph) {
            hi = mid;
        } else if (target_second_glyph > second_glyph) {
            lo = mid + 1;
        } else {
            return pair_record_offset;
        }
    }
    return null;
}

fn ensureCursivePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const entry_exit_count = try readU16BadGpos(table, subtable_offset + 4);
    try ensureCoverageTableWithin(table, coverage_offset);
    try ensureCoverageIndicesWithin(table, coverage_offset, entry_exit_count);
    try ensureBytesWithin(table, subtable_offset + 6, @as(usize, entry_exit_count) * 4);
    for (0..entry_exit_count) |entry_i| {
        const record = subtable_offset + 6 + entry_i * 4;
        const entry_anchor = try readU16BadGpos(table, record);
        const exit_anchor = try readU16BadGpos(table, record + 2);
        if (entry_anchor != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, subtable_offset, entry_anchor));
        if (exit_anchor != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, subtable_offset, exit_anchor));
    }
}

fn ensureMarkToBasePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const base_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
    const class_count = try readU16BadGpos(table, subtable_offset + 6);
    // Mark attachment array offsets are mandatory OpenType child tables. A
    // zero offset aliases the enclosing positioning subtable as an array and
    // lets header fields masquerade as mark counts, classes, or anchor grids.
    const mark_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
    const base_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
    try ensureCoverageTableWithin(table, mark_coverage_offset);
    try ensureCoverageTableWithin(table, base_coverage_offset);
    const mark_count = try ensureMarkArrayWithin(table, mark_array_offset, class_count);
    const base_count = try ensureBaseArrayWithin(table, base_array_offset, class_count);
    try ensureCoverageIndicesWithin(table, mark_coverage_offset, mark_count);
    try ensureCoverageIndicesWithin(table, base_coverage_offset, base_count);
}

fn ensureMarkToLigaturePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const ligature_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
    const class_count = try readU16BadGpos(table, subtable_offset + 6);
    const mark_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
    const ligature_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
    try ensureCoverageTableWithin(table, mark_coverage_offset);
    try ensureCoverageTableWithin(table, ligature_coverage_offset);
    const mark_count = try ensureMarkArrayWithin(table, mark_array_offset, class_count);
    const ligature_count = try ensureLigatureArrayWithin(table, ligature_array_offset, class_count);
    try ensureCoverageIndicesWithin(table, mark_coverage_offset, mark_count);
    try ensureCoverageIndicesWithin(table, ligature_coverage_offset, ligature_count);
}

fn ensureMarkToMarkPositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_1_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const mark_2_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
    const class_count = try readU16BadGpos(table, subtable_offset + 6);
    const mark_1_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
    const mark_2_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
    try ensureCoverageTableWithin(table, mark_1_coverage_offset);
    try ensureCoverageTableWithin(table, mark_2_coverage_offset);
    const mark_1_count = try ensureMarkArrayWithin(table, mark_1_array_offset, class_count);
    const mark_2_count = try ensureMark2ArrayWithin(table, mark_2_array_offset, class_count);
    try ensureCoverageIndicesWithin(table, mark_1_coverage_offset, mark_1_count);
    try ensureCoverageIndicesWithin(table, mark_2_coverage_offset, mark_2_count);
}

fn ensureContextPositionSubtableWithin(table: Table, subtable_offset: usize, depth: usize) GposError!void {
    // ContextPos uses the same variable-length topology as ContextSubst, but
    // each matched rule references PosLookupRecords. Validate every rule and
    // referenced lookup before any earlier subtable in the same lookup can
    // append adjustments, preserving lookup-level atomicity.
    const pos_format = try readU16BadGpos(table, subtable_offset);
    switch (pos_format) {
        1 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            try ensureCoverageTableWithin(table, coverage_offset);
            const rule_set_count = try readU16BadGpos(table, subtable_offset + 4);
            const rule_set_offsets_pos = subtable_offset + 6;
            try ensureBytesWithin(table, rule_set_offsets_pos, @as(usize, rule_set_count) * 2);
            for (0..rule_set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, rule_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensurePositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        2 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            const class_def_offset = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
            try ensureCoverageTableWithin(table, coverage_offset);
            try ensureClassDefTableWithin(table, class_def_offset);
            const class_set_count = try readU16BadGpos(table, subtable_offset + 6);
            const class_set_offsets_pos = subtable_offset + 8;
            try ensureBytesWithin(table, class_set_offsets_pos, @as(usize, class_set_count) * 2);
            for (0..class_set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, class_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensurePositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        3 => {
            const glyph_count = try readU16BadGpos(table, subtable_offset + 2);
            if (glyph_count == 0) return error.BadGpos;
            const pos_count = try readU16BadGpos(table, subtable_offset + 4);
            const coverage_offsets_pos = subtable_offset + 6;
            try ensureContextCoverageOffsetArrayWithin(table, subtable_offset, coverage_offsets_pos, glyph_count);
            const records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
            try ensurePositionRecordsWithinDepth(table, records_pos, pos_count, glyph_count, depth);
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensurePositionRuleSetWithin(table: Table, rule_set_offset: usize, depth: usize) GposError!void {
    const rule_count = try readU16BadGpos(table, rule_set_offset);
    const rule_offsets_pos = rule_set_offset + 2;
    try ensureBytesWithin(table, rule_offsets_pos, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_i| {
        const rule_relative = try readU16BadGpos(table, rule_offsets_pos + rule_i * 2);
        // PosRule and PosClassRule offsets are mandatory child pointers once
        // their parent RuleSet exists. A zero value aliases the RuleSet header
        // as a rule, so record counts and nested lookup references would be
        // derived from unrelated metadata instead of declared rule payload.
        if (rule_relative == 0) return error.BadGpos;
        const rule_offset = try checkedPositionOffset(table, rule_set_offset, rule_relative);
        try ensurePositionRuleWithin(table, rule_offset, depth);
    }
}

fn ensurePositionRuleWithin(table: Table, rule_offset: usize, depth: usize) GposError!void {
    const glyph_count = try readU16BadGpos(table, rule_offset);
    if (glyph_count == 0) return error.BadGpos;
    const pos_count = try readU16BadGpos(table, rule_offset + 2);
    const input_pos = rule_offset + 4;
    try ensureBytesWithin(table, input_pos, (@as(usize, glyph_count) - 1) * 2);
    for (1..glyph_count) |input_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGpos(table, input_pos + (input_i - 1) * 2));
    }
    const records_pos = input_pos + (@as(usize, glyph_count) - 1) * 2;
    try ensurePositionRecordsWithinDepth(table, records_pos, pos_count, glyph_count, depth);
}

fn ensureChainingContextPositionSubtableWithin(table: Table, subtable_offset: usize, depth: usize) GposError!void {
    // ChainingContextPos contains backtrack, input, and lookahead regions
    // before its PosLookupRecords. Preflighting all three regions avoids a
    // malformed later subtable leaking adjustments from an earlier context
    // subtable in the same lookup.
    const pos_format = try readU16BadGpos(table, subtable_offset);
    switch (pos_format) {
        1 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            try ensureCoverageTableWithin(table, coverage_offset);
            const chain_set_count = try readU16BadGpos(table, subtable_offset + 4);
            const chain_set_offsets_pos = subtable_offset + 6;
            try ensureBytesWithin(table, chain_set_offsets_pos, @as(usize, chain_set_count) * 2);
            for (0..chain_set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, chain_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureChainingPositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        2 => {
            const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            const backtrack_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
            const input_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 6));
            const lookahead_class_def = try checkedRequiredClassDefOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
            try ensureCoverageTableWithin(table, coverage_offset);
            try ensureClassDefTableWithin(table, backtrack_class_def);
            try ensureClassDefTableWithin(table, input_class_def);
            try ensureClassDefTableWithin(table, lookahead_class_def);
            const set_count = try readU16BadGpos(table, subtable_offset + 10);
            const set_offsets_pos = subtable_offset + 12;
            try ensureBytesWithin(table, set_offsets_pos, @as(usize, set_count) * 2);
            for (0..set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureChainingPositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        3 => try ensureChainingCoveragePositionSubtableWithin(table, subtable_offset, depth),
        else => return error.UnsupportedGpos,
    }
}

fn ensureChainingPositionRuleSetWithin(table: Table, rule_set_offset: usize, depth: usize) GposError!void {
    const rule_count = try readU16BadGpos(table, rule_set_offset);
    const rule_offsets_pos = rule_set_offset + 2;
    try ensureBytesWithin(table, rule_offsets_pos, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_i| {
        const rule_relative = try readU16BadGpos(table, rule_offsets_pos + rule_i * 2);
        // ChainPosRule and ChainPosClassRule offsets are required children of
        // a non-null ChainPosRuleSet. Do not allow zero to reinterpret the
        // set's ruleCount/offset array as backtrack/input/lookahead counts.
        if (rule_relative == 0) return error.BadGpos;
        const rule_offset = try checkedPositionOffset(table, rule_set_offset, rule_relative);
        try ensureChainingPositionRuleWithin(table, rule_offset, depth);
    }
}

fn ensureChainingPositionRuleWithin(table: Table, rule_offset: usize, depth: usize) GposError!void {
    var cursor = rule_offset;
    const backtrack_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureBytesWithin(table, cursor, @as(usize, backtrack_count) * 2);
    for (0..backtrack_count) |backtrack_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGpos(table, cursor + backtrack_i * 2));
    }
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try readU16BadGpos(table, cursor);
    if (input_count == 0) return error.BadGpos;
    cursor += 2;
    try ensureBytesWithin(table, cursor, (@as(usize, input_count) - 1) * 2);
    for (1..input_count) |input_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGpos(table, cursor + (input_i - 1) * 2));
    }
    cursor += (@as(usize, input_count) - 1) * 2;

    const lookahead_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureBytesWithin(table, cursor, @as(usize, lookahead_count) * 2);
    for (0..lookahead_count) |lookahead_i| {
        try ensureGlyphIdWithinMaxp(table, try readU16BadGpos(table, cursor + lookahead_i * 2));
    }
    cursor += @as(usize, lookahead_count) * 2;

    const pos_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensurePositionRecordsWithinDepth(table, cursor, pos_count, input_count, depth);
}

fn ensureChainingCoveragePositionSubtableWithin(table: Table, subtable_offset: usize, depth: usize) GposError!void {
    var cursor = subtable_offset + 2;
    const backtrack_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureContextCoverageOffsetArrayWithin(table, subtable_offset, cursor, backtrack_count);
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try readU16BadGpos(table, cursor);
    if (input_count == 0) return error.BadGpos;
    cursor += 2;
    try ensureContextCoverageOffsetArrayWithin(table, subtable_offset, cursor, input_count);
    cursor += @as(usize, input_count) * 2;

    const lookahead_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureContextCoverageOffsetArrayWithin(table, subtable_offset, cursor, lookahead_count);
    cursor += @as(usize, lookahead_count) * 2;

    const pos_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensurePositionRecordsWithinDepth(table, cursor, pos_count, input_count, depth);
}

fn ensureMarkArrayWithin(table: Table, mark_array_offset: usize, class_count: u16) GposError!usize {
    const mark_count = try readU16BadGpos(table, mark_array_offset);
    try ensureBytesWithin(table, mark_array_offset + 2, @as(usize, mark_count) * 4);
    for (0..mark_count) |mark_i| {
        const record = mark_array_offset + 2 + mark_i * 4;
        const mark_class = try readU16BadGpos(table, record);
        if (mark_class >= class_count) return error.BadGpos;
        const anchor_offset = try readU16BadGpos(table, record + 2);
        // MarkRecords require a real anchor. Treating zero as relative to the
        // MarkArray header would reinterpret markCount/markClass metadata as a
        // Paint-style child table and make malformed mark positioning stateful.
        if (anchor_offset == 0) return error.BadGpos;
        try ensureAnchorTableWithin(table, try checkedPositionOffset(table, mark_array_offset, anchor_offset));
    }
    return mark_count;
}

fn ensureBaseArrayWithin(table: Table, base_array_offset: usize, class_count: u16) GposError!usize {
    const base_count = try readU16BadGpos(table, base_array_offset);
    const anchor_count = try checkedMul(@as(usize, base_count), class_count);
    try ensureBytesWithin(table, base_array_offset + 2, anchor_count * 2);
    for (0..anchor_count) |anchor_i| {
        const anchor_offset = try readU16BadGpos(table, base_array_offset + 2 + anchor_i * 2);
        if (anchor_offset != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, base_array_offset, anchor_offset));
    }
    return base_count;
}

fn ensureLigatureArrayWithin(table: Table, ligature_array_offset: usize, class_count: u16) GposError!usize {
    const ligature_count = try readU16BadGpos(table, ligature_array_offset);
    try ensureBytesWithin(table, ligature_array_offset + 2, @as(usize, ligature_count) * 2);
    for (0..ligature_count) |ligature_i| {
        const attach_relative = try readU16BadGpos(table, ligature_array_offset + 2 + ligature_i * 2);
        // LigatureAttach offsets are required child tables keyed by
        // LigatureCoverage index. Zero would alias the LigatureArray header as
        // a component count and make anchor availability depend on unrelated
        // offset-slot bytes, so reject it instead of silently dropping marks.
        if (attach_relative == 0) return error.BadGpos;
        const attach_offset = try checkedPositionOffset(table, ligature_array_offset, attach_relative);
        const component_count = try readU16BadGpos(table, attach_offset);
        const anchor_count = try checkedMul(@as(usize, component_count), class_count);
        try ensureBytesWithin(table, attach_offset + 2, anchor_count * 2);
        for (0..anchor_count) |anchor_i| {
            const anchor_offset = try readU16BadGpos(table, attach_offset + 2 + anchor_i * 2);
            if (anchor_offset != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, attach_offset, anchor_offset));
        }
    }
    return ligature_count;
}

fn ensureMark2ArrayWithin(table: Table, mark_2_array_offset: usize, class_count: u16) GposError!usize {
    const mark_2_count = try readU16BadGpos(table, mark_2_array_offset);
    const anchor_count = try checkedMul(@as(usize, mark_2_count), class_count);
    try ensureBytesWithin(table, mark_2_array_offset + 2, anchor_count * 2);
    for (0..anchor_count) |anchor_i| {
        const anchor_offset = try readU16BadGpos(table, mark_2_array_offset + 2 + anchor_i * 2);
        if (anchor_offset != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, mark_2_array_offset, anchor_offset));
    }
    return mark_2_count;
}

fn ensureAnchorTableWithin(table: Table, anchor_offset: usize) GposError!void {
    const format = try readU16BadGpos(table, anchor_offset);
    switch (format) {
        1 => try ensureBytesWithin(table, anchor_offset, 6),
        2 => try ensureBytesWithin(table, anchor_offset, 8),
        3 => {
            try ensureBytesWithin(table, anchor_offset, 10);
            const x_device_offset = try readU16BadGpos(table, anchor_offset + 6);
            const y_device_offset = try readU16BadGpos(table, anchor_offset + 8);
            // AnchorFormat3 uses nullable offsets for Device/VariationIndex
            // tables. Non-zero offsets are real child tables relative to the
            // anchor, so validate them during lookup preflight instead of
            // allowing a dangling offset to survive until future variation
            // support tries to follow it.
            if (x_device_offset != 0) try ensureDeviceOrVariationIndexTableWithin(table, try checkedPositionOffset(table, anchor_offset, x_device_offset));
            if (y_device_offset != 0) try ensureDeviceOrVariationIndexTableWithin(table, try checkedPositionOffset(table, anchor_offset, y_device_offset));
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensureDeviceOrVariationIndexTableWithin(table: Table, device_offset: usize) GposError!void {
    try ensureBytesWithin(table, device_offset, 6);
    const start_size = try readU16BadGpos(table, device_offset);
    const end_size = try readU16BadGpos(table, device_offset + 2);
    const delta_format = try readU16BadGpos(table, device_offset + 4);

    // OpenType 1.8 reuses AnchorFormat3's Device-table offsets for variation
    // indexes by storing DeltaFormat 0x8000. The table remains exactly three
    // uint16 fields; StartSize and EndSize carry outer/inner variation indexes.
    if (delta_format == 0x8000) return;
    if (end_size < start_size) return error.BadGpos;

    const bits_per_delta: usize = switch (delta_format) {
        1 => 2,
        2 => 4,
        3 => 8,
        else => return error.UnsupportedGpos,
    };
    const delta_count = @as(usize, end_size) - @as(usize, start_size) + 1;
    const words = (delta_count * bits_per_delta + 15) / 16;
    try ensureBytesWithin(table, device_offset + 6, words * 2);
}

fn ensureGlyphIdWithinMaxp(table: Table, glyph_id: usize) GposError!void {
    if (table.glyph_count) |glyph_count| {
        if (glyph_id >= glyph_count) return error.BadGpos;
    }
}

fn ensureGlyphRangeWithinMaxp(table: Table, start_glyph: u16, end_glyph: u16) GposError!void {
    try ensureGlyphIdWithinMaxp(table, start_glyph);
    try ensureGlyphIdWithinMaxp(table, end_glyph);
}

fn ensureCoverageIndicesWithin(table: Table, coverage_offset: usize, target_count: usize) GposError!void {
    const format = try readU16BadGpos(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16BadGpos(table, coverage_offset + 2);
            if (@as(usize, glyph_count) > target_count) return error.BadGpos;
        },
        2 => {
            const range_count = try readU16BadGpos(table, coverage_offset + 2);
            for (0..range_count) |range_i| {
                const range = coverage_offset + 4 + range_i * 6;
                const start = try readU16BadGpos(table, range);
                const end = try readU16BadGpos(table, range + 2);
                const start_index = try readU16BadGpos(table, range + 4);
                const span = @as(usize, end) - @as(usize, start) + 1;
                if (@as(usize, start_index) > target_count or span > target_count - @as(usize, start_index)) return error.BadGpos;
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensureContextCoverageOffsetArrayWithin(table: Table, base_offset: usize, offsets_pos: usize, count: u16) GposError!void {
    try ensureBytesWithin(table, offsets_pos, @as(usize, count) * 2);
    for (0..count) |i| {
        const coverage_offset = try checkedRequiredCoverageOffset(table, base_offset, try readU16BadGpos(table, offsets_pos + i * 2));
        try ensureContextCoverageTableWithin(table, coverage_offset);
    }
}

fn checkedMul(a: usize, b: usize) GposError!usize {
    if (a != 0 and b > std.math.maxInt(usize) / a) return error.BadGpos;
    return a * b;
}

fn ensureValueRecordWithin(table: Table, offset: usize, format: u16, value_base_offset: usize) GposError!void {
    try ensureBytesWithin(table, offset, try valueRecordSize(format));
    try ensureValueRecordDeviceOffsetsWithin(table, offset, format, value_base_offset);
}

fn ensureValueRecordDeviceOffsetsWithin(table: Table, offset: usize, format: u16, value_base_offset: usize) GposError!void {
    if (!valueRecordHasDeviceOffsets(format)) return;
    // Device/VariationIndex offsets in ValueRecords are nullable child pointers
    // relative to the immediate ValueRecord parent, not to the record itself.
    // Validate non-null children while preflighting so malformed variation data
    // cannot lurk behind otherwise usable placement/advance fields.
    var cursor = offset;
    if ((format & 0x0001) != 0) cursor += 2;
    if ((format & 0x0002) != 0) cursor += 2;
    if ((format & 0x0004) != 0) cursor += 2;
    if ((format & 0x0008) != 0) cursor += 2;
    inline for (.{ 0x0010, 0x0020, 0x0040, 0x0080 }) |bit| {
        if ((format & bit) != 0) {
            const device_offset = try readU16BadGpos(table, cursor);
            if (device_offset != 0) {
                try ensureDeviceOrVariationIndexTableWithin(table, try checkedPositionOffset(table, value_base_offset, device_offset));
            }
            cursor += 2;
        }
    }
}

fn valueRecordHasDeviceOffsets(format: u16) bool {
    return (format & 0x00f0) != 0;
}

fn ensureCoverageTableWithin(table: Table, coverage_offset: usize) GposError!void {
    return ensureCoverageTableWithinMode(table, coverage_offset, false);
}

fn ensureContextCoverageTableWithin(table: Table, coverage_offset: usize) GposError!void {
    // ContextPos/ChainContextPos format 3 use each Coverage only as a set
    // membership predicate; unlike SinglePos, PairPos, and mark attachment,
    // the CoverageIndex never selects a parallel record. Some widely deployed
    // fonts (including Noto Sans Arabic) retain a duplicate glyph in one of
    // these sets. Accept equal adjacent glyphs only for this membership-only
    // use while preserving sortedness and the strict indexed-table contract.
    return ensureCoverageTableWithinMode(table, coverage_offset, true);
}

fn ensureCoverageTableWithinMode(table: Table, coverage_offset: usize, allow_format_1_duplicates: bool) GposError!void {
    const format = try readU16BadGpos(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16BadGpos(table, coverage_offset + 2);
            try ensureBytesWithin(table, coverage_offset + 4, @as(usize, glyph_count) * 2);
            try validateCoverageFormat1OrderMode(table, coverage_offset, glyph_count, allow_format_1_duplicates);
            for (0..glyph_count) |glyph_i| {
                try ensureGlyphIdWithinMaxp(table, try readU16BadGpos(table, coverage_offset + 4 + glyph_i * 2));
            }
        },
        2 => {
            const range_count = try readU16BadGpos(table, coverage_offset + 2);
            try ensureBytesWithin(table, coverage_offset + 4, @as(usize, range_count) * 6);
            try validateCoverageFormat2Ranges(table, coverage_offset, range_count);
            for (0..range_count) |range_i| {
                const range_offset = coverage_offset + 4 + range_i * 6;
                try ensureGlyphRangeWithinMaxp(
                    table,
                    try readU16BadGpos(table, range_offset),
                    try readU16BadGpos(table, range_offset + 2),
                );
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensureClassDefTableWithin(table: Table, class_def_offset: usize) GposError!void {
    return ensureClassDefTableWithinLimit(table, class_def_offset, null);
}

fn ensureClassDefTableWithinLimit(table: Table, class_def_offset: usize, max_class_count: ?u16) GposError!void {
    const format = try readU16BadGpos(table, class_def_offset);
    switch (format) {
        1 => {
            const start_glyph = try readU16BadGpos(table, class_def_offset + 2);
            const glyph_count = try readU16BadGpos(table, class_def_offset + 4);
            try ensureBytesWithin(table, class_def_offset + 6, @as(usize, glyph_count) * 2);
            if (glyph_count != 0) {
                const end_glyph = @as(usize, start_glyph) + @as(usize, glyph_count) - 1;
                try ensureGlyphIdWithinMaxp(table, end_glyph);
            }
            if (max_class_count) |class_count| {
                for (0..glyph_count) |class_i| {
                    try ensureClassValueWithinLimit(try readU16BadGpos(table, class_def_offset + 6 + class_i * 2), class_count);
                }
            }
        },
        2 => {
            const range_count = try readU16BadGpos(table, class_def_offset + 2);
            try ensureBytesWithin(table, class_def_offset + 4, @as(usize, range_count) * 6);
            try validateClassDefFormat2Ranges(table, class_def_offset, range_count);
            for (0..range_count) |range_i| {
                const range_offset = class_def_offset + 4 + range_i * 6;
                try ensureGlyphRangeWithinMaxp(
                    table,
                    try readU16BadGpos(table, range_offset),
                    try readU16BadGpos(table, range_offset + 2),
                );
                if (max_class_count) |class_count| {
                    try ensureClassValueWithinLimit(try readU16BadGpos(table, range_offset + 4), class_count);
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensureClassValueWithinLimit(class_value: u16, class_count: u16) GposError!void {
    // PairPos format 2 uses ClassDef results as direct matrix indexes. Class 0
    // is implicit/default, but any explicit class value must still fit the
    // advertised Class1Count/Class2Count; otherwise covered pairs may be
    // silently ignored by shaping after the table declared them classed.
    if (class_value >= class_count) return error.BadGpos;
}

fn checkedPositionOffset(table: Table, base_offset: usize, relative_offset: u32) GposError!usize {
    if (relative_offset > std.math.maxInt(usize) - base_offset) return error.BadGpos;
    const absolute = base_offset + @as(usize, @intCast(relative_offset));
    if (absolute > table.length) return error.BadGpos;
    return absolute;
}

fn checkedRequiredPositionOffset(table: Table, base_offset: usize, relative_offset: u16) GposError!usize {
    if (relative_offset == 0) return error.BadGpos;
    return checkedPositionOffset(table, base_offset, @as(u32, relative_offset));
}

fn checkedExtensionPositionPayloadOffset(table: Table, extension_offset: usize, relative_offset: u32) GposError!usize {
    // ExtensionPos.ExtensionOffset is a required Offset32 to a wrapped
    // positioning subtable. It must not point back into the fixed 8-byte
    // wrapper header, where format/type/offset words can masquerade as a
    // plausible SinglePos/PairPos header and make shaping depend on aliases.
    if (relative_offset < 8) return error.BadGpos;
    return checkedPositionOffset(table, extension_offset, relative_offset);
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
    if (offset > table.length or len > table.length - offset) return error.BadGpos;
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
        try validateMarkFilteringSetIndex(lookup_options);
    }
    lookup_options.context_depth = options.context_depth + 1;
    if (lookup_type == 1) {
        if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.single_pos_subtables.len != 0) {
                if (try collectSingleAdjustmentAtAccelerated(table, accelerator.single_pos_subtables, glyphs[target_index], target_index, adjustments, allocator, lookup_flag, lookup_options)) return;
                return;
            }
        }
    }
    if (lookup_type == 8) {
        if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
            if (accelerator.chaining_coverage_only) {
                _ = try collectNestedChainingCoveragePositioningAt(table, lookup_offset, subtable_count, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options, accelerator);
                return;
            }
        }
    }
    if (lookup_type == 9) {
        if (lookupAccelerator(lookup_index, lookup_options)) |accelerator| {
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
            7 => if (try collectContextAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
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
        7 => return try collectContextAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        8 => return try collectChainingContextAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        else => {},
    }
    return false;
}

fn collectSingleAdjustmentAt(table: Table, subtable_offset: usize, glyph: GlyphId, target_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const value_format = try readU16(table, subtable_offset + 4);
    switch (pos_format) {
        1 => {
            if (try coverageIndex(table, coverage_offset, glyph) != null) {
                const value = try readValueRecord(table, subtable_offset + 6, value_format, subtable_offset);
                try appendAdjustment(adjustments, allocator, target_index, value, false);
                return true;
            }
            return false;
        },
        2 => {
            const coverage = try coverageIndex(table, coverage_offset, glyph) orelse return false;
            const value_count = try readU16(table, subtable_offset + 6);
            if (coverage >= value_count) return false;
            const value_size = try valueRecordSize(value_format);
            const value = try readValueRecord(table, subtable_offset + 8 + coverage * value_size, value_format, subtable_offset);
            try appendAdjustment(adjustments, allocator, target_index, value, false);
            return true;
        },
        else => return error.UnsupportedGpos,
    }
}

fn collectSingleAdjustmentAtAccelerated(table: Table, subtables: []const SinglePosSubtable, glyph: GlyphId, target_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;
    for (subtables) |subtable| {
        switch (subtable.pos_format) {
            1 => {
                if (try coverageIndex(table, subtable.coverage_offset, glyph) == null) continue;
                try appendAdjustment(adjustments, allocator, target_index, subtable.value, false);
                return true;
            },
            2 => {
                const coverage = try coverageIndex(table, subtable.coverage_offset, glyph) orelse continue;
                if (coverage >= subtable.value_count) continue;
                const value = try readValueRecord(table, subtable.values_pos + coverage * subtable.value_size, subtable.value_format, subtable.subtable_offset);
                try appendAdjustment(adjustments, allocator, target_index, value, false);
                return true;
            },
            else => return error.UnsupportedGpos,
        }
    }
    return false;
}

fn collectMarkToLigatureAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const class_count = try readU16(table, subtable_offset + 6);
    if (class_count == 0 or glyphs.len < 2) return;

    for (glyphs, 0..) |_, i| {
        _ = try collectMarkToLigatureAdjustmentAt(table, subtable_offset, glyphs, i, adjustments, allocator, lookup_flag, options);
    }
}

fn collectMarkToLigatureAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, mark_position: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecord application names one mark in the matched
    // input sequence. MarkLigPos still needs the complete glyph run so the
    // backwards ligature search observes the nested lookup's LookupFlag, but
    // only the record's sequenceIndex target may receive an adjustment.
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    if (mark_position >= glyphs.len) return false;
    const glyph = glyphs[mark_position];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const mark_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const ligature_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
    const ligature_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16(table, subtable_offset + 10));
    if (class_count == 0 or glyphs.len < 2) return false;

    const mark_index = try coverageIndex(table, mark_coverage_offset, glyph) orelse return false;
    const ligature_position = try previousCoveredLigatureGlyph(table, mark_coverage_offset, glyphs, mark_position, lookup_flag, options) orelse return false;
    const ligature_index = try coverageIndex(table, ligature_coverage_offset, glyphs[ligature_position]) orelse return false;
    const mark_record_offset = mark_array_offset + 2 + mark_index * 4;
    const mark_class = try readU16(table, mark_record_offset);
    if (mark_class >= class_count) return false;
    const mark_anchor_offset = try checkedRequiredPositionOffset(table, mark_array_offset, try readU16(table, mark_record_offset + 2));
    const ligature_attach_offset = ligature_array_offset + try readU16(table, ligature_array_offset + 2 + ligature_index * 2);
    const component_count = try readU16(table, ligature_attach_offset);
    if (component_count == 0) return false;
    const component_index = try ligatureComponentIndexForMark(table, mark_coverage_offset, glyphs, ligature_position, mark_position, component_count, lookup_flag, options);
    const anchor_record = ligature_attach_offset + 2 + (component_index * class_count + mark_class) * 2;
    const ligature_anchor_relative = try readU16(table, anchor_record);
    if (ligature_anchor_relative == 0) return false;
    const ligature_anchor_offset = ligature_attach_offset + ligature_anchor_relative;
    const mark_anchor = try readAnchor(table, mark_anchor_offset, options);
    const ligature_anchor = try readAnchor(table, ligature_anchor_offset, options);
    try appendAdjustmentEx(adjustments, allocator, mark_position, .{
        .index = mark_position,
        .x_placement = ligature_anchor.x - mark_anchor.x,
        .y_placement = ligature_anchor.y - mark_anchor.y,
    }, .{ .attachment_type = .mark, .attachment_parent_index = ligature_position });
    return true;
}

fn previousCoveredLigatureGlyph(table: Table, mark_coverage_offset: usize, glyphs: []const GlyphId, mark_position: usize, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = mark_position;
    while (i > 0) {
        i -= 1;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) continue;
        if (markAttachmentSearchSkipsGlyph(options, i)) continue;

        // MarkLigPos attaches marks to the nearest previous participating
        // ligature. Earlier marks in the same cluster must be transparent for
        // that search; otherwise only the first mark after a ligature can ever
        // be positioned. Non-mark glyphs still block the search for this
        // subtable even when they are not in LigatureCoverage, matching
        // HarfBuzz's nearest-non-mark search followed by coverage validation.
        if (try markAttachmentSearchSkipsNonCoveredGlyph(table, mark_coverage_offset, glyphs, i, options)) continue;
        return i;
    }
    return null;
}

fn ligatureComponentIndexForMark(table: Table, mark_coverage_offset: usize, glyphs: []const GlyphId, ligature_position: usize, mark_position: usize, component_count: usize, lookup_flag: u16, options: LookupOptions) GposError!usize {
    if (component_count <= 1) return 0;

    if (options.glyph_source_indices) |sources| {
        if (mark_position < sources.len) {
            if (options.ligature_components) |store| {
                if (ligature_position < store.infos.items.len) {
                    const info = store.infos.items[ligature_position];
                    if (baseMarkLigatureActsAsSingleBase(options.script_tag, info)) return 0;
                    const component_sources = store.componentSources(info) orelse return error.InvalidShapingInput;
                    const available_count = @min(component_sources.len, component_count);
                    if (available_count > 0) {
                        const mark_source = sources[mark_position];
                        var chosen: usize = 0;
                        // Component source positions are monotonically ordered
                        // by the GSUB ligature trace. A mark belongs to the
                        // latest component whose source position is not after
                        // that mark, which handles marks originally typed
                        // between ligature components as well as marks after
                        // the full ligature sequence.
                        for (component_sources[0..available_count], 0..) |component_source, component_i| {
                            if (component_source > mark_source) break;
                            chosen = component_i;
                        }
                        return chosen;
                    }
                }
            }
        }
    }

    var covered_marks_before_target: usize = 0;
    var pos = ligature_position + 1;
    while (pos < mark_position) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        if (markAttachmentSearchSkipsGlyph(options, pos)) continue;
        // OpenType engines normally know the original GSUB ligature component
        // for each remaining mark. When the caller does not provide that
        // metadata, use the mark's order within the post-ligature covered mark
        // run as the best available component hint. Clamp to the final
        // component so extra stacked marks still choose a valid anchor.
        if (try coverageIndex(table, mark_coverage_offset, glyphs[pos]) != null) {
            covered_marks_before_target += 1;
        }
    }
    return @min(covered_marks_before_target, component_count - 1);
}

fn markGlyphForAttachmentSearch(table: Table, mark_coverage_offset: usize, glyph: GlyphId, options: LookupOptions) GposError!bool {
    if (options.glyph_classes) |classes| {
        return glyph < classes.len and classes[glyph] == 3;
    }
    return try coverageIndex(table, mark_coverage_offset, glyph) != null;
}

fn markGlyphForAttachmentSearchParsed(table: Table, subtable: MarkToBaseSubtable, glyph: GlyphId, options: LookupOptions) GposError!bool {
    if (options.glyph_classes) |classes| {
        return glyph < classes.len and classes[glyph] == 3;
    }
    return if (subtable.mark_coverage) |coverage|
        coverage.index(glyph) != null
    else
        try coverageIndex(table, subtable.mark_coverage_offset, glyph) != null;
}

fn markAttachmentSearchSkipsNonCoveredGlyphParsed(table: Table, subtable: MarkToBaseSubtable, glyphs: []const GlyphId, index: usize, options: LookupOptions) GposError!bool {
    if (try markGlyphForAttachmentSearchParsed(table, subtable, glyphs[index], options)) return true;
    if (index == 0) return false;
    const sources = options.glyph_source_indices orelse return false;
    if (index >= sources.len) return false;
    if (sources[index] != sources[index - 1]) return false;
    if (try markGlyphForAttachmentSearchParsed(table, subtable, glyphs[index - 1], options)) return false;
    return true;
}

fn markAttachmentSearchSkipsNonCoveredGlyph(table: Table, mark_coverage_offset: usize, glyphs: []const GlyphId, index: usize, options: LookupOptions) GposError!bool {
    if (try markGlyphForAttachmentSearch(table, mark_coverage_offset, glyphs[index], options)) return true;
    return isMultipleSubstContinuationForMarkSearch(table, mark_coverage_offset, glyphs, index, options);
}

fn isMultipleSubstContinuationForMarkSearch(table: Table, mark_coverage_offset: usize, glyphs: []const GlyphId, index: usize, options: LookupOptions) GposError!bool {
    if (index == 0) return false;
    const sources = options.glyph_source_indices orelse return false;
    if (index >= sources.len) return false;
    if (sources[index] != sources[index - 1]) return false;
    if (try markGlyphForAttachmentSearch(table, mark_coverage_offset, glyphs[index - 1], options)) return false;
    return true;
}

fn collectMarkToMarkAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const class_count = try readU16(table, subtable_offset + 6);
    if (class_count == 0 or glyphs.len < 2) return;

    for (glyphs, 0..) |_, i| {
        _ = try collectMarkToMarkAdjustmentAt(table, subtable_offset, glyphs, i, adjustments, allocator, lookup_flag, options);
    }
}

fn collectMarkToMarkAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, mark_1_position: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecord application targets one matched input glyph,
    // not every mark covered by the nested MarkToMarkPos lookup. Keep the full
    // glyph run for the backwards Mark2Coverage search, but append an
    // adjustment only for the requested Mark1 position.
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    if (mark_1_position >= glyphs.len) return false;
    const glyph = glyphs[mark_1_position];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const mark_1_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 2));
    const mark_2_coverage_offset = try checkedRequiredCoverageOffset(table, subtable_offset, try readU16(table, subtable_offset + 4));
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_1_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16(table, subtable_offset + 8));
    const mark_2_array_offset = try checkedRequiredPositionOffset(table, subtable_offset, try readU16(table, subtable_offset + 10));
    if (class_count == 0 or glyphs.len < 2) return false;

    const mark_1_index = try coverageIndex(table, mark_1_coverage_offset, glyph) orelse return false;
    const mark_2_position = try previousUnignoredCoveredGlyph(table, mark_2_coverage_offset, glyphs, mark_1_position, lookup_flag, options) orelse return false;
    if (!(try marksShareLigatureComponent(table, mark_1_coverage_offset, glyphs, mark_1_position, mark_2_position, lookup_flag, options))) return false;
    const mark_2_index = try coverageIndex(table, mark_2_coverage_offset, glyphs[mark_2_position]) orelse return false;
    const mark_1_record_offset = mark_1_array_offset + 2 + mark_1_index * 4;
    const mark_class = try readU16(table, mark_1_record_offset);
    if (mark_class >= class_count) return false;
    const mark_1_anchor_offset = try checkedRequiredPositionOffset(table, mark_1_array_offset, try readU16(table, mark_1_record_offset + 2));
    const mark_2_anchor_record = mark_2_array_offset + 2 + (mark_2_index * class_count + mark_class) * 2;
    const mark_2_anchor_relative = try readU16(table, mark_2_anchor_record);
    if (mark_2_anchor_relative == 0) return false;
    const mark_2_anchor_offset = mark_2_array_offset + mark_2_anchor_relative;
    const mark_1_anchor = try readAnchor(table, mark_1_anchor_offset, options);
    const mark_2_anchor = try readAnchor(table, mark_2_anchor_offset, options);
    try appendAdjustmentEx(adjustments, allocator, mark_1_position, .{
        .index = mark_1_position,
        .x_placement = mark_2_anchor.x - mark_1_anchor.x,
        .y_placement = mark_2_anchor.y - mark_1_anchor.y,
    }, .{ .attachment_type = .mark, .attachment_parent_index = mark_2_position });
    return true;
}

fn marksShareLigatureComponent(table: Table, mark_coverage_offset: usize, glyphs: []const GlyphId, mark_1_position: usize, mark_2_position: usize, lookup_flag: u16, options: LookupOptions) GposError!bool {
    const first = try markLigatureComponentHint(table, mark_coverage_offset, glyphs, mark_1_position, lookup_flag, options) orelse return true;
    const second = try markLigatureComponentHint(table, mark_coverage_offset, glyphs, mark_2_position, lookup_flag, options) orelse return true;
    return first.ligature_position == second.ligature_position and first.component_index == second.component_index;
}

const MarkLigatureComponentHint = struct {
    ligature_position: usize,
    component_index: usize,
};

fn markLigatureComponentHint(table: Table, mark_coverage_offset: usize, glyphs: []const GlyphId, mark_position: usize, lookup_flag: u16, options: LookupOptions) GposError!?MarkLigatureComponentHint {
    const ligature_position = try previousCoveredLigatureGlyph(table, mark_coverage_offset, glyphs, mark_position, lookup_flag, options) orelse return null;
    const store = options.ligature_components orelse return null;
    if (ligature_position >= store.infos.items.len) return null;
    const info = store.infos.items[ligature_position];
    if (baseMarkLigatureActsAsSingleBase(options.script_tag, info)) return null;
    if (info.component_count <= 1) return null;
    const component_sources = store.componentSources(info) orelse return error.InvalidShapingInput;
    const sources = options.glyph_source_indices orelse return null;
    if (mark_position >= sources.len) return null;

    const mark_source = sources[mark_position];
    var component_index: usize = 0;
    for (component_sources, 0..) |component_source, index| {
        if (component_source > mark_source) break;
        component_index = index;
    }
    return .{ .ligature_position = ligature_position, .component_index = component_index };
}

fn baseMarkLigatureActsAsSingleBase(script_tag: unicode.OpenTypeScriptTag, info: ligature_provenance.Info) bool {
    return info.flags.base_mark_ligature and script_tag == .hebr;
}

const Anchor = struct {
    x: i16,
    y: i16,
};

fn readAnchor(table: Table, anchor_offset: usize, options: LookupOptions) GposError!Anchor {
    const format = try readU16(table, anchor_offset);
    return switch (format) {
        1 => blk: {
            if (anchor_offset + 6 > table.length) return error.EndOfStream;
            break :blk .{
                .x = try readI16(table, anchor_offset + 2),
                .y = try readI16(table, anchor_offset + 4),
            };
        },
        2 => blk: {
            if (anchor_offset + 8 > table.length) return error.EndOfStream;
            break :blk .{
                .x = try readI16(table, anchor_offset + 2),
                .y = try readI16(table, anchor_offset + 4),
            };
        },
        3 => blk: {
            if (anchor_offset + 10 > table.length) return error.EndOfStream;
            var x: i32 = try readI16(table, anchor_offset + 2);
            var y: i32 = try readI16(table, anchor_offset + 4);
            x += try anchorVariationDelta(table, anchor_offset, try readU16(table, anchor_offset + 6), options);
            y += try anchorVariationDelta(table, anchor_offset, try readU16(table, anchor_offset + 8), options);
            break :blk .{
                .x = std.math.cast(i16, x) orelse return error.BadGpos,
                .y = std.math.cast(i16, y) orelse return error.BadGpos,
            };
        },
        else => error.UnsupportedGpos,
    };
}

fn anchorVariationDelta(table: Table, anchor_offset: usize, relative_offset: u16, options: LookupOptions) GposError!i32 {
    if (relative_offset == 0 or options.normalized_variation_coords.len == 0) return 0;
    const device_offset = try checkedPositionOffset(table, anchor_offset, relative_offset);
    const delta_format = try readU16(table, device_offset + 4);
    // Device tables are PPEM-dependent and remain outside this font-unit
    // shaping API. DeltaFormat 0x8000 is the variation-common VariationIndex
    // encoding: StartSize/EndSize are its outer/inner ItemVariationStore keys.
    if (delta_format != 0x8000) return 0;
    const store = options.gdef_variation_store orelse return 0;
    return metric_variation.itemVariationDelta(
        store.data,
        store.table_offset,
        store.table_length,
        store.store_offset,
        .{
            .outer = try readU16(table, device_offset),
            .inner = try readU16(table, device_offset + 2),
        },
        options.normalized_variation_coords,
    ) catch |err| switch (err) {
        error.BadSfnt, error.EndOfStream => error.BadGpos,
        error.OutOfMemory => unreachable,
    };
}

fn valueRecordSize(format: u16) GposError!usize {
    // OpenType ValueFormat is a 16-bit bitset, but only the low byte is
    // assigned for pair/single positioning value records. Accepting unknown
    // high bits would make the parser compute too-small record strides and
    // reinterpret trailing payload bytes as subsequent PairValue/Class records.
    if ((format & 0xff00) != 0) return error.BadGpos;
    var size: usize = 0;
    if ((format & 0x0001) != 0) size += 2;
    if ((format & 0x0002) != 0) size += 2;
    if ((format & 0x0004) != 0) size += 2;
    if ((format & 0x0008) != 0) size += 2;
    if ((format & 0x0010) != 0) size += 2;
    if ((format & 0x0020) != 0) size += 2;
    if ((format & 0x0040) != 0) size += 2;
    if ((format & 0x0080) != 0) size += 2;
    return size;
}

fn readValueRecord(table: Table, offset: usize, format: u16, value_base_offset: usize) GposError!Adjustment {
    // ValueFormat bits decide which signed fields are present and in what order.
    // Device/variation-index offset fields are parsed and skipped for now: the
    // base placement/advance remains valid, while size-specific deltas can be
    // layered in later without rejecting common production fonts outright.
    try ensureValueRecordWithin(table, offset, format, value_base_offset);
    var value = Adjustment{ .index = 0 };
    var cursor = offset;
    if ((format & 0x0001) != 0) {
        value.x_placement = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x0002) != 0) {
        value.y_placement = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x0004) != 0) {
        value.x_advance = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x0008) != 0) {
        value.y_advance = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x0010) != 0) cursor += 2;
    if ((format & 0x0020) != 0) cursor += 2;
    if ((format & 0x0040) != 0) cursor += 2;
    if ((format & 0x0080) != 0) cursor += 2;
    return value;
}

fn coverageIndex(table: Table, coverage_offset: usize, glyph: GlyphId) GposError!?usize {
    // Coverage handling mirrors GSUB so coverage index semantics remain
    // identical between substitution and positioning code. The OpenType
    // contract requires sorted glyph arrays and sorted, non-overlapping ranges;
    // enforcing that here keeps malformed positioning data from quietly
    // selecting the wrong value record.
    const format = try readU16(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16(table, coverage_offset + 2);
            if (!table.assume_validated) try validateCoverageFormat1Order(table, coverage_offset, glyph_count);
            var lo: usize = 0;
            var hi: usize = glyph_count;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const candidate = try readU16(table, coverage_offset + 4 + mid * 2);
                if (glyph < candidate) {
                    hi = mid;
                } else if (glyph > candidate) {
                    lo = mid + 1;
                } else {
                    return mid;
                }
            }
            return null;
        },
        2 => {
            const range_count = try readU16(table, coverage_offset + 2);
            if (!table.assume_validated) try validateCoverageFormat2Ranges(table, coverage_offset, range_count);
            if (try findSortedGlyphRangeRecord(table, coverage_offset + 4, range_count, glyph)) |record| {
                // Keep coverage-index arithmetic in usize. Malformed or
                // edge-of-glyph-space ranges can otherwise overflow u16 in
                // safety builds before callers get a chance to bounds-check
                // the resulting index against their subtable-specific counts.
                return @as(usize, record.value) + (@as(usize, glyph) - @as(usize, record.start));
            }
            return null;
        },
        else => return error.UnsupportedGpos,
    }
}

fn coverageDigest(table: Table, coverage_offset: usize) GposError!GlyphDigest {
    const format = try readU16(table, coverage_offset);
    var digest = GlyphDigest.empty();
    switch (format) {
        1 => {
            const glyph_count = try readU16(table, coverage_offset + 2);
            if (!table.assume_validated) try validateCoverageFormat1Order(table, coverage_offset, glyph_count);
            for (0..glyph_count) |glyph_i| {
                digest.add(try readU16(table, coverage_offset + 4 + glyph_i * 2));
            }
        },
        2 => {
            const range_count = try readU16(table, coverage_offset + 2);
            if (!table.assume_validated) try validateCoverageFormat2Ranges(table, coverage_offset, range_count);
            for (0..range_count) |range_i| {
                const range_offset = coverage_offset + 4 + range_i * 6;
                digest.addRange(try readU16(table, range_offset), try readU16(table, range_offset + 2));
            }
        },
        else => return error.UnsupportedGpos,
    }
    return digest;
}

fn appendChainingSubtablePairs(table: Table, coverage_offset: usize, subtable_index: u16, pairs: *std.ArrayList(ChainingSubtablePair), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const format = try readU16(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16(table, coverage_offset + 2);
            if (!table.assume_validated) try validateCoverageFormat1Order(table, coverage_offset, glyph_count);
            try pairs.ensureUnusedCapacity(allocator, glyph_count);
            for (0..glyph_count) |glyph_i| {
                pairs.appendAssumeCapacity(.{
                    .glyph = try readU16(table, coverage_offset + 4 + glyph_i * 2),
                    .subtable_index = subtable_index,
                });
            }
        },
        2 => {
            const range_count = try readU16(table, coverage_offset + 2);
            if (!table.assume_validated) try validateCoverageFormat2Ranges(table, coverage_offset, range_count);
            for (0..range_count) |range_i| {
                const range_offset = coverage_offset + 4 + range_i * 6;
                const start = try readU16(table, range_offset);
                const end = try readU16(table, range_offset + 2);
                try pairs.ensureUnusedCapacity(allocator, @as(usize, end) - @as(usize, start) + 1);
                for (@as(usize, start)..@as(usize, end) + 1) |glyph| {
                    pairs.appendAssumeCapacity(.{
                        .glyph = @intCast(glyph),
                        .subtable_index = subtable_index,
                    });
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn findSortedGlyphRangeRecord(table: Table, records_offset: usize, range_count: u16, glyph: GlyphId) GposError!?ot_layout.GlyphRangeRecord {
    if (table.offset > table.data.len or table.length > table.data.len - table.offset) return error.EndOfStream;
    const data = table.data[table.offset .. table.offset + table.length];
    return ot_layout.findSortedGlyphRangeRecord(data, records_offset, range_count, glyph) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

fn buildChainingSubtableGroups(pairs: []ChainingSubtablePair, allocator: std.mem.Allocator) std.mem.Allocator.Error![]ChainingSubtableGroup {
    if (pairs.len == 0) return try allocator.alloc(ChainingSubtableGroup, 0);
    std.sort.heap(ChainingSubtablePair, pairs, {}, chainingSubtablePairLessThan);

    var group_count: usize = 1;
    var previous_glyph = pairs[0].glyph;
    for (pairs[1..]) |pair| {
        if (pair.glyph == previous_glyph) continue;
        group_count += 1;
        previous_glyph = pair.glyph;
    }

    const groups = try allocator.alloc(ChainingSubtableGroup, group_count);
    var built_group_count: usize = 0;
    errdefer {
        for (groups[0..built_group_count]) |group| allocator.free(group.subtable_indices);
        allocator.free(groups);
    }
    var pair_index: usize = 0;
    for (groups) |*group| {
        const glyph = pairs[pair_index].glyph;
        const start = pair_index;
        while (pair_index < pairs.len and pairs[pair_index].glyph == glyph) : (pair_index += 1) {}
        const indices = try allocator.alloc(u16, pair_index - start);
        for (indices, 0..) |*index, i| {
            index.* = pairs[start + i].subtable_index;
        }
        group.* = .{ .glyph = glyph, .subtable_indices = indices };
        built_group_count += 1;
    }
    return groups;
}

const min_chaining_groups_for_hash = 8;
const min_run_glyphs_for_chaining_digest = 16;

fn chainingLookupUsesGlyphDigest(glyph_count: usize) bool {
    return glyph_count >= min_run_glyphs_for_chaining_digest;
}

fn buildChainingGroupSlots(groups: []const ChainingSubtableGroup, allocator: std.mem.Allocator) std.mem.Allocator.Error![]u16 {
    if (groups.len < min_chaining_groups_for_hash or groups.len > std.math.maxInt(u16)) return try allocator.alloc(u16, 0);
    // Match GSUB's bounded first-input index: an empty zero slot and at most
    // 50% load keep both successful and negative GPOS coverage probes short.
    const slot_count = std.math.ceilPowerOfTwo(usize, groups.len * 2) catch return error.OutOfMemory;
    const slots = try allocator.alloc(u16, slot_count);
    @memset(slots, 0);
    for (groups, 0..) |group, group_i| {
        var slot = chainingGroupHash(group.glyph) & (slots.len - 1);
        while (slots[slot] != 0) slot = (slot + 1) & (slots.len - 1);
        slots[slot] = @intCast(group_i + 1);
    }
    return slots;
}

fn chainingSubtableGroupForGlyph(groups: []const ChainingSubtableGroup, slots: []const u16, glyph: GlyphId) ?[]const u16 {
    if (slots.len != 0) {
        var slot = chainingGroupHash(glyph) & (slots.len - 1);
        while (slots[slot] != 0) : (slot = (slot + 1) & (slots.len - 1)) {
            const group = groups[slots[slot] - 1];
            if (group.glyph == glyph) return group.subtable_indices;
        }
        return null;
    }

    var lo: usize = 0;
    var hi: usize = groups.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const candidate = groups[mid].glyph;
        if (glyph < candidate) {
            hi = mid;
        } else if (glyph > candidate) {
            lo = mid + 1;
        } else {
            return groups[mid].subtable_indices;
        }
    }
    return null;
}

fn chainingGroupHash(glyph: GlyphId) usize {
    return @as(usize, glyph) *% 0x9e37;
}

test "GPOS chaining group slots preserve hits and misses" {
    const allocator = std.testing.allocator;
    var groups: [min_chaining_groups_for_hash]ChainingSubtableGroup = undefined;
    var group_indices: [min_chaining_groups_for_hash][1]u16 = undefined;
    for (&groups, 0..) |*group, i| {
        group_indices[i][0] = @intCast(i);
        group.* = .{
            .glyph = @intCast(13 + i * 19),
            .subtable_indices = &group_indices[i],
        };
    }
    const slots = try buildChainingGroupSlots(&groups, allocator);
    defer allocator.free(slots);
    for (groups, 0..) |group, i| {
        const indices = chainingSubtableGroupForGlyph(&groups, slots, group.glyph) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualSlices(u16, &.{@intCast(i)}, indices);
    }
    try std.testing.expect(chainingSubtableGroupForGlyph(&groups, slots, 12) == null);

    const small_groups = groups[0 .. min_chaining_groups_for_hash - 1];
    const small_slots = try buildChainingGroupSlots(small_groups, allocator);
    defer allocator.free(small_slots);
    try std.testing.expectEqual(@as(usize, 0), small_slots.len);
    const fallback = chainingSubtableGroupForGlyph(small_groups, small_slots, small_groups[3].glyph) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u16, &group_indices[3], fallback);
}

test "GPOS chaining glyph digest activates only for amortized runs" {
    var digest = GlyphDigest.empty();
    digest.add(20);
    const definite_miss: GlyphId = 21;
    try std.testing.expect(!digest.mayHave(definite_miss));
    try std.testing.expect(!chainingLookupUsesGlyphDigest(min_run_glyphs_for_chaining_digest - 1));
    try std.testing.expect(chainingLookupUsesGlyphDigest(min_run_glyphs_for_chaining_digest));

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
    try std.testing.expect(chainingSubtableGroupForGlyph(&groups, &.{}, collision.?) == null);
}

fn contextCoverageContains(table: Table, coverage_offset: usize, glyph: GlyphId) GposError!bool {
    const format = try readU16(table, coverage_offset);
    if (format != 1) return (try coverageIndex(table, coverage_offset, glyph)) != null;

    const glyph_count = try readU16(table, coverage_offset + 2);
    if (!table.assume_validated) {
        try ensureBytesWithin(table, coverage_offset + 4, @as(usize, glyph_count) * 2);
        try validateCoverageFormat1OrderMode(table, coverage_offset, glyph_count, true);
    }
    var lo: usize = 0;
    var hi: usize = glyph_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const candidate = try readU16(table, coverage_offset + 4 + mid * 2);
        if (glyph < candidate) {
            hi = mid;
        } else if (glyph > candidate) {
            lo = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

fn validateCoverageFormat1Order(table: Table, coverage_offset: usize, glyph_count: u16) GposError!void {
    return validateCoverageFormat1OrderMode(table, coverage_offset, glyph_count, false);
}

fn validateCoverageFormat1OrderMode(table: Table, coverage_offset: usize, glyph_count: u16, allow_duplicates: bool) GposError!void {
    var previous: ?GlyphId = null;
    for (0..glyph_count) |index| {
        const glyph = try readU16BadGpos(table, coverage_offset + 4 + index * 2);
        if (previous) |last| {
            if (glyph < last or (!allow_duplicates and glyph == last)) return error.BadGpos;
        }
        previous = glyph;
    }
}

fn validateCoverageFormat2Ranges(table: Table, coverage_offset: usize, range_count: u16) GposError!void {
    var previous_end: ?GlyphId = null;
    var expected_start_index: usize = 0;
    for (0..range_count) |index| {
        const range_offset = coverage_offset + 4 + index * 6;
        const start = try readU16BadGpos(table, range_offset);
        const end = try readU16BadGpos(table, range_offset + 2);
        const start_index = try readU16BadGpos(table, range_offset + 4);
        if (end < start) return error.BadGpos;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadGpos;
        }
        // StartCoverageIndex is the dense coverage index assigned to the first
        // glyph in this range. Checking it in the shared coverage validator
        // keeps every GPOS subtable's value arrays aligned with coverage data.
        if (expected_start_index > std.math.maxInt(u16) or start_index != expected_start_index) return error.BadGpos;
        previous_end = end;
        expected_start_index += @as(usize, end) - @as(usize, start) + 1;
    }
}

fn classValue(table: Table, class_def_offset: usize, glyph: GlyphId) GposError!u16 {
    const format = try readU16(table, class_def_offset);
    switch (format) {
        1 => {
            const start = try readU16(table, class_def_offset + 2);
            const count = try readU16(table, class_def_offset + 4);
            // ClassDef format 1 describes a half-open range, but `start +
            // count` is not guaranteed to fit in GlyphId's u16 type near the
            // upper glyph boundary. Widen before comparing so edge-range class
            // definitions behave deterministically instead of trapping.
            const glyph_index = @as(usize, glyph);
            const start_index = @as(usize, start);
            const end_exclusive = start_index + @as(usize, count);
            if (glyph_index < start_index or glyph_index >= end_exclusive) return 0;
            return try readU16(table, class_def_offset + 6 + (glyph_index - start_index) * 2);
        },
        2 => {
            const range_count = try readU16(table, class_def_offset + 2);
            if (!table.assume_validated) try validateClassDefFormat2Ranges(table, class_def_offset, range_count);
            return if (try findSortedGlyphRangeRecord(table, class_def_offset + 4, range_count, glyph)) |record| record.value else 0;
        },
        else => return error.UnsupportedGpos,
    }
}

fn validateClassDefFormat2Ranges(table: Table, class_def_offset: usize, range_count: u16) GposError!void {
    // PairPos class matrices and contextual class matching assume ClassDef
    // format 2 ranges are canonical: sorted, non-overlapping, and individually
    // ordered. Rejecting malformed ranges keeps an early overlapping record
    // from silently selecting the wrong positioning class.
    var previous_end: ?GlyphId = null;
    for (0..range_count) |index| {
        const range_offset = class_def_offset + 4 + index * 6;
        const start = try readU16BadGpos(table, range_offset);
        const end = try readU16BadGpos(table, range_offset + 2);
        if (end < start) return error.BadGpos;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadGpos;
        }
        previous_end = end;
    }
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
    try std.testing.expectError(error.BadGpos, extensionPositionSubtablePayload(table, 0, 1));
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
    try std.testing.expectError(error.BadGpos, extensionPositionSubtablePayload(table, 0, 1));
    try std.testing.expectError(error.BadGpos, ensureExtensionPositionPayloadWithin(table, 0));
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
    try ensureAnchorTableWithin(table, 0);

    writeU16Test(&bytes, 6, 14); // Points inside an incomplete child DeviceTable.
    try std.testing.expectError(error.BadGpos, ensureAnchorTableWithin(table, 0));

    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 12, 11); // endSize must not precede startSize.
    try std.testing.expectError(error.BadGpos, ensureAnchorTableWithin(table, 0));

    writeU16Test(&bytes, 12, 14);
    writeU16Test(&bytes, 14, 4); // Unknown delta formats cannot be sized safely.
    try std.testing.expectError(error.UnsupportedGpos, ensureAnchorTableWithin(table, 0));

    writeU16Test(&bytes, 14, 0x8000); // VariationIndex table: three uint16 fields only.
    try ensureAnchorTableWithin(table, 0);
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
    try std.testing.expectEqual(@as(?usize, 0xfffe), try coverageIndex(table, 0, 0xfffe));
    try std.testing.expectEqual(@as(?usize, 0xffff), try coverageIndex(table, 0, 0xffff));
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
    try std.testing.expectError(error.BadGpos, coverageIndex(table, 0, 3));
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
    try ensureContextCoverageTableWithin(table, 0);
    try std.testing.expect(try contextCoverageContains(table, 0, 5));
    try std.testing.expect(!(try contextCoverageContains(table, 0, 6)));
    try std.testing.expect(try contextCoverageContains(table, 0, 7));

    // Indexed consumers still reject duplicate CoverageIndex values because
    // they select parallel arrays and cannot discard an index deterministically.
    try std.testing.expectError(error.BadGpos, ensureCoverageTableWithin(table, 0));
    try std.testing.expectError(error.BadGpos, coverageIndex(table, 0, 5));

    writeU16Test(&bytes, 8, 4);
    try std.testing.expectError(error.BadGpos, ensureContextCoverageTableWithin(table, 0));
    try std.testing.expectError(error.BadGpos, contextCoverageContains(table, 0, 5));
}

test "GPOS rejects reserved ValueFormat bits" {
    var bytes = [_]u8{0} ** 18;
    writeU16Test(&bytes, 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, 2, 8);
    writeU16Test(&bytes, 4, 0x0100); // Reserved ValueFormat bit.
    writeCoverage1Test(&bytes, 8, 5);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, ensureSinglePositionSubtableWithin(table, 0));
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
    try std.testing.expectError(error.BadGpos, ensureSinglePositionSubtableWithin(table, 0));
}

test "GPOS class format 1 handles upper glyph boundary" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0xfffe);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 7);
    writeU16Test(&bytes, 8, 9);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(@as(u16, 7), try classValue(table, 0, 0xfffe));
    try std.testing.expectEqual(@as(u16, 9), try classValue(table, 0, 0xffff));
    try std.testing.expectEqual(@as(u16, 0), try classValue(table, 0, 0xfffd));
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
    const cached = try lookupDispatch(0, 0, .{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, .{ .lookup_accelerators = &accelerators });
    try std.testing.expectEqual(@as(u16, 8), cached.lookup_type);
    try std.testing.expectEqual(@as(u16, 4), cached.subtable_count);
    try std.testing.expectEqual(@as(?u16, 7), cached.mark_filtering_set);

    const parsed = try lookupDispatch(0, 0, .{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, .{ .lookup_accelerators = &accelerators });
    try std.testing.expectEqual(@as(u16, 1), parsed.lookup_type);
    try std.testing.expectEqual(@as(u16, 0x0010), parsed.lookup_flag);
    try std.testing.expectEqual(@as(?u16, 0xffff), parsed.mark_filtering_set);

    var stale = accelerators;
    stale[0].lookup_offset = 2;
    const stale_fallback = try lookupDispatch(0, 0, .{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, .{ .lookup_accelerators = &stale });
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
        try resolvedExtensionPositionLookupType(validated, 0, 9, 1, 0, .{
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
        try resolvedExtensionPositionLookupType(unvalidated, 0, 9, 1, 0, .{
            .lookup_accelerators = &accelerators,
        }),
    );
    var stale = accelerators;
    stale[0].lookup_offset = 2;
    try std.testing.expectEqual(
        @as(?u16, 1),
        try resolvedExtensionPositionLookupType(validated, 0, 9, 1, 0, .{
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
    try std.testing.expectError(error.BadGpos, ensurePositionLookupHeaderWithin(table, 14));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));

    writeU16Test(&bytes, 16, 0xff10); // MarkAttachmentType plus UseMarkFilteringSet are valid.
    writeU16Test(&bytes, 22, 0); // MarkFilteringSet index follows the subtable-offset array.
    try ensurePositionLookupHeaderWithin(table, 14);
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
    try std.testing.expectError(error.BadGpos, ensureSinglePositionSubtableWithin(table, subtable));
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
    try ensureSinglePositionSubtableWithin(table, subtable);
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
    try std.testing.expectError(error.BadGpos, classValue(table, 0, 12));
    const validated_table = Table{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true };
    try std.testing.expectEqual(@as(u16, 1), try classValue(validated_table, 0, 12));

    writeU16Test(&bytes, 10, 13); // Repair overlap so the reversed range is checked.
    try std.testing.expectError(error.BadGpos, classValue(table, 0, 18));
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

    const value = try readValueRecord(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, 0x00ff, 0);
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
    try std.testing.expectError(error.BadGpos, ensureValueRecordWithin(table, std.math.maxInt(usize) - 1, 0x0004, 0));
    try std.testing.expectError(error.BadGpos, readValueRecord(table, std.math.maxInt(usize) - 1, 0x0004, 0));
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
    try std.testing.expectError(error.BadGpos, ensureSinglePositionSubtableWithin(table, 0));

    // If the same offset were incorrectly interpreted relative to the
    // ValueRecord at byte 6 it would point into this valid Coverage table.
    // Repairing the parent-relative Device table makes the subtable valid.
    writeU16Test(&bytes, 10, 12);
    writeU16Test(&bytes, 12, 12);
    writeU16Test(&bytes, 14, 1);
    try ensureSinglePositionSubtableWithin(table, 0);
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
    try ensurePairPositionSubtableWithin(table, 0);

    writeU16Test(&bytes, pair_set + 6, 16); // Points at the Device payload word.
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));
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
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));
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
    const accelerator = try appendSimplePairPosFormat1Records(
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
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));

    // A real, non-null empty PairSet remains valid. The parser must reject
    // only the aliasing offset, not empty pair data.
    writeU16Test(&bytes, 10, 12);
    writeU16Test(&bytes, 12, 0);
    try ensurePairPositionSubtableWithin(table, 0);
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
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectPairAdjustment(table, 0, &.{ 5, 11 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, pair_set + 6, 12);
    try ensurePairPositionSubtableWithin(table, 0);
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
    const hit = try findValidatedPairValueRecord(table, pair_set, 3, 2, 0, 12) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, pair_set + 6), hit);
    try std.testing.expectEqual(@as(?usize, null), try findValidatedPairValueRecord(table, pair_set, 3, 2, 0, 11));
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
    const candidates = chainingSubtableGroupForGlyph(
        accelerator.coverage_groups,
        accelerator.coverage_group_slots,
        5,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, candidates);
    try std.testing.expect(chainingSubtableGroupForGlyph(
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
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
            .glyph_substituted = &substituted,
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
    const accelerator = try appendSimplePairPosRecords(
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
    try std.testing.expect(shouldBuildDensePairClasses(.{
        .coverage_base = 0,
        .coverage_len = max_dense_pair_class_entries - 1,
        .class_2_base = 0,
        .class_2_len = 1,
    }));
    try std.testing.expect(!shouldBuildDensePairClasses(.{
        .coverage_base = 0,
        .coverage_len = max_dense_pair_class_entries,
        .class_2_base = 0,
        .class_2_len = 1,
    }));
    try std.testing.expect(!shouldBuildDensePairClasses(.{
        .coverage_base = 0,
        .coverage_len = max_dense_pair_class_entries + 1,
        .class_2_base = 0,
        .class_2_len = 0,
    }));
}

test "GPOS dense class PairPos rejects entries outside endpoint ranges" {
    try std.testing.expect(pairClassDenseRanges(
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

    const ranges = PairClassDenseRanges{
        .coverage_base = 5,
        .coverage_len = 16,
        .class_2_base = 7,
        .class_2_len = 94,
    };
    try std.testing.expect(!pairClassEntriesFitDenseRanges(
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
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));

    writeU16Test(&bytes, 22, 1);
    try ensurePairPositionSubtableWithin(table, 0);

    writeU16Test(&bytes, 30, 1); // Now ClassDef2 exceeds Class2Count.
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));
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
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectPairAdjustment(table, 0, &.{ 10, 11 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&pair_bytes, 8, 18);
    writeU16Test(&pair_bytes, 10, 0); // ClassDef2 is required too.
    try std.testing.expectError(error.BadGpos, ensurePairPositionSubtableWithin(table, 0));

    writeU16Test(&pair_bytes, 10, 26);
    try ensurePairPositionSubtableWithin(table, 0);
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
    try std.testing.expectError(error.BadGpos, collectClassPositioning(table, 0, &.{5}, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&context_bytes, 4, 18);
    try ensureContextPositionSubtableWithin(table, 0, 0);
    try collectClassPositioning(table, 0, &.{5}, &adjustments, allocator, 0, .{});
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
    try std.testing.expectError(error.BadGpos, collectChainingClassPositioning(table, 0, &.{5}, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    writeU16Test(&chaining_bytes, 6, 30);

    writeU16Test(&chaining_bytes, 8, 0);
    try std.testing.expectError(error.BadGpos, ensureChainingContextPositionSubtableWithin(table, 0, 0));
    writeU16Test(&chaining_bytes, 8, 38);

    try ensureChainingContextPositionSubtableWithin(table, 0, 0);
    try collectChainingClassPositioning(table, 0, &.{5}, &adjustments, allocator, 0, .{});
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
    try ensureMarkToBasePositionSubtableWithin(table, 0);

    writeU16Test(&bytes, 8, 0); // Invalid: MarkArray offsets are not nullable.
    try std.testing.expectError(error.BadGpos, ensureMarkToBasePositionSubtableWithin(table, 0));
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectMarkToBaseAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, 8, 24);
    writeU16Test(&bytes, 10, 0); // Invalid: BaseArray offsets are not nullable.
    try std.testing.expectError(error.BadGpos, ensureMarkToBasePositionSubtableWithin(table, 0));

    writeU16Test(&bytes, 10, 36);
    writeU16Test(&bytes, mark_array + 4, 0); // Invalid: MarkRecord anchors are required.
    try std.testing.expectError(error.BadGpos, ensureMarkToBasePositionSubtableWithin(table, 0));
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
    try std.testing.expectError(error.BadGpos, ensureMarkToLigaturePositionSubtableWithin(table, 0));
    try std.testing.expectError(error.BadGpos, collectMarkToLigatureAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    writeU16Test(&bytes, 8, 24);

    writeU16Test(&bytes, 10, 0); // Invalid: LigatureArray offsets are not nullable.
    try std.testing.expectError(error.BadGpos, ensureMarkToLigaturePositionSubtableWithin(table, 0));
    try std.testing.expectError(error.BadGpos, collectMarkToLigatureAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    writeU16Test(&bytes, 10, 36);

    try std.testing.expectError(error.BadGpos, ensureMarkToLigaturePositionSubtableWithin(table, 0));

    // A real LigatureAttach may still omit individual class anchors with null
    // offsets; only the LigatureAttach child pointer itself is mandatory.
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 1);
    writeU16Test(&bytes, ligature_attach + 2, 0);
    try ensureMarkToLigaturePositionSubtableWithin(table, 0);

    writeU16Test(&bytes, ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, ligature_attach + 4, 100, 120);
    try ensureMarkToLigaturePositionSubtableWithin(table, 0);

    writeU16Test(&bytes, mark_array + 4, 0); // Invalid: MarkRecord anchors are required.
    try std.testing.expectError(error.BadGpos, ensureMarkToLigaturePositionSubtableWithin(table, 0));
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
    try ensureMarkToMarkPositionSubtableWithin(table, 0);

    writeU16Test(&bytes, 8, 0); // Invalid: Mark1Array offsets are not nullable.
    try std.testing.expectError(error.BadGpos, ensureMarkToMarkPositionSubtableWithin(table, 0));
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectMarkToMarkAdjustment(table, 0, &.{ 20, 22 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&bytes, 8, 24);
    writeU16Test(&bytes, 10, 0); // Invalid: Mark2Array offsets are not nullable.
    try std.testing.expectError(error.BadGpos, ensureMarkToMarkPositionSubtableWithin(table, 0));

    writeU16Test(&bytes, 10, 36);
    writeU16Test(&bytes, mark_1_array + 4, 0); // Invalid: MarkRecord anchors are required.
    try std.testing.expectError(error.BadGpos, ensureMarkToMarkPositionSubtableWithin(table, 0));
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
    const parsed = try buildCursivePositionSubtable(table, cursive, allocator);
    defer if (parsed.coverage) |coverage| deinitNativeCoverage(allocator, coverage);

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
        .glyph_source_indices = &sources,
        .source_codepoints = &codepoints,
        .glyph_substituted = &.{ false, false, false },
    });
    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);

    adjustments.clearRetainingCapacity();
    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_source_indices = &sources,
        .source_codepoints = &codepoints,
        .glyph_substituted = &.{ false, true, false },
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
        .glyph_source_indices = &sources,
        .ligature_components = &ligature_components,
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
        .glyph_source_indices = &sources,
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
        .ligature_components = &ligature_components,
    }));
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
    // `relative` is ultimately derived from font-supplied offsets. Keep the
    // bounds check in subtraction form so hostile values near usize.max report
    // a parser error instead of overflowing before the table slice is read.
    if (relative > table.length or table.length - relative < 2) return error.EndOfStream;
    return bin.readU16At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

fn readI16(table: Table, relative: usize) GposError!i16 {
    if (relative > table.length or table.length - relative < 2) return error.EndOfStream;
    return bin.readI16At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

fn readU32(table: Table, relative: usize) GposError!u32 {
    if (relative > table.length or table.length - relative < 4) return error.EndOfStream;
    return bin.readU32At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}
