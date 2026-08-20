//! Decoded GPOS lookup sidecars shared across shaping runs.
//!
//! These are concrete borrowed/owned value types. Builders fill the decoded
//! fields, while `deinitLookups` owns the complete nested allocation graph.

const std = @import("std");
const GlyphDigest = @import("../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../glyph.zig").GlyphId;
const class_context = @import("../../opentype/class_context.zig");
const positioning = @import("../positioning/root.zig");
const coverage = @import("coverage.zig");
const glyph_groups = @import("glyph_groups.zig");

pub const Lookup = struct {
    /// Runtime use checks `lookup_offset`, so stale or foreign sidecars fall
    /// back to normal bounds-checked lookup parsing.
    lookup_offset: usize = 0,
    lookup_type: u16 = 0,
    lookup_flag: u16 = 0,
    subtable_count: u16 = 0,
    mark_filtering_set: ?u16 = null,
    extension_lookup_type: ?u16 = null,
    coverage_digest: GlyphDigest = .{},
    coverage_groups: []const glyph_groups.Group = &.{},
    coverage_group_slots: []const u16 = &.{},
    /// Exact glyph-id to one-based coverage-group mapping for compact fonts.
    /// This avoids hashing or binary search in per-pair runtime traversal; an
    /// empty slot still means the lookup does not cover that glyph.
    coverage_group_direct: []const u16 = &.{},
    single_pos_subtables: []const SinglePositionSubtable = &.{},
    pair_pos_subtables: []const PairPositionSubtable = &.{},
    pair_pos_records: []const PairPositionRecord = &.{},
    pair_pos_coverage_classes: []const PairClassEntry = &.{},
    pair_pos_class_entries: []const PairClassEntry = &.{},
    pair_pos_class_matrix: []const i16 = &.{},
    pair_pos_extension: bool = false,
    cursive_subtables: []const CursivePositionSubtable = &.{},
    mark_to_base_subtables: []const MarkToBaseSubtable = &.{},
    mark_to_mark_subtables: []const MarkToMarkSubtable = &.{},
    chaining_coverage_only: bool = false,
    chaining_subtables: []const ChainingCoverageSubtable = &.{},
    chaining_groups: []const glyph_groups.Group = &.{},
    chaining_group_slots: []const u16 = &.{},
    chaining_class_subtables: []const ChainingClassSubtable = &.{},
};

pub const PairPositionKind = enum(u8) {
    generic,
    format_1_x_advance,
    format_2_x_advance,
    format_2_dense_x_advance,
};

pub const PairPositionSubtable = struct {
    kind: PairPositionKind = .generic,
    // Format 1 uses these as the global record slice. Dense format 2 has no
    // PairPositionRecord slice, so it reuses the otherwise-idle words for the
    // ClassDef1-coverage and ClassDef2 base glyphs without widening Lookup.
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

pub const PairPositionRecord = struct {
    first: GlyphId,
    second: GlyphId,
    x_advance: i16,
};

pub const PairClassEntry = struct {
    glyph: GlyphId,
    class: u16,
};

pub const SinglePositionSubtable = struct {
    subtable_offset: usize = 0,
    pos_format: u16 = 0,
    coverage_offset: usize = 0,
    value_format: u16 = 0,
    value_count: u16 = 0,
    value_size: usize = 0,
    values_pos: usize = 0,
    value: positioning.Adjustment = .{ .index = 0 },
};

pub const CursivePositionSubtable = struct {
    subtable_offset: usize,
    coverage_offset: usize,
    entry_exit_count: u16,
    coverage: ?coverage.Owned = null,
};

pub const MarkToBaseSubtable = struct {
    mark_coverage_offset: usize = 0,
    base_coverage_offset: usize = 0,
    class_count: u16 = 0,
    mark_array_offset: usize = 0,
    base_array_offset: usize = 0,
    mark_coverage: ?coverage.Owned = null,
    base_coverage: ?coverage.Owned = null,
};

pub const MarkToMarkSubtable = struct {
    subtable_offset: usize = 0,
    mark_1_coverage_offset: usize = 0,
    mark_2_coverage_offset: usize = 0,
    class_count: u16 = 0,
    mark_1_array_offset: usize = 0,
    mark_2_array_offset: usize = 0,
    mark_1_coverage: ?coverage.Owned = null,
    mark_2_coverage: ?coverage.Owned = null,
};

pub const ChainingCoverageSubtable = struct {
    pub const max_fast_records = 4;

    subtable_offset: usize = 0,
    backtrack_offsets_pos: usize = 0,
    backtrack_count: u16 = 0,
    backtrack_coverages: []const coverage.Owned = &.{},
    input_offsets_pos: usize = 0,
    input_count: u16 = 0,
    input_coverages: []const coverage.Owned = &.{},
    second_input_digest: GlyphDigest = .{},
    lookahead_offsets_pos: usize = 0,
    lookahead_count: u16 = 0,
    lookahead_coverages: []const coverage.Owned = &.{},
    records_pos: usize = 0,
    pos_count: u16 = 0,
    fast_record_count: u16 = 0,
    fast_records: [max_fast_records]FastSinglePositionRecord =
        [_]FastSinglePositionRecord{.{}} ** max_fast_records,
};

pub const FastSinglePositionRecord = struct {
    sequence_index: u16 = 0,
    lookup_index: u16 = 0,
    lookup_flag: u16 = 0,
};

pub const ChainingClassSubtable = struct {
    subtable_offset: usize = 0,
    coverage_offset: usize = 0,
    input_class_def: usize = 0,
    lookahead_class_def: usize = 0,
    uniform_input_count: u16 = 0,
    rules: []const class_context.Rule = &.{},
    classes: []const u16 = &.{},
    groups: []const class_context.RuleGroup = &.{},
};

/// Release both one lookup's nested allocations and the outer lookup slice.
pub fn deinitLookups(
    lookups: []Lookup,
    allocator: std.mem.Allocator,
) void {
    deinitLookupContents(lookups, allocator);
    allocator.free(lookups);
}

/// Release only nested allocations; useful for partially-built arrays.
pub fn deinitLookupContents(
    lookups: []Lookup,
    allocator: std.mem.Allocator,
) void {
    for (lookups) |lookup| {
        glyph_groups.deinitGroups(lookup.coverage_groups, allocator);
        allocator.free(lookup.coverage_group_slots);
        allocator.free(lookup.coverage_group_direct);
        allocator.free(lookup.single_pos_subtables);
        allocator.free(lookup.pair_pos_subtables);
        allocator.free(lookup.pair_pos_records);
        allocator.free(lookup.pair_pos_coverage_classes);
        allocator.free(lookup.pair_pos_class_entries);
        allocator.free(lookup.pair_pos_class_matrix);
        deinitCursiveSubtables(lookup.cursive_subtables, allocator);
        deinitMarkToBaseSubtables(lookup.mark_to_base_subtables, allocator);
        deinitMarkToMarkSubtables(lookup.mark_to_mark_subtables, allocator);
        glyph_groups.deinitGroups(lookup.chaining_groups, allocator);
        allocator.free(lookup.chaining_group_slots);
        deinitChainingCoverageSubtables(lookup.chaining_subtables, allocator);
        deinitChainingClassSubtables(lookup.chaining_class_subtables, allocator);
    }
}

pub fn deinitCursiveSubtables(
    subtables: []const CursivePositionSubtable,
    allocator: std.mem.Allocator,
) void {
    for (subtables) |subtable| {
        if (subtable.coverage) |owned| owned.deinit(allocator);
    }
    allocator.free(subtables);
}

pub fn deinitMarkToBaseSubtables(
    subtables: []const MarkToBaseSubtable,
    allocator: std.mem.Allocator,
) void {
    for (subtables) |subtable| {
        if (subtable.mark_coverage) |owned| owned.deinit(allocator);
        if (subtable.base_coverage) |owned| owned.deinit(allocator);
    }
    allocator.free(subtables);
}

pub fn deinitMarkToMarkSubtables(
    subtables: []const MarkToMarkSubtable,
    allocator: std.mem.Allocator,
) void {
    for (subtables) |subtable| {
        if (subtable.mark_1_coverage) |owned| owned.deinit(allocator);
        if (subtable.mark_2_coverage) |owned| owned.deinit(allocator);
    }
    allocator.free(subtables);
}

pub fn deinitChainingCoverageSubtables(
    subtables: []const ChainingCoverageSubtable,
    allocator: std.mem.Allocator,
) void {
    for (subtables) |subtable| {
        deinitChainingCoverageSubtableContents(subtable, allocator);
    }
    allocator.free(subtables);
}

pub fn deinitChainingCoverageSubtableContents(
    subtable: ChainingCoverageSubtable,
    allocator: std.mem.Allocator,
) void {
    coverage.Owned.deinitSequence(subtable.backtrack_coverages, allocator);
    coverage.Owned.deinitSequence(subtable.input_coverages, allocator);
    coverage.Owned.deinitSequence(subtable.lookahead_coverages, allocator);
}

pub fn deinitChainingClassSubtables(
    subtables: []const ChainingClassSubtable,
    allocator: std.mem.Allocator,
) void {
    deinitChainingClassSubtableContents(subtables, allocator);
    allocator.free(subtables);
}

pub fn deinitChainingClassSubtableContents(
    subtables: []const ChainingClassSubtable,
    allocator: std.mem.Allocator,
) void {
    for (subtables) |subtable| {
        allocator.free(subtable.rules);
        allocator.free(subtable.classes);
        allocator.free(subtable.groups);
    }
}
