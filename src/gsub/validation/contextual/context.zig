//! ContextSubst format-1/2/3 grammar and nested-record validation.

const coverage_array = @import("../coverage_array.zig");
const shared = @import("shared.zig");

const Error = shared.Error;
const View = shared.View;

pub fn validate(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
) Error!void {
    switch (try shared.read(view, subtable_offset)) {
        1 => try validateGlyphOrClass(
            Executor,
            view,
            subtable_offset,
            false,
        ),
        2 => try validateGlyphOrClass(
            Executor,
            view,
            subtable_offset,
            true,
        ),
        3 => try validateCoverage(Executor, view, subtable_offset),
        else => return error.UnsupportedGsub,
    }
}

fn validateGlyphOrClass(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    class_format: bool,
) Error!void {
    const coverage = try shared.required(
        view,
        subtable_offset,
        try shared.read(view, subtable_offset + 2),
    );
    try shared.validateCoverage(view, coverage);
    if (class_format) {
        const class_def = try shared.required(
            view,
            subtable_offset,
            try shared.read(view, subtable_offset + 4),
        );
        try shared.validateClassDef(view, class_def);
    }

    const set_count_position = subtable_offset +
        @as(usize, if (class_format) 6 else 4);
    const set_count = try shared.read(view, set_count_position);
    const set_offsets = set_count_position + 2;
    try view.ensure(set_offsets, @as(usize, set_count) * 2);
    for (0..set_count) |set_index| {
        const relative = try shared.read(
            view,
            set_offsets + set_index * 2,
        );
        if (relative == 0) continue;
        try validateRuleSet(
            Executor,
            view,
            try shared.required(view, subtable_offset, relative),
        );
    }
}

fn validateCoverage(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
) Error!void {
    const input_count = try shared.read(view, subtable_offset + 2);
    if (input_count == 0) return error.BadGsub;
    const record_count = try shared.read(view, subtable_offset + 4);
    const coverage_offsets = subtable_offset + 6;
    try coverage_array.validate(
        view,
        subtable_offset,
        coverage_offsets,
        input_count,
        .indexed,
    );
    try shared.validateRecords(
        Executor,
        view,
        coverage_offsets + @as(usize, input_count) * 2,
        record_count,
    );
}

fn validateRuleSet(
    comptime Executor: type,
    view: View,
    set_offset: usize,
) Error!void {
    const rule_count = try shared.read(view, set_offset);
    const rule_offsets = set_offset + 2;
    try view.ensure(rule_offsets, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_index| {
        // A present RuleSet owns required child rules. Zero would alias the
        // count/offset header and reinterpret it as a rule payload.
        const relative = try shared.read(
            view,
            rule_offsets + rule_index * 2,
        );
        const rule = try shared.required(view, set_offset, relative);
        try validateRule(Executor, view, rule);
    }
}

fn validateRule(
    comptime Executor: type,
    view: View,
    rule_offset: usize,
) Error!void {
    const input_count = try shared.read(view, rule_offset);
    if (input_count == 0) return error.BadGsub;
    const record_count = try shared.read(view, rule_offset + 2);
    const input_values = rule_offset + 4;
    try view.ensure(
        input_values,
        (@as(usize, input_count) - 1) * 2,
    );
    // This shared grammar serves both glyph and class formats. Retain the
    // established maxp check for authored trailing values when maxp is bound.
    for (1..input_count) |input_index| {
        try shared.ensureGlyphWithinMaxp(
            view,
            try shared.read(
                view,
                input_values + (input_index - 1) * 2,
            ),
        );
    }
    try shared.validateRecords(
        Executor,
        view,
        input_values + (@as(usize, input_count) - 1) * 2,
        record_count,
    );
}
