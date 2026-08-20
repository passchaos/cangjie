//! Whole-table GSUB lookup accelerator orchestration contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const ownership = @import("../../../accelerator/ownership.zig");
const table = @import("../../../table/root.zig");

test "lookup builder records dispatch fields and direct substitution sidecars" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 44;
    writeHeaderAndLookupList(&bytes, 14, 1);
    const lookup = 14;
    writeU16(&bytes, lookup, 1);
    writeU16(&bytes, lookup + 2, 0x0010);
    writeU16(&bytes, lookup + 4, 1);
    writeU16(&bytes, lookup + 6, 10);
    writeU16(&bytes, lookup + 8, 3);
    const single = lookup + 10;
    writeU16(&bytes, single, 1);
    writeU16(&bytes, single + 2, 6);
    writeI16(&bytes, single + 4, 2);
    writeCoverage1(&bytes, single + 6, 5);

    const lookups = try build.lookup.build(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer ownership.deinit(allocator, lookups);
    try std.testing.expectEqual(@as(usize, 1), lookups.len);
    try std.testing.expectEqual(@as(usize, lookup), lookups[0].lookup_offset);
    try std.testing.expectEqual(@as(u16, 1), lookups[0].lookup_type);
    try std.testing.expectEqual(@as(u16, 0x0010), lookups[0].lookup_flag);
    try std.testing.expectEqual(@as(?u16, 3), lookups[0].mark_filtering_set);
    try std.testing.expectEqual(@as(usize, 1), lookups[0].single_subst_entries.len);
    try std.testing.expectEqual(@as(u16, 5), lookups[0].single_subst_entries[0].from);
    try std.testing.expectEqual(@as(u16, 7), lookups[0].single_subst_entries[0].to);
    // Mark-filtering lookup flags intentionally disable the flag-free compact
    // fast path while retaining the exact sorted entry sidecar.
    try std.testing.expect(!lookups[0].single_subst.enabled);
}

test "lookup builder derives table-wide digest policy and feature index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;
    writeU32(&bytes, 0, 0x00010000);
    writeU16(&bytes, 4, 0);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 28);

    // One canonical `rand` FeatureRecord references lookup zero.
    writeU16(&bytes, 10, 1);
    writeU32(&bytes, 12, 0x72616e64);
    writeU16(&bytes, 16, 8);
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 20, 1);
    writeU16(&bytes, 22, 0);

    writeU16(&bytes, 28, 2);
    writeU16(&bytes, 30, 6);
    writeU16(&bytes, 32, 14);
    writeLigatureLookup(&bytes, 34, 16, 1, 2, 10);
    writeLigatureLookup(&bytes, 42, 36, 3, 4, 11);

    const lookups = try build.lookup.build(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer ownership.deinit(allocator, lookups);
    try std.testing.expectEqual(@as(usize, 2), lookups.len);
    try std.testing.expect(lookups[0].table_uses_run_digest_cache);
    try std.testing.expect(lookups[0].feature_index != null);
    try std.testing.expect(lookups[0].feature_index.?.has_random_feature);
    try std.testing.expect(lookups[1].feature_index == null);
}

test "lookup builder releases partial table ownership on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildTwoLookups,
        .{},
    );
}

test "extension reverse lookup releases every nested allocation on failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildExtensionReverse,
        .{},
    );
}

test "lookup header proof rejects reserved flags and truncated mark filters" {
    var bytes = [_]u8{0} ** 12;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0x0020);
    writeU16(&bytes, 4, 0);
    const view = table.View{ .data = &bytes, .offset = 0, .length = 10 };
    try std.testing.expectError(
        error.BadGsub,
        build.lookup.header.validate(view, 0),
    );

    writeU16(&bytes, 2, 0x0010);
    writeU16(&bytes, 4, 2);
    try std.testing.expectError(
        error.BadGsub,
        build.lookup.header.validate(view, 0),
    );
}

test "extension lookup kind proof handles homogeneous mixed and recursive wrappers" {
    var bytes = [_]u8{0} ** 30;
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 18);
    writeExtensionWrapper(&bytes, 10, 1, 8);
    writeExtensionWrapper(&bytes, 18, 1, 8);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(?u16, 1),
        try build.lookup.extension.commonType(view, 0, 2),
    );

    writeU16(&bytes, 20, 2);
    try std.testing.expectEqual(
        @as(?u16, null),
        try build.lookup.extension.commonType(view, 0, 2),
    );
    writeU16(&bytes, 20, 7);
    try std.testing.expectError(
        error.UnsupportedGsub,
        build.lookup.extension.commonType(view, 0, 2),
    );
}

fn buildTwoLookups(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0} ** 80;
    writeU32(&bytes, 0, 0x00010000);
    writeU16(&bytes, 8, 10);
    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 12, 6);
    writeU16(&bytes, 14, 30);
    writeSingleLookup(&bytes, 16, 1, 2);
    writeSingleLookup(&bytes, 40, 3, 4);
    const lookups = try build.lookup.build(&bytes, 0, bytes.len, allocator);
    defer ownership.deinit(allocator, lookups);
    try std.testing.expectEqual(@as(usize, 2), lookups.len);
}

fn buildExtensionReverse(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0} ** 64;
    writeU16(&bytes, 0, 7);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeExtensionWrapper(&bytes, 8, 8, 8);
    const reverse = 16;
    writeU16(&bytes, reverse, 1);
    writeU16(&bytes, reverse + 2, 18);
    writeU16(&bytes, reverse + 4, 1);
    writeU16(&bytes, reverse + 6, 24);
    writeU16(&bytes, reverse + 8, 2);
    writeU16(&bytes, reverse + 10, 30);
    writeU16(&bytes, reverse + 12, 36);
    writeU16(&bytes, reverse + 14, 1);
    writeU16(&bytes, reverse + 16, 9);
    writeCoverage1(&bytes, reverse + 18, 2);
    writeCoverage1(&bytes, reverse + 24, 1);
    writeCoverage1(&bytes, reverse + 30, 3);
    writeCoverage1(&bytes, reverse + 36, 4);

    const lookup = try build.lookup.one(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer {
        const lookups = [_]@import(
            "../../../accelerator/model.zig",
        ).Lookup{lookup};
        ownership.deinitContents(allocator, &lookups);
    }
    try std.testing.expectEqual(
        @as(usize, 1),
        lookup.reverse_chaining_exact_contexts.len,
    );
}

fn writeHeaderAndLookupList(
    bytes: []u8,
    lookup_offset: u16,
    lookup_count: u16,
) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, lookup_count);
    writeU16(bytes, 12, lookup_offset - 10);
}

fn writeSingleLookup(
    bytes: []u8,
    lookup: usize,
    glyph: u16,
    replacement: u16,
) void {
    writeU16(bytes, lookup, 1);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const single = lookup + 8;
    writeU16(bytes, single, 2);
    writeU16(bytes, single + 2, 8);
    writeU16(bytes, single + 4, 1);
    writeU16(bytes, single + 6, replacement);
    writeCoverage1(bytes, single + 8, glyph);
}

fn writeLigatureLookup(
    bytes: []u8,
    lookup: usize,
    subtable_relative: u16,
    first: u16,
    second: u16,
    result: u16,
) void {
    writeU16(bytes, lookup, 4);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, subtable_relative);
    const subtable = lookup + subtable_relative;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 8);
    writeU16(bytes, subtable + 4, 1);
    writeU16(bytes, subtable + 6, 14);
    writeCoverage1(bytes, subtable + 8, first);
    writeU16(bytes, subtable + 14, 1);
    writeU16(bytes, subtable + 16, 4);
    writeU16(bytes, subtable + 18, result);
    writeU16(bytes, subtable + 20, 2);
    writeU16(bytes, subtable + 22, second);
}

fn writeExtensionWrapper(
    bytes: []u8,
    offset: usize,
    wrapped_type: u16,
    payload_relative: u32,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, wrapped_type);
    writeU32(bytes, offset + 4, payload_relative);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
