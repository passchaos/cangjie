//! Accelerator-backed ChainContextSubst format-2 execution.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const class_context = @import("../../../../../opentype/class_context.zig");
const shaping_sections = @import("../../../../../shaping_sections.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const traversal = @import("../../../support/context_traversal.zig");
const commit = @import("commit.zig");
const match = @import("match.zig");
const matching = @import("matching.zig");
const model = @import("../../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
const Lookup = accelerator.Lookup;
const Subtable = accelerator.model.ChainingClassSubtable;
const View = table.View;

pub fn lookup(
    comptime Executor: type,
    view: View,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    lookup_accelerator: *const Lookup,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.items.len) {
        var next_position = position + 1;
        defer position = next_position;
        const first = glyphs.items[position];
        var subtable_index: usize = 0;
        while (subtable_index < subtable_count and
            subtable_index <
                lookup_accelerator.chaining_class_subtables.len) : (subtable_index += 1)
        {
            const parsed =
                lookup_accelerator.chaining_class_subtables[subtable_index];
            if (parsed.rules.len == 0) continue;
            const group = accelerator.index.class_first.findPrepared(
                parsed.classes,
                parsed.first_index_start,
                parsed.groups,
                first,
            ) orelse continue;
            // The compact first-glyph index is an exact necessary condition
            // and rejects most glyphs. Defer source-scope and LookupFlag
            // filtering until it proves that a rule group exists.
            if (!eligible(glyphs.items, position, lookup_flag, run)) break;
            const result = try applyEligibleGroupAt(
                Executor,
                view,
                parsed,
                group,
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

pub fn at(
    comptime Executor: type,
    view: View,
    parsed: Subtable,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!model.ApplyResult {
    if (!eligible(glyphs.items, position, lookup_flag, run)) return .{};
    const group = accelerator.index.class_first.findPrepared(
        parsed.classes,
        parsed.first_index_start,
        parsed.groups,
        glyphs.items[position],
    ) orelse return .{};
    if (!try secondInputClassMayMatch(
        view,
        parsed,
        group,
        glyphs.items,
        position,
        lookup_flag,
        run,
    )) return .{};
    return applyEligibleGroupAt(
        Executor,
        view,
        parsed,
        group,
        glyphs,
        position,
        allocator,
        lookup_flag,
        run,
    );
}

fn secondInputClassMayMatch(
    view: View,
    parsed: Subtable,
    group: *const class_context.RuleGroup,
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) table.class_def.Error!bool {
    const digest = group.second_input_class_digest;
    if (digest == 0) return true;

    // The digest describes logical input[1], not the physically adjacent
    // glyph. Resolve both logical inputs with the matcher's traversal because
    // `position` is merely the lookup cursor: a default-ignorable such as CGJ
    // may remain eligible there while being transparent to contextual input.
    const first_index = traversal.nextIndex(
        glyphs,
        position,
        lookup_flag,
        run,
        false,
        position,
    ) orelse return false;
    const second_index = traversal.nextIndex(
        glyphs,
        first_index + 1,
        lookup_flag,
        run,
        false,
        position,
    ) orelse return false;
    const second_class = try table.class_def.valueWithDense(
        view,
        parsed.input_class_def,
        parsed.input_class_values,
        glyphs[second_index],
    );
    const bit: u3 = @truncate(second_class);
    return (digest & (@as(u8, 1) << bit)) != 0;
}

noinline fn applyEligibleGroupAt(
    comptime Executor: type,
    view: View,
    parsed: Subtable,
    group: *const class_context.RuleGroup,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) linksection(shaping_sections.isolated_hotpaths) Error!model.ApplyResult {
    var matched: match.Match = undefined;
    if (!try matching.acceleratedGroup(
        view,
        parsed,
        group,
        glyphs.items,
        position,
        lookup_flag,
        run,
        &matched,
    )) return .{};
    return commit.apply(
        Executor,
        view,
        glyphs,
        position,
        &matched,
        allocator,
        run,
    );
}

fn eligible(
    glyphs: []const GlyphId,
    position: usize,
    lookup_flag: u16,
    run: Options,
) bool {
    return position < glyphs.len and
        filtering.lookupCursorAllowsGlyph(run, position) and
        !filtering.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[position],
        );
}
