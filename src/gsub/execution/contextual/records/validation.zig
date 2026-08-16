//! Atomic preflight for OpenType SequenceLookupRecord arrays.

const filtering = @import("../../../runtime/filtering.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");

const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded };
const View = table.View;

/// Validate every nested lookup reference before any contextual record runs.
///
/// `Executor.validateNested` is a comptime-resolved concrete declaration. The
/// record module stays independent of the recursive lookup dispatcher without
/// storing callbacks or erasing caller state.
pub fn validate(
    comptime Executor: type,
    view: View,
    records_offset: usize,
    record_count: usize,
    run: Options,
) Error!void {
    try validateReferences(
        Executor,
        view,
        records_offset,
        record_count,
    );
    const lookup_list = try requiredLookupList(view);
    for (0..record_count) |record_index| {
        const record = records_offset + record_index * 4;
        const lookup_index = try read(view, record + 2);
        const lookup_offset = try table.offset.required16(
            view,
            lookup_list,
            try read(
                view,
                lookup_list + 2 + @as(usize, lookup_index) * 2,
            ),
        );
        try validateMarkFilteringSet(view, lookup_offset, run);
    }
}

pub fn validateReferences(
    comptime Executor: type,
    view: View,
    records_offset: usize,
    record_count: usize,
) Error!void {
    try validateList(view, records_offset, record_count);
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try read(view, lookup_list);
    for (0..record_count) |record_index| {
        const record = records_offset + record_index * 4;
        // Out-of-range SequenceIndex values are ignored during execution, but
        // every record must still name an existing nested lookup.
        const lookup_index = try read(view, record + 2);
        if (lookup_index >= lookup_count) return error.BadGsub;
        const lookup_offset = try table.offset.required16(
            view,
            lookup_list,
            try read(
                view,
                lookup_list + 2 + @as(usize, lookup_index) * 2,
            ),
        );
        try Executor.validateNested(view, lookup_offset);
    }
}

pub fn validateList(
    view: View,
    records_offset: usize,
    record_count: usize,
) Error!void {
    if (records_offset > view.length or
        record_count > (view.length - records_offset) / 4)
    {
        return error.BadGsub;
    }
}

fn validateMarkFilteringSet(
    view: View,
    lookup_offset: usize,
    run: Options,
) Error!void {
    const lookup_flag = try read(view, lookup_offset + 2);
    if ((lookup_flag & 0x0010) == 0) return;
    const subtable_count = try read(view, lookup_offset + 4);
    try filtering.validateMarkFilteringSetIndex(.{
        .mark_filtering_sets = run.mark_filtering_sets,
        .active_mark_filtering_set = try read(
            view,
            lookup_offset + 6 + @as(usize, subtable_count) * 2,
        ),
    });
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(view, 0, try read(view, 8));
}

fn read(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}
