//! MultipleSubst and AlternateSubst required child-array validation.

const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub fn multiple(
    view: View,
    subtable_offset: usize,
) Error!void {
    return validate(view, subtable_offset);
}

pub fn alternate(
    view: View,
    subtable_offset: usize,
) Error!void {
    return validate(view, subtable_offset);
}

fn validate(view: View, subtable_offset: usize) Error!void {
    if (try readU16(view, subtable_offset) != 1) {
        return error.UnsupportedGsub;
    }
    const coverage = try table.offset.required16(
        view,
        subtable_offset,
        try readU16(view, subtable_offset + 2),
    );
    try table.coverage.validate(view, coverage, .indexed);
    const child_count = try readU16(view, subtable_offset + 4);
    try table.coverage.validateIndices(view, coverage, child_count);
    const child_offsets = subtable_offset + 6;
    try view.ensure(child_offsets, @as(usize, child_count) * 2);

    for (0..child_count) |child_index| {
        // Sequence and AlternateSet offsets are required, coverage-indexed
        // children. Zero would reinterpret the parent header as child data.
        const child = try table.offset.required16(
            view,
            subtable_offset,
            try readU16(view, child_offsets + child_index * 2),
        );
        const glyph_count = try readU16(view, child);
        try view.ensure(child + 2, @as(usize, glyph_count) * 2);
        for (0..glyph_count) |glyph_index| {
            try ensureGlyphWithinMaxp(
                view,
                try readU16(view, child + 2 + glyph_index * 2),
            );
        }
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
