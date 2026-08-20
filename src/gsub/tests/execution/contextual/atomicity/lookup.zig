//! Whole-contextual-lookup payload preflight atomicity.

const std = @import("std");
const fixture = @import("fixture.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "ContextSubst preflights every coverage before mutation" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 110;
            fixture.writeLookupList(&bytes, &.{ 6, 60 });
            fixture.writeU16(&bytes, 16, 5);
            fixture.writeU16(&bytes, 20, 2);
            fixture.writeU16(&bytes, 22, 10);
            fixture.writeU16(&bytes, 24, 34);

            const first = 26;
            writeContextCoverage(&bytes, first, 12, 1);
            fixture.writeCoverage1(&bytes, first + 12, 10);

            const malformed = 50;
            writeContextCoverage(&bytes, malformed, 10, 0);
            writeTruncatedCoverage(&bytes, malformed + 10, 30);
            fixture.writeSingleDeltaLookup(&bytes, 70, 10, 5);

            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                16,
                &.{ 10, 30 },
                allocator,
            );
        }

        test "ChainContextSubst preflights every coverage before mutation" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 112;
            fixture.writeLookupList(&bytes, &.{ 6, 62 });
            fixture.writeU16(&bytes, 16, 6);
            fixture.writeU16(&bytes, 20, 2);
            fixture.writeU16(&bytes, 22, 10);
            fixture.writeU16(&bytes, 24, 36);

            const first = 26;
            writeChainingCoverage(&bytes, first, 16, 1);
            fixture.writeCoverage1(&bytes, first + 16, 10);

            const malformed = 52;
            writeChainingCoverage(&bytes, malformed, 16, 0);
            writeTruncatedCoverage(&bytes, malformed + 16, 30);
            fixture.writeSingleDeltaLookup(&bytes, 72, 10, 5);

            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                16,
                &.{ 10, 30 },
                allocator,
            );
        }
    };
}

fn expectAtomicBadGsub(
    comptime Bindings: type,
    bytes: []const u8,
    lookup_offset: usize,
    initial: []const GlyphId,
    allocator: std.mem.Allocator,
) !void {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, initial);
    try std.testing.expectError(
        error.BadGsub,
        Bindings.applyLookup(
            fixture.view(bytes),
            lookup_offset,
            &glyphs,
            allocator,
            .{},
        ),
    );
    try std.testing.expectEqualSlices(GlyphId, initial, glyphs.items);
}

fn writeContextCoverage(
    bytes: []u8,
    offset: usize,
    coverage_relative: u16,
    record_count: u16,
) void {
    fixture.writeU16(bytes, offset, 3);
    fixture.writeU16(bytes, offset + 2, 1);
    fixture.writeU16(bytes, offset + 4, record_count);
    fixture.writeU16(bytes, offset + 6, coverage_relative);
    fixture.writeU16(bytes, offset + 8, 0);
    fixture.writeU16(bytes, offset + 10, 1);
}

fn writeChainingCoverage(
    bytes: []u8,
    offset: usize,
    coverage_relative: u16,
    record_count: u16,
) void {
    fixture.writeU16(bytes, offset, 3);
    fixture.writeU16(bytes, offset + 2, 0);
    fixture.writeU16(bytes, offset + 4, 1);
    fixture.writeU16(bytes, offset + 6, coverage_relative);
    fixture.writeU16(bytes, offset + 8, 0);
    fixture.writeU16(bytes, offset + 10, record_count);
    fixture.writeU16(bytes, offset + 12, 0);
    fixture.writeU16(bytes, offset + 14, 1);
}

fn writeTruncatedCoverage(
    bytes: []u8,
    offset: usize,
    first_glyph: GlyphId,
) void {
    fixture.writeU16(bytes, offset, 1);
    fixture.writeU16(bytes, offset + 2, 54);
    fixture.writeU16(bytes, offset + 4, first_glyph);
}
