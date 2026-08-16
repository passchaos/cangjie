//! GPOS Offset16/Offset32 resolution contracts.

const view = @import("view.zig");

pub const Error = view.Error;
pub const View = view.View;

pub fn required16(table: View, base: usize, relative: u16) Error!usize {
    if (relative == 0) return error.BadGpos;
    return offset16(table, base, relative);
}

pub fn required32(table: View, base: usize, relative: u32) Error!usize {
    if (relative == 0) return error.BadGpos;
    return offset32(table, base, relative);
}

pub fn optional16(table: View, base: usize, relative: u16) Error!?usize {
    if (relative == 0) return null;
    return try offset16(table, base, relative);
}

pub fn optional32(table: View, base: usize, relative: u32) Error!?usize {
    if (relative == 0) return null;
    return try offset32(table, base, relative);
}

/// Resolve an ExtensionPos payload and reject offsets that point back into the
/// fixed eight-byte wrapper instead of naming a child positioning subtable.
pub fn extensionPayload(
    table: View,
    extension_offset: usize,
    relative: u32,
) Error!usize {
    if (relative < 8) return error.BadGpos;
    return try offset32(table, extension_offset, relative);
}

fn offset16(table: View, base: usize, relative: u16) Error!usize {
    return try checkedAdd(table, base, relative);
}

fn offset32(table: View, base: usize, relative: u32) Error!usize {
    return try checkedAdd(table, base, relative);
}

fn checkedAdd(table: View, base: usize, relative: anytype) Error!usize {
    if (base > table.length) return error.BadGpos;
    const amount: usize = @intCast(relative);
    if (amount > table.length - base) return error.BadGpos;
    return base + amount;
}
