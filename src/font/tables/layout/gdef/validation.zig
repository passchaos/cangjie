//! Top-level GDEF, attachment, ligature-caret, and variation-store validation.

const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const variation = @import("../../../../opentype/variation/root.zig");
const class_def = @import("class_def.zig");
const coverage = @import("coverage.zig");
const header = @import("header.zig");
const mark_sets = @import("mark_sets.zig");

const item_store = variation.item_store;

pub const Error = sfnt.Error || error{EndOfStream};

pub fn validate(
    data: []const u8,
    table: sfnt.Record,
    glyph_count: u16,
    variation_axis_count: ?usize,
) Error!void {
    const h = try header.read(data, table);
    const bytes = data[table.offset .. table.offset + table.length];

    if (h.glyph_class_def_offset != 0) {
        try validateClassDefChild(
            bytes,
            h.glyph_class_def_offset,
            h.length,
            glyph_count,
            true,
        );
    }
    if (h.attach_list_offset != 0) {
        try header.validateChildOffset(
            h.attach_list_offset,
            bytes.len,
            h.length,
        );
        try validateAttachList(bytes, h.attach_list_offset, glyph_count);
    }
    if (h.lig_caret_list_offset != 0) {
        try header.validateChildOffset(
            h.lig_caret_list_offset,
            bytes.len,
            h.length,
        );
        try validateLigCaretList(
            bytes,
            h.lig_caret_list_offset,
            glyph_count,
        );
    }
    if (h.mark_attach_class_def_offset != 0) {
        try validateClassDefChild(
            bytes,
            h.mark_attach_class_def_offset,
            h.length,
            glyph_count,
            false,
        );
    }
    if (h.mark_glyph_sets_def_offset) |offset| {
        if (offset != 0) {
            try header.validateChildOffset(offset, bytes.len, h.length);
            try mark_sets.validate(bytes, offset, glyph_count);
        }
    }
    if (h.item_variation_store_offset) |offset| {
        if (offset != 0) {
            try header.validateChildOffset(offset, bytes.len, h.length);
            const axis_count = variation_axis_count orelse return error.BadSfnt;
            _ = try item_store.validate(
                data,
                .{ .offset = table.offset, .length = table.length },
                offset,
                axis_count,
                h.length,
            );
        }
    }
}

fn validateClassDefChild(
    data: []const u8,
    offset: usize,
    header_len: usize,
    glyph_count: u16,
    validate_glyph_classes: bool,
) Error!void {
    try header.validateChildOffset(offset, data.len, header_len);
    try class_def.validateBounds(data, offset, glyph_count);
    if (validate_glyph_classes) {
        try class_def.validateGlyphClassValues(data, offset);
    }
}

fn validateAttachList(
    data: []const u8,
    offset: usize,
    glyph_count_bound: u16,
) Error!void {
    if (offset > data.len or data.len - offset < 4) return error.BadSfnt;
    const coverage_relative = try bin.readU16At(data, offset);
    const glyph_count = try bin.readU16At(data, offset + 2);
    const offsets_start = offset + 4;
    if (@as(usize, glyph_count) * 2 > data.len - offsets_start) {
        return error.BadSfnt;
    }

    const children_start = 4 + @as(usize, glyph_count) * 2;
    const coverage_offset = try childOffset(
        data,
        offset,
        coverage_relative,
        children_start,
    );
    try coverage.validate(
        data,
        coverage_offset,
        glyph_count_bound,
        .canonical,
    );
    if (try coverage.glyphCount(data, coverage_offset) != glyph_count) {
        return error.BadSfnt;
    }

    for (0..glyph_count) |index| {
        const relative = try bin.readU16At(data, offsets_start + index * 2);
        // AttachPoint offsets are a non-null parallel array to Coverage. Keep
        // every child after the complete offset array so malformed input cannot
        // reinterpret glyphCount or a sibling offset as a point count.
        try validateAttachPoint(
            data,
            try childOffset(data, offset, relative, children_start),
        );
    }
}

fn validateAttachPoint(data: []const u8, offset: usize) Error!void {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    const count = try bin.readU16At(data, offset);
    if (@as(usize, count) * 2 > data.len - (offset + 2)) {
        return error.BadSfnt;
    }
    var previous: ?u16 = null;
    for (0..count) |index| {
        const point = try bin.readU16At(data, offset + 2 + index * 2);
        if (previous) |last| {
            // Point indices are required to be strictly increasing; duplicate
            // or decreasing entries make attachment behavior order-dependent.
            if (point <= last) return error.BadSfnt;
        }
        previous = point;
    }
}

fn validateLigCaretList(
    data: []const u8,
    offset: usize,
    glyph_count_bound: u16,
) Error!void {
    if (offset > data.len or data.len - offset < 4) return error.BadSfnt;
    const coverage_relative = try bin.readU16At(data, offset);
    const ligature_count = try bin.readU16At(data, offset + 2);
    const offsets_start = offset + 4;
    if (@as(usize, ligature_count) * 2 > data.len - offsets_start) {
        return error.BadSfnt;
    }

    const children_start = 4 + @as(usize, ligature_count) * 2;
    const coverage_offset = try childOffset(
        data,
        offset,
        coverage_relative,
        children_start,
    );
    try coverage.validate(
        data,
        coverage_offset,
        glyph_count_bound,
        .canonical,
    );
    if (try coverage.glyphCount(data, coverage_offset) != ligature_count) {
        return error.BadSfnt;
    }

    for (0..ligature_count) |index| {
        const relative = try bin.readU16At(data, offsets_start + index * 2);
        // LigGlyph offsets have the same non-aliasing requirement as
        // AttachPoint offsets: they must not target count/offset words.
        try validateLigatureGlyph(
            data,
            try childOffset(data, offset, relative, children_start),
        );
    }
}

fn validateLigatureGlyph(data: []const u8, offset: usize) Error!void {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    const count = try bin.readU16At(data, offset);
    if (@as(usize, count) * 2 > data.len - (offset + 2)) {
        return error.BadSfnt;
    }
    const children_start = 2 + @as(usize, count) * 2;
    for (0..count) |index| {
        const relative = try bin.readU16At(data, offset + 2 + index * 2);
        try validateCaretValue(
            data,
            try childOffset(data, offset, relative, children_start),
        );
    }
}

fn validateCaretValue(data: []const u8, offset: usize) Error!void {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    switch (try bin.readU16At(data, offset)) {
        1 => try requireBytes(data, offset, 4),
        2 => {
            // The payload is an index into the covered glyph's outline and
            // cannot be bounded by GDEF/maxp alone. Runtime contour resolution
            // validates it against the concrete glyf instance and can decline
            // the optional caret when that point does not exist.
            try requireBytes(data, offset, 4);
        },
        3 => {
            try requireBytes(data, offset, 6);
            const relative = try bin.readU16At(data, offset + 4);
            if (relative == 0) return error.BadSfnt;
            try validateDeviceOrVariationIndex(
                data,
                try childOffset(data, offset, relative, 6),
            );
        },
        else => return error.BadSfnt,
    }
}

fn validateDeviceOrVariationIndex(
    data: []const u8,
    offset: usize,
) Error!void {
    try requireBytes(data, offset, 6);
    const start_size = try bin.readU16At(data, offset);
    const end_size = try bin.readU16At(data, offset + 2);
    const format = try bin.readU16At(data, offset + 4);
    // OpenType overloads Device offsets with a three-word VariationIndex when
    // DeltaFormat is 0x8000. Its first two words are outer/inner indices, not a
    // PPEM range, so there is intentionally no packed-delta payload to check.
    if (format == 0x8000) return;
    if (end_size < start_size) return error.BadSfnt;
    const bits_per_delta: usize = switch (format) {
        1 => 2,
        2 => 4,
        3 => 8,
        else => return error.BadSfnt,
    };
    const count = @as(usize, end_size) - @as(usize, start_size) + 1;
    try requireBytes(data, offset + 6, (count * bits_per_delta + 15) / 16 * 2);
}

fn childOffset(
    data: []const u8,
    base: usize,
    relative: usize,
    minimum_relative: usize,
) Error!usize {
    if (base > data.len or relative < minimum_relative or
        relative > data.len - base)
    {
        return error.BadSfnt;
    }
    return base + relative;
}

fn requireBytes(data: []const u8, offset: usize, len: usize) Error!void {
    if (offset > data.len or len > data.len - offset) return error.BadSfnt;
}
