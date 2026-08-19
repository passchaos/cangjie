//! MarkBasePos, MarkLigPos, and MarkMarkPos structural validation.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const anchor = @import("../anchor.zig");
const table = @import("../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;
pub const MarkToBase = accelerator.model.MarkToBaseSubtable;

pub const MarkToLigature = struct {
    subtable_offset: usize,
    mark_coverage_offset: usize,
    ligature_coverage_offset: usize,
    class_count: u16,
    mark_array_offset: usize,
    ligature_array_offset: usize,
};

pub const MarkToMark = accelerator.model.MarkToMarkSubtable;

pub fn parseMarkToBase(
    view: View,
    subtable_offset: usize,
) Error!MarkToBase {
    if (try view.readU16(subtable_offset) != 1) {
        return error.UnsupportedGpos;
    }
    return .{
        .mark_coverage_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .base_coverage_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 4),
        ),
        .class_count = try view.readU16(subtable_offset + 6),
        .mark_array_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 8),
        ),
        .base_array_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 10),
        ),
    };
}

pub fn validateMarkToBase(view: View, subtable_offset: usize) Error!void {
    const parsed = try parseMarkToBaseForValidation(view, subtable_offset);
    try table.coverage.validate(view, parsed.mark_coverage_offset, .indexed);
    try table.coverage.validate(view, parsed.base_coverage_offset, .indexed);
    const mark_count = try validateMarkArray(
        view,
        parsed.mark_array_offset,
        parsed.class_count,
    );
    const base_count = try validateBaseArray(
        view,
        parsed.base_array_offset,
        parsed.class_count,
    );
    try table.coverage.validateIndices(
        view,
        parsed.mark_coverage_offset,
        mark_count,
    );
    try table.coverage.validateIndices(
        view,
        parsed.base_coverage_offset,
        base_count,
    );
}

pub fn validateMarkToLigature(
    view: View,
    subtable_offset: usize,
) Error!void {
    const parsed = try parseMarkToLigatureForValidation(
        view,
        subtable_offset,
    );
    try table.coverage.validate(view, parsed.mark_coverage_offset, .indexed);
    try table.coverage.validate(
        view,
        parsed.ligature_coverage_offset,
        .indexed,
    );
    const mark_count = try validateMarkArray(
        view,
        parsed.mark_array_offset,
        parsed.class_count,
    );
    const ligature_count = try validateLigatureArray(
        view,
        parsed.ligature_array_offset,
        parsed.class_count,
    );
    try table.coverage.validateIndices(
        view,
        parsed.mark_coverage_offset,
        mark_count,
    );
    try table.coverage.validateIndices(
        view,
        parsed.ligature_coverage_offset,
        ligature_count,
    );
}

pub fn parseMarkToLigature(
    view: View,
    subtable_offset: usize,
) Error!MarkToLigature {
    if (try view.readU16(subtable_offset) != 1) {
        return error.UnsupportedGpos;
    }
    return .{
        .subtable_offset = subtable_offset,
        .mark_coverage_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .ligature_coverage_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 4),
        ),
        .class_count = try view.readU16(subtable_offset + 6),
        .mark_array_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 8),
        ),
        .ligature_array_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 10),
        ),
    };
}

pub fn validateMarkToMark(view: View, subtable_offset: usize) Error!void {
    const parsed = try parseMarkToMarkForValidation(view, subtable_offset);
    try table.coverage.validate(view, parsed.mark_1_coverage_offset, .indexed);
    try table.coverage.validate(view, parsed.mark_2_coverage_offset, .indexed);
    const mark_1_count = try validateMarkArray(
        view,
        parsed.mark_1_array_offset,
        parsed.class_count,
    );
    const mark_2_count = try validateMark2Array(
        view,
        parsed.mark_2_array_offset,
        parsed.class_count,
    );
    try table.coverage.validateIndices(
        view,
        parsed.mark_1_coverage_offset,
        mark_1_count,
    );
    try table.coverage.validateIndices(
        view,
        parsed.mark_2_coverage_offset,
        mark_2_count,
    );
}

pub fn parseMarkToMark(
    view: View,
    subtable_offset: usize,
) Error!MarkToMark {
    if (try view.readU16(subtable_offset) != 1) {
        return error.UnsupportedGpos;
    }
    return .{
        .subtable_offset = subtable_offset,
        .mark_1_coverage_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .mark_2_coverage_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 4),
        ),
        .class_count = try view.readU16(subtable_offset + 6),
        .mark_1_array_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 8),
        ),
        .mark_2_array_offset = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 10),
        ),
    };
}

fn validateMarkArray(
    view: View,
    array_offset: usize,
    class_count: u16,
) Error!usize {
    const mark_count = try readU16ForValidation(view, array_offset);
    try view.ensure(array_offset + 2, @as(usize, mark_count) * 4);
    for (0..mark_count) |mark_index| {
        const record = array_offset + 2 + mark_index * 4;
        if (try readU16ForValidation(view, record) >= class_count) {
            return error.BadGpos;
        }
        // MarkRecord.Anchor is mandatory; zero would alias MarkArray metadata.
        const relative = try readU16ForValidation(view, record + 2);
        try anchor.validate(
            view,
            try requiredOffset(view, array_offset, relative),
        );
    }
    return mark_count;
}

fn validateBaseArray(
    view: View,
    array_offset: usize,
    class_count: u16,
) Error!usize {
    const base_count = try readU16ForValidation(view, array_offset);
    try validateOptionalAnchorGrid(
        view,
        array_offset,
        array_offset + 2,
        try checkedMul(base_count, class_count),
    );
    return base_count;
}

fn validateLigatureArray(
    view: View,
    array_offset: usize,
    class_count: u16,
) Error!usize {
    const ligature_count = try readU16ForValidation(view, array_offset);
    try view.ensure(
        array_offset + 2,
        @as(usize, ligature_count) * 2,
    );
    for (0..ligature_count) |ligature_index| {
        const attach = try requiredOffset(
            view,
            array_offset,
            try readU16ForValidation(
                view,
                array_offset + 2 + ligature_index * 2,
            ),
        );
        const component_count = try readU16ForValidation(view, attach);
        try validateOptionalAnchorGrid(
            view,
            attach,
            attach + 2,
            try checkedMul(component_count, class_count),
        );
    }
    return ligature_count;
}

fn validateMark2Array(
    view: View,
    array_offset: usize,
    class_count: u16,
) Error!usize {
    const mark_count = try readU16ForValidation(view, array_offset);
    try validateOptionalAnchorGrid(
        view,
        array_offset,
        array_offset + 2,
        try checkedMul(mark_count, class_count),
    );
    return mark_count;
}

fn validateOptionalAnchorGrid(
    view: View,
    base_offset: usize,
    offsets_pos: usize,
    count: usize,
) Error!void {
    try view.ensure(offsets_pos, count * 2);
    for (0..count) |anchor_index| {
        const relative =
            try readU16ForValidation(view, offsets_pos + anchor_index * 2);
        if (relative == 0) continue;
        try anchor.validate(
            view,
            try requiredOffset(view, base_offset, relative),
        );
    }
}

fn parseMarkToBaseForValidation(
    view: View,
    subtable_offset: usize,
) Error!MarkToBase {
    return parseMarkToBase(view, subtable_offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

fn parseMarkToLigatureForValidation(
    view: View,
    subtable_offset: usize,
) Error!MarkToLigature {
    return parseMarkToLigature(view, subtable_offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

fn parseMarkToMarkForValidation(
    view: View,
    subtable_offset: usize,
) Error!MarkToMark {
    return parseMarkToMark(view, subtable_offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

fn requiredOffset(view: View, base: usize, relative: u16) Error!usize {
    return table.offset.required16(view, base, relative);
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
