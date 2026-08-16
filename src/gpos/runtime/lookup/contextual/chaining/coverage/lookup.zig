//! Lookup-level dispatch for ChainContextPos format-3 coverage subtables.

const std = @import("std");
const accelerator_core = @import("../../../../../accelerator/root.zig");
const contextual_matching = @import("../../matching.zig");
const execute = @import("execute.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;
const model = @import("../../model.zig");
const run_matching = @import("../../../../matching.zig");

const Adjustment = model.Adjustment;
const ApplyNestedFn = model.ApplyNestedFn;
const ApplyRecordsFn = model.ApplyRecordsFn;
const Error = model.Error;
const LookupAccelerator = accelerator_core.model.Lookup;
const Options = model.Options;
const View = model.View;

const min_run_glyphs_for_digest = 16;

pub fn usesGlyphDigest(glyph_count: usize) bool {
    return glyph_count >= min_run_glyphs_for_digest;
}

/// Execute an accelerated format-3-only ChainContextPos lookup.
pub fn collect(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    accelerator: *const LookupAccelerator,
    comptime applyRecords: ApplyRecordsFn,
    comptime applyNested: ApplyNestedFn,
) Error!void {
    if (usesGlyphDigest(glyphs.len)) {
        return collectImpl(
            true,
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            accelerator,
            applyRecords,
            applyNested,
        );
    }
    return collectImpl(
        false,
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
        accelerator,
        applyRecords,
        applyNested,
    );
}

pub fn collectNestedAt(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    accelerator: *const LookupAccelerator,
    comptime applyRecords: ApplyRecordsFn,
    comptime applyNested: ApplyNestedFn,
) Error!bool {
    if (position >= glyphs.len) return false;
    if (run_matching.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs[position],
    )) return false;
    if (usesGlyphDigest(glyphs.len) and
        !accelerator.coverage_digest.mayHave(glyphs[position]))
    {
        return false;
    }
    const candidates = accelerator_core.glyph_groups.find(
        accelerator.chaining_groups,
        accelerator.chaining_group_slots,
        glyphs[position],
    ) orelse return false;
    const second_position = contextual_matching.next(
        glyphs,
        position + 1,
        lookup_flag,
        run,
    );
    for (candidates) |subtable_index| {
        if (subtable_index >= subtable_count) return error.BadGpos;
        const subtable = try resolvedSubtable(
            view,
            lookup_offset,
            subtable_index,
            accelerator,
        ) orelse continue;
        if (subtable.input_count > 1) {
            const second = second_position orelse continue;
            if (!subtable.second_input_digest.mayHave(glyphs[second])) {
                continue;
            }
        }
        if ((try execute.collectAt(
            true,
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
            applyNested,
        )).matched) return true;
    }
    return false;
}

fn collectImpl(
    comptime use_glyph_digest: bool,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    accelerator: *const LookupAccelerator,
    comptime applyRecords: ApplyRecordsFn,
    comptime applyNested: ApplyNestedFn,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.len) {
        var next_position = position + 1;
        defer position = next_position;
        if (run_matching.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[position],
        )) continue;
        if (use_glyph_digest and
            !accelerator.coverage_digest.mayHave(glyphs[position]))
        {
            continue;
        }
        const candidates = accelerator_core.glyph_groups.find(
            accelerator.chaining_groups,
            accelerator.chaining_group_slots,
            glyphs[position],
        ) orelse continue;
        const second_position = contextual_matching.next(
            glyphs,
            position + 1,
            lookup_flag,
            run,
        );
        for (candidates) |subtable_index| {
            const subtable = try resolvedSubtable(
                view,
                lookup_offset,
                subtable_index,
                accelerator,
            ) orelse continue;
            if (subtable.input_count > 1) {
                const second = second_position orelse continue;
                if (!subtable.second_input_digest.mayHave(glyphs[second])) {
                    continue;
                }
            }
            const result = try execute.collectAt(
                true,
                view,
                subtable,
                glyphs,
                position,
                adjustments,
                allocator,
                lookup_flag,
                run,
                applyRecords,
                applyNested,
            );
            if (result.matched) {
                next_position = @max(next_position, result.next_pos);
                break;
            }
        }
        _ = subtable_count;
    }
}

fn resolvedSubtable(
    view: View,
    lookup_offset: usize,
    subtable_index: usize,
    accelerator: *const LookupAccelerator,
) Error!?execute.Subtable {
    if (subtable_index < accelerator.chaining_subtables.len and
        accelerator.chaining_subtables[subtable_index].input_count != 0)
    {
        return accelerator.chaining_subtables[subtable_index];
    }
    const subtable_offset = lookup_offset + try view.readU16(
        lookup_offset + 6 + subtable_index * 2,
    );
    return execute.parse(view, subtable_offset);
}
