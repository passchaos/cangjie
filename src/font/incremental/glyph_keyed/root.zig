//! Atomic application of an IFT glyph-keyed patch group.
//!
//! All patch envelopes are authenticated and Brotli payloads are decoded and
//! structurally validated before any table is reconstructed. Returned bytes
//! are a new canonical SFNT; the borrowed source face and patch buffers are
//! never modified, including on errors.

const std = @import("std");

const ift = @import("../../../opentype/ift.zig");
const brotli = @import("../brotli.zig");
const sfnt_builder = @import("../sfnt_builder.zig");
const cff = @import("cff.zig");
const glyf = @import("glyf.zig");
const gvar = @import("gvar.zig");
const payload = @import("payload.zig");
const replacements = @import("replacements.zig");

pub const Error = error{
    BadSfnt,
    IncompatiblePatch,
    EmptyPatchList,
    MissingBaseTable,
} || brotli.Error || std.mem.Allocator.Error || error{EndOfStream};

pub const Source = enum { ift, iftx };

pub const Patch = struct {
    source: Source,
    expected_compatibility_id: [16]u8,
    /// Absolute bit indexes in the source IFT/IFTX table to mark as applied.
    application_bits: []const u32 = &.{},
    data: []const u8,
};

pub const Context = struct {
    scaler: u32,
    glyph_count: usize,
    index_to_loc_format: i16,
    base_tables: []const sfnt_builder.Table,
    ift_info: ?ift.Info,
    iftx_info: ?ift.Info,
};

const Decoded = struct {
    bytes: []u8,
    view: payload.View,
};

const CffTarget = struct { tag: [4]u8, kind: cff.Kind };

pub fn applyAlloc(
    allocator: std.mem.Allocator,
    context: Context,
    patches: []const Patch,
    max_output_size: usize,
) Error![]u8 {
    if (patches.len == 0) return error.EmptyPatchList;
    if (context.glyph_count == 0) return error.BadSfnt;

    const decoded = try allocator.alloc(Decoded, patches.len);
    defer allocator.free(decoded);
    var decoded_count: usize = 0;
    defer for (decoded[0..decoded_count]) |item| allocator.free(item.bytes);

    for (patches, 0..) |patch, index| {
        const source_info = sourceInfo(context, patch.source) orelse
            return error.MissingBaseTable;
        if (!std.mem.eql(
            u8,
            &source_info.compatibility_id,
            &patch.expected_compatibility_id,
        )) return error.IncompatiblePatch;
        const envelope = try ift.glyphKeyedPatchInfo(
            patch.data,
            0,
            patch.data.len,
        );
        if (!std.mem.eql(
            u8,
            &envelope.compatibility_id,
            &patch.expected_compatibility_id,
        )) return error.IncompatiblePatch;
        if (envelope.max_uncompressed_length > max_output_size) {
            return error.BadSfnt;
        }
        const bytes = try brotli.decodeAlloc(
            allocator,
            envelope.brotli_stream,
            null,
            envelope.max_uncompressed_length,
        );
        // Publish ownership before parsing so the single cleanup path also
        // handles a malformed decompressed directory without a second
        // overlapping errdefer freeing the same allocation.
        decoded[index].bytes = bytes;
        decoded_count += 1;
        decoded[index].view = try payload.parse(bytes, envelope.flags);
    }

    const views = try allocator.alloc(payload.View, decoded.len);
    defer allocator.free(views);
    for (decoded, views) |item, *view| view.* = item.view;

    var output_tables = try allocator.dupe(sfnt_builder.Table, context.base_tables);
    defer allocator.free(output_tables);
    const owned_tables = try allocator.alloc(?[]u8, output_tables.len);
    defer {
        for (owned_tables) |maybe| if (maybe) |bytes| allocator.free(bytes);
        allocator.free(owned_tables);
    }
    @memset(owned_tables, null);

    // Only the four glyph-indexed table families defined by IFT are rebuilt.
    // Unknown tags in a payload are intentionally ignored like Fontations.
    if (containsTable(views, "glyf".*)) {
        const glyf_index = tableIndex(output_tables, "glyf".*) orelse
            return error.MissingBaseTable;
        const loca_index = tableIndex(output_tables, "loca".*) orelse
            return error.MissingBaseTable;
        const merged = try replacements.collect(
            allocator,
            views,
            "glyf".*,
            context.glyph_count,
        );
        defer allocator.free(merged);
        const rebuilt = try glyf.apply(
            allocator,
            output_tables[glyf_index].data,
            output_tables[loca_index].data,
            context.index_to_loc_format,
            merged,
            max_output_size,
        );
        owned_tables[glyf_index] = rebuilt.glyf;
        owned_tables[loca_index] = rebuilt.loca;
        output_tables[glyf_index].data = rebuilt.glyf;
        output_tables[loca_index].data = rebuilt.loca;
    }
    if (containsTable(views, "gvar".*)) {
        const index = tableIndex(output_tables, "gvar".*) orelse
            return error.MissingBaseTable;
        const merged = try replacements.collect(
            allocator,
            views,
            "gvar".*,
            context.glyph_count,
        );
        defer allocator.free(merged);
        const rebuilt = try gvar.apply(
            allocator,
            output_tables[index].data,
            context.glyph_count,
            merged,
            max_output_size,
        );
        owned_tables[index] = rebuilt;
        output_tables[index].data = rebuilt;
    }
    inline for ([_]CffTarget{
        .{ .tag = "CFF ".*, .kind = .cff },
        .{ .tag = "CFF2".*, .kind = .cff2 },
    }) |entry| {
        if (containsTable(views, entry.tag)) {
            const index = tableIndex(output_tables, entry.tag) orelse
                return error.MissingBaseTable;
            const primary = context.ift_info orelse return error.MissingBaseTable;
            const charstrings_offset = switch (entry.kind) {
                .cff => primary.cff_charstrings_offset,
                .cff2 => primary.cff2_charstrings_offset,
            } orelse return error.BadSfnt;
            const merged = try replacements.collect(
                allocator,
                views,
                entry.tag,
                context.glyph_count,
            );
            defer allocator.free(merged);
            const rebuilt = try cff.apply(
                allocator,
                output_tables[index].data,
                charstrings_offset,
                context.glyph_count,
                merged,
                entry.kind,
                max_output_size,
            );
            owned_tables[index] = rebuilt;
            output_tables[index].data = rebuilt;
        }
    }

    // Application bits are committed only after every glyph table has been
    // reconstructed successfully, preserving group-level atomicity.
    for (patches) |patch| {
        const tag: [4]u8 = if (patch.source == .ift) "IFT ".* else "IFTX".*;
        const index = tableIndex(output_tables, tag) orelse
            return error.MissingBaseTable;
        if (owned_tables[index] == null) {
            const copy = try allocator.dupe(u8, output_tables[index].data);
            owned_tables[index] = copy;
            output_tables[index].data = copy;
        }
        const mutable = owned_tables[index].?;
        for (patch.application_bits) |bit| {
            const byte_index: usize = bit / 8;
            if (byte_index >= mutable.len) return error.BadSfnt;
            mutable[byte_index] |= @as(u8, 1) << @intCast(bit % 8);
        }
    }

    return sfnt_builder.build(
        allocator,
        context.scaler,
        output_tables,
        max_output_size,
    );
}

test "glyph keyed gvar rebuild retains shared tuples and patches data" {
    const allocator = std.testing.allocator;
    // Two glyphs, short offsets {0, 4, 4}; one two-byte shared tuple.
    var table: [32]u8 = .{0} ** 32;
    std.mem.writeInt(u16, table[0..2], 1, .big);
    std.mem.writeInt(u16, table[4..6], 1, .big);
    std.mem.writeInt(u16, table[6..8], 1, .big);
    std.mem.writeInt(u32, table[8..12], 26, .big);
    std.mem.writeInt(u16, table[12..14], 2, .big);
    std.mem.writeInt(u32, table[16..20], 28, .big);
    std.mem.writeInt(u16, table[20..22], 0, .big);
    std.mem.writeInt(u16, table[22..24], 2, .big);
    std.mem.writeInt(u16, table[24..26], 2, .big);
    table[26] = 0x12;
    table[27] = 0x34;
    @memcpy(table[28..32], "base");
    const replacement = "xyz";
    const merged = [_]?[]const u8{ null, replacement };
    const rebuilt = try gvar.apply(allocator, &table, 2, &merged, 1024);
    defer allocator.free(rebuilt);
    try std.testing.expectEqual(@as(u32, 28), std.mem.readInt(u32, rebuilt[16..20], .big));
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34 }, rebuilt[26..28]);
    try std.testing.expectEqualStrings("basexyz\x00", rebuilt[28..]);
}

test "glyph keyed CFF and CFF2 rebuild terminal CharStrings indexes" {
    const allocator = std.testing.allocator;
    const replacement = "long";
    const merged = [_]?[]const u8{ null, replacement };

    const cff_table = [_]u8{ 0xaa, 0xbb, 0, 2, 1, 1, 2, 3, 'a', 'b' };
    const cff_rebuilt = try cff.apply(
        allocator,
        &cff_table,
        2,
        2,
        &merged,
        .cff,
        1024,
    );
    defer allocator.free(cff_rebuilt);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xaa, 0xbb, 0, 2, 1, 1, 2, 6, 'a', 'l', 'o', 'n', 'g' },
        cff_rebuilt,
    );

    const cff2_table = [_]u8{ 0xcc, 0, 0, 0, 2, 1, 1, 2, 3, 'a', 'b' };
    const cff2_rebuilt = try cff.apply(
        allocator,
        &cff2_table,
        1,
        2,
        &merged,
        .cff2,
        1024,
    );
    defer allocator.free(cff2_rebuilt);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xcc, 0, 0, 0, 2, 1, 1, 2, 6, 'a', 'l', 'o', 'n', 'g' },
        cff2_rebuilt,
    );
}

fn sourceInfo(context: Context, source: Source) ?ift.Info {
    return if (source == .ift) context.ift_info else context.iftx_info;
}

fn tableIndex(tables: []const sfnt_builder.Table, tag: [4]u8) ?usize {
    for (tables, 0..) |table, index| {
        if (std.mem.eql(u8, &table.tag, &tag)) return index;
    }
    return null;
}

fn containsTable(views: []const payload.View, tag: [4]u8) bool {
    for (views) |view| for (0..view.table_count) |index| {
        const candidate = view.tableTag(index) catch return false;
        if (std.mem.eql(u8, &candidate, &tag)) return true;
    };
    return false;
}
