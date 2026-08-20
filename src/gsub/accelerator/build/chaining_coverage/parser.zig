//! ChainContextSubst format-3 cursor parsing.

const model = @import("../../model.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.view.Error;
pub const Parsed = model.ChainingCoverageSubtable;
pub const View = table.View;

pub fn parse(view: View, subtable_offset: usize) Error!?Parsed {
    if (try view.readU16(subtable_offset) != 3) return null;
    var cursor = subtable_offset + 2;
    const backtrack_count = try view.readU16(cursor);
    cursor += 2;
    const backtrack_offsets_pos = cursor;
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try view.readU16(cursor);
    cursor += 2;
    if (input_count == 0) return null;
    const input_offsets_pos = cursor;
    cursor += @as(usize, input_count) * 2;

    const lookahead_count = try view.readU16(cursor);
    cursor += 2;
    const lookahead_offsets_pos = cursor;
    cursor += @as(usize, lookahead_count) * 2;

    const subst_count = try view.readU16(cursor);
    cursor += 2;
    return .{
        .subtable_offset = subtable_offset,
        .backtrack_offsets_pos = backtrack_offsets_pos,
        .backtrack_count = backtrack_count,
        .input_offsets_pos = input_offsets_pos,
        .input_count = input_count,
        .lookahead_offsets_pos = lookahead_offsets_pos,
        .lookahead_count = lookahead_count,
        .records_pos = cursor,
        .subst_count = subst_count,
    };
}

pub fn firstInputCoverage(view: View, subtable_offset: usize) Error!?usize {
    const parsed = try parse(view, subtable_offset) orelse return null;
    return @as(?usize, try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(parsed.input_offsets_pos),
    ));
}
