//! HVAR/VVAR/MVAR ItemVariationStore and index-map ownership validation.

const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const common = @import("../../../../opentype/variation/root.zig");
const mvar = @import("../../../../opentype/mvar.zig");

const delta_map = common.delta_set_index_map;
const item_store = common.item_store;

pub const Error = sfnt.Error || error{EndOfStream} ||
    @import("std").mem.Allocator.Error;

pub fn validateHvar(
    data: []const u8,
    table: sfnt.Record,
    axis_count: usize,
) Error!void {
    try validateMetric(data, table, axis_count, 20);
}

pub fn validateVvar(
    data: []const u8,
    table: sfnt.Record,
    axis_count: usize,
) Error!void {
    try validateMetric(data, table, axis_count, 24);
}

pub fn validateMvar(
    data: []const u8,
    table: sfnt.Record,
    axis_count: usize,
) Error!void {
    const header = try mvar.header(data, table.offset, table.length);
    try mvar.validateValueRecords(data, table.offset, header);
    if (header.value_record_count == 0) return;
    const store_offset =
        header.item_variation_store_offset orelse return error.BadSfnt;
    const store = try item_store.validate(
        data,
        variationTable(table),
        store_offset,
        axis_count,
        header.records_end,
    );
    for (0..header.value_record_count) |index| {
        const record = try mvar.valueRecordAt(data, table.offset, header, index);
        if (!record.hasVariationData()) continue;
        const outer: usize = record.delta_set_outer_index;
        const inner: usize = record.delta_set_inner_index;
        if (outer >= store.item_data_count or
            inner >= try item_store.itemCount(
                data,
                variationTable(table),
                store_offset,
                outer,
            ))
        {
            return error.BadSfnt;
        }
    }
}

fn validateMetric(
    data: []const u8,
    table: sfnt.Record,
    axis_count: usize,
    minimum_length: usize,
) Error!void {
    if (table.offset > data.len or table.length > data.len - table.offset or
        table.length < minimum_length)
    {
        return error.BadSfnt;
    }
    const major = try bin.readU16At(data, table.offset);
    const minor = try bin.readU16At(data, table.offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const store_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 4));
    const store = try item_store.validate(
        data,
        variationTable(table),
        store_offset,
        axis_count,
        minimum_length,
    );

    var ranges: [5]item_store.Range = undefined;
    var range_count: usize = 1;
    ranges[0] = .{ .start = store_offset, .end = store.end_offset };
    const map_count: usize = if (minimum_length == 24) 4 else 3;
    for (0..map_count) |index| {
        const map_offset: usize = @intCast(try bin.readU32At(
            data,
            table.offset + 8 + index * 4,
        ));
        if (map_offset == 0) continue;
        const map = try validateMap(
            data,
            table,
            store_offset,
            store.item_data_count,
            map_offset,
            minimum_length,
        );
        const range = item_store.Range{
            .start = map.offset,
            .end = map.end_offset,
        };
        var already_owned = false;
        for (ranges[0..range_count]) |previous| {
            // Real fonts may reuse the exact same map for multiple metric
            // fields; partial overlap still creates incompatible ownership.
            if (item_store.rangesEqual(range, previous)) {
                already_owned = true;
                break;
            }
            if (item_store.rangesOverlap(range, previous)) return error.BadSfnt;
        }
        if (already_owned) continue;
        ranges[range_count] = range;
        range_count += 1;
    }
}

fn validateMap(
    data: []const u8,
    table: sfnt.Record,
    store_offset: usize,
    item_data_count: usize,
    map_offset: usize,
    minimum_length: usize,
) Error!delta_map.Map {
    const map = try delta_map.read(
        data,
        variationTable(table),
        map_offset,
        minimum_length,
    );
    for (0..map.map_count) |index| {
        const entry = try delta_map.entry(data, map, index);
        if (entry.outer == 0xffff and entry.inner == 0xffff) continue;
        if (entry.outer >= item_data_count or
            entry.inner >= try item_store.itemCount(
                data,
                variationTable(table),
                store_offset,
                entry.outer,
            ))
        {
            return error.BadSfnt;
        }
    }
    return map;
}

fn variationTable(record: sfnt.Record) delta_map.Table {
    return .{ .offset = record.offset, .length = record.length };
}
