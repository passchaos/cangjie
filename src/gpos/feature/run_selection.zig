//! Run-specific filtering and canonicalization of active GPOS lookups.

const std = @import("std");
const options = @import("../runtime/options.zig");
const selection = @import("selection.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const Options = options.Options;
pub const View = table.View;

pub fn lookupIndices(
    view: View,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var lookups = try selection.lookupIndices(
        view,
        allocator,
        .{
            .script_tag = run.script_tag,
            .language_tag = run.language_tag,
            .overrides = run.features,
        },
    );
    errdefer lookups.deinit(allocator);

    // Filter in place so adding run metadata to activation selection does not
    // allocate a second lookup list on the uncached shaping path.
    var write_index: usize = 0;
    for (lookups.items) |lookup_index| {
        if (!try mayApply(view, lookup_index, run)) continue;
        lookups.items[write_index] = lookup_index;
        write_index += 1;
    }
    lookups.shrinkRetainingCapacity(write_index);
    sortUnique(&lookups);
    return lookups;
}

fn mayApply(view: View, lookup_index: u16, run: Options) Error!bool {
    if (run.run_may_have_mark_attachments orelse true) return true;
    const lookup_list = try table.offset.required16(
        view,
        0,
        try view.readU16(8),
    );
    const lookup_count = try view.readU16(lookup_list);
    if (lookup_index >= lookup_count) return true;
    const lookup = try table.offset.required16(
        view,
        lookup_list,
        try view.readU16(lookup_list + 2 + @as(usize, lookup_index) * 2),
    );
    return switch (try view.readU16(lookup)) {
        4, 5, 6 => false,
        9 => extensionMayApplyWithoutMarks(view, lookup),
        else => true,
    };
}

fn extensionMayApplyWithoutMarks(view: View, lookup: usize) Error!bool {
    const subtable_count = try view.readU16(lookup + 4);
    for (0..subtable_count) |subtable_index| {
        const wrapper = try table.offset.required16(
            view,
            lookup,
            try view.readU16(lookup + 6 + subtable_index * 2),
        );
        if (try view.readU16(wrapper) != 1) return true;
        switch (try view.readU16(wrapper + 2)) {
            4, 5, 6 => {},
            else => return true,
        }
    }
    return false;
}

fn sortUnique(lookups: *std.ArrayList(u16)) void {
    if (lookups.items.len < 2) return;
    std.sort.heap(u16, lookups.items, {}, lessThan);
    var write_index: usize = 1;
    var previous = lookups.items[0];
    for (lookups.items[1..]) |lookup_index| {
        if (lookup_index == previous) continue;
        lookups.items[write_index] = lookup_index;
        write_index += 1;
        previous = lookup_index;
    }
    lookups.shrinkRetainingCapacity(write_index);
}

fn lessThan(_: void, lhs: u16, rhs: u16) bool {
    return lhs < rhs;
}
