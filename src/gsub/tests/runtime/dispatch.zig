//! GSUB lookup dispatch identity and capability contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const runtime = @import("../../runtime/root.zig");
const table = @import("../../table/root.zig");

test "cached lookup dispatch requires exact table and slice identity" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    writeSingleTable(&bytes, 7);
    const accelerators = try accelerator.build.lookup.build(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.ownership.deinit(allocator, accelerators);

    const validated = view(&bytes, true);
    const exact = runtime.dispatch.exact(
        validated,
        14,
        0,
        .{ .lookup_accelerators = accelerators },
    ) orelse return error.TestUnexpectedResult;
    const cached = try runtime.dispatch.header(validated, 14, exact);
    try std.testing.expectEqual(@as(u16, 1), cached.lookup_type);
    try std.testing.expectEqual(@as(u16, 1), cached.subtable_count);
    try std.testing.expectEqual(@as(?u16, null), cached.mark_filtering_set);

    const parsed = try runtime.dispatch.header(view(&bytes, false), 14, null);
    try std.testing.expectEqual(@as(u16, 1), parsed.lookup_type);
    try std.testing.expect(
        runtime.dispatch.exact(
            view(&bytes, false),
            14,
            0,
            .{ .lookup_accelerators = accelerators },
        ) == null,
    );

    // Identical bytes in different storage must not inherit decoded payloads.
    var foreign_bytes = bytes;
    try std.testing.expect(
        runtime.dispatch.exact(
            view(&foreign_bytes, true),
            14,
            0,
            .{ .lookup_accelerators = accelerators },
        ) == null,
    );

    // A shallow copy retains the index pointer but not the original containing
    // allocation address, so it is likewise not the built sidecar set.
    const copied = try allocator.dupe(accelerator.Lookup, accelerators);
    defer allocator.free(copied);
    try std.testing.expect(
        runtime.dispatch.exact(
            validated,
            14,
            0,
            .{ .lookup_accelerators = copied },
        ) == null,
    );
}

test "dispatch selects capabilities only from a proved lookup" {
    const entries = [_]accelerator.model.SingleEntry{
        .{ .from = 1, .to = 2 },
    };
    const multiple = [_]accelerator.model.MultipleEntry{
        .{ .glyph = 2, .sequence_offset = 8, .glyph_count = 1 },
    };
    const lookups = [_]accelerator.Lookup{
        .{
            .single_subst_entries = &entries,
            .single_subst = .{
                .enabled = true,
                .single_mapping = true,
                .single_from = 1,
                .single_to = 2,
            },
        },
        .{ .multiple_subst = .{ .entries = &multiple } },
        .{ .chaining_coverage_only = true },
    };

    try std.testing.expectEqualSlices(
        accelerator.model.SingleEntry,
        &entries,
        runtime.dispatch.singleEntries(&lookups[0]).?,
    );
    try std.testing.expect(runtime.dispatch.single(&lookups[0]) != null);
    try std.testing.expect(runtime.dispatch.single(&lookups[1]) == null);
    try std.testing.expect(
        runtime.dispatch.multiple(&lookups[1]).?.entries.ptr == multiple[0..].ptr,
    );
    try std.testing.expect(
        runtime.dispatch.chainingCoverage(&lookups[2]) != null,
    );
    try std.testing.expect(runtime.dispatch.ligature(&lookups[0]) == null);

    // Raw, hand-built sidecars cannot manufacture table identity.
    try std.testing.expect(
        runtime.dispatch.exactSidecars(
            .{
                .data = &.{},
                .offset = 0,
                .length = 0,
                .assume_validated = true,
            },
            .{ .lookup_accelerators = &lookups },
        ) == null,
    );
}

test "dispatch customization is limited to lookup-local overrides" {
    try std.testing.expect(!runtime.dispatch.needsCustomizedOptions(
        0,
        false,
        .{},
    ));
    try std.testing.expect(runtime.dispatch.needsCustomizedOptions(
        0x0010,
        false,
        .{},
    ));
    try std.testing.expect(runtime.dispatch.needsCustomizedOptions(
        0,
        true,
        .{},
    ));
    try std.testing.expect(!runtime.dispatch.needsCustomizedOptions(
        0,
        true,
        .{ .match_source_syllable = true },
    ));
}

test "dispatch derives per-lookup syllable scope" {
    try std.testing.expect(runtime.dispatch.matchesSourceSyllable(
        3,
        .{ .match_source_syllable_lookups = &.{ 1, 3 } },
    ));
    try std.testing.expect(!runtime.dispatch.matchesSourceSyllable(
        2,
        .{ .match_source_syllable_lookups = &.{ 1, 3 } },
    ));
    try std.testing.expect(runtime.dispatch.matchesSourceSyllable(
        null,
        .{ .match_source_syllable = true },
    ));
}

fn writeSingleTable(bytes: []u8, replacement: u16) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 1);
    writeU16(bytes, 12, 4);
    writeU16(bytes, 14, 1);
    writeU16(bytes, 18, 1);
    writeU16(bytes, 20, 8);
    writeU16(bytes, 22, 2);
    writeU16(bytes, 24, 8);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, replacement);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 1);
    writeU16(bytes, 34, 5);
}

fn view(bytes: []const u8, assumed: bool) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = assumed,
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
