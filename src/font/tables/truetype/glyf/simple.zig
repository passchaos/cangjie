//! TrueType simple-glyph structural and maxp-summary validation.

const bin = @import("../../../../binary.zig");

pub const Error = error{ InvalidGlyph, EndOfStream };

pub fn validate(
    glyph_data: []const u8,
    contour_count: u16,
    max_points: u16,
    max_contours: u16,
) Error!usize {
    const point_count = try pointCount(glyph_data, contour_count);
    // maxp summaries let clients size outline work buffers before reading an
    // individual glyph, so under-reporting is a structural font inconsistency.
    if (point_count > max_points or contour_count > max_contours) {
        return error.InvalidGlyph;
    }
    return point_count;
}

pub fn validateFlag(flag: u8, point_index: usize) Error!void {
    // Bit 7 is reserved; OVERLAP_SIMPLE is meaningful only on the first
    // logical flag after RLE expansion.
    if ((flag & 0x80) != 0) return error.InvalidGlyph;
    if (point_index != 0 and (flag & 0x40) != 0) {
        return error.InvalidGlyph;
    }
}

fn pointCount(glyph_data: []const u8, contour_count: u16) Error!usize {
    if (contour_count == 0) return 0;

    var offset: usize = 10; // numberOfContours + x/y bounds.
    var total_points: usize = 0;
    var previous_end: ?u16 = null;
    for (0..contour_count) |_| {
        if (offset > glyph_data.len or glyph_data.len - offset < 2) {
            return error.InvalidGlyph;
        }
        const end = try bin.readU16At(glyph_data, offset);
        offset += 2;
        if (previous_end) |previous| {
            if (end <= previous) return error.InvalidGlyph;
        }
        previous_end = end;
        total_points = @as(usize, end) + 1;
    }

    if (offset > glyph_data.len or glyph_data.len - offset < 2) {
        return error.InvalidGlyph;
    }
    const instruction_len = try bin.readU16At(glyph_data, offset);
    offset += 2;
    if (instruction_len > glyph_data.len - offset) return error.InvalidGlyph;
    offset += instruction_len;

    // Flags are RLE; X and Y deltas follow as separate streams. Count both
    // streams while expanding the logical flags without allocating.
    var expanded_flags: usize = 0;
    var x_bytes: usize = 0;
    var y_bytes: usize = 0;
    while (expanded_flags < total_points) {
        if (offset >= glyph_data.len) return error.InvalidGlyph;
        const flag = glyph_data[offset];
        try validateFlag(flag, expanded_flags);
        offset += 1;
        expanded_flags += 1;
        x_bytes += coordinateByteCount(flag, true);
        y_bytes += coordinateByteCount(flag, false);
        if ((flag & 0x08) != 0) {
            if (offset >= glyph_data.len) return error.InvalidGlyph;
            const repeat = glyph_data[offset];
            offset += 1;
            if (@as(usize, repeat) > total_points - expanded_flags) {
                return error.InvalidGlyph;
            }
            if (repeat != 0) try validateFlag(flag, expanded_flags);
            expanded_flags += repeat;
            x_bytes += @as(usize, repeat) * coordinateByteCount(flag, true);
            y_bytes += @as(usize, repeat) * coordinateByteCount(flag, false);
        }
    }

    if (x_bytes > glyph_data.len - offset) return error.InvalidGlyph;
    offset += x_bytes;
    if (y_bytes > glyph_data.len - offset) return error.InvalidGlyph;
    return total_points;
}

fn coordinateByteCount(flag: u8, x_axis: bool) usize {
    const short_vector: u8 = if (x_axis) 0x02 else 0x04;
    const same_or_positive: u8 = if (x_axis) 0x10 else 0x20;
    if ((flag & short_vector) != 0) return 1;
    if ((flag & same_or_positive) != 0) return 0;
    return 2;
}
