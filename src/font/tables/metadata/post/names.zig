//! Glyph-name lookup for validated OpenType `post` tables.

const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const standard = @import("standard_names.zig");

pub const Error = sfnt.Error || error{ EndOfStream, InvalidGlyph };

pub fn glyphName(
    data: []const u8,
    table: sfnt.Record,
    glyph_id: u16,
) Error!?[]const u8 {
    const bytes = data[table.offset .. table.offset + table.length];
    const version = try bin.readU32At(bytes, 0);
    return switch (version) {
        0x00010000 => try standard.get(glyph_id),
        0x00020000 => try format2GlyphName(bytes, glyph_id),
        0x00025000 => try format25GlyphName(bytes, glyph_id),
        // Format 3.0 deliberately omits names. Format 4.0 maps glyphs to
        // character codes for legacy composite-font workflows, not names.
        0x00030000, 0x00040000 => null,
        else => error.BadSfnt,
    };
}

fn format2GlyphName(
    table: []const u8,
    glyph_id: u16,
) Error!?[]const u8 {
    const number_of_glyphs = try bin.readU16At(table, 32);
    if (glyph_id >= number_of_glyphs) return error.InvalidGlyph;

    const indices_offset: usize = 34;
    const name_index = try bin.readU16At(
        table,
        indices_offset + @as(usize, glyph_id) * 2,
    );
    if (name_index < standard.count) return try standard.get(name_index);

    // Index 258 names the first Pascal string after the glyphNameIndex array.
    // Validation guarantees that all ordinals through the largest reference
    // exist, while this lookup retains defensive bounds checks of its own.
    const name = try customGlyphName(
        table,
        name_index - standard.count,
    );
    return if (name.len == 0) null else name;
}

fn customGlyphName(table: []const u8, ordinal: usize) Error![]const u8 {
    const number_of_glyphs = try bin.readU16At(table, 32);
    var cursor: usize = 34 + @as(usize, number_of_glyphs) * 2;
    for (0..ordinal) |_| {
        if (cursor >= table.len) return error.BadSfnt;
        const name_len = table[cursor];
        cursor += 1 + @as(usize, name_len);
        if (cursor > table.len) return error.BadSfnt;
    }
    if (cursor >= table.len) return error.BadSfnt;
    const name_len = table[cursor];
    cursor += 1;
    if (@as(usize, name_len) > table.len - cursor) return error.BadSfnt;
    return table[cursor .. cursor + name_len];
}

fn format25GlyphName(
    table: []const u8,
    glyph_id: u16,
) Error!?[]const u8 {
    const number_of_glyphs = try bin.readU16At(table, 32);
    if (glyph_id >= number_of_glyphs) return error.InvalidGlyph;

    const delta: i8 = @bitCast(table[34 + @as(usize, glyph_id)]);
    const standard_index = @as(i32, glyph_id) + @as(i32, delta);
    if (standard_index < 0 or standard_index >= standard.count) {
        return error.BadSfnt;
    }
    return try standard.get(@intCast(standard_index));
}
