//! GSUB lookup-level profiling helpers.
//!
//! Lookup dispatch owns these counters and glyph-window snapshots. Keeping the
//! bookkeeping here prevents the root table runner and concrete substitution
//! executors from each growing their own timing and diff implementation.

const std = @import("std");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const Options = @import("../../runtime/options.zig").Options;
const shape_profile = @import("../../../shape_profile.zig");

pub const Profile = shape_profile.ShapeStageProfile;

pub fn now(profile: ?*Profile, io: ?std.Io) i128 {
    return if (profile != null)
        std.Io.Clock.now(.awake, io.?).nanoseconds
    else
        0;
}

pub fn elapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}

pub fn recordKind(profile: ?*Profile, lookup_type: u16) void {
    const active = profile orelse return;
    active.gsub_lookup_count += 1;
    switch (lookup_type) {
        1 => active.gsub_single_lookup_count += 1,
        2 => active.gsub_multiple_lookup_count += 1,
        3 => active.gsub_alternate_lookup_count += 1,
        4 => active.gsub_ligature_lookup_count += 1,
        5, 6 => active.gsub_context_lookup_count += 1,
        7 => active.gsub_extension_lookup_count += 1,
        else => {},
    }
}

/// Record the compact fast-path profile which does not retain a glyph copy.
pub fn recordAccelerated(
    run: Options,
    lookup_index: ?u16,
    lookup_type: u16,
    lookup_start: i128,
    glyph_count_before: usize,
    glyph_count_after: usize,
) void {
    const active = run.shape_profile orelse return;
    recordKind(active, lookup_type);
    active.recordGsubLookupTime(
        lookup_index,
        elapsed(lookup_start, run.profile_io),
    );
    active.recordGsubLookupGlyphs(
        lookup_index,
        glyph_count_before,
        glyph_count_after,
        0,
        0,
        glyph_count_before,
        0,
        &.{},
        &.{},
    );
}

pub fn glyphRunHash(glyphs: []const GlyphId) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (glyphs) |glyph| {
        hash ^= glyph;
        hash *%= 0x100000001b3;
    }
    return hash;
}

pub fn firstDifferentGlyphIndex(
    before: []const GlyphId,
    after: []const GlyphId,
) usize {
    const len = @min(before.len, after.len);
    for (0..len) |index| {
        if (before[index] != after[index]) return index;
    }
    return len;
}
