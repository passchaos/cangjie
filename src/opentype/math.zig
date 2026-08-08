const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const ValueRecord = struct {
    value: i16,
    device_offset: u16,
};

pub const GlyphValueRecord = struct {
    glyph_id: u16,
    value_record: ValueRecord,
};

pub const Constants = struct {
    script_percent_scale_down: i16,
    script_script_percent_scale_down: i16,
    delimited_sub_formula_min_height: u16,
    display_operator_min_height: u16,
    value_records: []ValueRecord,
    radical_degree_bottom_raise_percent: i16,
};

pub const GlyphInfo = struct {
    italics_correction_info_offset: ?usize,
    top_accent_attachment_offset: ?usize,
    extended_shape_coverage_offset: ?usize,
    math_kern_info_offset: ?usize,
    italics_corrections: []GlyphValueRecord,
    top_accent_attachments: []GlyphValueRecord,
    extended_shape_glyphs: []u16,
};

pub const VariantRecord = struct {
    glyph_id: u16,
    advance_measurement: u16,
};

pub const PartRecord = struct {
    glyph_id: u16,
    start_connector_length: u16,
    end_connector_length: u16,
    full_advance: u16,
    flags: u16,
};

pub const Assembly = struct {
    italics_correction: ValueRecord,
    parts: []PartRecord,
};

pub const Construction = struct {
    index: usize,
    glyph_id: u16,
    vertical: bool,
    offset: usize,
    assembly_offset: ?usize,
    assembly: ?Assembly,
    variants: []VariantRecord,
};

pub const Variants = struct {
    min_connector_overlap: u16,
    vertical_coverage_offset: ?usize,
    horizontal_coverage_offset: ?usize,
    vertical_glyphs: []u16,
    horizontal_glyphs: []u16,
    construction_offsets: []?usize,
    constructions: []Construction,
};

pub const Info = struct {
    version: u32,
    constants_offset: usize,
    glyph_info_offset: usize,
    variants_offset: usize,
    constants: Constants,
    glyph_info: GlyphInfo,
    variants: Variants,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const h = try header(data, offset, length);
    try validateConstants(data, offset, length, h.constants_offset);
    try validateGlyphInfo(data, offset, length, h.glyph_info_offset);
    try validateVariants(data, offset, length, h.variants_offset);
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!Info {
    const h = try header(data, offset, length);
    try validate(data, offset, length);
    const constants = try readConstants(allocator, data, offset, h.constants_offset);
    errdefer freeConstants(allocator, constants);
    const glyph_info = try readGlyphInfo(allocator, data, offset, length, h.glyph_info_offset);
    errdefer freeGlyphInfo(allocator, glyph_info);
    const variants = try readVariants(allocator, data, offset, length, h.variants_offset);
    errdefer freeVariants(allocator, variants);
    return .{
        .version = h.version,
        .constants_offset = h.constants_offset,
        .glyph_info_offset = h.glyph_info_offset,
        .variants_offset = h.variants_offset,
        .constants = constants,
        .glyph_info = glyph_info,
        .variants = variants,
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    freeConstants(allocator, value.constants);
    freeGlyphInfo(allocator, value.glyph_info);
    freeVariants(allocator, value.variants);
}

fn freeGlyphInfo(allocator: std.mem.Allocator, value: GlyphInfo) void {
    allocator.free(value.italics_corrections);
    allocator.free(value.top_accent_attachments);
    allocator.free(value.extended_shape_glyphs);
}

fn freeVariants(allocator: std.mem.Allocator, value: Variants) void {
    for (value.constructions) |construction| {
        if (construction.assembly) |assembly| allocator.free(assembly.parts);
        allocator.free(construction.variants);
    }
    allocator.free(value.vertical_glyphs);
    allocator.free(value.horizontal_glyphs);
    allocator.free(value.construction_offsets);
    allocator.free(value.constructions);
}

fn freeConstants(allocator: std.mem.Allocator, value: Constants) void {
    allocator.free(value.value_records);
}

const Header = struct {
    version: u32,
    constants_offset: usize,
    glyph_info_offset: usize,
    variants_offset: usize,
};

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 10) return error.BadSfnt;
    const major = try bin.readU16At(data, offset);
    const minor = try bin.readU16At(data, offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const constants_offset: usize = @intCast(try bin.readU16At(data, offset + 4));
    const glyph_info_offset: usize = @intCast(try bin.readU16At(data, offset + 6));
    const variants_offset: usize = @intCast(try bin.readU16At(data, offset + 8));
    try validateChildOffset(constants_offset, length, 214);
    return .{
        .version = (@as(u32, major) << 16) | minor,
        .constants_offset = constants_offset,
        .glyph_info_offset = glyph_info_offset,
        .variants_offset = variants_offset,
    };
}

fn validateChildOffset(child_offset: usize, table_length: usize, min_len: usize) Error!void {
    if (child_offset == 0 or child_offset > table_length or min_len > table_length - child_offset) return error.BadSfnt;
}

fn validateConstants(data: []const u8, table_offset: usize, table_length: usize, constants_offset: usize) Error!void {
    try validateChildOffset(constants_offset, table_length, 214);
    const constants = table_offset + constants_offset;
    for (0..51) |index| {
        const record_offset = constants + 8 + index * 4;
        const device_offset = try bin.readU16At(data, record_offset + 2);
        if (device_offset != 0) try validateDeviceTable(data, table_offset, table_length, constants_offset, device_offset);
    }
}

fn validateGlyphInfo(data: []const u8, table_offset: usize, table_length: usize, glyph_info_offset: usize) Error!void {
    try validateChildOffset(glyph_info_offset, table_length, 8);
    const start = table_offset + glyph_info_offset;
    const italic_offset = try bin.readU16At(data, start);
    const accent_offset = try bin.readU16At(data, start + 2);
    const extended_offset = try bin.readU16At(data, start + 4);
    const kern_offset = try bin.readU16At(data, start + 6);
    if (italic_offset != 0) try validateMathValueArraySubtable(data, table_offset, table_length, glyph_info_offset + @as(usize, italic_offset));
    if (accent_offset != 0) try validateMathValueArraySubtable(data, table_offset, table_length, glyph_info_offset + @as(usize, accent_offset));
    if (extended_offset != 0) _ = try coverageGlyphCount(data, table_offset, table_length, glyph_info_offset + @as(usize, extended_offset));
    if (kern_offset != 0) try validateChildWithinParent(kern_offset, table_length, glyph_info_offset, 2);
}

fn validateChildWithinParent(child_offset: u16, table_length: usize, parent_offset: usize, min_len: usize) Error!void {
    const relative = parent_offset + @as(usize, child_offset);
    if (relative > table_length or min_len > table_length - relative) return error.BadSfnt;
}

fn validateVariants(data: []const u8, table_offset: usize, table_length: usize, variants_offset: usize) Error!void {
    try validateChildOffset(variants_offset, table_length, 10);
    const start = table_offset + variants_offset;
    const vert_coverage_offset = try bin.readU16At(data, start + 2);
    const horiz_coverage_offset = try bin.readU16At(data, start + 4);
    const vert_count: usize = @intCast(try bin.readU16At(data, start + 6));
    const horiz_count: usize = @intCast(try bin.readU16At(data, start + 8));
    const construction_count = vert_count + horiz_count;
    if (construction_count > (table_length - variants_offset - 10) / 2) return error.BadSfnt;
    if (vert_count != 0) {
        if (vert_coverage_offset == 0) return error.BadSfnt;
        if (try coverageGlyphCount(data, table_offset, table_length, variants_offset + @as(usize, vert_coverage_offset)) != vert_count) return error.BadSfnt;
    }
    if (horiz_count != 0) {
        if (horiz_coverage_offset == 0) return error.BadSfnt;
        if (try coverageGlyphCount(data, table_offset, table_length, variants_offset + @as(usize, horiz_coverage_offset)) != horiz_count) return error.BadSfnt;
    }
    for (0..construction_count) |index| {
        const construction_offset = try bin.readU16At(data, start + 10 + index * 2);
        if (construction_offset != 0) try validateGlyphConstruction(data, table_offset, table_length, variants_offset + @as(usize, construction_offset));
    }
}

fn validateGlyphConstruction(data: []const u8, table_offset: usize, table_length: usize, construction_offset: usize) Error!void {
    try validateChildOffset(construction_offset, table_length, 4);
    const start = table_offset + construction_offset;
    const assembly_offset = try bin.readU16At(data, start);
    const variant_count: usize = @intCast(try bin.readU16At(data, start + 2));
    if (variant_count > (table_length - construction_offset - 4) / 4) return error.BadSfnt;
    if (assembly_offset != 0) try validateGlyphAssembly(data, table_offset, table_length, construction_offset + @as(usize, assembly_offset));
}

fn validateGlyphAssembly(data: []const u8, table_offset: usize, table_length: usize, assembly_offset: usize) Error!void {
    try validateChildOffset(assembly_offset, table_length, 6);
    const start = table_offset + assembly_offset;
    const device_offset = try bin.readU16At(data, start + 2);
    if (device_offset != 0) try validateDeviceTable(data, table_offset, table_length, assembly_offset, device_offset);
    const part_count: usize = @intCast(try bin.readU16At(data, start + 4));
    if (part_count > (table_length - assembly_offset - 6) / 10) return error.BadSfnt;
    for (0..part_count) |index| {
        const part = start + 6 + index * 10;
        const flags = try bin.readU16At(data, part + 8);
        if ((flags & ~@as(u16, 0x0001)) != 0) return error.BadSfnt;
    }
}

fn readVariants(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, variants_offset: usize) Error!Variants {
    try validateVariants(data, table_offset, table_length, variants_offset);
    const start = table_offset + variants_offset;
    const vert_coverage_offset = try bin.readU16At(data, start + 2);
    const horiz_coverage_offset = try bin.readU16At(data, start + 4);
    const vert_count: usize = @intCast(try bin.readU16At(data, start + 6));
    const horiz_count: usize = @intCast(try bin.readU16At(data, start + 8));
    const vertical_glyphs = if (vert_count != 0)
        try coverageGlyphs(allocator, data, table_offset, table_length, variants_offset + @as(usize, vert_coverage_offset))
    else
        try allocator.alloc(u16, 0);
    errdefer allocator.free(vertical_glyphs);
    const horizontal_glyphs = if (horiz_count != 0)
        try coverageGlyphs(allocator, data, table_offset, table_length, variants_offset + @as(usize, horiz_coverage_offset))
    else
        try allocator.alloc(u16, 0);
    errdefer allocator.free(horizontal_glyphs);
    const construction_count = vert_count + horiz_count;
    const construction_offsets = try allocator.alloc(?usize, construction_count);
    errdefer allocator.free(construction_offsets);
    var non_null_construction_count: usize = 0;
    for (construction_offsets, 0..) |*value, index| {
        const raw = try bin.readU16At(data, start + 10 + index * 2);
        value.* = nullableOffset(raw);
        if (value.* != null) non_null_construction_count += 1;
    }

    const constructions = try allocator.alloc(Construction, non_null_construction_count);
    var initialized: usize = 0;
    errdefer {
        for (constructions[0..initialized]) |construction| {
            if (construction.assembly) |assembly| allocator.free(assembly.parts);
            allocator.free(construction.variants);
        }
        allocator.free(constructions);
    }
    for (construction_offsets, 0..) |maybe_offset, index| {
        const construction_offset = maybe_offset orelse continue;
        const vertical = index < vert_count;
        const glyph_id = if (vertical) vertical_glyphs[index] else horizontal_glyphs[index - vert_count];
        constructions[initialized] = try readGlyphConstruction(allocator, data, table_offset, table_length, index, glyph_id, vertical, variants_offset + construction_offset);
        initialized += 1;
    }

    return .{
        .min_connector_overlap = try bin.readU16At(data, start),
        .vertical_coverage_offset = nullableOffset(vert_coverage_offset),
        .horizontal_coverage_offset = nullableOffset(horiz_coverage_offset),
        .vertical_glyphs = vertical_glyphs,
        .horizontal_glyphs = horizontal_glyphs,
        .construction_offsets = construction_offsets,
        .constructions = constructions,
    };
}

fn readGlyphConstruction(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, index: usize, glyph_id: u16, vertical: bool, construction_offset: usize) Error!Construction {
    try validateGlyphConstruction(data, table_offset, table_length, construction_offset);
    const start = table_offset + construction_offset;
    const assembly_offset_raw = try bin.readU16At(data, start);
    const variant_count: usize = @intCast(try bin.readU16At(data, start + 2));
    const variants = try allocator.alloc(VariantRecord, variant_count);
    errdefer allocator.free(variants);
    for (variants, 0..) |*variant, variant_index| {
        const record = start + 4 + variant_index * 4;
        variant.* = .{
            .glyph_id = try bin.readU16At(data, record),
            .advance_measurement = try bin.readU16At(data, record + 2),
        };
    }
    const assembly = if (assembly_offset_raw != 0)
        try readGlyphAssembly(allocator, data, table_offset, construction_offset + @as(usize, assembly_offset_raw))
    else
        null;
    errdefer if (assembly) |value| allocator.free(value.parts);
    return .{
        .index = index,
        .glyph_id = glyph_id,
        .vertical = vertical,
        .offset = construction_offset,
        .assembly_offset = nullableOffset(assembly_offset_raw),
        .assembly = assembly,
        .variants = variants,
    };
}

fn readGlyphAssembly(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, assembly_offset: usize) Error!Assembly {
    const start = table_offset + assembly_offset;
    const part_count: usize = @intCast(try bin.readU16At(data, start + 4));
    const parts = try allocator.alloc(PartRecord, part_count);
    errdefer allocator.free(parts);
    for (parts, 0..) |*out, index| {
        const part = start + 6 + index * 10;
        out.* = .{
            .glyph_id = try bin.readU16At(data, part),
            .start_connector_length = try bin.readU16At(data, part + 2),
            .end_connector_length = try bin.readU16At(data, part + 4),
            .full_advance = try bin.readU16At(data, part + 6),
            .flags = try bin.readU16At(data, part + 8),
        };
    }
    return .{
        .italics_correction = .{ .value = try bin.readI16At(data, start), .device_offset = try bin.readU16At(data, start + 2) },
        .parts = parts,
    };
}

fn validateDeviceTable(data: []const u8, table_offset: usize, table_length: usize, parent_offset: usize, device_offset: u16) Error!void {
    const absolute_relative = parent_offset + @as(usize, device_offset);
    if (absolute_relative > table_length or table_length - absolute_relative < 6) return error.BadSfnt;
    const start = table_offset + absolute_relative;
    const start_size = try bin.readU16At(data, start);
    const end_size = try bin.readU16At(data, start + 2);
    const delta_format = try bin.readU16At(data, start + 4);
    if (start_size > end_size) return error.BadSfnt;
    const bits_per_delta: usize = switch (delta_format) {
        1 => 2,
        2 => 4,
        3 => 8,
        else => return error.BadSfnt,
    };
    const value_count = @as(usize, end_size - start_size) + 1;
    const word_count = (value_count * bits_per_delta + 15) / 16;
    if (word_count * 2 > table_length - absolute_relative - 6) return error.BadSfnt;
}

fn readGlyphInfo(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, glyph_info_offset: usize) Error!GlyphInfo {
    try validateGlyphInfo(data, table_offset, table_length, glyph_info_offset);
    const start = table_offset + glyph_info_offset;
    const italic_offset = try bin.readU16At(data, start);
    const accent_offset = try bin.readU16At(data, start + 2);
    const extended_offset = try bin.readU16At(data, start + 4);
    const kern_offset = try bin.readU16At(data, start + 6);
    const italics = if (italic_offset != 0)
        try readMathValueArraySubtable(allocator, data, table_offset, table_length, glyph_info_offset + @as(usize, italic_offset))
    else
        try allocator.alloc(GlyphValueRecord, 0);
    errdefer allocator.free(italics);
    const top_accents = if (accent_offset != 0)
        try readMathValueArraySubtable(allocator, data, table_offset, table_length, glyph_info_offset + @as(usize, accent_offset))
    else
        try allocator.alloc(GlyphValueRecord, 0);
    errdefer allocator.free(top_accents);
    const extended_shape_glyphs = if (extended_offset != 0)
        try coverageGlyphs(allocator, data, table_offset, table_length, glyph_info_offset + @as(usize, extended_offset))
    else
        try allocator.alloc(u16, 0);
    errdefer allocator.free(extended_shape_glyphs);
    return .{
        .italics_correction_info_offset = nullableOffset(italic_offset),
        .top_accent_attachment_offset = nullableOffset(accent_offset),
        .extended_shape_coverage_offset = nullableOffset(extended_offset),
        .math_kern_info_offset = nullableOffset(kern_offset),
        .italics_corrections = italics,
        .top_accent_attachments = top_accents,
        .extended_shape_glyphs = extended_shape_glyphs,
    };
}

fn nullableOffset(value: u16) ?usize {
    return if (value == 0) null else @intCast(value);
}

fn validateMathValueArraySubtable(data: []const u8, table_offset: usize, table_length: usize, subtable_offset: usize) Error!void {
    try validateChildOffset(subtable_offset, table_length, 4);
    const start = table_offset + subtable_offset;
    const coverage_offset: usize = @intCast(try bin.readU16At(data, start));
    if (coverage_offset == 0) return error.BadSfnt;
    const coverage_count = try coverageGlyphCount(data, table_offset, table_length, subtable_offset + coverage_offset);
    const value_count: usize = @intCast(try bin.readU16At(data, start + 2));
    if (value_count != coverage_count) return error.BadSfnt;
    if (value_count > (table_length - subtable_offset - 4) / 4) return error.BadSfnt;
    for (0..value_count) |index| {
        const value_record = start + 4 + index * 4;
        const device_offset = try bin.readU16At(data, value_record + 2);
        if (device_offset != 0) try validateDeviceTable(data, table_offset, table_length, subtable_offset, device_offset);
    }
}

fn readMathValueArraySubtable(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, subtable_offset: usize) Error![]GlyphValueRecord {
    try validateMathValueArraySubtable(data, table_offset, table_length, subtable_offset);
    const start = table_offset + subtable_offset;
    const coverage_offset: usize = @intCast(try bin.readU16At(data, start));
    const glyphs = try coverageGlyphs(allocator, data, table_offset, table_length, subtable_offset + coverage_offset);
    defer allocator.free(glyphs);
    const records = try allocator.alloc(GlyphValueRecord, glyphs.len);
    errdefer allocator.free(records);
    for (records, 0..) |*record, index| {
        const value_record = start + 4 + index * 4;
        record.* = .{
            .glyph_id = glyphs[index],
            .value_record = .{
                .value = try bin.readI16At(data, value_record),
                .device_offset = try bin.readU16At(data, value_record + 2),
            },
        };
    }
    return records;
}

fn coverageGlyphCount(data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize) Error!usize {
    try validateChildOffset(coverage_offset, table_length, 4);
    const start = table_offset + coverage_offset;
    const format = try bin.readU16At(data, start);
    return switch (format) {
        1 => count: {
            const count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (count > (table_length - coverage_offset - 4) / 2) return error.BadSfnt;
            var previous: ?u16 = null;
            for (0..count) |index| {
                const glyph = try bin.readU16At(data, start + 4 + index * 2);
                if (previous) |last| if (glyph <= last) return error.BadSfnt;
                previous = glyph;
            }
            break :count count;
        },
        2 => count: {
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (range_count > (table_length - coverage_offset - 4) / 6) return error.BadSfnt;
            var total: usize = 0;
            var previous_end: ?u16 = null;
            for (0..range_count) |index| {
                const record = start + 4 + index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                const start_coverage_index = try bin.readU16At(data, record + 4);
                if (first > last or start_coverage_index != total) return error.BadSfnt;
                if (previous_end) |prev| if (first <= prev) return error.BadSfnt;
                previous_end = last;
                total += @as(usize, last - first) + 1;
                if (total > std.math.maxInt(u16)) return error.BadSfnt;
            }
            break :count total;
        },
        else => error.BadSfnt,
    };
}

fn coverageGlyphs(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize) Error![]u16 {
    const count = try coverageGlyphCount(data, table_offset, table_length, coverage_offset);
    const glyphs = try allocator.alloc(u16, count);
    errdefer allocator.free(glyphs);
    const start = table_offset + coverage_offset;
    switch (try bin.readU16At(data, start)) {
        1 => {
            for (glyphs, 0..) |*glyph, index| glyph.* = try bin.readU16At(data, start + 4 + index * 2);
        },
        2 => {
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            var out_index: usize = 0;
            for (0..range_count) |range_index| {
                const record = start + 4 + range_index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                var glyph = first;
                while (glyph <= last) : (glyph += 1) {
                    glyphs[out_index] = glyph;
                    out_index += 1;
                }
            }
        },
        else => return error.BadSfnt,
    }
    return glyphs;
}

fn readConstants(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, constants_offset: usize) Error!Constants {
    const start = table_offset + constants_offset;
    const value_records = try allocator.alloc(ValueRecord, 51);
    errdefer allocator.free(value_records);
    for (value_records, 0..) |*record, index| {
        const record_offset = start + 8 + index * 4;
        record.* = .{
            .value = try bin.readI16At(data, record_offset),
            .device_offset = try bin.readU16At(data, record_offset + 2),
        };
    }
    return .{
        .script_percent_scale_down = try bin.readI16At(data, start),
        .script_script_percent_scale_down = try bin.readI16At(data, start + 2),
        .delimited_sub_formula_min_height = try bin.readU16At(data, start + 4),
        .display_operator_min_height = try bin.readU16At(data, start + 6),
        .value_records = value_records,
        .radical_degree_bottom_raise_percent = try bin.readI16At(data, start + 212),
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

test "MATH constants expose scalar and value-record metadata" {
    var bytes: [324]u8 = .{0} ** 324;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 224);
    writeU16(&bytes, 8, 270);
    writeI16(&bytes, 10, 80);
    writeI16(&bytes, 12, 60);
    writeU16(&bytes, 14, 1000);
    writeU16(&bytes, 16, 1200);
    writeI16(&bytes, 18, 11);
    writeI16(&bytes, 222, 55);
    writeU16(&bytes, 224, 8);
    writeU16(&bytes, 226, 24);
    writeU16(&bytes, 228, 40);
    writeU16(&bytes, 232, 8);
    writeU16(&bytes, 234, 1);
    writeI16(&bytes, 236, -12);
    writeU16(&bytes, 240, 1);
    writeU16(&bytes, 242, 1);
    writeU16(&bytes, 244, 3);
    writeU16(&bytes, 248, 8);
    writeU16(&bytes, 250, 1);
    writeI16(&bytes, 252, 42);
    writeU16(&bytes, 256, 1);
    writeU16(&bytes, 258, 1);
    writeU16(&bytes, 260, 3);
    writeU16(&bytes, 264, 1);
    writeU16(&bytes, 266, 1);
    writeU16(&bytes, 268, 3);
    writeU16(&bytes, 270, 5);
    writeU16(&bytes, 272, 14);
    writeU16(&bytes, 274, 20);
    writeU16(&bytes, 276, 1);
    writeU16(&bytes, 278, 1);
    writeU16(&bytes, 284, 1);
    writeU16(&bytes, 286, 1);
    writeU16(&bytes, 288, 5);
    writeU16(&bytes, 280, 26);
    writeU16(&bytes, 282, 0);
    writeU16(&bytes, 284, 1);
    writeU16(&bytes, 286, 1);
    writeU16(&bytes, 288, 5);
    writeU16(&bytes, 290, 1);
    writeU16(&bytes, 292, 1);
    writeU16(&bytes, 294, 6);
    writeU16(&bytes, 296, 8);
    writeU16(&bytes, 298, 1);
    writeU16(&bytes, 300, 7);
    writeU16(&bytes, 302, 900);
    writeI16(&bytes, 304, -7);
    writeU16(&bytes, 308, 1);
    writeU16(&bytes, 310, 8);
    writeU16(&bytes, 312, 1);
    writeU16(&bytes, 314, 2);
    writeU16(&bytes, 316, 3);
    writeU16(&bytes, 318, 1);

    try validate(&bytes, 0, bytes.len);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u32, 0x00010000), parsed.version);
    try std.testing.expectEqual(@as(i16, 80), parsed.constants.script_percent_scale_down);
    try std.testing.expectEqual(@as(u16, 1200), parsed.constants.display_operator_min_height);
    try std.testing.expectEqual(@as(i16, 11), parsed.constants.value_records[0].value);
    try std.testing.expectEqual(@as(i16, 55), parsed.constants.radical_degree_bottom_raise_percent);
    try std.testing.expectEqual(@as(?usize, 8), parsed.glyph_info.italics_correction_info_offset);
    try std.testing.expectEqual(@as(?usize, 24), parsed.glyph_info.top_accent_attachment_offset);
    try std.testing.expectEqual(@as(?usize, 40), parsed.glyph_info.extended_shape_coverage_offset);
    try std.testing.expectEqual(@as(usize, 1), parsed.glyph_info.italics_corrections.len);
    try std.testing.expectEqual(GlyphValueRecord{ .glyph_id = 3, .value_record = .{ .value = -12, .device_offset = 0 } }, parsed.glyph_info.italics_corrections[0]);
    try std.testing.expectEqual(GlyphValueRecord{ .glyph_id = 3, .value_record = .{ .value = 42, .device_offset = 0 } }, parsed.glyph_info.top_accent_attachments[0]);
    try std.testing.expectEqualSlices(u16, &.{3}, parsed.glyph_info.extended_shape_glyphs);
    try std.testing.expectEqual(@as(u16, 5), parsed.variants.min_connector_overlap);
    try std.testing.expectEqualSlices(u16, &.{5}, parsed.variants.vertical_glyphs);
    try std.testing.expectEqualSlices(u16, &.{6}, parsed.variants.horizontal_glyphs);
    try std.testing.expectEqual(@as(usize, 2), parsed.variants.construction_offsets.len);
}

test "MATH rejects malformed constants offsets" {
    var bytes: [20]u8 = .{0} ** 20;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 0);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len));
}
