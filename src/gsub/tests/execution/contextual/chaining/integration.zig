//! Root-bound ChainContextSubst integration contracts.
//!
//! Focused matchers use local executors. These fixtures retain complete
//! LookupList recursion so class/coverage matching and source-syllable policy
//! are proven against the real nested lookup dispatcher.

const std = @import("std");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB chaining class substitution applies a nested lookup" {
            const allocator = std.testing.allocator;
            const bytes = try allocator.alloc(u8, 112);
            defer allocator.free(bytes);
            @memset(bytes, 0);
            writeLookupList(bytes, 16, 92);

            const chain = 24;
            writeU16(bytes, 16, 6);
            writeU16(bytes, 20, 1);
            writeU16(bytes, 22, 8);
            writeU16(bytes, chain, 2);
            writeU16(bytes, chain + 2, 38);
            writeU16(bytes, chain + 4, 44);
            writeU16(bytes, chain + 6, 52);
            writeU16(bytes, chain + 8, 60);
            writeU16(bytes, chain + 10, 2);
            writeU16(bytes, chain + 14, 16);

            const set = chain + 16;
            writeU16(bytes, set, 1);
            writeU16(bytes, set + 2, 4);
            const rule = set + 4;
            writeU16(bytes, rule, 1);
            writeU16(bytes, rule + 2, 1);
            writeU16(bytes, rule + 4, 1);
            writeU16(bytes, rule + 6, 1);
            writeU16(bytes, rule + 8, 1);
            writeU16(bytes, rule + 10, 1);
            writeU16(bytes, rule + 12, 0);
            writeU16(bytes, rule + 14, 1);

            writeCoverage1(bytes, chain + 38, 1);
            writeClassDef1(bytes, chain + 44, 1, 1);
            writeClassDef1(bytes, chain + 52, 1, 1);
            writeClassDef1(bytes, chain + 60, 1, 1);
            writeSingleDeltaLookup(bytes, 92, 1, 2);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
            try Bindings.applyLookup(
                view(bytes),
                16,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 1, 3, 1 },
                glyphs.items,
            );
        }

        test "GSUB chaining coverage substitution applies a nested lookup" {
            const allocator = std.testing.allocator;
            const bytes = try allocator.alloc(u8, 82);
            defer allocator.free(bytes);
            @memset(bytes, 0);
            writeLookupList(bytes, 16, 62);
            writeCoverageChain(bytes);
            writeSingleDeltaLookup(bytes, 62, 1, 2);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
            try Bindings.applyLookup(
                view(bytes),
                16,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 1, 3, 1 },
                glyphs.items,
            );
        }

        test "GSUB source syllables block cross-syllable chaining context" {
            const allocator = std.testing.allocator;
            const bytes = try allocator.alloc(u8, 82);
            defer allocator.free(bytes);
            @memset(bytes, 0);
            writeLookupList(bytes, 16, 62);
            writeCoverageChain(bytes);
            writeSingleDeltaLookup(bytes, 62, 1, 2);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.appendSlice(allocator, &.{ 0, 1, 2 });
            const syllables = [_]u8{ 1, 2, 2 };

            try Bindings.applyLookup(
                view(bytes),
                16,
                &glyphs,
                allocator,
                .{
                    .glyph_source_indices = &sources,
                    .source_syllables = &syllables,
                    .match_source_syllable = true,
                },
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 1, 1, 1 },
                glyphs.items,
            );
        }
    };
}

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeLookupList(bytes: []u8, chaining_lookup: usize, nested: usize) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 2);
    writeU16(bytes, 12, @intCast(chaining_lookup - 10));
    writeU16(bytes, 14, @intCast(nested - 10));
}

fn writeCoverageChain(bytes: []u8) void {
    writeU16(bytes, 16, 6);
    writeU16(bytes, 20, 1);
    writeU16(bytes, 22, 8);
    const chain = 24;
    writeU16(bytes, chain, 3);
    writeU16(bytes, chain + 2, 1);
    writeU16(bytes, chain + 4, 20);
    writeU16(bytes, chain + 6, 1);
    writeU16(bytes, chain + 8, 26);
    writeU16(bytes, chain + 10, 1);
    writeU16(bytes, chain + 12, 32);
    writeU16(bytes, chain + 14, 1);
    writeU16(bytes, chain + 16, 0);
    writeU16(bytes, chain + 18, 1);
    writeCoverage1(bytes, chain + 20, 1);
    writeCoverage1(bytes, chain + 26, 1);
    writeCoverage1(bytes, chain + 32, 1);
}

fn writeSingleDeltaLookup(
    bytes: []u8,
    offset: usize,
    glyph: GlyphId,
    delta: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 6);
    writeI16(bytes, offset + 12, delta);
    writeCoverage1(bytes, offset + 14, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    start: GlyphId,
    class: u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, start);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, class);
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
