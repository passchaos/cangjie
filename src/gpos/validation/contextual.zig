//! ContextPos and ChainContextPos rule validation.
//!
//! The caller supplies its concrete recursive record validator at comptime.
//! This keeps contextual table traversal independent without an opaque context,
//! erased callback, or runtime indirect call.

const positioning = @import("../positioning/root.zig");
const table = @import("../table/root.zig");

pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const View = table.View;

pub const ValidateRecordsFn = fn (
    View,
    usize,
    usize,
    usize,
    usize,
) Error!void;

pub fn contextSubtable(
    view: View,
    subtable_offset: usize,
    depth: usize,
    comptime validateRecords: ValidateRecordsFn,
) Error!void {
    switch (try positioning.lookup.contextual.parseContextForValidation(
        view,
        subtable_offset,
    )) {
        .glyph => |subtable| {
            for (0..subtable.sets.count) |set_index| {
                const set =
                    try subtable.sets.resolve(view, set_index) orelse continue;
                try contextRuleSet(view, set, depth, validateRecords);
            }
        },
        .class => |subtable| {
            for (0..subtable.sets.count) |set_index| {
                const set =
                    try subtable.sets.resolve(view, set_index) orelse continue;
                try contextRuleSet(view, set, depth, validateRecords);
            }
        },
        .coverage => |subtable| try validateRecords(
            view,
            subtable.records.records_pos,
            subtable.records.count,
            subtable.records.input_count,
            depth,
        ),
    }
}

pub fn contextRuleSet(
    view: View,
    rule_set_offset: usize,
    depth: usize,
    comptime validateRecords: ValidateRecordsFn,
) Error!void {
    const set = try positioning.lookup.contextual.parseRuleSetForValidation(
        view,
        rule_set_offset,
    );
    for (0..set.rule_count) |rule_index| {
        // Rule offsets are mandatory children of a non-null RuleSet.
        try contextRule(
            view,
            try set.ruleOffset(view, rule_index),
            depth,
            validateRecords,
        );
    }
}

pub fn chainingSubtable(
    view: View,
    subtable_offset: usize,
    depth: usize,
    comptime validateRecords: ValidateRecordsFn,
) Error!void {
    switch (try positioning.lookup.contextual.parseChainingForValidation(
        view,
        subtable_offset,
    )) {
        .glyph => |subtable| {
            for (0..subtable.sets.count) |set_index| {
                const set =
                    try subtable.sets.resolve(view, set_index) orelse continue;
                try chainingRuleSet(view, set, depth, validateRecords);
            }
        },
        .class => |subtable| {
            for (0..subtable.sets.count) |set_index| {
                const set =
                    try subtable.sets.resolve(view, set_index) orelse continue;
                try chainingRuleSet(view, set, depth, validateRecords);
            }
        },
        .coverage => |subtable| try validateRecords(
            view,
            subtable.records.records_pos,
            subtable.records.count,
            subtable.records.input_count,
            depth,
        ),
    }
}

pub fn chainingRuleSet(
    view: View,
    rule_set_offset: usize,
    depth: usize,
    comptime validateRecords: ValidateRecordsFn,
) Error!void {
    const set = try positioning.lookup.contextual.parseRuleSetForValidation(
        view,
        rule_set_offset,
    );
    for (0..set.rule_count) |rule_index| {
        try chainingRule(
            view,
            try set.ruleOffset(view, rule_index),
            depth,
            validateRecords,
        );
    }
}

fn contextRule(
    view: View,
    rule_offset: usize,
    depth: usize,
    comptime validateRecords: ValidateRecordsFn,
) Error!void {
    const rule =
        try positioning.lookup.contextual.parseContextRuleForValidation(
            view,
            rule_offset,
        );
    for (1..rule.input_count) |input_index| {
        try glyphWithinMaxp(
            view,
            try readU16(
                view,
                rule.input_values_pos + (input_index - 1) * 2,
            ),
        );
    }
    try validateRecords(
        view,
        rule.records.records_pos,
        rule.records.count,
        rule.records.input_count,
        depth,
    );
}

fn chainingRule(
    view: View,
    rule_offset: usize,
    depth: usize,
    comptime validateRecords: ValidateRecordsFn,
) Error!void {
    const rule =
        try positioning.lookup.contextual.parseChainingRuleForValidation(
            view,
            rule_offset,
        );
    for (0..rule.backtrack_count) |index| {
        try glyphWithinMaxp(
            view,
            try readU16(view, rule.backtrack_values_pos + index * 2),
        );
    }
    for (1..rule.input_count) |index| {
        try glyphWithinMaxp(
            view,
            try readU16(
                view,
                rule.input_values_pos + (index - 1) * 2,
            ),
        );
    }
    for (0..rule.lookahead_count) |index| {
        try glyphWithinMaxp(
            view,
            try readU16(view, rule.lookahead_values_pos + index * 2),
        );
    }
    try validateRecords(
        view,
        rule.records.records_pos,
        rule.records.count,
        rule.records.input_count,
        depth,
    );
}

fn glyphWithinMaxp(view: View, glyph_id: usize) Error!void {
    if (view.glyph_count) |glyph_count| {
        if (glyph_id >= glyph_count) return error.BadGpos;
    }
}

fn readU16(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
