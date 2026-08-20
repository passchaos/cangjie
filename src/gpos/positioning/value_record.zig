//! GPOS ValueRecord sizing, structural validation, and scalar decoding.

const positioning = @import("root.zig");
const device = @import("device.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub fn size(format: u16) Error!usize {
    // Only the low byte is assigned by OpenType. Accepting unknown high bits
    // would compute too-small strides and reinterpret trailing payload bytes as
    // later PairValue or class records.
    if ((format & 0xff00) != 0) return error.BadGpos;
    var result: usize = 0;
    inline for (.{ 0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0080 }) |bit| {
        if ((format & bit) != 0) result += 2;
    }
    return result;
}

pub fn hasDeviceOffsets(format: u16) bool {
    return (format & 0x00f0) != 0;
}

pub fn validate(
    view: View,
    offset: usize,
    format: u16,
    parent_offset: usize,
) Error!void {
    try view.ensure(offset, try size(format));
    if (!hasDeviceOffsets(format)) return;

    // Device/VariationIndex offsets are relative to the immediate ValueRecord
    // parent (SinglePos subtable or PairSet), never to this record itself.
    var cursor = offset;
    inline for (.{ 0x0001, 0x0002, 0x0004, 0x0008 }) |bit| {
        if ((format & bit) != 0) cursor += 2;
    }
    inline for (.{ 0x0010, 0x0020, 0x0040, 0x0080 }) |bit| {
        if ((format & bit) != 0) {
            const relative = try readU16ForValidation(view, cursor);
            if (relative != 0) {
                try device.validate(
                    view,
                    try table.offset.required16(view, parent_offset, relative),
                );
            }
            cursor += 2;
        }
    }
}

pub fn read(
    view: View,
    offset: usize,
    format: u16,
    parent_offset: usize,
) Error!positioning.Adjustment {
    try validate(view, offset, format, parent_offset);
    var value = positioning.Adjustment{ .index = 0 };
    var cursor = offset;
    if ((format & 0x0001) != 0) {
        value.x_placement = try view.readI16(cursor);
        cursor += 2;
    }
    if ((format & 0x0002) != 0) {
        value.y_placement = try view.readI16(cursor);
        cursor += 2;
    }
    if ((format & 0x0004) != 0) {
        value.x_advance = try view.readI16(cursor);
        cursor += 2;
    }
    if ((format & 0x0008) != 0) {
        value.y_advance = try view.readI16(cursor);
    }
    return value;
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
