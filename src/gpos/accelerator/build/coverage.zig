//! First-Coverage navigation used while grouping GPOS lookup subtables.

const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub fn subtableOffset(
    view: View,
    subtable_offset: usize,
    lookup_type: u16,
) Error!?usize {
    return switch (lookup_type) {
        1, 2, 3, 4, 5, 6 => try requiredCoverage(
            view,
            subtable_offset,
            subtable_offset + 2,
        ),
        7 => contextOffset(view, subtable_offset),
        8 => chainingOffset(view, subtable_offset),
        9 => extensionOffset(view, subtable_offset),
        else => null,
    };
}

fn contextOffset(view: View, subtable_offset: usize) Error!?usize {
    return switch (try view.readU16(subtable_offset)) {
        1, 2 => try requiredCoverage(
            view,
            subtable_offset,
            subtable_offset + 2,
        ),
        3 => {
            const input_count = try view.readU16(subtable_offset + 2);
            if (input_count == 0) return null;
            return try requiredCoverage(
                view,
                subtable_offset,
                subtable_offset + 6,
            );
        },
        else => error.UnsupportedGpos,
    };
}

fn chainingOffset(view: View, subtable_offset: usize) Error!?usize {
    return switch (try view.readU16(subtable_offset)) {
        1, 2 => try requiredCoverage(
            view,
            subtable_offset,
            subtable_offset + 2,
        ),
        3 => {
            const parsed =
                try positioning.lookup.contextual.parseChainingCoverage(
                    view,
                    subtable_offset,
                ) orelse return null;
            return try parsed.input_coverages.coverageOffset(view, 0);
        },
        else => error.UnsupportedGpos,
    };
}

fn extensionOffset(view: View, wrapper_offset: usize) Error!?usize {
    const extension = try positioning.lookup.dispatch.extension(
        view,
        wrapper_offset,
    );
    if (extension.lookup_type == 9) return error.UnsupportedGpos;
    return subtableOffset(
        view,
        extension.payload_offset,
        extension.lookup_type,
    );
}

fn requiredCoverage(
    view: View,
    base_offset: usize,
    field_offset: usize,
) Error!usize {
    return table.offset.required16(
        view,
        base_offset,
        try view.readU16(field_offset),
    );
}
