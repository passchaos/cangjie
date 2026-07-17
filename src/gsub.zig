const std = @import("std");
const bin = @import("binary.zig");
const GlyphId = @import("glyph.zig").GlyphId;
const unicode = @import("unicode.zig");

/// GSUB parsing is table-driven and intentionally tolerant of unsupported
/// lookup types: unknown lookups are skipped, while malformed supported lookup
/// data reports BadGsub/UnsupportedGsub.
pub const GsubError = error{
    BadGsub,
    UnsupportedGsub,
    EndOfStream,
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
    apply_all_if_unselected: bool = true,
    glyph_classes: ?[]const u16 = null,
    mark_attach_classes: ?[]const u16 = null,
};

/// Apply default or explicitly enabled substitution features to the glyph
/// stream in place. The input and output are glyph ids; source text metadata is
/// handled by the caller because GSUB itself has no Unicode context.
pub fn apply(data: []const u8, offset: usize, length: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)!void {
    return try applyWithOptions(data, offset, length, glyphs, allocator, .{});
}

pub fn applyWithOptions(data: []const u8, offset: usize, length: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    if (length < 10 or offset > data.len or length > data.len - offset) return error.BadGsub;
    const table = Table{ .data = data, .offset = offset, .length = length };
    const major = try readU16(table, 0);
    if (major != 1) return error.UnsupportedGsub;
    // Script/language/feature selection happens before the lookup list pass.
    // When no explicit features are supplied, selectedLookupIndices returns the
    // default-enabled lookups for the requested script/language.
    var selected_lookups = try selectedLookupIndices(table, allocator, options);
    defer selected_lookups.deinit(allocator);
    const script_list_offset = try readU16(table, 4);
    const feature_list_offset = try readU16(table, 6);
    const has_feature_topology = script_list_offset != 0 and
        feature_list_offset != 0 and
        try readU16(table, script_list_offset) != 0 and
        try readU16(table, feature_list_offset) != 0;
    // An empty selection means the active LangSys has no required/default
    // feature to apply. Falling through used to execute every lookup in the
    // font, enabling optional stylistic sets such as New Computer Modern's
    // Devanagari digit substitutions for ordinary ASCII digits. Low-level
    // callers can retain the historical all-lookup behavior; the text shaper
    // explicitly disables it after Script/LangSys selection.
    if (selected_lookups.items.len == 0 and
        (options.features.len != 0 or (!options.apply_all_if_unselected and has_feature_topology))) return;

    const lookup_list_offset = try readU16(table, 8);
    const lookup_count = try readU16(table, lookup_list_offset);
    for (0..lookup_count) |i| {
        if (selected_lookups.items.len != 0 and !containsLookup(selected_lookups.items, @intCast(i))) continue;
        const lookup_offset = try readU16(table, lookup_list_offset + 2 + i * 2);
        try applyLookup(table, lookup_list_offset + lookup_offset, glyphs, allocator, options);
    }
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var feature_indices = std.ArrayList(u16).empty;
    defer feature_indices.deinit(allocator);
    var lookups = std.ArrayList(u16).empty;
    errdefer lookups.deinit(allocator);

    const script_list_offset = try readU16(table, 4);
    const feature_list_offset = try readU16(table, 6);
    if (script_list_offset == 0 or feature_list_offset == 0) return lookups;

    const script_count = try readU16(table, script_list_offset);
    // Prefer the requested script, then fall back to DFLT. Language selection
    // mirrors OpenType: a matching LangSys overrides the default LangSys.
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
    return defaultFeatureEnabled(feature_tag);
}

fn defaultFeatureEnabled(feature_tag: u32) bool {
    // Keep only shaping features that are expected to be on by default. Optional
    // stylistic features remain disabled unless the caller passes overrides.
    return feature_tag == unicode.tag("ccmp") or
        feature_tag == unicode.tag("locl") or
        feature_tag == unicode.tag("rlig") or
        feature_tag == unicode.tag("liga") or
        feature_tag == unicode.tag("clig") or
        feature_tag == unicode.tag("calt") or
        feature_tag == unicode.tag("rclt");
}

fn findScriptOffset(table: Table, script_list_offset: usize, script_count: u16, script_tag: u32) GsubError!?usize {
    for (0..script_count) |script_i| {
        const script_record = script_list_offset + 2 + script_i * 6;
        if (try readU32(table, script_record) != script_tag) continue;
        return script_list_offset + try readU16(table, script_record + 4);
    }
    return null;
}

fn collectScriptFeatures(table: Table, script_offset: usize, language_tag: unicode.OpenTypeLanguageTag, feature_indices: *std.ArrayList(u16), allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)!void {
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

fn findLangSysOffset(table: Table, script_offset: usize, language_tag: u32) (GsubError || std.mem.Allocator.Error)!?usize {
    const lang_sys_count = try readU16(table, script_offset + 2);
    for (0..lang_sys_count) |lang_i| {
        const lang_record = script_offset + 4 + lang_i * 6;
        if (try readU32(table, lang_record) != language_tag) continue;
        return script_offset + try readU16(table, lang_record + 4);
    }
    return null;
}

fn collectLangSysFeatures(table: Table, lang_sys_offset: usize, feature_indices: *std.ArrayList(u16), allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)!void {
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

fn applyLookup(table: Table, lookup_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const lookup_type = try readU16(table, lookup_offset);
    const lookup_flag = try readU16(table, lookup_offset + 2);
    const subtable_count = try readU16(table, lookup_offset + 4);
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => try applySingleSubstitution(table, subtable_offset, glyphs, lookup_flag, options),
            2 => try applyMultipleSubstitution(table, subtable_offset, glyphs, allocator),
            3 => try applyAlternateSubstitution(table, subtable_offset, glyphs),
            4 => try applyLigatureSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
            5 => try applyContextSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
            6 => try applyChainingContextSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
            7 => try applyExtensionSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
            8 => try applyReverseChainingSingleSubstitution(table, subtable_offset, glyphs),
            else => {},
        }
    }
}

fn applySingleSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), lookup_flag: u16, options: LookupOptions) GsubError!void {
    const subst_format = try readU16(table, subtable_offset);
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    switch (subst_format) {
        1 => {
            const delta = try readI16(table, subtable_offset + 4);
            for (glyphs.items) |*glyph| {
                if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
                if (try coverageIndex(table, coverage_offset, glyph.*) != null) {
                    glyph.* = @bitCast(@as(i16, @bitCast(glyph.*)) +% delta);
                }
            }
        },
        2 => {
            const glyph_count = try readU16(table, subtable_offset + 4);
            for (glyphs.items) |*glyph| {
                if (lookupIgnoresGlyph(lookup_flag, options, glyph.*)) continue;
                if (try coverageIndex(table, coverage_offset, glyph.*)) |index| {
                    if (index < glyph_count) glyph.* = try readU16(table, subtable_offset + 6 + index * 2);
                }
            }
        },
        else => return error.UnsupportedGsub,
    }
}

fn lookupIgnoresGlyph(lookup_flag: u16, options: LookupOptions, glyph: GlyphId) bool {
    // Lookup flags use GDEF glyph classes. Without GDEF class data the lookup is
    // applied to all glyphs, which matches the behavior of many simple fonts.
    const classes = options.glyph_classes orelse return false;
    if (glyph >= classes.len) return false;
    const class = classes[glyph];
    if ((lookup_flag & 0x0002) != 0 and class == 1) return true;
    if ((lookup_flag & 0x0004) != 0 and class == 2) return true;
    if ((lookup_flag & 0x0008) != 0 and class == 3) return true;
    const mark_attachment_type = lookup_flag >> 8;
    if (mark_attachment_type != 0 and class == 3) {
        const attach_classes = options.mark_attach_classes orelse return true;
        if (glyph >= attach_classes.len) return true;
        return attach_classes[glyph] != mark_attachment_type;
    }
    return false;
}

fn applyMultipleSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const sequence_count = try readU16(table, subtable_offset + 4);

    var i: usize = 0;
    while (i < glyphs.items.len) : (i += 1) {
        const coverage = try coverageIndex(table, coverage_offset, glyphs.items[i]) orelse continue;
        if (coverage >= sequence_count) continue;
        const sequence_offset = subtable_offset + try readU16(table, subtable_offset + 6 + coverage * 2);
        const glyph_count = try readU16(table, sequence_offset);
        if (glyph_count == 0) {
            // A zero-length sequence deletes the covered glyph.
            try glyphs.replaceRange(allocator, i, 1, &.{});
            if (i > 0) i -= 1;
            continue;
        }
        const replacement = try allocator.alloc(GlyphId, glyph_count);
        defer allocator.free(replacement);
        for (replacement, 0..) |*glyph, replacement_index| {
            glyph.* = try readU16(table, sequence_offset + 2 + replacement_index * 2);
        }
        try glyphs.replaceRange(allocator, i, 1, replacement);
        i += glyph_count - 1;
    }
}

fn applyAlternateSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId)) GsubError!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const alternate_set_count = try readU16(table, subtable_offset + 4);

    for (glyphs.items) |*glyph| {
        const coverage = try coverageIndex(table, coverage_offset, glyph.*) orelse continue;
        if (coverage >= alternate_set_count) continue;
        const alternate_set_offset = subtable_offset + try readU16(table, subtable_offset + 6 + coverage * 2);
        const glyph_count = try readU16(table, alternate_set_offset);
        if (glyph_count == 0) continue;
        glyph.* = try readU16(table, alternate_set_offset + 2);
    }
}

fn applyExtensionSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 7) return error.UnsupportedGsub;
    const extension_offset = try readU32(table, subtable_offset + 4);
    const extension_subtable = subtable_offset + extension_offset;
    // Extension subtables only move the payload past 16-bit offset limits; the
    // wrapper lookup still owns LookupFlag filtering for the enclosed lookup.
    switch (extension_lookup_type) {
        1 => try applySingleSubstitution(table, extension_subtable, glyphs, lookup_flag, options),
        2 => try applyMultipleSubstitution(table, extension_subtable, glyphs, allocator),
        3 => try applyAlternateSubstitution(table, extension_subtable, glyphs),
        4 => try applyLigatureSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        5 => try applyContextSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        6 => try applyChainingContextSubstitution(table, extension_subtable, glyphs, allocator, lookup_flag, options),
        8 => try applyReverseChainingSingleSubstitution(table, extension_subtable, glyphs),
        else => {},
    }
}

fn applyLigatureSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const lig_set_count = try readU16(table, subtable_offset + 4);

    var i: usize = 0;
    while (i < glyphs.items.len) : (i += 1) {
        const first = glyphs.items[i];
        if (lookupIgnoresGlyph(lookup_flag, options, first)) continue;
        const covered = try coverageIndex(table, coverage_offset, first) orelse continue;
        if (covered >= lig_set_count) continue;
        const set_offset = subtable_offset + try readU16(table, subtable_offset + 6 + covered * 2);
        if (try ligatureAt(table, set_offset, glyphs.items[i..], lookup_flag, options)) |match| {
            glyphs.items[i] = match.ligature;
            if (match.component_count > 1) {
                var component_index = match.component_count;
                while (component_index > 1) {
                    component_index -= 1;
                    try glyphs.replaceRange(allocator, i + match.component_offsets[component_index], 1, &.{});
                }
            }
        }
    }
}

fn applyContextSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    switch (subst_format) {
        1 => {
            const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
            const rule_set_count = try readU16(table, subtable_offset + 4);
            var pos: usize = 0;
            while (pos < glyphs.items.len) : (pos += 1) {
                if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
                const coverage = try coverageIndex(table, coverage_offset, glyphs.items[pos]) orelse continue;
                if (coverage >= rule_set_count) continue;
                const rule_set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
                if (rule_set_relative == 0) continue;
                const rule_set_offset = subtable_offset + rule_set_relative;
                if (try applyContextRuleSet(table, rule_set_offset, glyphs, pos, allocator, lookup_flag, options)) {
                    pos += 1;
                }
            }
        },
        2 => try applyContextClassSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        3 => try applyContextCoverageSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        else => return error.UnsupportedGsub,
    }
}

fn applyContextClassSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const class_def_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_set_count = try readU16(table, subtable_offset + 6);
    var pos: usize = 0;
    while (pos < glyphs.items.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        if (try coverageIndex(table, coverage_offset, glyphs.items[pos]) == null) continue;
        const class = try classValue(table, class_def_offset, glyphs.items[pos]);
        if (class >= class_set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 8 + @as(usize, class) * 2);
        if (set_relative == 0) continue;
        if (try applyClassRuleSet(table, subtable_offset + set_relative, class_def_offset, glyphs, pos, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn applyClassRuleSet(table: Table, rule_set_offset: usize, class_def_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, rule_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = rule_set_offset + try readU16(table, rule_set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const subst_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0 or pos + glyph_count > glyphs.items.len) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (1..glyph_count) |i| {
            const expected_class = try readU16(table, rule_offset + 4 + (i - 1) * 2);
            const actual_class = try classValue(table, class_def_offset, glyphs.items[input_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        // Once the input classes match, each substitution record points at a
        // glyph within the matched input sequence and a nested lookup index.
        const records_offset = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        for (0..subst_count) |subst_i| {
            const record_offset = records_offset + subst_i * 4;
            const sequence_index = try readU16(table, record_offset);
            const lookup_index = try readU16(table, record_offset + 2);
            if (sequence_index >= glyph_count) continue;
            try applyNestedSingleGlyphLookup(table, glyphs, input_indices_buf[sequence_index], lookup_index, allocator);
        }
        return true;
    }
    return false;
}

fn applyContextCoverageSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const glyph_count = try readU16(table, subtable_offset + 2);
    const subst_count = try readU16(table, subtable_offset + 4);
    if (glyph_count == 0) return;
    const coverage_offsets_pos = subtable_offset + 6;
    const subst_records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
    var pos: usize = 0;
    while (pos < glyphs.items.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (0..glyph_count) |i| {
            const coverage_offset = subtable_offset + try readU16(table, coverage_offsets_pos + i * 2);
            if (try coverageIndex(table, coverage_offset, glyphs.items[input_indices_buf[i]]) == null) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        for (0..subst_count) |subst_i| {
            const record_offset = subst_records_pos + subst_i * 4;
            const sequence_index = try readU16(table, record_offset);
            const lookup_index = try readU16(table, record_offset + 2);
            if (sequence_index >= glyph_count) continue;
            try applyNestedSingleGlyphLookup(table, glyphs, input_indices_buf[sequence_index], lookup_index, allocator);
        }
        pos += glyph_count - 1;
    }
}

fn applyContextRuleSet(table: Table, rule_set_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, rule_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = rule_set_offset + try readU16(table, rule_set_offset + 2 + rule_i * 2);
        const glyph_count = try readU16(table, rule_offset);
        const subst_count = try readU16(table, rule_offset + 2);
        if (glyph_count == 0 or pos + glyph_count > glyphs.items.len) continue;
        var input_indices_buf: [64]usize = undefined;
        if (glyph_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..glyph_count])) continue;
        var matched = true;
        for (1..glyph_count) |component_i| {
            const expected = try readU16(table, rule_offset + 4 + (component_i - 1) * 2);
            if (glyphs.items[input_indices_buf[component_i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;

        const records_offset = rule_offset + 4 + (@as(usize, glyph_count) - 1) * 2;
        for (0..subst_count) |subst_i| {
            const record_offset = records_offset + subst_i * 4;
            const sequence_index = try readU16(table, record_offset);
            const lookup_index = try readU16(table, record_offset + 2);
            if (sequence_index >= glyph_count) continue;
            try applyNestedSingleGlyphLookup(table, glyphs, input_indices_buf[sequence_index], lookup_index, allocator);
        }
        return true;
    }
    return false;
}

fn applyChainingContextSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const subst_format = try readU16(table, subtable_offset);
    switch (subst_format) {
        1 => {
            const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
            const chain_set_count = try readU16(table, subtable_offset + 4);
            var pos: usize = 0;
            while (pos < glyphs.items.len) : (pos += 1) {
                if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
                const coverage = try coverageIndex(table, coverage_offset, glyphs.items[pos]) orelse continue;
                if (coverage >= chain_set_count) continue;
                const set_relative = try readU16(table, subtable_offset + 6 + coverage * 2);
                if (set_relative == 0) continue;
                if (try applyChainingRuleSet(table, subtable_offset + set_relative, glyphs, pos, allocator, lookup_flag, options)) {
                    pos += 1;
                }
            }
        },
        2 => try applyChainingClassSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        3 => try applyChainingCoverageSubstitution(table, subtable_offset, glyphs, allocator, lookup_flag, options),
        else => return error.UnsupportedGsub,
    }
}

fn applyChainingClassSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const backtrack_class_def = subtable_offset + try readU16(table, subtable_offset + 4);
    const input_class_def = subtable_offset + try readU16(table, subtable_offset + 6);
    const lookahead_class_def = subtable_offset + try readU16(table, subtable_offset + 8);
    const set_count = try readU16(table, subtable_offset + 10);
    var pos: usize = 0;
    while (pos < glyphs.items.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        if (try coverageIndex(table, coverage_offset, glyphs.items[pos]) == null) continue;
        const input_class = try classValue(table, input_class_def, glyphs.items[pos]);
        if (input_class >= set_count) continue;
        const set_relative = try readU16(table, subtable_offset + 12 + @as(usize, input_class) * 2);
        if (set_relative == 0) continue;
        if (try applyChainingClassRuleSet(table, subtable_offset + set_relative, backtrack_class_def, input_class_def, lookahead_class_def, glyphs, pos, allocator, lookup_flag, options)) {
            pos += 1;
        }
    }
}

fn applyChainingClassRuleSet(table: Table, set_offset: usize, backtrack_class_def: usize, input_class_def: usize, lookahead_class_def: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = set_offset + try readU16(table, set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;

        // Chaining rules match three regions around `pos`: backtrack before the
        // input, input at `pos`, and lookahead after the input.
        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGsub;
        if (!collectBacktrackUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count])) continue;
        var matched = true;
        for (0..backtrack_count) |i| {
            const expected_class = try readU16(table, cursor + i * 2);
            const actual_class = try classValue(table, backtrack_class_def, glyphs.items[backtrack_indices_buf[i]]);
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
        if (input_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..input_count])) continue;
        for (1..input_count) |i| {
            const expected_class = try readU16(table, cursor + (i - 1) * 2);
            const actual_class = try classValue(table, input_class_def, glyphs.items[input_indices_buf[i]]);
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
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count])) continue;
        for (0..lookahead_count) |i| {
            const expected_class = try readU16(table, cursor + i * 2);
            const actual_class = try classValue(table, lookahead_class_def, glyphs.items[lookahead_indices_buf[i]]);
            if (actual_class != expected_class) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += lookahead_count * 2;

        const subst_count = try readU16(table, cursor);
        cursor += 2;
        for (0..subst_count) |subst_i| {
            const record_offset = cursor + subst_i * 4;
            const sequence_index = try readU16(table, record_offset);
            const lookup_index = try readU16(table, record_offset + 2);
            if (sequence_index >= input_count) continue;
            try applyNestedSingleGlyphLookup(table, glyphs, input_indices_buf[sequence_index], lookup_index, allocator);
        }
        return true;
    }
    return false;
}

fn applyChainingCoverageSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!void {
    var cursor = subtable_offset + 2;
    const backtrack_count = try readU16(table, cursor);
    cursor += 2;
    const backtrack_offsets_pos = cursor;
    cursor += backtrack_count * 2;

    const input_count = try readU16(table, cursor);
    cursor += 2;
    if (input_count == 0) return;
    const input_offsets_pos = cursor;
    cursor += input_count * 2;

    const lookahead_count = try readU16(table, cursor);
    cursor += 2;
    const lookahead_offsets_pos = cursor;
    cursor += lookahead_count * 2;

    const subst_count = try readU16(table, cursor);
    cursor += 2;
    const records_pos = cursor;

    var pos: usize = 0;
    while (pos < glyphs.items.len) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs.items[pos])) continue;
        var input_indices_buf: [64]usize = undefined;
        if (input_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..input_count])) continue;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGsub;
        if (!collectBacktrackUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count])) continue;
        const lookahead_start = input_indices_buf[input_count - 1] + 1;
        var lookahead_indices_buf: [64]usize = undefined;
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count])) continue;
        if (!try coverageIndicesMatch(table, subtable_offset, glyphs.items, backtrack_indices_buf[0..backtrack_count], backtrack_offsets_pos)) continue;
        if (!try coverageIndicesMatch(table, subtable_offset, glyphs.items, input_indices_buf[0..input_count], input_offsets_pos)) continue;
        if (!try coverageIndicesMatch(table, subtable_offset, glyphs.items, lookahead_indices_buf[0..lookahead_count], lookahead_offsets_pos)) continue;
        for (0..subst_count) |subst_i| {
            const record_offset = records_pos + subst_i * 4;
            const sequence_index = try readU16(table, record_offset);
            const lookup_index = try readU16(table, record_offset + 2);
            if (sequence_index >= input_count) continue;
            try applyNestedSingleGlyphLookup(table, glyphs, input_indices_buf[sequence_index], lookup_index, allocator);
        }
        pos += input_count - 1;
    }
}

const CoverageSequenceKind = enum {
    backtrack,
    input,
    lookahead,
};

fn collectForwardUnignoredGlyphs(glyphs: []const GlyphId, start: usize, lookup_flag: u16, options: LookupOptions, out: []usize) bool {
    // Contextual GSUB sequences are written in terms of glyphs that the lookup
    // participates in. IgnoreBase/Ligature/Mark and mark attachment filters
    // remove glyphs from matching, but those skipped glyphs must remain in the
    // buffer so sequence indexes can still target the original glyph positions.
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

fn coverageIndicesMatch(table: Table, base_offset: usize, glyphs: []const GlyphId, indices: []const usize, offsets_pos: usize) GsubError!bool {
    for (indices, 0..) |glyph_index, i| {
        const coverage_offset = base_offset + try readU16(table, offsets_pos + i * 2);
        if (try coverageIndex(table, coverage_offset, glyphs[glyph_index]) == null) return false;
    }
    return true;
}

fn coverageSequenceMatches(table: Table, base_offset: usize, glyphs: []const GlyphId, pos: usize, offsets_pos: usize, count: usize, kind: CoverageSequenceKind) GsubError!bool {
    switch (kind) {
        .backtrack => if (pos < count) return false,
        .input, .lookahead => if (pos + count > glyphs.len) return false,
    }
    for (0..count) |i| {
        const coverage_offset = base_offset + try readU16(table, offsets_pos + i * 2);
        const glyph_index = switch (kind) {
            .backtrack => pos - 1 - i,
            .input, .lookahead => pos + i,
        };
        if (try coverageIndex(table, coverage_offset, glyphs[glyph_index]) == null) return false;
    }
    return true;
}

fn applyChainingRuleSet(table: Table, chain_set_offset: usize, glyphs: *std.ArrayList(GlyphId), pos: usize, allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GsubError || std.mem.Allocator.Error)!bool {
    const rule_count = try readU16(table, chain_set_offset);
    for (0..rule_count) |rule_i| {
        const rule_offset = chain_set_offset + try readU16(table, chain_set_offset + 2 + rule_i * 2);
        var cursor = rule_offset;

        const backtrack_count = try readU16(table, cursor);
        cursor += 2;
        var backtrack_indices_buf: [64]usize = undefined;
        if (backtrack_count > backtrack_indices_buf.len) return error.UnsupportedGsub;
        if (!collectBacktrackUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, backtrack_indices_buf[0..backtrack_count])) continue;
        var matched = true;
        for (0..backtrack_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs.items[backtrack_indices_buf[i]] != expected) {
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
        if (input_count > input_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, pos, lookup_flag, options, input_indices_buf[0..input_count])) continue;
        for (1..input_count) |i| {
            const expected = try readU16(table, cursor + (i - 1) * 2);
            if (glyphs.items[input_indices_buf[i]] != expected) {
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
        if (lookahead_count > lookahead_indices_buf.len) return error.UnsupportedGsub;
        if (!collectForwardUnignoredGlyphs(glyphs.items, lookahead_start, lookup_flag, options, lookahead_indices_buf[0..lookahead_count])) continue;
        for (0..lookahead_count) |i| {
            const expected = try readU16(table, cursor + i * 2);
            if (glyphs.items[lookahead_indices_buf[i]] != expected) {
                matched = false;
                break;
            }
        }
        if (!matched) continue;
        cursor += lookahead_count * 2;

        const subst_count = try readU16(table, cursor);
        cursor += 2;
        for (0..subst_count) |subst_i| {
            const record_offset = cursor + subst_i * 4;
            const sequence_index = try readU16(table, record_offset);
            const lookup_index = try readU16(table, record_offset + 2);
            if (sequence_index >= input_count) continue;
            try applyNestedSingleGlyphLookup(table, glyphs, input_indices_buf[sequence_index], lookup_index, allocator);
        }
        return true;
    }
    return false;
}

fn applyNestedSingleGlyphLookup(table: Table, glyphs: *std.ArrayList(GlyphId), glyph_index: usize, lookup_index: u16, allocator: std.mem.Allocator) (GsubError || std.mem.Allocator.Error)!void {
    const lookup_list_offset = try readU16(table, 8);
    const lookup_count = try readU16(table, lookup_list_offset);
    if (lookup_index >= lookup_count) return;
    const nested_lookup_offset = lookup_list_offset + try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2);
    // Contextual records target one glyph. Run the nested lookup on a one-glyph
    // slice and only write back when the nested lookup preserves cardinality.
    var slice = std.ArrayList(GlyphId).empty;
    defer slice.deinit(allocator);
    try slice.append(allocator, glyphs.items[glyph_index]);
    try applyLookup(table, nested_lookup_offset, &slice, allocator, .{});
    if (slice.items.len == 1) glyphs.items[glyph_index] = slice.items[0];
}

fn applyReverseChainingSingleSubstitution(table: Table, subtable_offset: usize, glyphs: *std.ArrayList(GlyphId)) GsubError!void {
    const subst_format = try readU16(table, subtable_offset);
    if (subst_format != 1) return error.UnsupportedGsub;
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    var cursor = subtable_offset + 4;

    const backtrack_count = try readU16(table, cursor);
    cursor += 2;
    const backtrack_offsets_pos = cursor;
    cursor += backtrack_count * 2;

    const lookahead_count = try readU16(table, cursor);
    cursor += 2;
    const lookahead_offsets_pos = cursor;
    cursor += lookahead_count * 2;

    const glyph_count = try readU16(table, cursor);
    cursor += 2;
    const substitutes_pos = cursor;

    if (glyphs.items.len == 0) return;
    // Reverse chaining scans backward so earlier replacements cannot influence
    // the lookahead context of glyphs that have not been visited yet.
    var pos = glyphs.items.len;
    while (pos > 0) {
        pos -= 1;
        const coverage = try coverageIndex(table, coverage_offset, glyphs.items[pos]) orelse continue;
        if (coverage >= glyph_count) continue;
        if (!try reverseCoverageMatches(table, subtable_offset, glyphs.items, pos, backtrack_offsets_pos, backtrack_count, true)) continue;
        if (!try reverseCoverageMatches(table, subtable_offset, glyphs.items, pos, lookahead_offsets_pos, lookahead_count, false)) continue;
        glyphs.items[pos] = try readU16(table, substitutes_pos + coverage * 2);
    }
}

fn reverseCoverageMatches(table: Table, subtable_offset: usize, glyphs: []const GlyphId, pos: usize, offsets_pos: usize, count: usize, backtrack: bool) GsubError!bool {
    if (backtrack and pos < count) return false;
    if (!backtrack and pos + 1 + count > glyphs.len) return false;
    for (0..count) |i| {
        const coverage_offset = subtable_offset + try readU16(table, offsets_pos + i * 2);
        const glyph = if (backtrack) glyphs[pos - 1 - i] else glyphs[pos + 1 + i];
        if (try coverageIndex(table, coverage_offset, glyph) == null) return false;
    }
    return true;
}

const LigatureMatch = struct {
    ligature: GlyphId,
    component_count: usize,
    component_offsets: [max_ligature_components]usize = [_]usize{0} ** max_ligature_components,
};

const max_ligature_components = 64;

fn ligatureAt(table: Table, set_offset: usize, glyphs: []const GlyphId, lookup_flag: u16, options: LookupOptions) GsubError!?LigatureMatch {
    const ligature_count = try readU16(table, set_offset);
    var best: ?LigatureMatch = null;
    for (0..ligature_count) |i| {
        const lig_offset = set_offset + try readU16(table, set_offset + 2 + i * 2);
        const ligature = try readU16(table, lig_offset);
        const component_count = try readU16(table, lig_offset + 2);
        if (component_count == 0 or component_count > max_ligature_components) continue;
        var component_offsets = [_]usize{0} ** max_ligature_components;
        var ok = true;
        var cursor: usize = 1;
        for (1..component_count) |component_index| {
            const expected = try readU16(table, lig_offset + 4 + (component_index - 1) * 2);
            while (cursor < glyphs.len and lookupIgnoresGlyph(lookup_flag, options, glyphs[cursor])) : (cursor += 1) {}
            if (cursor >= glyphs.len or glyphs[cursor] != expected) {
                ok = false;
                break;
            }
            component_offsets[component_index] = cursor;
            cursor += 1;
        }
        if (ok and (best == null or component_count > best.?.component_count)) {
            best = .{ .ligature = ligature, .component_count = component_count, .component_offsets = component_offsets };
        }
    }
    return best;
}

fn coverageIndex(table: Table, coverage_offset: usize, glyph: GlyphId) GsubError!?usize {
    // Coverage tables are the common membership/index primitive used by nearly
    // every GSUB subtable. Format 1 is sorted glyph ids; format 2 is ranges.
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
        else => return error.UnsupportedGsub,
    }
}

fn classValue(table: Table, class_def_offset: usize, glyph: GlyphId) GsubError!u16 {
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
        else => return error.UnsupportedGsub,
    }
}

fn readU16(table: Table, relative: usize) GsubError!u16 {
    if (relative + 2 > table.length) return error.EndOfStream;
    return bin.readU16At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

fn readI16(table: Table, relative: usize) GsubError!i16 {
    if (relative + 2 > table.length) return error.EndOfStream;
    return bin.readI16At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

fn readU32(table: Table, relative: usize) GsubError!u32 {
    if (relative + 4 > table.length) return error.EndOfStream;
    return bin.readU32At(table.data, table.offset + relative) catch |err| switch (err) {
        error.EndOfStream => error.EndOfStream,
    };
}

test "GSUB lookup selection honors script and language tags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 160;
    writeScriptLanguageSelectionTable(&bytes);
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var latin = try selectedLookupIndices(table, allocator, .{ .script_tag = .latn });
    defer latin.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{0}, latin.items);

    var han_default = try selectedLookupIndices(table, allocator, .{ .script_tag = .hani });
    defer han_default.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{1}, han_default.items);

    var han_japanese = try selectedLookupIndices(table, allocator, .{ .script_tag = .hani, .language_tag = .jan });
    defer han_japanese.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{2}, han_japanese.items);

    var fallback = try selectedLookupIndices(table, allocator, .{ .script_tag = .arab });
    defer fallback.deinit(allocator);
    try std.testing.expectEqualSlices(u16, &.{3}, fallback.items);
}

test "GSUB default features do not enable ordinals" {
    try std.testing.expect(defaultFeatureEnabled(unicode.tag("liga")));
    try std.testing.expect(defaultFeatureEnabled(unicode.tag("ccmp")));
    try std.testing.expect(!defaultFeatureEnabled(unicode.tag("ordn")));
    try std.testing.expect(!defaultFeatureEnabled(unicode.tag("sups")));
}

test "GSUB chaining class substitution applies nested lookup" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, 112);
    defer allocator.free(bytes);
    @memset(bytes, 0);

    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 8, 10);
    writeU16Test(bytes, 10, 2);
    writeU16Test(bytes, 12, 6);
    writeU16Test(bytes, 14, 82);

    writeU16Test(bytes, 16, 6);
    writeU16Test(bytes, 20, 1);
    writeU16Test(bytes, 22, 8);

    const chain = 24;
    writeU16Test(bytes, chain + 0, 2);
    writeU16Test(bytes, chain + 2, 38);
    writeU16Test(bytes, chain + 4, 44);
    writeU16Test(bytes, chain + 6, 52);
    writeU16Test(bytes, chain + 8, 60);
    writeU16Test(bytes, chain + 10, 2);
    writeU16Test(bytes, chain + 14, 16);

    const set = chain + 16;
    writeU16Test(bytes, set + 0, 1);
    writeU16Test(bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(bytes, rule + 0, 1);
    writeU16Test(bytes, rule + 2, 1);
    writeU16Test(bytes, rule + 4, 1);
    writeU16Test(bytes, rule + 6, 1);
    writeU16Test(bytes, rule + 8, 1);
    writeU16Test(bytes, rule + 10, 1);
    writeU16Test(bytes, rule + 12, 0);
    writeU16Test(bytes, rule + 14, 1);

    writeCoverage1(bytes, chain + 38, 1);
    writeClassDef1(bytes, chain + 44, 1, 1);
    writeClassDef1(bytes, chain + 52, 1, 1);
    writeClassDef1(bytes, chain + 60, 1, 1);

    writeSingleDeltaLookup(bytes, 92, 1, 2);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
    try applyLookup(.{ .data = bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 1 }, glyphs.items);
}

test "GSUB chaining coverage substitution applies nested lookup" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, 82);
    defer allocator.free(bytes);
    @memset(bytes, 0);

    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 8, 10);
    writeU16Test(bytes, 10, 2);
    writeU16Test(bytes, 12, 6);
    writeU16Test(bytes, 14, 52);

    writeU16Test(bytes, 16, 6);
    writeU16Test(bytes, 20, 1);
    writeU16Test(bytes, 22, 8);

    const chain = 24;
    writeU16Test(bytes, chain + 0, 3);
    writeU16Test(bytes, chain + 2, 1);
    writeU16Test(bytes, chain + 4, 20);
    writeU16Test(bytes, chain + 6, 1);
    writeU16Test(bytes, chain + 8, 26);
    writeU16Test(bytes, chain + 10, 1);
    writeU16Test(bytes, chain + 12, 32);
    writeU16Test(bytes, chain + 14, 1);
    writeU16Test(bytes, chain + 16, 0);
    writeU16Test(bytes, chain + 18, 1);
    writeCoverage1(bytes, chain + 20, 1);
    writeCoverage1(bytes, chain + 26, 1);
    writeCoverage1(bytes, chain + 32, 1);

    writeSingleDeltaLookup(bytes, 62, 1, 2);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
    try applyLookup(.{ .data = bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{});

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 1 }, glyphs.items);
}

test "GSUB context substitution skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 18, 0x0008);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);

    writeCoverage1(&bytes, context + 22, 1);
    writeSingleDeltaLookup(&bytes, 52, 2, 10);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 3, 2 });

    const glyph_classes = [_]u16{ 0, 0, 0, 3 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{ 1, 3, 12 }, glyphs.items);
}

test "GSUB extension substitution preserves wrapper lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 28;

    writeU16Test(&bytes, 0, 7);
    writeU16Test(&bytes, 2, 0x0008);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const extension = 8;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    writeU32Test(&bytes, extension + 4, 8);

    const single = extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 6);
    writeI16Test(&bytes, single + 4, 1);
    writeCoverage1(&bytes, single + 6, 3);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 3);

    const glyph_classes = [_]u16{ 0, 1, 2, 3 };
    try applyLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{3}, glyphs.items);
}

fn writeSingleDeltaLookup(bytes: []u8, lookup_offset: usize, glyph: GlyphId, delta: i16) void {
    writeU16Test(bytes, lookup_offset + 0, 1);
    writeU16Test(bytes, lookup_offset + 4, 1);
    writeU16Test(bytes, lookup_offset + 6, 8);
    const subtable = lookup_offset + 8;
    writeU16Test(bytes, subtable + 0, 1);
    writeU16Test(bytes, subtable + 2, 6);
    writeI16Test(bytes, subtable + 4, delta);
    writeCoverage1(bytes, subtable + 6, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, glyph);
}

fn writeClassDef1(bytes: []u8, offset: usize, start: GlyphId, class: u16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, start);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, class);
}

fn writeScriptLanguageSelectionTable(bytes: []u8) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 90);
    writeU16Test(bytes, 8, 142);

    writeU16Test(bytes, 10, 3);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 20);
    writeU32Test(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.latn));
    writeU16Test(bytes, 22, 32);
    writeU32Test(bytes, 24, @intFromEnum(unicode.OpenTypeScriptTag.hani));
    writeU16Test(bytes, 28, 44);

    writeScriptTable(bytes, 30, 4, 0);
    writeLangSys(bytes, 34, 3);
    writeScriptTable(bytes, 42, 4, 0);
    writeLangSys(bytes, 46, 0);
    writeU16Test(bytes, 54, 10);
    writeU16Test(bytes, 56, 1);
    writeU32Test(bytes, 58, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16Test(bytes, 62, 18);
    writeLangSys(bytes, 64, 1);
    writeLangSys(bytes, 72, 2);

    writeU16Test(bytes, 90, 4);
    writeFeatureRecord(bytes, 92, unicode.tag("liga"), 26);
    writeFeatureRecord(bytes, 98, unicode.tag("ccmp"), 32);
    writeFeatureRecord(bytes, 104, unicode.tag("rlig"), 38);
    writeFeatureRecord(bytes, 110, unicode.tag("rclt"), 44);
    writeFeature(bytes, 116, 0);
    writeFeature(bytes, 122, 1);
    writeFeature(bytes, 128, 2);
    writeFeature(bytes, 134, 3);

    writeU16Test(bytes, 142, 4);
    writeU16Test(bytes, 144, 8);
    writeU16Test(bytes, 146, 8);
    writeU16Test(bytes, 148, 8);
    writeU16Test(bytes, 150, 8);
}

fn writeScriptTable(bytes: []u8, offset: usize, default_lang_offset: u16, lang_count: u16) void {
    writeU16Test(bytes, offset, default_lang_offset);
    writeU16Test(bytes, offset + 2, lang_count);
}

fn writeLangSys(bytes: []u8, offset: usize, feature_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 0xffff);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, feature_index);
}

fn writeFeatureRecord(bytes: []u8, offset: usize, tag_value: u32, feature_offset: u16) void {
    writeU32Test(bytes, offset, tag_value);
    writeU16Test(bytes, offset + 4, feature_offset);
}

fn writeFeature(bytes: []u8, offset: usize, lookup_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, lookup_index);
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    writeU16Test(bytes, offset, @bitCast(value));
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
