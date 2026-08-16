//! GDEF Coverage validation, counting, and owned glyph expansion.

const std = @import("std");
const bin = @import("../../../../binary.zig");

pub const ParseError = error{ BadSfnt, EndOfStream };
pub const Error = ParseError || std.mem.Allocator.Error;
pub const GlyphId = u16;

pub const ReadMode = enum {
    canonical,
    mark_filtering_set,
};

pub fn validate(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
    mode: ReadMode,
) ParseError!void {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    switch (try bin.readU16At(data, offset)) {
        1 => try validateFormat1(data, offset, glyph_count, mode),
        2 => try validateFormat2(data, offset, glyph_count),
        else => return error.BadSfnt,
    }
}

pub fn glyphCount(data: []const u8, offset: usize) ParseError!u16 {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    return switch (try bin.readU16At(data, offset)) {
        1 => format1Count(data, offset),
        2 => format2Count(data, offset),
        else => error.BadSfnt,
    };
}

pub fn glyphs(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
) Error![]GlyphId {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    return switch (try bin.readU16At(data, offset)) {
        1 => format1Glyphs(allocator, data, offset),
        2 => format2Glyphs(allocator, data, offset),
        else => error.BadSfnt,
    };
}

fn validateFormat1(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
    mode: ReadMode,
) ParseError!void {
    if (data.len - offset < 4) return error.BadSfnt;
    const count = try bin.readU16At(data, offset + 2);
    if (@as(usize, count) * 2 > data.len - (offset + 4)) {
        return error.BadSfnt;
    }
    var previous: ?GlyphId = null;
    for (0..count) |index| {
        const glyph_id = try bin.readU16At(data, offset + 4 + index * 2);
        if (previous) |last| switch (mode) {
            .canonical => if (glyph_id <= last) return error.BadSfnt,
            // Roboto contains duplicate format-1 glyph IDs in GDEF mark sets,
            // and both HarfBuzz and FreeType accept them. Membership is
            // set-like, so tolerate equality while still rejecting decreasing
            // order that would break the sorted-set contract.
            .mark_filtering_set => if (glyph_id < last) return error.BadSfnt,
        };
        if (glyph_id >= glyph_count) return error.BadSfnt;
        previous = glyph_id;
    }
}

fn validateFormat2(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
) ParseError!void {
    if (data.len - offset < 4) return error.BadSfnt;
    const range_count = try bin.readU16At(data, offset + 2);
    if (@as(usize, range_count) * 6 > data.len - (offset + 4)) {
        return error.BadSfnt;
    }
    var previous_end: ?GlyphId = null;
    for (0..range_count) |index| {
        const record = offset + 4 + index * 6;
        const start = try bin.readU16At(data, record);
        const end = try bin.readU16At(data, record + 2);
        if (end < start) return error.BadSfnt;
        if (previous_end) |previous| {
            if (start <= previous) return error.BadSfnt;
        }
        if (end >= glyph_count) return error.BadSfnt;
        previous_end = end;
    }
}

fn format1Count(data: []const u8, offset: usize) ParseError!u16 {
    if (data.len - offset < 4) return error.BadSfnt;
    const count = try bin.readU16At(data, offset + 2);
    if (@as(usize, count) * 2 > data.len - (offset + 4)) {
        return error.BadSfnt;
    }
    return count;
}

fn format2Count(data: []const u8, offset: usize) ParseError!u16 {
    if (data.len - offset < 4) return error.BadSfnt;
    const range_count = try bin.readU16At(data, offset + 2);
    if (@as(usize, range_count) * 6 > data.len - (offset + 4)) {
        return error.BadSfnt;
    }
    var total: usize = 0;
    for (0..range_count) |index| {
        const record = offset + 4 + index * 6;
        const start = try bin.readU16At(data, record);
        const end = try bin.readU16At(data, record + 2);
        if (end < start) return error.BadSfnt;
        total += @as(usize, end) - @as(usize, start) + 1;
        if (total > std.math.maxInt(u16)) return error.BadSfnt;
    }
    return @intCast(total);
}

fn format1Glyphs(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
) Error![]GlyphId {
    const count = try format1Count(data, offset);
    const result = try allocator.alloc(GlyphId, count);
    errdefer allocator.free(result);
    var out: usize = 0;
    var previous: ?GlyphId = null;
    for (0..count) |index| {
        const glyph_id = try bin.readU16At(data, offset + 4 + index * 2);
        if (previous) |last| {
            if (glyph_id < last) return error.BadSfnt;
            if (glyph_id == last) continue;
        }
        previous = glyph_id;
        result[out] = glyph_id;
        out += 1;
    }
    return allocator.realloc(result, out);
}

fn format2Glyphs(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
) Error![]GlyphId {
    const total = try format2Count(data, offset);
    const range_count = try bin.readU16At(data, offset + 2);
    const result = try allocator.alloc(GlyphId, total);
    errdefer allocator.free(result);
    var out: usize = 0;
    var previous_end: ?GlyphId = null;
    for (0..range_count) |index| {
        const record = offset + 4 + index * 6;
        const start = try bin.readU16At(data, record);
        const end = try bin.readU16At(data, record + 2);
        if (previous_end) |previous| {
            if (start <= previous) return error.BadSfnt;
        }
        for (start..@as(usize, end) + 1) |glyph_id| {
            result[out] = @intCast(glyph_id);
            out += 1;
        }
        previous_end = end;
    }
    return result;
}
