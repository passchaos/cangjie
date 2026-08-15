//! Structural and cross-table validation for OpenType `CPAL` v0/v1.

const bin = @import("../../../../binary.zig");
const name = @import("../../../../opentype/name.zig");
const types = @import("types.zig");

const PayloadRange = struct {
    start: usize,
    end: usize,
};

const known_palette_type_mask: u32 = 0x0000_0003;

pub fn structure(
    data: []const u8,
    table: types.Table,
) types.Error!types.Layout {
    if (table.offset > data.len or table.length > data.len - table.offset) {
        return error.BadSfnt;
    }
    if (table.length < 12) return error.BadSfnt;

    const version = try bin.readU16At(data, table.offset);
    if (version > 1) return error.BadSfnt;
    const palette_entries = try bin.readU16At(data, table.offset + 2);
    const palette_count = try bin.readU16At(data, table.offset + 4);
    const color_count = try bin.readU16At(data, table.offset + 6);
    const color_records_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 8));

    const palette_indices_len = @as(usize, palette_count) * 2;
    if (palette_indices_len > table.length - 12) return error.BadSfnt;
    const version_0_header_len = 12 + palette_indices_len;
    var layout = types.Layout{
        .version = version,
        .palette_entries = palette_entries,
        .palette_count = palette_count,
        .color_count = color_count,
        .color_records_offset = color_records_offset,
    };

    const header_len = if (version == 1) header: {
        if (12 > table.length - version_0_header_len) return error.BadSfnt;
        layout.palette_types_offset = @intCast(try bin.readU32At(
            data,
            table.offset + version_0_header_len,
        ));
        layout.palette_labels_offset = @intCast(try bin.readU32At(
            data,
            table.offset + version_0_header_len + 4,
        ));
        layout.palette_entry_labels_offset = @intCast(try bin.readU32At(
            data,
            table.offset + version_0_header_len + 8,
        ));
        const extended_header_len = version_0_header_len + 12;
        try validatePaletteTypes(data, table, extended_header_len, layout);
        try validateOptionalArray(
            table,
            extended_header_len,
            layout.palette_labels_offset,
            palette_count,
            2,
        );
        try validateOptionalArray(
            table,
            extended_header_len,
            layout.palette_entry_labels_offset,
            palette_entries,
            2,
        );
        break :header extended_header_len;
    } else version_0_header_len;

    // firstColorIndex and extension offsets are metadata, not BGRA payload.
    // Keeping ColorRecordsArray after the complete header prevents malformed
    // tables from reinterpreting directory bytes as renderable colors.
    if (color_records_offset < header_len or
        color_records_offset > table.length)
    {
        return error.BadSfnt;
    }
    if (@as(usize, color_count) >
        (table.length - color_records_offset) / 4)
    {
        return error.BadSfnt;
    }

    if (version == 1) {
        try validateV1PayloadRanges(table, header_len, layout);
    }
    try validatePaletteSlices(data, table, layout);
    return layout;
}

pub fn nameReferences(
    data: []const u8,
    table: types.Table,
    layout: types.Layout,
    name_table: ?name.Table,
) types.Error!void {
    if (layout.version == 0) return;
    if (layout.palette_labels_offset == 0 and
        layout.palette_entry_labels_offset == 0)
    {
        return;
    }

    var name_index_storage: name.NameIdIndex = undefined;
    const name_index: ?*const name.NameIdIndex = if (name_table) |record| blk: {
        name_index_storage = try name.idIndex(data, record);
        break :blk &name_index_storage;
    } else null;

    // CPAL labels are optional name IDs rather than raw strings. Validate the
    // referenced name table as part of the same borrowed-byte read boundary.
    const header_len =
        12 + @as(usize, layout.palette_count) * 2 + 12;
    try validateNameIdArray(
        data,
        table,
        header_len,
        layout.palette_labels_offset,
        layout.palette_count,
        name_index,
    );
    try validateNameIdArray(
        data,
        table,
        header_len,
        layout.palette_entry_labels_offset,
        layout.palette_entries,
        name_index,
    );
}

fn validatePaletteSlices(
    data: []const u8,
    table: types.Table,
    layout: types.Layout,
) types.Error!void {
    var previous_first_color_index: ?usize = null;
    var previous_palette_end: ?usize = null;

    for (0..layout.palette_count) |palette_index| {
        const first_color_index: usize = @intCast(try bin.readU16At(
            data,
            table.offset + 12 + palette_index * 2,
        ));
        const entries: usize = @intCast(layout.palette_entries);
        const colors: usize = @intCast(layout.color_count);
        if (first_color_index > colors or
            entries > colors - first_color_index)
        {
            return error.BadSfnt;
        }

        if (previous_first_color_index) |previous_first| {
            // Canonical, disjoint slices prevent two palettes from silently
            // reinterpreting the same BGRA records.
            if (first_color_index <= previous_first or
                first_color_index < previous_palette_end.?)
            {
                return error.BadSfnt;
            }
        }
        previous_first_color_index = first_color_index;
        previous_palette_end = first_color_index + entries;
    }
}

fn validateV1PayloadRanges(
    table: types.Table,
    header_len: usize,
    layout: types.Layout,
) types.Error!void {
    var ranges: [4]PayloadRange = undefined;
    var range_count: usize = 0;
    try appendPayloadRange(
        &ranges,
        &range_count,
        table,
        header_len,
        layout.palette_types_offset,
        layout.palette_count,
        4,
    );
    try appendPayloadRange(
        &ranges,
        &range_count,
        table,
        header_len,
        layout.palette_labels_offset,
        layout.palette_count,
        2,
    );
    try appendPayloadRange(
        &ranges,
        &range_count,
        table,
        header_len,
        layout.palette_entry_labels_offset,
        layout.palette_entries,
        2,
    );
    try appendPayloadRange(
        &ranges,
        &range_count,
        table,
        header_len,
        layout.color_records_offset,
        layout.color_count,
        4,
    );

    for (ranges[0..range_count], 0..) |lhs, lhs_index| {
        for (ranges[lhs_index + 1 .. range_count]) |rhs| {
            // Independently typed v1 arrays may not alias, even when element
            // widths happen to match.
            if (lhs.start < rhs.end and rhs.start < lhs.end) {
                return error.BadSfnt;
            }
        }
    }
}

fn appendPayloadRange(
    ranges: *[4]PayloadRange,
    range_count: *usize,
    table: types.Table,
    header_len: usize,
    offset: usize,
    count: usize,
    item_size: usize,
) types.Error!void {
    if (offset == 0) return;
    try validateOptionalArray(table, header_len, offset, count, item_size);
    const byte_len = count * item_size;
    ranges[range_count.*] = .{ .start = offset, .end = offset + byte_len };
    range_count.* += 1;
}

fn validatePaletteTypes(
    data: []const u8,
    table: types.Table,
    header_len: usize,
    layout: types.Layout,
) types.Error!void {
    const offset = layout.palette_types_offset;
    if (offset == 0) return;
    try validateOptionalArray(
        table,
        header_len,
        offset,
        layout.palette_count,
        4,
    );
    for (0..layout.palette_count) |palette_index| {
        const palette_type = try bin.readU32At(
            data,
            table.offset + offset + palette_index * 4,
        );
        if (palette_type & ~known_palette_type_mask != 0) {
            return error.BadSfnt;
        }
    }
}

fn validateNameIdArray(
    data: []const u8,
    table: types.Table,
    header_len: usize,
    offset: usize,
    count: usize,
    name_index: ?*const name.NameIdIndex,
) types.Error!void {
    if (offset == 0) return;
    try validateOptionalArray(table, header_len, offset, count, 2);
    for (0..count) |index| {
        const name_id = try bin.readU16At(
            data,
            table.offset + offset + index * 2,
        );
        try name.validateOptionalIdReference(name_index, name_id);
    }
}

fn validateOptionalArray(
    table: types.Table,
    header_len: usize,
    offset: usize,
    count: usize,
    item_size: usize,
) types.Error!void {
    if (offset == 0) return;
    if (offset < header_len or offset > table.length) return error.BadSfnt;
    if (count > (table.length - offset) / item_size) return error.BadSfnt;
}
