//! Compact ReverseChainSingleSubst fixtures shared by execution tests.

const std = @import("std");

pub fn writeLookup(
    bytes: []u8,
    lookup_type: u16,
    lookup_flag: u16,
    children: []const u16,
) void {
    writeU16(bytes, 0, lookup_type);
    writeU16(bytes, 2, lookup_flag);
    writeU16(bytes, 4, @intCast(children.len));
    for (children, 0..) |child, index| {
        writeU16(bytes, 6 + index * 2, child);
    }
}

pub fn writeExtensionWrapper(
    bytes: []u8,
    wrapper: usize,
    payload: usize,
) void {
    writeU16(bytes, wrapper, 1);
    writeU16(bytes, wrapper + 2, 8);
    writeU32(bytes, wrapper + 4, @intCast(payload - wrapper));
}

/// Write one format-1 subtable with singleton target and context coverages.
///
/// Backtrack glyphs are supplied nearest first, matching OpenType storage.
/// Lookahead glyphs are supplied in forward order.
pub fn writeReverse(
    bytes: []u8,
    base: usize,
    target: u16,
    substitute: u16,
    backtrack: []const u16,
    lookahead: []const u16,
) void {
    writeU16(bytes, base, 1);
    var cursor = base + 4;
    writeU16(bytes, cursor, @intCast(backtrack.len));
    cursor += 2;
    const backtrack_offsets = cursor;
    cursor += backtrack.len * 2;
    writeU16(bytes, cursor, @intCast(lookahead.len));
    cursor += 2;
    const lookahead_offsets = cursor;
    cursor += lookahead.len * 2;
    writeU16(bytes, cursor, 1);
    writeU16(bytes, cursor + 2, substitute);
    cursor += 4;

    writeU16(bytes, base + 2, @intCast(cursor - base));
    writeCoverage1(bytes, cursor, target);
    cursor += 6;
    for (backtrack, 0..) |glyph, index| {
        writeU16(
            bytes,
            backtrack_offsets + index * 2,
            @intCast(cursor - base),
        );
        writeCoverage1(bytes, cursor, glyph);
        cursor += 6;
    }
    for (lookahead, 0..) |glyph, index| {
        writeU16(
            bytes,
            lookahead_offsets + index * 2,
            @intCast(cursor - base),
        );
        writeCoverage1(bytes, cursor, glyph);
        cursor += 6;
    }
}

pub fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
