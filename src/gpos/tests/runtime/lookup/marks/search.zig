//! Shared mark-attachment backward-search contracts.

const std = @import("std");
const ligature_provenance = @import("../../../../../ligature_provenance.zig");
const marks = @import("../../../../runtime/lookup/marks/root.zig");
const table = @import("../../../../table/root.zig");

test "mark search skips non-first MultipleSubst components across marks" {
    var components: ligature_provenance.Store = .{};
    defer components.deinit(std.testing.allocator);
    try components.infos.appendSlice(std.testing.allocator, &.{
        .{},
        .{ .flags = .{ .multiplied = true, .multiple_component = 0 } },
        .{},
        .{ .flags = .{ .multiplied = true, .multiple_component = 1 } },
    });

    // A surviving mark makes the second MultipleSubst component no longer
    // source-adjacent. Exact provenance still makes that component transparent.
    const sources = [_]usize{ 0, 2, 3, 2 };
    const glyphs = [_]u16{ 10, 11, 12, 13 };
    try std.testing.expect(try marks.search.isMultipleSubstContinuation(
        .{ .data = &.{}, .offset = 0, .length = 0 },
        0,
        &glyphs,
        3,
        .{
            .run_metadata = &.{
                .glyph_source_indices = &sources,
                .ligature_components = &components,
            },
        },
    ));
}

test "previous covered mark stops at first participating blocker" {
    var bytes = [_]u8{0} ** 8;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 5);
    writeU16(&bytes, 6, 7);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expectEqual(
        @as(?usize, 1),
        try marks.search.previousUnignoredCoveredGlyph(
            view,
            0,
            &.{ 9, 7, 10 },
            2,
            0,
            .{},
        ),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        try marks.search.previousUnignoredCoveredGlyph(
            view,
            0,
            &.{ 7, 8, 10 },
            2,
            0,
            .{},
        ),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
