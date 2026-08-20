//! Predecode bounded nested SingleSubst records for chaining format 3.

const model = @import("../../model.zig");
const single_builder = @import("../single.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub fn fill(
    view: View,
    subtable: *model.ChainingCoverageSubtable,
) Error!void {
    if (subtable.subst_count == 0 or
        subtable.subst_count > model.ChainingCoverageSubtable.max_fast_records)
    {
        return;
    }
    const lookup_list = try table.offset.required16(
        view,
        0,
        try view.readU16(8),
    );
    const lookup_count = try view.readU16(lookup_list);
    var records: [model.ChainingCoverageSubtable.max_fast_records]model.FastSingleRecord =
        [_]model.FastSingleRecord{.{}} **
        model.ChainingCoverageSubtable.max_fast_records;
    for (0..subtable.subst_count) |record_index| {
        const record = subtable.records_pos + record_index * 4;
        const sequence_index = try view.readU16(record);
        if (sequence_index >= subtable.input_count) return;
        const lookup_index = try view.readU16(record + 2);
        if (lookup_index >= lookup_count) return;
        const lookup = try table.offset.required16(
            view,
            lookup_list,
            try view.readU16(
                lookup_list + 2 + @as(usize, lookup_index) * 2,
            ),
        );
        if (try view.readU16(lookup) != 1 or
            try view.readU16(lookup + 2) != 0 or
            try view.readU16(lookup + 4) != 1)
        {
            return;
        }
        const single_subtable = try table.offset.required16(
            view,
            lookup,
            try view.readU16(lookup + 6),
        );
        records[record_index] = .{
            .sequence_index = sequence_index,
            .accelerator = try single_builder.compact(view, single_subtable),
        };
        if (!records[record_index].accelerator.enabled) return;
    }
    subtable.fast_record_count = subtable.subst_count;
    subtable.fast_records = records;
}
