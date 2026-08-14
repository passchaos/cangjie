const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gsub = @import("gsub.zig");
const insertion = @import("aat_morx/insertion.zig");
const rearrangement = @import("aat_morx/rearrangement.zig");
const state_table = @import("aat_morx/state_table.zig");

pub const Error = error{ BadSfnt, InvalidShapingInput } || std.mem.Allocator.Error || error{EndOfStream};

const insertion_set_mark: u16 = 0x8000;
const insertion_current_before: u16 = 0x0800;
const insertion_marked_before: u16 = 0x0400;
const insertion_current_count: u16 = 0x03e0;
const insertion_marked_count: u16 = 0x001f;
const no_insertion: u16 = 0xffff;

pub fn validate(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
) Error!void {
    if (table_offset > data.len or table_length > data.len - table_offset or table_length < 8) return error.BadSfnt;
    if (try readU32(data, table_offset) != 0x0001_0000) return error.BadSfnt;
    const chain_count: usize = @intCast(try readU32(data, table_offset + 4));
    var chain_relative: usize = 8;
    for (0..chain_count) |_| {
        if (chain_relative > table_length or table_length - chain_relative < 12) return error.BadSfnt;
        const chain_start = table_offset + chain_relative;
        const chain_length: usize = @intCast(try readU32(data, chain_start + 4));
        const feature_count: usize = try readU16(data, chain_start + 8);
        const subtable_count: usize = try readU16(data, chain_start + 10);
        if (chain_length < 12 or chain_length > table_length - chain_relative) return error.BadSfnt;
        const feature_bytes = std.math.mul(usize, feature_count, 12) catch return error.BadSfnt;
        if (feature_bytes > chain_length - 12) return error.BadSfnt;

        var subtable_relative = chain_relative + 12 + feature_bytes;
        const chain_end = chain_relative + chain_length;
        for (0..subtable_count) |_| {
            if (subtable_relative > chain_end or chain_end - subtable_relative < 8) return error.BadSfnt;
            const subtable_start = table_offset + subtable_relative;
            const subtable_length: usize = try readU16(data, subtable_start);
            const format: u8 = @intCast((try readU16(data, subtable_start + 2)) & 0xff);
            if (subtable_length < 8 or subtable_length > chain_end - subtable_relative) return error.BadSfnt;
            switch (format) {
                0 => try validateRearrangement(
                    data,
                    subtable_start + 8,
                    subtable_length - 8,
                ),
                1 => try validateContextual(
                    data,
                    subtable_start + 8,
                    subtable_length - 8,
                    glyph_count,
                ),
                5 => try validateInsertion(
                    data,
                    subtable_start + 8,
                    subtable_length - 8,
                    glyph_count,
                ),
                4 => try state_table.validateLookupU16(
                    data,
                    subtable_start + 8,
                    subtable_length - 8,
                    glyph_count,
                ),
                2 => {},
                else => return error.BadSfnt,
            }
            subtable_relative += subtable_length;
        }
        if (subtable_relative > chain_end) return error.BadSfnt;
        chain_relative += chain_length;
    }
    if (chain_relative > table_length) return error.BadSfnt;
}

fn validateInsertion(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    if (length < 10) return error.BadSfnt;
    const class_count: usize = try readU16(data, offset);
    const class_table_offset: usize = try readU16(data, offset + 2);
    const state_array_offset: usize = try readU16(data, offset + 4);
    const entry_table_offset: usize = try readU16(data, offset + 6);
    const insertion_offset: usize = try readU16(data, offset + 8);
    if (class_count < 4 or
        class_table_offset < 10 or
        state_array_offset < 10 or
        entry_table_offset < 10 or
        insertion_offset < 10 or
        class_table_offset >= length or
        state_array_offset >= entry_table_offset or
        entry_table_offset >= length or
        insertion_offset > length)
    {
        return error.BadSfnt;
    }
    const class_glyph_count: usize = try readU16(data, offset + class_table_offset + 2);
    if (class_glyph_count > length - class_table_offset - 4) return error.BadSfnt;
    if ((entry_table_offset - state_array_offset) % class_count != 0) return error.BadSfnt;
    for (data[offset + state_array_offset .. offset + entry_table_offset]) |entry_index| {
        const entry_relative = std.math.add(usize, entry_table_offset, @as(usize, entry_index) * 8) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 8) return error.BadSfnt;
        const new_state_offset: usize = try readU16(data, offset + entry_relative);
        const flags = try readU16(data, offset + entry_relative + 2);
        const current_index: usize = try readU16(data, offset + entry_relative + 4);
        const marked_index: usize = try readU16(data, offset + entry_relative + 6);
        if (new_state_offset < state_array_offset or new_state_offset >= entry_table_offset) return error.BadSfnt;
        if ((new_state_offset - state_array_offset) % class_count != 0) return error.BadSfnt;
        try validateInsertionList(data, offset, length, insertion_offset, current_index, (flags & insertion_current_count) >> 5, glyph_count);
        try validateInsertionList(data, offset, length, insertion_offset, marked_index, flags & insertion_marked_count, glyph_count);
    }
}

fn validateInsertionList(
    data: []const u8,
    offset: usize,
    length: usize,
    insertion_offset: usize,
    list_index: usize,
    count: usize,
    glyph_count: usize,
) Error!void {
    if (list_index == no_insertion or count == 0) return;
    // Unlike the insertionOffset header field, an entry stores a zero-based
    // glyph index into the insertion table. In particular, zero selects the
    // first action and 0xFFFF—not zero—is the no-action sentinel.
    const index_bytes = std.math.mul(usize, list_index, 2) catch return error.BadSfnt;
    const list_offset = std.math.add(usize, insertion_offset, index_bytes) catch return error.BadSfnt;
    const bytes = std.math.mul(usize, count, 2) catch return error.BadSfnt;
    if (list_offset > length or bytes > length - list_offset) return error.BadSfnt;
    for (0..count) |index| {
        if (try readU16(data, offset + list_offset + index * 2) >= glyph_count) return error.BadSfnt;
    }
}

fn validateRearrangement(data: []const u8, offset: usize, length: usize) Error!void {
    if (length < 8) return error.BadSfnt;
    const class_count: usize = try readU16(data, offset);
    const class_table_offset: usize = try readU16(data, offset + 2);
    const state_array_offset: usize = try readU16(data, offset + 4);
    const entry_table_offset: usize = try readU16(data, offset + 6);
    if (class_count < 4 or
        class_table_offset < 8 or
        state_array_offset < 8 or
        entry_table_offset < 8 or
        class_table_offset >= length or
        state_array_offset >= entry_table_offset or
        entry_table_offset >= length)
    {
        return error.BadSfnt;
    }
    const glyph_count: usize = try readU16(data, offset + class_table_offset + 2);
    if (glyph_count > length - class_table_offset - 4) return error.BadSfnt;
    const state_bytes = entry_table_offset - state_array_offset;
    if (state_bytes % class_count != 0) return error.BadSfnt;
    for (data[offset + state_array_offset .. offset + entry_table_offset]) |entry_index| {
        const entry_relative = std.math.add(usize, entry_table_offset, @as(usize, entry_index) * 4) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 4) return error.BadSfnt;
        const new_state_offset: usize = try readU16(data, offset + entry_relative);
        const flags = try readU16(data, offset + entry_relative + 2);
        if (new_state_offset < state_array_offset or new_state_offset >= entry_table_offset) return error.BadSfnt;
        if ((new_state_offset - state_array_offset) % class_count != 0 or (flags & 0x1ff0) != 0) return error.BadSfnt;
    }
}

fn validateContextual(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    if (length < 10) return error.BadSfnt;
    const class_count: usize = try readU16(data, offset);
    const class_table_offset: usize = try readU16(data, offset + 2);
    const state_array_offset: usize = try readU16(data, offset + 4);
    const entry_table_offset: usize = try readU16(data, offset + 6);
    const substitution_offset: usize = try readU16(data, offset + 8);
    if (class_count < 4 or
        class_table_offset < 10 or
        state_array_offset < 10 or
        entry_table_offset < 10 or
        substitution_offset < 10 or
        class_table_offset >= length or
        state_array_offset >= entry_table_offset or
        entry_table_offset >= length or
        substitution_offset > length)
    {
        return error.BadSfnt;
    }
    const class_glyph_count: usize = try readU16(data, offset + class_table_offset + 2);
    if (class_glyph_count > length - class_table_offset - 4) return error.BadSfnt;
    if ((entry_table_offset - state_array_offset) % class_count != 0) return error.BadSfnt;

    for (data[offset + state_array_offset .. offset + entry_table_offset]) |entry_index| {
        const entry_relative = std.math.add(usize, entry_table_offset, @as(usize, entry_index) * 8) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 8) return error.BadSfnt;
        const new_state_offset: usize = try readU16(data, offset + entry_relative);
        const flags = try readU16(data, offset + entry_relative + 2);
        const mark_offset: i16 = try readI16(data, offset + entry_relative + 4);
        const current_offset: i16 = try readI16(data, offset + entry_relative + 6);
        if (new_state_offset < state_array_offset or new_state_offset >= entry_table_offset) return error.BadSfnt;
        if ((new_state_offset - state_array_offset) % class_count != 0 or (flags & 0x3fff) != 0) return error.BadSfnt;
        try validateContextualOffset(data, offset, length, substitution_offset, mark_offset, glyph_count);
        try validateContextualOffset(data, offset, length, substitution_offset, current_offset, glyph_count);
    }
}

fn validateContextualOffset(
    data: []const u8,
    offset: usize,
    length: usize,
    substitution_offset: usize,
    action_offset: i16,
    glyph_count: usize,
) Error!void {
    if (action_offset == 0) return;
    for (0..glyph_count) |glyph| {
        const word_index = @as(i64, action_offset) + @as(i64, @intCast(glyph));
        if (word_index < 0) return error.BadSfnt;
        const relative_i64 = std.math.mul(i64, word_index, 2) catch return error.BadSfnt;
        if (relative_i64 < 0) return error.BadSfnt;
        const relative: usize = @intCast(relative_i64);
        if (relative < substitution_offset or relative > length or length - relative < 2) return error.BadSfnt;
        const replacement = try readU16(data, offset + relative);
        if (replacement >= glyph_count and replacement != 0) return error.BadSfnt;
    }
}

/// Apply the supported subset of the legacy AAT `mort` table.
///
/// `mort` predates `morx`: chain and subtable lengths/counts are 16-bit and
/// coverage is an 8-bit flag byte packed above the subtable type. The deployed
/// Types 0, 1, 4, and 5 have dedicated obsolete-layout executors. Type 2
/// remains intentionally inert: its offsets differ from modern `morx`, so
/// accepting its structure without executing it is preferable to accidentally
/// applying the incompatible modern ligature machine.
pub fn apply(
    allocator: std.mem.Allocator,
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    try validateParallelMetadata(glyphs.items.len, options);
    try validate(data, table_offset, table_length, glyph_count);
    const chain_count: usize = @intCast(try readU32(data, table_offset + 4));

    var chain_relative: usize = 8;
    for (0..chain_count) |_| {
        if (chain_relative > table_length or table_length - chain_relative < 12) return error.BadSfnt;
        const chain_start = table_offset + chain_relative;
        const default_flags = try readU32(data, chain_start);
        const chain_length: usize = @intCast(try readU32(data, chain_start + 4));
        const feature_count: usize = try readU16(data, chain_start + 8);
        const subtable_count: usize = try readU16(data, chain_start + 10);
        if (chain_length < 12 or chain_length > table_length - chain_relative) return error.BadSfnt;
        const feature_bytes = std.math.mul(usize, feature_count, 12) catch return error.BadSfnt;
        if (feature_bytes > chain_length - 12) return error.BadSfnt;

        // The full AAT feature map will eventually fold caller-selected feature
        // types/settings. For the initial production path, chain default flags
        // are authoritative; Honoka's vertical substitution is enabled by
        // default and feature records only describe optional overrides.
        const flags = default_flags;
        var subtable_relative = chain_relative + 12 + feature_bytes;
        const chain_end = chain_relative + chain_length;
        for (0..subtable_count) |_| {
            if (subtable_relative > chain_end or chain_end - subtable_relative < 8) return error.BadSfnt;
            const subtable_start = table_offset + subtable_relative;
            const subtable_length: usize = try readU16(data, subtable_start);
            const coverage = try readU16(data, subtable_start + 2);
            const sub_feature_flags = try readU32(data, subtable_start + 4);
            if (subtable_length < 8 or subtable_length > chain_end - subtable_relative) return error.BadSfnt;

            if ((flags & sub_feature_flags) != 0) {
                const coverage_flags: u8 = @intCast(coverage >> 8);
                const vertical = (coverage_flags & 0x80) != 0;
                const all_directions = (coverage_flags & 0x20) != 0;
                if (all_directions or vertical == options.vertical) {
                    switch (@as(u8, @intCast(coverage & 0xff))) {
                        0 => try applyRearrangement(
                            data,
                            subtable_start + 8,
                            subtable_length - 8,
                            glyphs,
                            options,
                        ),
                        1 => try applyContextual(
                            data,
                            subtable_start + 8,
                            subtable_length - 8,
                            glyph_count,
                            glyphs,
                            options,
                        ),
                        5 => try applyInsertion(
                            allocator,
                            data,
                            subtable_start + 8,
                            subtable_length - 8,
                            glyph_count,
                            glyphs,
                            options,
                        ),
                        4 => try applyNoncontextual(
                            data,
                            subtable_start + 8,
                            subtable_length - 8,
                            glyph_count,
                            glyphs,
                            options,
                        ),
                        // The obsolete ligature format has different offset
                        // bases from its morx successor. Keep it inert until
                        // its executor has dedicated reference fixtures.
                        2 => {},
                        else => return error.BadSfnt,
                    }
                }
            }
            subtable_relative += subtable_length;
        }
        if (subtable_relative > chain_end) return error.BadSfnt;
        chain_relative += chain_length;
    }
    if (chain_relative > table_length) return error.BadSfnt;
}

fn applyInsertion(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    const class_count: usize = try readU16(data, offset);
    const class_table_offset: usize = try readU16(data, offset + 2);
    const state_array_offset: usize = try readU16(data, offset + 4);
    const entry_table_offset: usize = try readU16(data, offset + 6);
    const insertion_offset: usize = try readU16(data, offset + 8);
    const class_first: usize = try readU16(data, offset + class_table_offset);
    const class_glyph_count: usize = try readU16(data, offset + class_table_offset + 2);

    var run = try insertion.WorkingRun.init(allocator, glyphs, options);
    defer run.deinit(allocator);
    var operations_left = try state_table.operationBudget(glyphs.items.len);
    var state_offset = state_array_offset;
    var cursor: usize = 0;
    var mark: usize = 0;
    while (true) {
        if (operations_left == 0) return error.BadSfnt;
        operations_left -= 1;
        const class: usize = if (cursor >= run.glyphs.items.len)
            state_table.class_end_of_text
        else class: {
            const glyph: usize = run.glyphs.items[cursor];
            if (glyph < class_first or glyph >= class_first + class_glyph_count) break :class state_table.class_out_of_bounds;
            break :class data[offset + class_table_offset + 4 + glyph - class_first];
        };
        const bounded_class = if (class < class_count) class else state_table.class_out_of_bounds;
        const state_cell = std.math.add(usize, state_offset, bounded_class) catch return error.BadSfnt;
        if (state_cell >= length) return error.BadSfnt;
        const entry_relative = std.math.add(usize, entry_table_offset, @as(usize, data[offset + state_cell]) * 8) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 8) return error.BadSfnt;
        const new_state_offset: usize = try readU16(data, offset + entry_relative);
        const flags = try readU16(data, offset + entry_relative + 2);
        const current_index: usize = try readU16(data, offset + entry_relative + 4);
        const marked_index: usize = try readU16(data, offset + entry_relative + 6);
        const mark_location = cursor;

        const marked_count: usize = flags & insertion_marked_count;
        if (marked_index != no_insertion and marked_count != 0) {
            const count = marked_count;
            if (count >= operations_left) return error.BadSfnt;
            operations_left -= count;
            const end = cursor;
            if (mark > run.glyphs.items.len) return error.BadSfnt;
            cursor = mark;
            const before = (flags & insertion_marked_before) != 0;
            if (cursor < run.glyphs.items.len and !before) try run.copyCurrent(allocator, &cursor);
            try outputMortInsertion(allocator, data, offset, length, insertion_offset, marked_index, count, glyph_count, &run, &cursor);
            if (cursor < run.glyphs.items.len and !before) run.skipCurrent(cursor);
            cursor = std.math.add(usize, end, count) catch return error.BadSfnt;
            if (cursor > run.glyphs.items.len) return error.BadSfnt;
        }
        if ((flags & insertion_set_mark) != 0) mark = mark_location;
        const current_count: usize = (flags & insertion_current_count) >> 5;
        if (current_index != no_insertion and current_count != 0) {
            const count = current_count;
            if (count >= operations_left) return error.BadSfnt;
            operations_left -= count;
            const end = cursor;
            const before = (flags & insertion_current_before) != 0;
            if (cursor < run.glyphs.items.len and !before) try run.copyCurrent(allocator, &cursor);
            try outputMortInsertion(allocator, data, offset, length, insertion_offset, current_index, count, glyph_count, &run, &cursor);
            if (cursor < run.glyphs.items.len and !before) run.skipCurrent(cursor);
            cursor = if ((flags & state_table.dont_advance) != 0) end else std.math.add(usize, end, count) catch return error.BadSfnt;
            if (cursor > run.glyphs.items.len) return error.BadSfnt;
        }
        state_offset = new_state_offset;
        if (cursor >= run.glyphs.items.len) break;
        if ((flags & state_table.dont_advance) == 0) cursor += 1;
    }
    try run.commit(allocator, glyphs, options);
}

fn outputMortInsertion(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    insertion_offset: usize,
    list_index: usize,
    count: usize,
    glyph_count: usize,
    run: *insertion.WorkingRun,
    cursor: *usize,
) Error!void {
    const index_bytes = std.math.mul(usize, list_index, 2) catch return error.BadSfnt;
    const list_offset = std.math.add(usize, insertion_offset, index_bytes) catch return error.BadSfnt;
    const byte_count = std.math.mul(usize, count, 2) catch return error.BadSfnt;
    if (list_offset > length or byte_count > length - list_offset) return error.BadSfnt;
    for (0..count) |index| {
        const glyph = try readU16(data, offset + list_offset + index * 2);
        if (glyph >= glyph_count) return error.BadSfnt;
        try run.outputGlyph(allocator, cursor, glyph);
    }
}

fn applyContextual(
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    const class_count: usize = try readU16(data, offset);
    const class_table_offset: usize = try readU16(data, offset + 2);
    const state_array_offset: usize = try readU16(data, offset + 4);
    const entry_table_offset: usize = try readU16(data, offset + 6);
    const substitution_offset: usize = try readU16(data, offset + 8);
    const class_first: usize = try readU16(data, offset + class_table_offset);
    const class_glyph_count: usize = try readU16(data, offset + class_table_offset + 2);

    var operations_left = try state_table.operationBudget(glyphs.items.len);
    var state_offset = state_array_offset;
    var index: usize = 0;
    var mark: usize = 0;
    var mark_set = false;
    while (true) {
        if (operations_left == 0) return error.BadSfnt;
        operations_left -= 1;
        const class: usize = if (index >= glyphs.items.len)
            state_table.class_end_of_text
        else class: {
            const glyph: usize = glyphs.items[index];
            if (glyph < class_first or glyph >= class_first + class_glyph_count) {
                break :class state_table.class_out_of_bounds;
            }
            break :class data[offset + class_table_offset + 4 + glyph - class_first];
        };
        const bounded_class = if (class < class_count) class else state_table.class_out_of_bounds;
        const state_cell = std.math.add(usize, state_offset, bounded_class) catch return error.BadSfnt;
        if (state_cell >= length) return error.BadSfnt;
        const entry_index: usize = data[offset + state_cell];
        const entry_relative = std.math.add(usize, entry_table_offset, entry_index * 8) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 8) return error.BadSfnt;
        const new_state_offset: usize = try readU16(data, offset + entry_relative);
        const flags = try readU16(data, offset + entry_relative + 2);
        const mark_offset = try readI16(data, offset + entry_relative + 4);
        const current_offset = try readI16(data, offset + entry_relative + 6);

        if (index < glyphs.items.len or mark_set) {
            try replaceContextualGlyph(
                data,
                offset,
                length,
                substitution_offset,
                mark_offset,
                glyph_count,
                glyphs,
                options,
                mark,
            );
            if (glyphs.items.len != 0) {
                try replaceContextualGlyph(
                    data,
                    offset,
                    length,
                    substitution_offset,
                    current_offset,
                    glyph_count,
                    glyphs,
                    options,
                    @min(index, glyphs.items.len - 1),
                );
            }
        }
        if ((flags & 0x8000) != 0) {
            mark_set = index < glyphs.items.len;
            mark = index;
        }
        state_offset = new_state_offset;
        if (index >= glyphs.items.len) break;
        if ((flags & state_table.dont_advance) == 0) index += 1;
    }
}

fn replaceContextualGlyph(
    data: []const u8,
    offset: usize,
    length: usize,
    substitution_offset: usize,
    action_offset: i16,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    glyph_index: usize,
) Error!void {
    if (action_offset == 0 or glyph_index >= glyphs.items.len) return;
    const word_index = @as(i64, action_offset) + glyphs.items[glyph_index];
    if (word_index < 0) return error.BadSfnt;
    const relative_i64 = word_index * 2;
    if (relative_i64 < 0) return error.BadSfnt;
    const relative: usize = @intCast(relative_i64);
    if (relative < substitution_offset or relative > length or length - relative < 2) return error.BadSfnt;
    const replacement = try readU16(data, offset + relative);
    // Obsolete contextual tables use zero as "no substitution".
    if (replacement == 0) return;
    if (replacement >= glyph_count) return error.BadSfnt;
    glyphs.items[glyph_index] = replacement;
    if (options.glyph_substituted) |values| values.items[glyph_index] = true;
    if (options.glyph_stage_substituted) |values| values.items[glyph_index] = true;
}

fn applyRearrangement(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    if (length < 8) return error.BadSfnt;
    const class_count: usize = try readU16(data, offset);
    const class_table_offset: usize = try readU16(data, offset + 2);
    const state_array_offset: usize = try readU16(data, offset + 4);
    const entry_table_offset: usize = try readU16(data, offset + 6);
    if (class_count < 4 or
        class_table_offset < 8 or
        state_array_offset < 8 or
        entry_table_offset < 8 or
        class_table_offset >= length or
        state_array_offset >= length or
        entry_table_offset >= length or
        state_array_offset >= entry_table_offset)
    {
        return error.BadSfnt;
    }

    const class_first: usize = try readU16(data, offset + class_table_offset);
    const class_count_glyphs: usize = try readU16(data, offset + class_table_offset + 2);
    if (class_count_glyphs > length - class_table_offset - 4) return error.BadSfnt;

    var operations_left = try state_table.operationBudget(glyphs.items.len);
    var state_offset = state_array_offset;
    var index: usize = 0;
    var start: usize = 0;
    var end: usize = 0;
    while (true) {
        if (operations_left == 0) return error.BadSfnt;
        operations_left -= 1;
        const class: usize = if (index >= glyphs.items.len)
            state_table.class_end_of_text
        else class: {
            const glyph: usize = glyphs.items[index];
            if (glyph < class_first or glyph >= class_first + class_count_glyphs) {
                break :class state_table.class_out_of_bounds;
            }
            break :class data[offset + class_table_offset + 4 + glyph - class_first];
        };
        const bounded_class = if (class < class_count) class else state_table.class_out_of_bounds;
        const state_cell = std.math.add(usize, state_offset, bounded_class) catch return error.BadSfnt;
        if (state_cell >= length) return error.BadSfnt;
        const entry_index: usize = data[offset + state_cell];
        const entry_relative = std.math.add(usize, entry_table_offset, entry_index * 4) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 4) return error.BadSfnt;
        const new_state_offset: usize = try readU16(data, offset + entry_relative);
        const flags = try readU16(data, offset + entry_relative + 2);
        if (new_state_offset < state_array_offset or new_state_offset >= entry_table_offset) return error.BadSfnt;
        if ((new_state_offset - state_array_offset) % class_count != 0) return error.BadSfnt;
        if ((flags & 0x1ff0) != 0) return error.BadSfnt;

        if ((flags & 0x8000) != 0) start = index;
        if ((flags & 0x2000) != 0) end = @min(index + 1, glyphs.items.len);
        const verb = flags & 0x000f;
        if (verb != 0 and start < end) {
            rearrangement.applyVerb(
                glyphs,
                options,
                start,
                end,
                @min(index + 1, glyphs.items.len),
                verb,
            );
        }

        state_offset = new_state_offset;
        if (index >= glyphs.items.len) break;
        if ((flags & state_table.dont_advance) == 0) index += 1;
    }
}

fn applyNoncontextual(
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    if (length < 2) return error.BadSfnt;
    try state_table.validateLookupU16(data, offset, length, glyph_count);
    for (glyphs.items, 0..) |*glyph, index| {
        const replacement = (try state_table.lookupGlyphValueBounded(
            data,
            offset,
            length,
            glyph.*,
            glyph_count,
        )) orelse continue;
        if (replacement >= glyph_count) return error.BadSfnt;
        glyph.* = replacement;
        if (options.glyph_substituted) |substituted| substituted.items[index] = true;
        if (options.glyph_stage_substituted) |substituted| substituted.items[index] = true;
    }
}

fn validateParallelMetadata(glyph_count: usize, options: gsub.LookupOptions) Error!void {
    if (options.glyph_source_indices) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.glyph_cluster_indices) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.glyph_substituted) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.glyph_stage_substituted) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.ligature_components) |store| {
        if (store.infos.items.len != glyph_count or !store.isValid()) return error.InvalidShapingInput;
    }
}

fn readU16(data: []const u8, offset: usize) Error!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) Error!i16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 4) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

test "legacy mort noncontextual substitutions update glyph metadata" {
    var bytes = [_]u8{0} ** 42;
    std.mem.writeInt(u32, bytes[0..4], 0x0001_0000, .big);
    std.mem.writeInt(u32, bytes[4..8], 1, .big);
    std.mem.writeInt(u32, bytes[8..12], 1, .big);
    std.mem.writeInt(u32, bytes[12..16], 34, .big);
    std.mem.writeInt(u16, bytes[16..18], 0, .big);
    std.mem.writeInt(u16, bytes[18..20], 1, .big);
    std.mem.writeInt(u16, bytes[20..22], 22, .big);
    std.mem.writeInt(u16, bytes[22..24], 0x2004, .big);
    std.mem.writeInt(u32, bytes[24..28], 1, .big);
    // Lookup format 8: glyph 1 -> glyph 2.
    std.mem.writeInt(u16, bytes[28..30], 8, .big);
    std.mem.writeInt(u16, bytes[30..32], 1, .big);
    std.mem.writeInt(u16, bytes[32..34], 1, .big);
    std.mem.writeInt(u16, bytes[34..36], 2, .big);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.append(std.testing.allocator, false);

    try apply(std.testing.allocator, &bytes, 0, bytes.len, 3, &glyphs, .{ .glyph_substituted = &substituted });
    try std.testing.expectEqual(@as(GlyphId, 2), glyphs.items[0]);
    try std.testing.expect(substituted.items[0]);
}

test "legacy mort rearrangement executes obsolete state offsets" {
    var bytes = [_]u8{0} ** 72;
    std.mem.writeInt(u32, bytes[0..4], 0x0001_0000, .big);
    std.mem.writeInt(u32, bytes[4..8], 1, .big);
    std.mem.writeInt(u32, bytes[8..12], 1, .big);
    std.mem.writeInt(u32, bytes[12..16], 64, .big);
    std.mem.writeInt(u16, bytes[16..18], 0, .big);
    std.mem.writeInt(u16, bytes[18..20], 1, .big);
    std.mem.writeInt(u16, bytes[20..22], 52, .big);
    std.mem.writeInt(u16, bytes[22..24], 0x2000, .big);
    std.mem.writeInt(u32, bytes[24..28], 1, .big);

    const machine = 28;
    std.mem.writeInt(u16, bytes[machine..][0..2], 4, .big); // stateSize / class count.
    std.mem.writeInt(u16, bytes[machine + 2 ..][0..2], 8, .big);
    std.mem.writeInt(u16, bytes[machine + 4 ..][0..2], 16, .big);
    std.mem.writeInt(u16, bytes[machine + 6 ..][0..2], 24, .big);
    // ClassTable: glyph 1 and glyph 2 both use class 3.
    std.mem.writeInt(u16, bytes[machine + 8 ..][0..2], 1, .big);
    std.mem.writeInt(u16, bytes[machine + 10 ..][0..2], 2, .big);
    bytes[machine + 12] = 3;
    bytes[machine + 13] = 3;
    // Two state rows. First glyph selects entry 1, second selects entry 2.
    bytes[machine + 16 + 3] = 1;
    bytes[machine + 16 + 4 + 3] = 2;
    // entry 0 inert, entry 1 marks first and moves to row 1, entry 2 marks
    // last and applies verb 1 (AB -> BA).
    std.mem.writeInt(u16, bytes[machine + 24 ..][0..2], 16, .big);
    std.mem.writeInt(u16, bytes[machine + 28 ..][0..2], 20, .big);
    std.mem.writeInt(u16, bytes[machine + 30 ..][0..2], 0x8000, .big);
    std.mem.writeInt(u16, bytes[machine + 32 ..][0..2], 16, .big);
    std.mem.writeInt(u16, bytes[machine + 34 ..][0..2], 0x2001, .big);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 1 });

    try apply(std.testing.allocator, &bytes, 0, bytes.len, 3, &glyphs, .{
        .glyph_source_indices = &sources,
        .glyph_cluster_indices = &clusters,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 1 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, sources.items);
}

test "legacy mort contextual substitution uses signed word offsets" {
    var bytes = [_]u8{0} ** 96;
    std.mem.writeInt(u32, bytes[0..4], 0x0001_0000, .big);
    std.mem.writeInt(u32, bytes[4..8], 1, .big);
    std.mem.writeInt(u32, bytes[8..12], 1, .big);
    std.mem.writeInt(u32, bytes[12..16], 88, .big);
    std.mem.writeInt(u16, bytes[16..18], 0, .big);
    std.mem.writeInt(u16, bytes[18..20], 1, .big);
    std.mem.writeInt(u16, bytes[20..22], 76, .big);
    std.mem.writeInt(u16, bytes[22..24], 0x2001, .big);
    std.mem.writeInt(u32, bytes[24..28], 1, .big);

    const machine = 28;
    std.mem.writeInt(u16, bytes[machine..][0..2], 4, .big);
    std.mem.writeInt(u16, bytes[machine + 2 ..][0..2], 10, .big);
    std.mem.writeInt(u16, bytes[machine + 4 ..][0..2], 18, .big);
    std.mem.writeInt(u16, bytes[machine + 6 ..][0..2], 26, .big);
    std.mem.writeInt(u16, bytes[machine + 8 ..][0..2], 50, .big);
    std.mem.writeInt(u16, bytes[machine + 10 ..][0..2], 1, .big);
    std.mem.writeInt(u16, bytes[machine + 12 ..][0..2], 2, .big);
    bytes[machine + 14] = 3;
    bytes[machine + 15] = 3;
    bytes[machine + 18 + 3] = 1;
    bytes[machine + 18 + 4 + 3] = 2;
    std.mem.writeInt(u16, bytes[machine + 26 ..][0..2], 18, .big);
    std.mem.writeInt(u16, bytes[machine + 34 ..][0..2], 22, .big);
    std.mem.writeInt(u16, bytes[machine + 36 ..][0..2], 0x8000, .big);
    std.mem.writeInt(u16, bytes[machine + 42 ..][0..2], 18, .big);
    // Entry 2 substitutes current glyph 2. Obsolete offsets are word offsets
    // from the state subtable, so 26 + glyph 2 addresses byte 56.
    std.mem.writeInt(i16, bytes[machine + 48 ..][0..2], 26, .big);
    std.mem.writeInt(u16, bytes[machine + 50 + 3 * 2 ..][0..2], 1, .big);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false });

    try apply(std.testing.allocator, &bytes, 0, bytes.len, 3, &glyphs, .{ .glyph_substituted = &substituted });
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 1 }, glyphs.items);
    try std.testing.expect(substituted.items[1]);
}

test "legacy mort insertion clones glyph metadata" {
    var bytes = [_]u8{0} ** 92;
    std.mem.writeInt(u32, bytes[0..4], 0x0001_0000, .big);
    std.mem.writeInt(u32, bytes[4..8], 1, .big);
    std.mem.writeInt(u32, bytes[8..12], 1, .big);
    std.mem.writeInt(u32, bytes[12..16], 84, .big);
    std.mem.writeInt(u16, bytes[16..18], 0, .big);
    std.mem.writeInt(u16, bytes[18..20], 1, .big);
    std.mem.writeInt(u16, bytes[20..22], 72, .big);
    std.mem.writeInt(u16, bytes[22..24], 0x2005, .big);
    std.mem.writeInt(u32, bytes[24..28], 1, .big);

    const machine = 28;
    std.mem.writeInt(u16, bytes[machine..][0..2], 4, .big);
    std.mem.writeInt(u16, bytes[machine + 2 ..][0..2], 10, .big);
    std.mem.writeInt(u16, bytes[machine + 4 ..][0..2], 18, .big);
    std.mem.writeInt(u16, bytes[machine + 6 ..][0..2], 22, .big);
    std.mem.writeInt(u16, bytes[machine + 8 ..][0..2], 62, .big);
    std.mem.writeInt(u16, bytes[machine + 10 ..][0..2], 1, .big);
    std.mem.writeInt(u16, bytes[machine + 12 ..][0..2], 1, .big);
    bytes[machine + 14] = 3;
    bytes[machine + 18 + 3] = 1;
    std.mem.writeInt(u16, bytes[machine + 22 ..][0..2], 18, .big);
    std.mem.writeInt(u16, bytes[machine + 30 ..][0..2], 18, .big);
    std.mem.writeInt(u16, bytes[machine + 32 ..][0..2], 0x0020, .big);
    // Entry 1 inserts glyph 2 after current glyph 1. The action value is a
    // zero-based glyph index, while the header's 62 is its byte-offset base.
    std.mem.writeInt(u16, bytes[machine + 34 ..][0..2], 0, .big);
    std.mem.writeInt(u16, bytes[machine + 36 ..][0..2], 0xffff, .big);
    std.mem.writeInt(u16, bytes[machine + 62 ..][0..2], 2, .big);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.append(std.testing.allocator, 7);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.append(std.testing.allocator, false);

    try apply(std.testing.allocator, &bytes, 0, bytes.len, 3, &glyphs, .{
        .glyph_source_indices = &sources,
        .glyph_substituted = &substituted,
    });
    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 2 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 7, 7 }, sources.items);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, substituted.items);
}
