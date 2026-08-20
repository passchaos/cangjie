//! Generic lookup whole-payload preflight atomicity contracts.
//!
//! A malformed later direct subtable or ExtensionSubst payload must be found
//! before an earlier valid alternative can mutate the glyph stream.

const std = @import("std");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "direct SingleSubst preflights all subtables atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 36;
            writeLookup(&bytes, 1, &.{ 10, 24 });
            writeSingleDelta(&bytes, 10, 10, 10);
            writeTruncatedCoverageSingle(&bytes, 24, 30);
            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                &.{ 10, 30 },
                allocator,
            );
        }

        test "extension SingleSubst preflights wrapped Coverage atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 52;
            writeLookup(&bytes, 7, &.{ 10, 32 });
            writeExtension(&bytes, 10, 1);
            writeSingleDelta(&bytes, 18, 10, 10);
            writeExtension(&bytes, 32, 1);
            writeTruncatedCoverageSingle(&bytes, 40, 30);
            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                &.{ 10, 30 },
                allocator,
            );
        }

        test "extension MultipleSubst preflights wrapped Sequence atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 66;
            writeLookup(&bytes, 7, &.{ 10, 40 });
            writeExtension(&bytes, 10, 2);
            writeMultiple(&bytes, 18, 10, &.{ 20, 21 });
            writeExtension(&bytes, 40, 2);

            const multiple = 48;
            writeU16(&bytes, multiple, 1);
            writeU16(&bytes, multiple + 2, 8);
            writeU16(&bytes, multiple + 4, 1);
            writeU16(&bytes, multiple + 6, 14);
            writeCoverage1(&bytes, multiple + 8, 30);
            const truncated_sequence = multiple + 14;
            writeU16(&bytes, truncated_sequence, 2);
            writeU16(&bytes, truncated_sequence + 2, 31);

            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                &.{ 10, 30 },
                allocator,
            );
        }

        test "mixed ExtensionSubst preflights wrapped ligature atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 72;
            writeLookup(&bytes, 7, &.{ 10, 40 });
            writeExtension(&bytes, 10, 1);
            writeSingleDelta(&bytes, 18, 10, 10);
            writeExtension(&bytes, 40, 4);

            const ligature = 48;
            writeU16(&bytes, ligature, 1);
            writeU16(&bytes, ligature + 2, 8);
            writeU16(&bytes, ligature + 4, 1);
            writeU16(&bytes, ligature + 6, 14);
            writeCoverage1(&bytes, ligature + 8, 30);
            const set = ligature + 14;
            writeU16(&bytes, set, 1);
            writeU16(&bytes, set + 2, 4);
            const truncated = set + 4;
            writeU16(&bytes, truncated, 40);
            writeU16(&bytes, truncated + 2, 3);
            writeU16(&bytes, truncated + 4, 31);

            try expectAtomicBadGsub(
                Bindings,
                &bytes,
                &.{ 10, 30, 31, 32 },
                allocator,
            );
        }
    };
}

fn expectAtomicBadGsub(
    comptime Bindings: type,
    bytes: []const u8,
    initial: []const GlyphId,
    allocator: std.mem.Allocator,
) !void {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, initial);
    try std.testing.expectError(
        error.BadGsub,
        Bindings.applyLookup(
            table.View{
                .data = bytes,
                .offset = 0,
                .length = bytes.len,
            },
            0,
            &glyphs,
            allocator,
            .{},
        ),
    );
    try std.testing.expectEqualSlices(GlyphId, initial, glyphs.items);
}

fn writeLookup(
    bytes: []u8,
    lookup_type: u16,
    offsets: []const u16,
) void {
    writeU16(bytes, 0, lookup_type);
    writeU16(bytes, 4, @intCast(offsets.len));
    for (offsets, 0..) |offset, index| {
        writeU16(bytes, 6 + index * 2, offset);
    }
}

fn writeExtension(bytes: []u8, offset: usize, lookup_type: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, lookup_type);
    writeU32(bytes, offset + 4, 8);
}

fn writeSingleDelta(
    bytes: []u8,
    offset: usize,
    glyph: GlyphId,
    delta: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 6);
    writeI16(bytes, offset + 4, delta);
    writeCoverage1(bytes, offset + 6, glyph);
}

fn writeTruncatedCoverageSingle(
    bytes: []u8,
    offset: usize,
    first_glyph: GlyphId,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 6);
    writeI16(bytes, offset + 4, 1);
    const coverage = offset + 6;
    writeU16(bytes, coverage, 1);
    writeU16(bytes, coverage + 2, 2);
    writeU16(bytes, coverage + 4, first_glyph);
}

fn writeMultiple(
    bytes: []u8,
    offset: usize,
    glyph: GlyphId,
    replacements: []const GlyphId,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 14);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, @intCast(replacements.len));
    for (replacements, 0..) |replacement, index| {
        writeU16(bytes, offset + 10 + index * 2, replacement);
    }
    writeCoverage1(bytes, offset + 14, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
