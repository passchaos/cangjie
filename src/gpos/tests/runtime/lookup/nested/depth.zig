//! Runtime depth bounds for nested PosLookupRecord dispatch.

const std = @import("std");
const fixture = @import("fixture.zig");
const limits = @import("../../../../runtime/limits.zig");
const nested = @import("../../../../runtime/lookup/nested.zig");

test "nested positioning rejects the seventeenth edge before adjustment mutation" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 44;
    writeHeader(&bytes, 10, 1);
    fixture.writeSinglePositionLookup(&bytes, 14, 5, 0, 33);

    var adjustments = std.ArrayList(nested.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(
        error.UnsupportedGpos,
        nested.apply(
            validatedView(&bytes),
            &.{5},
            0,
            0,
            &adjustments,
            allocator,
            .{ .context_depth = limits.max_context_depth },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "nested positioning accepts the sixteenth direct and extension edge" {
    const allocator = std.testing.allocator;
    inline for (.{ false, true }) |use_extension| {
        var bytes = [_]u8{0} ** 56;
        writeHeader(&bytes, 10, 1);
        if (use_extension) {
            writeExtensionSingleLookup(&bytes, 14, 5, 37);
        } else {
            fixture.writeSinglePositionLookup(&bytes, 14, 5, 0, 37);
        }

        var adjustments = std.ArrayList(nested.Adjustment).empty;
        defer adjustments.deinit(allocator);
        try nested.apply(
            validatedView(&bytes),
            &.{5},
            0,
            0,
            &adjustments,
            allocator,
            .{ .context_depth = limits.max_context_depth - 1 },
        );
        try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
        try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
        try std.testing.expectEqual(@as(i16, 37), adjustments.items[0].x_placement);
    }
}

test "direct and extension contextual self cycles stop at the depth limit" {
    const allocator = std.testing.allocator;
    inline for (.{ false, true }) |use_extension| {
        var bytes = [_]u8{0} ** 54;
        writeHeader(&bytes, 10, 1);
        writeRecursiveContextLookup(&bytes, 14, 5, use_extension);

        var adjustments = std.ArrayList(nested.Adjustment).empty;
        defer adjustments.deinit(allocator);
        try std.testing.expectError(
            error.UnsupportedGpos,
            nested.apply(
                validatedView(&bytes),
                &.{5},
                0,
                0,
                &adjustments,
                allocator,
                .{},
            ),
        );
        try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    }
}

fn validatedView(bytes: []const u8) nested.View {
    // Recursive fixtures intentionally bypass preflight so this test exercises
    // the runtime guard rather than the validation guard.
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}

fn writeHeader(bytes: []u8, lookup_list: u16, lookup_count: u16) void {
    fixture.writeU32(bytes, 0, 0x00010000);
    fixture.writeU16(bytes, 8, lookup_list);
    fixture.writeU16(bytes, lookup_list, lookup_count);
    fixture.writeU16(bytes, lookup_list + 2, 4);
}

fn writeExtensionSingleLookup(
    bytes: []u8,
    lookup: usize,
    glyph: u16,
    x_placement: i16,
) void {
    fixture.writeU16(bytes, lookup, 9);
    fixture.writeU16(bytes, lookup + 2, 0);
    fixture.writeU16(bytes, lookup + 4, 1);
    fixture.writeU16(bytes, lookup + 6, 8);
    const wrapper = lookup + 8;
    fixture.writeU16(bytes, wrapper, 1);
    fixture.writeU16(bytes, wrapper + 2, 1);
    fixture.writeU32(bytes, wrapper + 4, 8);
    const single = wrapper + 8;
    fixture.writeU16(bytes, single, 1);
    fixture.writeU16(bytes, single + 2, 8);
    fixture.writeU16(bytes, single + 4, 0x0001);
    fixture.writeI16(bytes, single + 6, x_placement);
    fixture.writeCoverage1(bytes, single + 8, glyph);
}

fn writeRecursiveContextLookup(
    bytes: []u8,
    lookup: usize,
    glyph: u16,
    use_extension: bool,
) void {
    fixture.writeU16(bytes, lookup, if (use_extension) 9 else 7);
    fixture.writeU16(bytes, lookup + 2, 0);
    fixture.writeU16(bytes, lookup + 4, 1);
    fixture.writeU16(bytes, lookup + 6, 8);

    const context = if (use_extension) context: {
        const wrapper = lookup + 8;
        fixture.writeU16(bytes, wrapper, 1);
        fixture.writeU16(bytes, wrapper + 2, 7);
        fixture.writeU32(bytes, wrapper + 4, 8);
        break :context wrapper + 8;
    } else lookup + 8;
    // ContextPos format 3: one input Coverage and one record pointing back to
    // lookup zero. Matching the same glyph recurses through exactly one record
    // edge per iteration.
    fixture.writeU16(bytes, context, 3);
    fixture.writeU16(bytes, context + 2, 1);
    fixture.writeU16(bytes, context + 4, 1);
    fixture.writeU16(bytes, context + 6, 12);
    fixture.writeU16(bytes, context + 8, 0);
    fixture.writeU16(bytes, context + 10, 0);
    fixture.writeCoverage1(bytes, context + 12, glyph);
}
