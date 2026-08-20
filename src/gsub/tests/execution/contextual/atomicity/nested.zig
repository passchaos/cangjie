//! Nested lookup body and MarkFilteringSet preflight atomicity.

const std = @import("std");
const fixture = @import("fixture.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "contextual preflight rejects a later truncated lookup atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 96;
            fixture.writeLookupList(&bytes, &.{ 18, 60, 80 });
            const context_lookup = 28;
            writeTwoRecordContext(&bytes, context_lookup);
            fixture.writeSingleDeltaLookup(&bytes, 70, 1, 9);

            // Lookup 2 has a complete fixed header but its declared subtable
            // offset is outside this table.
            fixture.writeU16(&bytes, 90, 1);
            fixture.writeU16(&bytes, 94, 1);
            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                context_lookup,
                allocator,
                .{},
            );
        }

        test "contextual preflight rejects a missing mark filtering set atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 128;
            fixture.writeLookupList(&bytes, &.{ 18, 60, 84 });
            const context_lookup = 28;
            writeTwoRecordContext(&bytes, context_lookup);
            fixture.writeSingleDeltaLookup(&bytes, 70, 1, 9);

            const bad_lookup = 94;
            fixture.writeU16(&bytes, bad_lookup, 1);
            fixture.writeU16(&bytes, bad_lookup + 2, 0x0010);
            fixture.writeU16(&bytes, bad_lookup + 4, 1);
            fixture.writeU16(&bytes, bad_lookup + 6, 10);
            fixture.writeU16(&bytes, bad_lookup + 8, 1);
            const single = bad_lookup + 10;
            fixture.writeU16(&bytes, single, 1);
            fixture.writeU16(&bytes, single + 2, 6);
            fixture.writeI16(&bytes, single + 4, 5);
            fixture.writeCoverage1(&bytes, single + 6, 1);
            const mark_sets = [_][]const GlyphId{&.{1}};

            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                context_lookup,
                allocator,
                .{ .mark_filtering_sets = &mark_sets },
            );
        }

        test "contextual preflight rejects a nested extension payload atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 112;
            fixture.writeLookupList(&bytes, &.{ 18, 60, 80 });
            const context_lookup = 28;
            writeTwoRecordContext(&bytes, context_lookup);
            fixture.writeSingleDeltaLookup(&bytes, 70, 1, 9);

            fixture.writeU16(&bytes, 90, 7);
            fixture.writeU16(&bytes, 94, 1);
            fixture.writeU16(&bytes, 96, 8);
            const extension = 98;
            fixture.writeU16(&bytes, extension, 1);
            fixture.writeU16(&bytes, extension + 2, 1);
            fixture.writeU32(&bytes, extension + 4, 20);

            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                context_lookup,
                allocator,
                .{},
            );
        }
    };
}

fn writeTwoRecordContext(bytes: []u8, lookup: usize) void {
    fixture.writeU16(bytes, lookup, 5);
    fixture.writeU16(bytes, lookup + 4, 1);
    fixture.writeU16(bytes, lookup + 6, 8);
    const context = lookup + 8;
    fixture.writeU16(bytes, context, 1);
    fixture.writeU16(bytes, context + 2, 24);
    fixture.writeU16(bytes, context + 4, 1);
    fixture.writeU16(bytes, context + 6, 8);
    const set = context + 8;
    fixture.writeU16(bytes, set, 1);
    fixture.writeU16(bytes, set + 2, 4);
    const rule = set + 4;
    fixture.writeU16(bytes, rule, 1);
    fixture.writeU16(bytes, rule + 2, 2);
    fixture.writeU16(bytes, rule + 4, 0);
    fixture.writeU16(bytes, rule + 6, 1);
    fixture.writeU16(bytes, rule + 8, 0);
    fixture.writeU16(bytes, rule + 10, 2);
    fixture.writeCoverage1(bytes, context + 24, 1);
}

fn expectAtomicBadGsub(
    comptime Bindings: type,
    bytes: []const u8,
    lookup_offset: usize,
    allocator: std.mem.Allocator,
    run: @import("../../../../runtime/options.zig").Options,
) !void {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);
    try std.testing.expectError(
        error.BadGsub,
        Bindings.applyLookup(
            fixture.view(bytes),
            lookup_offset,
            &glyphs,
            allocator,
            run,
        ),
    );
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}
