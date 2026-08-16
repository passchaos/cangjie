//! ChainSubRule and ChainSubClassRule grammar validation.

const shared = @import("../shared.zig");

const Error = shared.Error;
const View = shared.View;

pub fn validateSet(
    comptime Executor: type,
    view: View,
    set_offset: usize,
) Error!void {
    const rule_count = try shared.read(view, set_offset);
    const rule_offsets = set_offset + 2;
    try view.ensure(rule_offsets, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_index| {
        // ChainSubRule and ChainSubClassRule offsets are required children.
        // Reject zero rather than treating the RuleSet header as rule data.
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
    var cursor = rule_offset;
    const backtrack_count = try shared.read(view, cursor);
    cursor += 2;
    cursor = try validateValues(view, cursor, backtrack_count);

    const input_count = try shared.read(view, cursor);
    if (input_count == 0) return error.BadGsub;
    cursor += 2;
    cursor = try validateValues(view, cursor, input_count - 1);

    const lookahead_count = try shared.read(view, cursor);
    cursor += 2;
    cursor = try validateValues(view, cursor, lookahead_count);

    const record_count = try shared.read(view, cursor);
    try shared.validateRecords(
        Executor,
        view,
        cursor + 2,
        record_count,
    );
}

fn validateValues(
    view: View,
    offset: usize,
    count: u16,
) Error!usize {
    try view.ensure(offset, @as(usize, count) * 2);
    // As with ContextSubst, this grammar is shared by glyph and class formats.
    // Preserve the established maxp check for every authored region value.
    for (0..count) |index| {
        try shared.ensureGlyphWithinMaxp(
            view,
            try shared.read(view, offset + index * 2),
        );
    }
    return offset + @as(usize, count) * 2;
}
