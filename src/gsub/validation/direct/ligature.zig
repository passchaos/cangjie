//! LigatureSubst required topology and glyph-bound validation.

const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Mode = enum {
    strict,
    shaping,
};
pub const View = table.View;

pub fn validate(
    view: View,
    subtable_offset: usize,
    mode: Mode,
) Error!void {
    if (try readU16(view, subtable_offset) != 1) {
        return error.UnsupportedGsub;
    }
    const coverage = try table.offset.required16(
        view,
        subtable_offset,
        try readU16(view, subtable_offset + 2),
    );
    try table.coverage.validate(view, coverage, .indexed);
    const set_count = try readU16(view, subtable_offset + 4);
    try table.coverage.validateIndices(view, coverage, set_count);
    const set_offsets = subtable_offset + 6;
    try view.ensure(set_offsets, @as(usize, set_count) * 2);

    for (0..set_count) |set_index| {
        const set_relative = try readU16(
            view,
            set_offsets + set_index * 2,
        );
        const set = table.offset.required16(
            view,
            subtable_offset,
            set_relative,
        ) catch |err| {
            if (mode == .shaping) continue;
            return err;
        };
        const ligature_count = try readU16(view, set);
        const ligature_offsets = set + 2;
        try view.ensure(
            ligature_offsets,
            @as(usize, ligature_count) * 2,
        );
        for (0..ligature_count) |ligature_index| {
            const ligature_relative = try readU16(
                view,
                ligature_offsets + ligature_index * 2,
            );
            const ligature = table.offset.required16(
                view,
                set,
                ligature_relative,
            ) catch |err| {
                if (mode == .shaping) continue;
                return err;
            };
            try ensureGlyphWithinMaxp(
                view,
                try readU16(view, ligature),
            );
            const component_count = try readU16(view, ligature + 2);
            if (component_count == 0) {
                if (mode == .shaping) continue;
                return error.BadGsub;
            }
            try view.ensure(
                ligature + 4,
                (@as(usize, component_count) - 1) * 2,
            );
            for (1..component_count) |component_index| {
                try ensureGlyphWithinMaxp(
                    view,
                    try readU16(
                        view,
                        ligature + 4 + (component_index - 1) * 2,
                    ),
                );
            }
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
