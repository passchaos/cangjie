//! Lookup header and required-child offset contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const lookup_dispatch = @import("../../../positioning/lookup/dispatch.zig");
const lookup_dispatcher =
    @import("../../../runtime/lookup/dispatcher/root.zig");
const runtime_run = @import("../../../runtime/run.zig");
const single = @import("../../../positioning/lookup/single.zig");
const single_runtime = @import("../../../runtime/lookup/single.zig");
const table = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");

test "font validation rejects reserved LookupFlag bits" {
    var bytes = [_]u8{0} ** 42;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 38);
    fixture.writeU16(&bytes, 6, 40);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 16, 0x0020);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 10);
    const subtable: usize = 24;
    fixture.writeU16(&bytes, subtable, 1);
    fixture.writeU16(&bytes, subtable + 2, 8);
    fixture.writeU16(&bytes, subtable + 4, 0x0004);
    fixture.writeI16(&bytes, subtable + 6, 20);
    fixture.writeCoverage1(&bytes, subtable + 8, 1);
    fixture.writeU16(&bytes, 38, 0);
    fixture.writeU16(&bytes, 40, 0);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectError(
        error.BadGpos,
        lookup_dispatch.validateHeader(view, 14),
    );
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );

    fixture.writeU16(&bytes, 16, 0xff10);
    fixture.writeU16(&bytes, 22, 0);
    try lookup_dispatch.validateHeader(view, 14);
    try validation.font.glyphBounds(&bytes, 0, bytes.len, 4);
}

test "font validation rejects null LookupList child offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 38);
    fixture.writeU16(&bytes, 6, 40);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 0);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 16, 8);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 8);
    fixture.writeU16(&bytes, 22, 0x0001);
    fixture.writeI16(&bytes, 24, 20);
    fixture.writeCoverage1(&bytes, 26, 1);
    fixture.writeU16(&bytes, 38, 0);
    fixture.writeU16(&bytes, 40, 0);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectError(
        error.BadGpos,
        validation.font.requiredLookupOffset(view, 10, 0),
    );
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );

    var adjustments = std.ArrayList(runtime_run.Adjustment).empty;
    defer adjustments.deinit(allocator);
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

    @memset(&bytes, 0);
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 38);
    fixture.writeU16(&bytes, 6, 40);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);
    fixture.writeSinglePositionLookup(&bytes, 14, 1, 0, 20);
    fixture.writeU16(&bytes, 38, 0);
    fixture.writeU16(&bytes, 40, 0);
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

test "font validation rejects null Lookup SubTable offsets" {
    var bytes = [_]u8{0} ** 42;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 38);
    fixture.writeU16(&bytes, 6, 40);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 0);
    const subtable: usize = 24;
    fixture.writeU16(&bytes, subtable, 1);
    fixture.writeU16(&bytes, subtable + 2, 8);
    fixture.writeU16(&bytes, subtable + 4, 0x0001);
    fixture.writeI16(&bytes, subtable + 6, 20);
    fixture.writeCoverage1(&bytes, subtable + 8, 1);
    fixture.writeU16(&bytes, 38, 0);
    fixture.writeU16(&bytes, 40, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expectError(
        error.BadGpos,
        validation.lookup.lookupSubtables(view, 14, 1, 1),
    );
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );
    var adjustments = std.ArrayList(lookup_dispatcher.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.BadGpos,
        lookup_dispatcher.collect(
            view,
            14,
            &.{1},
            &adjustments,
            std.testing.allocator,
            .{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    fixture.writeU16(&bytes, 20, 10);
    try validation.lookup.lookupSubtables(view, 14, 1, 1);
    try validation.font.glyphBounds(&bytes, 0, bytes.len, 4);
}

test "font validation rejects null required Coverage offsets" {
    var bytes = [_]u8{0} ** 42;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 38);
    fixture.writeU16(&bytes, 6, 40);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 10);
    const subtable: usize = 24;
    fixture.writeU16(&bytes, subtable, 1);
    fixture.writeU16(&bytes, subtable + 2, 0);
    fixture.writeU16(&bytes, subtable + 4, 0x0001);
    fixture.writeI16(&bytes, subtable + 6, 20);
    fixture.writeCoverage1(&bytes, subtable + 8, 1);
    fixture.writeU16(&bytes, 38, 0);
    fixture.writeU16(&bytes, 40, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expectError(error.BadGpos, single.validate(view, subtable));
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );
    var adjustments = std.ArrayList(lookup_dispatcher.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.BadGpos,
        single_runtime.collect(
            view,
            subtable,
            &.{1},
            &adjustments,
            std.testing.allocator,
            0,
            .{},
        ),
    );
    try std.testing.expectError(
        error.BadGpos,
        lookup_dispatcher.collect(
            view,
            14,
            &.{1},
            &adjustments,
            std.testing.allocator,
            .{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    fixture.writeU16(&bytes, subtable + 2, 8);
    try single.validate(view, subtable);
    try validation.font.glyphBounds(&bytes, 0, bytes.len, 4);
}
