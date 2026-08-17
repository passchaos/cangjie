//! OpenType ClassDef lookup, dense expansion, and GDEF class validation.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const types = @import("types.zig");

pub const Error = error{ BadSfnt, EndOfStream };
pub const AllocationError = Error || std.mem.Allocator.Error;
pub const GlyphId = u16;

pub fn value(data: []const u8, offset: usize, glyph_id: GlyphId) Error!u16 {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    return switch (try bin.readU16At(data, offset)) {
        1 => format1Value(data, offset, glyph_id),
        2 => format2Value(data, offset, glyph_id),
        else => error.BadSfnt,
    };
}

pub fn readDense(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
    out: []u16,
    validate_glyph_classes: bool,
) Error!void {
    if (out.len != glyph_count) return error.BadSfnt;
    @memset(out, 0);
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    switch (try bin.readU16At(data, offset)) {
        1 => try readDenseFormat1(
            data,
            offset,
            glyph_count,
            out,
            validate_glyph_classes,
        ),
        2 => try readDenseFormat2(
            data,
            offset,
            glyph_count,
            out,
            validate_glyph_classes,
        ),
        else => return error.BadSfnt,
    }
}

pub fn glyphsInClass(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    glyph_count: u16,
    requested: types.GlyphClass,
) AllocationError![]GlyphId {
    try validateGlyphClassValue(@intFromEnum(requested));
    const dense = try allocator.alloc(u16, glyph_count);
    defer allocator.free(dense);
    try readDense(data, offset, glyph_count, dense, true);

    var result = std.ArrayList(GlyphId).empty;
    errdefer result.deinit(allocator);
    for (dense, 0..) |class, glyph_id| {
        if (class == @intFromEnum(requested)) {
            try result.append(allocator, @intCast(glyph_id));
        }
    }
    return result.toOwnedSlice(allocator);
}

pub fn validateBounds(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
) Error!void {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    switch (try bin.readU16At(data, offset)) {
        1 => {
            if (data.len - offset < 6) return error.BadSfnt;
            const start = try bin.readU16At(data, offset + 2);
            const count = try bin.readU16At(data, offset + 4);
            if (@as(usize, count) * 2 > data.len - (offset + 6)) {
                return error.BadSfnt;
            }
            if (count == 0) return;
            if (start >= glyph_count or
                @as(usize, count) > @as(usize, glyph_count - start))
            {
                return error.BadSfnt;
            }
        },
        2 => {
            if (data.len - offset < 4) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            try validateRanges(data, offset, range_count);
            for (0..range_count) |index| {
                const end = try bin.readU16At(
                    data,
                    offset + 4 + index * 6 + 2,
                );
                if (end >= glyph_count) return error.BadSfnt;
            }
        },
        else => return error.BadSfnt,
    }
}

pub fn validateGlyphClassValues(data: []const u8, offset: usize) Error!void {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    switch (try bin.readU16At(data, offset)) {
        1 => {
            if (data.len - offset < 6) return error.BadSfnt;
            const count = try bin.readU16At(data, offset + 4);
            if (@as(usize, count) * 2 > data.len - (offset + 6)) {
                return error.BadSfnt;
            }
            for (0..count) |index| {
                try validateGlyphClassValue(
                    try bin.readU16At(data, offset + 6 + index * 2),
                );
            }
        },
        2 => {
            if (data.len - offset < 4) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            try validateRanges(data, offset, range_count);
            for (0..range_count) |index| {
                try validateGlyphClassValue(
                    try bin.readU16At(data, offset + 4 + index * 6 + 4),
                );
            }
        },
        else => return error.BadSfnt,
    }
}

pub fn validateGlyphClassValue(class: u16) Error!void {
    // GlyphClassDef has a closed OpenType vocabulary (0..4).
    // MarkAttachClassDef deliberately bypasses this check because its non-zero
    // values are font-defined attachment groups, not glyph-kind enum tags.
    if (class > @intFromEnum(types.GlyphClass.component)) {
        return error.BadSfnt;
    }
}

fn format1Value(
    data: []const u8,
    offset: usize,
    glyph_id: GlyphId,
) Error!u16 {
    if (data.len - offset < 6) return error.BadSfnt;
    const start = try bin.readU16At(data, offset + 2);
    const count = try bin.readU16At(data, offset + 4);
    if (@as(usize, count) * 2 > data.len - (offset + 6)) {
        return error.BadSfnt;
    }
    const index: usize = glyph_id;
    const start_index: usize = start;
    const end = start_index + @as(usize, count);
    if (index < start_index or index >= end) return 0;
    return bin.readU16At(data, offset + 6 + (index - start_index) * 2);
}

fn format2Value(
    data: []const u8,
    offset: usize,
    glyph_id: GlyphId,
) Error!u16 {
    if (data.len - offset < 4) return error.BadSfnt;
    const range_count = try bin.readU16At(data, offset + 2);
    try validateRanges(data, offset, range_count);
    for (0..range_count) |index| {
        const record = offset + 4 + index * 6;
        const start = try bin.readU16At(data, record);
        const end = try bin.readU16At(data, record + 2);
        if (glyph_id >= start and glyph_id <= end) {
            return bin.readU16At(data, record + 4);
        }
    }
    return 0;
}

fn readDenseFormat1(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
    out: []u16,
    validate_classes: bool,
) Error!void {
    if (data.len - offset < 6) return error.BadSfnt;
    const start = try bin.readU16At(data, offset + 2);
    const count = try bin.readU16At(data, offset + 4);
    if (@as(usize, count) * 2 > data.len - (offset + 6)) {
        return error.BadSfnt;
    }
    if (count == 0) return;
    if (start >= glyph_count or
        @as(usize, count) > @as(usize, glyph_count - start))
    {
        return error.BadSfnt;
    }
    for (out[@as(usize, start) .. @as(usize, start) + count], 0..) |*slot, i| {
        const class = try bin.readU16At(data, offset + 6 + i * 2);
        if (validate_classes) try validateGlyphClassValue(class);
        slot.* = class;
    }
}

fn readDenseFormat2(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
    out: []u16,
    validate_classes: bool,
) Error!void {
    if (data.len - offset < 4) return error.BadSfnt;
    const range_count = try bin.readU16At(data, offset + 2);
    try validateRanges(data, offset, range_count);
    for (0..range_count) |index| {
        const record = offset + 4 + index * 6;
        const start = try bin.readU16At(data, record);
        const end = try bin.readU16At(data, record + 2);
        const class = try bin.readU16At(data, record + 4);
        if (end >= glyph_count) return error.BadSfnt;
        if (validate_classes) try validateGlyphClassValue(class);
        // Shaping repeatedly filters lookup candidates by glyph ID. Expand the
        // canonical ranges once at the font/cache boundary instead of parsing
        // ClassDef records again for each GSUB/GPOS lookup.
        @memset(out[@as(usize, start) .. @as(usize, end) + 1], class);
    }
}

fn validateRanges(
    data: []const u8,
    offset: usize,
    range_count: u16,
) Error!void {
    if (@as(usize, range_count) * 6 > data.len - (offset + 4)) {
        return error.BadSfnt;
    }
    // Format 2 records are sorted and disjoint. Enforcing that invariant makes
    // class lookup deterministic instead of silently choosing the first of
    // several overlapping records.
    var previous_end: ?GlyphId = null;
    for (0..range_count) |index| {
        const record = offset + 4 + index * 6;
        const start = try bin.readU16At(data, record);
        const end = try bin.readU16At(data, record + 2);
        if (end < start) return error.BadSfnt;
        if (previous_end) |previous| {
            if (start <= previous) return error.BadSfnt;
        }
        previous_end = end;
    }
}
