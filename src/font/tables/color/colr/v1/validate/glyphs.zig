//! COLR v1 glyph-reference validation across Paint and clip graphs.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const bases = @import("../bases.zig");
const clip = @import("../clip.zig");
const glyph = @import("../../../../../../glyph.zig");
const paint = @import("../paint/root.zig");
const types = @import("../types.zig");

pub fn validate(
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
) types.Error!void {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 34 or
        try bin.readU16At(data, table.offset) != 1)
    {
        return error.BadSfnt;
    }
    _ = try clip.validate(data, table, glyph_count);

    const base_list = try bases.read(data, table);
    if (base_list) |list| {
        for (0..list.record_count) |index| {
            try validateGlyphId(
                (try bases.recordAt(data, table, list, index)).glyph_id,
                glyph_count,
            );
        }
    }

    var visitor = Visitor{
        .glyph_count = glyph_count,
        .base_list = base_list,
    };
    try paint.walkAll(data, table, &visitor);
}

const Visitor = struct {
    glyph_count: u16,
    base_list: ?bases.List,

    pub fn visit(
        self: *const Visitor,
        data: []const u8,
        table: types.Table,
        offset: usize,
        info: paint.FormatInfo,
    ) types.Error!void {
        switch (info.kind) {
            .glyph => try validateGlyphId(
                try bin.readU16At(data, offset + 4),
                self.glyph_count,
            ),
            .colr_glyph => {
                const referenced_glyph = try bin.readU16At(data, offset + 1);
                try validateGlyphId(referenced_glyph, self.glyph_count);
                const list = self.base_list orelse return error.BadSfnt;
                _ = (try bases.paintOffsetForGlyph(
                    data,
                    table,
                    list,
                    referenced_glyph,
                )) orelse return error.BadSfnt;
                // Cross-glyph recursion is a renderer traversal concern:
                // rejecting a cycle here would make unrelated valid glyphs
                // unusable. This pass proves only that the referenced base
                // glyph exists and belongs to maxp.
            },
            .terminal,
            .colr_layers,
            .solid,
            .color_line,
            .single_child,
            .composite,
            => {},
        }
    }
};

fn validateGlyphId(
    glyph_id: glyph.GlyphId,
    glyph_count: u16,
) types.Error!void {
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

test "glyph validation covers PaintGlyph and declared PaintColrGlyph targets" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 2);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 16);
    writeU16(&bytes, 44, 2);
    writeU32(&bytes, 46, 25);

    bytes[50] = 10;
    writeU24(&bytes, 51, 6);
    writeU16(&bytes, 54, 3);
    bytes[56] = 11;
    writeU16(&bytes, 57, 2);
    bytes[59] = 2;
    writeI16(&bytes, 62, 0x4000);

    const table = types.Table{ .offset = 0, .length = bytes.len };
    try validate(&bytes, table, 4);

    writeU16(&bytes, 54, 4);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
    writeU16(&bytes, 54, 3);

    writeU16(&bytes, 57, 3);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
    writeU16(&bytes, 57, 1);
    // A self-edge remains structurally valid; lazy traversal rejects it only
    // when that glyph is actually rendered.
    try validate(&bytes, table, 4);

    var indirect_cycle = bytes;
    writeU16(&indirect_cycle, 57, 2);
    indirect_cycle[59] = 11;
    writeU16(&indirect_cycle, 60, 1);
    // Cross-glyph cycles are likewise a lazy traversal concern. Parse-time
    // validation proves that each edge names a declared BaseGlyphPaintRecord.
    try validate(&indirect_cycle, table, 4);
}

test "glyph validation covers LayerList Paints and ClipList ranges" {
    var bytes: [80]u8 = .{0} ** 80;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 18, 34);
    writeU32(&bytes, 22, 53);

    writeU32(&bytes, 34, 1);
    writeU32(&bytes, 38, 8);
    bytes[42] = 10;
    writeU24(&bytes, 43, 6);
    writeU16(&bytes, 46, 1);
    bytes[48] = 2;
    writeI16(&bytes, 51, 0x4000);

    bytes[53] = 1;
    writeU32(&bytes, 54, 1);
    writeU16(&bytes, 58, 2);
    writeU16(&bytes, 60, 3);
    writeU24(&bytes, 62, 12);
    bytes[65] = 1;
    writeI16(&bytes, 66, 0);
    writeI16(&bytes, 68, 0);
    writeI16(&bytes, 70, 10);
    writeI16(&bytes, 72, 10);

    const table = types.Table{ .offset = 0, .length = 74 };
    try validate(&bytes, table, 4);

    writeU16(&bytes, 46, 4);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
    writeU16(&bytes, 46, 1);

    writeU16(&bytes, 60, 4);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, table, 4));
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
