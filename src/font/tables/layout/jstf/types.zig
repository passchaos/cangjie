//! Owned OpenType JSTF inspection values.

const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const LookupList = struct {
    indices: []u16,
};

pub const MaxLookup = struct {
    lookup_type: u16,
    lookup_flag: u16,
    subtable_count: u16,
    offset: usize,
};

pub const Priority = struct {
    shrinkage_enable_gsub: LookupList,
    shrinkage_disable_gsub: LookupList,
    shrinkage_enable_gpos: LookupList,
    shrinkage_disable_gpos: LookupList,
    shrinkage_max: []MaxLookup,
    extension_enable_gsub: LookupList,
    extension_disable_gsub: LookupList,
    extension_enable_gpos: LookupList,
    extension_disable_gpos: LookupList,
    extension_max: []MaxLookup,
};

pub const Language = struct {
    tag: ?[4]u8,
    priorities: []Priority,
};

pub const Script = struct {
    tag: [4]u8,
    extender_glyphs: []GlyphId,
    default_language: ?Language,
    languages: []Language,
};

pub const Info = struct {
    version: u32,
    scripts: []Script,
};
