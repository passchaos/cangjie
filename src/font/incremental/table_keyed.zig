//! Table-keyed Incremental Font Transfer patch application.

const std = @import("std");

const bin = @import("../../binary.zig");
const brotli = @import("brotli.zig");
const sfnt_builder = @import("sfnt_builder.zig");

pub const Error = error{
    BadSfnt,
    IncompatiblePatch,
    MissingBaseTable,
} || brotli.Error || std.mem.Allocator.Error || error{EndOfStream};

pub const Table = struct { tag: [4]u8, data: []const u8 };

pub fn applyAlloc(
    allocator: std.mem.Allocator,
    scaler: u32,
    base_tables: []const Table,
    expected_compatibility_id: [16]u8,
    patch_data: []const u8,
    max_output_size: usize,
) Error![]u8 {
    if (patch_data.len < 30 or
        !std.mem.eql(u8, patch_data[0..4], "iftk") or
        try bin.readU32At(patch_data, 4) != 0)
    {
        return error.BadSfnt;
    }
    if (!std.mem.eql(
        u8,
        patch_data[8..24],
        &expected_compatibility_id,
    )) return error.IncompatiblePatch;
    const patch_count: usize = try bin.readU16At(patch_data, 24);
    const offset_count = std.math.add(usize, patch_count, 1) catch
        return error.BadSfnt;
    const offsets_bytes = std.math.mul(usize, offset_count, 4) catch
        return error.BadSfnt;
    const payload_start = std.math.add(usize, 26, offsets_bytes) catch
        return error.BadSfnt;
    if (payload_start > patch_data.len) return error.BadSfnt;

    var output_tables = std.ArrayList(sfnt_builder.Table).empty;
    defer output_tables.deinit(allocator);
    try output_tables.ensureTotalCapacity(allocator, base_tables.len + patch_count);
    for (base_tables) |table| output_tables.appendAssumeCapacity(.{
        .tag = table.tag,
        .data = table.data,
    });
    var owned = std.ArrayList([]u8).empty;
    defer {
        for (owned.items) |bytes| allocator.free(bytes);
        owned.deinit(allocator);
    }
    var processed = std.ArrayList([4]u8).empty;
    defer processed.deinit(allocator);

    var previous_offset: usize = 0;
    for (0..offset_count) |index| {
        const current: usize = try bin.readU32At(patch_data, 26 + index * 4);
        if ((patch_count == 0 and current != 0) or
            (patch_count != 0 and current < payload_start) or
            current > patch_data.len or
            (index != 0 and current < previous_offset))
        {
            return error.BadSfnt;
        }
        previous_offset = current;
    }
    for (0..patch_count) |patch_index| {
        const start: usize = try bin.readU32At(patch_data, 26 + patch_index * 4);
        const end: usize = try bin.readU32At(patch_data, 26 + (patch_index + 1) * 4);
        if (end < start or end - start < 9) return error.BadSfnt;
        const tag = try bin.readTagAt(patch_data, start);
        const flags = patch_data[start + 4];
        if ((flags & ~@as(u8, 0x03)) != 0) return error.BadSfnt;
        const max_length: usize = try bin.readU32At(patch_data, start + 5);
        if (max_length > max_output_size) return error.BadSfnt;
        if (containsTag(processed.items, tag)) continue;
        try processed.append(allocator, tag);

        if ((flags & 0x02) != 0) {
            removeTable(&output_tables, tag);
            continue;
        }
        const replacement = (flags & 0x01) != 0;
        const dictionary = if (!replacement)
            tableData(output_tables.items, tag) orelse
                return error.MissingBaseTable
        else
            null;
        const decoded = try brotli.decodeAlloc(
            allocator,
            patch_data[start + 9 .. end],
            dictionary,
            max_length,
        );
        try owned.append(allocator, decoded);
        removeTable(&output_tables, tag);
        try output_tables.append(allocator, .{ .tag = tag, .data = decoded });
    }
    return sfnt_builder.build(
        allocator,
        scaler,
        output_tables.items,
        max_output_size,
    );
}

fn containsTag(tags: []const [4]u8, tag: [4]u8) bool {
    for (tags) |candidate| if (std.mem.eql(u8, &candidate, &tag)) return true;
    return false;
}

fn tableData(tables: []const sfnt_builder.Table, tag: [4]u8) ?[]const u8 {
    for (tables) |table| if (std.mem.eql(u8, &table.tag, &tag)) return table.data;
    return null;
}

fn removeTable(tables: *std.ArrayList(sfnt_builder.Table), tag: [4]u8) void {
    for (tables.items, 0..) |table, index| {
        if (!std.mem.eql(u8, &table.tag, &tag)) continue;
        _ = tables.swapRemove(index);
        return;
    }
}
