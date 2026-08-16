//! Structural and public-text validation for OpenType `post` tables.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub const CustomNameValidation = enum {
    /// Require every referenced custom name to be non-empty and public-safe.
    strict,
    /// Accept deployed empty Pascal strings as an absent glyph name.
    allow_empty,
    /// Validate only offsets, lengths, and name-index reachability.
    structural_only,
};

pub const Options = struct {
    compat_ttc_face: bool = false,
    custom_name_validation: CustomNameValidation = .strict,
};

pub fn validate(
    data: []const u8,
    table: sfnt.Record,
    glyph_count: u16,
    options: Options,
) Error!void {
    try sfnt.requireLength(table, 32);
    const version = try bin.readU32At(data, table.offset);
    switch (version) {
        0x00010000 => {
            // Format 1.0 implies the complete standard Macintosh glyph-name
            // set. `maxp` must therefore expose the same addressable set.
            if (glyph_count != 258) return error.BadSfnt;
        },
        0x00020000 => try validateFormat2(
            data,
            table,
            glyph_count,
            options,
        ),
        0x00025000 => try validateFormat25(data, table, glyph_count),
        0x00030000 => {},
        0x00040000 => try validateFormat4(table, glyph_count),
        else => return error.BadSfnt,
    }
}

fn validateFormat2(
    data: []const u8,
    table: sfnt.Record,
    glyph_count: u16,
    options: Options,
) Error!void {
    const bytes = data[table.offset .. table.offset + table.length];
    if (table.length - 32 < 2) return error.BadSfnt;
    const number_of_glyphs = try bin.readU16At(bytes, 32);
    if (number_of_glyphs != glyph_count) return error.BadSfnt;

    const indices_offset: usize = 34;
    const indices_len = @as(usize, number_of_glyphs) * 2;
    if (indices_len > table.length - indices_offset) return error.BadSfnt;

    var custom_name_count: usize = 0;
    for (0..number_of_glyphs) |glyph_index| {
        const name_index = try bin.readU16At(
            bytes,
            indices_offset + glyph_index * 2,
        );
        if (name_index >= 258) {
            custom_name_count = @max(
                custom_name_count,
                @as(usize, name_index) - 257,
            );
        }
    }

    var cursor = indices_offset + indices_len;
    for (0..custom_name_count) |_| {
        if (cursor >= table.length) return error.BadSfnt;
        const name_len = bytes[cursor];
        cursor += 1;
        if (name_len > 63) return error.BadSfnt;
        if (@as(usize, name_len) > table.length - cursor) {
            return error.BadSfnt;
        }
        if (!options.compat_ttc_face) {
            const name = bytes[cursor .. cursor + name_len];
            switch (options.custom_name_validation) {
                .strict => if (name.len == 0 or !isGlyphName(name)) {
                    return error.BadSfnt;
                },
                .allow_empty => if (name.len != 0 and !isGlyphName(name)) {
                    return error.BadSfnt;
                },
                .structural_only => {},
            }
        }
        cursor += name_len;
    }
    if (!options.compat_ttc_face and cursor != table.length) {
        return error.BadSfnt;
    }
}

fn validateFormat25(
    data: []const u8,
    table: sfnt.Record,
    glyph_count: u16,
) Error!void {
    const bytes = data[table.offset .. table.offset + table.length];
    if (table.length - 32 < 2) return error.BadSfnt;
    const number_of_glyphs = try bin.readU16At(bytes, 32);
    if (number_of_glyphs != glyph_count) return error.BadSfnt;

    const offsets_offset: usize = 34;
    // Format 2.5 has no name pool or extension payload. Exact consumption
    // prevents different consumers from assigning meaning to orphan bytes.
    const required_len = offsets_offset + @as(usize, number_of_glyphs);
    if (table.length != required_len) return error.BadSfnt;

    for (0..number_of_glyphs) |glyph_index| {
        const delta: i8 = @bitCast(bytes[offsets_offset + glyph_index]);
        const standard_index =
            @as(i32, @intCast(glyph_index)) + @as(i32, delta);
        if (standard_index < 0 or standard_index >= 258) {
            return error.BadSfnt;
        }
    }
}

fn validateFormat4(table: sfnt.Record, glyph_count: u16) Error!void {
    // Format 4.0 owns exactly one character-code slot per glyph.
    const required_len = 32 + @as(usize, glyph_count) * 2;
    if (table.length != required_len) return error.BadSfnt;
}

pub fn isGlyphName(name: []const u8) bool {
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte) or
            byte == ' ' or
            byte == '.' or
            byte == '_' or
            byte == '-')
        {
            continue;
        }
        return false;
    }
    return true;
}

test "glyph names accept deployed separators but reject controls" {
    try std.testing.expect(isGlyphName("Dot Below"));
    try std.testing.expect(isGlyphName("Virama-Killer"));
    try std.testing.expect(!isGlyphName("Dot\tBelow"));
}
