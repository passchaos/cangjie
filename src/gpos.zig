const std = @import("std");
const bin = @import("binary.zig");
const GlyphId = @import("glyph.zig").GlyphId;
const unicode = @import("unicode.zig");

pub const max_ligature_components = 64;

pub const LigatureComponentInfo = struct {
    /// Source-order positions for the logical components that produced this
    /// ligature glyph. Non-ligature glyphs may leave component_count at 1.
    component_count: u8 = 1,
    component_sources: [max_ligature_components]usize = [_]usize{0} ** max_ligature_components,
};

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

const FeatureSelection = struct {
    index: u16,
    required: bool = false,
};

pub const LookupOptions = struct {
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    features: []const unicode.FeatureOverride = &.{},
    apply_all_if_unselected: bool = true,
    glyph_classes: ?[]const u16 = null,
    mark_attach_classes: ?[]const u16 = null,
    mark_filtering_sets: ?[]const []const GlyphId = null,
    active_mark_filtering_set: ?u16 = null,
    /// Optional source-order index per shaped glyph. MarkLigPos uses this with
    /// `ligature_components` to attach marks to the logical component whose
    /// source position most closely precedes the mark. Without this metadata,
    /// the parser falls back to a conservative positional heuristic.
    glyph_source_indices: ?[]const usize = null,
    /// Optional ligature component metadata parallel to the post-GSUB glyph
    /// stream. Entries are only meaningful for ligature glyph positions.
    ligature_components: ?[]const LigatureComponentInfo = null,
};

const max_context_preflight_depth = 16;

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
    const script_list_offset = try readU16(table, 4);
    const feature_list_offset = try readU16(table, 6);
    const has_feature_topology = script_list_offset != 0 and
        feature_list_offset != 0 and
        try readU16(table, script_list_offset) != 0 and
        try readU16(table, feature_list_offset) != 0;
    // As with GSUB, an empty active-feature selection means no lookup applies
    // for this Script/LangSys. Executing the full lookup list would leak
    // optional or unrelated-script positioning into the run. Low-level callers
    // can opt into the historical all-lookup fallback.
    if (selected_lookups.items.len == 0 and
        (options.features.len != 0 or (!options.apply_all_if_unselected and has_feature_topology))) return;

    const lookup_list_offset = try readU16(table, 8);
    const lookup_count = try readU16(table, lookup_list_offset);
    for (0..lookup_count) |i| {
        if (selected_lookups.items.len != 0 and !containsLookup(selected_lookups.items, @intCast(i))) continue;
        const lookup_offset = try readU16(table, lookup_list_offset + 2 + i * 2);
        try collectLookup(table, lookup_list_offset + lookup_offset, glyphs, adjustments, allocator, options);
    }
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var feature_indices = std.ArrayList(FeatureSelection).empty;
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
    for (feature_indices.items) |selection| {
        const feature_index = selection.index;
        if (feature_index >= feature_count) continue;
        const feature_record = feature_list_offset + 2 + @as(usize, feature_index) * 6;
        const feature_tag = try readU32(table, feature_record);
        // LangSys.ReqFeatureIndex is mandatory for the active language system.
        // Feature overrides model user-controllable optional/default features;
        // they must not suppress required positioning lookups.
        if (!selection.required and !featureEnabled(feature_tag, options.features)) continue;
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

fn collectScriptFeatures(table: Table, script_offset: usize, language_tag: unicode.OpenTypeLanguageTag, feature_indices: *std.ArrayList(FeatureSelection), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
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

fn collectLangSysFeatures(table: Table, lang_sys_offset: usize, feature_indices: *std.ArrayList(FeatureSelection), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    const required_feature_index = try readU16(table, lang_sys_offset + 2);
    if (required_feature_index != 0xffff) {
        try appendFeatureSelection(feature_indices, allocator, required_feature_index, true);
    }
    const feature_count = try readU16(table, lang_sys_offset + 4);
    for (0..feature_count) |i| {
        const feature_index = try readU16(table, lang_sys_offset + 6 + i * 2);
        try appendFeatureSelection(feature_indices, allocator, feature_index, false);
    }
}

fn appendFeatureSelection(feature_indices: *std.ArrayList(FeatureSelection), allocator: std.mem.Allocator, index: u16, required: bool) std.mem.Allocator.Error!void {
    for (feature_indices.items) |*selection| {
        if (selection.index != index) continue;
        selection.required = selection.required or required;
        return;
    }
    try feature_indices.append(allocator, .{ .index = index, .required = required });
}

fn containsLookup(items: []const u16, needle: u16) bool {
    for (items) |item| {
        if (item == needle) return true;
    }
    return false;
}

fn collectLookup(table: Table, lookup_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    try ensurePositionLookupHeaderWithin(table, lookup_offset);
    const lookup_type = try readU16(table, lookup_offset);
    const lookup_flag = try readU16(table, lookup_offset + 2);
    const subtable_count = try readU16(table, lookup_offset + 4);
    // Positioning results are appended incrementally, but OpenType lookups are
    // atomic units. Preflight supported direct subtables before collecting any
    // adjustment so malformed later subtables cannot leave partial positioning.
    try ensurePositionLookupSubtablesWithin(table, lookup_offset, lookup_type, subtable_count);
    var lookup_options = options;
    if ((lookup_flag & 0x0010) != 0) {
        // UseMarkFilteringSet stores its set index after the variable-length
        // SubTable offset array. The high byte remains reserved for the older
        // MarkAttachmentType mechanism when bit 4 is clear.
        lookup_options.active_mark_filtering_set = try readU16(table, lookup_offset + 6 + @as(usize, subtable_count) * 2);
    }
    if (lookup_type == 1) {
        try collectSingleAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 2) {
        try collectPairAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
        return;
    }
    if (lookup_type == 9) {
        // ExtensionPos only widens offsets, but a lookup still applies as an
        // all-or-nothing unit. Preflight wrapped variable-length arrays before
        // collecting any adjustments so a later malformed wrapper cannot leave
        // earlier wrapper results visible to the caller.
        try ensureExtensionPositionLookupPayloadsWithin(table, lookup_offset, subtable_count);
        if (try extensionPositionLookupType(table, lookup_offset, subtable_count)) |wrapped_type| {
            switch (wrapped_type) {
                1 => {
                    try collectExtensionSingleAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
                    return;
                },
                2 => {
                    try collectExtensionPairAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
                    return;
                },
                else => {},
            }
        }
        try collectExtensionAdjustmentLookup(table, lookup_offset, subtable_count, glyphs, adjustments, allocator, lookup_flag, lookup_options);
        return;
    }
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => {}, // SinglePos needs whole-lookup subtable ordering; handled above.
            2 => {}, // PairPos needs whole-lookup subtable ordering; handled above.
            3 => try collectCursiveAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            4 => try collectMarkToBaseAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            5 => try collectMarkToLigatureAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            6 => try collectMarkToMarkAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            7 => try collectContextAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            8 => try collectChainingContextAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            9 => try collectExtensionAdjustment(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, lookup_options),
            else => {},
        }
    }
}

fn extensionPositionLookupType(table: Table, lookup_offset: usize, subtable_count: u16) GposError!?u16 {
    // ExtensionPos is an addressing wrapper. When one lookup contains only
    // ExtensionPos subtables around the same order-sensitive type, we can keep
    // direct lookup semantics instead of delegating each wrapper over the whole
    // glyph run independently. Mixed wrapped types intentionally fall back to
    // generic per-subtable collection because their interactions are not simple
    // alternatives for one positioning kind.
    var common_type: ?u16 = null;
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        if (try readU16(table, subtable_offset) != 1) return null;
        const wrapped_type = try readU16(table, subtable_offset + 2);
        if (wrapped_type == 9) return error.UnsupportedGpos;
        if (common_type) |existing| {
            if (existing != wrapped_type) return null;
        } else {
            common_type = wrapped_type;
        }
    }
    return common_type;
}

fn extensionPositionSubtablePayload(table: Table, subtable_offset: usize, expected_lookup_type: u16) GposError!usize {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    if (extension_lookup_type != expected_lookup_type) return error.UnsupportedGpos;
    return subtable_offset + try readU32(table, subtable_offset + 4);
}

fn collectExtensionSingleAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // Preserve SinglePos lookup ordering through ExtensionPos. Without a
    // lookup-level matched set, overlapping wrapped subtables would stack their
    // deltas even though OpenType treats subtables in one lookup as ordered
    // alternatives for each original glyph position.
    if (glyphs.len == 0) return;
    const matched = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(matched);
    @memset(matched, false);

    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const extension_subtable = try extensionPositionSubtablePayload(table, subtable_offset, 1);
        try collectSingleAdjustmentSubtable(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options, matched);
    }
}

fn collectExtensionPairAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // PairPos has the same lookup-subtable alternative rule under ExtensionPos
    // as it does directly: the first matching wrapped PairPos handles the pair.
    if (glyphs.len < 2) return;
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) : (first_index += 1) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            const extension_subtable = try extensionPositionSubtablePayload(table, subtable_offset, 2);
            if (try collectPairAdjustmentAt(table, extension_subtable, glyphs, first_index, adjustments, allocator, lookup_flag, options)) break;
        }
    }
}

fn collectExtensionAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // Mixed ExtensionPos lookups are uncommon, but preserving ordering for each
    // wrapped positioning kind still matters. In particular, two wrapped
    // PairPos subtables remain alternatives for the same first glyph even when
    // another wrapped type prevents the homogeneous fast path above.
    const single_matched = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(single_matched);
    @memset(single_matched, false);

    const pair_matched = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(pair_matched);
    @memset(pair_matched, false);

    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        const pos_format = try readU16(table, subtable_offset);
        if (pos_format != 1) return error.UnsupportedGpos;
        const extension_lookup_type = try readU16(table, subtable_offset + 2);
        if (extension_lookup_type == 9) return error.UnsupportedGpos;
        const extension_subtable = subtable_offset + try readU32(table, subtable_offset + 4);

        switch (extension_lookup_type) {
            1 => try collectSingleAdjustmentSubtable(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options, single_matched),
            2 => {
                if (glyphs.len < 2) continue;
                var first_index: usize = 0;
                while (first_index + 1 < glyphs.len) : (first_index += 1) {
                    if (pair_matched[first_index]) continue;
                    if (try collectPairAdjustmentAt(table, extension_subtable, glyphs, first_index, adjustments, allocator, lookup_flag, options)) {
                        pair_matched[first_index] = true;
                    }
                }
            },
            3 => try collectCursiveAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            4 => try collectMarkToBaseAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            5 => try collectMarkToLigatureAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            6 => try collectMarkToMarkAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            7 => try collectContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            8 => try collectChainingContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
            else => {},
        }
    }
}

fn collectPairAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // PairPos subtables within one lookup are ordered alternatives for a
    // position. Once a subtable handles a pair, later subtables in the same
    // lookup must not add more deltas for that same first glyph; otherwise
    // split pair data cascades instead of following OpenType lookup ordering.
    if (glyphs.len < 2) return;
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) : (first_index += 1) {
        for (0..subtable_count) |subtable_i| {
            const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
            if (try collectPairAdjustmentAt(table, subtable_offset, glyphs, first_index, adjustments, allocator, lookup_flag, options)) break;
        }
    }
}

fn collectSingleAdjustmentLookup(table: Table, lookup_offset: usize, subtable_count: u16, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    // Lookup subtables are tried in order as alternatives for each glyph. Track
    // which input positions have already matched so overlapping SinglePos
    // subtables do not accumulate deltas in the same lookup.
    if (glyphs.len == 0) return;
    const matched = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(matched);
    @memset(matched, false);

    for (0..subtable_count) |subtable_i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + subtable_i * 2);
        try collectSingleAdjustmentSubtable(table, subtable_offset, glyphs, adjustments, allocator, lookup_flag, options, matched);
    }
}

fn collectSingleAdjustmentSubtable(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, matched: []bool) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const value_format = try readU16(table, subtable_offset + 4);
    switch (pos_format) {
        1 => {
            const value = try readValueRecord(table, subtable_offset + 6, value_format);
            for (glyphs, 0..) |glyph, i| {
                if (matched[i]) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph) != null) {
                    try appendAdjustment(adjustments, allocator, i, value, false);
                    matched[i] = true;
                }
            }
        },
        2 => {
            const value_count = try readU16(table, subtable_offset + 6);
            const value_size = valueRecordSize(value_format);
            for (glyphs, 0..) |glyph, i| {
                if (matched[i]) continue;
                if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
                if (try coverageIndex(table, coverage_offset, glyph)) |coverage| {
                    if (coverage < value_count) {
                        const value = try readValueRecord(table, subtable_offset + 8 + coverage * value_size, value_format);
                        try appendAdjustment(adjustments, allocator, i, value, false);
                        matched[i] = true;
                    }
                }
            }
        },
        else => return error.UnsupportedGpos,
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
    const classes = options.glyph_classes;
    const class = if (classes) |items| if (glyph < items.len) items[glyph] else 0 else 0;

    // UseMarkFilteringSet appends a set index after the SubTable offsets; it
    // does not consume the high-byte MarkAttachmentType bits. Apply both mark
    // filters independently so a lookup can require a selected mark set and a
    // selected GDEF mark attachment class at the same time.
    if ((lookup_flag & 0x0010) != 0) {
        const mark_filtering_set_index = options.active_mark_filtering_set orelse return class == 3;
        const mark_sets = options.mark_filtering_sets orelse return class == 3;
        if (mark_filtering_set_index >= mark_sets.len) return class == 3;
        const in_selected_set = glyphInMarkFilteringSet(mark_sets[mark_filtering_set_index], glyph);
        const is_mark = class == 3 or glyphInAnyMarkFilteringSet(mark_sets, glyph);
        if (is_mark and !in_selected_set) return true;
    }

    if (classes != null) {
        if ((lookup_flag & 0x0002) != 0 and class == 1) return true;
        if ((lookup_flag & 0x0004) != 0 and class == 2) return true;
        if ((lookup_flag & 0x0008) != 0 and class == 3) return true;
    }
    const mark_attachment_type = lookup_flag >> 8;
    if (mark_attachment_type != 0) {
        const attach_classes = options.mark_attach_classes orelse return class == 3;
        if (glyph >= attach_classes.len) return class == 3;
        const attach_class = attach_classes[glyph];
        // MarkAttachClassDef is mark-only data. Some fonts provide it without a
        // useful GlyphClassDef; treat non-zero attachment classes as marks for
        // MarkAttachmentType filtering while still letting an explicit mark
        // glyph class cover attachment class zero.
        const is_mark = class == 3 or (class == 0 and attach_class != 0);
        if (!is_mark) return false;
        return attach_class != mark_attachment_type;
    }
    return false;
}

fn glyphInAnyMarkFilteringSet(mark_sets: []const []const GlyphId, glyph: GlyphId) bool {
    for (mark_sets) |set| {
        if (glyphInMarkFilteringSet(set, glyph)) return true;
    }
    return false;
}

fn glyphInMarkFilteringSet(glyphs: []const GlyphId, glyph: GlyphId) bool {
    for (glyphs) |candidate| {
        if (candidate == glyph) return true;
    }
    return false;
}

fn collectExtensionAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    const extension_offset = try readU32(table, subtable_offset + 4);
    const extension_subtable = subtable_offset + extension_offset;
    // The extension wrapper extends addressing only; LookupFlag still belongs
    // to the outer lookup and must filter glyph classes in the delegated body.
    switch (extension_lookup_type) {
        1 => try collectSingleAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        2 => try collectPairAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        3 => try collectCursiveAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        4 => try collectMarkToBaseAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        5 => try collectMarkToLigatureAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        6 => try collectMarkToMarkAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        7 => try collectContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        8 => try collectChainingContextAdjustment(table, extension_subtable, glyphs, adjustments, allocator, lookup_flag, options),
        else => {},
    }
}

fn collectPairAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;
    var i: usize = 0;
    while (i + 1 < glyphs.len) : (i += 1) {
        _ = try collectPairAdjustmentAt(table, subtable_offset, glyphs, i, adjustments, allocator, lookup_flag, options);
    }
}

fn collectPairAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, first_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual positioning can invoke a PairPos lookup at a specific matched
    // sequence index. Keep the pair matcher index-addressable so top-level
    // PairPos and nested PosLookupRecord application share the same semantics,
    // including transparent lookup-flag ignored glyphs between the pair.
    if (first_index + 1 >= glyphs.len) return false;
    if (lookupIgnoresGlyph(lookup_flag, options, glyphs[first_index])) return false;
    const second_index = nextUnignoredGlyph(glyphs, first_index + 1, lookup_flag, options) orelse return false;

    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const value_format_1 = try readU16(table, subtable_offset + 4);
    const value_format_2 = try readU16(table, subtable_offset + 6);
    const value_size_1 = valueRecordSize(value_format_1);
    const value_size_2 = valueRecordSize(value_format_2);

    switch (pos_format) {
        1 => {
            // PairPos format 1 is a sparse list keyed by the first glyph's
            // coverage index, then searched by the second glyph.
            const pair_set_count = try readU16(table, subtable_offset + 8);
            const coverage = try coverageIndex(table, coverage_offset, glyphs[first_index]) orelse return false;
            if (coverage >= pair_set_count) return false;
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
                    try appendAdjustment(adjustments, allocator, first_index, value_1, true);
                    try appendAdjustment(adjustments, allocator, second_index, value_2, false);
                    return true;
                }
            }
            return false;
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
            if (try coverageIndex(table, coverage_offset, glyphs[first_index]) == null) return false;
            const class_1 = try classValue(table, class_def_1, glyphs[first_index]);
            const class_2 = try classValue(table, class_def_2, glyphs[second_index]);
            if (class_1 >= class_1_count or class_2 >= class_2_count) return false;
            const record_offset = matrix_offset + (@as(usize, class_1) * class_2_count + class_2) * record_size;
            const value_1 = try readValueRecord(table, record_offset, value_format_1);
            const value_2 = try readValueRecord(table, record_offset + value_size_1, value_format_2);
            try appendAdjustment(adjustments, allocator, first_index, value_1, true);
            try appendAdjustment(adjustments, allocator, second_index, value_2, false);
            return true;
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
    const has_delta = value.x_advance != 0 or value.x_placement != 0 or value.y_placement != 0 or value.y_advance != 0;
    // PairPos is also a precedence signal for higher-level shaping: when a
    // GPOS pair matches, legacy 'kern' must not be applied to that same pair
    // even if the first ValueRecord is empty and all numeric deltas live on the
    // second glyph. Keep a zero-valued record when metadata carries that fact.
    if (!has_delta and !flags.pair_positioned and !flags.mark_attachment) return;
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

fn collectCursiveAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const entry_exit_count = try readU16(table, subtable_offset + 4);
    if (glyphs.len < 2) return;

    var previous_covered_position: ?usize = null;
    var previous_coverage_index: usize = 0;
    for (glyphs, 0..) |glyph, i| {
        if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
        const current_index = try coverageIndex(table, coverage_offset, glyph) orelse {
            // A non-ignored, non-covered glyph breaks cursive adjacency. Ignored
            // glyphs are skipped above, matching OpenType LookupFlag semantics.
            previous_covered_position = null;
            continue;
        };
        if (current_index >= entry_exit_count) {
            previous_covered_position = null;
            continue;
        }

        if (previous_covered_position) |_| {
            const current_record = subtable_offset + 6 + current_index * 4;
            const previous_record = subtable_offset + 6 + previous_coverage_index * 4;
            const entry_relative = try readU16(table, current_record);
            const exit_relative = try readU16(table, previous_record + 2);
            if (entry_relative != 0 and exit_relative != 0) {
                // Position the current glyph so its entry anchor lands on the
                // previous non-ignored covered glyph's exit anchor.
                const entry = try readAnchor(table, subtable_offset + entry_relative);
                const exit = try readAnchor(table, subtable_offset + exit_relative);
                try appendAdjustment(adjustments, allocator, i, .{
                    .index = i,
                    .x_placement = exit.x - entry.x,
                    .y_placement = exit.y - entry.y,
                }, false);
            }
        }
        previous_covered_position = i;
        previous_coverage_index = current_index;
    }
}

fn collectCursiveAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, target_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecords target exactly one matched input glyph.
    // CursivePos still needs the preceding participating glyph from the real
    // run, but a nested context lookup must not rescan and position every
    // covered cursive join in the run.
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    if (target_index >= glyphs.len) return false;
    const glyph = glyphs[target_index];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const entry_exit_count = try readU16(table, subtable_offset + 4);
    const current_index = try coverageIndex(table, coverage_offset, glyph) orelse return false;
    if (current_index >= entry_exit_count) return false;
    const previous_position = try previousCoveredCursiveGlyph(table, coverage_offset, glyphs, target_index, entry_exit_count, lookup_flag, options) orelse return false;
    const previous_index = (try coverageIndex(table, coverage_offset, glyphs[previous_position])) orelse return false;

    const current_record = subtable_offset + 6 + current_index * 4;
    const previous_record = subtable_offset + 6 + previous_index * 4;
    const entry_relative = try readU16(table, current_record);
    const exit_relative = try readU16(table, previous_record + 2);
    if (entry_relative == 0 or exit_relative == 0) return false;

    const entry = try readAnchor(table, subtable_offset + entry_relative);
    const exit = try readAnchor(table, subtable_offset + exit_relative);
    try appendAdjustment(adjustments, allocator, target_index, .{
        .index = target_index,
        .x_placement = exit.x - entry.x,
        .y_placement = exit.y - entry.y,
    }, false);
    return true;
}

fn previousCoveredCursiveGlyph(table: Table, coverage_offset: usize, glyphs: []const GlyphId, target_index: usize, entry_exit_count: usize, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = target_index;
    while (i > 0) {
        i -= 1;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) continue;
        const coverage = try coverageIndex(table, coverage_offset, glyphs[i]) orelse return null;
        return if (coverage < entry_exit_count) i else null;
    }
    return null;
}

fn collectMarkToBaseAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const class_count = try readU16(table, subtable_offset + 6);
    if (class_count == 0 or glyphs.len < 2) return;

    const attached_marks = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(attached_marks);
    @memset(attached_marks, false);

    for (glyphs, 0..) |glyph, i| {
        if (lookupIgnoresGlyph(lookup_flag, options, glyph)) continue;
        if (try collectMarkToBaseAdjustmentAt(table, subtable_offset, glyphs, i, adjustments, allocator, lookup_flag, options, attached_marks)) {
            attached_marks[i] = true;
        }
    }
}

fn collectMarkToBaseAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, mark_position: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions, attached_marks: []const bool) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecord application names one glyph in the matched
    // input sequence. MarkBasePos still needs the surrounding run to find the
    // preceding base, but it must attach only that named mark instead of
    // rescanning and positioning every mark covered by the nested lookup.
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    if (mark_position >= glyphs.len) return false;
    const glyph = glyphs[mark_position];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const mark_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const base_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_array_offset = subtable_offset + try readU16(table, subtable_offset + 8);
    const base_array_offset = subtable_offset + try readU16(table, subtable_offset + 10);
    if (class_count == 0 or glyphs.len < 2) return false;

    const mark_index = try coverageIndex(table, mark_coverage_offset, glyph) orelse return false;
    const base_position = try previousCoveredBaseGlyph(table, mark_coverage_offset, base_coverage_offset, glyphs, mark_position, attached_marks, lookup_flag, options) orelse return false;
    const base_index = try coverageIndex(table, base_coverage_offset, glyphs[base_position]) orelse return false;
    const mark_record_offset = mark_array_offset + 2 + mark_index * 4;
    const mark_class = try readU16(table, mark_record_offset);
    if (mark_class >= class_count) return false;
    const mark_anchor_offset = mark_array_offset + try readU16(table, mark_record_offset + 2);
    const base_anchor_record = base_array_offset + 2 + (base_index * class_count + mark_class) * 2;
    const base_anchor_relative = try readU16(table, base_anchor_record);
    if (base_anchor_relative == 0) return false;
    const base_anchor_offset = base_array_offset + base_anchor_relative;
    const mark_anchor = try readAnchor(table, mark_anchor_offset);
    const base_anchor = try readAnchor(table, base_anchor_offset);
    try appendAdjustmentEx(adjustments, allocator, mark_position, .{
        .index = mark_position,
        .x_placement = base_anchor.x - mark_anchor.x,
        .y_placement = base_anchor.y - mark_anchor.y,
    }, .{ .mark_attachment = true, .mark_base_index = base_position });
    return true;
}

fn previousCoveredBaseGlyph(table: Table, mark_coverage_offset: usize, base_coverage_offset: usize, glyphs: []const GlyphId, mark_index: usize, attached_marks: []const bool, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = mark_index;
    while (i > 0) {
        i -= 1;
        if (i < attached_marks.len and attached_marks[i]) continue;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) continue;
        if (try coverageIndex(table, base_coverage_offset, glyphs[i]) != null) return i;

        // MarkBasePos attaches to the nearest previous participating base. A
        // non-mark glyph that is not in BaseCoverage is a real blocker; walking
        // past it would incorrectly attach the mark to an older base across an
        // intervening base/ligature. Marks remain transparent for stacked-mark
        // clusters; use GDEF classes when present and fall back to this
        // subtable's MarkCoverage for minimal fonts that omit GDEF.
        const class_is_mark = if (options.glyph_classes) |classes|
            glyphs[i] < classes.len and classes[glyphs[i]] == 3
        else
            false;
        if (!class_is_mark and try coverageIndex(table, mark_coverage_offset, glyphs[i]) == null) return null;
    }
    return null;
}

fn previousUnignoredCoveredGlyph(table: Table, coverage_offset: usize, glyphs: []const GlyphId, mark_index: usize, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = mark_index;
    while (i > 0) {
        i -= 1;
        // Mark attachment lookups test the previous glyph after applying the
        // lookup flag. Ignored glyphs are transparent for this adjacency check;
        // the first non-ignored glyph either matches the target coverage or
        // blocks the attachment.
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) continue;
        return if (try coverageIndex(table, coverage_offset, glyphs[i]) != null) i else null;
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
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator, options);
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
        try collectPositionRecordsMapped(table, cursor, pos_count, input_indices_buf[0..input_count], glyphs, adjustments, allocator, options);
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
        try collectPositionRecordsMapped(table, cursor, pos_count, input_indices_buf[0..input_count], glyphs, adjustments, allocator, options);
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
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..input_count], glyphs, adjustments, allocator, options);
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
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator, options);
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
        try collectPositionRecordsMapped(table, records_pos, pos_count, input_indices_buf[0..glyph_count], glyphs, adjustments, allocator, options);
        return true;
    }
    return false;
}

fn collectPositionRecordsMapped(table: Table, records_pos: usize, record_count: usize, input_indices: []const usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    try ensurePositionRecordListWithin(table, records_pos, record_count);
    try ensurePositionRecordLookupsWithin(table, records_pos, record_count);

    // Context positioning records name a glyph in the matched input sequence
    // and a lookup-list index. Nested lookups own their own LookupFlag, so a
    // mark/base/ligature ignored by that nested flag must not receive deltas.
    for (0..record_count) |record_i| {
        const record_offset = records_pos + record_i * 4;
        const sequence_index = try readU16(table, record_offset);
        const lookup_index = try readU16(table, record_offset + 2);
        if (sequence_index >= input_indices.len) continue;
        const target_index = input_indices[sequence_index];
        try collectNestedAdjustment(table, glyphs, target_index, lookup_index, adjustments, allocator, options);
    }
}

fn ensurePositionRecordListWithin(table: Table, records_pos: usize, record_count: usize) GposError!void {
    // PosLookupRecord arrays are an all-or-nothing part of a contextual match:
    // detect truncation before appending any nested adjustment so a malformed
    // table cannot expose a partly-applied positioning result to the caller.
    if (records_pos > table.length) return error.BadGpos;
    if (record_count > (table.length - records_pos) / 4) return error.BadGpos;
}

fn ensurePositionRecordLookupsWithin(table: Table, records_pos: usize, record_count: usize) GposError!void {
    return ensurePositionRecordLookupsWithinDepth(table, records_pos, record_count, 0);
}

fn ensurePositionRecordLookupsWithinDepth(table: Table, records_pos: usize, record_count: usize, depth: usize) GposError!void {
    // Contextual positioning appends adjustments as it walks PosLookupRecords.
    // Preflight referenced lookup headers so a malformed later lookup count or
    // UseMarkFilteringSet slot cannot leave earlier nested adjustments visible.
    // Contextual lookups are allowed to reference other contextual lookups; cap
    // validation recursion so cyclic lookup graphs are reported as unsupported
    // instead of overflowing the validator stack.
    if (depth > max_context_preflight_depth) return error.UnsupportedGpos;
    const lookup_list_offset = try readU16BadGpos(table, 8);
    const lookup_count = try readU16BadGpos(table, lookup_list_offset);
    for (0..record_count) |record_i| {
        const record_offset = records_pos + record_i * 4;
        const lookup_index = try readU16BadGpos(table, record_offset + 2);
        if (lookup_index >= lookup_count) continue;
        const lookup_offset_pos = lookup_list_offset + 2 + @as(usize, lookup_index) * 2;
        const lookup_offset = lookup_list_offset + try readU16BadGpos(table, lookup_offset_pos);
        try ensurePositionLookupHeaderWithin(table, lookup_offset);
        const lookup_type = try readU16BadGpos(table, lookup_offset);
        const subtable_count = try readU16BadGpos(table, lookup_offset + 4);
        try ensurePositionLookupSubtablesWithinDepth(table, lookup_offset, lookup_type, subtable_count, depth + 1);
    }
}

fn ensurePositionLookupHeaderWithin(table: Table, lookup_offset: usize) GposError!void {
    if (lookup_offset > table.length or table.length - lookup_offset < 6) return error.BadGpos;
    const lookup_type = try readU16BadGpos(table, lookup_offset);
    const lookup_flag = try readU16BadGpos(table, lookup_offset + 2);
    const subtable_count = try readU16BadGpos(table, lookup_offset + 4);
    const subtable_offsets_pos = lookup_offset + 6;
    const subtable_offsets_len = @as(usize, subtable_count) * 2;
    if (subtable_offsets_pos > table.length or subtable_offsets_len > table.length - subtable_offsets_pos) return error.BadGpos;
    if ((lookup_flag & 0x0010) != 0) {
        const mark_filtering_set_pos = subtable_offsets_pos + subtable_offsets_len;
        if (mark_filtering_set_pos > table.length or table.length - mark_filtering_set_pos < 2) return error.BadGpos;
    }
    if (lookup_type == 9) {
        try ensureExtensionPositionLookupPayloadsWithin(table, lookup_offset, subtable_count);
    }
}

fn ensurePositionLookupSubtablesWithin(table: Table, lookup_offset: usize, lookup_type: u16, subtable_count: u16) GposError!void {
    return ensurePositionLookupSubtablesWithinDepth(table, lookup_offset, lookup_type, subtable_count, 0);
}

fn ensurePositionLookupSubtablesWithinDepth(table: Table, lookup_offset: usize, lookup_type: u16, subtable_count: u16, depth: usize) GposError!void {
    switch (lookup_type) {
        1, 2, 3, 4, 5, 6, 7, 8 => {},
        else => return,
    }
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = try checkedPositionOffset(table, lookup_offset, try readU16BadGpos(table, lookup_offset + 6 + subtable_i * 2));
        try ensurePositionSubtableFixedHeaderWithin(table, subtable_offset, lookup_type);
        try ensurePositionSubtableVariableDataWithinDepth(table, subtable_offset, lookup_type, depth);
    }
}

fn ensureExtensionPositionLookupPayloadsWithin(table: Table, lookup_offset: usize, subtable_count: u16) GposError!void {
    for (0..subtable_count) |subtable_i| {
        const subtable_offset = try checkedPositionOffset(table, lookup_offset, try readU16BadGpos(table, lookup_offset + 6 + subtable_i * 2));
        try ensureExtensionPositionPayloadWithin(table, subtable_offset);
    }
}

fn ensureExtensionPositionPayloadWithin(table: Table, subtable_offset: usize) GposError!void {
    // PosLookupRecords are applied eagerly. If a later record references a
    // malformed ExtensionPos wrapper, reject the entire contextual match before
    // earlier records can append partial adjustments.
    if (subtable_offset > table.length or table.length - subtable_offset < 8) return error.BadGpos;
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16BadGpos(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    const extension_subtable = try checkedPositionOffset(table, subtable_offset, try readU32BadGpos(table, subtable_offset + 4));
    try ensurePositionSubtableFixedHeaderWithin(table, extension_subtable, extension_lookup_type);
    try ensurePositionSubtableVariableDataWithin(table, extension_subtable, extension_lookup_type);
}

fn ensurePositionSubtableFixedHeaderWithin(table: Table, subtable_offset: usize, lookup_type: u16) GposError!void {
    if (subtable_offset > table.length or table.length - subtable_offset < 2) return error.BadGpos;
    const pos_format = try readU16BadGpos(table, subtable_offset);
    const min_len: usize = switch (lookup_type) {
        1 => 6,
        2 => 8,
        3 => 6,
        4, 5, 6 => 12,
        7 => switch (pos_format) {
            1, 3 => 6,
            2 => 8,
            else => return error.UnsupportedGpos,
        },
        8 => switch (pos_format) {
            1 => 6,
            2 => 12,
            3 => 4,
            else => return error.UnsupportedGpos,
        },
        else => return,
    };
    if (table.length - subtable_offset < min_len) return error.BadGpos;
}

fn ensurePositionSubtableVariableDataWithin(table: Table, subtable_offset: usize, lookup_type: u16) GposError!void {
    return ensurePositionSubtableVariableDataWithinDepth(table, subtable_offset, lookup_type, 0);
}

fn ensurePositionSubtableVariableDataWithinDepth(table: Table, subtable_offset: usize, lookup_type: u16, depth: usize) GposError!void {
    switch (lookup_type) {
        1 => try ensureSinglePositionSubtableWithin(table, subtable_offset),
        2 => try ensurePairPositionSubtableWithin(table, subtable_offset),
        3 => try ensureCursivePositionSubtableWithin(table, subtable_offset),
        4 => try ensureMarkToBasePositionSubtableWithin(table, subtable_offset),
        5 => try ensureMarkToLigaturePositionSubtableWithin(table, subtable_offset),
        6 => try ensureMarkToMarkPositionSubtableWithin(table, subtable_offset),
        7 => try ensureContextPositionSubtableWithin(table, subtable_offset, depth),
        8 => try ensureChainingContextPositionSubtableWithin(table, subtable_offset, depth),
        else => {},
    }
}

fn ensureSinglePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    const coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const value_format = try readU16BadGpos(table, subtable_offset + 4);
    switch (pos_format) {
        1 => try ensureValueRecordWithin(table, subtable_offset + 6, value_format),
        2 => {
            const value_count = try readU16BadGpos(table, subtable_offset + 6);
            try ensureBytesWithin(table, subtable_offset + 8, @as(usize, value_count) * valueRecordSize(value_format));
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensurePairPositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    const coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    try ensureCoverageTableWithin(table, coverage_offset);
    const value_format_1 = try readU16BadGpos(table, subtable_offset + 4);
    const value_format_2 = try readU16BadGpos(table, subtable_offset + 6);
    const value_size_1 = valueRecordSize(value_format_1);
    const value_size_2 = valueRecordSize(value_format_2);

    switch (pos_format) {
        1 => {
            const pair_set_count = try readU16BadGpos(table, subtable_offset + 8);
            const pair_set_offsets_pos = subtable_offset + 10;
            try ensureBytesWithin(table, pair_set_offsets_pos, @as(usize, pair_set_count) * 2);
            const pair_record_size = 2 + value_size_1 + value_size_2;
            for (0..pair_set_count) |pair_set_i| {
                const pair_set_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, pair_set_offsets_pos + pair_set_i * 2));
                const pair_value_count = try readU16BadGpos(table, pair_set_offset);
                try ensureBytesWithin(table, pair_set_offset + 2, @as(usize, pair_value_count) * pair_record_size);
            }
        },
        2 => {
            const class_def_1 = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
            const class_def_2 = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
            try ensureClassDefTableWithin(table, class_def_1);
            try ensureClassDefTableWithin(table, class_def_2);
            const class_1_count = try readU16BadGpos(table, subtable_offset + 12);
            const class_2_count = try readU16BadGpos(table, subtable_offset + 14);
            const record_size = value_size_1 + value_size_2;
            try ensureBytesWithin(table, subtable_offset + 16, @as(usize, class_1_count) * @as(usize, class_2_count) * record_size);
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensureCursivePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const entry_exit_count = try readU16BadGpos(table, subtable_offset + 4);
    try ensureCoverageTableWithin(table, coverage_offset);
    try ensureCoverageIndicesWithin(table, coverage_offset, entry_exit_count);
    try ensureBytesWithin(table, subtable_offset + 6, @as(usize, entry_exit_count) * 4);
    for (0..entry_exit_count) |entry_i| {
        const record = subtable_offset + 6 + entry_i * 4;
        const entry_anchor = try readU16BadGpos(table, record);
        const exit_anchor = try readU16BadGpos(table, record + 2);
        if (entry_anchor != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, subtable_offset, entry_anchor));
        if (exit_anchor != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, subtable_offset, exit_anchor));
    }
}

fn ensureMarkToBasePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const base_coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
    const class_count = try readU16BadGpos(table, subtable_offset + 6);
    const mark_array_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
    const base_array_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
    try ensureCoverageTableWithin(table, mark_coverage_offset);
    try ensureCoverageTableWithin(table, base_coverage_offset);
    const mark_count = try ensureMarkArrayWithin(table, mark_array_offset, class_count);
    const base_count = try ensureBaseArrayWithin(table, base_array_offset, class_count);
    try ensureCoverageIndicesWithin(table, mark_coverage_offset, mark_count);
    try ensureCoverageIndicesWithin(table, base_coverage_offset, base_count);
}

fn ensureMarkToLigaturePositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const ligature_coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
    const class_count = try readU16BadGpos(table, subtable_offset + 6);
    const mark_array_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
    const ligature_array_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
    try ensureCoverageTableWithin(table, mark_coverage_offset);
    try ensureCoverageTableWithin(table, ligature_coverage_offset);
    const mark_count = try ensureMarkArrayWithin(table, mark_array_offset, class_count);
    const ligature_count = try ensureLigatureArrayWithin(table, ligature_array_offset, class_count);
    try ensureCoverageIndicesWithin(table, mark_coverage_offset, mark_count);
    try ensureCoverageIndicesWithin(table, ligature_coverage_offset, ligature_count);
}

fn ensureMarkToMarkPositionSubtableWithin(table: Table, subtable_offset: usize) GposError!void {
    const pos_format = try readU16BadGpos(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const mark_1_coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
    const mark_2_coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
    const class_count = try readU16BadGpos(table, subtable_offset + 6);
    const mark_1_array_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
    const mark_2_array_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 10));
    try ensureCoverageTableWithin(table, mark_1_coverage_offset);
    try ensureCoverageTableWithin(table, mark_2_coverage_offset);
    const mark_1_count = try ensureMarkArrayWithin(table, mark_1_array_offset, class_count);
    const mark_2_count = try ensureMark2ArrayWithin(table, mark_2_array_offset, class_count);
    try ensureCoverageIndicesWithin(table, mark_1_coverage_offset, mark_1_count);
    try ensureCoverageIndicesWithin(table, mark_2_coverage_offset, mark_2_count);
}

fn ensureContextPositionSubtableWithin(table: Table, subtable_offset: usize, depth: usize) GposError!void {
    // ContextPos uses the same variable-length topology as ContextSubst, but
    // each matched rule references PosLookupRecords. Validate every rule and
    // referenced lookup before any earlier subtable in the same lookup can
    // append adjustments, preserving lookup-level atomicity.
    const pos_format = try readU16BadGpos(table, subtable_offset);
    switch (pos_format) {
        1 => {
            const coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            try ensureCoverageTableWithin(table, coverage_offset);
            const rule_set_count = try readU16BadGpos(table, subtable_offset + 4);
            const rule_set_offsets_pos = subtable_offset + 6;
            try ensureBytesWithin(table, rule_set_offsets_pos, @as(usize, rule_set_count) * 2);
            for (0..rule_set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, rule_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensurePositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        2 => {
            const coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            const class_def_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
            try ensureCoverageTableWithin(table, coverage_offset);
            try ensureClassDefTableWithin(table, class_def_offset);
            const class_set_count = try readU16BadGpos(table, subtable_offset + 6);
            const class_set_offsets_pos = subtable_offset + 8;
            try ensureBytesWithin(table, class_set_offsets_pos, @as(usize, class_set_count) * 2);
            for (0..class_set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, class_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensurePositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        3 => {
            const glyph_count = try readU16BadGpos(table, subtable_offset + 2);
            if (glyph_count == 0) return error.BadGpos;
            const pos_count = try readU16BadGpos(table, subtable_offset + 4);
            const coverage_offsets_pos = subtable_offset + 6;
            try ensureCoverageOffsetArrayWithin(table, subtable_offset, coverage_offsets_pos, glyph_count);
            const records_pos = coverage_offsets_pos + @as(usize, glyph_count) * 2;
            try ensurePositionRecordListWithin(table, records_pos, pos_count);
            try ensurePositionRecordLookupsWithinDepth(table, records_pos, pos_count, depth);
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensurePositionRuleSetWithin(table: Table, rule_set_offset: usize, depth: usize) GposError!void {
    const rule_count = try readU16BadGpos(table, rule_set_offset);
    const rule_offsets_pos = rule_set_offset + 2;
    try ensureBytesWithin(table, rule_offsets_pos, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_i| {
        const rule_offset = try checkedPositionOffset(table, rule_set_offset, try readU16BadGpos(table, rule_offsets_pos + rule_i * 2));
        try ensurePositionRuleWithin(table, rule_offset, depth);
    }
}

fn ensurePositionRuleWithin(table: Table, rule_offset: usize, depth: usize) GposError!void {
    const glyph_count = try readU16BadGpos(table, rule_offset);
    if (glyph_count == 0) return error.BadGpos;
    const pos_count = try readU16BadGpos(table, rule_offset + 2);
    const input_pos = rule_offset + 4;
    try ensureBytesWithin(table, input_pos, (@as(usize, glyph_count) - 1) * 2);
    const records_pos = input_pos + (@as(usize, glyph_count) - 1) * 2;
    try ensurePositionRecordListWithin(table, records_pos, pos_count);
    try ensurePositionRecordLookupsWithinDepth(table, records_pos, pos_count, depth);
}

fn ensureChainingContextPositionSubtableWithin(table: Table, subtable_offset: usize, depth: usize) GposError!void {
    // ChainingContextPos contains backtrack, input, and lookahead regions
    // before its PosLookupRecords. Preflighting all three regions avoids a
    // malformed later subtable leaking adjustments from an earlier context
    // subtable in the same lookup.
    const pos_format = try readU16BadGpos(table, subtable_offset);
    switch (pos_format) {
        1 => {
            const coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            try ensureCoverageTableWithin(table, coverage_offset);
            const chain_set_count = try readU16BadGpos(table, subtable_offset + 4);
            const chain_set_offsets_pos = subtable_offset + 6;
            try ensureBytesWithin(table, chain_set_offsets_pos, @as(usize, chain_set_count) * 2);
            for (0..chain_set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, chain_set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureChainingPositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        2 => {
            const coverage_offset = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 2));
            const backtrack_class_def = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 4));
            const input_class_def = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 6));
            const lookahead_class_def = try checkedPositionOffset(table, subtable_offset, try readU16BadGpos(table, subtable_offset + 8));
            try ensureCoverageTableWithin(table, coverage_offset);
            try ensureClassDefTableWithin(table, backtrack_class_def);
            try ensureClassDefTableWithin(table, input_class_def);
            try ensureClassDefTableWithin(table, lookahead_class_def);
            const set_count = try readU16BadGpos(table, subtable_offset + 10);
            const set_offsets_pos = subtable_offset + 12;
            try ensureBytesWithin(table, set_offsets_pos, @as(usize, set_count) * 2);
            for (0..set_count) |set_i| {
                const set_relative = try readU16BadGpos(table, set_offsets_pos + set_i * 2);
                if (set_relative == 0) continue;
                try ensureChainingPositionRuleSetWithin(table, try checkedPositionOffset(table, subtable_offset, set_relative), depth);
            }
        },
        3 => try ensureChainingCoveragePositionSubtableWithin(table, subtable_offset, depth),
        else => return error.UnsupportedGpos,
    }
}

fn ensureChainingPositionRuleSetWithin(table: Table, rule_set_offset: usize, depth: usize) GposError!void {
    const rule_count = try readU16BadGpos(table, rule_set_offset);
    const rule_offsets_pos = rule_set_offset + 2;
    try ensureBytesWithin(table, rule_offsets_pos, @as(usize, rule_count) * 2);
    for (0..rule_count) |rule_i| {
        const rule_offset = try checkedPositionOffset(table, rule_set_offset, try readU16BadGpos(table, rule_offsets_pos + rule_i * 2));
        try ensureChainingPositionRuleWithin(table, rule_offset, depth);
    }
}

fn ensureChainingPositionRuleWithin(table: Table, rule_offset: usize, depth: usize) GposError!void {
    var cursor = rule_offset;
    const backtrack_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureBytesWithin(table, cursor, @as(usize, backtrack_count) * 2);
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try readU16BadGpos(table, cursor);
    if (input_count == 0) return error.BadGpos;
    cursor += 2;
    try ensureBytesWithin(table, cursor, (@as(usize, input_count) - 1) * 2);
    cursor += (@as(usize, input_count) - 1) * 2;

    const lookahead_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureBytesWithin(table, cursor, @as(usize, lookahead_count) * 2);
    cursor += @as(usize, lookahead_count) * 2;

    const pos_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensurePositionRecordListWithin(table, cursor, pos_count);
    try ensurePositionRecordLookupsWithinDepth(table, cursor, pos_count, depth);
}

fn ensureChainingCoveragePositionSubtableWithin(table: Table, subtable_offset: usize, depth: usize) GposError!void {
    var cursor = subtable_offset + 2;
    const backtrack_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, backtrack_count);
    cursor += @as(usize, backtrack_count) * 2;

    const input_count = try readU16BadGpos(table, cursor);
    if (input_count == 0) return error.BadGpos;
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, input_count);
    cursor += @as(usize, input_count) * 2;

    const lookahead_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensureCoverageOffsetArrayWithin(table, subtable_offset, cursor, lookahead_count);
    cursor += @as(usize, lookahead_count) * 2;

    const pos_count = try readU16BadGpos(table, cursor);
    cursor += 2;
    try ensurePositionRecordListWithin(table, cursor, pos_count);
    try ensurePositionRecordLookupsWithinDepth(table, cursor, pos_count, depth);
}

fn ensureMarkArrayWithin(table: Table, mark_array_offset: usize, class_count: u16) GposError!usize {
    const mark_count = try readU16BadGpos(table, mark_array_offset);
    try ensureBytesWithin(table, mark_array_offset + 2, @as(usize, mark_count) * 4);
    for (0..mark_count) |mark_i| {
        const record = mark_array_offset + 2 + mark_i * 4;
        const mark_class = try readU16BadGpos(table, record);
        if (mark_class >= class_count) return error.BadGpos;
        const anchor_offset = try readU16BadGpos(table, record + 2);
        // MarkRecords require a real anchor. Treating zero as relative to the
        // MarkArray header would reinterpret markCount/markClass metadata as a
        // Paint-style child table and make malformed mark positioning stateful.
        if (anchor_offset == 0) return error.BadGpos;
        try ensureAnchorTableWithin(table, try checkedPositionOffset(table, mark_array_offset, anchor_offset));
    }
    return mark_count;
}

fn ensureBaseArrayWithin(table: Table, base_array_offset: usize, class_count: u16) GposError!usize {
    const base_count = try readU16BadGpos(table, base_array_offset);
    const anchor_count = try checkedMul(@as(usize, base_count), class_count);
    try ensureBytesWithin(table, base_array_offset + 2, anchor_count * 2);
    for (0..anchor_count) |anchor_i| {
        const anchor_offset = try readU16BadGpos(table, base_array_offset + 2 + anchor_i * 2);
        if (anchor_offset != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, base_array_offset, anchor_offset));
    }
    return base_count;
}

fn ensureLigatureArrayWithin(table: Table, ligature_array_offset: usize, class_count: u16) GposError!usize {
    const ligature_count = try readU16BadGpos(table, ligature_array_offset);
    try ensureBytesWithin(table, ligature_array_offset + 2, @as(usize, ligature_count) * 2);
    for (0..ligature_count) |ligature_i| {
        const attach_offset = try checkedPositionOffset(table, ligature_array_offset, try readU16BadGpos(table, ligature_array_offset + 2 + ligature_i * 2));
        const component_count = try readU16BadGpos(table, attach_offset);
        const anchor_count = try checkedMul(@as(usize, component_count), class_count);
        try ensureBytesWithin(table, attach_offset + 2, anchor_count * 2);
        for (0..anchor_count) |anchor_i| {
            const anchor_offset = try readU16BadGpos(table, attach_offset + 2 + anchor_i * 2);
            if (anchor_offset != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, attach_offset, anchor_offset));
        }
    }
    return ligature_count;
}

fn ensureMark2ArrayWithin(table: Table, mark_2_array_offset: usize, class_count: u16) GposError!usize {
    const mark_2_count = try readU16BadGpos(table, mark_2_array_offset);
    const anchor_count = try checkedMul(@as(usize, mark_2_count), class_count);
    try ensureBytesWithin(table, mark_2_array_offset + 2, anchor_count * 2);
    for (0..anchor_count) |anchor_i| {
        const anchor_offset = try readU16BadGpos(table, mark_2_array_offset + 2 + anchor_i * 2);
        if (anchor_offset != 0) try ensureAnchorTableWithin(table, try checkedPositionOffset(table, mark_2_array_offset, anchor_offset));
    }
    return mark_2_count;
}

fn ensureAnchorTableWithin(table: Table, anchor_offset: usize) GposError!void {
    const format = try readU16BadGpos(table, anchor_offset);
    const min_len: usize = switch (format) {
        1 => 6,
        2 => 8,
        3 => 10,
        else => return error.UnsupportedGpos,
    };
    try ensureBytesWithin(table, anchor_offset, min_len);
}

fn ensureCoverageIndicesWithin(table: Table, coverage_offset: usize, target_count: usize) GposError!void {
    const format = try readU16BadGpos(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16BadGpos(table, coverage_offset + 2);
            if (@as(usize, glyph_count) > target_count) return error.BadGpos;
        },
        2 => {
            const range_count = try readU16BadGpos(table, coverage_offset + 2);
            for (0..range_count) |range_i| {
                const range = coverage_offset + 4 + range_i * 6;
                const start = try readU16BadGpos(table, range);
                const end = try readU16BadGpos(table, range + 2);
                const start_index = try readU16BadGpos(table, range + 4);
                const span = @as(usize, end) - @as(usize, start) + 1;
                if (@as(usize, start_index) > target_count or span > target_count - @as(usize, start_index)) return error.BadGpos;
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensureCoverageOffsetArrayWithin(table: Table, base_offset: usize, offsets_pos: usize, count: u16) GposError!void {
    try ensureBytesWithin(table, offsets_pos, @as(usize, count) * 2);
    for (0..count) |i| {
        const coverage_offset = try checkedPositionOffset(table, base_offset, try readU16BadGpos(table, offsets_pos + i * 2));
        try ensureCoverageTableWithin(table, coverage_offset);
    }
}

fn checkedMul(a: usize, b: usize) GposError!usize {
    if (a != 0 and b > std.math.maxInt(usize) / a) return error.BadGpos;
    return a * b;
}

fn ensureValueRecordWithin(table: Table, offset: usize, format: u16) GposError!void {
    try ensureBytesWithin(table, offset, valueRecordSize(format));
}

fn ensureCoverageTableWithin(table: Table, coverage_offset: usize) GposError!void {
    const format = try readU16BadGpos(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16BadGpos(table, coverage_offset + 2);
            try ensureBytesWithin(table, coverage_offset + 4, @as(usize, glyph_count) * 2);
            try validateCoverageFormat1Order(table, coverage_offset, glyph_count);
        },
        2 => {
            const range_count = try readU16BadGpos(table, coverage_offset + 2);
            try ensureBytesWithin(table, coverage_offset + 4, @as(usize, range_count) * 6);
            try validateCoverageFormat2Ranges(table, coverage_offset, range_count);
        },
        else => return error.UnsupportedGpos,
    }
}

fn ensureClassDefTableWithin(table: Table, class_def_offset: usize) GposError!void {
    const format = try readU16BadGpos(table, class_def_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16BadGpos(table, class_def_offset + 4);
            try ensureBytesWithin(table, class_def_offset + 6, @as(usize, glyph_count) * 2);
        },
        2 => {
            const range_count = try readU16BadGpos(table, class_def_offset + 2);
            try ensureBytesWithin(table, class_def_offset + 4, @as(usize, range_count) * 6);
        },
        else => return error.UnsupportedGpos,
    }
}

fn checkedPositionOffset(table: Table, base_offset: usize, relative_offset: u32) GposError!usize {
    if (relative_offset > std.math.maxInt(usize) - base_offset) return error.BadGpos;
    const absolute = base_offset + @as(usize, @intCast(relative_offset));
    if (absolute > table.length) return error.BadGpos;
    return absolute;
}

fn ensureBytesWithin(table: Table, offset: usize, len: usize) GposError!void {
    if (offset > table.length or len > table.length - offset) return error.BadGpos;
}

fn readU16BadGpos(table: Table, relative: usize) GposError!u16 {
    return readU16(table, relative) catch |err| {
        return switch (err) {
            error.EndOfStream => error.BadGpos,
            else => err,
        };
    };
}

fn readU32BadGpos(table: Table, relative: usize) GposError!u32 {
    return readU32(table, relative) catch |err| {
        return switch (err) {
            error.EndOfStream => error.BadGpos,
            else => err,
        };
    };
}

fn collectNestedAdjustment(table: Table, glyphs: []const GlyphId, target_index: usize, lookup_index: u16, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const lookup_list_offset = try readU16(table, 8);
    const lookup_count = try readU16(table, lookup_list_offset);
    if (lookup_index >= lookup_count) return;
    const lookup_offset = lookup_list_offset + try readU16(table, lookup_list_offset + 2 + @as(usize, lookup_index) * 2);
    const lookup_type = try readU16(table, lookup_offset);
    const lookup_flag = try readU16(table, lookup_offset + 2);
    const subtable_count = try readU16(table, lookup_offset + 4);
    var lookup_options = options;
    if ((lookup_flag & 0x0010) != 0) {
        lookup_options.active_mark_filtering_set = try readU16(table, lookup_offset + 6 + @as(usize, subtable_count) * 2);
    }
    for (0..subtable_count) |i| {
        const subtable_offset = lookup_offset + try readU16(table, lookup_offset + 6 + i * 2);
        switch (lookup_type) {
            1 => if (try collectSingleAdjustmentAt(table, subtable_offset, glyphs[target_index], target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
            2 => if (try collectPairAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
            3 => _ = try collectCursiveAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options),
            4 => _ = try collectMarkToBaseAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options, &.{}),
            5 => _ = try collectMarkToLigatureAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options),
            6 => _ = try collectMarkToMarkAdjustmentAt(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options),
            9 => if (try collectNestedExtensionAdjustment(table, subtable_offset, glyphs, target_index, adjustments, allocator, lookup_flag, lookup_options)) return,
            else => {},
        }
    }
}

fn collectNestedExtensionAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, target_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const extension_lookup_type = try readU16(table, subtable_offset + 2);
    if (extension_lookup_type == 9) return error.UnsupportedGpos;
    const extension_offset = try readU32(table, subtable_offset + 4);
    const extension_subtable = subtable_offset + extension_offset;

    // PosLookupRecord names one glyph in an already-matched input sequence.
    // ExtensionPos only widens the subtable address, so keep using the
    // contextual target index when delegating to the wrapped lookup body.
    switch (extension_lookup_type) {
        // SinglePos subtables inside one lookup are ordered alternatives for a
        // target glyph. Returning the match status here lets the parent lookup
        // stop after the first matching ExtensionPos(SinglePos) wrapper,
        // matching the top-level lookup-level SinglePos collector.
        1 => return try collectSingleAdjustmentAt(table, extension_subtable, glyphs[target_index], target_index, adjustments, allocator, lookup_flag, options),
        // PairPos subtables are ordered alternatives even when the PairPos is
        // reached through ExtensionPos from a PosLookupRecord. Return the
        // wrapped pair match so the containing nested lookup can stop before a
        // later ExtensionPos(PairPos) subtable cascades onto the same pair.
        2 => return try collectPairAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        3 => _ = try collectCursiveAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        4 => _ = try collectMarkToBaseAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options, &.{}),
        5 => _ = try collectMarkToLigatureAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        6 => _ = try collectMarkToMarkAdjustmentAt(table, extension_subtable, glyphs, target_index, adjustments, allocator, lookup_flag, options),
        else => {},
    }
    return false;
}

fn collectSingleAdjustmentAt(table: Table, subtable_offset: usize, glyph: GlyphId, target_index: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;
    const pos_format = try readU16(table, subtable_offset);
    const coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const value_format = try readU16(table, subtable_offset + 4);
    switch (pos_format) {
        1 => {
            if (try coverageIndex(table, coverage_offset, glyph) != null) {
                const value = try readValueRecord(table, subtable_offset + 6, value_format);
                try appendAdjustment(adjustments, allocator, target_index, value, false);
                return true;
            }
            return false;
        },
        2 => {
            const coverage = try coverageIndex(table, coverage_offset, glyph) orelse return false;
            const value_count = try readU16(table, subtable_offset + 6);
            if (coverage >= value_count) return false;
            const value_size = valueRecordSize(value_format);
            const value = try readValueRecord(table, subtable_offset + 8 + coverage * value_size, value_format);
            try appendAdjustment(adjustments, allocator, target_index, value, false);
            return true;
        },
        else => return error.UnsupportedGpos,
    }
}

fn collectMarkToLigatureAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const class_count = try readU16(table, subtable_offset + 6);
    if (class_count == 0 or glyphs.len < 2) return;

    for (glyphs, 0..) |_, i| {
        _ = try collectMarkToLigatureAdjustmentAt(table, subtable_offset, glyphs, i, adjustments, allocator, lookup_flag, options);
    }
}

fn collectMarkToLigatureAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, mark_position: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecord application names one mark in the matched
    // input sequence. MarkLigPos still needs the complete glyph run so the
    // backwards ligature search observes the nested lookup's LookupFlag, but
    // only the record's sequenceIndex target may receive an adjustment.
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    if (mark_position >= glyphs.len) return false;
    const glyph = glyphs[mark_position];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const mark_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const ligature_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_array_offset = subtable_offset + try readU16(table, subtable_offset + 8);
    const ligature_array_offset = subtable_offset + try readU16(table, subtable_offset + 10);
    if (class_count == 0 or glyphs.len < 2) return false;

    const mark_index = try coverageIndex(table, mark_coverage_offset, glyph) orelse return false;
    const ligature_position = try previousCoveredLigatureGlyph(table, mark_coverage_offset, ligature_coverage_offset, glyphs, mark_position, lookup_flag, options) orelse return false;
    const ligature_index = try coverageIndex(table, ligature_coverage_offset, glyphs[ligature_position]) orelse return false;
    const mark_record_offset = mark_array_offset + 2 + mark_index * 4;
    const mark_class = try readU16(table, mark_record_offset);
    if (mark_class >= class_count) return false;
    const mark_anchor_offset = mark_array_offset + try readU16(table, mark_record_offset + 2);
    const ligature_attach_offset = ligature_array_offset + try readU16(table, ligature_array_offset + 2 + ligature_index * 2);
    const component_count = try readU16(table, ligature_attach_offset);
    if (component_count == 0) return false;
    const component_index = try ligatureComponentIndexForMark(table, mark_coverage_offset, glyphs, ligature_position, mark_position, component_count, lookup_flag, options);
    const anchor_record = ligature_attach_offset + 2 + (component_index * class_count + mark_class) * 2;
    const ligature_anchor_relative = try readU16(table, anchor_record);
    if (ligature_anchor_relative == 0) return false;
    const ligature_anchor_offset = ligature_attach_offset + ligature_anchor_relative;
    const mark_anchor = try readAnchor(table, mark_anchor_offset);
    const ligature_anchor = try readAnchor(table, ligature_anchor_offset);
    try appendAdjustmentEx(adjustments, allocator, mark_position, .{
        .index = mark_position,
        .x_placement = ligature_anchor.x - mark_anchor.x,
        .y_placement = ligature_anchor.y - mark_anchor.y,
    }, .{ .mark_attachment = true, .mark_base_index = ligature_position });
    return true;
}

fn previousCoveredLigatureGlyph(table: Table, mark_coverage_offset: usize, ligature_coverage_offset: usize, glyphs: []const GlyphId, mark_position: usize, lookup_flag: u16, options: LookupOptions) GposError!?usize {
    var i = mark_position;
    while (i > 0) {
        i -= 1;
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[i])) continue;
        if (try coverageIndex(table, ligature_coverage_offset, glyphs[i]) != null) return i;

        // MarkLigPos attaches marks to the nearest previous participating
        // ligature. Earlier marks in the same cluster must be transparent for
        // that search; otherwise only the first mark after a ligature can ever
        // be positioned. Non-mark glyphs still block the search so we do not
        // attach across an intervening base or ligature.
        if (try markGlyphForLigatureSearch(table, mark_coverage_offset, glyphs[i], options)) continue;
        return null;
    }
    return null;
}

fn ligatureComponentIndexForMark(table: Table, mark_coverage_offset: usize, glyphs: []const GlyphId, ligature_position: usize, mark_position: usize, component_count: usize, lookup_flag: u16, options: LookupOptions) GposError!usize {
    if (component_count <= 1) return 0;

    if (options.glyph_source_indices) |sources| {
        if (mark_position < sources.len) {
            if (options.ligature_components) |components| {
                if (ligature_position < components.len) {
                    const info = components[ligature_position];
                    const available_count = @min(@as(usize, info.component_count), component_count);
                    if (available_count > 0) {
                        const mark_source = sources[mark_position];
                        var chosen: usize = 0;
                        // Component source positions are monotonically ordered
                        // by the GSUB ligature trace. A mark belongs to the
                        // latest component whose source position is not after
                        // that mark, which handles marks originally typed
                        // between ligature components as well as marks after
                        // the full ligature sequence.
                        for (info.component_sources[0..available_count], 0..) |component_source, component_i| {
                            if (component_source > mark_source) break;
                            chosen = component_i;
                        }
                        return chosen;
                    }
                }
            }
        }
    }

    var covered_marks_before_target: usize = 0;
    var pos = ligature_position + 1;
    while (pos < mark_position) : (pos += 1) {
        if (lookupIgnoresGlyph(lookup_flag, options, glyphs[pos])) continue;
        // OpenType engines normally know the original GSUB ligature component
        // for each remaining mark. When the caller does not provide that
        // metadata, use the mark's order within the post-ligature covered mark
        // run as the best available component hint. Clamp to the final
        // component so extra stacked marks still choose a valid anchor.
        if (try coverageIndex(table, mark_coverage_offset, glyphs[pos]) != null) {
            covered_marks_before_target += 1;
        }
    }
    return @min(covered_marks_before_target, component_count - 1);
}

fn markGlyphForLigatureSearch(table: Table, mark_coverage_offset: usize, glyph: GlyphId, options: LookupOptions) GposError!bool {
    if (options.glyph_classes) |classes| {
        if (glyph < classes.len and classes[glyph] == 3) return true;
    }
    return try coverageIndex(table, mark_coverage_offset, glyph) != null;
}

fn collectMarkToMarkAdjustment(table: Table, subtable_offset: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    const class_count = try readU16(table, subtable_offset + 6);
    if (class_count == 0 or glyphs.len < 2) return;

    for (glyphs, 0..) |_, i| {
        _ = try collectMarkToMarkAdjustmentAt(table, subtable_offset, glyphs, i, adjustments, allocator, lookup_flag, options);
    }
}

fn collectMarkToMarkAdjustmentAt(table: Table, subtable_offset: usize, glyphs: []const GlyphId, mark_1_position: usize, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, lookup_flag: u16, options: LookupOptions) (GposError || std.mem.Allocator.Error)!bool {
    // Contextual PosLookupRecord application targets one matched input glyph,
    // not every mark covered by the nested MarkToMarkPos lookup. Keep the full
    // glyph run for the backwards Mark2Coverage search, but append an
    // adjustment only for the requested Mark1 position.
    const pos_format = try readU16(table, subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    if (mark_1_position >= glyphs.len) return false;
    const glyph = glyphs[mark_1_position];
    if (lookupIgnoresGlyph(lookup_flag, options, glyph)) return false;

    const mark_1_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 2);
    const mark_2_coverage_offset = subtable_offset + try readU16(table, subtable_offset + 4);
    const class_count = try readU16(table, subtable_offset + 6);
    const mark_1_array_offset = subtable_offset + try readU16(table, subtable_offset + 8);
    const mark_2_array_offset = subtable_offset + try readU16(table, subtable_offset + 10);
    if (class_count == 0 or glyphs.len < 2) return false;

    const mark_1_index = try coverageIndex(table, mark_1_coverage_offset, glyph) orelse return false;
    const mark_2_position = try previousUnignoredCoveredGlyph(table, mark_2_coverage_offset, glyphs, mark_1_position, lookup_flag, options) orelse return false;
    const mark_2_index = try coverageIndex(table, mark_2_coverage_offset, glyphs[mark_2_position]) orelse return false;
    const mark_1_record_offset = mark_1_array_offset + 2 + mark_1_index * 4;
    const mark_class = try readU16(table, mark_1_record_offset);
    if (mark_class >= class_count) return false;
    const mark_1_anchor_offset = mark_1_array_offset + try readU16(table, mark_1_record_offset + 2);
    const mark_2_anchor_record = mark_2_array_offset + 2 + (mark_2_index * class_count + mark_class) * 2;
    const mark_2_anchor_relative = try readU16(table, mark_2_anchor_record);
    if (mark_2_anchor_relative == 0) return false;
    const mark_2_anchor_offset = mark_2_array_offset + mark_2_anchor_relative;
    const mark_1_anchor = try readAnchor(table, mark_1_anchor_offset);
    const mark_2_anchor = try readAnchor(table, mark_2_anchor_offset);
    try appendAdjustmentEx(adjustments, allocator, mark_1_position, .{
        .index = mark_1_position,
        .x_placement = mark_2_anchor.x - mark_1_anchor.x,
        .y_placement = mark_2_anchor.y - mark_1_anchor.y,
    }, .{ .mark_attachment = true, .mark_base_index = mark_2_position });
    return true;
}

const Anchor = struct {
    x: i16,
    y: i16,
};

fn readAnchor(table: Table, anchor_offset: usize) GposError!Anchor {
    const format = try readU16(table, anchor_offset);
    return switch (format) {
        1 => blk: {
            if (anchor_offset + 6 > table.length) return error.EndOfStream;
            break :blk .{
                .x = try readI16(table, anchor_offset + 2),
                .y = try readI16(table, anchor_offset + 4),
            };
        },
        2 => blk: {
            if (anchor_offset + 8 > table.length) return error.EndOfStream;
            break :blk .{
                .x = try readI16(table, anchor_offset + 2),
                .y = try readI16(table, anchor_offset + 4),
            };
        },
        3 => blk: {
            if (anchor_offset + 10 > table.length) return error.EndOfStream;
            break :blk .{
                .x = try readI16(table, anchor_offset + 2),
                .y = try readI16(table, anchor_offset + 4),
            };
        },
        else => error.UnsupportedGpos,
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
    // Device/variation-index offset fields are parsed and skipped for now: the
    // base placement/advance remains valid, while size-specific deltas can be
    // layered in later without rejecting common production fonts outright.
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
    if ((format & 0x0010) != 0) cursor += 2;
    if ((format & 0x0020) != 0) cursor += 2;
    if ((format & 0x0040) != 0) cursor += 2;
    if ((format & 0x0080) != 0) cursor += 2;
    if (cursor > table.length) return error.EndOfStream;
    return value;
}

fn coverageIndex(table: Table, coverage_offset: usize, glyph: GlyphId) GposError!?usize {
    // Coverage handling mirrors GSUB so coverage index semantics remain
    // identical between substitution and positioning code. The OpenType
    // contract requires sorted glyph arrays and sorted, non-overlapping ranges;
    // enforcing that here keeps malformed positioning data from quietly
    // selecting the wrong value record.
    const format = try readU16(table, coverage_offset);
    switch (format) {
        1 => {
            const glyph_count = try readU16(table, coverage_offset + 2);
            try validateCoverageFormat1Order(table, coverage_offset, glyph_count);
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
            try validateCoverageFormat2Ranges(table, coverage_offset, range_count);
            for (0..range_count) |i| {
                const range_offset = coverage_offset + 4 + i * 6;
                const start = try readU16(table, range_offset);
                const end = try readU16(table, range_offset + 2);
                const start_index = try readU16(table, range_offset + 4);
                if (glyph >= start and glyph <= end) {
                    // Keep coverage-index arithmetic in usize. Malformed or
                    // edge-of-glyph-space ranges can otherwise overflow u16 in
                    // safety builds before callers get a chance to bounds-check
                    // the resulting index against their subtable-specific counts.
                    return @as(usize, start_index) + (@as(usize, glyph) - @as(usize, start));
                }
            }
            return null;
        },
        else => return error.UnsupportedGpos,
    }
}

fn validateCoverageFormat1Order(table: Table, coverage_offset: usize, glyph_count: u16) GposError!void {
    var previous: ?GlyphId = null;
    for (0..glyph_count) |index| {
        const glyph = try readU16BadGpos(table, coverage_offset + 4 + index * 2);
        if (previous) |last| {
            if (glyph <= last) return error.BadGpos;
        }
        previous = glyph;
    }
}

fn validateCoverageFormat2Ranges(table: Table, coverage_offset: usize, range_count: u16) GposError!void {
    var previous_end: ?GlyphId = null;
    for (0..range_count) |index| {
        const range_offset = coverage_offset + 4 + index * 6;
        const start = try readU16BadGpos(table, range_offset);
        const end = try readU16BadGpos(table, range_offset + 2);
        if (end < start) return error.BadGpos;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadGpos;
        }
        previous_end = end;
    }
}

fn classValue(table: Table, class_def_offset: usize, glyph: GlyphId) GposError!u16 {
    const format = try readU16(table, class_def_offset);
    switch (format) {
        1 => {
            const start = try readU16(table, class_def_offset + 2);
            const count = try readU16(table, class_def_offset + 4);
            // ClassDef format 1 describes a half-open range, but `start +
            // count` is not guaranteed to fit in GlyphId's u16 type near the
            // upper glyph boundary. Widen before comparing so edge-range class
            // definitions behave deterministically instead of trapping.
            const glyph_index = @as(usize, glyph);
            const start_index = @as(usize, start);
            const end_exclusive = start_index + @as(usize, count);
            if (glyph_index < start_index or glyph_index >= end_exclusive) return 0;
            return try readU16(table, class_def_offset + 6 + (glyph_index - start_index) * 2);
        },
        2 => {
            const range_count = try readU16(table, class_def_offset + 2);
            try validateClassDefFormat2Ranges(table, class_def_offset, range_count);
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

fn validateClassDefFormat2Ranges(table: Table, class_def_offset: usize, range_count: u16) GposError!void {
    // PairPos class matrices and contextual class matching assume ClassDef
    // format 2 ranges are canonical: sorted, non-overlapping, and individually
    // ordered. Rejecting malformed ranges keeps an early overlapping record
    // from silently selecting the wrong positioning class.
    var previous_end: ?GlyphId = null;
    for (0..range_count) |index| {
        const range_offset = class_def_offset + 4 + index * 6;
        const start = try readU16BadGpos(table, range_offset);
        const end = try readU16BadGpos(table, range_offset + 2);
        if (end < start) return error.BadGpos;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadGpos;
        }
        previous_end = end;
    }
}

test "GPOS coverage format 2 widens boundary coverage indexes" {
    var bytes = [_]u8{0} ** 16;
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 1);
    writeU16Test(&bytes, 4, 0xfffe);
    writeU16Test(&bytes, 6, 0xffff);
    writeU16Test(&bytes, 8, 0xffff);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(@as(?usize, 0xffff), try coverageIndex(table, 0, 0xfffe));
    try std.testing.expectEqual(@as(?usize, 0x10000), try coverageIndex(table, 0, 0xffff));
}

test "GPOS rejects malformed coverage ordering before positioning" {
    var bytes = [_]u8{0} ** 20;
    writeU16Test(&bytes, 0, 1); // SinglePos format 1.
    writeU16Test(&bytes, 2, 10); // Coverage table.
    writeU16Test(&bytes, 4, 0x0004); // ValueFormat: xAdvance.
    writeU16Test(&bytes, 6, 30);
    writeU16Test(&bytes, 10, 1); // Coverage format 1.
    writeU16Test(&bytes, 12, 2);
    writeU16Test(&bytes, 14, 10);
    writeU16Test(&bytes, 16, 5); // Out-of-order; binary search would be unsound.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expectError(error.BadGpos, collectSingleAdjustment(table, 0, &.{10}, &adjustments, std.testing.allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS class format 1 handles upper glyph boundary" {
    var bytes = [_]u8{0} ** 12;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0xfffe);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 7);
    writeU16Test(&bytes, 8, 9);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(@as(u16, 7), try classValue(table, 0, 0xfffe));
    try std.testing.expectEqual(@as(u16, 9), try classValue(table, 0, 0xffff));
    try std.testing.expectEqual(@as(u16, 0), try classValue(table, 0, 0xfffd));
}

test "GPOS rejects malformed ClassDef format 2 ranges" {
    var bytes = [_]u8{0} ** 22;
    writeU16Test(&bytes, 0, 2); // ClassDef format 2.
    writeU16Test(&bytes, 2, 3); // Three ClassRangeRecords.
    writeU16Test(&bytes, 4, 10);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 12); // Overlaps the previous inclusive range.
    writeU16Test(&bytes, 12, 14);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 20);
    writeU16Test(&bytes, 18, 18); // Reversed range must also be rejected.
    writeU16Test(&bytes, 20, 3);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, classValue(table, 0, 12));

    writeU16Test(&bytes, 10, 13); // Repair overlap so the reversed range is checked.
    try std.testing.expectError(error.BadGpos, classValue(table, 0, 18));
}

test "GPOS anchors validate format-specific record sizes" {
    var bytes = [_]u8{0} ** 10;
    writeU16Test(&bytes, 0, 1);
    writeI16Test(&bytes, 2, 10);
    writeI16Test(&bytes, 4, 20);
    try std.testing.expectEqual(Anchor{ .x = 10, .y = 20 }, try readAnchor(.{ .data = &bytes, .offset = 0, .length = 6 }, 0));

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 6, 3);
    try std.testing.expectError(error.EndOfStream, readAnchor(.{ .data = &bytes, .offset = 0, .length = 6 }, 0));
    try std.testing.expectEqual(Anchor{ .x = 10, .y = 20 }, try readAnchor(.{ .data = &bytes, .offset = 0, .length = 8 }, 0));

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 8, 0);
    try std.testing.expectError(error.EndOfStream, readAnchor(.{ .data = &bytes, .offset = 0, .length = 8 }, 0));
    try std.testing.expectEqual(Anchor{ .x = 10, .y = 20 }, try readAnchor(.{ .data = &bytes, .offset = 0, .length = 10 }, 0));
}

test "GPOS value records tolerate device and variation offset fields" {
    var bytes = [_]u8{0} ** 16;
    writeI16Test(&bytes, 0, 50);
    writeI16Test(&bytes, 2, -25);
    writeI16Test(&bytes, 4, 30);
    writeI16Test(&bytes, 6, -10);
    writeU16Test(&bytes, 8, 12);
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 14);
    writeU16Test(&bytes, 14, 0);

    const value = try readValueRecord(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, 0x00ff);
    try std.testing.expectEqual(@as(i16, 50), value.x_placement);
    try std.testing.expectEqual(@as(i16, -25), value.y_placement);
    try std.testing.expectEqual(@as(i16, 30), value.x_advance);
    try std.testing.expectEqual(@as(i16, -10), value.y_advance);
}

test "GPOS LangSys required feature bypasses feature overrides" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;
    writeRequiredFeatureSelectionTable(&bytes, unicode.tag("kern"), unicode.tag("mark"));
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    var lookups = try selectedLookupIndices(table, allocator, .{
        .script_tag = .dflt,
        // Required features are mandatory LangSys data, while overrides only
        // opt optional/default feature tags in or out.
        .features = &.{
            .{ .tag = unicode.tag("kern"), .enabled = false },
            .{ .tag = unicode.tag("mark"), .enabled = false },
        },
    });
    defer lookups.deinit(allocator);

    try std.testing.expectEqualSlices(u16, &.{0}, lookups.items);
}

test "GPOS cursive attachment skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 3);
    writeU16Test(&bytes, 2, 0x0008); // IgnoreMarks: transparent marks must not break cursive joins.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const cursive = 8;
    writeU16Test(&bytes, cursive + 0, 1);
    writeU16Test(&bytes, cursive + 2, 14);
    writeU16Test(&bytes, cursive + 4, 2);
    // Glyph 10 contributes only an exit anchor; glyph 12 contributes only an
    // entry anchor. The ignored mark between them should be transparent.
    writeU16Test(&bytes, cursive + 6, 0);
    writeU16Test(&bytes, cursive + 8, 22);
    writeU16Test(&bytes, cursive + 10, 28);
    writeU16Test(&bytes, cursive + 12, 0);
    writeCoverage1ListTest(&bytes, cursive + 14, &.{ 10, 12 });
    writeAnchor1Test(&bytes, cursive + 22, 100, 30);
    writeAnchor1Test(&bytes, cursive + 28, 20, 5);

    const glyphs = [_]GlyphId{ 10, 11, 12 };
    const glyph_classes = [_]u16{0} ** 13;
    var mutable_classes = glyph_classes;
    mutable_classes[11] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &mutable_classes,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 80), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[0].y_placement);
}

test "GPOS mark-to-base stops at intervening non-covered base" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 4);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_base = 8;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 18);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 24);
    writeU16Test(&bytes, mark_base + 10, 38);

    writeCoverage1Test(&bytes, mark_base + 12, 12);
    writeCoverage1Test(&bytes, mark_base + 18, 10);

    const mark_array = mark_base + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 8);
    writeAnchor1Test(&bytes, mark_array + 8, 0, 0);

    const base_array = mark_base + 38;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 100, 120);

    const glyphs = [_]GlyphId{ 10, 11, 12 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[10] = 1;
    glyph_classes[11] = 1;
    glyph_classes[12] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS MarkAttachmentType uses MarkAttachClassDef without glyph classes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 26;

    writeSinglePositionLookup(&bytes, 0, 5, 0x0100, 33); // MarkAttachmentType 1.
    writeU16Test(&bytes, 16, 1);
    writeU16Test(&bytes, 18, 2);
    writeU16Test(&bytes, 20, 5);
    writeU16Test(&bytes, 22, 8);

    const glyphs = [_]GlyphId{ 5, 7, 8 };
    var mark_attach_classes = [_]u16{0} ** 9;
    mark_attach_classes[5] = 2;
    mark_attach_classes[7] = 1;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_attach_classes = &mark_attach_classes,
    });

    // Non-zero MarkAttachClassDef entries identify marks even when GlyphClassDef
    // is absent or incomplete. Glyph 5 is a mark of the wrong attachment type,
    // so the covered SinglePos adjustment must not apply to it. Glyph 8 has no
    // attachment class and still participates as an ordinary glyph.
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

test "GPOS lookup flags honor GDEF mark filtering sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 1); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 33);
    writeCoverage1Test(&bytes, single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{7}, &.{5} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

test "GPOS lookup flags combine mark filtering set and attachment type" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 28;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0210); // MarkAttachmentType 2 + UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 0); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 41);
    writeCoverage1ListTest(&bytes, single + 8, &.{ 5, 7 });

    const glyphs = [_]GlyphId{ 5, 7 };
    var glyph_classes = [_]u16{0} ** 8;
    glyph_classes[5] = 3;
    glyph_classes[7] = 3;
    var mark_attach_classes = [_]u16{0} ** 8;
    mark_attach_classes[5] = 1;
    mark_attach_classes[7] = 2;
    const mark_sets = [_][]const GlyphId{&.{ 5, 7 }};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 41), adjustments.items[0].x_placement);
}

test "GPOS context nested lookup honors nested lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 74;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 18, 0);
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

    writeCoverage1Test(&bytes, context + 22, 1);
    writeSinglePositionLookup(&bytes, 52, 2, 0x0008, 50);

    const glyphs = [_]GlyphId{ 1, 2 };
    const glyph_classes = [_]u16{ 0, 1, 3 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual record truncation is atomic" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 14);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 28);

    writeSinglePositionLookup(&bytes, 24, 1, 0, 40);

    const context = 44;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 8);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 14);
    writeCoverage1Test(&bytes, context + 8, 1);

    const set = context + 14;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    // The second declared PosLookupRecord is beyond table.length below.

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    const table = Table{ .data = &bytes, .offset = 0, .length = rule + 8 };
    try std.testing.expectError(error.BadGpos, collectLookup(table, 16, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual lookup preflight rejects later truncated lookup atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    // Lookup 2 is referenced only after lookup 1 would append an adjustment.
    // Its truncated SubTable offset array must be caught before collecting any
    // nested result from the contextual match.
    writeU16Test(&bytes, 90, 1);
    writeU16Test(&bytes, 94, 1);

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS contextual lookup preflight rejects nested extension payload atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 18);
    writeU16Test(&bytes, 14, 60);
    writeU16Test(&bytes, 16, 80);

    const context_lookup = 28;
    writeU16Test(&bytes, context_lookup + 0, 7);
    writeU16Test(&bytes, context_lookup + 4, 1);
    writeU16Test(&bytes, context_lookup + 6, 8);

    const context = context_lookup + 8;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 24);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 2);
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 0);
    writeU16Test(&bytes, rule + 10, 2);
    writeCoverage1Test(&bytes, context + 24, 1);

    writeSinglePositionLookup(&bytes, 70, 1, 0, 45);

    writeU16Test(&bytes, 90, 9);
    writeU16Test(&bytes, 94, 1);
    writeU16Test(&bytes, 96, 8);
    const extension = 98;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    // The ExtensionPos wrapper header is present, but its wrapped SinglePos
    // payload is outside this table. Reject the whole contextual match before
    // the preceding record appends its adjustment.
    writeU32Test(&bytes, extension + 4, 20);

    const glyphs = [_]GlyphId{1};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, context_lookup, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS extension single positioning preflights wrapped value arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 60;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 32);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 45);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_extension = 32;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 2);
    writeU16Test(&bytes, second_single + 2, 14);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeU16Test(&bytes, second_single + 6, 7);
    writeCoverage1Test(&bytes, second_single + 14, 30);
    // The second wrapped SinglePos declares seven value records, extending past
    // table.length. Reject the whole ExtensionPos lookup before the first
    // wrapper appends its otherwise valid adjustment for glyph 10.

    const glyphs = [_]GlyphId{ 10, 30 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct single positioning preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 46;

    writeU16Test(&bytes, 0, 1); // SinglePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 26);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 45);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_single = 26;
    writeU16Test(&bytes, second_single + 0, 2);
    writeU16Test(&bytes, second_single + 2, 14);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeU16Test(&bytes, second_single + 6, 7);
    writeCoverage1Test(&bytes, second_single + 14, 30);
    // The second SinglePos subtable declares seven ValueRecords, extending past
    // table.length. Reject the lookup before collecting the first subtable's
    // otherwise valid xAdvance adjustment.

    const glyphs = [_]GlyphId{ 10, 30 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct cursive positioning preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 58;

    writeU16Test(&bytes, 0, 3); // CursivePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 46);

    const first_cursive = 10;
    writeU16Test(&bytes, first_cursive + 0, 1);
    writeU16Test(&bytes, first_cursive + 2, 14);
    writeU16Test(&bytes, first_cursive + 4, 2);
    writeU16Test(&bytes, first_cursive + 6, 0);
    writeU16Test(&bytes, first_cursive + 8, 22);
    writeU16Test(&bytes, first_cursive + 10, 28);
    writeU16Test(&bytes, first_cursive + 12, 0);
    writeCoverage1ListTest(&bytes, first_cursive + 14, &.{ 10, 11 });
    writeAnchor1Test(&bytes, first_cursive + 22, 100, 50);
    writeAnchor1Test(&bytes, first_cursive + 28, 20, 10);

    const second_cursive = 46;
    writeU16Test(&bytes, second_cursive + 0, 1);
    writeU16Test(&bytes, second_cursive + 2, 6);
    writeU16Test(&bytes, second_cursive + 4, 1);
    writeU16Test(&bytes, second_cursive + 6, 1); // Truncated Coverage format 1.
    writeU16Test(&bytes, second_cursive + 8, 2);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct mark-to-base positioning preflights anchor arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU16Test(&bytes, 0, 4); // MarkBasePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 58);

    const first_mark_base = 10;
    writeU16Test(&bytes, first_mark_base + 0, 1);
    writeU16Test(&bytes, first_mark_base + 2, 12);
    writeU16Test(&bytes, first_mark_base + 4, 18);
    writeU16Test(&bytes, first_mark_base + 6, 1);
    writeU16Test(&bytes, first_mark_base + 8, 24);
    writeU16Test(&bytes, first_mark_base + 10, 36);
    writeCoverage1Test(&bytes, first_mark_base + 12, 2);
    writeCoverage1Test(&bytes, first_mark_base + 18, 1);
    const first_mark_array = first_mark_base + 24;
    writeU16Test(&bytes, first_mark_array + 0, 1);
    writeU16Test(&bytes, first_mark_array + 2, 0);
    writeU16Test(&bytes, first_mark_array + 4, 6);
    writeAnchor1Test(&bytes, first_mark_array + 6, 20, 30);
    const first_base_array = first_mark_base + 36;
    writeU16Test(&bytes, first_base_array + 0, 1);
    writeU16Test(&bytes, first_base_array + 2, 4);
    writeAnchor1Test(&bytes, first_base_array + 4, 100, 100);

    const second_mark_base = 58;
    writeU16Test(&bytes, second_mark_base + 0, 1);
    writeU16Test(&bytes, second_mark_base + 2, 12);
    writeU16Test(&bytes, second_mark_base + 4, 18);
    writeU16Test(&bytes, second_mark_base + 6, 1);
    writeU16Test(&bytes, second_mark_base + 8, 24);
    writeU16Test(&bytes, second_mark_base + 10, 30);
    writeCoverage1Test(&bytes, second_mark_base + 12, 2);
    writeCoverage1Test(&bytes, second_mark_base + 18, 1);
    const second_mark_array = second_mark_base + 24;
    writeU16Test(&bytes, second_mark_array + 0, 1);
    writeU16Test(&bytes, second_mark_array + 2, 0);
    writeU16Test(&bytes, second_mark_array + 4, 8); // Anchor starts exactly at table.length.

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS context lookup preflights later malformed subtable atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6); // Lookup 0: ContextPos with two subtables.
    writeU16Test(&bytes, 14, 30); // Lookup 1: nested SinglePos.

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 2);
    writeU16Test(&bytes, 22, 48);
    writeU16Test(&bytes, 24, 80);
    writeSinglePositionLookup(&bytes, 40, 5, 0, 33);

    const first_context = 64;
    writeU16Test(&bytes, first_context + 0, 1);
    writeU16Test(&bytes, first_context + 2, 22);
    writeU16Test(&bytes, first_context + 4, 1);
    writeU16Test(&bytes, first_context + 6, 8);
    writeU16Test(&bytes, first_context + 8, 1);
    writeU16Test(&bytes, first_context + 10, 4);
    writeU16Test(&bytes, first_context + 12, 1);
    writeU16Test(&bytes, first_context + 14, 1);
    writeU16Test(&bytes, first_context + 16, 0);
    writeU16Test(&bytes, first_context + 18, 1);
    writeCoverage1Test(&bytes, first_context + 22, 5);

    const malformed_context = 96;
    writeU16Test(&bytes, malformed_context + 0, 1);
    writeU16Test(&bytes, malformed_context + 2, 16);
    writeU16Test(&bytes, malformed_context + 4, 1);
    writeU16Test(&bytes, malformed_context + 6, 24);
    writeCoverage1Test(&bytes, malformed_context + 16, 5);
    writeU16Test(&bytes, malformed_context + 24, 1);
    writeU16Test(&bytes, malformed_context + 26, 4);
    writeU16Test(&bytes, malformed_context + 28, 1);
    writeU16Test(&bytes, malformed_context + 30, 2);
    writeU16Test(&bytes, malformed_context + 32, 0);
    writeU16Test(&bytes, malformed_context + 34, 1);
    // The second declared PosLookupRecord begins exactly at table.length below.

    const glyphs = [_]GlyphId{5};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = 132 }, 16, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS context nested lookup can apply pair positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    // PosLookupRecord sequenceIndex=0 intentionally invokes PairPos on the
    // first glyph of the matched input. The nested lookup must still inspect
    // the following glyph in the real run and produce both pair adjustments.
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 1);

    writeU16Test(&bytes, 52, 2);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const pair = 60;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0x0001);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 1);
    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 2);
    writeI16Test(&bytes, pair_set + 4, -50);
    writeI16Test(&bytes, pair_set + 6, 20);

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[1].x_placement);
}

test "GPOS context nested lookup can apply cursive positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 124;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 22);
    // The PosLookupRecord targets sequenceIndex 1. A nested CursivePos must
    // use glyph 20 as the previous cursive glyph, while leaving the unrelated
    // earlier 10-12 join untouched.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 20);

    writeU16Test(&bytes, 52, 3);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const cursive = 60;
    writeU16Test(&bytes, cursive + 0, 1);
    writeU16Test(&bytes, cursive + 2, 22);
    writeU16Test(&bytes, cursive + 4, 4);
    writeU16Test(&bytes, cursive + 6, 0);
    writeU16Test(&bytes, cursive + 8, 34);
    writeU16Test(&bytes, cursive + 10, 40);
    writeU16Test(&bytes, cursive + 12, 0);
    writeU16Test(&bytes, cursive + 14, 0);
    writeU16Test(&bytes, cursive + 16, 46);
    writeU16Test(&bytes, cursive + 18, 52);
    writeU16Test(&bytes, cursive + 20, 0);
    writeCoverage1ListTest(&bytes, cursive + 22, &.{ 10, 12, 20, 22 });
    writeAnchor1Test(&bytes, cursive + 34, 100, 30);
    writeAnchor1Test(&bytes, cursive + 40, 20, 5);
    writeAnchor1Test(&bytes, cursive + 46, 200, 70);
    writeAnchor1Test(&bytes, cursive + 52, 50, 10);

    const glyphs = [_]GlyphId{ 10, 12, 20, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 3), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 150), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 60), adjustments.items[0].y_placement);
}

test "GPOS single positioning subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 24);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 20);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_single = 24;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeI16Test(&bytes, second_single + 6, 30);
    writeCoverage1Test(&bytes, second_single + 8, 10);

    const glyphs = [_]GlyphId{10};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    // Lookup subtables are ordered alternatives. The second overlapping
    // SinglePos subtable must not add another xPlacement after the first match.
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[0].x_placement);
}

test "GPOS pair positioning records precedence when first value is empty" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const pair = 8;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0000); // Empty valueFormat1 is common when only the second glyph moves.
    writeU16Test(&bytes, pair + 6, 0x0001);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 10);

    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 11);
    writeI16Test(&bytes, pair_set + 4, 25);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[1].x_placement);
}

test "GPOS pair positioning subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 44);

    const first_pair = 10;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const second_pair = 44;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // Subtables in a lookup are alternatives. The first matching PairPos
    // subtable wins for this pair; the later matching subtable must not add its
    // xAdvance on top.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS context nested lookup can apply extension positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 1);
    // PosLookupRecord invokes lookup 1, an ExtensionPos wrapping SinglePos, at
    // sequenceIndex 0. Nested extension handling must preserve the context
    // target index rather than ignoring the lookup or applying it globally.
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeCoverage1Test(&bytes, context + 22, 3);

    writeU16Test(&bytes, 52, 9);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const extension = 60;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    writeU32Test(&bytes, extension + 4, 8);
    const single = extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0004);
    writeI16Test(&bytes, single + 6, 70);
    writeCoverage1Test(&bytes, single + 8, 3);

    const glyphs = [_]GlyphId{3};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_advance);
}

test "GPOS chaining coverage nested ExtensionPos SinglePos respects alternatives" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 70);

    writeU16Test(&bytes, 16, 8);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const chaining = 24;
    writeU16Test(&bytes, chaining + 0, 3);
    writeU16Test(&bytes, chaining + 2, 1);
    writeU16Test(&bytes, chaining + 4, 24);
    writeU16Test(&bytes, chaining + 6, 2);
    writeU16Test(&bytes, chaining + 8, 30);
    writeU16Test(&bytes, chaining + 10, 36);
    writeU16Test(&bytes, chaining + 12, 1);
    writeU16Test(&bytes, chaining + 14, 42);
    writeU16Test(&bytes, chaining + 16, 1);
    // Match [10, 11] only when preceded by 7 and followed by 12, then apply
    // lookup 1 to input sequenceIndex 1. The nested lookup contains two
    // ExtensionPos(SinglePos) subtables for glyph 11; the first matching
    // wrapper must win instead of cascading both SinglePos adjustments.
    writeU16Test(&bytes, chaining + 18, 1);
    writeU16Test(&bytes, chaining + 20, 1);
    writeCoverage1Test(&bytes, chaining + 24, 7);
    writeCoverage1Test(&bytes, chaining + 30, 10);
    writeCoverage1Test(&bytes, chaining + 36, 11);
    writeCoverage1Test(&bytes, chaining + 42, 12);

    writeU16Test(&bytes, 80, 9);
    writeU16Test(&bytes, 84, 2);
    writeU16Test(&bytes, 86, 10);
    writeU16Test(&bytes, 88, 32);

    const first_extension = 90;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0004);
    writeI16Test(&bytes, first_single + 6, 40);
    writeCoverage1Test(&bytes, first_single + 8, 11);

    const second_extension = 112;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0004);
    writeI16Test(&bytes, second_single + 6, 90);
    writeCoverage1Test(&bytes, second_single + 8, 11);

    const glyphs = [_]GlyphId{ 7, 10, 11, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 40), adjustments.items[0].x_advance);
}

test "GPOS context nested ExtensionPos PairPos respects alternatives with mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 170;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 54);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 18, 0x0010);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 10);
    writeU16Test(&bytes, 24, 0);

    const context = 26;
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
    writeU16Test(&bytes, rule + 4, 11);
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 64, 9);
    writeU16Test(&bytes, 66, 0x0010);
    writeU16Test(&bytes, 68, 2);
    writeU16Test(&bytes, 70, 12);
    writeU16Test(&bytes, 72, 56);
    writeU16Test(&bytes, 74, 0);

    const first_extension = 76;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const second_extension = 120;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The unselected mark is transparent for both the outer ContextPos match
    // and the wrapped PairPos lookup. Once the first ExtensionPos(PairPos)
    // subtable matches that filtered pair, the second wrapper in the same
    // lookup must remain an alternative rather than adding another adjustment.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS context nested lookup can apply MarkBasePos" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 106;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 12);
    // PosLookupRecord sequenceIndex=1 invokes MarkBasePos on the matched mark.
    // The nested lookup still needs the full run so it can locate glyph 10 as
    // the previous base, but it must not position marks outside this record.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 52, 4);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_base = 60;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 18);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 24);
    writeU16Test(&bytes, mark_base + 10, 36);

    writeCoverage1Test(&bytes, mark_base + 12, 12);
    writeCoverage1Test(&bytes, mark_base + 18, 10);

    const mark_array = mark_base + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const base_array = mark_base + 36;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 80, 120);

    const glyphs = [_]GlyphId{ 10, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].mark_attachment);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].mark_base_index);
}

test "GPOS context nested lookup applies MarkLigPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 22);
    // The context matches only [20, 22], but the nested MarkLigPos subtable
    // also covers the later [21, 22] cluster. PosLookupRecord sequenceIndex=1
    // must therefore attach just the matched mark while still using the full
    // run to find glyph 20 as its preceding ligature.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 20);

    writeU16Test(&bytes, 52, 5);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_lig = 60;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 18);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 26);
    writeU16Test(&bytes, mark_lig + 10, 38);

    writeCoverage1Test(&bytes, mark_lig + 12, 22);
    writeCoverage1ListTest(&bytes, mark_lig + 18, &.{ 20, 21 });

    const mark_array = mark_lig + 26;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const ligature_array = mark_lig + 38;
    writeU16Test(&bytes, ligature_array + 0, 2);
    writeU16Test(&bytes, ligature_array + 2, 6);
    writeU16Test(&bytes, ligature_array + 4, 16);

    const first_ligature_attach = ligature_array + 6;
    writeU16Test(&bytes, first_ligature_attach + 0, 1);
    writeU16Test(&bytes, first_ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, first_ligature_attach + 4, 100, 120);

    const second_ligature_attach = ligature_array + 16;
    writeU16Test(&bytes, second_ligature_attach + 0, 1);
    writeU16Test(&bytes, second_ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, second_ligature_attach + 4, 200, 220);

    const glyphs = [_]GlyphId{ 20, 22, 21, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].mark_attachment);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].mark_base_index);
}

test "GPOS context nested lookup applies MarkToMarkPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 116;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
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
    writeU16Test(&bytes, rule + 4, 12);
    // The matched input is [10, 12], and sequenceIndex=1 targets only that
    // second glyph. A later [13, 12] mark pair is covered by MarkToMarkPos too,
    // so a nested implementation that rescans the entire run would incorrectly
    // attach the final glyph as well.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 52, 6);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_mark = 60;
    writeU16Test(&bytes, mark_mark + 0, 1);
    writeU16Test(&bytes, mark_mark + 2, 12);
    writeU16Test(&bytes, mark_mark + 4, 18);
    writeU16Test(&bytes, mark_mark + 6, 1);
    writeU16Test(&bytes, mark_mark + 8, 26);
    writeU16Test(&bytes, mark_mark + 10, 38);

    writeCoverage1Test(&bytes, mark_mark + 12, 12);
    writeCoverage1ListTest(&bytes, mark_mark + 18, &.{ 10, 13 });

    const mark_1_array = mark_mark + 26;
    writeU16Test(&bytes, mark_1_array + 0, 1);
    writeU16Test(&bytes, mark_1_array + 2, 0);
    writeU16Test(&bytes, mark_1_array + 4, 6);
    writeAnchor1Test(&bytes, mark_1_array + 6, 10, 15);

    const mark_2_array = mark_mark + 38;
    writeU16Test(&bytes, mark_2_array + 0, 2);
    writeU16Test(&bytes, mark_2_array + 2, 6);
    writeU16Test(&bytes, mark_2_array + 4, 12);
    writeAnchor1Test(&bytes, mark_2_array + 6, 80, 120);
    writeAnchor1Test(&bytes, mark_2_array + 12, 200, 220);

    const glyphs = [_]GlyphId{ 10, 12, 13, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].mark_attachment);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].mark_base_index);
}

test "GPOS ExtensionPos single positioning subtables respect mark filtering ordering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 36);
    writeU16Test(&bytes, 10, 0);

    const first_extension = 12;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 25);
    writeCoverage1Test(&bytes, first_single + 8, 5);

    const second_extension = 36;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeI16Test(&bytes, second_single + 6, 40);
    writeCoverage1Test(&bytes, second_single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{5}, &.{7} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    // Homogeneous ExtensionPos(SinglePos) subtables must behave like direct
    // SinglePos alternatives: the first matching wrapper wins for the original
    // mark, while the unselected mark filtering-set member remains transparent.
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[0].x_placement);
}

test "GPOS mixed ExtensionPos PairPos alternatives respect mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 3);
    writeU16Test(&bytes, 6, 14);
    writeU16Test(&bytes, 8, 58);
    writeU16Test(&bytes, 10, 82);
    writeU16Test(&bytes, 12, 0);

    const first_extension = 14;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const middle_extension = 58;
    writeU16Test(&bytes, middle_extension + 0, 1);
    writeU16Test(&bytes, middle_extension + 2, 1);
    writeU32Test(&bytes, middle_extension + 4, 8);
    const single = middle_extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 25);
    writeCoverage1Test(&bytes, single + 8, 99);

    const second_extension = 82;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    var mark_attach_classes = [_]u16{0} ** 13;
    mark_attach_classes[12] = 2;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The middle ExtensionPos(SinglePos) makes the lookup heterogeneous, so it
    // cannot use the homogeneous PairPos fast path. PairPos wrappers are still
    // ordered alternatives for glyph 10, and mark filtering keeps glyph 12
    // transparent when searching for the second glyph of the pair.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS extension positioning preserves wrapper lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0008);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const extension = 8;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    writeU32Test(&bytes, extension + 4, 8);

    const single = extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 50);
    writeCoverage1Test(&bytes, single + 8, 3);

    const glyphs = [_]GlyphId{3};
    const glyph_classes = [_]u16{ 0, 1, 2, 3 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS mark-to-ligature uses source metadata for component choice" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 5);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_lig = 8;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 18);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 24);
    writeU16Test(&bytes, mark_lig + 10, 36);

    writeCoverage1Test(&bytes, mark_lig + 12, 22);
    writeCoverage1Test(&bytes, mark_lig + 18, 20);

    const mark_array = mark_lig + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const ligature_array = mark_lig + 36;
    writeU16Test(&bytes, ligature_array + 0, 1);
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 2);
    writeU16Test(&bytes, ligature_attach + 2, 8);
    writeU16Test(&bytes, ligature_attach + 4, 14);
    writeAnchor1Test(&bytes, ligature_attach + 8, 100, 120);
    writeAnchor1Test(&bytes, ligature_attach + 14, 260, 300);

    const glyphs = [_]GlyphId{ 20, 22 };
    const sources = [_]usize{ 0, 2 };
    const ligature_components = [_]LigatureComponentInfo{
        .{
            .component_count = 2,
            .component_sources = blk: {
                var component_sources = [_]usize{0} ** max_ligature_components;
                component_sources[0] = 0;
                component_sources[1] = 1;
                break :blk component_sources;
            },
        },
        .{},
    };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_source_indices = &sources,
        .ligature_components = &ligature_components,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    // This is the first mark after the ligature in the post-GSUB stream, so
    // the mark-order fallback would choose component 0. Source metadata shows
    // that it originated after the second component's source position, so it
    // must use component 1.
    try std.testing.expectEqual(@as(i16, 250), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 285), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].mark_base_index);
}

test "GPOS mark-to-ligature attachment skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 5);
    writeU16Test(&bytes, 2, 0x0002); // IgnoreBaseGlyphs between the ligature and mark.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_lig = 8;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 18);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 24);
    writeU16Test(&bytes, mark_lig + 10, 44);

    writeCoverage1Test(&bytes, mark_lig + 12, 22);
    writeCoverage1Test(&bytes, mark_lig + 18, 20);

    const mark_array = mark_lig + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 8);
    writeAnchor1Test(&bytes, mark_array + 8, 0, 0);

    const ligature_array = mark_lig + 44;
    writeU16Test(&bytes, ligature_array + 0, 1);
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 1);
    writeU16Test(&bytes, ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, ligature_attach + 4, 100, 120);

    const glyphs = [_]GlyphId{ 20, 21, 22 };
    var glyph_classes = [_]u16{0} ** 23;
    glyph_classes[20] = 2;
    glyph_classes[21] = 1;
    glyph_classes[22] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 120), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].mark_base_index);
}

test "GPOS mark-to-ligature selects component anchors from mark order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 104;

    writeU16Test(&bytes, 0, 5);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_lig = 8;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 20);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 26);
    writeU16Test(&bytes, mark_lig + 10, 54);

    writeCoverage1ListTest(&bytes, mark_lig + 12, &.{ 22, 23 });
    writeCoverage1Test(&bytes, mark_lig + 20, 20);

    const mark_array = mark_lig + 26;
    writeU16Test(&bytes, mark_array + 0, 2);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 10);
    writeU16Test(&bytes, mark_array + 6, 0);
    writeU16Test(&bytes, mark_array + 8, 16);
    writeAnchor1Test(&bytes, mark_array + 10, 0, 0);
    writeAnchor1Test(&bytes, mark_array + 16, 0, 0);

    const ligature_array = mark_lig + 54;
    writeU16Test(&bytes, ligature_array + 0, 1);
    writeU16Test(&bytes, ligature_array + 2, 4);
    const ligature_attach = ligature_array + 4;
    writeU16Test(&bytes, ligature_attach + 0, 2);
    writeU16Test(&bytes, ligature_attach + 2, 6);
    writeU16Test(&bytes, ligature_attach + 4, 12);
    writeAnchor1Test(&bytes, ligature_attach + 6, 100, 110);
    writeAnchor1Test(&bytes, ligature_attach + 12, 300, 330);

    const glyphs = [_]GlyphId{ 20, 22, 23 };
    var glyph_classes = [_]u16{0} ** 24;
    glyph_classes[20] = 2;
    glyph_classes[22] = 3;
    glyph_classes[23] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 100), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 110), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].mark_base_index);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 300), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, 330), adjustments.items[1].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[1].mark_base_index);
}

test "GPOS mark-to-mark attachment skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 6);
    writeU16Test(&bytes, 2, 0x0002); // IgnoreBaseGlyphs between the two marks.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_mark = 8;
    writeU16Test(&bytes, mark_mark + 0, 1);
    writeU16Test(&bytes, mark_mark + 2, 12);
    writeU16Test(&bytes, mark_mark + 4, 18);
    writeU16Test(&bytes, mark_mark + 6, 1);
    writeU16Test(&bytes, mark_mark + 8, 24);
    writeU16Test(&bytes, mark_mark + 10, 44);

    writeCoverage1Test(&bytes, mark_mark + 12, 12);
    writeCoverage1Test(&bytes, mark_mark + 18, 10);

    const mark_1_array = mark_mark + 24;
    writeU16Test(&bytes, mark_1_array + 0, 1);
    writeU16Test(&bytes, mark_1_array + 2, 0);
    writeU16Test(&bytes, mark_1_array + 4, 8);
    writeAnchor1Test(&bytes, mark_1_array + 8, 0, 0);

    const mark_2_array = mark_mark + 44;
    writeU16Test(&bytes, mark_2_array + 0, 1);
    writeU16Test(&bytes, mark_2_array + 2, 6);
    writeAnchor1Test(&bytes, mark_2_array + 6, 50, 70);

    const glyphs = [_]GlyphId{ 10, 11, 12 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[10] = 3;
    glyph_classes[11] = 1;
    glyph_classes[12] = 3;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 50), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].mark_base_index);
}

fn writeSinglePositionLookup(bytes: []u8, lookup_offset: usize, glyph: GlyphId, lookup_flag: u16, x_placement: i16) void {
    writeU16Test(bytes, lookup_offset + 0, 1);
    writeU16Test(bytes, lookup_offset + 2, lookup_flag);
    writeU16Test(bytes, lookup_offset + 4, 1);
    writeU16Test(bytes, lookup_offset + 6, 8);

    const single = lookup_offset + 8;
    writeU16Test(bytes, single + 0, 1);
    writeU16Test(bytes, single + 2, 8);
    writeU16Test(bytes, single + 4, 0x0001);
    writeI16Test(bytes, single + 6, x_placement);
    writeCoverage1Test(bytes, single + 8, glyph);
}

fn writeCoverage1Test(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, glyph);
}

fn writeCoverage1ListTest(bytes: []u8, offset: usize, glyphs: []const GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, i| {
        writeU16Test(bytes, offset + 4 + i * 2, glyph);
    }
}

fn writeAnchor1Test(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeI16Test(bytes, offset + 2, x);
    writeI16Test(bytes, offset + 4, y);
}

fn writeRequiredFeatureSelectionTable(bytes: []u8, required_tag: u32, optional_tag: u32) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 34);
    writeU16Test(bytes, 8, 60);

    writeU16Test(bytes, 10, 1);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 8);

    writeU16Test(bytes, 18, 4);
    writeU16Test(bytes, 20, 0);
    writeU16Test(bytes, 22, 0);
    writeU16Test(bytes, 24, 0); // ReqFeatureIndex: feature 0.
    writeU16Test(bytes, 26, 1);
    writeU16Test(bytes, 28, 1); // Ordinary FeatureIndex[]: feature 1.

    writeU16Test(bytes, 34, 2);
    writeFeatureRecordTest(bytes, 36, required_tag, 14);
    writeFeatureRecordTest(bytes, 42, optional_tag, 20);
    writeFeatureTest(bytes, 48, 0);
    writeFeatureTest(bytes, 54, 1);

    writeU16Test(bytes, 60, 2);
    writeU16Test(bytes, 62, 0);
    writeU16Test(bytes, 64, 0);
}

fn writeFeatureRecordTest(bytes: []u8, offset: usize, tag_value: u32, feature_offset: u16) void {
    writeU32Test(bytes, offset, tag_value);
    writeU16Test(bytes, offset + 4, feature_offset);
}

fn writeFeatureTest(bytes: []u8, offset: usize, lookup_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, lookup_index);
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
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
