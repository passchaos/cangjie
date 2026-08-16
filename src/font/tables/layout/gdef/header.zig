//! Versioned GDEF header decoding and top-level child offsets.

const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub fn read(data: []const u8, table: sfnt.Record) Error!types.Header {
    if (table.offset > data.len or table.length > data.len - table.offset or
        table.length < 12)
    {
        return error.BadSfnt;
    }
    const major = try bin.readU16At(data, table.offset);
    const minor = try bin.readU16At(data, table.offset + 2);
    if (major != 1) return error.BadSfnt;
    const length = minimumLength(minor);
    if (table.length < length) return error.BadSfnt;
    return .{
        .minor_version = minor,
        .length = length,
        .glyph_class_def_offset = try bin.readU16At(data, table.offset + 4),
        .attach_list_offset = try bin.readU16At(data, table.offset + 6),
        .lig_caret_list_offset = try bin.readU16At(data, table.offset + 8),
        .mark_attach_class_def_offset = try bin.readU16At(data, table.offset + 10),
        .mark_glyph_sets_def_offset = if (minor >= 2)
            try bin.readU16At(data, table.offset + 12)
        else
            null,
        .item_variation_store_offset = if (minor >= 3)
            try bin.readU32At(data, table.offset + 14)
        else
            null,
    };
}

pub fn minimumLength(minor: u16) usize {
    return if (minor >= 3) 18 else if (minor >= 2) 14 else 12;
}

pub fn validateChildOffset(
    offset: usize,
    table_len: usize,
    header_len: usize,
) Error!void {
    // Every top-level GDEF offset names a child table relative to GDEF. It
    // therefore cannot point into the versioned header itself; accepting that
    // alias would let later ClassDef/Coverage readers reinterpret header words
    // as attacker-controlled records.
    if (offset < header_len or offset >= table_len) return error.BadSfnt;
}
