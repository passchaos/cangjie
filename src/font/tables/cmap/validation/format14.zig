//! cmap format-14 variation-selector structure and payload ownership.

const bin = @import("../../../../binary.zig");
const policy = @import("../policy.zig");

pub const Error = error{ BadSfnt, EndOfStream };

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 10) return error.BadSfnt;
    const record_count: usize = @intCast(try bin.readU32At(data, offset + 6));
    const records_end = try recordsEnd(length, record_count);

    const table_end = offset + length;
    var previous_selector: ?u32 = null;
    for (0..record_count) |index| {
        const record = offset + 10 + index * 11;
        const selector = try policy.readU24(data, record);
        if (!policy.isVariationSelector(selector)) return error.BadSfnt;
        if (previous_selector) |last_selector| {
            // Variation selector records are consumed with an early-exit search
            // in glyphIndexFormat14. Reject unsorted/duplicate selectors here
            // so malformed cmaps cannot make mappings depend on record order.
            if (selector <= last_selector) return error.BadSfnt;
        }
        previous_selector = selector;

        const default_offset = try bin.readU32At(data, record + 3);
        const non_default_offset = try bin.readU32At(data, record + 7);
        if (default_offset != 0) {
            const default_payload_offset = try payloadOffset(default_offset, records_end, length);
            const default_absolute = offset + default_payload_offset;
            const default_range = try cmapFormat14DefaultUvsRange(data, default_absolute, table_end);
            try validateCmapFormat14DefaultUvs(data, default_absolute, table_end);
            try validateCmapFormat14UvsRangeDoesNotAliasRecords(
                data,
                offset,
                table_end,
                index,
                default_range,
            );
        }
        if (non_default_offset != 0) {
            const non_default_payload_offset = try payloadOffset(non_default_offset, records_end, length);
            const non_default_absolute = offset + non_default_payload_offset;
            const non_default_range = try cmapFormat14NonDefaultUvsRange(data, non_default_absolute, table_end);
            try validateCmapFormat14NonDefaultUvs(data, non_default_absolute, table_end);
            try validateCmapFormat14UvsRangeDoesNotAliasRecords(
                data,
                offset,
                table_end,
                index,
                non_default_range,
            );
        }
        if (default_offset != 0 and non_default_offset != 0) {
            const default_absolute = offset + try payloadOffset(default_offset, records_end, length);
            const non_default_absolute = offset + try payloadOffset(non_default_offset, records_end, length);
            const default_range = try cmapFormat14DefaultUvsRange(data, default_absolute, table_end);
            const non_default_range = try cmapFormat14NonDefaultUvsRange(data, non_default_absolute, table_end);
            if (payloadRangesOverlap(default_range, non_default_range)) return error.BadSfnt;
            try validateCmapFormat14UvsSetsDisjoint(
                data,
                default_absolute,
                non_default_absolute,
                table_end,
            );
        }
    }
}

const CmapFormat14PayloadRange = struct {
    start: usize,
    end: usize,
};

pub fn recordsEnd(length: usize, record_count: usize) Error!usize {
    if (length < 10) return error.BadSfnt;
    if (record_count > (length - 10) / 11) return error.BadSfnt;
    return 10 + record_count * 11;
}

pub fn payloadOffset(
    payload_offset: u32,
    records_end: usize,
    length: usize,
) Error!usize {
    const offset: usize = @intCast(payload_offset);
    // A non-zero UVS payload offset must name a child array after the complete
    // VariationSelectorRecord directory. Keeping this check in one helper lets
    // both parse-time validation and lazy lookup reject record-directory aliases
    // with the same boundary contract.
    if (offset < records_end or offset >= length) return error.BadSfnt;
    return offset;
}

fn cmapFormat14DefaultUvsRange(data: []const u8, offset: usize, table_end: usize) Error!CmapFormat14PayloadRange {
    if (offset + 4 > table_end) return error.BadSfnt;
    const range_count: usize = @intCast(try bin.readU32At(data, offset));
    if (range_count > (table_end - (offset + 4)) / 4) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 4 + range_count * 4 };
}

fn cmapFormat14NonDefaultUvsRange(data: []const u8, offset: usize, table_end: usize) Error!CmapFormat14PayloadRange {
    if (offset + 4 > table_end) return error.BadSfnt;
    const mapping_count: usize = @intCast(try bin.readU32At(data, offset));
    if (mapping_count > (table_end - (offset + 4)) / 5) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 4 + mapping_count * 5 };
}

fn payloadRangesOverlap(a: CmapFormat14PayloadRange, b: CmapFormat14PayloadRange) bool {
    return a.start < b.end and b.start < a.end;
}

fn validateCmapFormat14UvsRangeDoesNotAliasRecords(
    data: []const u8,
    cmap_offset: usize,
    table_end: usize,
    current_record_index: usize,
    candidate: CmapFormat14PayloadRange,
) Error!void {
    // Each format-14 UVS array is a variable-length child table. Offsets that
    // point into another selector's child payload make two records share bytes
    // with incompatible ownership, so a later edit to one selector can silently
    // reinterpret the other's Unicode ranges or glyph IDs. Reject aliasing at
    // parse time, while still permitting adjacent payloads.
    for (0..current_record_index) |previous_index| {
        const previous_record = cmap_offset + 10 + previous_index * 11;
        const previous_default_offset = try bin.readU32At(data, previous_record + 3);
        if (previous_default_offset != 0) {
            const previous_range = try cmapFormat14DefaultUvsRange(
                data,
                cmap_offset + @as(usize, previous_default_offset),
                table_end,
            );
            if (payloadRangesOverlap(candidate, previous_range)) return error.BadSfnt;
        }

        const previous_non_default_offset = try bin.readU32At(data, previous_record + 7);
        if (previous_non_default_offset != 0) {
            const previous_range = try cmapFormat14NonDefaultUvsRange(
                data,
                cmap_offset + @as(usize, previous_non_default_offset),
                table_end,
            );
            if (payloadRangesOverlap(candidate, previous_range)) return error.BadSfnt;
        }
    }
}

fn validateCmapFormat14DefaultUvs(
    data: []const u8,
    offset: usize,
    table_end: usize,
) Error!void {
    if (offset + 4 > table_end) return error.BadSfnt;
    const range_count: usize = @intCast(try bin.readU32At(data, offset));
    if (range_count > (table_end - (offset + 4)) / 4) return error.BadSfnt;

    var previous_end: ?u32 = null;
    for (0..range_count) |index| {
        const range = offset + 4 + index * 4;
        const start = try policy.readU24(data, range);
        if (!policy.isUnicodeScalar(start)) return error.BadSfnt;
        const end_u64 = @as(u64, start) + data[range + 3];
        if (end_u64 > 0x10ffff) return error.BadSfnt;
        const end: u32 = @intCast(end_u64);
        if (!policy.isUnicodeScalar(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;
    }
}

fn validateCmapFormat14NonDefaultUvs(
    data: []const u8,
    offset: usize,
    table_end: usize,
) Error!void {
    if (offset + 4 > table_end) return error.BadSfnt;
    const mapping_count: usize = @intCast(try bin.readU32At(data, offset));
    if (mapping_count > (table_end - (offset + 4)) / 5) return error.BadSfnt;

    var previous_unicode: ?u32 = null;
    for (0..mapping_count) |index| {
        const mapping = offset + 4 + index * 5;
        const unicode_value = try policy.readU24(data, mapping);
        if (!policy.isUnicodeScalar(unicode_value)) return error.BadSfnt;
        if (previous_unicode) |last_unicode| {
            if (unicode_value <= last_unicode) return error.BadSfnt;
        }
        previous_unicode = unicode_value;
    }
}

fn validateCmapFormat14UvsSetsDisjoint(
    data: []const u8,
    default_offset: usize,
    non_default_offset: usize,
    table_end: usize,
) Error!void {
    const default_count: usize = @intCast(try bin.readU32At(data, default_offset));
    const non_default_count: usize = @intCast(try bin.readU32At(data, non_default_offset));
    if (default_count > (table_end - (default_offset + 4)) / 4) return error.BadSfnt;
    if (non_default_count > (table_end - (non_default_offset + 4)) / 5) return error.BadSfnt;

    // A Unicode variation sequence is either default (use the base cmap glyph)
    // or non-default (use the explicit UVS glyph), never both for the same
    // selector. The two arrays are already validated as sorted, so a linear
    // merge detects contradictory records without allocating per-selector side
    // tables even for large CJK variation maps.
    var default_index: usize = 0;
    for (0..non_default_count) |mapping_index| {
        const mapping = non_default_offset + 4 + mapping_index * 5;
        const unicode_value = try policy.readU24(data, mapping);

        while (default_index < default_count) {
            const range = default_offset + 4 + default_index * 4;
            const start = try policy.readU24(data, range);
            const end = start + data[range + 3];
            if (end >= unicode_value) break;
            default_index += 1;
        }
        if (default_index < default_count) {
            const range = default_offset + 4 + default_index * 4;
            const start = try policy.readU24(data, range);
            const end = start + data[range + 3];
            if (unicode_value >= start and unicode_value <= end) return error.BadSfnt;
        }
    }
}
