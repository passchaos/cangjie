//! ReverseChainSingleSubst grammar and glyph-bound validation.

const coverage_array = @import("coverage_array.zig");
const table = @import("../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub fn validate(view: View, subtable_offset: usize) Error!void {
    if (try readU16(view, subtable_offset) != 1) {
        return error.UnsupportedGsub;
    }
    const coverage = try table.offset.required16(
        view,
        subtable_offset,
        try readU16(view, subtable_offset + 2),
    );
    try table.coverage.validate(view, coverage, .indexed);

    var cursor = subtable_offset + 4;
    const backtrack_count = try readU16(view, cursor);
    cursor += 2;
    try coverage_array.validate(
        view,
        subtable_offset,
        cursor,
        backtrack_count,
        .indexed,
    );
    cursor += @as(usize, backtrack_count) * 2;

    const lookahead_count = try readU16(view, cursor);
    cursor += 2;
    try coverage_array.validate(
        view,
        subtable_offset,
        cursor,
        lookahead_count,
        .indexed,
    );
    cursor += @as(usize, lookahead_count) * 2;

    const glyph_count = try readU16(view, cursor);
    cursor += 2;
    try table.coverage.validateIndices(view, coverage, glyph_count);
    try view.ensure(cursor, @as(usize, glyph_count) * 2);
    for (0..glyph_count) |glyph_index| {
        try ensureGlyphWithinMaxp(
            view,
            try readU16(view, cursor + glyph_index * 2),
        );
    }
}

fn ensureGlyphWithinMaxp(view: View, glyph: usize) Error!void {
    if (view.glyph_count) |glyph_count| {
        if (glyph >= glyph_count) return error.BadGsub;
    }
}

fn readU16(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
