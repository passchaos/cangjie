//! Mandatory top-level GPOS offset contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const runtime_run = @import("../../../runtime/run.zig");
const table = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");

test "font validation rejects null top-level LookupList offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 36);
    fixture.writeU16(&bytes, 6, 38);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);
    fixture.writeSinglePositionLookup(&bytes, 14, 1, 0, 20);
    fixture.writeU16(&bytes, 36, 0);
    fixture.writeU16(&bytes, 38, 0);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(runtime_run.Adjustment).empty;
    defer adjustments.deinit(allocator);

    fixture.writeU16(&bytes, 8, 0);
    try std.testing.expectError(
        error.BadGpos,
        validation.font.requiredLookupList(view),
    );
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );
    try std.testing.expectError(
        error.BadGpos,
        runtime_run.collect(
            &bytes,
            0,
            bytes.len,
            &.{1},
            &adjustments,
            allocator,
            .{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    fixture.writeU16(&bytes, 8, 10);
    try validation.font.glyphBounds(&bytes, 0, bytes.len, 4);
    try runtime_run.collect(
        &bytes,
        0,
        bytes.len,
        &.{1},
        &adjustments,
        allocator,
        .{},
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[0].x_placement);
}

test "font validation rejects null ScriptList and FeatureList offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 36);
    fixture.writeU16(&bytes, 6, 38);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);
    fixture.writeSinglePositionLookup(&bytes, 14, 1, 0, 20);
    fixture.writeU16(&bytes, 36, 0);
    fixture.writeU16(&bytes, 38, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(runtime_run.Adjustment).empty;
    defer adjustments.deinit(allocator);

    fixture.writeU16(&bytes, 4, 0);
    try std.testing.expectError(
        error.BadGpos,
        validation.font.requiredTopLevelOffset(view, 4),
    );
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );
    try std.testing.expectError(
        error.BadGpos,
        runtime_run.collect(
            &bytes,
            0,
            bytes.len,
            &.{1},
            &adjustments,
            allocator,
            .{},
        ),
    );

    fixture.writeU16(&bytes, 4, 36);
    fixture.writeU16(&bytes, 6, 0);
    try std.testing.expectError(
        error.BadGpos,
        validation.font.requiredTopLevelOffset(view, 6),
    );
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );
    try std.testing.expectError(
        error.BadGpos,
        runtime_run.collect(
            &bytes,
            0,
            bytes.len,
            &.{1},
            &adjustments,
            allocator,
            .{},
        ),
    );

    fixture.writeU16(&bytes, 6, 38);
    try validation.font.glyphBounds(&bytes, 0, bytes.len, 4);
    try runtime_run.collect(
        &bytes,
        0,
        bytes.len,
        &.{1},
        &adjustments,
        allocator,
        .{},
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
}
