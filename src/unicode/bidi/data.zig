//! Generated Unicode 17 UAX #9 properties and sparse bracket/mirror maps.

const std = @import("std");

const data = @embedFile("data.bin");

pub const unicode_version = std.SemanticVersion{
    .major = 17,
    .minor = 0,
    .patch = 0,
};

/// Exact Unicode `Bidi_Class` values.
///
/// Declaration order is part of the generated binary format and the compact
/// BidiTest fixture. Keep it synchronized with both generators.
pub const Class = enum(u5) {
    l,
    r,
    al,
    en,
    es,
    et,
    an,
    cs,
    nsm,
    bn,
    b,
    s,
    ws,
    on,
    lre,
    lro,
    rle,
    rlo,
    pdf,
    lri,
    rli,
    fsi,
    pdi,
};

pub const Bracket = struct {
    opening: u21,
    is_open: bool,
};

const header_len = 16;
const index_count = readU16(8);
const page_count = readU16(10);
const bracket_count = readU16(12);
const mirror_count = readU16(14);
const index_offset = header_len;
const pages_offset = index_offset + @as(usize, index_count) * 2;
const brackets_offset = pages_offset + @as(usize, page_count) * 256;
const mirrors_offset = brackets_offset + @as(usize, bracket_count) * 12;

const ascii_classes = buildAsciiClasses();

comptime {
    if (data.len < header_len or !std.mem.eql(u8, data[0..4], "CJB1") or
        data[4] != 1 or data[5] != 17 or data[6] != 0 or data[7] != 0)
    {
        @compileError("invalid Unicode bidi data");
    }
    if (index_count != 0x1100 or
        mirrors_offset + @as(usize, mirror_count) * 8 != data.len)
    {
        @compileError("invalid Unicode bidi data lengths");
    }
}

pub inline fn class(codepoint: u21) Class {
    if (codepoint < 0x80) return ascii_classes[codepoint];
    return classGenerated(codepoint);
}

pub fn bracket(codepoint: u21) ?Bracket {
    var low: usize = 0;
    var high: usize = bracket_count;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const offset = brackets_offset + mid * 12;
        const candidate = readU32(offset);
        if (codepoint < candidate) {
            high = mid;
        } else if (codepoint > candidate) {
            low = mid + 1;
        } else {
            return .{
                .opening = @intCast(readU32(offset + 4)),
                .is_open = data[offset + 8] != 0,
            };
        }
    }
    return null;
}

pub fn mirrored(codepoint: u21) u21 {
    var low: usize = 0;
    var high: usize = mirror_count;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const offset = mirrors_offset + mid * 8;
        const candidate = readU32(offset);
        if (codepoint < candidate) {
            high = mid;
        } else if (codepoint > candidate) {
            low = mid + 1;
        } else {
            return @intCast(readU32(offset + 4));
        }
    }
    return codepoint;
}

fn classGenerated(codepoint: u21) Class {
    const page = @as(usize, codepoint) >> 8;
    const slot = readU16(index_offset + page * 2);
    return @enumFromInt(data[
        pages_offset + @as(usize, slot) * 256 +
            (@as(usize, codepoint) & 0xff)
    ]);
}

fn buildAsciiClasses() [128]Class {
    var result: [128]Class = undefined;
    for (&result, 0..) |*entry, codepoint| {
        entry.* = classGenerated(@intCast(codepoint));
    }
    return result;
}

fn readU16(offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

fn readU32(offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}
