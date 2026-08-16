//! GSUB Lookup fixed-header and LookupFlag validation.

const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

/// Validate the fixed Lookup fields and return its type.
///
/// Subtable payloads remain a separate proof because parse-time contextual
/// record validation intentionally checks nested lookup headers without
/// recursively walking every nested payload.
pub fn validate(view: View, lookup_offset: usize) Error!u16 {
    if (lookup_offset > view.length or view.length - lookup_offset < 6) {
        return error.BadGsub;
    }
    const lookup_type = try read(view, lookup_offset);
    const lookup_flag = try read(view, lookup_offset + 2);
    const subtable_count = try read(view, lookup_offset + 4);
    // OpenType reserves bits 5..7. MarkAttachmentType occupies the high byte,
    // and UseMarkFilteringSet is the defined low bit 4.
    if ((lookup_flag & 0x00e0) != 0) return error.BadGsub;
    const offsets = lookup_offset + 6;
    const offsets_len = @as(usize, subtable_count) * 2;
    try view.ensure(offsets, offsets_len);
    if ((lookup_flag & 0x0010) != 0) {
        try view.ensure(offsets + offsets_len, 2);
    }
    return lookup_type;
}

fn read(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
