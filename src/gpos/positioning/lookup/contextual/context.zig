//! ContextPos formats 1, 2, and 3.

const table = @import("../../../table/root.zig");
const model = @import("model.zig");

pub const Error = model.Error;
pub const View = model.View;

pub fn parse(view: View, subtable_offset: usize) Error!model.Context {
    const pos_format = try view.readU16(subtable_offset);
    return switch (pos_format) {
        1 => .{ .glyph = try parseGlyph(view, subtable_offset) },
        2 => .{ .class = try parseClass(view, subtable_offset) },
        3 => .{ .coverage = try parseCoverage(view, subtable_offset) },
        else => error.UnsupportedGpos,
    };
}

/// Parse a ContextPos header and validate grammar that does not recurse into
/// PosLookupRecord lookup references.
pub fn parseForValidation(
    view: View,
    subtable_offset: usize,
) Error!model.Context {
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
            try table.class_def.validate(view, subtable.class_def_offset);
        },
        .coverage => |subtable| {
            if (subtable.records.input_count == 0) return error.BadGpos;
            try subtable.input_coverages.validate(view);
            try subtable.records.validateSequenceIndices(view);
        },
    }
    return parsed;
}

pub fn parseRule(view: View, rule_offset: usize) Error!model.ContextRule {
    const input_count = try view.readU16(rule_offset);
    const pos_count =
        try view.readU16(try model.advance(view, rule_offset, 2));
    const input_values_pos = try model.advance(view, rule_offset, 4);
    const extra_input_count: usize =
        if (input_count == 0) 0 else @as(usize, input_count) - 1;
    const records_pos =
        try model.advance(view, input_values_pos, extra_input_count * 2);
    _ = try model.advance(view, records_pos, @as(usize, pos_count) * 4);
    return .{
        .rule_offset = rule_offset,
        .input_count = input_count,
        .input_values_pos = input_values_pos,
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
) Error!model.ContextRule {
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
) Error!model.ContextGlyph {
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
) Error!model.ContextClass {
    const coverage_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(try model.advance(view, subtable_offset, 2)),
    );
    const class_def_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(try model.advance(view, subtable_offset, 4)),
    );
    const set_count =
        try view.readU16(try model.advance(view, subtable_offset, 6));
    const offsets_pos = try model.advance(view, subtable_offset, 8);
    _ = try model.advance(view, offsets_pos, @as(usize, set_count) * 2);
    return .{
        .coverage_offset = coverage_offset,
        .class_def_offset = class_def_offset,
        .sets = .{
            .base_offset = subtable_offset,
            .offsets_pos = offsets_pos,
            .count = set_count,
        },
    };
}

fn parseCoverage(
    view: View,
    subtable_offset: usize,
) Error!model.ContextCoverage {
    const input_count =
        try view.readU16(try model.advance(view, subtable_offset, 2));
    const pos_count =
        try view.readU16(try model.advance(view, subtable_offset, 4));
    const offsets_pos = try model.advance(view, subtable_offset, 6);
    const records_pos =
        try model.advance(view, offsets_pos, @as(usize, input_count) * 2);
    _ = try model.advance(view, records_pos, @as(usize, pos_count) * 4);
    return .{
        .input_coverages = .{
            .base_offset = subtable_offset,
            .offsets_pos = offsets_pos,
            .count = input_count,
        },
        .records = .{
            .records_pos = records_pos,
            .count = pos_count,
            .input_count = input_count,
        },
    };
}
