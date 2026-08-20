//! Bounds-checked arithmetic and big-endian helpers shared by decoders.

const std = @import("std");
const Error = @import("types.zig").Error;

pub fn checkedEnd(start: usize, len: usize, file_len: usize) Error!usize {
    if (start > file_len or len > file_len - start) return error.InvalidContainer;
    return start + len;
}

pub fn rangesOverlap(a_start: usize, a_end: usize, b_start: usize, b_end: usize) bool {
    return a_start < b_end and b_start < a_end;
}

pub fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}

pub fn align4(value: anytype) Error!usize {
    const widened: usize = @intCast(value);
    const sum = std.math.add(usize, widened, 3) catch return error.InvalidContainer;
    return sum & ~@as(usize, 3);
}

pub fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .big);
}

pub fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
