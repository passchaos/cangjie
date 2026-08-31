//! Accelerator-backed execution for a bounded ChainContextSubst format 1.
//!
//! The sidecar admits exactly two logical input glyphs, no backtrack, at most
//! one lookahead glyph, and one SequenceLookupRecord targeting input zero.
//! Keeping the executor equally narrow makes every omitted table field an
//! invariant rather than silently changing the generic format-1 semantics.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const model = @import("../../model.zig");
const safety = @import("../../safety.zig");
const traversal = @import("../../../support/context_traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Lookup = accelerator.Lookup;
const Rule = accelerator.model.ChainingGlyphRule;
const Subtable = accelerator.model.ChainingGlyphSubtable;
const View = table.View;

/// A format-1 sidecar is executable only when it represents every authored
/// subtable. Treating a partial slice as a capability would suppress generic
/// fallback and could change which later subtable wins at a position.
pub fn supportsLookup(sidecar: *const Lookup) bool {
    return sidecar.chaining_glyph_subtables.len != 0 and
        sidecar.chaining_glyph_subtables.len ==
            @as(usize, sidecar.subtable_count);
}

/// Scan one complete lookup position-major, preserving authored subtable
/// order at each cursor exactly as the generic chaining dispatcher does.
pub fn lookup(
    comptime Executor: type,
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    sidecar: *const Lookup,
) Error!void {
    std.debug.assert(supportsLookup(sidecar));

    var position: usize = 0;
    while (position < glyphs.items.len) {
        var next_position = position + 1;
        defer position = next_position;

        for (sidecar.chaining_glyph_subtables) |subtable| {
            const result = try at(
                Executor,
                view,
                subtable,
                glyphs,
                position,
                allocator,
                lookup_flag,
                run,
            );
            if (!result.matched) continue;
            next_position = @max(next_position, result.next_pos);
            break;
        }
    }
}

/// Apply one decoded subtable at a fixed physical lookup cursor.
pub fn at(
    comptime Executor: type,
    view: View,
    subtable: Subtable,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (position >= glyphs.items.len) return .{};
    const rule = subtable.find(glyphs.items[position]) orelse return .{};
    if (!filtering.lookupCursorAllowsGlyph(run, position) or
        filtering.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs.items[position],
        ))
    {
        return .{};
    }
    return matchAndApply(
        Executor,
        view,
        rule,
        glyphs,
        position,
        allocator,
        lookup_flag,
        run,
    );
}

fn matchAndApply(
    comptime Executor: type,
    view: View,
    rule: *const Rule,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    // The parent Coverage selected the lookup cursor, but OpenType's input
    // iterator can still treat that glyph as transparent (CGJ is the notable
    // case). Match the generic format-1 path by resolving logical input zero
    // from the cursor before resolving the authored second input.
    const adjacent = lookup_flag == 0 and
        run.run_has_default_ignorables == false;
    const first_input = if (adjacent)
        position
    else
        traversal.nextIndex(
            glyphs.items,
            position,
            lookup_flag,
            run,
            false,
            position,
        ) orelse return .{};
    const second_input = if (adjacent) adjacent_input: {
        const index = first_input + 1;
        if (index >= glyphs.items.len or
            !filtering.sourceSyllableAllowsGlyph(
                run,
                filtering.sourceSyllableForGlyph(run, position),
                index,
            )) return .{};
        break :adjacent_input index;
    } else traversal.nextIndex(
        glyphs.items,
        first_input + 1,
        lookup_flag,
        run,
        false,
        position,
    ) orelse return .{};
    if (glyphs.items[second_input] != rule.second) return .{};

    const input = [_]usize{ first_input, second_input };
    var lookahead_storage: [1]usize = undefined;
    var lookahead_count: usize = 0;
    if (rule.lookahead) |expected| {
        const lookahead = traversal.nextIndex(
            glyphs.items,
            second_input + 1,
            lookup_flag,
            run,
            true,
            position,
        ) orelse return .{};
        if (glyphs.items[lookahead] != expected) return .{};
        lookahead_storage[0] = lookahead;
        lookahead_count = 1;
    }

    // Safety must observe the pre-mutation physical regions, including gaps
    // occupied by ignored glyphs. The source-boundary implementation closes
    // those gaps when it marks the span between participating glyphs.
    try safety.markRegions(
        allocator,
        run,
        &.{},
        &input,
        lookahead_storage[0..lookahead_count],
    );

    const original_next = second_input + 1;
    const glyph_count_before = glyphs.items.len;
    _ = try Executor.applyNested(
        view,
        glyphs,
        first_input,
        rule.nested_lookup,
        allocator,
        run,
    );
    return .{
        .matched = true,
        .next_pos = model.nextPositionAfterMutation(
            original_next,
            position,
            glyph_count_before,
            glyphs.items.len,
        ),
    };
}
