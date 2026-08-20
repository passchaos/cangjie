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

/// Detailed defensive-path trace retaining the pre-lookup glyph window.
///
/// Validated accelerated execution uses `recordAccelerated` instead because
/// copying the complete run would defeat the purpose of its fast path.
pub const Detailed = struct {
    active: ?*Profile,
    io: ?std.Io,
    lookup_index: ?u16,
    started: i128,
    glyph_count_before: usize,
    hash_before: u64,
    glyphs_before: []const GlyphId,

    pub fn begin(
        allocator: std.mem.Allocator,
        run: Options,
        lookup_index: ?u16,
        glyphs: []const GlyphId,
    ) std.mem.Allocator.Error!Detailed {
        const active = run.shape_profile;
        return .{
            .active = active,
            .io = run.profile_io,
            .lookup_index = lookup_index,
            .started = now(active, run.profile_io),
            .glyph_count_before = if (active != null) glyphs.len else 0,
            .hash_before = if (active != null) glyphRunHash(glyphs) else 0,
            .glyphs_before = if (active != null)
                try allocator.dupe(GlyphId, glyphs)
            else
                &.{},
        };
    }

    pub fn finish(
        self: Detailed,
        allocator: std.mem.Allocator,
        glyphs_after: []const GlyphId,
    ) void {
        const active = self.active orelse return;
        defer allocator.free(self.glyphs_before);

        const first_diff = firstDifferentGlyphIndex(
            self.glyphs_before,
            glyphs_after,
        );
        const window_start = first_diff -| 2;
        const before_window = self.glyphs_before[window_start..@min(
            self.glyphs_before.len,
            window_start + Profile.lookup_window_capacity,
        )];
        const after_window = glyphs_after[window_start..@min(
            glyphs_after.len,
            window_start + Profile.lookup_window_capacity,
        )];
        active.recordGsubLookupTime(
            self.lookup_index,
            elapsed(self.started, self.io),
        );
        active.recordGsubLookupGlyphs(
            self.lookup_index,
            self.glyph_count_before,
            glyphs_after.len,
            self.hash_before,
            glyphRunHash(glyphs_after),
            first_diff,
            window_start,
            before_window,
            after_window,
        );
    }
};

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
