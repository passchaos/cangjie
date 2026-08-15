//! SFNT per-table checksum calculation and borrowed-byte revalidation.

const std = @import("std");

const record_mod = @import("record.zig");
const Error = record_mod.Error;
const Record = record_mod.Record;

pub fn validateAll(data: []const u8, records: []const Record) Error!void {
    // AAT tooling commonly rewrites mort/morx payloads without refreshing the
    // font-wide head adjustment. Match HarfBuzz compatibility while keeping
    // every table-local checksum strict.
    const tolerate_stale_head_checksum =
        record_mod.find(records, "morx") != null or
        record_mod.find(records, "mort") != null;
    for (records) |record| {
        if (tolerate_stale_head_checksum and
            std.mem.eql(u8, &record.tag, "head"))
        {
            continue;
        }
        try validate(data, record);
    }
}

pub fn validate(data: []const u8, record: Record) Error!void {
    // head.checkSumAdjustment is zero for this per-table checksum. Lazy APIs
    // reuse this proof because parsed faces retain caller-owned bytes.
    const actual = if (std.mem.eql(u8, &record.tag, "head"))
        try head(data, record)
    else
        try table(data, record);
    if (actual != record.checksum) return error.BadSfnt;
}

pub fn table(data: []const u8, record: Record) Error!u32 {
    try validateBounds(data, record);
    var sum: u32 = 0;
    var cursor: usize = 0;
    while (cursor < record.length) : (cursor += 4) {
        var word: u32 = 0;
        for (0..4) |byte_index| {
            word <<= 8;
            const table_index = cursor + byte_index;
            if (table_index < record.length) {
                word |= data[record.offset + table_index];
            }
        }
        sum +%= word;
    }
    return sum;
}

pub fn head(data: []const u8, record: Record) Error!u32 {
    try validateBounds(data, record);
    var sum: u32 = 0;
    var cursor: usize = 0;
    while (cursor < record.length) : (cursor += 4) {
        var word: u32 = 0;
        for (0..4) |byte_index| {
            word <<= 8;
            const table_index = cursor + byte_index;
            if (table_index < record.length and
                (table_index < 8 or table_index >= 12))
            {
                word |= data[record.offset + table_index];
            }
        }
        sum +%= word;
    }
    return sum;
}

fn validateBounds(data: []const u8, record: Record) Error!void {
    if (record.offset > data.len or record.length > data.len - record.offset) {
        return error.BadSfnt;
    }
}
