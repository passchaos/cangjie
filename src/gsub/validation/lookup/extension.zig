//! ExtensionSubst wrapper and wrapped-payload validation.

const subtable = @import("subtable.zig");
const table = @import("../../table/root.zig");

pub const Error = subtable.Error;
pub const View = table.View;

pub fn validateAll(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
) Error!void {
    for (0..subtable_count) |subtable_index| {
        const wrapper = try table.offset.required16(
            view,
            lookup_offset,
            try readU16(
                view,
                lookup_offset + 6 + subtable_index * 2,
            ),
        );
        try validate(Executor, view, wrapper);
    }
}

/// Validate one wrapper and its complete payload using strict body policy.
///
/// Existing shaping validation deliberately keeps ExtensionSubst strict:
/// wrapper indirection does not relax the wrapped lookup's font grammar.
pub fn validate(
    comptime Executor: type,
    view: View,
    wrapper: usize,
) Error!void {
    if (wrapper > view.length or view.length - wrapper < 8) {
        return error.BadGsub;
    }
    if (try readU16(view, wrapper) != 1) return error.UnsupportedGsub;
    const wrapped_type = try readU16(view, wrapper + 2);
    if (wrapped_type == 7) return error.UnsupportedGsub;
    const payload = try table.offset.extensionPayload(
        view,
        wrapper,
        try readU32(view, wrapper + 4),
    );
    try subtable.validate(
        Executor,
        view,
        payload,
        wrapped_type,
        .strict,
    );
}

fn readU16(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}

fn readU32(view: View, offset: usize) Error!u32 {
    return view.readU32(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
