//! Bounded ChainContextSubst format-1 accelerator construction.
//!
//! Admission is intentionally lookup-wide. A partially decoded lookup would
//! hide later authored subtables from accelerated execution, so any subtable
//! or rule outside the narrow common shape returns an empty fallback.

const std = @import("std");
const model = @import("../model.zig");
const ownership = @import("../ownership.zig");
const shared = @import("class_context/shared.zig");
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Source = shared.Source;
pub const View = table.View;

pub fn build(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    source: Source,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]model.ChainingGlyphSubtable {
    const subtables =
        try allocator.alloc(model.ChainingGlyphSubtable, subtable_count);
    @memset(subtables, .{});
    errdefer {
        ownership.deinitChainingGlyphSubtableContents(
            allocator,
            subtables,
        );
        allocator.free(subtables);
    }

    var admitted = true;
    for (subtables, 0..) |*subtable, subtable_index| {
        const offset = shared.resolveSubtable(
            view,
            lookup_offset,
            subtable_index,
            source,
            6,
        ) catch |err| return normalizeStructuralError(err);
        const candidate = buildSubtable(view, offset, allocator) catch |err|
            return switch (err) {
                error.EndOfStream => error.BadGsub,
                else => err,
            };
        if (candidate) |built| {
            subtable.* = built;
        } else {
            // Keep scanning later subtables. Capability rejection must not
            // suppress structural errors that generic execution could
            // otherwise discover only after an earlier subtable mutated.
            admitted = false;
        }
    }
    if (!admitted) {
        // Acquire the fallback result before releasing partial ownership. If
        // this zero-length allocation reports OOM, the outer errdefer remains
        // the sole owner of every successfully decoded subtable.
        const empty = try allocator.alloc(model.ChainingGlyphSubtable, 0);
        ownership.deinitChainingGlyphSubtableContents(allocator, subtables);
        allocator.free(subtables);
        return empty;
    }
    return subtables;
}

fn buildSubtable(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!?model.ChainingGlyphSubtable {
    if (try view.readU16(subtable_offset) != 1) return null;
    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    var admitted = try coverageHasUniqueGlyphs(view, coverage_offset);

    const set_count = try view.readU16(subtable_offset + 4);
    try view.ensure(subtable_offset + 6, @as(usize, set_count) * 2);
    var rules = std.ArrayList(model.ChainingGlyphRule).empty;
    defer rules.deinit(allocator);

    for (0..set_count) |set_index| {
        const set_relative =
            try view.readU16(subtable_offset + 6 + set_index * 2);
        if (set_relative == 0) continue;
        const set_offset = try table.offset.required16(
            view,
            subtable_offset,
            set_relative,
        );
        const rule_count = try view.readU16(set_offset);
        try view.ensure(set_offset + 2, @as(usize, rule_count) * 2);
        var decoded: ?DecodedRule = null;
        var set_admitted = rule_count == 1;
        for (0..rule_count) |rule_index| {
            const rule_offset = try table.offset.required16(
                view,
                set_offset,
                try view.readU16(set_offset + 2 + rule_index * 2),
            );
            const scanned = try scanRule(view, rule_offset);
            set_admitted = set_admitted and scanned != null;
            if (rule_index == 0) decoded = scanned;
        }
        admitted = admitted and set_admitted;
        if (!set_admitted) continue;

        // RuleSets beyond Coverage are unreachable in generic execution. They
        // still must satisfy admission above, but need no searchable entry.
        const first = try table.coverage.glyphAt(
            view,
            coverage_offset,
            set_index,
        ) orelse continue;
        try rules.append(allocator, .{
            .first = first,
            .second = decoded.?.second,
            .lookahead = decoded.?.lookahead,
            .nested_lookup = decoded.?.nested_lookup,
        });
    }
    if (!admitted) return null;

    std.sort.heap(
        model.ChainingGlyphRule,
        rules.items,
        {},
        ruleLessThan,
    );
    // Indexed format-1 Coverage is unique by grammar. Valid format-2 Coverage
    // may overlap, however, so the policy check above rejects it rather than
    // risking a different winner after sorting. Keep this final invariant
    // check close to the binary-search representation as defense in depth.
    if (rules.items.len > 1) {
        for (
            rules.items[1..],
            rules.items[0 .. rules.items.len - 1],
        ) |rule, prior| {
            if (rule.first == prior.first) return null;
        }
    }

    return .{
        .subtable_offset = subtable_offset,
        .rules = try rules.toOwnedSlice(allocator),
    };
}

const DecodedRule = struct {
    second: u16,
    lookahead: ?u16,
    nested_lookup: u16,
};

/// Scan the complete authored rule before reporting whether its shape is
/// accelerator-compatible. Reading every region and record is essential:
/// returning a capability miss early could otherwise let a truncated tail
/// escape lookup preflight and fail only after an earlier match mutated.
fn scanRule(view: View, rule_offset: usize) Error!?DecodedRule {
    var cursor = rule_offset;
    const backtrack_count = try view.readU16(cursor);
    cursor += 2;
    cursor = try scanGlyphs(view, cursor, backtrack_count);

    const input_count = try view.readU16(cursor);
    if (input_count == 0) return error.BadGsub;
    cursor += 2;
    const second = if (input_count >= 2)
        try view.readU16(cursor)
    else
        0;
    cursor = try scanGlyphs(view, cursor, input_count - 1);

    const lookahead_count = try view.readU16(cursor);
    cursor += 2;
    const lookahead = if (lookahead_count != 0)
        try view.readU16(cursor)
    else
        null;
    cursor = try scanGlyphs(view, cursor, lookahead_count);

    const subst_count = try view.readU16(cursor);
    cursor += 2;
    try view.ensure(cursor, @as(usize, subst_count) * 4);
    var sequence_index: u16 = 0;
    var nested_lookup: u16 = 0;
    for (0..subst_count) |record_index| {
        const record = cursor + record_index * 4;
        const sequence = try view.readU16(record);
        const nested = try view.readU16(record + 2);
        if (record_index == 0) {
            sequence_index = sequence;
            nested_lookup = nested;
        }
    }

    if (backtrack_count != 0 or
        input_count != 2 or
        lookahead_count > 1 or
        subst_count != 1 or
        sequence_index != 0)
    {
        return null;
    }
    return .{
        .second = second,
        .lookahead = lookahead,
        .nested_lookup = nested_lookup,
    };
}

fn scanGlyphs(view: View, offset: usize, count: u16) Error!usize {
    try view.ensure(offset, @as(usize, count) * 2);
    for (0..count) |index| {
        const glyph = try view.readU16(offset + index * 2);
        if (view.glyph_count) |glyph_count| {
            if (glyph >= glyph_count) return error.BadGsub;
        }
    }
    return offset + @as(usize, count) * 2;
}

/// Binary search is exact only when one first glyph selects one Coverage
/// index. Format-1 already requires strict order. For format-2, reject valid
/// but overlapping or out-of-order ranges and let generic execution preserve
/// the specification's first-authored-range behavior.
fn coverageHasUniqueGlyphs(view: View, coverage_offset: usize) Error!bool {
    try table.coverage.validate(view, coverage_offset, .indexed);
    if (try view.readU16(coverage_offset) != 2) return true;

    const range_count = try view.readU16(coverage_offset + 2);
    var previous_end: ?u16 = null;
    for (0..range_count) |range_index| {
        const range = coverage_offset + 4 + range_index * 6;
        const start = try view.readU16(range);
        const end = try view.readU16(range + 2);
        if (previous_end) |prior| {
            if (start <= prior) return false;
        }
        previous_end = end;
    }
    return true;
}

fn ruleLessThan(
    _: void,
    lhs: model.ChainingGlyphRule,
    rhs: model.ChainingGlyphRule,
) bool {
    return lhs.first < rhs.first;
}

fn normalizeStructuralError(err: Error) Error {
    return switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
