//! Accelerated ChainContextPos class-subtable execution.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const class_context = @import("../../../../../../opentype/class_context.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;
const matching = @import("../../matching.zig");
const model = @import("../../model.zig");
const output = @import("../../../../output/root.zig");
const table = @import("../../../../../table/root.zig");

const Adjustment = model.Adjustment;
const ApplyNestedFn = model.ApplyNestedFn;
const Error = model.Error;
const Options = model.Options;
const Result = model.Result;
const View = model.View;

pub const Subtable = accelerator.model.ChainingClassSubtable;

const max_region_glyphs = 64;

pub fn collectAt(
    view: View,
    subtable: Subtable,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyNested: ApplyNestedFn,
) Error!Result {
    if (position >= glyphs.len) return .{};
    if (try table.coverage.index(
        view,
        subtable.coverage_offset,
        glyphs[position],
    ) == null) return .{};
    const input_class = try table.class_def.value(
        view,
        subtable.input_class_def,
        glyphs[position],
    );
    const group =
        class_context.groupForClass(subtable.groups, input_class) orelse
        return .{};
    if (group.max_input_count == 0 or
        group.max_input_count > max_region_glyphs or
        group.max_lookahead_count > max_region_glyphs)
    {
        return error.UnsupportedGpos;
    }

    var input_indices_buffer: [max_region_glyphs]usize = undefined;
    const input_indices =
        input_indices_buffer[0..group.max_input_count];
    if (!matching.forward(
        glyphs,
        position,
        lookup_flag,
        run,
        input_indices,
    )) return .{};

    var input_classes: [max_region_glyphs]u16 = undefined;
    for (1..group.max_input_count) |input_index| {
        input_classes[input_index - 1] = try table.class_def.value(
            view,
            subtable.input_class_def,
            glyphs[input_indices[input_index]],
        );
    }

    var lookahead_indices: [max_region_glyphs]usize = undefined;
    var lookahead_classes: [max_region_glyphs]u16 = undefined;
    var lookahead_count: usize = 0;
    var glyph_index = input_indices[group.max_input_count - 1] + 1;
    while (glyph_index < glyphs.len and
        lookahead_count < group.max_lookahead_count) : (glyph_index += 1)
    {
        if (@import("../../../../matching.zig").matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) continue;
        lookahead_indices[lookahead_count] = glyph_index;
        lookahead_classes[lookahead_count] = try table.class_def.value(
            view,
            subtable.lookahead_class_def,
            glyphs[glyph_index],
        );
        lookahead_count += 1;
    }

    const rules = subtable.rules[group.start .. group.start + group.len];
    for (rules) |rule| {
        if (rule.input_count > group.max_input_count or
            rule.lookahead_count > group.max_lookahead_count)
        {
            return error.BadGpos;
        }
        if (rule.input_count == 0 or
            rule.lookahead_count > lookahead_count)
        {
            continue;
        }
        const extra_input_count = @as(usize, rule.input_count) - 1;
        var hash =
            class_context.sequenceHash(input_classes[0..extra_input_count]);
        for (lookahead_classes[0..rule.lookahead_count]) |class| {
            hash = class_context.sequenceHashAppend(hash, class);
        }
        if (rule.hash != hash) continue;
        const expected_input = subtable.classes[rule.classes_start .. rule.classes_start + extra_input_count];
        if (!std.mem.eql(
            u16,
            expected_input,
            input_classes[0..extra_input_count],
        )) continue;
        const expected_lookahead = subtable.classes[rule.classes_start + extra_input_count .. rule.classes_start +
            extra_input_count +
            rule.lookahead_count];
        if (!std.mem.eql(
            u16,
            expected_lookahead,
            lookahead_classes[0..rule.lookahead_count],
        )) continue;

        const matched_inputs = input_indices[0..rule.input_count];
        try output.safety.markChainingContext(
            allocator,
            &run,
            &.{},
            matched_inputs,
            lookahead_indices[0..rule.lookahead_count],
        );
        try applyNested(
            view,
            glyphs,
            matched_inputs[0],
            rule.lookup_index,
            adjustments,
            allocator,
            run,
        );
        return .{
            .matched = true,
            .next_pos = matched_inputs[matched_inputs.len - 1] + 1,
        };
    }
    return .{};
}
