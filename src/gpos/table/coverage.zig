//! OpenType Coverage grammar, lookup, and digest operations for GPOS.

const std = @import("std");
const GlyphDigest = @import("../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../glyph.zig").GlyphId;
const layout = @import("../../opentype/layout.zig");
const view = @import("view.zig");

pub const Error = view.Error || error{UnsupportedGpos};
pub const View = view.View;

pub const ValidationMode = enum {
    /// Coverage indexes select parallel positioning records. Format-1 glyphs
    /// must therefore be unique, and format-2 indexes must be dense.
    indexed,
    /// ContextPos/ChainContextPos format 3 use Coverage as membership sets.
    /// Production fonts contain duplicate format-1 glyphs in these sets, which
    /// are harmless because no parallel record is selected by CoverageIndex.
    membership,
};

pub fn validate(table: View, coverage_offset: usize, mode: ValidationMode) Error!void {
    const format = try readU16ForValidation(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16ForValidation(table, coverage_offset + 2);
            try table.ensure(coverage_offset + 4, @as(usize, glyph_count) * 2);
            try validateFormat1Order(table, coverage_offset, glyph_count, mode);
            for (0..glyph_count) |glyph_index| {
                try ensureGlyphWithinMaxp(
                    table,
                    try readU16ForValidation(
                        table,
                        coverage_offset + 4 + glyph_index * 2,
                    ),
                );
            }
        },
        2 => {
            const range_count = try readU16ForValidation(table, coverage_offset + 2);
            try table.ensure(coverage_offset + 4, @as(usize, range_count) * 6);
            try validateFormat2Ranges(table, coverage_offset, range_count);
            for (0..range_count) |range_index| {
                const range = coverage_offset + 4 + range_index * 6;
                try ensureGlyphWithinMaxp(
                    table,
                    try readU16ForValidation(table, range),
                );
                try ensureGlyphWithinMaxp(
                    table,
                    try readU16ForValidation(table, range + 2),
                );
            }
        },
        else => return error.UnsupportedGpos,
    }
}

/// Validate that every authored CoverageIndex selects an existing record in a
/// parallel subtable array. Callers first validate the Coverage grammar itself;
/// this operation only checks the consumer-specific target cardinality.
pub fn validateIndices(
    table: View,
    coverage_offset: usize,
    target_count: usize,
) Error!void {
    const format = try readU16ForValidation(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16ForValidation(table, coverage_offset + 2);
            if (@as(usize, glyph_count) > target_count) return error.BadGpos;
        },
        2 => {
            const range_count = try readU16ForValidation(table, coverage_offset + 2);
            for (0..range_count) |range_index| {
                const range = coverage_offset + 4 + range_index * 6;
                const start = try readU16ForValidation(table, range);
                const end = try readU16ForValidation(table, range + 2);
                if (end < start) return error.BadGpos;
                const start_index = try readU16ForValidation(table, range + 4);
                const span = @as(usize, end) - @as(usize, start) + 1;
                if (@as(usize, start_index) > target_count or
                    span > target_count - @as(usize, start_index))
                {
                    return error.BadGpos;
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

pub fn index(
    table: View,
    coverage_offset: usize,
    glyph: GlyphId,
) Error!?usize {
    const format = try table.readU16(coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try table.readU16(coverage_offset + 2);
            if (!table.assume_validated) {
                try validateFormat1Order(
                    table,
                    coverage_offset,
                    glyph_count,
                    .indexed,
                );
            }
            return findFormat1Glyph(table, coverage_offset, glyph_count, glyph);
        },
        2 => {
            const range_count = try table.readU16(coverage_offset + 2);
            if (!table.assume_validated) {
                try validateFormat2Ranges(table, coverage_offset, range_count);
            }
            const record = try rangeRecord(
                table,
                coverage_offset + 4,
                range_count,
                glyph,
            ) orelse return null;
            // Widen before adding: a range ending at glyph 0xffff can produce
            // CoverageIndex 65535 without wrapping a u16 intermediate.
            return @as(usize, record.value) +
                (@as(usize, glyph) - @as(usize, record.start));
        },
        else => return error.UnsupportedGpos,
    }
}

pub fn contains(
    table: View,
    coverage_offset: usize,
    glyph: GlyphId,
    mode: ValidationMode,
) Error!bool {
    const format = try table.readU16(coverage_offset);
    if (mode == .indexed or format != 1) {
        return (try index(table, coverage_offset, glyph)) != null;
    }

    const glyph_count = try table.readU16(coverage_offset + 2);
    if (!table.assume_validated) {
        try table.ensure(coverage_offset + 4, @as(usize, glyph_count) * 2);
        try validateFormat1Order(
            table,
            coverage_offset,
            glyph_count,
            .membership,
        );
    }
    return (try findFormat1Glyph(
        table,
        coverage_offset,
        glyph_count,
        glyph,
    )) != null;
}

pub fn glyphCount(table: View, coverage_offset: usize) Error!usize {
    return switch (try table.readU16(coverage_offset)) {
        1 => try table.readU16(coverage_offset + 2),
        2 => count: {
            const range_count = try table.readU16(coverage_offset + 2);
            var result: usize = 0;
            for (0..range_count) |range_index| {
                const range = coverage_offset + 4 + range_index * 6;
                const start = try table.readU16(range);
                const end = try table.readU16(range + 2);
                if (end < start) return error.BadGpos;
                const span = @as(usize, end) - @as(usize, start) + 1;
                if (span > std.math.maxInt(usize) - result) {
                    return error.BadGpos;
                }
                result += span;
            }
            break :count result;
        },
        else => error.UnsupportedGpos,
    };
}

pub fn glyphAt(
    table: View,
    coverage_offset: usize,
    target_index: usize,
) Error!?GlyphId {
    return switch (try table.readU16(coverage_offset)) {
        1 => glyph: {
            const glyph_count = try table.readU16(coverage_offset + 2);
            if (target_index >= glyph_count) break :glyph null;
            break :glyph try table.readU16(
                coverage_offset + 4 + target_index * 2,
            );
        },
        2 => glyph: {
            const range_count = try table.readU16(coverage_offset + 2);
            for (0..range_count) |range_index| {
                const range = coverage_offset + 4 + range_index * 6;
                const start = try table.readU16(range);
                const end = try table.readU16(range + 2);
                if (end < start) return error.BadGpos;
                const start_index = try table.readU16(range + 4);
                const span = @as(usize, end) - @as(usize, start) + 1;
                if (target_index < start_index or
                    target_index - @as(usize, start_index) >= span)
                {
                    continue;
                }
                break :glyph @intCast(
                    @as(usize, start) +
                        (target_index - @as(usize, start_index)),
                );
            }
            break :glyph null;
        },
        else => error.UnsupportedGpos,
    };
}

pub fn digest(table: View, coverage_offset: usize) Error!GlyphDigest {
    const format = try table.readU16(coverage_offset);
    var result = GlyphDigest.empty();
    switch (format) {
        1 => {
            const glyph_count = try table.readU16(coverage_offset + 2);
            if (!table.assume_validated) {
                try validateFormat1Order(
                    table,
                    coverage_offset,
                    glyph_count,
                    .indexed,
                );
            }
            for (0..glyph_count) |glyph_index| {
                result.add(
                    try table.readU16(
                        coverage_offset + 4 + glyph_index * 2,
                    ),
                );
            }
        },
        2 => {
            const range_count = try table.readU16(coverage_offset + 2);
            if (!table.assume_validated) {
                try validateFormat2Ranges(table, coverage_offset, range_count);
            }
            for (0..range_count) |range_index| {
                const range = coverage_offset + 4 + range_index * 6;
                result.addRange(
                    try table.readU16(range),
                    try table.readU16(range + 2),
                );
            }
        },
        else => return error.UnsupportedGpos,
    }
    return result;
}

pub fn validateFormat1Order(
    table: View,
    coverage_offset: usize,
    glyph_count: u16,
    mode: ValidationMode,
) Error!void {
    var previous: ?GlyphId = null;
    for (0..glyph_count) |glyph_index| {
        const glyph = try readU16ForValidation(
            table,
            coverage_offset + 4 + glyph_index * 2,
        );
        if (previous) |last| {
            if (glyph < last or (mode == .indexed and glyph == last)) {
                return error.BadGpos;
            }
        }
        previous = glyph;
    }
}

pub fn validateFormat2Ranges(
    table: View,
    coverage_offset: usize,
    range_count: u16,
) Error!void {
    var previous_end: ?GlyphId = null;
    var expected_start_index: usize = 0;
    for (0..range_count) |range_index| {
        const range = coverage_offset + 4 + range_index * 6;
        const start = try readU16ForValidation(table, range);
        const end = try readU16ForValidation(table, range + 2);
        const start_index = try readU16ForValidation(table, range + 4);
        if (end < start) return error.BadGpos;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadGpos;
        }
        if (expected_start_index > std.math.maxInt(u16) or
            start_index != expected_start_index)
        {
            return error.BadGpos;
        }
        previous_end = end;
        expected_start_index += @as(usize, end) - @as(usize, start) + 1;
    }
}

fn findFormat1Glyph(
    table: View,
    coverage_offset: usize,
    glyph_count: u16,
    glyph: GlyphId,
) Error!?usize {
    var low: usize = 0;
    var high: usize = glyph_count;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const candidate =
            try table.readU16(coverage_offset + 4 + middle * 2);
        if (glyph < candidate) {
            high = middle;
        } else if (glyph > candidate) {
            low = middle + 1;
        } else {
            return middle;
        }
    }
    return null;
}

fn rangeRecord(
    table: View,
    records_offset: usize,
    range_count: u16,
    glyph: GlyphId,
) Error!?layout.GlyphRangeRecord {
    const bytes = try table.bytes();
    return layout.findSortedGlyphRangeRecord(
        bytes,
        records_offset,
        range_count,
        glyph,
    ) catch error.EndOfStream;
}

fn ensureGlyphWithinMaxp(table: View, glyph: usize) Error!void {
    if (table.glyph_count) |glyph_count| {
        if (glyph >= glyph_count) return error.BadGpos;
    }
}

fn readU16ForValidation(table: View, relative: usize) Error!u16 {
    return table.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
