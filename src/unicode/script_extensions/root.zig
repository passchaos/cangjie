//! Unicode 17 Script_Extensions membership.
//!
//! Only explicit UAX #24 overrides are stored in the compact table. A scalar
//! absent from that table inherits its single Script value.

const std = @import("std");
const script = @import("../script/root.zig");

const data = @embedFile("data.bin");
const header_len = 20;
const set_count = readU16(12);
const member_count = readU16(14);
const entry_count = readU32(16);
const offsets_offset = header_len;
const members_offset = offsets_offset + (@as(usize, set_count) + 1) * 2;
const entries_offset = members_offset + member_count;
const entry_len = 8;

pub const Set = struct {
    explicit: []const u8 = &.{},
    fallback: ?script.Script = null,

    pub fn len(self: Set) usize {
        return if (self.explicit.len != 0) self.explicit.len else 1;
    }

    pub fn contains(self: Set, candidate: script.Script) bool {
        if (self.explicit.len == 0) return self.fallback.? == candidate;
        const wanted: u8 = @intFromEnum(candidate);
        for (self.explicit) |member| {
            if (member == wanted) return true;
        }
        return false;
    }

    pub fn at(self: Set, index: usize) ?script.Script {
        if (index >= self.len()) return null;
        if (self.explicit.len == 0) return self.fallback;
        return @enumFromInt(self.explicit[index]);
    }
};

comptime {
    if (data.len < header_len or !std.mem.eql(u8, data[0..4], "CJSE") or
        data[4] != 1 or data[5] != 17 or data[6] != 0 or data[7] != 0)
    {
        @compileError("invalid Unicode Script_Extensions data");
    }
    if (readU32(8) != scriptEnumFingerprint() or
        entries_offset + @as(usize, entry_count) * entry_len != data.len)
    {
        @compileError("invalid Unicode Script_Extensions data layout");
    }
}

/// Returns whether `codepoint` is conventionally used with `candidate`.
///
/// UAX #24 defines Script_Extensions as an override of Script, not as a union
/// with it. Therefore an explicit extension row is authoritative even when the
/// scalar's Script value is already specific.
pub fn contains(codepoint: u21, candidate: script.Script) bool {
    return forCodepoint(codepoint).contains(candidate);
}

/// Return the Script_Extensions cardinality for one scalar.
///
/// The implicit fallback is always the singleton Script value, including
/// Unknown for unassigned scalars.
pub fn count(codepoint: u21) usize {
    return forCodepoint(codepoint).len();
}

/// Return a zero-allocation immutable view of one Script_Extensions set.
pub fn forCodepoint(codepoint: u21) Set {
    return if (explicitSet(codepoint)) |members|
        .{ .explicit = members }
    else
        .{ .fallback = script.forCodepoint(codepoint) };
}

/// Whether ScriptExtensions.txt overrides the scalar's primary Script value.
pub fn hasExplicit(codepoint: u21) bool {
    return explicitSet(codepoint) != null;
}

fn explicitSet(codepoint: u21) ?[]const u8 {
    var low: usize = 0;
    var high: usize = entry_count;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const offset = entries_offset + middle * entry_len;
        const scalar = readU32(offset);
        if (codepoint < scalar) {
            high = middle;
        } else if (codepoint > scalar) {
            low = middle + 1;
        } else {
            const set_index = data[offset + 4];
            const start = readU16(offsets_offset + @as(usize, set_index) * 2);
            const end = readU16(offsets_offset + (@as(usize, set_index) + 1) * 2);
            return data[members_offset + start .. members_offset + end];
        }
    }
    return null;
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
    inline for (@typeInfo(script.Script).@"enum".fields) |field| {
        for (field.name) |byte| value = (value ^ byte) *% 16777619;
        value = (value ^ 0xff) *% 16777619;
    }
    return value;
}
