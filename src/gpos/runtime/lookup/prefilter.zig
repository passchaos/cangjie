//! Per-run coverage prefilters shared by accelerated GPOS lookups.

const accelerator = @import("../../accelerator/root.zig");
const GlyphDigest = @import("../../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const matching = @import("../matching.zig");
const options = @import("../options.zig");

pub const Group = accelerator.glyph_groups.Group;
pub const Options = options.Options;

pub const DigestCache = struct {
    digest: GlyphDigest = undefined,
    valid: bool = false,

    pub fn init() DigestCache {
        // The digest becomes readable only after `get` or `primeUnfiltered`
        // assigns it and flips `valid`; avoid clearing the 64-bit payload.
        return .{};
    }

    pub fn get(
        self: *DigestCache,
        glyphs: []const GlyphId,
        lookup_flag: u16,
        run: Options,
    ) GlyphDigest {
        _ = lookup_flag;
        _ = run;
        if (!self.valid) {
            self.digest = rawDigest(glyphs);
            self.valid = true;
        }
        return self.digest;
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
        if (self.valid) return;
        self.digest = rawDigest(glyphs);
        self.valid = true;
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
    direct: []const u16,
    glyphs: []const GlyphId,
    lookup_flag: u16,
    run: Options,
) bool {
    if (lookup_flag == 0) {
        // The dominant GPOS case has no lookup filtering. Select this loop
        // once instead of proving the same flag state for every glyph in each
        // exact whole-run preflight.
        for (glyphs) |glyph| {
            if (accelerator.glyph_groups.findDirect(
                groups,
                slots,
                direct,
                glyph,
            ) != null) return true;
        }
        return false;
    }
    for (glyphs) |glyph| {
        if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) continue;
        if (accelerator.glyph_groups.findDirect(
            groups,
            slots,
            direct,
            glyph,
        ) != null) {
            return true;
        }
    }
    return false;
}
