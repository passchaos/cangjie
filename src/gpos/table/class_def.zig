//! OpenType ClassDef grammar, bounds, and lookup operations for GPOS.

const GlyphId = @import("../../glyph.zig").GlyphId;
const layout = @import("../../opentype/layout.zig");
const view = @import("view.zig");

pub const Error = view.Error || error{UnsupportedGpos};
pub const View = view.View;

pub fn validate(table: View, class_def_offset: usize) Error!void {
    return validateWithLimit(table, class_def_offset, null);
}

/// Validate ClassDef structure and optionally constrain every explicit class to
/// a consumer's matrix/set cardinality. PairPos format 2 needs this stronger
/// contract because ClassDef values are used directly as matrix indexes.
pub fn validateWithLimit(
    table: View,
    class_def_offset: usize,
    max_class_count: ?u16,
) Error!void {
    const format = try readU16ForValidation(table, class_def_offset);
    switch (format) {
        1 => {
            const start = try readU16ForValidation(table, class_def_offset + 2);
            const count = try readU16ForValidation(table, class_def_offset + 4);
            try table.ensure(class_def_offset + 6, @as(usize, count) * 2);
            if (count != 0) {
                try ensureGlyphWithinMaxp(
                    table,
                    @as(usize, start) + @as(usize, count) - 1,
                );
            }
            if (max_class_count) |class_count| {
                for (0..count) |class_index| {
                    try ensureClassWithinLimit(
                        try readU16ForValidation(
                            table,
                            class_def_offset + 6 + class_index * 2,
                        ),
                        class_count,
                    );
                }
            }
        },
        2 => {
            const range_count =
                try readU16ForValidation(table, class_def_offset + 2);
            try table.ensure(
                class_def_offset + 4,
                @as(usize, range_count) * 6,
            );
            try validateFormat2Ranges(table, class_def_offset, range_count);
            for (0..range_count) |range_index| {
                const range = class_def_offset + 4 + range_index * 6;
                try ensureGlyphWithinMaxp(
                    table,
                    try readU16ForValidation(table, range),
                );
                try ensureGlyphWithinMaxp(
                    table,
                    try readU16ForValidation(table, range + 2),
                );
                if (max_class_count) |class_count| {
                    try ensureClassWithinLimit(
                        try readU16ForValidation(table, range + 4),
                        class_count,
                    );
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

pub fn value(
    table: View,
    class_def_offset: usize,
    glyph: GlyphId,
) Error!u16 {
    const format = try table.readU16(class_def_offset);
    switch (format) {
        1 => {
            const start = try table.readU16(class_def_offset + 2);
            const count = try table.readU16(class_def_offset + 4);
            // ClassDef format 1 is half-open. Widen the end calculation so a
            // definition spanning glyphs 0xfffe..0xffff cannot wrap u16.
            const glyph_index = @as(usize, glyph);
            const start_index = @as(usize, start);
            const end_exclusive = start_index + @as(usize, count);
            if (glyph_index < start_index or glyph_index >= end_exclusive) {
                return 0;
            }
            return try table.readU16(
                class_def_offset + 6 + (glyph_index - start_index) * 2,
            );
        },
        2 => {
            const range_count = try table.readU16(class_def_offset + 2);
            if (!table.assume_validated) {
                try validateFormat2Ranges(
                    table,
                    class_def_offset,
                    range_count,
                );
            }
            return if (try rangeRecord(
                table,
                class_def_offset + 4,
                range_count,
                glyph,
            )) |record|
                record.value
            else
                0;
        },
        else => return error.UnsupportedGpos,
    }
}

pub fn validateFormat2Ranges(
    table: View,
    class_def_offset: usize,
    range_count: u16,
) Error!void {
    var previous_end: ?GlyphId = null;
    for (0..range_count) |range_index| {
        const range = class_def_offset + 4 + range_index * 6;
        const start = try readU16ForValidation(table, range);
        const end = try readU16ForValidation(table, range + 2);
        if (end < start) return error.BadGpos;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadGpos;
        }
        previous_end = end;
    }
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

fn ensureClassWithinLimit(class_value: u16, class_count: u16) Error!void {
    if (class_value >= class_count) return error.BadGpos;
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
