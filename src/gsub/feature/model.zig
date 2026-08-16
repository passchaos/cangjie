//! Value and owner types for staged GSUB feature planning.
//!
//! Lookup selection and application remain in the table executor. Keeping the
//! plan model independent lets shaping caches own concrete plans without
//! depending on parser internals or ABI-style handles.

const std = @import("std");
const unicode = @import("../../unicode.zig");

pub const Application = struct {
    tag: u32,
    source_scoped: bool = false,
    match_source_syllable: bool = false,
    auto_zwnj: bool = true,
    auto_zwj: bool = true,
    value: u32 = 1,
};

pub const source_mask_marker: u32 = 0x80000000;

/// Return the compact source-side feature bit used by script shapers.
///
/// The high marker bit distinguishes a source-feature assignment from a raw
/// OpenType tag. Only features that participate in source-scoped shaping need a
/// bit; unknown and purely global features deliberately return `null`.
pub fn sourceMaskForTag(feature_tag: u32) ?u32 {
    const bit: u5 = if (feature_tag == unicode.tag("rphf"))
        0
    else if (feature_tag == unicode.tag("half"))
        1
    else if (feature_tag == unicode.tag("locl"))
        2
    else if (feature_tag == unicode.tag("ccmp"))
        3
    else if (feature_tag == unicode.tag("nukt"))
        4
    else if (feature_tag == unicode.tag("akhn"))
        5
    else if (feature_tag == unicode.tag("pref"))
        6
    else if (feature_tag == unicode.tag("rkrf"))
        7
    else if (feature_tag == unicode.tag("abvf"))
        8
    else if (feature_tag == unicode.tag("blwf"))
        9
    else if (feature_tag == unicode.tag("pstf"))
        10
    else if (feature_tag == unicode.tag("vatu"))
        11
    else if (feature_tag == unicode.tag("cjct"))
        12
    else if (feature_tag == unicode.tag("isol"))
        13
    else if (feature_tag == unicode.tag("init"))
        14
    else if (feature_tag == unicode.tag("medi"))
        15
    else if (feature_tag == unicode.tag("fina"))
        16
    else if (feature_tag == unicode.tag("blwm"))
        17
    else if (feature_tag == unicode.tag("abvm"))
        18
    else if (feature_tag == unicode.tag("abvs"))
        19
    else if (feature_tag == unicode.tag("blws"))
        20
    else if (feature_tag == unicode.tag("haln"))
        21
    else if (feature_tag == unicode.tag("pres"))
        22
    else if (feature_tag == unicode.tag("psts"))
        23
    else if (feature_tag == unicode.tag("dist"))
        24
    else if (feature_tag == unicode.tag("rlig"))
        25
    else if (feature_tag == unicode.tag("liga"))
        26
    else if (feature_tag == unicode.tag("clig"))
        27
    else if (feature_tag == unicode.tag("calt"))
        28
    else if (feature_tag == unicode.tag("rclt"))
        29
    else if (feature_tag == unicode.tag("cfar"))
        30
    else
        return null;
    return source_mask_marker | (@as(u32, 1) << bit);
}

pub const LookupPlanEntry = struct {
    application: Application,
    lookups: []u16,
    lookup_offsets: []usize,
};

pub const MergedLookup = struct {
    lookup: u16,
    source_mask: u32 = 0,
    auto_zwnj: bool = true,
    auto_zwj: bool = true,
    match_source_syllable: bool = false,
    value: u32 = 1,
    /// `rand` uses the maximum feature value as a sentinel, but the numeric
    /// value alone is not enough once several feature maps are merged by
    /// lookup index. Retain the semantic bit so cached merged plans still
    /// advance the shared HarfBuzz-compatible PRNG at each AlternateSubst.
    random: bool = false,
};

pub const MergedLookupPlan = struct {
    lookups: []MergedLookup,
    lookup_offsets: []usize,

    pub fn deinit(self: *MergedLookupPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.lookup_offsets);
        allocator.free(self.lookups);
        self.* = .{ .lookups = &.{}, .lookup_offsets = &.{} };
    }
};

pub const LookupPlan = struct {
    entries: []LookupPlanEntry,

    pub fn deinit(self: *LookupPlan, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| {
            allocator.free(entry.lookups);
            allocator.free(entry.lookup_offsets);
        }
        allocator.free(self.entries);
        self.* = .{ .entries = &.{} };
    }
};

/// HarfBuzz enables `rand` globally with HB_OT_MAP_MAX_VALUE.
pub const random_value: u32 = 255;
