//! Cached GSUB FeatureList lookup index and identity proof.
//!
//! The index owns canonical lookup slices but borrows the font bytes and its
//! containing lookup-accelerator slice. Every trusted query rechecks both
//! identities so copied or foreign sidecars fall back to defensive parsing.

const std = @import("std");
const feature_selection = @import("../feature/selection.zig");
const model = @import("model.zig");
const table = @import("../table/root.zig");
const unicode = @import("../../unicode.zig");

pub const Error = table.view.Error;
pub const View = table.View;
pub const Index = model.FeatureIndex;
pub const Lookup = model.Lookup;
pub const Record = model.FeatureRecord;

pub const Data = struct {
    has_random_feature: bool,
    records: []Record,
    lookups: []u16,

    pub fn deinit(self: *Data, allocator: std.mem.Allocator) void {
        allocator.free(self.records);
        allocator.free(self.lookups);
        self.* = .{
            .has_random_feature = false,
            .records = &.{},
            .lookups = &.{},
        };
    }
};

pub fn build(
    view: View,
    lookup_count: u16,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Data {
    const feature_list_offset = try table.offset.required16(
        view,
        0,
        try view.readU16(6),
    );
    const feature_count = try view.readU16(feature_list_offset);
    try view.ensure(feature_list_offset + 2, @as(usize, feature_count) * 6);
    const records = try allocator.alloc(Record, feature_count);
    errdefer allocator.free(records);
    var lookups = std.ArrayList(u16).empty;
    errdefer lookups.deinit(allocator);
    var has_random_feature = false;

    for (records, 0..) |*record, feature_index| {
        const feature_record = feature_list_offset + 2 + feature_index * 6;
        const tag = try view.readU32(feature_record);
        has_random_feature = has_random_feature or tag == unicode.tag("rand");
        const feature_offset = try table.offset.required16(
            view,
            feature_list_offset,
            try view.readU16(feature_record + 4),
        );
        try view.ensure(feature_offset, 4);
        const lookup_len = try view.readU16(feature_offset + 2);
        try view.ensure(feature_offset + 4, @as(usize, lookup_len) * 2);
        const lookup_start = lookups.items.len;
        try lookups.ensureUnusedCapacity(allocator, lookup_len);
        var previous_lookup: ?u16 = null;
        var borrowable = true;
        for (0..lookup_len) |lookup_index| {
            const lookup = try view.readU16(
                feature_offset + 4 + lookup_index * 2,
            );
            if (lookup >= lookup_count) return error.BadGsub;
            if (previous_lookup) |previous| {
                // The owned fallback sorts and deduplicates arbitrary producer
                // output. Borrow only when this record is already canonical.
                if (lookup <= previous) borrowable = false;
            }
            previous_lookup = lookup;
            lookups.appendAssumeCapacity(lookup);
        }
        record.* = .{
            .tag = tag,
            .lookup_start = lookup_start,
            .lookup_len = lookup_len,
            .borrowable = borrowable,
        };
    }
    return .{
        .has_random_feature = has_random_feature,
        .records = records,
        .lookups = try lookups.toOwnedSlice(allocator),
    };
}

pub fn create(
    view: View,
    accelerators: []const Lookup,
    lookup_count: u16,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!*Index {
    var data = try build(view, lookup_count, allocator);
    errdefer data.deinit(allocator);
    const index = try allocator.create(Index);
    index.* = .{
        .data_ptr = view.data.ptr,
        .data_len = view.data.len,
        .table_offset = view.offset,
        .table_length = view.length,
        .accelerators_addr = @intFromPtr(accelerators.ptr),
        .accelerator_count = accelerators.len,
        .has_random_feature = data.has_random_feature,
        .records = data.records,
        .lookups = data.lookups,
    };
    return index;
}

pub fn destroy(index: *const Index, allocator: std.mem.Allocator) void {
    allocator.free(index.records);
    allocator.free(index.lookups);
    allocator.destroy(@constCast(index));
}

pub fn exact(
    data: []const u8,
    offset: usize,
    length: usize,
    accelerators: []const Lookup,
) ?*const Index {
    if (accelerators.len == 0) return null;
    const index = accelerators[0].feature_index orelse return null;
    if (index.data_ptr != data.ptr or
        index.data_len != data.len or
        index.table_offset != offset or
        index.table_length != length or
        index.accelerators_addr != @intFromPtr(accelerators.ptr) or
        index.accelerator_count != accelerators.len)
    {
        return null;
    }
    return index;
}

/// Return the cached `rand` capability, or `null` when identity is unproved.
pub fn hasRandomFeature(
    data: []const u8,
    offset: usize,
    length: usize,
    accelerators: []const Lookup,
) ?bool {
    const index = exact(data, offset, length, accelerators) orelse return null;
    return index.has_random_feature;
}

/// Borrow one already-canonical feature lookup slice.
///
/// Multiple active FeatureRecords with one tag require the fallback's
/// union/sort/dedup behavior and therefore deliberately return `null`.
pub fn selectedLookups(
    index: *const Index,
    feature_tag: u32,
    feature_indices: []const feature_selection.Item,
    feature_count: usize,
) ?[]const u16 {
    if (index.records.len != feature_count) return null;
    var matched_record: ?Record = null;
    for (feature_indices) |selection| {
        if (selection.index >= feature_count) continue;
        const record = index.records[selection.index];
        if (record.tag != feature_tag) continue;
        if (matched_record != null or !record.borrowable) return null;
        matched_record = record;
    }
    const record = matched_record orelse return &.{};
    if (record.lookup_start > index.lookups.len or
        record.lookup_len > index.lookups.len - record.lookup_start)
    {
        return null;
    }
    return index.lookups[record.lookup_start .. record.lookup_start + record.lookup_len];
}
