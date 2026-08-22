//! GSUB lookup dispatch identity and capability contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const runtime = @import("../../runtime/root.zig");
const table = @import("../../table/root.zig");

test "cached lookup dispatch requires validated matching metadata" {
    var bytes = [_]u8{0} ** 12;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0x0010);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 0xffff);

    const accelerators = [_]accelerator.Lookup{.{
        .lookup_offset = 0,
        .lookup_type = 7,
        .lookup_flag = 0,
        .subtable_count = 3,
        .mark_filtering_set = 9,
    }};
    const validated = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const cached = try runtime.dispatch.header(
        validated,
        0,
        0,
        .{ .lookup_accelerators = &accelerators },
    );
    try std.testing.expectEqual(@as(u16, 7), cached.lookup_type);
    try std.testing.expectEqual(@as(u16, 3), cached.subtable_count);
    try std.testing.expectEqual(@as(?u16, 9), cached.mark_filtering_set);
    try std.testing.expect(
        runtime.dispatch.exact(
            validated,
            0,
            0,
            .{ .lookup_accelerators = &accelerators },
        ) != null,
    );

    const parsed = try runtime.dispatch.header(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, 0, 0, .{ .lookup_accelerators = &accelerators });
    try std.testing.expectEqual(@as(u16, 1), parsed.lookup_type);
    try std.testing.expectEqual(@as(u16, 0x0010), parsed.lookup_flag);
    try std.testing.expectEqual(@as(?u16, 0xffff), parsed.mark_filtering_set);
    try std.testing.expect(
        runtime.dispatch.exact(
            .{ .data = &bytes, .offset = 0, .length = bytes.len },
            0,
            0,
            .{ .lookup_accelerators = &accelerators },
        ) == null,
    );

    var stale = accelerators;
    stale[0].lookup_offset = 2;
    const fallback = try runtime.dispatch.header(
        validated,
        0,
        0,
        .{ .lookup_accelerators = &stale },
    );
    try std.testing.expectEqual(@as(u16, 1), fallback.lookup_type);
    try std.testing.expect(
        runtime.dispatch.exact(
            validated,
            0,
            0,
            .{ .lookup_accelerators = &stale },
        ) == null,
    );
}

test "dispatch selects only populated accelerator capabilities" {
    const entries = [_]accelerator.model.SingleEntry{
        .{ .from = 1, .to = 2 },
    };
    const multiple = [_]accelerator.model.MultipleEntry{
        .{ .glyph = 2, .sequence_offset = 8, .glyph_count = 1 },
    };
    const lookups = [_]accelerator.Lookup{
        .{ .single_subst_entries = &entries },
        .{ .multiple_subst = .{ .entries = &multiple } },
        .{ .chaining_coverage_only = true },
    };
    const run: runtime.Options = .{ .lookup_accelerators = &lookups };

    try std.testing.expectEqualSlices(
        accelerator.model.SingleEntry,
        &entries,
        runtime.dispatch.singleEntries(0, run).?,
    );
    try std.testing.expect(
        runtime.dispatch.multiple(1, run).?.entries.ptr == multiple[0..].ptr,
    );
    try std.testing.expect(runtime.dispatch.chainingCoverage(2, run) != null);
    try std.testing.expect(runtime.dispatch.ligature(0, run) == null);
    try std.testing.expect(runtime.dispatch.any(99, run) == null);
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

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
