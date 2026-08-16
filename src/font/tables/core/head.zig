//! OpenType `head` table decoding and SFNT-wide invariant validation.

const bin = @import("../../../binary.zig");
const glyph = @import("../../../glyph.zig");
const sfnt = @import("../../sfnt/root.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error || error{ EndOfStream, InvalidLoca };

pub const Info = struct {
    table_version: u32,
    font_revision: f32,
    flags: u16,
    units_per_em: u16,
    created: i64,
    modified: i64,
    bounds: glyph.Bounds,
    mac_style: u16,
    lowest_rec_ppem: u16,
    font_direction_hint: i16,
    index_to_loc_format: i16,
    glyph_data_format: i16,
};

pub fn info(data: []const u8, table: sfnt.Record) Error!Info {
    try sfnt.requireLength(table, 54);
    return .{
        .table_version = try bin.readU32At(data, table.offset),
        .font_revision = fixed16_16ToF32(
            try bin.readI32At(data, table.offset + 4),
        ),
        .flags = try bin.readU16At(data, table.offset + 16),
        .units_per_em = try bin.readU16At(data, table.offset + 18),
        .created = try readI64(data, table.offset + 20),
        .modified = try readI64(data, table.offset + 28),
        .bounds = .{
            .x_min = try bin.readI16At(data, table.offset + 36),
            .y_min = try bin.readI16At(data, table.offset + 38),
            .x_max = try bin.readI16At(data, table.offset + 40),
            .y_max = try bin.readI16At(data, table.offset + 42),
        },
        .mac_style = try bin.readU16At(data, table.offset + 44),
        .lowest_rec_ppem = try bin.readU16At(data, table.offset + 46),
        .font_direction_hint = try bin.readI16At(data, table.offset + 48),
        .index_to_loc_format = try bin.readI16At(data, table.offset + 50),
        .glyph_data_format = try bin.readI16At(data, table.offset + 52),
    };
}

pub fn validate(
    data: []const u8,
    table: sfnt.Record,
    format: types.Format,
) Error!void {
    try sfnt.requireLength(table, 54);

    const version = try bin.readU32At(data, table.offset);
    const magic_number = try bin.readU32At(data, table.offset + 12);
    const units_per_em = try bin.readU16At(data, table.offset + 18);
    const x_min = try bin.readI16At(data, table.offset + 36);
    const y_min = try bin.readI16At(data, table.offset + 38);
    const x_max = try bin.readI16At(data, table.offset + 40);
    const y_max = try bin.readI16At(data, table.offset + 42);
    const mac_style = try bin.readU16At(data, table.offset + 44);
    const lowest_rec_ppem = try bin.readU16At(data, table.offset + 46);
    const font_direction_hint = try bin.readI16At(data, table.offset + 48);
    const index_to_loc_format = try bin.readI16At(data, table.offset + 50);
    const glyph_data_format = try bin.readI16At(data, table.offset + 52);

    // These fields identify the table and define the scale shared by metrics,
    // outlines, and layout. Accepting values outside the OpenType ranges would
    // make every downstream font-unit conversion ambiguous.
    if (version != 0x00010000) return error.BadSfnt;
    if (magic_number != 0x5f0f3cf5) return error.BadSfnt;
    if (units_per_em < 16 or units_per_em > 16384) return error.BadSfnt;
    if (x_min > x_max or y_min > y_max) return error.BadSfnt;

    // macStyle has seven defined bits. lowestRecPPEM is a positive pixel size,
    // while the deprecated direction hint still has a specified stored range.
    if ((mac_style & 0xff80) != 0) return error.BadSfnt;
    if (lowest_rec_ppem == 0) return error.BadSfnt;
    if (font_direction_hint < -2 or font_direction_hint > 2) {
        return error.BadSfnt;
    }

    // indexToLocFormat is meaningful only for glyf/loca. Some deployed CFF
    // fonts retain a noncanonical value in this otherwise-unused field.
    if (format == .truetype and
        index_to_loc_format != 0 and
        index_to_loc_format != 1)
    {
        return error.InvalidLoca;
    }
    if (glyph_data_format != 0) return error.BadSfnt;
}

fn readI64(data: []const u8, offset: usize) Error!i64 {
    const high = try bin.readU32At(data, offset);
    const low = try bin.readU32At(data, offset + 4);
    return @bitCast((@as(u64, high) << 32) | low);
}

fn fixed16_16ToF32(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}
