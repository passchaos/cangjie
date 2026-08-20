//! GDEF MarkGlyphSetsDef validation and owned set expansion.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const coverage = @import("coverage.zig");

pub const Error = coverage.Error;
pub const ParseError = coverage.ParseError;
pub const GlyphId = coverage.GlyphId;

pub fn validate(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
) ParseError!void {
    const count = try setCount(data, offset);
    const children_start = 4 + @as(usize, count) * 4;
    for (0..count) |index| {
        const relative = try bin.readU32At(data, offset + 4 + index * 4);
        if (relative < children_start or relative > data.len - offset) {
            return error.BadSfnt;
        }
        try coverage.validate(
            data,
            offset + relative,
            glyph_count,
            .mark_filtering_set,
        );
    }
}

pub fn read(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
) Error![][]GlyphId {
    const count = try setCount(data, offset);
    const children_start = 4 + @as(usize, count) * 4;
    const sets = try allocator.alloc([]GlyphId, count);
    errdefer allocator.free(sets);
    var initialized: usize = 0;
    errdefer freeInitialized(allocator, sets[0..initialized]);

    for (sets, 0..) |*set, index| {
        const relative = try bin.readU32At(data, offset + 4 + index * 4);
        if (relative < children_start or relative > data.len - offset) {
            return error.BadSfnt;
        }
        set.* = try coverage.glyphs(allocator, data, offset + relative);
        initialized += 1;
    }
    return sets;
}

pub fn setCountPublic(data: []const u8, offset: usize) ParseError!u16 {
    return setCount(data, offset);
}

pub fn readSet(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    set_index: usize,
) (Error || error{InvalidMarkGlyphSet})![]GlyphId {
    const set_count = try setCount(data, offset);
    if (set_index >= set_count) return error.InvalidMarkGlyphSet;
    const children_start = 4 + @as(usize, set_count) * 4;
    const relative = try bin.readU32At(data, offset + 4 + set_index * 4);
    if (relative < children_start or relative > data.len - offset) {
        return error.BadSfnt;
    }
    return coverage.glyphs(allocator, data, offset + relative);
}

pub fn free(allocator: std.mem.Allocator, sets: [][]GlyphId) void {
    freeInitialized(allocator, sets);
    allocator.free(sets);
}

fn setCount(data: []const u8, offset: usize) ParseError!u16 {
    if (offset > data.len or data.len - offset < 4) return error.BadSfnt;
    if (try bin.readU16At(data, offset) != 1) return error.BadSfnt;
    const count = try bin.readU16At(data, offset + 2);
    if (@as(usize, count) * 4 > data.len - (offset + 4)) {
        return error.BadSfnt;
    }
    return count;
}

fn freeInitialized(
    allocator: std.mem.Allocator,
    sets: [][]GlyphId,
) void {
    for (sets) |set| allocator.free(set);
}
