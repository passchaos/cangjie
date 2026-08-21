//! ContextSubst format-2 and accelerated class/glyph rule execution.

const std = @import("std");
const filtering = @import("../../../runtime/filtering.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const model = @import("../model.zig");
const records = @import("../records/root.zig");
const safety = @import("../safety.zig");
const traversal = @import("../../support/context_traversal.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const View = table.View;
const max_input_glyphs = 64;

pub fn applyAt(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (position >= glyphs.items.len or
        !filtering.lookupCursorAllowsGlyph(run, position) or
        filtering.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs.items[position],
        ))
    {
        return .{};
    }
    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    if (try table.coverage.index(
        view,
        coverage_offset,
        glyphs.items[position],
    ) == null) return .{};
    const class_def = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 4),
    );
    const class_value = try table.class_def.value(
        view,
        class_def,
        glyphs.items[position],
    );
    const set_count = try view.readU16(subtable_offset + 6);
    if (class_value >= set_count) return .{};
    const set_relative = try view.readU16(
        subtable_offset + 8 + @as(usize, class_value) * 2,
    );
    if (set_relative == 0) return .{};
    return if (try applyRuleSet(
        Executor,
        view,
        subtable_offset + set_relative,
        class_def,
        glyphs,
        position,
        allocator,
        lookup_flag,
        run,
    ))
        .{ .matched = true, .next_pos = position + 1 }
    else
        .{};
}

fn applyRuleSet(
    comptime Executor: type,
    view: View,
    set_offset: usize,
    class_def: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    const rule_count = try view.readU16(set_offset);
    for (0..rule_count) |rule_index| {
        const rule_offset = set_offset +
            try view.readU16(set_offset + 2 + rule_index * 2);
        const input_count = try view.readU16(rule_offset);
        const record_count = try view.readU16(rule_offset + 2);
        if (input_count == 0) continue;
        var input_indices: [max_input_glyphs]usize = undefined;
        if (input_count > input_indices.len) return error.UnsupportedGsub;
        if (!traversal.collectForward(
            glyphs.items,
            position,
            lookup_flag,
            run,
            input_indices[0..input_count],
            false,
            position,
        )) continue;

        var matched = true;
        for (1..input_count) |input_index| {
            const expected = try view.readU16(
                rule_offset + 4 + (input_index - 1) * 2,
            );
            const actual = try table.class_def.value(
                view,
                class_def,
                glyphs.items[input_indices[input_index]],
            );
            if (actual != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;

        const records_offset =
            rule_offset + 4 + (@as(usize, input_count) - 1) * 2;
        try safety.markInput(
            allocator,
            run,
            input_indices[0..input_count],
        );
        try records.apply(
            Executor,
            view,
            glyphs,
            records_offset,
            record_count,
            input_indices[0..input_count],
            allocator,
            run,
        );
        return true;
    }
    return false;
}
