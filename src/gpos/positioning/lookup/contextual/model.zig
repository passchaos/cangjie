//! Shared value types for contextual GPOS lookup grammar.

const table = @import("../../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

/// A nullable array of offsets to rule sets, relative to one positioning
/// subtable. Null entries are explicitly permitted by the OpenType grammar.
pub const RuleSetList = struct {
    base_offset: usize,
    offsets_pos: usize,
    count: u16,

    pub fn resolve(
        self: RuleSetList,
        view: View,
        index: usize,
    ) Error!?usize {
        if (index >= self.count) return error.BadGpos;
        return table.offset.optional16(
            view,
            self.base_offset,
            try view.readU16(self.offsets_pos + index * 2),
        );
    }
};

/// A non-null array of rule offsets relative to a RuleSet.
pub const RuleSet = struct {
    offset: usize,
    rule_offsets_pos: usize,
    rule_count: u16,

    pub fn ruleOffset(
        self: RuleSet,
        view: View,
        index: usize,
    ) Error!usize {
        if (index >= self.rule_count) return error.BadGpos;
        return table.offset.required16(
            view,
            self.offset,
            try view.readU16(self.rule_offsets_pos + index * 2),
        );
    }
};

/// A consecutive array of Coverage offsets relative to one subtable.
pub const CoverageRegion = struct {
    base_offset: usize,
    offsets_pos: usize,
    count: u16,

    pub fn coverageOffset(
        self: CoverageRegion,
        view: View,
        index: usize,
    ) Error!usize {
        if (index >= self.count) return error.BadGpos;
        return table.offset.required16(
            view,
            self.base_offset,
            try view.readU16(self.offsets_pos + index * 2),
        );
    }

    /// Context coverage arrays only need membership semantics. Unlike a
    /// top-level indexed Coverage, separate arrays describe each input slot,
    /// so Coverage indexes do not select a parallel record.
    pub fn validate(self: CoverageRegion, view: View) Error!void {
        for (0..self.count) |index| {
            try table.coverage.validate(
                view,
                try self.coverageOffsetForValidation(view, index),
                .membership,
            );
        }
    }

    fn coverageOffsetForValidation(
        self: CoverageRegion,
        view: View,
        index: usize,
    ) Error!usize {
        return self.coverageOffset(view, index) catch |err| switch (err) {
            error.EndOfStream => error.BadGpos,
            else => err,
        };
    }
};

pub const PositionRecord = struct {
    sequence_index: u16,
    lookup_index: u16,
};

/// PosLookupRecord region shared by all contextual formats.
pub const PositionRecords = struct {
    records_pos: usize,
    count: u16,
    input_count: u16,

    pub fn record(
        self: PositionRecords,
        view: View,
        index: usize,
    ) Error!PositionRecord {
        if (index >= self.count) return error.BadGpos;
        const offset = self.records_pos + index * 4;
        return .{
            .sequence_index = try view.readU16(offset),
            .lookup_index = try view.readU16(offset + 2),
        };
    }

    /// Validate the part of PosLookupRecord that is local to this rule.
    /// Lookup-list bounds and recursive lookup payloads are runtime concerns
    /// and are intentionally preflighted by the root GPOS validator.
    pub fn validateSequenceIndices(
        self: PositionRecords,
        view: View,
    ) Error!void {
        for (0..self.count) |index| {
            const item = self.record(view, index) catch |err| switch (err) {
                error.EndOfStream => return error.BadGpos,
                else => return err,
            };
            if (item.sequence_index >= self.input_count) return error.BadGpos;
        }
    }
};

pub const ContextGlyph = struct {
    coverage_offset: usize,
    sets: RuleSetList,
};

pub const ContextClass = struct {
    coverage_offset: usize,
    class_def_offset: usize,
    sets: RuleSetList,
};

pub const ContextCoverage = struct {
    input_coverages: CoverageRegion,
    records: PositionRecords,
};

pub const Context = union(enum) {
    glyph: ContextGlyph,
    class: ContextClass,
    coverage: ContextCoverage,
};

pub const ChainingGlyph = struct {
    coverage_offset: usize,
    sets: RuleSetList,
};

pub const ChainingClass = struct {
    coverage_offset: usize,
    backtrack_class_def: usize,
    input_class_def: usize,
    lookahead_class_def: usize,
    sets: RuleSetList,
};

pub const ChainingCoverage = struct {
    subtable_offset: usize,
    backtrack_coverages: CoverageRegion,
    input_coverages: CoverageRegion,
    lookahead_coverages: CoverageRegion,
    records: PositionRecords,
};

pub const Chaining = union(enum) {
    glyph: ChainingGlyph,
    class: ChainingClass,
    coverage: ChainingCoverage,
};

/// Parsed PosRule or PosClassRule. `input_values_pos` excludes the first input,
/// whose glyph/class is selected by the parent Coverage and RuleSet index.
pub const ContextRule = struct {
    rule_offset: usize,
    input_count: u16,
    input_values_pos: usize,
    records: PositionRecords,
};

/// Parsed ChainPosRule or ChainPosClassRule. As in ContextRule, the first input
/// is implicit in the parent RuleSet selection.
pub const ChainingRule = struct {
    rule_offset: usize,
    backtrack_count: u16,
    backtrack_values_pos: usize,
    input_count: u16,
    input_values_pos: usize,
    lookahead_count: u16,
    lookahead_values_pos: usize,
    records: PositionRecords,
};

pub fn parseRuleSet(view: View, set_offset: usize) Error!RuleSet {
    const rule_count = try view.readU16(set_offset);
    const rule_offsets_pos = try advance(view, set_offset, 2);
    _ = try advance(view, rule_offsets_pos, @as(usize, rule_count) * 2);
    return .{
        .offset = set_offset,
        .rule_offsets_pos = rule_offsets_pos,
        .rule_count = rule_count,
    };
}

pub fn parseRuleSetForValidation(
    view: View,
    set_offset: usize,
) Error!RuleSet {
    return parseRuleSet(view, set_offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

/// Advance only after proving the complete region lies in the declared GPOS
/// range. That proof also makes the addition overflow-free.
pub fn advance(view: View, offset: usize, amount: usize) Error!usize {
    try view.ensure(offset, amount);
    return offset + amount;
}
