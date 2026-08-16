//! SingleSubst grammar, coverage cardinality, and glyph-bound validation.

const GlyphId = @import("../../../glyph.zig").GlyphId;
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub fn validate(view: View, subtable_offset: usize) Error!void {
    const format = try readU16(view, subtable_offset);
    const coverage = try table.offset.required16(
        view,
        subtable_offset,
        try readU16(view, subtable_offset + 2),
    );
    switch (format) {
        // Format 1 uses modulo-16-bit results. Shaping validation permits an
        // intermediate ID outside maxp when a later lookup maps it back.
        1 => if (view.allow_transient_single_delta) {
            var transient_view = view;
            transient_view.glyph_count = null;
            try table.coverage.validate(transient_view, coverage, .indexed);
        } else {
            try table.coverage.validate(view, coverage, .indexed);
            try validateDeltaResults(
                view,
                coverage,
                try readI16(view, subtable_offset + 4),
            );
        },
        2 => {
            try table.coverage.validate(view, coverage, .indexed);
            const glyph_count = try readU16(view, subtable_offset + 4);
            try table.coverage.validateIndices(view, coverage, glyph_count);
            try view.ensure(
                subtable_offset + 6,
                @as(usize, glyph_count) * 2,
            );
            for (0..glyph_count) |glyph_index| {
                try ensureGlyphWithinMaxp(
                    view,
                    try readU16(
                        view,
                        subtable_offset + 6 + glyph_index * 2,
                    ),
                );
            }
        },
        else => return error.UnsupportedGsub,
    }
}

fn validateDeltaResults(
    view: View,
    coverage: usize,
    delta: i16,
) Error!void {
    switch (try readU16(view, coverage)) {
        1 => {
            const glyph_count = try readU16(view, coverage + 2);
            for (0..glyph_count) |glyph_index| {
                try ensureGlyphWithinMaxp(
                    view,
                    deltaResult(
                        try readU16(
                            view,
                            coverage + 4 + glyph_index * 2,
                        ),
                        delta,
                    ),
                );
            }
        },
        2 => {
            const range_count = try readU16(view, coverage + 2);
            for (0..range_count) |range_index| {
                const range = coverage + 4 + range_index * 6;
                const start = try readU16(view, range);
                const end = try readU16(view, range + 2);
                for (@as(usize, start)..@as(usize, end) + 1) |glyph| {
                    try ensureGlyphWithinMaxp(
                        view,
                        deltaResult(@intCast(glyph), delta),
                    );
                }
            }
        },
        else => return error.UnsupportedGsub,
    }
}

fn deltaResult(glyph: GlyphId, delta: i16) GlyphId {
    return @bitCast(@as(i16, @bitCast(glyph)) +% delta);
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

fn readI16(view: View, offset: usize) Error!i16 {
    return view.readI16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
