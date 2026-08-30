//! Decoded GSUB lookup sidecars shared across shaping runs.
//!
//! These are concrete borrowed/owned value types. The builder owns every
//! mutable allocation, while a `Lookup` slice is borrowed by shaping options.

const std = @import("std");
const GlyphDigest = @import("../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../glyph.zig").GlyphId;
const class_context = @import("../../opentype/class_context.zig");

/// Contextual and ligature acceleration use fixed stack scratch for component
/// offsets. Builders omit larger authored definitions so runtime execution and
/// cached sidecars share one explicit bound.
pub const max_ligature_components = 64;

/// Class-based contextual accelerators and their runtime matchers share fixed
/// stack windows. Keep the builder admission policy and executor storage bound
/// as one model contract so neither side can silently accept wider rules.
pub const max_context_region_glyphs = 64;

pub const Lookup = struct {
    /// Dispatch fields decoded once from the validated Lookup table. Runtime
    /// use checks `lookup_offset`, so a stale or foreign sidecar falls back to
    /// the defensive parser.
    lookup_offset: usize = 0,
    lookup_type: u16 = 0,
    lookup_flag: u16 = 0,
    subtable_count: u16 = 0,
    mark_filtering_set: ?u16 = null,
    /// Stored on entry zero because feature selection is table-wide.
    feature_index: ?*const FeatureIndex = null,
    /// Stored on entry zero for an O(1) table-level capability check.
    table_uses_run_digest_cache: bool = false,
    extension_lookup_type: ?u16 = null,
    single_subst: SingleSubstitution = .{},
    single_subst_entries: []const SingleEntry = &.{},
    multiple_subst: MultipleSubstitution = .{},
    ligature_subst: LigatureSubstitution = .{},
    context_class_subtables: []const ContextClassSubtable = &.{},
    context_coverage_subtables: []const ContextCoverageSubtable = &.{},
    context_coverage_offsets: []const usize = &.{},
    context_groups: []const ChainingGroup = &.{},
    context_group_slots: []const u16 = &.{},
    chaining_coverage_only: bool = false,
    chaining_needs_second_input: bool = false,
    chaining_needs_backtrack: bool = false,
    chaining_needs_single_input_lookahead: bool = false,
    chaining_input_digest: GlyphDigest = .{},
    chaining_subtable_digests: []const GlyphDigest = &.{},
    chaining_subtables: []const ChainingCoverageSubtable = &.{},
    chaining_groups: []const ChainingGroup = &.{},
    chaining_group_slots: []const u16 = &.{},
    chaining_pair_groups: []const ChainingPairGroup = &.{},
    chaining_pair_group_slots: []const u16 = &.{},
    chaining_pair_index_complete: bool = false,
    chaining_class_subtables: []const ChainingClassSubtable = &.{},
    reverse_chaining_subtables: []const ReverseChainingSingleSubtable = &.{},
    reverse_chaining_groups: []const ChainingGroup = &.{},
    reverse_chaining_exact_contexts: []const ReverseChainingContextEntry = &.{},
};

pub const FeatureRecord = struct {
    tag: u32,
    lookup_start: usize,
    lookup_len: usize,
    borrowable: bool,
};

pub const FeatureIndex = struct {
    data_ptr: [*]const u8,
    data_len: usize,
    table_offset: usize,
    table_length: usize,
    // Bind the table-wide feature index to the exact lookup sidecar slice.
    // Copying a Lookup and retaining this pointer must not make a foreign
    // accelerator eligible for trusted feature selection.
    accelerators_addr: usize,
    accelerator_count: usize,
    has_random_feature: bool,
    records: []FeatureRecord,
    lookups: []u16,
};

pub const SingleSubstitution = struct {
    pub const max_dense_glyphs = 4096;

    enabled: bool = false,
    subst_format: u16 = 0,
    coverage_offset: usize = 0,
    delta: i16 = 0,
    glyph_count: u16 = 0,
    substitutes_pos: usize = 0,
    single_mapping: bool = false,
    single_from: GlyphId = 0,
    single_to: GlyphId = 0,
    /// One-based replacement glyphs indexed by input glyph; zero is a miss.
    /// The u32 representation can encode the full u16 replacement domain.
    dense_mapping: []const u32 = &.{},
};

pub const SingleEntry = struct {
    from: GlyphId,
    to: GlyphId,
};

pub const MultipleSubstitution = struct {
    entries: []const MultipleEntry = &.{},
};

pub const MultipleEntry = struct {
    glyph: GlyphId,
    sequence_offset: usize,
    glyph_count: u16,
    single_to: GlyphId = 0,
};

pub const LigatureSubstitution = struct {
    sets: []const LigatureSet = &.{},
    set_slots: []const u16 = &.{},
    definitions: []const LigatureDefinition = &.{},
    components: []const GlyphId = &.{},
    first_component_digest: GlyphDigest = .{},
    /// Compact range metadata uses tail padding instead of widening every
    /// lookup sidecar with another slice.
    required_second_start: u32 = 0,
    required_second_len: u16 = 0,
    prefilter_second: bool = false,
};

comptime {
    const LayoutWithoutRequiredSecondRange = struct {
        sets: []const LigatureSet = &.{},
        set_slots: []const u16 = &.{},
        definitions: []const LigatureDefinition = &.{},
        components: []const GlyphId = &.{},
        first_component_digest: GlyphDigest = .{},
        prefilter_second: bool = false,
    };
    std.debug.assert(@sizeOf(LigatureSubstitution) ==
        @sizeOf(LayoutWithoutRequiredSecondRange));
}

pub const LigatureSet = struct {
    glyph: GlyphId,
    definition_start: usize,
    definition_len: usize,
};

pub const LigatureDefinition = struct {
    ligature: GlyphId,
    component_start: usize,
    component_count: u16,
};

pub const ContextClassSubtable = struct {
    subtable_offset: usize = 0,
    first_index_start: usize = 0,
    class_def: usize = 0,
    class_values: []const u16 = &.{},
    /// Rules are grouped by first class, then ordered by sequence hash. This
    /// lets large class sets probe exact candidate ranges without a linear
    /// scan while the rule's authored `order` still resolves overlaps.
    rules_hash_sorted: bool = false,
    rules: []const class_context.Rule = &.{},
    classes: []const u16 = &.{},
    groups: []const class_context.RuleGroup = &.{},
};

pub const ContextCoverageSubtable = struct {
    glyph_count: u16 = 0,
    coverage_start: usize = 0,
    subst_count: u16 = 0,
    records_pos: usize = 0,
};

pub const ChainingCoverageSubtable = struct {
    pub const max_fast_records = 4;

    subtable_offset: usize = 0,
    backtrack_offsets_pos: usize = 0,
    backtrack_count: u16 = 0,
    input_offsets_pos: usize = 0,
    input_count: u16 = 0,
    second_input_digest: GlyphDigest = .{},
    second_input_coverage_offset: usize = 0,
    third_input_digest: GlyphDigest = .{},
    third_input_coverage_offset: usize = 0,
    first_backtrack_digest: GlyphDigest = .{},
    lookahead_offsets_pos: usize = 0,
    lookahead_count: u16 = 0,
    first_lookahead_digest: GlyphDigest = .{},
    records_pos: usize = 0,
    subst_count: u16 = 0,
    fast_record_count: u16 = 0,
    fast_records: [max_fast_records]FastSingleRecord =
        [_]FastSingleRecord{.{}} ** max_fast_records,
};

pub const FastSingleRecord = struct {
    sequence_index: u16 = 0,
    accelerator: SingleSubstitution = .{},
};

pub const ChainingClassSubtable = struct {
    first_index_start: usize = 0,
    backtrack_class_def: usize = 0,
    input_class_def: usize = 0,
    lookahead_class_def: usize = 0,
    backtrack_class_values: []const u16 = &.{},
    input_class_values: []const u16 = &.{},
    lookahead_class_values: []const u16 = &.{},
    rules: []const class_context.Rule = &.{},
    classes: []const u16 = &.{},
    groups: []const class_context.RuleGroup = &.{},
};

pub const ReverseChainingSingleSubtable = struct {
    subtable_offset: usize = 0,
    coverage_offset: usize = 0,
    backtrack_offsets_pos: usize = 0,
    backtrack_count: u16 = 0,
    lookahead_offsets_pos: usize = 0,
    lookahead_count: u16 = 0,
    glyph_count: u16 = 0,
    substitutes_pos: usize = 0,
};

pub const ReverseChainingContextKey = struct {
    target: GlyphId,
    backtrack: GlyphId,
    lookahead_0: GlyphId,
    lookahead_1: GlyphId,

    pub fn lessThan(lhs: ReverseChainingContextKey, rhs: ReverseChainingContextKey) bool {
        if (lhs.target != rhs.target) return lhs.target < rhs.target;
        if (lhs.backtrack != rhs.backtrack) return lhs.backtrack < rhs.backtrack;
        if (lhs.lookahead_0 != rhs.lookahead_0) {
            return lhs.lookahead_0 < rhs.lookahead_0;
        }
        return lhs.lookahead_1 < rhs.lookahead_1;
    }

    pub fn eql(lhs: ReverseChainingContextKey, rhs: ReverseChainingContextKey) bool {
        return lhs.target == rhs.target and
            lhs.backtrack == rhs.backtrack and
            lhs.lookahead_0 == rhs.lookahead_0 and
            lhs.lookahead_1 == rhs.lookahead_1;
    }
};

pub const ReverseChainingContextEntry = struct {
    key: ReverseChainingContextKey,
    subtable_index: u16,
    substitute: GlyphId,
};

pub const ChainingGroup = struct {
    glyph: GlyphId,
    subtable_indices: []const u16,
    second_input_digest: GlyphDigest = .{},
    has_no_second_input: bool = false,
};

pub const ChainingPair = struct {
    glyph: GlyphId,
    subtable_index: u16,
};

pub const ChainingPairGroup = struct {
    first: GlyphId,
    second: GlyphId,
    subtable_indices: []const u16,
};

pub const ChainingPairEntry = struct {
    first: GlyphId,
    second: GlyphId,
    subtable_index: u16,
};
