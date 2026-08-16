//! PairPos parsing, PairSet lookup, and structural validation.

const std = @import("std");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const table = @import("../../table/root.zig");
const value_record = @import("../value_record.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub const Parsed = struct {
    subtable_offset: usize,
    pos_format: u16,
    coverage_offset: usize,
    value_format_1: u16,
    value_format_2: u16,
    value_size_1: usize,
    value_size_2: usize,
    class_def_1: usize = 0,
    class_def_2: usize = 0,
    class_1_count: u16 = 0,
    class_2_count: u16 = 0,
    matrix_offset: usize = 0,
};

pub fn parse(view: View, subtable_offset: usize) Error!Parsed {
    const pos_format = try view.readU16(subtable_offset);
    const value_format_1 = try view.readU16(subtable_offset + 4);
    const value_format_2 = try view.readU16(subtable_offset + 6);
    var parsed = Parsed{
        .subtable_offset = subtable_offset,
        .pos_format = pos_format,
        .coverage_offset = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .value_format_1 = value_format_1,
        .value_format_2 = value_format_2,
        .value_size_1 = try value_record.size(value_format_1),
        .value_size_2 = try value_record.size(value_format_2),
    };
    if (pos_format == 2) {
        parsed.class_def_1 = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 8),
        );
        parsed.class_def_2 = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 10),
        );
        parsed.class_1_count = try view.readU16(subtable_offset + 12);
        parsed.class_2_count = try view.readU16(subtable_offset + 14);
        parsed.matrix_offset = subtable_offset + 16;
    }
    return parsed;
}

pub fn validate(view: View, subtable_offset: usize) Error!void {
    const parsed = try parseForValidation(view, subtable_offset);
    try table.coverage.validate(view, parsed.coverage_offset, .indexed);
    switch (parsed.pos_format) {
        1 => {
            const pair_set_count =
                try readU16ForValidation(view, subtable_offset + 8);
            try table.coverage.validateIndices(
                view,
                parsed.coverage_offset,
                pair_set_count,
            );
            const offsets_pos = subtable_offset + 10;
            try view.ensure(offsets_pos, @as(usize, pair_set_count) * 2);
            for (0..pair_set_count) |pair_set_index| {
                const pair_set = try table.offset.required16(
                    view,
                    subtable_offset,
                    try readU16ForValidation(
                        view,
                        offsets_pos + pair_set_index * 2,
                    ),
                );
                const pair_count = try readU16ForValidation(view, pair_set);
                _ = try validatePairSet(
                    view,
                    pair_set,
                    pair_count,
                    parsed.value_format_1,
                    parsed.value_format_2,
                    parsed.value_size_1,
                    parsed.value_size_2,
                    null,
                );
            }
        },
        2 => {
            try table.class_def.validateWithLimit(
                view,
                parsed.class_def_1,
                parsed.class_1_count,
            );
            try table.class_def.validateWithLimit(
                view,
                parsed.class_def_2,
                parsed.class_2_count,
            );
            const record_size = parsed.value_size_1 + parsed.value_size_2;
            const record_count = try checkedMul(
                parsed.class_1_count,
                parsed.class_2_count,
            );
            try view.ensure(
                parsed.matrix_offset,
                try checkedMul(record_count, record_size),
            );
            if (value_record.hasDeviceOffsets(
                parsed.value_format_1,
            ) or value_record.hasDeviceOffsets(
                parsed.value_format_2,
            )) {
                for (0..record_count) |record_index| {
                    const record =
                        parsed.matrix_offset + record_index * record_size;
                    if (value_record.hasDeviceOffsets(
                        parsed.value_format_1,
                    )) {
                        try value_record.validate(
                            view,
                            record,
                            parsed.value_format_1,
                            subtable_offset,
                        );
                    }
                    if (value_record.hasDeviceOffsets(
                        parsed.value_format_2,
                    )) {
                        try value_record.validate(
                            view,
                            record + parsed.value_size_1,
                            parsed.value_format_2,
                            subtable_offset,
                        );
                    }
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

pub fn validatePairSet(
    view: View,
    pair_set_offset: usize,
    pair_count: u16,
    value_format_1: u16,
    value_format_2: u16,
    value_size_1: usize,
    value_size_2: usize,
    target_second_glyph: ?GlyphId,
) Error!?usize {
    const record_size = 2 + value_size_1 + value_size_2;
    try view.ensure(
        pair_set_offset + 2,
        try checkedMul(pair_count, record_size),
    );

    var previous: ?GlyphId = null;
    var matched: ?usize = null;
    for (0..pair_count) |pair_index| {
        const record = pair_set_offset + 2 + pair_index * record_size;
        const second = try readU16ForValidation(view, record);
        if (previous) |last| {
            if (second <= last) return error.BadGpos;
        }
        previous = second;
        if (view.glyph_count) |glyph_count| {
            if (second >= glyph_count) return error.BadGpos;
        }
        if (value_record.hasDeviceOffsets(value_format_1)) {
            try value_record.validate(
                view,
                record + 2,
                value_format_1,
                pair_set_offset,
            );
        }
        if (value_record.hasDeviceOffsets(value_format_2)) {
            try value_record.validate(
                view,
                record + 2 + value_size_1,
                value_format_2,
                pair_set_offset,
            );
        }
        if (target_second_glyph) |target| {
            if (second == target) matched = record;
        }
    }
    return matched;
}

/// Binary search after `validate` has proved strict SecondGlyph ordering.
pub fn findAfterProof(
    view: View,
    pair_set_offset: usize,
    pair_count: u16,
    value_size_1: usize,
    value_size_2: usize,
    target: GlyphId,
) Error!?usize {
    const record_size = 2 + value_size_1 + value_size_2;
    var low: usize = 0;
    var high: usize = pair_count;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const record = pair_set_offset + 2 + middle * record_size;
        const second = try view.readU16(record);
        if (target < second) {
            high = middle;
        } else if (target > second) {
            low = middle + 1;
        } else {
            return record;
        }
    }
    return null;
}

fn parseForValidation(view: View, subtable_offset: usize) Error!Parsed {
    return parse(view, subtable_offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

fn checkedMul(lhs: anytype, rhs: anytype) Error!usize {
    const a: usize = @intCast(lhs);
    const b: usize = @intCast(rhs);
    if (a != 0 and b > std.math.maxInt(usize) / a) return error.BadGpos;
    return a * b;
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
