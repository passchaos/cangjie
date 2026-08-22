//! Generated Unicode 17 Script-property lookup.
//!
//! The byte values are discriminants of `root.Script`; the generator reads the
//! enum order directly. The header also records that enum's stable fingerprint,
//! so reordering it without regenerating the blob fails at compile time.

const std = @import("std");

const data = @embedFile("data.bin");
const script_root = @import("types.zig");
const header_len = 16;
const index_count = readU16(12);
const page_count = readU16(14);
const index_offset = header_len;
const pages_offset = index_offset + @as(usize, index_count) * 2;

comptime {
    if (data.len < header_len or !std.mem.eql(u8, data[0..4], "CJS1") or
        data[4] != 1 or data[5] != 17 or data[6] != 0 or data[7] != 0)
    {
        @compileError("invalid Unicode Script data");
    }
    if (index_count != 0x1100 or
        pages_offset + @as(usize, page_count) * 256 != data.len)
    {
        @compileError("invalid Unicode Script data lengths");
    }
    if (readU32(8) != scriptEnumFingerprint()) {
        @compileError("Unicode Script data was generated for a different Script enum");
    }
}

pub inline fn scriptId(codepoint: u21) u8 {
    const page = @as(usize, codepoint) >> 8;
    const slot = readU16(index_offset + page * 2);
    return data[
        pages_offset + @as(usize, slot) * 256 +
            (@as(usize, codepoint) & 0xff)
    ];
}

fn readU16(offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

fn readU32(offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}

fn scriptEnumFingerprint() u32 {
    @setEvalBranchQuota(10_000);
    var value: u32 = 2166136261;
    inline for (@typeInfo(script_root.Script).@"enum".fields) |field| {
        for (field.name) |byte| {
            value = (value ^ byte) *% 16777619;
        }
        value = (value ^ 0xff) *% 16777619;
    }
    return value;
}
