//! Contextual position-map integration with real MultipleSubst dispatch.
//!
//! Local map tests cover the algorithm. These complete LookupList fixtures
//! prove direct and extension cardinality changes update later authored
//! SequenceLookupRecord targets correctly through the real nested executor.

const std = @import("std");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "ContextSubst applies nested MultipleSubst to the real run" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 80;
            writeLookupList(&bytes, &.{ 6, 42 });
            const context_lookup = 16;
            const rule = writeContextLookup(
                &bytes,
                context_lookup,
                2,
                &.{.{ 1, 1 }},
                22,
            );
            writeU16(&bytes, rule + 4, 2);
            writeMultipleLookup(&bytes, 52, 2, &.{ 20, 21 });

            var glyphs = try glyphList(allocator, &.{ 1, 2, 3 });
            defer glyphs.deinit(allocator);
            try Bindings.applyLookup(
                view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 1, 20, 21, 3 },
                glyphs.items,
            );
        }

        test "MultipleSubst can make a later SequenceIndex valid" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 124;
            writeLookupList(&bytes, &.{ 10, 52, 88 });
            writeU16(&bytes, 4, 118);
            writeU16(&bytes, 6, 120);
            writeU16(&bytes, 118, 0);
            writeU16(&bytes, 120, 0);
            const context_lookup = 20;
            const rule = writeContextLookup(
                &bytes,
                context_lookup,
                2,
                &.{
                    .{ 0, 1 },
                    .{ 2, 2 },
                },
                28,
            );
            writeU16(&bytes, rule + 4, 2);
            writeMultipleLookup(&bytes, 62, 1, &.{ 10, 11 });
            writeSingleLookup(&bytes, 98, 2, 10);

            var glyphs = try glyphList(allocator, &.{ 1, 2 });
            defer glyphs.deinit(allocator);
            try Bindings.validateTable(&bytes, 0, bytes.len, 32);
            try Bindings.applyLookup(
                view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 10, 11, 12 },
                glyphs.items,
            );
        }

        test "contextual records skip a deleted input target" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 160;
            writeLookupList(&bytes, &.{ 10, 60, 92, 124 });
            const context_lookup = 20;
            const rule = writeContextLookup(
                &bytes,
                context_lookup,
                3,
                &.{
                    .{ 0, 1 },
                    .{ 0, 2 },
                    .{ 1, 3 },
                },
                34,
            );
            writeU16(&bytes, rule + 4, 2);
            writeU16(&bytes, rule + 6, 3);
            writeMultipleLookup(&bytes, 70, 1, &.{});
            writeSingleLookup(&bytes, 102, 2, 10);
            writeSingleLookup(&bytes, 134, 2, 20);

            var glyphs = try glyphList(allocator, &.{ 1, 2, 3 });
            defer glyphs.deinit(allocator);
            try Bindings.applyLookup(
                view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 22, 3 },
                glyphs.items,
            );
        }

        test "extension MultipleSubst extends later record positions" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 132;
            writeLookupList(&bytes, &.{ 8, 60, 100 });
            const context_lookup = 18;
            const rule = writeContextLookup(
                &bytes,
                context_lookup,
                3,
                &.{
                    .{ 1, 1 },
                    .{ 2, 2 },
                },
                32,
            );
            writeU16(&bytes, rule + 4, 2);
            writeU16(&bytes, rule + 6, 3);
            writeExtensionMultipleLookup(&bytes, 70, 2, &.{ 20, 21 });
            writeSingleLookup(&bytes, 110, 21, 10);

            var glyphs = try glyphList(allocator, &.{ 1, 2, 3 });
            defer glyphs.deinit(allocator);
            try Bindings.applyLookup(
                view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 1, 20, 31, 3 },
                glyphs.items,
            );
        }
    };
}

fn glyphList(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphId,
) !std.ArrayList(GlyphId) {
    var result = std.ArrayList(GlyphId).empty;
    try result.appendSlice(allocator, glyphs);
    return result;
}

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeLookupList(bytes: []u8, offsets: []const u16) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, @intCast(offsets.len));
    for (offsets, 0..) |offset, index| {
        writeU16(bytes, 12 + index * 2, offset);
    }
}

fn writeContextLookup(
    bytes: []u8,
    lookup: usize,
    input_count: u16,
    records: []const [2]u16,
    coverage_relative: u16,
) usize {
    writeU16(bytes, lookup, 5);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const context = lookup + 8;
    writeU16(bytes, context, 1);
    writeU16(bytes, context + 2, coverage_relative);
    writeU16(bytes, context + 4, 1);
    writeU16(bytes, context + 6, 8);
    const set = context + 8;
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(bytes, rule, input_count);
    writeU16(bytes, rule + 2, @intCast(records.len));
    var cursor = rule + 4 + (@as(usize, input_count) - 1) * 2;
    for (records) |record| {
        writeU16(bytes, cursor, record[0]);
        writeU16(bytes, cursor + 2, record[1]);
        cursor += 4;
    }
    writeCoverage1(bytes, context + coverage_relative, 1);
    return rule;
}

fn writeMultipleLookup(
    bytes: []u8,
    lookup: usize,
    glyph: GlyphId,
    replacements: []const GlyphId,
) void {
    writeU16(bytes, lookup, 2);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const multiple = lookup + 8;
    writeU16(bytes, multiple, 1);
    writeU16(bytes, multiple + 2, 8);
    writeU16(bytes, multiple + 4, 1);
    writeU16(bytes, multiple + 6, 14);
    writeCoverage1(bytes, multiple + 8, glyph);
    writeU16(bytes, multiple + 14, @intCast(replacements.len));
    for (replacements, 0..) |replacement, index| {
        writeU16(bytes, multiple + 16 + index * 2, replacement);
    }
}

fn writeExtensionMultipleLookup(
    bytes: []u8,
    lookup: usize,
    glyph: GlyphId,
    replacements: []const GlyphId,
) void {
    writeU16(bytes, lookup, 7);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    writeU16(bytes, lookup + 8, 1);
    writeU16(bytes, lookup + 10, 2);
    writeU32(bytes, lookup + 12, 8);
    const multiple = lookup + 16;
    writeU16(bytes, multiple, 1);
    writeU16(bytes, multiple + 2, 12);
    writeU16(bytes, multiple + 4, 1);
    writeU16(bytes, multiple + 6, 18);
    writeCoverage1(bytes, multiple + 12, glyph);
    writeU16(bytes, multiple + 18, @intCast(replacements.len));
    for (replacements, 0..) |replacement, index| {
        writeU16(bytes, multiple + 20 + index * 2, replacement);
    }
}

fn writeSingleLookup(
    bytes: []u8,
    lookup: usize,
    glyph: GlyphId,
    delta: i16,
) void {
    writeU16(bytes, lookup, 1);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    writeU16(bytes, lookup + 8, 1);
    writeU16(bytes, lookup + 10, 6);
    writeI16(bytes, lookup + 12, delta);
    writeCoverage1(bytes, lookup + 14, glyph);
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
