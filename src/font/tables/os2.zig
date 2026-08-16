//! Versioned OS/2 metadata decoding and style validation.

const bin = @import("../../binary.zig");
const sfnt = @import("../sfnt/root.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub const Style = struct {
    weight: u16 = 400,
    width: u16 = 5,
    italic: bool = false,
    bold: bool = false,
};

pub const Info = struct {
    version: u16,
    x_avg_char_width: i16,
    weight_class: u16,
    width_class: u16,
    fs_type: u16,
    subscript_x_size: i16,
    subscript_y_size: i16,
    subscript_x_offset: i16,
    subscript_y_offset: i16,
    superscript_x_size: i16,
    superscript_y_size: i16,
    superscript_x_offset: i16,
    superscript_y_offset: i16,
    strikeout_size: i16,
    strikeout_position: i16,
    family_class: i16,
    panose: [10]u8,
    unicode_ranges: [4]u32,
    vendor_id: [4]u8,
    selection: u16,
    first_char_index: u16,
    last_char_index: u16,
    typo_ascender: i16,
    typo_descender: i16,
    typo_line_gap: i16,
    win_ascent: u16,
    win_descent: u16,
    code_page_ranges: ?[2]u32 = null,
    x_height: ?i16 = null,
    cap_height: ?i16 = null,
    default_char: ?u16 = null,
    break_char: ?u16 = null,
    max_context: ?u16 = null,
    lower_optical_point_size: ?u16 = null,
    upper_optical_point_size: ?u16 = null,
};

pub fn validate(data: []const u8, table: sfnt.Record) Error!void {
    _ = try style(data, table);
}

pub fn style(data: []const u8, table: sfnt.Record) Error!Style {
    const version = try versionAndLength(data, table);
    _ = version;

    const weight = try bin.readU16At(data, table.offset + 4);
    const width = try bin.readU16At(data, table.offset + 6);
    const selection = try bin.readU16At(data, table.offset + 62);

    // Font databases and style matching consume these fields directly. Keep
    // their OS/2 ranges strict both at parse time and at each borrowed lazy
    // read so impossible values cannot leak into family matching.
    if (weight < 1 or weight > 1000) return error.BadSfnt;
    if (width < 1 or width > 9) return error.BadSfnt;

    return .{
        .weight = weight,
        .width = width,
        .italic = (selection & 0x0001) != 0,
        .bold = (selection & 0x0020) != 0,
    };
}

pub fn info(data: []const u8, table: sfnt.Record) Error!Info {
    const version = try versionAndLength(data, table);
    // `info` exposes the same user-facing weight/width fields as `style`, so
    // retain their validated range contract rather than decoding a looser
    // second representation.
    _ = try style(data, table);

    var result: Info = .{
        .version = version,
        .x_avg_char_width = try bin.readI16At(data, table.offset + 2),
        .weight_class = try bin.readU16At(data, table.offset + 4),
        .width_class = try bin.readU16At(data, table.offset + 6),
        .fs_type = try bin.readU16At(data, table.offset + 8),
        .subscript_x_size = try bin.readI16At(data, table.offset + 10),
        .subscript_y_size = try bin.readI16At(data, table.offset + 12),
        .subscript_x_offset = try bin.readI16At(data, table.offset + 14),
        .subscript_y_offset = try bin.readI16At(data, table.offset + 16),
        .superscript_x_size = try bin.readI16At(data, table.offset + 18),
        .superscript_y_size = try bin.readI16At(data, table.offset + 20),
        .superscript_x_offset = try bin.readI16At(data, table.offset + 22),
        .superscript_y_offset = try bin.readI16At(data, table.offset + 24),
        .strikeout_size = try bin.readI16At(data, table.offset + 26),
        .strikeout_position = try bin.readI16At(data, table.offset + 28),
        .family_class = try bin.readI16At(data, table.offset + 30),
        .panose = try readArray10(data, table.offset + 32),
        .unicode_ranges = .{
            try bin.readU32At(data, table.offset + 42),
            try bin.readU32At(data, table.offset + 46),
            try bin.readU32At(data, table.offset + 50),
            try bin.readU32At(data, table.offset + 54),
        },
        .vendor_id = try bin.readTagAt(data, table.offset + 58),
        .selection = try bin.readU16At(data, table.offset + 62),
        .first_char_index = try bin.readU16At(data, table.offset + 64),
        .last_char_index = try bin.readU16At(data, table.offset + 66),
        .typo_ascender = try bin.readI16At(data, table.offset + 68),
        .typo_descender = try bin.readI16At(data, table.offset + 70),
        .typo_line_gap = try bin.readI16At(data, table.offset + 72),
        .win_ascent = try bin.readU16At(data, table.offset + 74),
        .win_descent = try bin.readU16At(data, table.offset + 76),
    };
    if (version >= 1) {
        result.code_page_ranges = .{
            try bin.readU32At(data, table.offset + 78),
            try bin.readU32At(data, table.offset + 82),
        };
    }
    if (version >= 2) {
        result.x_height = try bin.readI16At(data, table.offset + 86);
        result.cap_height = try bin.readI16At(data, table.offset + 88);
        result.default_char = try bin.readU16At(data, table.offset + 90);
        result.break_char = try bin.readU16At(data, table.offset + 92);
        result.max_context = try bin.readU16At(data, table.offset + 94);
    }
    if (version >= 5) {
        result.lower_optical_point_size =
            try bin.readU16At(data, table.offset + 96);
        result.upper_optical_point_size =
            try bin.readU16At(data, table.offset + 98);
    }
    return result;
}

fn versionAndLength(data: []const u8, table: sfnt.Record) Error!u16 {
    try sfnt.requireLength(table, 2);
    const version = try bin.readU16At(data, table.offset);
    try sfnt.requireLength(table, try minimumLength(version));
    return version;
}

fn minimumLength(version: u16) Error!usize {
    // Even APIs using only early fields honor the complete versioned payload.
    // Otherwise a truncated v4/v5 table could borrow bytes from its neighbor.
    return switch (version) {
        0 => 78,
        1 => 86,
        2...4 => 96,
        5 => 100,
        else => error.BadSfnt,
    };
}

fn readArray10(data: []const u8, offset: usize) Error![10]u8 {
    if (offset > data.len or data.len - offset < 10) return error.BadSfnt;
    var value: [10]u8 = undefined;
    @memcpy(&value, data[offset .. offset + 10]);
    return value;
}
