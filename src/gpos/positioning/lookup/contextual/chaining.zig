//! ChainContextPos formats 1, 2, and 3.

const table = @import("../../../table/root.zig");
const model = @import("model.zig");

pub const Error = model.Error;
pub const View = model.View;

pub fn parse(view: View, subtable_offset: usize) Error!model.Chaining {
    const pos_format = try view.readU16(subtable_offset);
    return switch (pos_format) {
        1 => .{ .glyph = try parseGlyph(view, subtable_offset) },
        2 => .{ .class = try parseClass(view, subtable_offset) },
        3 => .{
            .coverage = try parseCoverageBody(
                view,
                subtable_offset,
            ),
        },
        else => error.UnsupportedGpos,
    };
}

/// Parse a ChainContextPos header and validate its non-recursive grammar.
pub fn parseForValidation(
    view: View,
    subtable_offset: usize,
) Error!model.Chaining {
    const parsed = parse(view, subtable_offset) catch |err| switch (err) {
        error.EndOfStream => return error.BadGpos,
        else => return err,
    };
    switch (parsed) {
        .glyph => |subtable| {
            try table.coverage.validate(
                view,
                subtable.coverage_offset,
                .indexed,
            );
        },
        .class => |subtable| {
            try table.coverage.validate(
                view,
                subtable.coverage_offset,
                .indexed,
            );
            try table.class_def.validate(
                view,
                subtable.backtrack_class_def,
            );
            try table.class_def.validate(view, subtable.input_class_def);
            try table.class_def.validate(
                view,
                subtable.lookahead_class_def,
            );
        },
        .coverage => |subtable| {
            if (subtable.records.input_count == 0) return error.BadGpos;
            try subtable.backtrack_coverages.validate(view);
            try subtable.input_coverages.validate(view);
            try subtable.lookahead_coverages.validate(view);
            try subtable.records.validateSequenceIndices(view);
        },
    }
    return parsed;
}

/// Return only format 3 chaining positioning. A zero-input table cannot match
/// a run, so runtime callers receive null; validation uses `parse` and reports
/// that malformed grammar as BadGpos instead.
pub fn parseCoverage(
    view: View,
    subtable_offset: usize,
) Error!?model.ChainingCoverage {
    if (try view.readU16(subtable_offset) != 3) return null;
    const parsed = try parseCoverageBody(view, subtable_offset);
    if (parsed.records.input_count == 0) return null;
    return parsed;
}

pub fn parseRule(
    view: View,
    rule_offset: usize,
) Error!model.ChainingRule {
    var cursor = rule_offset;

    const backtrack_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const backtrack_values_pos = cursor;
    cursor =
        try model.advance(view, cursor, @as(usize, backtrack_count) * 2);

    const input_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const input_values_pos = cursor;
    const extra_input_count: usize =
        if (input_count == 0) 0 else @as(usize, input_count) - 1;
    cursor = try model.advance(view, cursor, extra_input_count * 2);

    const lookahead_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const lookahead_values_pos = cursor;
    cursor = try model.advance(view, cursor, @as(usize, lookahead_count) * 2);

    const pos_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const records_pos = cursor;
    _ = try model.advance(view, records_pos, @as(usize, pos_count) * 4);

    return .{
        .rule_offset = rule_offset,
        .backtrack_count = backtrack_count,
        .backtrack_values_pos = backtrack_values_pos,
        .input_count = input_count,
        .input_values_pos = input_values_pos,
        .lookahead_count = lookahead_count,
        .lookahead_values_pos = lookahead_values_pos,
        .records = .{
            .records_pos = records_pos,
            .count = pos_count,
            .input_count = input_count,
        },
    };
}

pub fn parseRuleForValidation(
    view: View,
    rule_offset: usize,
) Error!model.ChainingRule {
    const parsed = parseRule(view, rule_offset) catch |err| switch (err) {
        error.EndOfStream => return error.BadGpos,
        else => return err,
    };
    if (parsed.input_count == 0) return error.BadGpos;
    try parsed.records.validateSequenceIndices(view);
    return parsed;
}

fn parseGlyph(
    view: View,
    subtable_offset: usize,
) Error!model.ChainingGlyph {
    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(try model.advance(view, subtable_offset, 2)),
    );
    const set_count =
        try view.readU16(try model.advance(view, subtable_offset, 4));
    const offsets_pos = try model.advance(view, subtable_offset, 6);
    _ = try model.advance(view, offsets_pos, @as(usize, set_count) * 2);
    return .{
        .coverage_offset = coverage_offset,
        .sets = .{
            .base_offset = subtable_offset,
            .offsets_pos = offsets_pos,
            .count = set_count,
        },
    };
}

fn parseClass(
    view: View,
    subtable_offset: usize,
) Error!model.ChainingClass {
    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(try model.advance(view, subtable_offset, 2)),
    );
    const backtrack_class_def = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(try model.advance(view, subtable_offset, 4)),
    );
    const input_class_def = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(try model.advance(view, subtable_offset, 6)),
    );
    const lookahead_class_def = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(try model.advance(view, subtable_offset, 8)),
    );
    const set_count =
        try view.readU16(try model.advance(view, subtable_offset, 10));
    const offsets_pos = try model.advance(view, subtable_offset, 12);
    _ = try model.advance(view, offsets_pos, @as(usize, set_count) * 2);
    return .{
        .coverage_offset = coverage_offset,
        .backtrack_class_def = backtrack_class_def,
        .input_class_def = input_class_def,
        .lookahead_class_def = lookahead_class_def,
        .sets = .{
            .base_offset = subtable_offset,
            .offsets_pos = offsets_pos,
            .count = set_count,
        },
    };
}

fn parseCoverageBody(
    view: View,
    subtable_offset: usize,
) Error!model.ChainingCoverage {
    var cursor = try model.advance(view, subtable_offset, 2);

    const backtrack_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const backtrack_offsets_pos = cursor;
    cursor =
        try model.advance(view, cursor, @as(usize, backtrack_count) * 2);

    const input_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const input_offsets_pos = cursor;
    cursor = try model.advance(view, cursor, @as(usize, input_count) * 2);

    const lookahead_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const lookahead_offsets_pos = cursor;
    cursor = try model.advance(view, cursor, @as(usize, lookahead_count) * 2);

    const pos_count = try view.readU16(cursor);
    cursor = try model.advance(view, cursor, 2);
    const records_pos = cursor;
    _ = try model.advance(view, records_pos, @as(usize, pos_count) * 4);

    return .{
        .subtable_offset = subtable_offset,
        .backtrack_coverages = .{
            .base_offset = subtable_offset,
            .offsets_pos = backtrack_offsets_pos,
            .count = backtrack_count,
        },
        .input_coverages = .{
            .base_offset = subtable_offset,
            .offsets_pos = input_offsets_pos,
            .count = input_count,
        },
        .lookahead_coverages = .{
            .base_offset = subtable_offset,
            .offsets_pos = lookahead_offsets_pos,
            .count = lookahead_count,
        },
        .records = .{
            .records_pos = records_pos,
            .count = pos_count,
            .input_count = input_count,
        },
    };
}
