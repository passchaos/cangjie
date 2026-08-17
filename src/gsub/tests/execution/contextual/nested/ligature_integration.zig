//! Direct and ExtensionSubst nested ligature real-run integration.

const std = @import("std");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "ContextSubst nested LigatureSubst sees the real glyph run" {
            try expectNestedLigature(Bindings, false);
        }

        test "ContextSubst nested extension LigatureSubst sees the real glyph run" {
            try expectNestedLigature(Bindings, true);
        }
    };
}

fn expectNestedLigature(
    comptime Bindings: type,
    extension: bool,
) !void {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 100;
    writeU32(&bytes, 0, 0x00010000);
    writeU16(&bytes, 8, 10);
    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 12, 6);
    writeU16(&bytes, 14, 42);
    writeParentContext(&bytes);

    if (extension) {
        writeU16(&bytes, 52, 7);
        writeU16(&bytes, 56, 1);
        writeU16(&bytes, 58, 8);
        writeU16(&bytes, 60, 1);
        writeU16(&bytes, 62, 4);
        writeU32(&bytes, 64, 8);
        writeLigatureSubtable(&bytes, 68, 1, 2, 40);
    } else {
        writeU16(&bytes, 52, 4);
        writeU16(&bytes, 56, 1);
        writeU16(&bytes, 58, 8);
        writeLigatureSubtable(&bytes, 60, 1, 2, 40);
    }

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });
    try Bindings.applyLookup(
        table.View{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
        },
        16,
        &glyphs,
        allocator,
        .{},
    );
    // A one-glyph scratch run could not see component two.
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ 40, 3 },
        glyphs.items,
    );
}

fn writeParentContext(bytes: []u8) void {
    writeU16(bytes, 16, 5);
    writeU16(bytes, 20, 1);
    writeU16(bytes, 22, 8);
    const context = 24;
    writeU16(bytes, context, 1);
    writeU16(bytes, context + 2, 22);
    writeU16(bytes, context + 4, 1);
    writeU16(bytes, context + 6, 8);
    const set = context + 8;
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(bytes, rule, 2);
    writeU16(bytes, rule + 2, 1);
    writeU16(bytes, rule + 4, 2);
    writeU16(bytes, rule + 6, 0);
    writeU16(bytes, rule + 8, 1);
    writeCoverage1(bytes, context + 22, 1);
}

fn writeLigatureSubtable(
    bytes: []u8,
    offset: usize,
    first: GlyphId,
    second: GlyphId,
    output: GlyphId,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 18);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    const set = offset + 8;
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, 4);
    writeU16(bytes, set + 4, output);
    writeU16(bytes, set + 6, 2);
    writeU16(bytes, set + 8, second);
    writeCoverage1(bytes, offset + 18, first);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
