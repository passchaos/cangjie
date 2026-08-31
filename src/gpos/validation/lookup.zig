//! Atomic validation of supported GPOS lookup payloads.
//!
//! Contextual lookups append nested adjustments while walking PosLookupRecord
//! arrays. This validator proves the complete reachable supported graph before
//! execution so malformed later records cannot expose partial output.

const contextual = @import("contextual.zig");
const limits = @import("../runtime/limits.zig");
const matching = @import("../runtime/matching.zig");
const options = @import("../runtime/options.zig");
const positioning = @import("../positioning/root.zig");
const table = @import("../table/root.zig");

pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const Options = options.Options;
pub const View = table.View;

pub const max_context_depth = limits.max_context_depth;

pub fn records(
    view: View,
    records_pos: usize,
    record_count: usize,
    input_count: usize,
) Error!void {
    try recordList(view, records_pos, record_count);
    try recordReferences(view, records_pos, record_count, input_count, 0);
}

pub fn recordMarkFilteringSets(
    view: View,
    records_pos: usize,
    record_count: usize,
    run: Options,
) Error!void {
    const lookup_list = try requiredLookupList(view);
    for (0..record_count) |record_index| {
        const lookup_index =
            try readU16(view, records_pos + record_index * 4 + 2);
        const lookup = try lookupOffset(view, lookup_list, lookup_index);
        const lookup_flag = try readU16(view, lookup + 2);
        if ((lookup_flag & 0x0010) == 0) continue;
        const subtable_count = try readU16(view, lookup + 4);
        try matching.validateMarkFilteringSetIndex(.{
            .mark_filtering_sets = run.mark_filtering_sets,
            .active_mark_filtering_set = try readU16(
                view,
                lookup + 6 + @as(usize, subtable_count) * 2,
            ),
        });
    }
}

pub fn headerAndExtensions(view: View, lookup_offset: usize) Error!void {
    const header = try positioning.lookup.dispatch.header(view, lookup_offset);
    if (header.lookup_type != 9) return;
    for (0..header.subtable_count) |subtable_index| {
        const wrapper =
            try positioning.lookup.dispatch.extensionWrapperOffset(
                view,
                lookup_offset,
                subtable_index,
            );
        const extension =
            try positioning.lookup.dispatch.extension(view, wrapper);
        try positioning.lookup.dispatch.validateSubtableFixedHeader(
            view,
            extension.payload_offset,
            extension.lookup_type,
        );
        try subtableVariableData(
            view,
            extension.payload_offset,
            extension.lookup_type,
        );
    }
}

pub fn lookupSubtables(
    view: View,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
) Error!void {
    return lookupSubtablesDepth(
        view,
        lookup_offset,
        lookup_type,
        subtable_count,
        0,
    );
}

pub fn subtableVariableData(
    view: View,
    subtable_offset: usize,
    lookup_type: u16,
) Error!void {
    return subtableVariableDataDepth(
        view,
        subtable_offset,
        lookup_type,
        0,
    );
}

pub fn contextSubtable(
    view: View,
    subtable_offset: usize,
    depth: usize,
) Error!void {
    return contextual.contextSubtable(
        view,
        subtable_offset,
        depth,
        recordsDepth,
    );
}

pub fn contextRuleSet(
    view: View,
    rule_set_offset: usize,
    depth: usize,
) Error!void {
    return contextual.contextRuleSet(
        view,
        rule_set_offset,
        depth,
        recordsDepth,
    );
}

pub fn chainingSubtable(
    view: View,
    subtable_offset: usize,
    depth: usize,
) Error!void {
    return contextual.chainingSubtable(
        view,
        subtable_offset,
        depth,
        recordsDepth,
    );
}

pub fn chainingRuleSet(
    view: View,
    rule_set_offset: usize,
    depth: usize,
) Error!void {
    return contextual.chainingRuleSet(
        view,
        rule_set_offset,
        depth,
        recordsDepth,
    );
}

pub fn coverage(view: View, coverage_offset: usize) Error!void {
    return table.coverage.validate(view, coverage_offset, .indexed);
}

pub fn classDef(view: View, class_def_offset: usize) Error!void {
    return table.class_def.validate(view, class_def_offset);
}

pub fn classDefWithLimit(
    view: View,
    class_def_offset: usize,
    class_count: ?u16,
) Error!void {
    return table.class_def.validateWithLimit(
        view,
        class_def_offset,
        class_count,
    );
}

fn recordList(
    view: View,
    records_pos: usize,
    record_count: usize,
) Error!void {
    // PosLookupRecord arrays are all-or-nothing parts of a contextual match.
    if (records_pos > view.length) return error.BadGpos;
    if (record_count > (view.length - records_pos) / 4) return error.BadGpos;
}

fn recordsDepth(
    view: View,
    records_pos: usize,
    record_count: usize,
    input_count: usize,
    depth: usize,
) Error!void {
    try recordList(view, records_pos, record_count);
    try recordReferences(
        view,
        records_pos,
        record_count,
        input_count,
        depth,
    );
}

fn recordReferences(
    view: View,
    records_pos: usize,
    record_count: usize,
    input_count: usize,
    depth: usize,
) Error!void {
    // `depth` is the number of PosLookupRecord edges already entered by the
    // parent lookup. A contextual record at depth sixteen would be edge
    // seventeen, while a non-contextual leaf reached by edge sixteen remains
    // valid because it never enters this record walker.
    if (depth >= max_context_depth) return error.UnsupportedGpos;
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try readU16(view, lookup_list);
    for (0..record_count) |record_index| {
        const record = records_pos + record_index * 4;
        if (try readU16(view, record) >= input_count) return error.BadGpos;
        const lookup_index = try readU16(view, record + 2);
        if (lookup_index >= lookup_count) return error.BadGpos;
        if (view.validating_full_lookup_list) continue;
        const lookup = try lookupOffset(view, lookup_list, lookup_index);
        try headerAndExtensions(view, lookup);
        try lookupSubtablesDepth(
            view,
            lookup,
            try readU16(view, lookup),
            try readU16(view, lookup + 4),
            depth + 1,
        );
    }
}

fn lookupSubtablesDepth(
    view: View,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
    depth: usize,
) Error!void {
    switch (lookup_type) {
        1, 2, 3, 4, 5, 6, 7, 8 => {},
        else => return,
    }
    for (0..subtable_count) |subtable_index| {
        const subtable = try table.offset.required16(
            view,
            lookup_offset,
            try readU16(
                view,
                lookup_offset + 6 + subtable_index * 2,
            ),
        );
        try positioning.lookup.dispatch.validateSubtableFixedHeader(
            view,
            subtable,
            lookup_type,
        );
        try subtableVariableDataDepth(
            view,
            subtable,
            lookup_type,
            depth,
        );
    }
}

fn subtableVariableDataDepth(
    view: View,
    subtable_offset: usize,
    lookup_type: u16,
    depth: usize,
) Error!void {
    switch (lookup_type) {
        1 => try positioning.lookup.single.validate(view, subtable_offset),
        2 => try positioning.lookup.pair.validate(view, subtable_offset),
        3 => try positioning.lookup.cursive.validate(view, subtable_offset),
        4 => try positioning.lookup.marks.validateMarkToBase(
            view,
            subtable_offset,
        ),
        5 => try positioning.lookup.marks.validateMarkToLigature(
            view,
            subtable_offset,
        ),
        6 => try positioning.lookup.marks.validateMarkToMark(
            view,
            subtable_offset,
        ),
        7 => try contextSubtable(view, subtable_offset, depth),
        8 => try chainingSubtable(view, subtable_offset, depth),
        else => {},
    }
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(view, 0, try readU16(view, 8));
}

fn lookupOffset(
    view: View,
    lookup_list: usize,
    lookup_index: usize,
) Error!usize {
    return table.offset.required16(
        view,
        lookup_list,
        try readU16(view, lookup_list + 2 + lookup_index * 2),
    );
}

fn readU16(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
