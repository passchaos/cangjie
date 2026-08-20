//! OpenType Device and VariationIndex structural validation.

const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub fn validate(view: View, device_offset: usize) Error!void {
    try view.ensure(device_offset, 6);
    const start_size = try readU16ForValidation(view, device_offset);
    const end_size = try readU16ForValidation(view, device_offset + 2);
    const delta_format = try readU16ForValidation(view, device_offset + 4);

    // OpenType reuses Device offsets for VariationIndex records. DeltaFormat
    // 0x8000 identifies an exact three-uint16 record; the first two fields are
    // the outer and inner ItemVariationStore indexes rather than PPEM bounds.
    if (delta_format == 0x8000) return;
    if (end_size < start_size) return error.BadGpos;

    const bits_per_delta: usize = switch (delta_format) {
        1 => 2,
        2 => 4,
        3 => 8,
        else => return error.UnsupportedGpos,
    };
    const delta_count = @as(usize, end_size) - @as(usize, start_size) + 1;
    const words = (delta_count * bits_per_delta + 15) / 16;
    try view.ensure(device_offset + 6, words * 2);
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
