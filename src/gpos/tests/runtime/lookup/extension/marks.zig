//! Prepared ExtensionPos MarkBasePos and MarkMarkPos execution contracts.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const dispatcher = @import("../../../../runtime/lookup/dispatcher/root.zig");
const fixture = @import("mark_fixture.zig");
const marks = @import("../../../../runtime/lookup/marks/root.zig");
const output = @import("../../../../runtime/output/root.zig");
const positioning = @import("../../../../positioning/root.zig");
const table = @import("../../../../table/root.zig");

const Adjustment = positioning.Adjustment;

test "homogeneous ExtensionPos MarkBase uses prepared coverage indexes" {
    try expectPreparedMarkExtension(.base);
}

test "homogeneous ExtensionPos MarkMark uses prepared coverage indexes" {
    try expectPreparedMarkExtension(.mark);
}

fn expectPreparedMarkExtension(kind: fixture.MarkKind) !void {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 82;
    const offsets = fixture.writeSingleExtensionTable(&bytes, kind);
    const validated = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);

    try std.testing.expectEqual(
        @as(?u16, @intFromEnum(kind)),
        sidecars[0].extension_lookup_type,
    );
    switch (kind) {
        .base => {
            try std.testing.expectEqual(
                @as(usize, 1),
                sidecars[0].mark_to_base_subtables.len,
            );
            const parsed = sidecars[0].mark_to_base_subtables[0];
            try std.testing.expectEqual(
                @as(?usize, 0),
                parsed.mark_coverage.?.index(22),
            );
            try std.testing.expectEqual(
                @as(?usize, 0),
                parsed.base_coverage.?.index(20),
            );
        },
        .mark => {
            try std.testing.expectEqual(
                @as(usize, 1),
                sidecars[0].mark_to_mark_subtables.len,
            );
            const parsed = sidecars[0].mark_to_mark_subtables[0];
            try std.testing.expectEqual(
                @as(?usize, 0),
                parsed.mark_1_coverage.?.index(22),
            );
            try std.testing.expectEqual(
                @as(?usize, 0),
                parsed.mark_2_coverage.?.index(20),
            );
        },
    }

    var direct_adjustments = std.ArrayList(Adjustment).empty;
    defer direct_adjustments.deinit(allocator);
    switch (kind) {
        .base => try marks.base.collect(
            validated,
            offsets.payload_offset,
            &.{ 20, 22 },
            &direct_adjustments,
            allocator,
            0,
            .{},
        ),
        .mark => try marks.mark.collect(
            validated,
            offsets.payload_offset,
            &.{ 20, 22 },
            &direct_adjustments,
            allocator,
            0,
            .{},
        ),
    }
    var extension_adjustments = std.ArrayList(Adjustment).empty;
    defer extension_adjustments.deinit(allocator);
    try collectExact(
        validated,
        offsets.lookup_offset,
        sidecars,
        &.{ 20, 22 },
        &extension_adjustments,
        allocator,
    );
    try std.testing.expectEqualSlices(
        Adjustment,
        direct_adjustments.items,
        extension_adjustments.items,
    );

    // Completeness is part of the dispatch proof: a partial per-subtable slice
    // must not be used even when the outer table/allocation identity is exact.
    const complete_base = sidecars[0].mark_to_base_subtables;
    const complete_mark = sidecars[0].mark_to_mark_subtables;
    switch (kind) {
        .base => sidecars[0].mark_to_base_subtables = &.{},
        .mark => sidecars[0].mark_to_mark_subtables = &.{},
    }
    extension_adjustments.clearRetainingCapacity();
    var exact_digest_cache = dispatcher.DigestCache.init();
    try dispatcher.collectAfterAcceleratorProof(
        validated,
        0,
        &.{ 20, 22 },
        &extension_adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .assume_validated = true,
        },
        &exact_digest_cache,
        &sidecars[0],
    );
    try std.testing.expectEqualSlices(
        Adjustment,
        direct_adjustments.items,
        extension_adjustments.items,
    );
    sidecars[0].mark_to_base_subtables = complete_base;
    sidecars[0].mark_to_mark_subtables = complete_mark;

    // Only Coverage glyphs are copied into the immutable sidecar. Mutating the
    // borrowed table after construction is a focused proof that exact dispatch
    // reached both prepared indexes rather than reparsing either Coverage.
    fixture.writeU16(&bytes, offsets.first_coverage_glyph, 99);
    fixture.writeU16(&bytes, offsets.second_coverage_glyph, 99);
    const copied = try allocator.dupe(accelerator.Lookup, sidecars);
    defer allocator.free(copied);
    extension_adjustments.clearRetainingCapacity();
    try dispatcher.collectWithIndex(
        validated,
        offsets.lookup_offset,
        0,
        &.{ 20, 22 },
        &extension_adjustments,
        allocator,
        .{
            .lookup_accelerators = copied,
            .assume_validated = true,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 0), extension_adjustments.items.len);

    extension_adjustments.clearRetainingCapacity();
    try collectExact(
        validated,
        offsets.lookup_offset,
        sidecars,
        &.{ 20, 22 },
        &extension_adjustments,
        allocator,
    );
    const mark = output.adjustments.find(extension_adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, 90), mark.x_placement);
    try std.testing.expectEqual(@as(i16, 105), mark.y_placement);
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);
}

fn collectExact(
    view: table.View,
    lookup_offset: usize,
    sidecars: []const accelerator.Lookup,
    glyphs: []const fixture.GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
) !void {
    var digest_cache = dispatcher.DigestCache.init();
    try dispatcher.collectWithIndex(
        view,
        lookup_offset,
        0,
        glyphs,
        adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .assume_validated = true,
        },
        &digest_cache,
    );
}

test "mixed ExtensionPos mark wrappers stay on generic dispatch" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 138;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 134);
    fixture.writeU16(&bytes, 6, 136);
    fixture.writeU16(&bytes, 8, 10);
    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU16(&bytes, 12, 4);
    const lookup_offset = 14;
    fixture.writeU16(&bytes, lookup_offset, 9);
    fixture.writeU16(&bytes, lookup_offset + 2, 0);
    fixture.writeU16(&bytes, lookup_offset + 4, 2);
    fixture.writeU16(&bytes, lookup_offset + 6, 10);
    fixture.writeU16(&bytes, lookup_offset + 8, 66);

    const base_wrapper = 24;
    fixture.writeU16(&bytes, base_wrapper, 1);
    fixture.writeU16(&bytes, base_wrapper + 2, 4);
    fixture.writeU32(&bytes, base_wrapper + 4, 8);
    fixture.writeMarkPayload(
        &bytes,
        base_wrapper + 8,
        .base,
        21,
        20,
        10,
        15,
        100,
        120,
    );

    const mark_wrapper = 80;
    fixture.writeU16(&bytes, mark_wrapper, 1);
    fixture.writeU16(&bytes, mark_wrapper + 2, 6);
    fixture.writeU32(&bytes, mark_wrapper + 4, 8);
    fixture.writeMarkPayload(
        &bytes,
        mark_wrapper + 8,
        .mark,
        22,
        21,
        5,
        10,
        45,
        60,
    );
    fixture.writeU16(&bytes, 134, 0);
    fixture.writeU16(&bytes, 136, 0);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    try std.testing.expectEqual(
        @as(?u16, null),
        sidecars[0].extension_lookup_type,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        sidecars[0].mark_to_base_subtables.len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        sidecars[0].mark_to_mark_subtables.len,
    );

    // Exact table identity cannot turn a heterogeneous wrapper list into a
    // homogeneous prepared lookup; both authored wrappers stay generic.
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try collectExact(
        view,
        lookup_offset,
        sidecars,
        &.{ 20, 21, 22 },
        &adjustments,
        allocator,
    );
    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(
        @as(?usize, 0),
        output.adjustments.find(adjustments.items, 1).?.attachment_parent_index,
    );
    try std.testing.expectEqual(
        @as(?usize, 1),
        output.adjustments.find(adjustments.items, 2).?.attachment_parent_index,
    );
}

test "prepared ExtensionPos marks preserve authored order and stop nested targets" {
    const allocator = std.testing.allocator;
    for ([_]fixture.MarkKind{ .base, .mark }) |kind| {
        var bytes = [_]u8{0} ** 138;
        fixture.writeU32(&bytes, 0, 0x00010000);
        fixture.writeU16(&bytes, 4, 134);
        fixture.writeU16(&bytes, 6, 136);
        fixture.writeU16(&bytes, 8, 10);
        fixture.writeU16(&bytes, 10, 1);
        fixture.writeU16(&bytes, 12, 4);
        const lookup = 14;
        fixture.writeU16(&bytes, lookup, 9);
        fixture.writeU16(&bytes, lookup + 2, 0);
        fixture.writeU16(&bytes, lookup + 4, 2);
        fixture.writeU16(&bytes, lookup + 6, 10);
        fixture.writeU16(&bytes, lookup + 8, 66);
        for ([_]usize{ 24, 80 }, 0..) |wrapper, index| {
            fixture.writeU16(&bytes, wrapper, 1);
            fixture.writeU16(&bytes, wrapper + 2, @intFromEnum(kind));
            fixture.writeU32(&bytes, wrapper + 4, 8);
            fixture.writeMarkPayload(
                &bytes,
                wrapper + 8,
                kind,
                22,
                20,
                10,
                15,
                if (index == 0) 100 else 200,
                if (index == 0) 120 else 220,
            );
        }
        fixture.writeU16(&bytes, 134, 0);
        fixture.writeU16(&bytes, 136, 0);
        const sidecars = try accelerator.build.lookup.all(
            &bytes,
            0,
            bytes.len,
            allocator,
        );
        defer accelerator.build.lookup.deinit(allocator, sidecars);
        const view = table.View{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        };

        var whole = std.ArrayList(Adjustment).empty;
        defer whole.deinit(allocator);
        try collectExact(
            view,
            lookup,
            sidecars,
            &.{ 20, 22 },
            &whole,
            allocator,
        );
        // Top-level mark subtables all run in authored order; attachment output
        // is absolute, so the later matching subtable replaces the first.
        try std.testing.expectEqual(
            @as(i16, 190),
            output.adjustments.find(whole.items, 1).?.x_placement,
        );

        var nested_output = std.ArrayList(Adjustment).empty;
        defer nested_output.deinit(allocator);
        try @import("../../../../runtime/lookup/nested.zig").apply(
            view,
            &.{ 20, 22 },
            1,
            0,
            &nested_output,
            allocator,
            .{
                .lookup_accelerators = sidecars,
                .assume_validated = true,
            },
        );
        // PosLookupRecord semantics treat subtables as alternatives and stop at
        // the first match, rather than cascading the later anchor.
        try std.testing.expectEqual(
            @as(i16, 90),
            output.adjustments.find(nested_output.items, 1).?.x_placement,
        );
    }
}
