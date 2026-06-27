const std = @import("std");
const bin = @import("binary.zig");
const GlyphId = @import("glyph.zig").GlyphId;
const unicode = @import("unicode.zig");

/// GPOS produces additive adjustments instead of mutating glyph ids. The caller
/// applies these deltas while constructing final glyph positions.
pub const GposError = error{
    BadGpos,
    UnsupportedGpos,
    EndOfStream,
};

pub const Adjustment = struct {
    index: usize,
    x_advance: i16 = 0,
    x_placement: i16 = 0,
    y_placement: i16 = 0,
    y_advance: i16 = 0,
    pair_positioned: bool = false,
    mark_attachment: bool = false,
    mark_base_index: ?usize = null,
};

const Table = struct {
    data: []const u8,
    offset: usize,
    length: usize,
};

pub const LookupOptions = struct {
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    features: []const unicode.FeatureOverride = &.{},
    glyph_classes: ?[]const u16 = null,
};

/// Collect positioning adjustments for a post-GSUB glyph stream.
pub fn collectAdjustments(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    return try collectAdjustmentsWithOptions(data, offset, length, glyphs, adjustments, allocator, .{});
}

pub fn collectAdjustmentsWithOptions(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGpos;
    const table = Table{ .data = data, .offset = offset, .length = length };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGpos;
    // GPOS uses the same ScriptList/FeatureList/LookupList topology as GSUB,
    // but feature defaults differ: positioning lookups are generally active
    // unless an explicit feature override disables them.
    var selected_lookups = try selectedLookupIndices(table, allocator, options);
    defer selected_lookups.deinit(allocator);
    if (options.features.len != 0 and selected_lookups.items.len == 0) return;

    const lookup_list_offset = try readU16(table, 8);
    const lookup_count = try readU16(table, lookup_list_offset);
    for (0..lookup_count) |i| {
        if (selected_lookups.items.len != 0 and !containsLookup(selected_lookups.items, @intCast(i))) continue;
        const lookup_offset = try readU16(table, lookup_list_offset + 2 + i * 2);
        try collectLookup(table, lookup_list_offset + lookup_offset, glyphs, adjustments, allocator, options);
    }
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var feature_indices = std.ArrayList(u16).empty;
    defer feature_indices.deinit(allocator);
    var lookups = std.ArrayList(u16).empty;
    errdefer lookups.deinit(allocator);

    const script_list_offset = try readU16(table, 4);
    const feature_list_offset = try readU16(table, 6);
    if (script_list_offset == 0 or feature_list_offset == 0) return lookups;

    const script_count = try readU16(table, script_list_offset);
    const script_offset = try findScriptOffset(table, script_list_offset, script_count, @intFromEnum(options.script_tag)) orelse
        try findScriptOffset(table, script_list_offset, script_count, @intFromEnum(unicode.OpenTypeScriptTag.dflt)) orelse
        0;
    if (script_offset != 0) {
        try collectScriptFeatures(table, script_offset, options.language_tag, &feature_indices, allocator);
    }

    const feature_count = try readU16(table, feature_list_offset);
    for (feature_indices.items) |feature_index| {
        if (feature_index >= feature_count) continue;
        const feature_record = feature_list_offset + 2 + @as(usize, feature_index) * 6;
        const feature_tag = try readU32(table, feature_record);
        if (!featureEnabled(feature_tag, options.features)) continue;
        const feature_offset = feature_list_offset + try readU16(table, feature_record + 4);
        const lookup_index_count = try readU16(table, feature_offset + 2);
        for (0..lookup_index_count) |i| {
            const lookup_index = try readU16(table, feature_offset + 4 + i * 2);
            if (!containsLookup(lookups.items, lookup_index)) try lookups.append(allocator, lookup_index);
        }
    }

    return lookups;
}

fn featureEnabled(feature_tag: u32, overrides: []const unicode.FeatureOverride) bool {
    for (overrides) |override| {
        if (override.tag == feature_tag) return override.enabled;
    }
    return true;
}

fn findScriptOffset(table: Table, script_list_offset: usize, script_count: u16, script_tag: u32) GposError!?usize {
    for (0..script_count) |script_i| {
        const script_record = script_list_offset + 2 + script_i * 6;
        if (try readU32(table, script_record) != script_tag) continue;
        return script_list_offset + try readU16(table, script_record + 4);
    }
    return null;
}

fn collectScriptFeatures(table: Table, script_offset: usize, language_tag: unicode.OpenTypeLanguageTag, feature_indices: *std.ArrayList(u16), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const default_lang_sys_offset = try readU16(table, script_offset);
    if (language_tag != .dflt) {
        if (try findLangSysOffset(table, script_offset, @intFromEnum(language_tag))) |lang_sys_offset| {
            try collectLangSysFeatures(table, lang_sys_offset, feature_indices, allocator);
            return;
        }
    }
    if (default_lang_sys_offset != 0) {
        try collectLangSysFeatures(table, script_offset + default_lang_sys_offset, feature_indices, allocator);
    }
}

fn findLangSysOffset(table: Table, script_offset: usize, language_tag: u32) (GposError || std.mem.Allocator.Error)!?usize {
    const lang_sys_count = try readU16(table, script_offset + 2);
    for (0..lang_sys_count) |lang_i| {
        const lang_record = script_offset + 4 + lang_i * 6;
        if (try readU32(table, lang_record) != language_tag) continue;
        return script_offset + try readU16(table, lang_record + 4);
    }
    return null;
}

fn collectLangSysFeatures(table: Table, lang_sys_offset: usize, feature_indices: *std.ArrayList(u16), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const required_feature_index = try readU16(table, lang_sys_offset + 2);
    if (required_feature_index != 0xffff and !containsLookup(feature_indices.items, required_feature_index)) {
        try feature_indices.append(allocator, required_feature_index);
    }
    const feature_count = try readU16(table, lang_sys_offset + 4);
    for (0..feature_count) |i| {
        const feature_index = try readU16(table, lang_sys_offset + 6 + i * 2);
        if (!containsLookup(feature_indices.items, feature_index)) try feature_indices.append(allocator, feature_index);
    }
}

fn containsLookup(items: []const u16, needle: u16) bool {
    for (items) |item| {
        if (item == needle) return true;
    }
    return false;
}

fn collectLookup(table: Table, lookup_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const lookup_type = try readU16(table, lookup_offset);
    const lookup_flag = try readU16(table, lookup_offset + 2);
    const subtable_count = try readU16(table, lookup_offset + 4);
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => try collectSingleAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
            2 => try collectPairAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
            3 => try collectCursiveAdjustment(table, subtable_offset, glyphs, adjustments, allocator),
            4 => try collectMarkToBaseAdjustment(table, subtable_offset, glyphs, adjustments, allocator),
            5 => try collectMarkToLigatureAdjustment(table, subtable_offset, glyphs, adjustments, allocator),
            6 => try collectMarkToMarkAdjustment(table, subtable_offset, glyphs, adjustments, allocator),
            7 => try collectContextAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
            8 => try collectChainingContextAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
            9 => try collectExtensionAdjustment(table, subtable_offset, glyphs, adjustments, allocator, options),
            else => {},
        }
    }
}

fn collectSingleAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const value_format = try readU16(table, subtable_offset + 4);
    switch (pos_format) {
        1 => {
            const value = try readValueRecord(table, subtable_offset + 6, value_format);
            for (glyphs, 0..) |glyph, i| {
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph) != null) {
                    try appendAdjustment(adjustments, allocator, i, value, false);
                }
            }
        },
        2 => {
            const value_count = try readU16(table, subtable_offset + 6);
            const value_size = valueRecordSize(value_format);
            for (glyphs, 0..) |glyph, i| {
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph)) |coverage| {
                    if (coverage < value_count) {
                        const value = try readValueRecord(table, subtable_offset + 8 + coverage * value_size, value_format);
                        try appendAdjustment(adjustments, allocator, i, value, false);
                    }
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn lookupIgnoresGlyph(lookup_flag: u16, options: LookupOptions, glyph: GlyphId) bool {
    // Lookup flags share GDEF glyph class semantics with GSUB. If a font has no
    // GDEF class data, the lookup applies to all glyphs.
    const classes = options.glyph_classes orelse return false;
    if (glyph >= classes.len) return false;
    const class = classes[glyph];
    if ((lookup_flag & 0x0002) != 0 and class == 1) return true;
    if ((lookup_flag & 0x0004) != 0 and class == 2) return true;
    if ((lookup_flag & 0x0008) != 0 and class == 3) return true;
    return false;
}

fn collectExtensionAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    const extension_offset = try readU32(table, subtable_offset + 4);
    const extension_subtable = subtable_offset + extension_offset;
    switch (extension_lookup_type) {
        1 => try collectSingleAdjustment(table, extension_subtable, glyphs, adjustments, allocator, 0, options),
        2 => try collectPairAdjustment(table, extension_subtable, glyphs, adjustments, allocator, 0, options),
        3 => try collectCursiveAdjustment(table, extension_subtable, glyphs, adjustments, allocator),
        4 => try collectMarkToBaseAdjustment(table, extension_subtable, glyphs, adjustments, allocator),
        5 => try collectMarkToLigatureAdjustment(table, extension_subtable, glyphs, adjustments, allocator),
        6 => try collectMarkToMarkAdjustment(table, extension_subtable, glyphs, adjustments, allocator),
        7 => try collectContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, 0, options),
        8 => try collectChainingContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, 0, options),
        else => {},
    }
}

fn collectPairAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const value_format_1 = try readU16(table, subtable_offset + 4);
    const value_format_2 = try readU16(table, subtable_offset + 6);
    const value_size_1 = valueRecordSize(value_format_1);
    const value_size_2 = valueRecordSize(value_format_2);

    if (glyphs.len < 2) return;
    switch (pos_format) {
        1 => {
            // PairPos format 1 is a sparse list keyed by the first glyph's
            // coverage index, then searched by the second glyph.
            const pair_set_count = try readU16(table, subtable_offset + 8);
            var i: usize = 0;
            while (i + 1 < glyphs.len) : (i += 1) {
                if (lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) continue;
                const second_index = nextUnignoredGlyph(glyphs, i + 1, lookup_flag, options) orelse continue;
                const coverage = try coverageIndex(table, coverage_offset, glyphs[i]) orelse continue;
                if (coverage >= pair_set_count) continue;
                const pair_set_offset = subtable_offset + try readU16(table, subtable_offset + 10 + coverage * 2);
                const pair_value_count = try readU16(table, pair_set_offset);
                var record_offset = pair_set_offset + 2;
                for (0..pair_value_count) |_| {
                    const second = try readU16(table, record_offset);
                    record_offset += 2;
                    const value_1 = try readValueRecord(table, record_offset, value_format_1);
                    record_offset += value_size_1;
                    const value_2 = try readValueRecord(table, record_offset, value_format_2);
                    record_offset += value_size_2;
                    if (second == glyphs[second_index]) {
                        try appendAdjustment(adjustments, allocator, i, value_1, true);
                        try appendAdjustment(adjustments, allocator, second_index, value_2, false);
                        break;
                    }
                }
            }
        },
        2 => {
            // PairPos format 2 maps both glyphs through class definitions and
            // indexes a dense class1 x class2 value matrix.
            const class_def_1 = subtable_offset + try readU16(table, subtable_offset + 8);
            const class_def_2 = subtable_offset + try readU16(table, subtable_offset + 10);
            const class_1_count = try readU16(table, subtable_offset + 12);
            const class_2_count = try readU16(table, subtable_offset + 14);
            const record_size = value_size_1 + value_size_2;
            const matrix_offset = subtable_offset + 16;
            var i: usize = 0;
            while (i + 1 < glyphs.len) : (i += 1) {
                if (lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) continue;
                const second_index = nextUnignoredGlyph(glyphs, i + 1, lookup_flag, options) orelse continue;
                if (try coverageIndex(table, coverage_offset, glyphs[i]) == null) continue;
                const class_1 = try classValue(table, class_def_1, glyphs[i]);
                const class_2 = try classValue(table, class_def_2, glyphs[second_index]);
                if (class_1 >= class_1_count or class_2 >= class_2_count) continue;
                const record_offset = matrix_offset + (@as(usize, class_1) * class_2_count + class_2) * record_size;
                const value_1 = try readValueRecord(table, record_offset, value_format_1);
                const value_2 = try readValueRecord(table, record_offset + value_size_1, value_format_2);
                try appendAdjustment(adjustments, allocator, i, value_1, true);
                try appendAdjustment(adjustments, allocator, second_index, value_2, false);
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn nextUnignoredGlyph(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions) ?usize {
    var i = start;
    while (i < glyphs.len) : (i += 1) {
        if (!lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) return i;
    }
    return null;
}

fn collectForwardUnignoredGlyphs(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions, out: []usize) bool {
    var out_i: usize = 0;
    var glyph_i = start;
    while (glyph_i < glyphs.len and out_i < out.len) : (glyph_i += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[glyph_i])) continue;
        out[out_i] = glyph_i;
        out_i += 1;
    }
    return out_i == out.len;
}

fn collectBacktrackUnignoredGlyphs(glyphs: []const GlyphId, pos: usize, lookup_flag: u16, options: LookupOptions, out: []usize) bool {
    var out_i: usize = 0;
    var glyph_i = pos;
    while (glyph_i > 0 and out_i < out.len) {
        glyph_i -= 1;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[glyph_i])) continue;
        out[out_i] = glyph_i;
        out_i += 1;
    }
    return out_i == out.len;
}

fn appendAdjustment(adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, index: usize, value: Adjustment, pair_positioned: bool) std.mem.Allocator.Error!void {
    return try appendAdjustmentEx(adjustments, allocator, index, value, .{ .pair_positioned = pair_positioned });
}

const AdjustmentFlags = struct {
    pair_positioned: bool = false,
    mark_attachment: bool = false,
    mark_base_index: ?usize = null,
};

fn appendAdjustmentEx(adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, index: usize, value: Adjustment, flags: AdjustmentFlags) std.mem.Allocator.Error!void {
    // Multiple positioning subtables can target the same glyph. Accumulate all
    // deltas into one adjustment record per glyph index.
    if (value.x_advance == 0 and value.x_placement == 0 and value.y_placement == 0 and value.y_advance == 0) return;
    for (adjustments.items) |*existing| {
        if (existing.index == index) {
            existing.x_advance += value.x_advance;
            existing.x_placement += value.x_placement;
            existing.y_placement += value.y_placement;
            existing.y_advance += value.y_advance;
            existing.pair_positioned = existing.pair_positioned or flags.pair_positioned;
            existing.mark_attachment = existing.mark_attachment or flags.mark_attachment;
            if (flags.mark_base_index) |base_index| existing.mark_base_index = base_index;
            return;
        }
    }
    try adjustments.append(allocator, .{
        .index = index,
        .x_advance = value.x_advance,
        .x_placement = value.x_placement,
        .y_placement = value.y_placement,
        .y_advance = value.y_advance,
        .pair_positioned = flags.pair_positioned,
        .mark_attachment = flags.mark_attachment,
        .mark_base_index = flags.mark_base_index,
    });
}

fn collectCursiveAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const entry_exit_count = try readU16(table, subtable_offset + 4);
    if (glyphs.len < 2) return;

    var i: usize = 1;
    while (i < glyphs.len) : (i += 1) {
        const current_index = try coverageIndex(table, coverage_offset, glyphs[i]) orelse continue;
        const previous_index = try coverageIndex(table, coverage_offset, glyphs[i - 1]) orelse continue;
        if (current_index >= entry_exit_count or previous_index >= entry_exit_count) continue;

        const current_record = subtable_offset + 6 + current_index * 4;
        const previous_record = subtable_offset + 6 + previous_index * 4;
        const entry_relative = try readU16(table, current_record);
        const exit_relative = try readU16(table, previous_record + 2);
        if (entry_relative == 0 or exit_relative == 0) continue;

        // Position the current glyph so its entry anchor lands on the previous
        // glyph's exit anchor.
        const entry = try readAnchor(table, subtable_offset + entry_relative);
        const exit = try readAnchor(table, subtable_offset + exit_relative);
        try appendAdjustment(adjustments, allocator, i, .{
            .index = i,
            .x_placement = exit.x - entry.x,
            .y_placement = exit.y - entry.y,
        }, false);
    }
}

fn collectMarkToBaseAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const base_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_array_offset = subtable_offset + try readU16(table, subtable_offset + 8);
    const base_array_offset = subtable_offset + try readU16(table, subtable_offset + 10);
    if (class_count == 0 or glyphs.len < 2) return;

    const attached_marks = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(attached_marks);
    @memset(attached_marks, false);

    for (glyphs, 0..) |glyph, i| {
        const mark_index = try coverageIndex(table, mark_coverage_offset, glyph) orelse continue;
        const base_position = try previousCoveredBaseGlyph(table, base_coverage_offset, glyphs, i, attached_marks) orelse continue;
        const base_index = try coverageIndex(table, base_coverage_offset, glyphs[base_position]) orelse continue;
        const mark_record_offset = mark_array_offset + 2 + mark_index * 4;
        const mark_class = try readU16(table, mark_record_offset);
        if (mark_class >= class_count) continue;
        const mark_anchor_offset = mark_array_offset + try readU16(table, mark_record_offset + 2);
        const base_anchor_record = base_array_offset + 2 + (base_index * class_count + mark_class) * 2;
        const base_anchor_relative = try readU16(table, base_anchor_record);
        if (base_anchor_relative == 0) continue;
        const base_anchor_offset = base_array_offset + base_anchor_relative;
        const mark_anchor = try readAnchor(table, mark_anchor_offset);
        const base_anchor = try readAnchor(table, base_anchor_offset);
        try appendAdjustmentEx(adjustments, allocator, i, .{
            .index = i,
            .x_placement = base_anchor.x - mark_anchor.x,
            .y_placement = base_anchor.y - mark_anchor.y,
        }, .{ .mark_attachment = true, .mark_base_index = base_position });
        attached_marks[i] = true;
    }
}

fn previousCoveredBaseGlyph(table: Table, base_coverage_offset: usize, glyphs: []const GlyphId, mark_index: usize, attached_marks: []const bool) GposError!?usize {
    var i = mark_index;
    while (i > 0) {
        i -= 1;
        if (i < attached_marks.len and attached_marks[i]) continue;
        if (try coverageIndex(table, base_coverage_offset, glyphs[i]) != null) return i;
    }
    return null;
}

fn collectContextAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    switch (pos_format) {
        1 => {
            const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
            const rule_set_count = try readU16(table, subtable_offset + 4);
            var pos: usize = 0;
            while (pos < glyphs.len) : (pos += 1) {
                if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
                const coverage = try coverageIndex(table, coverage_offset, glyphs[pos]) orelse continue;
                if (coverage >= rule_set_count) continue;
                const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
                if (set_relative == 0) continue;
                if (try collectPositionRuleSet(table, subtable_offset + set_relative, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
                    pos += 1;
                }
            }
        },
        2 => try collectClassPositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        3 => try collectCoveragePositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        else => return error.UnsupportedGpos,
    }
}

fn collectClassPositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const class_def_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_set_count = try readU16(table, subtable_offset + 6);
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        if (try coverageIndex(table, coverage_offset, glyphs[pos]) == null) continue;
        const class = try classValue(table, class_def_offset, glyphs[pos]);
        if (class >= class_set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 8 + @as(usize, class) * 2);
        if (set_relative == 0) continue;
        if (try collectClassPositionRuleSet(table, subtable_offset + set_relative, class_def_offset, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn collectCoveragePositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const glyph_count = try readU16(table, subtable_offset + 2);
    const pos_count = try readU16(table, subtable_offset + 4);
    if (glyph_count == 0) return;
    const coverage_offsets_pos = subtable_offset + 6;
    const records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (0..glyph_count) |i| {
            const coverage_offset = subtable_offset + try readU16(table, coverage_offsets_pos + i * 2);
            if (try coverageIndex(table, coverage_offset, glyphs[input_indices_buf[i]]) == null) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator);
        pos += glyph_count - 1;
    }
}

fn collectChainingContextAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    switch (pos_format) {
        1 => try collectChainingGlyphPositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        2 => try collectChainingClassPositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        3 => try collectChainingCoveragePositioning(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options),
        else => return error.UnsupportedGpos,
    }
}

fn collectChainingGlyphPositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const chain_set_count = try readU16(table, subtable_offset + 4);
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        const coverage = try coverageIndex(table, coverage_offset, glyphs[pos]) orelse continue;
        if (coverage >= chain_set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
        if (set_relative == 0) continue;
        if (try collectChainingGlyphRuleSet(table, subtable_offset + set_relative, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn collectChainingGlyphRuleSet(table: Table, set_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;
        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGpos;
        if (!collectBacktrackUnignoredGlyphs(glyphs, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count])) continue;
        var matched = true;
        for (0..backtrack_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs[backtrack_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += backtrack_count * 2;

        const input_count = try readU16(table, cursor);
        cursor += 2;
        if (input_count == 0) continue;
        var input_indices_buf: [64]usize = undefined;
        if (input_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..input_count])) continue;
        for (1..input_count) |i| {
            const expected = try readU16(table, cursor + (i - 1) * 2);
            if (glyphs[input_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += (@as(usize, input_count) - 1) * 2;

        const lookahead_count = try readU16(table, cursor);
        cursor += 2;
        const lookahead_start = input_indices_buf[input_count - 1] + 1;
        var lookahead_indices_buf: [64]usize = undefined;
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count])) continue;
        for (0..lookahead_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs[lookahead_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += lookahead_count * 2;

        const pos_count = try readU16(table, cursor);
        cursor += 2;
        try collectPositionRecordsMapped(table, cursor, pos_count, input_indices_buf[0..input_count], glyphs, adjustments, allocator);
        return true;
    }
    return false;
}

fn collectChainingClassPositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const backtrack_class_def = subtable_offset + try readU16(table, subtable_offset + 4);
    const input_class_def = subtable_offset + try readU16(table, subtable_offset + 6);
    const lookahead_class_def = subtable_offset + try readU16(table, subtable_offset + 8);
    const set_count = try readU16(table, subtable_offset + 10);
    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        if (try coverageIndex(table, coverage_offset, glyphs[pos]) == null) continue;
        const input_class = try classValue(table, input_class_def, glyphs[pos]);
        if (input_class >= set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 12 + @as(usize, input_class) * 2);
        if (set_relative == 0) continue;
        if (try collectChainingClassRuleSet(table, subtable_offset + set_relative, backtrack_class_def, input_class_def, lookahead_class_def, glyphs, pos, adjustments, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn collectChainingClassRuleSet(table: Table, set_offset: usize, backtrack_class_def: usize, input_class_def: usize, lookahead_class_def: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;

        // Chaining positioning checks the same three regions as GSUB chaining:
        // backtrack, input, and lookahead. Only the input region receives
        // position records.
        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGpos;
        if (!collectBacktrackUnignoredGlyphs(glyphs, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count])) continue;
        var matched = true;
        for (0..backtrack_count) |i| {
            const expected_class = try readU16(table, cursor + i * 2);
            const actual_class = try classValue(table, backtrack_class_def, glyphs[backtrack_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += backtrack_count * 2;

        const input_count = try readU16(table, cursor);
        cursor += 2;
        if (input_count == 0) continue;
        var input_indices_buf: [64]usize = undefined;
        if (input_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..input_count])) continue;
        for (1..input_count) |i| {
            const expected_class = try readU16(table, cursor + (i - 1) * 2);
            const actual_class = try classValue(table, input_class_def, glyphs[input_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += (@as(usize, input_count) - 1) * 2;

        const lookahead_count = try readU16(table, cursor);
        cursor += 2;
        const lookahead_start = input_indices_buf[input_count - 1] + 1;
        var lookahead_indices_buf: [64]usize = undefined;
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count])) continue;
        for (0..lookahead_count) |i| {
            const expected_class = try readU16(table, cursor + i * 2);
            const actual_class = try classValue(table, lookahead_class_def, glyphs[lookahead_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += lookahead_count * 2;

        const pos_count = try readU16(table, cursor);
        cursor += 2;
        try collectPositionRecordsMapped(table, cursor, pos_count, input_indices_buf[0..input_count], glyphs, adjustments, allocator);
        return true;
    }
    return false;
}

fn collectChainingCoveragePositioning(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const backtrack_count = try readU16(table, subtable_offset + 2);
    const backtrack_offsets_pos = subtable_offset + 4;
    const input_count_pos = backtrack_offsets_pos + @as(usize, backtrack_count) * 2;
    const input_count = try readU16(table, input_count_pos);
    if (input_count == 0) return;
    const input_offsets_pos = input_count_pos + 2;
    const lookahead_count_pos = input_offsets_pos + @as(usize, input_count) * 2;
    const lookahead_count = try readU16(table, lookahead_count_pos);
    const lookahead_offsets_pos = lookahead_count_pos + 2;
    const pos_count_pos = lookahead_offsets_pos + @as(usize, lookahead_count) * 2;
    const pos_count = try readU16(table, pos_count_pos);
    const records_pos = pos_count_pos + 2;

    var pos: usize = 0;
    while (pos < glyphs.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        var input_indices_buf: [64]usize = undefined;
        if (input_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..input_count])) continue;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGpos;
        if (!collectBacktrackUnignoredGlyphs(glyphs, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count])) continue;
        const lookahead_start = input_indices_buf[input_count - 1] + 1;
        var lookahead_indices_buf: [64]usize = undefined;
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count])) continue;
        if (!try gposCoverageIndicesMatch(table, subtable_offset, glyphs, backtrack_indices_buf[0..backtrack_count], backtrack_offsets_pos)) continue;
        if (!try gposCoverageIndicesMatch(table, subtable_offset, glyphs, input_indices_buf[0..input_count], input_offsets_pos)) continue;
        if (!try gposCoverageIndicesMatch(table, subtable_offset, glyphs, lookahead_indices_buf[0..lookahead_count], lookahead_offsets_pos)) continue;
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..input_count], glyphs, adjustments, allocator);
        pos += input_count - 1;
    }
}

fn gposCoverageSequenceMatches(table: Table, base_offset: usize, glyphs: []const GlyphId, pos: usize, offsets_pos: usize, count: usize, backtrack: bool) GposError!bool {
    if (backtrack and pos < count) return false;
    if (!backtrack and pos + count > glyphs.len) return false;
    for (0..count) |i| {
        const coverage_offset = base_offset + try readU16(table, offsets_pos + i * 2);
        const glyph = if (backtrack) glyphs[pos - 1 - i] else glyphs[pos + i];
        if (try coverageIndex(table, coverage_offset, glyph) == null) return false;
    }
    return true;
}

fn gposLookaheadCoverageMatches(table: Table, base_offset: usize, glyphs: []const GlyphId, start: usize, offsets_pos: usize, count: usize) GposError!bool {
    if (start + count > glyphs.len) return false;
    for (0..count) |i| {
        const coverage_offset = base_offset + try readU16(table, offsets_pos + i * 2);
        if (try coverageIndex(table, coverage_offset, glyphs[start + i]) == null) return false;
    }
    return true;
}

fn gposCoverageIndicesMatch(table: Table, base_offset: usize, glyphs: []const GlyphId, indices: []const usize, offsets_pos: usize) GposError!bool {
    for (indices, 0..) |glyph_index, i| {
        const coverage_offset = base_offset + try readU16(table, offsets_pos + i * 2);
        if (try coverageIndex(table, coverage_offset, glyphs[glyph_index]) == null) return false;
    }
    return true;
}

fn collectPositionRuleSet(table: Table, rule_set_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, rule_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = rule_set_offset + try readU16(table, rule_set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const pos_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (1..glyph_count) |i| {
            const expected = try readU16(table, rule_offset + 4 + (i - 1) * 2);
            if (glyphs[input_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        const records_pos = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator);
        return true;
    }
    return false;
}

fn collectClassPositionRuleSet(table: Table, set_offset: usize, class_def_offset: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const pos_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGpos;
        if (!collectForwardUnignoredGlyphs(glyphs, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (1..glyph_count) |i| {
            const expected_class = try readU16(table, rule_offset + 4 + (i - 1) * 2);
            const actual_class = try classValue(table, class_def_offset, glyphs[input_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        const records_pos = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator);
        return true;
    }
    return false;
}

fn collectPositionRecords(table: Table, records_pos: usize, record_count: usize, glyph_count: usize, glyphs: []const GlyphId, pos: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    // Each contextual positioning record points to an input-sequence glyph and a
    // nested lookup. Only nested SinglePos lookups are applied here.
    for (0..record_count) |record_i| {
        const record_offset = records_pos + record_i * 4;
        const sequence_index = try readU16(table, record_offset);
        const lookup_index = try readU16(table, record_offset + 2);
        if (sequence_index >= glyph_count) continue;
        try collectNestedSingleAdjustment(table, glyphs[pos + sequence_index], pos + sequence_index, lookup_index, adjustments, allocator);
    }
}

fn collectPositionRecordsMapped(table: Table, records_pos: usize, record_count: usize, input_indices: []const usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    for (0..record_count) |record_i| {
        const record_offset = records_pos + record_i * 4;
        const sequence_index = try readU16(table, record_offset);
        const lookup_index = try readU16(table, record_offset + 2);
        if (sequence_index >= input_indices.len) continue;
        const target_index = input_indices[sequence_index];
        try collectNestedSingleAdjustment(table, glyphs[target_index], target_index, lookup_index, adjustments, allocator);
    }
}

fn collectNestedSingleAdjustment(table: Table, glyph: GlyphId, target_index: usize, lookup_index: u16, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const lookup_list_offset = try readU16(table, 8);
    const lookup_count = try readU16(table, lookup_list_offset);
    if (lookup_index >= lookup_count) return;
    const lookup_offset = lookup_list_offset + try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2);
    const lookup_type = try readU16(table, lookup_offset);
    if (lookup_type != 1) return;
    const subtable_count = try readU16(table, lookup_offset + 4);
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        const pos_format = try readU16(table, subtable_offset);
        const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
        const value_format = try readU16(table, subtable_offset + 4);
        switch (pos_format) {
            1 => {
                if (try coverageIndex(table, coverage_offset, glyph) != null) {
                    const value = try readValueRecord(table, subtable_offset + 6, value_format);
                    try appendAdjustment(adjustments, allocator, target_index, value, false);
                }
            },
            2 => {
                const coverage = try coverageIndex(table, coverage_offset, glyph) orelse continue;
                const value_count = try readU16(table, subtable_offset + 6);
                if (coverage >= value_count) continue;
                const value_size = valueRecordSize(value_format);
                const value = try readValueRecord(table, subtable_offset + 8 + coverage * value_size, value_format);
                try appendAdjustment(adjustments, allocator, target_index, value, false);
            },
            else => return error.UnsupportedGpos,
        }
    }
}

fn collectMarkToLigatureAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const ligature_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_array_offset = subtable_offset + try readU16(table, subtable_offset + 8);
    const ligature_array_offset = subtable_offset + try readU16(table, subtable_offset + 10);
    if (class_count == 0 or glyphs.len < 2) return;

    for (glyphs, 0..) |glyph, i| {
        const mark_index = try coverageIndex(table, mark_coverage_offset, glyph) orelse continue;
        if (i == 0) continue;
        const ligature_index = try coverageIndex(table, ligature_coverage_offset, glyphs[i - 1]) orelse continue;
        const mark_record_offset = mark_array_offset + 2 + mark_index * 4;
        const mark_class = try readU16(table, mark_record_offset);
        if (mark_class >= class_count) continue;
        const mark_anchor_offset = mark_array_offset + try readU16(table, mark_record_offset + 2);
        const ligature_attach_offset = ligature_array_offset + try readU16(table, ligature_array_offset + 2 + ligature_index * 2);
        const component_count = try readU16(table, ligature_attach_offset);
        if (component_count == 0) continue;
        const component_index: usize = 0;
        const anchor_record = ligature_attach_offset + 2 + (component_index * class_count + mark_class) * 2;
        const ligature_anchor_relative = try readU16(table, anchor_record);
        if (ligature_anchor_relative == 0) continue;
        const ligature_anchor_offset = ligature_attach_offset + ligature_anchor_relative;
        const mark_anchor = try readAnchor(table, mark_anchor_offset);
        const ligature_anchor = try readAnchor(table, ligature_anchor_offset);
        try appendAdjustmentEx(adjustments, allocator, i, .{
            .index = i,
            .x_placement = ligature_anchor.x - mark_anchor.x,
            .y_placement = ligature_anchor.y - mark_anchor.y,
        }, .{ .mark_attachment = true });
    }
}

fn collectMarkToMarkAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_1_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const mark_2_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_1_array_offset = subtable_offset + try readU16(table, subtable_offset + 8);
    const mark_2_array_offset = subtable_offset + try readU16(table, subtable_offset + 10);
    if (class_count == 0 or glyphs.len < 2) return;

    for (glyphs, 0..) |glyph, i| {
        const mark_1_index = try coverageIndex(table, mark_1_coverage_offset, glyph) orelse continue;
        if (i == 0) continue;
        const mark_2_index = try coverageIndex(table, mark_2_coverage_offset, glyphs[i - 1]) orelse continue;
        const mark_1_record_offset = mark_1_array_offset + 2 + mark_1_index * 4;
        const mark_class = try readU16(table, mark_1_record_offset);
        if (mark_class >= class_count) continue;
        const mark_1_anchor_offset = mark_1_array_offset + try readU16(table, mark_1_record_offset + 2);
        const mark_2_anchor_record = mark_2_array_offset + 2 + (mark_2_index * class_count + mark_class) * 2;
        const mark_2_anchor_relative = try readU16(table, mark_2_anchor_record);
        if (mark_2_anchor_relative == 0) continue;
        const mark_2_anchor_offset = mark_2_array_offset + mark_2_anchor_relative;
        const mark_1_anchor = try readAnchor(table, mark_1_anchor_offset);
        const mark_2_anchor = try readAnchor(table, mark_2_anchor_offset);
        try appendAdjustmentEx(adjustments, allocator, i, .{
            .index = i,
            .x_placement = mark_2_anchor.x - mark_1_anchor.x,
            .y_placement = mark_2_anchor.y - mark_1_anchor.y,
        }, .{ .mark_attachment = true });
    }
}

const Anchor = struct {
    x: i16,
    y: i16,
};

fn readAnchor(table: Table, anchor_offset: usize) GposError!Anchor {
    const format = try readU16(table, anchor_offset);
    if (format != 1) return error.UnsupportedGpos;
    return .{
        .x = try readI16(table, anchor_offset + 2),
        .y = try readI16(table, anchor_offset + 4),
    };
}

fn valueRecordSize(format: u16) usize {
    var size: usize = 0;
    if ((format & 0x0001) != 0) size += 2;
    if ((format & 0x0002) != 0) size += 2;
    if ((format & 0x0004) != 0) size += 2;
    if ((format & 0x0008) != 0) size += 2;
    if ((format & 0x0010) != 0) size += 2;
    if ((format & 0x0020) != 0) size += 2;
    if ((format & 0x0040) != 0) size += 2;
    if ((format & 0x0080) != 0) size += 2;
    return size;
}

fn readValueRecord(table: Table, offset: usize, format: u16) GposError!Adjustment {
    // ValueFormat bits decide which signed fields are present and in what order.
    // Device-table offsets are intentionally unsupported for now.
    var value = Adjustment{ .index = 0 };
    var cursor = offset;
    if ((format & 0x0001) != 0) {
        value.x_placement = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x0002) != 0) {
        value.y_placement = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x0004) != 0) {
        value.x_advance = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x0008) != 0) {
        value.y_advance = try readI16(table, cursor);
        cursor += 2;
    }
    if ((format & 0x00f0) != 0) return error.UnsupportedGpos;
    return value;
}

fn coverageIndex(table: Table, coverage_offset: usize, glyph: GlyphId) GposError!?usize {
    // Coverage handling mirrors GSUB so coverage index semantics remain
    // identical between substitution and positioning code.
    const format = try readU16(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16(table, coverage_offset + 2);
            var lo: usize = 0;
            var hi: usize = glyph_count;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const candidate = try readU16(table, coverage_offset + 4 + mid * 2);
                if (glyph < candidate) {
                    hi = mid;
                } else if (glyph > candidate) {
                    lo = mid + 1;
                } else {
                    return mid;
                }
            }
            return null;
        },
        2 => {
            const range_count = try readU16(table, coverage_offset + 2);
            for (0..range_count) |i| {
                const range_offset = coverage_offset + 4 + i * 6;
                const start = try readU16(table, range_offset);
                const end = try readU16(table, range_offset + 2);
                const start_index = try readU16(table, range_offset + 4);
                if (glyph >= start and glyph <= end) return start_index + glyph - start;
            }
            return null;
        },
        else => return error.UnsupportedGpos,
    }
}

fn classValue(table: Table, class_def_offset: usize, glyph: GlyphId) GposError!u16 {
    const format = try readU16(table, class_def_offset);
    switch (format) {
        1 => {
            const start = try readU16(table, class_def_offset + 2);
            const count = try readU16(table, class_def_offset + 4);
            if (glyph < start or glyph >= start + count) return 0;
            return try readU16(table, class_def_offset + 6 + @as(usize, glyph - start) * 2);
        },
        2 => {
            const range_count = try readU16(table, class_def_offset + 2);
            for (0..range_count) |i| {
                const range_offset = class_def_offset + 4 + i * 6;
                const start = try readU16(table, range_offset);
                const end = try readU16(table, range_offset + 2);
                const class = try readU16(table, range_offset + 4);
                if (glyph >= start and glyph <= end) return class;
            }
            return 0;
        },
        else => return error.UnsupportedGpos,
    }
}

fn readU16(table: Table, relative: usize) GposError!u16 {
    if (relative + 2 > table.length) return error.EndOfStream;
    return bin.readU16At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

fn readI16(table: Table, relative: usize) GposError!i16 {
    if (relative + 2 > table.length) return error.EndOfStream;
    return bin.readI16At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

fn readU32(table: Table, relative: usize) GposError!u32 {
    if (relative + 4 > table.length) return error.EndOfStream;
    return bin.readU32At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}
