//! Per-run coverage prefilters shared by accelerated GPOS lookups.

const accelerator = @import("../../accelerator/root.zig");
const GlyphDigest = @import("../../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const matching = @import("../matching.zig");
const options = @import("../options.zig");

pub const Group = accelerator.glyph_groups.Group;
pub const Options = options.Options;

const max_digest_cache_entries = 16;

pub const DigestCache = struct {
    const Entry = struct {
        lookup_flag: u16,
        active_mark_filtering_set: ?u16,
        digest: GlyphDigest,
    };

    entries: [max_digest_cache_entries]Entry = undefined,
    len: usize = 0,

    pub fn init() DigestCache {
        // Entries become readable only after `get` fully assigns them and
        // increments `len`; avoid clearing inactive storage for short runs.
        var cache: DigestCache = undefined;
        cache.len = 0;
        return cache;
    }

    pub fn get(
        self: *DigestCache,
        glyphs: []const GlyphId,
        lookup_flag: u16,
        run: Options,
    ) GlyphDigest {
        const active_mark_filtering_set = run.active_mark_filtering_set;
        for (self.entries[0..self.len]) |entry| {
            if (entry.lookup_flag == lookup_flag and
                entry.active_mark_filtering_set ==
                    active_mark_filtering_set)
            {
                return entry.digest;
            }
        }

        const digest = runDigest(glyphs, lookup_flag, run);
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

    /// Prime the common unfiltered digest once per run.
    ///
    /// Most GPOS lookups use LookupFlag zero. Building this entry up front
    /// turns their repeated linear cache search into an immediate slot-zero
    /// hit while preserving lazy construction for rare filtered variants.
    pub fn primeUnfiltered(
        self: *DigestCache,
        glyphs: []const GlyphId,
    ) void {
        if (self.len != 0) return;
        self.entries[0] = .{
            .lookup_flag = 0,
            .active_mark_filtering_set = null,
            .digest = rawDigest(glyphs),
        };
        self.len = 1;
    }
};

fn rawDigest(glyphs: []const GlyphId) GlyphDigest {
    var digest = GlyphDigest.empty();
    for (glyphs) |glyph| digest.add(glyph);
    return digest;
}

pub fn runDigest(
    glyphs: []const GlyphId,
    lookup_flag: u16,
    run: Options,
) GlyphDigest {
    if (lookup_flag == 0) return rawDigest(glyphs);
    var digest = GlyphDigest.empty();
    for (glyphs) |glyph| {
        if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) continue;
        digest.add(glyph);
    }
    return digest;
}

pub fn groupsMayMatchRun(
    groups: []const Group,
    slots: []const u16,
    glyphs: []const GlyphId,
    lookup_flag: u16,
    run: Options,
) bool {
    for (glyphs) |glyph| {
        if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) continue;
        if (accelerator.glyph_groups.find(groups, slots, glyph) != null) {
            return true;
        }
    }
    return false;
}
