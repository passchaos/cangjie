//! Canonical merged GSUB lookup-plan construction helpers.

const std = @import("std");
const model = @import("../model.zig");

pub fn append(
    lookups: *std.ArrayList(model.MergedLookup),
    allocator: std.mem.Allocator,
    selected: []const u16,
    application: model.Application,
) std.mem.Allocator.Error!void {
    const source_mask = if (application.source_scoped)
        model.sourceMaskForTag(application.tag) orelse 0
    else
        0;
    for (selected) |lookup| {
        try lookups.append(allocator, .{
            .lookup = lookup,
            .source_mask = source_mask,
            .auto_zwnj = application.auto_zwnj,
            .auto_zwj = application.auto_zwj,
            .match_source_syllable = application.match_source_syllable,
            .value = application.value,
            .random = isRandom(application),
        });
    }
}

pub fn canonicalize(lookups: *std.ArrayList(model.MergedLookup)) void {
    if (lookups.items.len < 2) return;

    std.sort.heap(
        model.MergedLookup,
        lookups.items,
        {},
        lessThan,
    );
    var write: usize = 1;
    var previous = lookups.items[0];
    for (lookups.items[1..]) |lookup| {
        if (lookup.lookup == previous.lookup) {
            const merged = &lookups.items[write - 1];
            merged.source_mask |= lookup.source_mask;
            merged.auto_zwnj = merged.auto_zwnj and lookup.auto_zwnj;
            merged.auto_zwj = merged.auto_zwj and lookup.auto_zwj;
            merged.match_source_syllable =
                merged.match_source_syllable or
                lookup.match_source_syllable;
            if (merged.value == 1) merged.value = lookup.value;
            merged.random = merged.random or lookup.random;
        } else {
            lookups.items[write] = lookup;
            write += 1;
            previous = lookup;
        }
    }
    lookups.shrinkRetainingCapacity(write);
}

pub fn isRandom(application: model.Application) bool {
    return application.tag == @import("../../../unicode.zig").tag("rand") and
        application.value == model.random_value;
}

fn lessThan(
    _: void,
    lhs: model.MergedLookup,
    rhs: model.MergedLookup,
) bool {
    return lhs.lookup < rhs.lookup;
}
