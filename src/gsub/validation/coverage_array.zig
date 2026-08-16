//! Validation of required Offset16 arrays that reference Coverage tables.

const table = @import("../table/root.zig");

pub const Error = table.coverage.Error;
pub const Mode = enum {
    indexed,
    membership,
};
pub const View = table.View;

pub fn validate(
    view: View,
    base_offset: usize,
    offsets_position: usize,
    count: u16,
    mode: Mode,
) Error!void {
    try view.ensure(offsets_position, @as(usize, count) * 2);
    for (0..count) |index| {
        const coverage = try table.offset.required16(
            view,
            base_offset,
            try readU16(view, offsets_position + index * 2),
        );
        try table.coverage.validate(
            view,
            coverage,
            switch (mode) {
                .indexed => .indexed,
                .membership => .membership,
            },
        );
    }
}

fn readU16(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
