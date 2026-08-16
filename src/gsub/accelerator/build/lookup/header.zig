//! Lookup header proof used before trusted accelerator dispatch.

const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub fn validate(view: View, lookup_offset: usize) Error!void {
    if (lookup_offset > view.length or view.length - lookup_offset < 6) {
        return error.BadGsub;
    }
    const lookup_flag = try readU16(view, lookup_offset + 2);
    const subtable_count = try readU16(view, lookup_offset + 4);
    // OpenType reserves bits 5..7. MarkAttachmentType occupies the high byte,
    // and UseMarkFilteringSet is the defined low bit 4.
    if ((lookup_flag & 0x00e0) != 0) return error.BadGsub;
    const offsets = lookup_offset + 6;
    const offsets_len = @as(usize, subtable_count) * 2;
    try view.ensure(offsets, offsets_len);
    if ((lookup_flag & 0x0010) != 0) {
        try view.ensure(offsets + offsets_len, 2);
    }
}

fn readU16(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        // Public font validation reports malformed layout structure uniformly
        // as BadGsub rather than leaking the table reader's transport detail.
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
