//! Atomic mutation of GSUB run metadata sidecars.
//!
//! The glyph stream itself is edited by lookup executors. This module keeps
//! every optional parallel sidecar aligned with that edit. Capacity for all
//! participating lists is reserved before any list changes length, so an
//! allocation failure cannot leave source, cluster, substitution, or
//! provenance metadata at different cardinalities.

const std = @import("std");
const GlyphId = @import("../../glyph.zig").GlyphId;
const options = @import("options.zig");
const sidecars = @import("mutation/sidecars.zig");

pub const Options = options.Options;

pub const PreparedReplacement = struct {
    run: Options,
    glyph_index: usize,
    removed_len: usize,
    inserted_len: usize,
    sidecar_state: sidecars.Prepared,

    /// Commit the glyph edit and every parallel sidecar without allocation.
    ///
    /// `prepareReplacement` has already proved all capacities, so this is the
    /// single mutation point and cannot expose a partially updated run on OOM.
    pub fn commit(
        prepared: PreparedReplacement,
        glyphs: *std.ArrayList(GlyphId),
        replacement: []const GlyphId,
    ) void {
        std.debug.assert(replacement.len == prepared.inserted_len);
        const removed = boundedRemoval(
            glyphs.items.len,
            prepared.glyph_index,
            prepared.removed_len,
        );
        glyphs.replaceRangeAssumeCapacity(
            prepared.glyph_index,
            removed,
            replacement,
        );
        prepared.sidecar_state.commit();
        note(prepared.run);
    }
};

pub fn markSubstituted(run: Options, glyph_index: usize) void {
    note(run);
    if (run.glyph_substituted) |substituted| {
        if (glyph_index < substituted.items.len) {
            substituted.items[glyph_index] = true;
        }
    }
    if (run.glyph_stage_substituted) |substituted| {
        if (glyph_index < substituted.items.len) {
            substituted.items[glyph_index] = true;
        }
    }
}

pub fn note(run: Options) void {
    const generation = run.glyph_mutation_generation orelse return;
    generation.* +%= 1;
}

/// Reserve the glyph stream and all participating metadata sidecars before a
/// cardinality-changing edit. The returned value captures metadata from the
/// pre-edit glyph and can be committed only with the matching replacement len.
pub fn prepareReplacement(
    allocator: std.mem.Allocator,
    glyphs: *std.ArrayList(GlyphId),
    run: Options,
    glyph_index: usize,
    removed_len: usize,
    inserted_len: usize,
    source: usize,
) std.mem.Allocator.Error!PreparedReplacement {
    try ensureReplacementCapacity(
        GlyphId,
        allocator,
        glyphs,
        glyph_index,
        removed_len,
        inserted_len,
    );
    return .{
        .run = run,
        .glyph_index = glyph_index,
        .removed_len = removed_len,
        .inserted_len = inserted_len,
        .sidecar_state = try sidecars.prepare(
            allocator,
            run,
            glyph_index,
            removed_len,
            inserted_len,
            source,
        ),
    };
}

/// Remove metadata after a glyph deletion that cannot allocate. Ligature
/// executors use this after their one substitution epoch has already been
/// recorded for the retained ligature glyph.
pub fn removeMetadata(
    run: Options,
    glyph_index: usize,
    removed_len: usize,
) void {
    sidecars.remove(run, glyph_index, removed_len);
}

fn ensureReplacementCapacity(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: *std.ArrayList(T),
    index: usize,
    removed_len: usize,
    inserted_len: usize,
) std.mem.Allocator.Error!void {
    if (index > items.items.len) return;
    const removed = boundedRemoval(items.items.len, index, removed_len);
    const target = std.math.add(
        usize,
        items.items.len - removed,
        inserted_len,
    ) catch return error.OutOfMemory;
    try items.ensureTotalCapacity(allocator, target);
}

fn boundedRemoval(length: usize, index: usize, requested: usize) usize {
    if (index > length) return 0;
    return @min(requested, length - index);
}
