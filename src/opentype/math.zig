const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Constant = enum(u8) {
    script_percent_scale_down = 0,
    script_script_percent_scale_down = 1,
    delimited_sub_formula_min_height = 2,
    display_operator_min_height = 3,
    math_leading = 4,
    axis_height = 5,
    accent_base_height = 6,
    flattened_accent_base_height = 7,
    subscript_shift_down = 8,
    subscript_top_max = 9,
    subscript_baseline_drop_min = 10,
    superscript_shift_up = 11,
    superscript_shift_up_cramped = 12,
    superscript_bottom_min = 13,
    superscript_baseline_drop_max = 14,
    sub_superscript_gap_min = 15,
    superscript_bottom_max_with_subscript = 16,
    space_after_script = 17,
    upper_limit_gap_min = 18,
    upper_limit_baseline_rise_min = 19,
    lower_limit_gap_min = 20,
    lower_limit_baseline_drop_min = 21,
    stack_top_shift_up = 22,
    stack_top_display_style_shift_up = 23,
    stack_bottom_shift_down = 24,
    stack_bottom_display_style_shift_down = 25,
    stack_gap_min = 26,
    stack_display_style_gap_min = 27,
    stretch_stack_top_shift_up = 28,
    stretch_stack_bottom_shift_down = 29,
    stretch_stack_gap_above_min = 30,
    stretch_stack_gap_below_min = 31,
    fraction_numerator_shift_up = 32,
    fraction_numerator_display_style_shift_up = 33,
    fraction_denominator_shift_down = 34,
    fraction_denominator_display_style_shift_down = 35,
    fraction_numerator_gap_min = 36,
    fraction_num_display_style_gap_min = 37,
    fraction_rule_thickness = 38,
    fraction_denominator_gap_min = 39,
    fraction_denom_display_style_gap_min = 40,
    skewed_fraction_horizontal_gap = 41,
    skewed_fraction_vertical_gap = 42,
    overbar_vertical_gap = 43,
    overbar_rule_thickness = 44,
    overbar_extra_ascender = 45,
    underbar_vertical_gap = 46,
    underbar_rule_thickness = 47,
    underbar_extra_descender = 48,
    radical_vertical_gap = 49,
    radical_display_style_vertical_gap = 50,
    radical_rule_thickness = 51,
    radical_extra_ascender = 52,
    radical_kern_before_degree = 53,
    radical_kern_after_degree = 54,
    radical_degree_bottom_raise_percent = 55,
};

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

pub const KernCorner = enum(u2) {
    top_right = 0,
    top_left = 1,
    bottom_right = 2,
    bottom_left = 3,
};

pub const MathKern = struct {
    offset: usize,
    correction_heights: []ValueRecord,
    kern_values: []ValueRecord,
};

pub const MathKernRecord = struct {
    glyph_id: u16,
    kerns: [4]?MathKern,
};

pub const MathKernInfo = struct {
    coverage_offset: usize,
    records: []MathKernRecord,
};

pub const GlyphInfo = struct {
    italics_correction_info_offset: ?usize,
    top_accent_attachment_offset: ?usize,
    extended_shape_coverage_offset: ?usize,
    math_kern_info_offset: ?usize,
    italics_corrections: []GlyphValueRecord,
    top_accent_attachments: []GlyphValueRecord,
    extended_shape_glyphs: []u16,
    math_kern_info: ?MathKernInfo,
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

pub const GlyphValueKind = enum { italics_correction, top_accent_attachment };

pub fn glyphValueRecord(data: []const u8, offset: usize, length: usize, glyph_id: u16, kind: GlyphValueKind) Error!?ValueRecord {
    const h = try header(data, offset, length);
    try validateGlyphInfo(data, offset, length, h.glyph_info_offset);
    const glyph_info = offset + h.glyph_info_offset;
    const child_offset = switch (kind) {
        .italics_correction => try bin.readU16At(data, glyph_info),
        .top_accent_attachment => try bin.readU16At(data, glyph_info + 2),
    };
    if (child_offset == 0) return null;
    return try valueRecordForGlyph(data, offset, length, h.glyph_info_offset + @as(usize, child_offset), glyph_id);
}

pub fn isExtendedShape(data: []const u8, offset: usize, length: usize, glyph_id: u16) Error!bool {
    const h = try header(data, offset, length);
    try validateGlyphInfo(data, offset, length, h.glyph_info_offset);
    const glyph_info = offset + h.glyph_info_offset;
    const child_offset = try bin.readU16At(data, glyph_info + 4);
    if (child_offset == 0) return false;
    return (try coverageIndex(data, offset, length, h.glyph_info_offset + @as(usize, child_offset), glyph_id)) != null;
}

pub fn constantValue(data: []const u8, offset: usize, length: usize, constant: Constant) Error!i32 {
    const h = try header(data, offset, length);
    try validateConstants(data, offset, length, h.constants_offset);
    const constants = offset + h.constants_offset;
    return switch (constant) {
        .script_percent_scale_down => try bin.readI16At(data, constants),
        .script_script_percent_scale_down => try bin.readI16At(data, constants + 2),
        .delimited_sub_formula_min_height => try bin.readU16At(data, constants + 4),
        .display_operator_min_height => try bin.readU16At(data, constants + 6),
        .radical_degree_bottom_raise_percent => try bin.readI16At(data, constants + 212),
        else => |tag| blk: {
            const index = @intFromEnum(tag);
            if (index < 4 or index > 54) return error.BadSfnt;
            break :blk try bin.readI16At(data, constants + 8 + (@as(usize, index) - 4) * 4);
        },
    };
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

pub fn kernValue(value: *const Info, glyph_id: u16, corner: KernCorner, correction_height: i16) ?i16 {
    const kern_info = value.glyph_info.math_kern_info orelse return null;
    for (kern_info.records) |record| {
        if (record.glyph_id != glyph_id) continue;
        const kern = record.kerns[@intFromEnum(corner)] orelse return null;
        var index: usize = 0;
        while (index < kern.correction_heights.len) : (index += 1) {
            if (correction_height < kern.correction_heights[index].value) break;
        }
        return kern.kern_values[index].value;
    }
    return null;
}

pub fn constructionForGlyph(value: *const Info, glyph_id: u16, vertical: bool) ?*const Construction {
    for (value.variants.constructions) |*construction| {
        if (construction.glyph_id == glyph_id and construction.vertical == vertical) return construction;
    }
    return null;
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
    if (value.math_kern_info) |info_value| freeMathKernInfo(allocator, info_value);
}

fn freeMathKernInfo(allocator: std.mem.Allocator, info_value: MathKernInfo) void {
    for (info_value.records) |record| {
        for (record.kerns) |maybe_kern| {
            if (maybe_kern) |kern| {
                allocator.free(kern.correction_heights);
                allocator.free(kern.kern_values);
            }
        }
    }
    allocator.free(info_value.records);
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
    if (kern_offset != 0) try validateMathKernInfo(data, table_offset, table_length, glyph_info_offset + @as(usize, kern_offset));
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
    const math_kern_info = if (kern_offset != 0)
        try readMathKernInfo(allocator, data, table_offset, table_length, glyph_info_offset + @as(usize, kern_offset))
    else
        null;
    errdefer if (math_kern_info) |info_value| freeMathKernInfo(allocator, info_value);
    return .{
        .italics_correction_info_offset = nullableOffset(italic_offset),
        .top_accent_attachment_offset = nullableOffset(accent_offset),
        .extended_shape_coverage_offset = nullableOffset(extended_offset),
        .math_kern_info_offset = nullableOffset(kern_offset),
        .italics_corrections = italics,
        .top_accent_attachments = top_accents,
        .extended_shape_glyphs = extended_shape_glyphs,
        .math_kern_info = math_kern_info,
    };
}

fn nullableOffset(value: u16) ?usize {
    return if (value == 0) null else @intCast(value);
}

fn validateMathKernInfo(data: []const u8, table_offset: usize, table_length: usize, kern_info_offset: usize) Error!void {
    try validateChildOffset(kern_info_offset, table_length, 4);
    const start = table_offset + kern_info_offset;
    const coverage_offset: usize = @intCast(try bin.readU16At(data, start));
    if (coverage_offset == 0) return error.BadSfnt;
    const coverage_count = try coverageGlyphCount(data, table_offset, table_length, kern_info_offset + coverage_offset);
    const record_count: usize = @intCast(try bin.readU16At(data, start + 2));
    if (record_count != coverage_count) return error.BadSfnt;
    if (record_count > (table_length - kern_info_offset - 4) / 8) return error.BadSfnt;
    for (0..record_count) |record_index| {
        const record = start + 4 + record_index * 8;
        for (0..4) |corner| {
            const kern_offset = try bin.readU16At(data, record + corner * 2);
            if (kern_offset != 0) try validateMathKern(data, table_offset, table_length, kern_info_offset + @as(usize, kern_offset));
        }
    }
}

fn validateMathKern(data: []const u8, table_offset: usize, table_length: usize, kern_offset: usize) Error!void {
    try validateChildOffset(kern_offset, table_length, 2);
    const start = table_offset + kern_offset;
    const height_count: usize = @intCast(try bin.readU16At(data, start));
    const record_count = height_count * 2 + 1;
    if (record_count > (table_length - kern_offset - 2) / 4) return error.BadSfnt;
    var previous_height: ?i16 = null;
    for (0..record_count) |index| {
        const value_record = start + 2 + index * 4;
        const value = try bin.readI16At(data, value_record);
        const device_offset = try bin.readU16At(data, value_record + 2);
        if (index < height_count) {
            if (previous_height) |last| if (value <= last) return error.BadSfnt;
            previous_height = value;
        }
        if (device_offset != 0) try validateDeviceTable(data, table_offset, table_length, kern_offset, device_offset);
    }
}

fn readMathKernInfo(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, kern_info_offset: usize) Error!MathKernInfo {
    try validateMathKernInfo(data, table_offset, table_length, kern_info_offset);
    const start = table_offset + kern_info_offset;
    const coverage_offset: usize = @intCast(try bin.readU16At(data, start));
    const glyphs = try coverageGlyphs(allocator, data, table_offset, table_length, kern_info_offset + coverage_offset);
    defer allocator.free(glyphs);
    const records = try allocator.alloc(MathKernRecord, glyphs.len);
    var initialized: usize = 0;
    errdefer {
        for (records[0..initialized]) |record| {
            for (record.kerns) |maybe_kern| if (maybe_kern) |kern| {
                allocator.free(kern.correction_heights);
                allocator.free(kern.kern_values);
            };
        }
        allocator.free(records);
    }
    for (records, 0..) |*record, record_index| {
        const record_offset = start + 4 + record_index * 8;
        var kerns: [4]?MathKern = .{ null, null, null, null };
        var corner: usize = 0;
        errdefer {
            for (kerns[0..corner]) |maybe_kern| if (maybe_kern) |kern| {
                allocator.free(kern.correction_heights);
                allocator.free(kern.kern_values);
            };
        }
        while (corner < 4) : (corner += 1) {
            const raw_offset = try bin.readU16At(data, record_offset + corner * 2);
            kerns[corner] = if (raw_offset == 0) null else try readMathKern(allocator, data, table_offset, kern_info_offset + @as(usize, raw_offset));
        }
        record.* = .{ .glyph_id = glyphs[record_index], .kerns = kerns };
        initialized += 1;
    }
    return .{ .coverage_offset = coverage_offset, .records = records };
}

fn readMathKern(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, kern_offset: usize) Error!MathKern {
    const start = table_offset + kern_offset;
    const height_count: usize = @intCast(try bin.readU16At(data, start));
    const correction_heights = try allocator.alloc(ValueRecord, height_count);
    errdefer allocator.free(correction_heights);
    const kern_values = try allocator.alloc(ValueRecord, height_count + 1);
    errdefer allocator.free(kern_values);
    for (correction_heights, 0..) |*record, index| {
        const value_record = start + 2 + index * 4;
        record.* = .{ .value = try bin.readI16At(data, value_record), .device_offset = try bin.readU16At(data, value_record + 2) };
    }
    for (kern_values, 0..) |*record, index| {
        const value_record = start + 2 + (height_count + index) * 4;
        record.* = .{ .value = try bin.readI16At(data, value_record), .device_offset = try bin.readU16At(data, value_record + 2) };
    }
    return .{ .offset = kern_offset, .correction_heights = correction_heights, .kern_values = kern_values };
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

fn valueRecordForGlyph(data: []const u8, table_offset: usize, table_length: usize, subtable_offset: usize, glyph_id: u16) Error!?ValueRecord {
    try validateMathValueArraySubtable(data, table_offset, table_length, subtable_offset);
    const start = table_offset + subtable_offset;
    const coverage_offset: usize = @intCast(try bin.readU16At(data, start));
    const index = (try coverageIndex(data, table_offset, table_length, subtable_offset + coverage_offset, glyph_id)) orelse return null;
    const value_count: usize = @intCast(try bin.readU16At(data, start + 2));
    if (index >= value_count) return error.BadSfnt;
    const value_record = start + 4 + index * 4;
    return .{ .value = try bin.readI16At(data, value_record), .device_offset = try bin.readU16At(data, value_record + 2) };
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

fn coverageIndex(data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize, glyph_id: u16) Error!?usize {
    _ = try coverageGlyphCount(data, table_offset, table_length, coverage_offset);
    const start = table_offset + coverage_offset;
    return switch (try bin.readU16At(data, start)) {
        1 => blk: {
            const count: usize = @intCast(try bin.readU16At(data, start + 2));
            for (0..count) |index| {
                const glyph = try bin.readU16At(data, start + 4 + index * 2);
                if (glyph == glyph_id) break :blk index;
                if (glyph > glyph_id) break :blk null;
            }
            break :blk null;
        },
        2 => blk: {
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            for (0..range_count) |range_index| {
                const record = start + 4 + range_index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                const start_index: usize = @intCast(try bin.readU16At(data, record + 4));
                if (glyph_id < first) break :blk null;
                if (glyph_id <= last) break :blk start_index + @as(usize, glyph_id - first);
            }
            break :blk null;
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
    var bytes: [356]u8 = .{0} ** 356;
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
    writeU16(&bytes, 230, 100);
    writeU16(&bytes, 232, 8);
    writeU16(&bytes, 234, 1);
    writeI16(&bytes, 236, -12);
    writeU16(&bytes, 240, 1);
    writeU16(&bytes, 242, 1);
    writeU16(&bytes, 244, 1);
    writeU16(&bytes, 248, 8);
    writeU16(&bytes, 250, 1);
    writeI16(&bytes, 252, 42);
    writeU16(&bytes, 256, 1);
    writeU16(&bytes, 258, 1);
    writeU16(&bytes, 260, 1);
    writeU16(&bytes, 264, 1);
    writeU16(&bytes, 266, 1);
    writeU16(&bytes, 268, 1);
    writeU16(&bytes, 270, 5);
    writeU16(&bytes, 272, 14);
    writeU16(&bytes, 274, 20);
    writeU16(&bytes, 276, 1);
    writeU16(&bytes, 278, 1);
    writeU16(&bytes, 284, 1);
    writeU16(&bytes, 286, 1);
    writeU16(&bytes, 288, 1);
    writeU16(&bytes, 280, 26);
    writeU16(&bytes, 282, 0);
    writeU16(&bytes, 284, 1);
    writeU16(&bytes, 286, 1);
    writeU16(&bytes, 288, 1);
    writeU16(&bytes, 290, 1);
    writeU16(&bytes, 292, 1);
    writeU16(&bytes, 294, 0);
    writeU16(&bytes, 296, 8);
    writeU16(&bytes, 298, 1);
    writeU16(&bytes, 300, 1);
    writeU16(&bytes, 302, 900);
    writeI16(&bytes, 304, -7);
    writeU16(&bytes, 308, 1);
    writeU16(&bytes, 310, 1);
    writeU16(&bytes, 312, 1);
    writeU16(&bytes, 314, 2);
    writeU16(&bytes, 316, 3);
    writeU16(&bytes, 318, 1);
    writeU16(&bytes, 324, 12);
    writeU16(&bytes, 326, 1);
    writeU16(&bytes, 328, 18);
    writeU16(&bytes, 336, 1);
    writeU16(&bytes, 338, 1);
    writeU16(&bytes, 340, 1);
    writeU16(&bytes, 342, 1);
    writeI16(&bytes, 344, 10);
    writeI16(&bytes, 348, -20);
    writeI16(&bytes, 352, -30);

    try validate(&bytes, 0, bytes.len);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u32, 0x00010000), parsed.version);
    try std.testing.expectEqual(@as(i16, 80), parsed.constants.script_percent_scale_down);
    try std.testing.expectEqual(@as(u16, 1200), parsed.constants.display_operator_min_height);
    try std.testing.expectEqual(@as(i16, 11), parsed.constants.value_records[0].value);
    try std.testing.expectEqual(@as(i16, 55), parsed.constants.radical_degree_bottom_raise_percent);
    try std.testing.expectEqual(@as(i32, 80), try constantValue(&bytes, 0, bytes.len, .script_percent_scale_down));
    try std.testing.expectEqual(@as(i32, 1200), try constantValue(&bytes, 0, bytes.len, .display_operator_min_height));
    try std.testing.expectEqual(@as(i32, 11), try constantValue(&bytes, 0, bytes.len, .math_leading));
    try std.testing.expectEqual(@as(i32, 55), try constantValue(&bytes, 0, bytes.len, .radical_degree_bottom_raise_percent));
    try std.testing.expectEqual(@as(?usize, 8), parsed.glyph_info.italics_correction_info_offset);
    try std.testing.expectEqual(@as(?usize, 24), parsed.glyph_info.top_accent_attachment_offset);
    try std.testing.expectEqual(@as(?usize, 40), parsed.glyph_info.extended_shape_coverage_offset);
    try std.testing.expectEqual(@as(usize, 1), parsed.glyph_info.italics_corrections.len);
    try std.testing.expectEqual(GlyphValueRecord{ .glyph_id = 1, .value_record = .{ .value = -12, .device_offset = 0 } }, parsed.glyph_info.italics_corrections[0]);
    try std.testing.expectEqual(GlyphValueRecord{ .glyph_id = 1, .value_record = .{ .value = 42, .device_offset = 0 } }, parsed.glyph_info.top_accent_attachments[0]);
    try std.testing.expectEqual(ValueRecord{ .value = -12, .device_offset = 0 }, (try glyphValueRecord(&bytes, 0, bytes.len, 1, .italics_correction)).?);
    try std.testing.expectEqual(ValueRecord{ .value = 42, .device_offset = 0 }, (try glyphValueRecord(&bytes, 0, bytes.len, 1, .top_accent_attachment)).?);
    try std.testing.expect((try glyphValueRecord(&bytes, 0, bytes.len, 0, .italics_correction)) == null);
    try std.testing.expectEqualSlices(u16, &.{1}, parsed.glyph_info.extended_shape_glyphs);
    try std.testing.expect(try isExtendedShape(&bytes, 0, bytes.len, 1));
    try std.testing.expect(!try isExtendedShape(&bytes, 0, bytes.len, 0));
    try std.testing.expectEqual(@as(u16, 5), parsed.variants.min_connector_overlap);
    try std.testing.expectEqualSlices(u16, &.{1}, parsed.variants.vertical_glyphs);
    try std.testing.expectEqualSlices(u16, &.{0}, parsed.variants.horizontal_glyphs);
    try std.testing.expectEqual(@as(usize, 2), parsed.variants.construction_offsets.len);
    try std.testing.expectEqual(@as(?i16, -20), kernValue(&parsed, 1, .top_right, 0));
    try std.testing.expectEqual(@as(?i16, -30), kernValue(&parsed, 1, .top_right, 10));
    try std.testing.expectEqual(@as(?i16, null), kernValue(&parsed, 0, .top_right, 0));
}

test "MATH rejects malformed constants offsets" {
    var bytes: [20]u8 = .{0} ** 20;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 0);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len));
}
