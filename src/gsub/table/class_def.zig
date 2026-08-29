//! OpenType ClassDef grammar and lookup for GSUB.

const std = @import("std");
const GlyphId = @import("../../glyph.zig").GlyphId;
const layout = @import("../../opentype/layout.zig");
const view = @import("view.zig");

pub const Error = view.Error || error{UnsupportedGsub};
pub const View = view.View;
pub const empty_offset = std.math.maxInt(usize);

pub fn validate(table: View, class_def_offset: usize) Error!void {
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
            }
        },
        else => return error.UnsupportedGsub,
    }
}

pub fn value(
    table: View,
    class_def_offset: usize,
    glyph: GlyphId,
) Error!u16 {
    // Optional ClassDef offsets are represented by this internal sentinel
    // after their nullable Offset16 has been resolved. OpenType assigns every
    // glyph to class zero when the optional table is absent.
    if (class_def_offset == empty_offset) return 0;
    const format = try table.readU16(class_def_offset);
    switch (format) {
        1 => {
            const start = try table.readU16(class_def_offset + 2);
            const count = try table.readU16(class_def_offset + 4);
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
        else => return error.UnsupportedGsub,
    }
}

pub inline fn valueWithDense(
    table: View,
    class_def_offset: usize,
    dense: []const u16,
    glyph: GlyphId,
) Error!u16 {
    if (dense.len != 0) {
        return if (glyph < dense.len) dense[glyph] else 0;
    }
    return value(table, class_def_offset, glyph);
}

/// Lookup after `validate` has already proved range ordering.
pub fn valueAfterProof(
    table: View,
    class_def_offset: usize,
    glyph: GlyphId,
) Error!u16 {
    var trusted = table;
    trusted.assume_validated = true;
    return value(trusted, class_def_offset, glyph);
}

pub fn valueForValidation(
    table: View,
    class_def_offset: usize,
    glyph: GlyphId,
) Error!u16 {
    return valueAfterProof(table, class_def_offset, glyph) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
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
        if (end < start) return error.BadGsub;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadGsub;
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

fn ensureGlyphWithinMaxp(table: View, glyph: usize) Error!void {
    if (table.glyph_count) |glyph_count| {
        if (glyph >= glyph_count) return error.BadGsub;
    }
}

fn readU16ForValidation(table: View, relative: usize) Error!u16 {
    return table.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
