//! Direct GSUB subtable fixed-header and body validation.

const contextual = @import("../contextual/root.zig");
const direct = @import("../direct/root.zig");
const reverse = @import("../reverse.zig");
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded };
pub const Mode = enum { strict, shaping };
pub const View = table.View;

pub fn validate(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    lookup_type: u16,
    mode: Mode,
) Error!void {
    try validateFixed(view, subtable_offset, lookup_type);
    switch (lookup_type) {
        1 => try direct.single.validate(view, subtable_offset),
        2 => try direct.set_sequence.multiple(view, subtable_offset),
        3 => try direct.set_sequence.alternate(view, subtable_offset),
        4 => try direct.ligature.validate(
            view,
            subtable_offset,
            if (mode == .strict) .strict else .shaping,
        ),
        5 => try contextual.context.validate(
            Executor,
            view,
            subtable_offset,
        ),
        6 => try contextual.chaining.validate(
            Executor,
            view,
            subtable_offset,
            if (mode == .strict) .strict else .shaping,
        ),
        8 => try reverse.validate(view, subtable_offset),
        else => {},
    }
}

pub fn validateFixed(
    view: View,
    subtable_offset: usize,
    lookup_type: u16,
) Error!void {
    if (subtable_offset > view.length or
        view.length - subtable_offset < 2)
    {
        return error.BadGsub;
    }
    const format = try read(view, subtable_offset);
    const minimum: usize = switch (lookup_type) {
        1, 2, 3, 4 => 6,
        5 => switch (format) {
            1, 3 => 6,
            2 => 8,
            else => return error.UnsupportedGsub,
        },
        6 => switch (format) {
            1 => 6,
            2 => 12,
            3 => 4,
            else => return error.UnsupportedGsub,
        },
        8 => 6,
        else => return,
    };
    if (view.length - subtable_offset < minimum) return error.BadGsub;
}

fn read(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
