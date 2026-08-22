//! Staged and merged GSUB lookup-plan construction contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const fixture = @import("../validation/lookup/support.zig");
const table = @import("../../table/root.zig");
const unicode = @import("../../../unicode.zig");

test "feature plan builders preserve required stages and merge lookup scope" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    writePlanTable(&bytes);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    const applications = [_]feature.Application{.{
        .tag = unicode.tag("liga"),
        .source_scoped = true,
        .auto_zwj = false,
    }};

    var staged = try feature.plan.build.lookupPlan(
        view,
        &applications,
        allocator,
        .{ .script_tag = .dflt },
    );
    defer staged.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), staged.entries.len);
    try std.testing.expectEqual(unicode.tag("ccmp"), staged.entries[0].application.tag);
    try std.testing.expectEqualSlices(u16, &.{0}, staged.entries[0].lookups);
    try std.testing.expectEqual(unicode.tag("liga"), staged.entries[1].application.tag);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, staged.entries[1].lookups);

    var merged = try feature.plan.build.mergedPlan(
        view,
        &applications,
        allocator,
        .{ .script_tag = .dflt },
    );
    defer merged.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), merged.lookups.len);
    try std.testing.expectEqual(@as(u16, 0), merged.lookups[0].lookup);
    try std.testing.expect(merged.lookups[0].source_mask != 0);
    try std.testing.expect(!merged.lookups[0].auto_zwj);
    try std.testing.expectEqual(@as(u16, 1), merged.lookups[1].lookup);
    try std.testing.expectEqualSlices(usize, &.{ 72, 80 }, merged.lookup_offsets);
}

test "feature plans omit absent no-op stages" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    writePlanTable(&bytes);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var plan = try feature.plan.build.lookupPlan(
        view,
        &.{.{ .tag = unicode.tag("salt") }},
        allocator,
        .{ .script_tag = .dflt },
    );
    defer plan.deinit(allocator);
    // The required ccmp stage remains; absent salt contributes no empty entry.
    try std.testing.expectEqual(@as(usize, 1), plan.entries.len);
    try std.testing.expectEqual(unicode.tag("ccmp"), plan.entries[0].application.tag);
}

fn writePlanTable(bytes: []u8) void {
    fixture.writeU32(bytes, 0, 0x00010000);
    fixture.writeU16(bytes, 4, 10); // ScriptList.
    fixture.writeU16(bytes, 6, 32); // FeatureList.
    fixture.writeU16(bytes, 8, 66); // LookupList.

    fixture.writeU16(bytes, 10, 1);
    fixture.writeU32(bytes, 12, unicode.tag("DFLT"));
    fixture.writeU16(bytes, 16, 8);
    fixture.writeU16(bytes, 18, 4); // DefaultLangSys.
    fixture.writeU16(bytes, 20, 0);
    fixture.writeU16(bytes, 22, 0);
    fixture.writeU16(bytes, 24, 0); // Required ccmp feature.
    fixture.writeU16(bytes, 26, 1);
    fixture.writeU16(bytes, 28, 1); // Optional liga feature.

    fixture.writeU16(bytes, 32, 2);
    fixture.writeU32(bytes, 34, unicode.tag("ccmp"));
    fixture.writeU16(bytes, 38, 14);
    fixture.writeU32(bytes, 40, unicode.tag("liga"));
    fixture.writeU16(bytes, 44, 20);
    fixture.writeU16(bytes, 46, 0);
    fixture.writeU16(bytes, 48, 1);
    fixture.writeU16(bytes, 50, 0);
    fixture.writeU16(bytes, 52, 0);
    fixture.writeU16(bytes, 54, 2);
    fixture.writeU16(bytes, 56, 1);
    fixture.writeU16(bytes, 58, 0); // Duplicate/reordered lookup list canonicalizes.

    fixture.writeU16(bytes, 66, 2);
    fixture.writeU16(bytes, 68, 6);
    fixture.writeU16(bytes, 70, 14);
    fixture.writeU16(bytes, 72, 0);
    fixture.writeU16(bytes, 74, 0);
    fixture.writeU16(bytes, 76, 0);
    fixture.writeU16(bytes, 80, 0);
    fixture.writeU16(bytes, 82, 0);
    fixture.writeU16(bytes, 84, 0);
}
