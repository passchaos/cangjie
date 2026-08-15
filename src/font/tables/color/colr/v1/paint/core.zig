//! COLR v1 Paint format metadata and typed payload boundaries.

const bin = @import("../../../../../../binary.zig");
const types = @import("types.zig");

const max_extend_mode = 2;
const max_composite_mode = 27;

pub fn formatInfo(format: u8) ?types.FormatInfo {
    return switch (format) {
        1 => .{ .min_size = 6, .kind = .colr_layers },
        2, 3 => .{ .min_size = if (format == 2) 5 else 9, .kind = .solid },
        4, 6 => .{ .min_size = 16, .kind = .color_line },
        5, 7 => .{ .min_size = 20, .kind = .color_line },
        8 => .{ .min_size = 12, .kind = .color_line },
        9 => .{ .min_size = 16, .kind = .color_line },
        10 => .{ .min_size = 6, .kind = .glyph },
        11 => .{ .min_size = 3, .kind = .colr_glyph },
        12, 13 => .{ .min_size = 7, .kind = .single_child },
        14, 16, 28 => .{ .min_size = 8, .kind = .single_child },
        15, 17, 29 => .{ .min_size = 12, .kind = .single_child },
        18 => .{ .min_size = 12, .kind = .single_child },
        19 => .{ .min_size = 16, .kind = .single_child },
        20, 24 => .{ .min_size = 6, .kind = .single_child },
        21, 25 => .{ .min_size = 10, .kind = .single_child },
        22, 26 => .{ .min_size = 10, .kind = .single_child },
        23, 27 => .{ .min_size = 14, .kind = .single_child },
        30 => .{ .min_size = 12, .kind = .single_child },
        31 => .{ .min_size = 16, .kind = .single_child },
        32 => .{ .min_size = 8, .kind = .composite },
        else => null,
    };
}

pub fn validateRecord(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!types.FormatInfo {
    const table_end = table.offset + table.length;
    if (offset < table.offset or offset >= table_end) return error.BadSfnt;
    const format = data[offset];
    const info = formatInfo(format) orelse return error.BadSfnt;
    if (info.min_size > table_end - offset) return error.BadSfnt;
    if (format == 2 or format == 3) {
        try validateAlpha(try bin.readI16At(data, offset + 3));
    }
    if (info.kind == .color_line) {
        try validateColorLine(
            data,
            table,
            offset,
            info.min_size,
            usesVariableColorLine(format),
        );
    }
    switch (format) {
        12, 13 => _ = try transformPayloadRange(
            data,
            table,
            offset,
            info.min_size,
        ),
        else => {},
    }
    try validateChildPayloadOwnership(data, table, offset, info);
    if (format == 32 and data[offset + 4] > max_composite_mode) {
        return error.BadSfnt;
    }
    return info;
}

pub fn childOffset(
    data: []const u8,
    table: types.Table,
    offset: usize,
    parent_size: usize,
    field_offset: usize,
) types.Error!usize {
    const relative: usize = @intCast(try readU24(data, offset + field_offset));
    if (relative < parent_size) return error.BadSfnt;
    if (relative > table.offset + table.length - offset) return error.BadSfnt;
    return offset + relative;
}

pub fn headerRange(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!types.Range {
    const table_end = table.offset + table.length;
    if (offset < table.offset or offset >= table_end) return error.BadSfnt;
    const info = formatInfo(data[offset]) orelse return error.BadSfnt;
    if (info.min_size > table_end - offset) return error.BadSfnt;
    return .{ .start = offset, .end = offset + info.min_size };
}

pub fn transformPayloadRange(
    data: []const u8,
    table: types.Table,
    offset: usize,
    min_size: usize,
) types.Error!types.Range {
    const relative: usize = @intCast(try readU24(data, offset + 4));
    if (relative < min_size) return error.BadSfnt;
    if (relative > table.offset + table.length - offset) return error.BadSfnt;
    const matrix_offset = offset + relative;
    const matrix_size: usize = if (data[offset] == 13) 28 else 24;
    if (matrix_size > table.offset + table.length - matrix_offset) {
        return error.BadSfnt;
    }
    return .{ .start = matrix_offset, .end = matrix_offset + matrix_size };
}

pub fn colorLineRange(
    data: []const u8,
    table: types.Table,
    offset: usize,
    header_size: usize,
    variable: bool,
) types.Error!types.Range {
    const color_line = try childOffset(data, table, offset, header_size, 1);
    const table_end = table.offset + table.length;
    if (color_line + 3 > table_end) return error.BadSfnt;
    const stop_count: usize =
        @intCast(try bin.readU16At(data, color_line + 1));
    const stops_start = color_line + 3;
    const stop_size = colorStopSize(variable);
    if (stop_count > (table_end - stops_start) / stop_size) {
        return error.BadSfnt;
    }
    return .{
        .start = color_line,
        .end = stops_start + stop_count * stop_size,
    };
}

pub fn usesVariableColorLine(format: u8) bool {
    return format == 5 or format == 7 or format == 9;
}

pub fn colorStopSize(variable: bool) usize {
    return if (variable) 10 else 6;
}

pub fn overlaps(lhs: types.Range, rhs: types.Range) bool {
    return lhs.start < rhs.end and rhs.start < lhs.end;
}

fn validateChildPayloadOwnership(
    data: []const u8,
    table: types.Table,
    offset: usize,
    info: types.FormatInfo,
) types.Error!void {
    switch (data[offset]) {
        12, 13 => {
            const child = try childOffset(
                data,
                table,
                offset,
                info.min_size,
                1,
            );
            const child_header = try headerRange(data, table, child);
            const matrix = try transformPayloadRange(
                data,
                table,
                offset,
                info.min_size,
            );
            if (overlaps(child_header, matrix)) return error.BadSfnt;
        },
        32 => {
            const source = try childOffset(
                data,
                table,
                offset,
                info.min_size,
                1,
            );
            const backdrop = try childOffset(
                data,
                table,
                offset,
                info.min_size,
                5,
            );
            const source_header = try headerRange(data, table, source);
            const backdrop_header = try headerRange(data, table, backdrop);
            if (source_header.start == backdrop_header.start and
                source_header.end == backdrop_header.end)
            {
                return;
            }
            if (overlaps(source_header, backdrop_header)) return error.BadSfnt;
        },
        else => {},
    }
}

fn validateColorLine(
    data: []const u8,
    table: types.Table,
    offset: usize,
    header_size: usize,
    variable: bool,
) types.Error!void {
    const range = try colorLineRange(
        data,
        table,
        offset,
        header_size,
        variable,
    );
    if (data[range.start] > max_extend_mode) return error.BadSfnt;
    const stop_count: usize =
        @intCast(try bin.readU16At(data, range.start + 1));
    if (stop_count == 0) return error.BadSfnt;
    const stops_start = range.start + 3;
    const stop_size = colorStopSize(variable);
    var previous_stop = try bin.readI16At(data, stops_start);
    try validateAlpha(try bin.readI16At(data, stops_start + 4));
    for (1..stop_count) |index| {
        const stop = stops_start + index * stop_size;
        const current = try bin.readI16At(data, stop);
        if (current < previous_stop) return error.BadSfnt;
        try validateAlpha(try bin.readI16At(data, stop + 4));
        previous_stop = current;
    }
}

fn validateAlpha(raw: i16) types.Error!void {
    if (raw < 0 or raw > 0x4000) return error.BadSfnt;
}

fn readU24(data: []const u8, offset: usize) types.Error!u32 {
    if (offset > data.len or 3 > data.len - offset) return error.EndOfStream;
    return (@as(u32, data[offset]) << 16) |
        (@as(u32, data[offset + 1]) << 8) |
        data[offset + 2];
}
