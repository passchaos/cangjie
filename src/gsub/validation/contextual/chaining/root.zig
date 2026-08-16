//! ChainContextSubst format-1/2/3 validation surface.

const coverage = @import("coverage.zig");
const rules = @import("rules.zig");
const shared = @import("../shared.zig");

const Error = shared.Error;
const View = shared.View;

pub const Mode = enum { strict, shaping };

pub fn validate(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    mode: Mode,
) Error!void {
    switch (try shared.read(view, subtable_offset)) {
        1 => try validateGlyph(Executor, view, subtable_offset),
        2 => try validateClass(Executor, view, subtable_offset),
        3 => try coverage.validate(
            Executor,
            view,
            subtable_offset,
            if (mode == .strict) .strict else .shaping,
        ),
        else => return error.UnsupportedGsub,
    }
}

fn validateGlyph(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
) Error!void {
    const coverage_offset = try shared.required(
        view,
        subtable_offset,
        try shared.read(view, subtable_offset + 2),
    );
    try shared.validateCoverage(view, coverage_offset);
    try validateSets(
        Executor,
        view,
        subtable_offset,
        subtable_offset + 4,
    );
}

fn validateClass(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
) Error!void {
    const coverage_offset = try shared.required(
        view,
        subtable_offset,
        try shared.read(view, subtable_offset + 2),
    );
    const backtrack_class_def = try shared.optionalClassDef(
        view,
        subtable_offset,
        try shared.read(view, subtable_offset + 4),
    );
    const input_class_def = try shared.required(
        view,
        subtable_offset,
        try shared.read(view, subtable_offset + 6),
    );
    const lookahead_class_def = try shared.optionalClassDef(
        view,
        subtable_offset,
        try shared.read(view, subtable_offset + 8),
    );
    try shared.validateCoverage(view, coverage_offset);
    try shared.validateOptionalClassDef(view, backtrack_class_def);
    try shared.validateClassDef(view, input_class_def);
    try shared.validateOptionalClassDef(view, lookahead_class_def);
    try validateSets(
        Executor,
        view,
        subtable_offset,
        subtable_offset + 10,
    );
}

fn validateSets(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    count_position: usize,
) Error!void {
    const set_count = try shared.read(view, count_position);
    const set_offsets = count_position + 2;
    try view.ensure(set_offsets, @as(usize, set_count) * 2);
    for (0..set_count) |set_index| {
        const relative = try shared.read(
            view,
            set_offsets + set_index * 2,
        );
        if (relative == 0) continue;
        try rules.validateSet(
            Executor,
            view,
            try shared.required(view, subtable_offset, relative),
        );
    }
}
