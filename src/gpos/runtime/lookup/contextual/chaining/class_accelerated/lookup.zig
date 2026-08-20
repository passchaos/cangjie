//! Lookup-level traversal for accelerated class-based chaining payloads.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const execute = @import("execute.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;
const model = @import("../../model.zig");
const run_matching = @import("../../../../matching.zig");

const Adjustment = model.Adjustment;
const ApplyNestedFn = model.ApplyNestedFn;
const Error = model.Error;
const LookupAccelerator = accelerator.model.Lookup;
const Options = model.Options;
const View = model.View;

pub fn collect(
    view: View,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    accelerator_data: *const LookupAccelerator,
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
        var subtable_index: usize = 0;
        while (subtable_index < subtable_count and
            subtable_index <
                accelerator_data.chaining_class_subtables.len) : (subtable_index += 1)
        {
            const subtable =
                accelerator_data.chaining_class_subtables[subtable_index];
            if (subtable.rules.len == 0) continue;
            const result = try execute.collectAt(
                view,
                subtable,
                glyphs,
                position,
                adjustments,
                allocator,
                lookup_flag,
                run,
                applyNested,
            );
            if (result.matched) {
                next_position = @max(next_position, result.next_pos);
                break;
            }
        }
    }
}

pub fn collectNestedAt(
    view: View,
    subtable_count: u16,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    accelerator_data: *const LookupAccelerator,
    comptime applyNested: ApplyNestedFn,
) Error!bool {
    if (position >= glyphs.len or
        run_matching.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[position],
        ))
    {
        return false;
    }
    var subtable_index: usize = 0;
    while (subtable_index < subtable_count and
        subtable_index < accelerator_data.chaining_class_subtables.len) : (subtable_index += 1)
    {
        const subtable =
            accelerator_data.chaining_class_subtables[subtable_index];
        if (subtable.rules.len == 0) continue;
        if ((try execute.collectAt(
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyNested,
        )).matched) return true;
    }
    return false;
}
