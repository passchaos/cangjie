//! Nested ChainContextSubst real-run lookahead integration.

const std = @import("std");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "nested ChainContextSubst sees real lookahead glyphs" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 140;
            writeU32(&bytes, 0, 0x00010000);
            writeU16(&bytes, 8, 10);
            writeU16(&bytes, 10, 3);
            writeU16(&bytes, 12, 8);
            writeU16(&bytes, 14, 48);
            writeU16(&bytes, 16, 98);
            writeParentContext(&bytes);
            writeNestedChaining(&bytes);
            writeSingleLookup(&bytes, 108, 1, 10);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });
            try Bindings.applyLookup(
                table.View{
                    .data = &bytes,
                    .offset = 0,
                    .length = bytes.len,
                },
                18,
                &glyphs,
                allocator,
                .{},
            );
            // A one-glyph scratch run cannot see lookahead glyph two.
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 11, 2, 3 },
                glyphs.items,
            );
        }
    };
}

fn writeParentContext(bytes: []u8) void {
    const lookup = 18;
    writeU16(bytes, lookup, 5);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const context = 26;
    writeU16(bytes, context, 1);
    writeU16(bytes, context + 2, 22);
    writeU16(bytes, context + 4, 1);
    writeU16(bytes, context + 6, 8);
    const set = context + 8;
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(bytes, rule, 1);
    writeU16(bytes, rule + 2, 1);
    writeU16(bytes, rule + 4, 0);
    writeU16(bytes, rule + 6, 1);
    writeCoverage1(bytes, context + 22, 1);
}

fn writeNestedChaining(bytes: []u8) void {
    const lookup = 58;
    writeU16(bytes, lookup, 6);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const chain = lookup + 8;
    writeU16(bytes, chain, 3);
    writeU16(bytes, chain + 2, 0);
    writeU16(bytes, chain + 4, 1);
    writeU16(bytes, chain + 6, 22);
    writeU16(bytes, chain + 8, 1);
    writeU16(bytes, chain + 10, 28);
    writeU16(bytes, chain + 12, 1);
    writeU16(bytes, chain + 14, 0);
    writeU16(bytes, chain + 16, 2);
    writeCoverage1(bytes, chain + 22, 1);
    writeCoverage1(bytes, chain + 28, 2);
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
