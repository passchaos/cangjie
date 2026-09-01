const std = @import("std");
const accelerator_core = @import("gpos/accelerator/root.zig");
const GlyphId = @import("glyph.zig").GlyphId;
pub const feature = @import("gpos/feature/root.zig");
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

/// One entry in the allocator-owned sidecar slice returned by
/// `buildLookupAccelerators`. The entries and their nested storage are not
/// standalone values: keep the complete original slice alive, at the same
/// address, and unchanged whenever it is supplied through
/// `LookupOptions.lookup_accelerators`. Copying a slice descriptor is fine, but
/// copying, moving, resizing, or mutating its elements breaks that contract.
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

/// Build an allocator-owned lookup plan for an internal immutable-font cache.
///
/// `options` must name the exact validated sidecar allocation returned by
/// `buildLookupAccelerators`; the plan is bound to that allocation and must be
/// destroyed before it. Entries retain stable LookupList indexes and offsets
/// only, so run-local variation values and metadata are resolved at execution.
pub fn buildLookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GposError || std.mem.Allocator.Error)!feature.LookupPlan {
    return feature.plan.buildLookupPlan(
        data,
        offset,
        length,
        allocator,
        options,
    );
}

/// Attempt exact proof-bound plan execution for the same cached selection.
/// `false` is an atomic decline and leaves the caller free to use ordinary
/// defensive table traversal. Higher-level cache owners additionally bind the
/// plan to a concrete `Font`; this low-level boundary proves exact table bytes,
/// table range, accelerator allocation, and every lookup tuple.
pub fn collectAdjustmentsWithPlanAfterProof(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: feature.LookupPlan,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    options: LookupOptions,
) (GposError || std.mem.Allocator.Error)!bool {
    return feature.plan.applyAfterProof(
        data,
        offset,
        length,
        plan,
        glyphs,
        adjustments,
        allocator,
        options,
    );
}

/// Build reusable decoded sidecars for one validated GPOS table range.
///
/// The caller owns the returned slice and all of its nested allocations and
/// must release them exactly once with `deinitLookupAccelerators` and the same
/// allocator. The sidecars borrow `data`: both the backing byte allocation and
/// the complete returned sidecar allocation must remain alive and immutable
/// for every shaping or lookup call that uses them.
///
/// Runtime matching records pointer, length, table range, and sidecar-allocation
/// identity. It is not a content hash and does not establish memory liveness:
/// mutation at the same addresses still has the same identity, while using a
/// sidecar or its backing bytes after free is outside the API contract.
pub fn buildLookupAccelerators(data: []const u8, offset: usize, length: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)![]LookupAccelerator {
    return accelerator_core.build.lookup.all(
        data,
        offset,
        length,
        allocator,
    );
}

/// Release the complete slice returned by `buildLookupAccelerators`. No copy,
/// subslice, or nested sidecar storage may be used after this call. This does
/// not release the separately caller-owned font bytes.
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
