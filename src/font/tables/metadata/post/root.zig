//! OpenType `post` metadata, validation, and glyph-name access.

const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const names = @import("names.zig");
const validation = @import("validation.zig");

pub const Error = sfnt.Error || error{ EndOfStream, InvalidGlyph };

pub const Info = struct {
    format: u32,
    italic_angle: f32,
    underline_position: i16,
    underline_thickness: i16,
    is_fixed_pitch: bool,
    min_mem_type42: u32,
    max_mem_type42: u32,
    min_mem_type1: u32,
    max_mem_type1: u32,
    glyph_name_count: ?u16 = null,
};

pub const CustomNameValidation = validation.CustomNameValidation;
pub const ValidationOptions = validation.Options;

pub fn validate(
    data: []const u8,
    table: sfnt.Record,
    glyph_count: u16,
    options: ValidationOptions,
) Error!void {
    return validation.validate(data, table, glyph_count, options);
}

pub fn info(data: []const u8, table: sfnt.Record) Error!Info {
    try sfnt.requireLength(table, 32);
    const format = try bin.readU32At(data, table.offset);
    const glyph_name_count: ?u16 = switch (format) {
        0x00020000, 0x00025000 => count: {
            // Keep this decoder safe as a standalone table helper rather than
            // relying only on the Font facade's preceding full validation.
            try sfnt.requireLength(table, 34);
            break :count try bin.readU16At(data, table.offset + 32);
        },
        0x00040000 => @intCast((table.length - 32) / 2),
        else => null,
    };
    return .{
        .format = format,
        .italic_angle = fixed16_16ToF32(
            try bin.readI32At(data, table.offset + 4),
        ),
        .underline_position = try bin.readI16At(data, table.offset + 8),
        .underline_thickness = try bin.readI16At(data, table.offset + 10),
        .is_fixed_pitch = (try bin.readU32At(data, table.offset + 12)) != 0,
        .min_mem_type42 = try bin.readU32At(data, table.offset + 16),
        .max_mem_type42 = try bin.readU32At(data, table.offset + 20),
        .min_mem_type1 = try bin.readU32At(data, table.offset + 24),
        .max_mem_type1 = try bin.readU32At(data, table.offset + 28),
        .glyph_name_count = glyph_name_count,
    };
}

/// Return a name borrowed from static standard-name storage or `data`.
///
/// The caller must validate the complete table with the desired text policy
/// immediately before this lookup. Keeping validation separate lets `Font`
/// combine it with the SFNT checksum policy for its borrowed public API.
pub fn glyphName(
    data: []const u8,
    table: sfnt.Record,
    glyph_id: u16,
) Error!?[]const u8 {
    return names.glyphName(data, table, glyph_id);
}

fn fixed16_16ToF32(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}
