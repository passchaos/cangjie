const std = @import("std");
const accelerator_core = @import("gpos/accelerator/root.zig");
const GlyphId = @import("glyph.zig").GlyphId;
const positioning = @import("gpos/positioning/root.zig");
pub const runtime = @import("gpos/runtime/root.zig");
const runtime_run = @import("gpos/runtime/run.zig");
const validation = @import("gpos/validation/root.zig");

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

pub const VariationStore = positioning.VariationStore;

pub const LookupAccelerator = accelerator_core.model.Lookup;
pub const LookupOptions = runtime.Options;

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
    return validation.font.glyphBounds(
        data,
        offset,
        length,
        glyph_count,
    );
}

/// Collect positioning adjustments for a post-GSUB glyph stream.
pub fn collectAdjustments(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    return try collectAdjustmentsWithOptions(data, offset, length, glyphs, adjustments, allocator, .{});
}

pub fn collectAdjustmentsWithOptions(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    return runtime_run.collect(
        data,
        offset,
        length,
        glyphs,
        adjustments,
        allocator,
        options,
    );
}

/// Collect from an internal shaping run whose owned pipeline maintained all
/// glyph/source sidecars and proved final glyph ids at the GSUB-to-GPOS
/// boundary. Public and detached callers retain the defensive metadata
/// validation in `collectAdjustmentsWithOptions`.
pub fn collectAdjustmentsWithOptionsAfterMetadataProof(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GposError || std.mem.Allocator.Error)!void {
    return runtime_run.collectAfterMetadataProof(
        data,
        offset,
        length,
        glyphs,
        adjustments,
        allocator,
        options,
    );
}

/// Execute GPOS Lookup tables embedded directly in an OpenType JSTF table.
///
/// Offsets are relative to the supplied JSTF table range and were structurally
/// validated when the face was parsed. A detached lookup has no LookupList
/// index or accelerator identity, but otherwise uses the same filtering,
/// attachment, variation, and output accumulation semantics as ordinary GPOS.
pub fn collectDetachedLookups(
    data: []const u8,
    offset: usize,
    length: usize,
    lookup_offsets: []const usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GposError || std.mem.Allocator.Error)!void {
    if (offset > data.len or length > data.len - offset) {
        return error.BadGpos;
    }
    try runtime.matching.validate(options, glyphs.len);
    const view = @import("gpos/table/root.zig").View{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = true,
    };
    for (lookup_offsets) |lookup_offset| {
        try @import("gpos/runtime/lookup/dispatcher/root.zig").collect(
            view,
            lookup_offset,
            glyphs,
            adjustments,
            allocator,
            options,
        );
    }
}

pub fn selectedLookupIndicesForOptions(data: []const u8, offset: usize, length: usize, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)![]u16 {
    return runtime_run.lookupIndicesForOptions(
        data,
        offset,
        length,
        allocator,
        options,
    );
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

test {
    _ = @import("gpos/tests/accelerator/root.zig");
    _ = @import("gpos/tests/feature/root.zig");
    _ = @import("gpos/tests/positioning/root.zig");
    _ = @import("gpos/tests/runtime/root.zig");
    _ = @import("gpos/tests/table/root.zig");
    _ = @import("gpos/tests/validation/root.zig");
}
