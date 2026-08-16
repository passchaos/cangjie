//! ChainContextSubst format-3 coverage and record validation.

const coverage_array = @import("../../coverage_array.zig");
const shared = @import("../shared.zig");

const Error = shared.Error;
const View = shared.View;

pub const Mode = enum {
    /// Coverage indexes are canonical and ordered for font-load validation.
    strict,
    /// Context coverages are membership sets; duplicate glyphs are accepted.
    shaping,
};

pub fn validate(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    mode: Mode,
) Error!void {
    var cursor = subtable_offset + 2;
    const backtrack_count = try shared.read(view, cursor);
    cursor += 2;
    try validateArray(view, subtable_offset, cursor, backtrack_count, mode);
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try shared.read(view, cursor);
    if (input_count == 0) return error.BadGsub;
    cursor += 2;
    try validateArray(view, subtable_offset, cursor, input_count, mode);
    cursor += @as(usize, input_count) * 2;

    const lookahead_count = try shared.read(view, cursor);
    cursor += 2;
    try validateArray(view, subtable_offset, cursor, lookahead_count, mode);
    cursor += @as(usize, lookahead_count) * 2;

    const record_count = try shared.read(view, cursor);
    try shared.validateRecords(
        Executor,
        view,
        cursor + 2,
        record_count,
    );
}

fn validateArray(
    view: View,
    base: usize,
    offsets: usize,
    count: u16,
    mode: Mode,
) Error!void {
    return coverage_array.validate(
        view,
        base,
        offsets,
        count,
        switch (mode) {
            .strict => .indexed,
            .shaping => .membership,
        },
    );
}
