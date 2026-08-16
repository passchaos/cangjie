//! Atomic cardinality changes for one matched MultipleSubst sequence.

const std = @import("std");
const filtering = @import("../../../runtime/filtering.zig");
const limits = @import("../../../runtime/limits.zig");
const mutation = @import("../../../runtime/mutation.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Change = struct {
    removed_len: usize = 1,
    inserted_len: usize = 1,
};

const Error = table.view.Error ||
    limits.Error ||
    std.mem.Allocator.Error;
const Options = filtering.Options;
const View = table.View;

pub fn apply(
    view: View,
    sequence_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    run: Options,
) Error!Change {
    const glyph_count = try view.readU16(sequence_offset);
    return applyKnown(
        view,
        sequence_offset,
        glyph_count,
        null,
        glyphs,
        glyph_index,
        allocator,
        run,
    );
}

/// Apply an accelerator-decoded sequence while retaining table-backed payloads.
pub fn applyKnown(
    view: View,
    sequence_offset: usize,
    glyph_count: u16,
    single_to: ?GlyphId,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    run: Options,
) Error!Change {
    if (glyph_count == 1) {
        // Read before charging the budget: malformed input must not consume a
        // run-owned resource guard when no mutation can be committed.
        const substitute =
            single_to orelse try view.readU16(sequence_offset + 2);
        try limits.consumeMutation(run, glyphs.items.len, 1, 1);
        glyphs.items[glyph_index] = substitute;
        mutation.markSubstituted(run, glyph_index);
        return .{};
    }

    const replacement = try allocator.alloc(GlyphId, glyph_count);
    defer allocator.free(replacement);
    for (replacement, 0..) |*glyph, replacement_index| {
        glyph.* = try view.readU16(
            sequence_offset + 2 + replacement_index * 2,
        );
    }
    // Reserve every parallel list before consuming the logical operation.
    // This makes an allocator failure observationally atomic for both buffer
    // contents and the caller-owned run budget.
    const prepared = try mutation.prepareReplacement(
        allocator,
        glyphs,
        run,
        glyph_index,
        1,
        replacement.len,
        filtering.sourceForGlyph(run, glyph_index),
    );
    try limits.consumeMutation(
        run,
        glyphs.items.len,
        1,
        replacement.len,
    );
    prepared.commit(glyphs, replacement);
    return .{
        .removed_len = 1,
        .inserted_len = replacement.len,
    };
}
