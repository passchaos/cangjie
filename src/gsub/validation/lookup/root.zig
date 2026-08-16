//! GSUB Lookup and ordered-subtable validation surface.

pub const extension = @import("extension.zig");
pub const header = @import("header.zig");
const subtable = @import("subtable.zig");
const table = @import("../../table/root.zig");

pub const Error = subtable.Error;
pub const Mode = subtable.Mode;
pub const View = table.View;

/// Validate a Lookup header and the ExtensionSubst payload graph it owns.
pub fn validateHeader(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
) Error!u16 {
    const lookup_type = try header.validate(view, lookup_offset);
    if (lookup_type == 7 and !view.assume_validated) {
        try extension.validateAll(
            Executor,
            view,
            lookup_offset,
            try read(view, lookup_offset + 4),
        );
    }
    return lookup_type;
}

/// Validate every supported direct subtable before lookup execution mutates.
pub fn validateSubtables(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
    mode: Mode,
) Error!void {
    switch (lookup_type) {
        1, 2, 3, 4, 5, 6, 8 => {},
        else => return,
    }
    for (0..subtable_count) |subtable_index| {
        const child = try table.offset.required16(
            view,
            lookup_offset,
            try read(
                view,
                lookup_offset + 6 + subtable_index * 2,
            ),
        );
        try subtable.validate(
            Executor,
            view,
            child,
            lookup_type,
            mode,
        );
    }
}

fn read(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
