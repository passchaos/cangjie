const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gsub = @import("gsub.zig");
const ligature_provenance = @import("ligature_provenance.zig");
const shaping_metadata = @import("shaping_metadata.zig");
const rearrangement = @import("aat_morx/rearrangement.zig");
const state_table = @import("aat_morx/state_table.zig");

const Error = error{ BadSfnt, InvalidShapingInput } || std.mem.Allocator.Error || error{EndOfStream};

const set_component: u16 = 0x8000;
const perform_action: u16 = 0x2000;

const lig_action_last: u32 = 0x8000_0000;
const lig_action_store: u32 = 0x4000_0000;
const lig_action_offset: u32 = 0x3fff_ffff;
const lig_action_sign_bit: u32 = 0x2000_0000;

const max_ligature_matches = ligature_provenance.max_components;

pub fn apply(
    allocator: std.mem.Allocator,
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    try validateParallelMetadata(glyphs.items.len, options);
    if (table_offset > data.len or table_length > data.len - table_offset or table_length < 8) return error.BadSfnt;
    const version = try readU16(data, table_offset);
    if (version != 2 and version != 3) return error.BadSfnt;
    if (try readU16(data, table_offset + 2) != 0) return error.BadSfnt;
    const chain_count = try readU32(data, table_offset + 4);
    var chain_offset: usize = 8;
    var chain_index: u32 = 0;
    while (chain_index < chain_count) : (chain_index += 1) {
        if (chain_offset > table_length or table_length - chain_offset < 16) return error.BadSfnt;
        const absolute_chain = table_offset + chain_offset;
        const default_flags = try readU32(data, absolute_chain);
        const chain_length: usize = @intCast(try readU32(data, absolute_chain + 4));
        const feature_count: usize = @intCast(try readU32(data, absolute_chain + 8));
        const subtable_count: usize = @intCast(try readU32(data, absolute_chain + 12));
        if (chain_length < 16 or chain_length > table_length - chain_offset or (chain_length & 3) != 0) return error.BadSfnt;

        const flags = default_flags;

        var subtable_offset = chain_offset + 16 + feature_count * 12;
        var subtable_index: usize = 0;
        while (subtable_index < subtable_count) : (subtable_index += 1) {
            if (subtable_offset > chain_offset + chain_length or chain_offset + chain_length - subtable_offset < 12) return error.BadSfnt;
            const absolute_subtable = table_offset + subtable_offset;
            const subtable_length: usize = @intCast(try readU32(data, absolute_subtable));
            const coverage = try readU32(data, absolute_subtable + 4);
            const sub_feature_flags = try readU32(data, absolute_subtable + 8);
            if (subtable_length < 12 or subtable_length > chain_offset + chain_length - subtable_offset) return error.BadSfnt;
            if ((flags & sub_feature_flags) != 0) {
                switch (coverage & 0xff) {
                    0 => try rearrangement.apply(
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyphs,
                        options,
                    ),
                    2 => try applyLigatureSubtable(
                        allocator,
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyphs,
                        options,
                    ),
                    4 => try applyNoncontextualSubtable(
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyphs,
                        options,
                    ),
                    else => {},
                }
            }
            subtable_offset += subtable_length;
        }
        chain_offset += chain_length;
    }
    if (chain_offset > table_length) return error.BadSfnt;
}

fn validateParallelMetadata(glyph_count: usize, options: gsub.LookupOptions) Error!void {
    if (options.glyph_source_indices) |values| {
        if (values.items.len != glyph_count) return error.InvalidShapingInput;
    }
    if (options.glyph_cluster_indices) |values| {
        if (values.items.len != glyph_count) return error.InvalidShapingInput;
    }
    if (options.glyph_substituted) |values| {
        if (values.items.len != glyph_count) return error.InvalidShapingInput;
    }
    if (options.glyph_stage_substituted) |values| {
        if (values.items.len != glyph_count) return error.InvalidShapingInput;
    }
    if (options.ligature_components) |store| {
        if (store.infos.items.len != glyph_count or !store.isValid()) return error.InvalidShapingInput;
    }
}

fn applyNoncontextualSubtable(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    if (length < 2) return error.BadSfnt;
    for (glyphs.items, 0..) |*glyph, index| {
        const replacement = (try state_table.lookupGlyphValue(data, offset, length, glyph.*)) orelse continue;
        glyph.* = replacement;
        if (options.glyph_substituted) |substituted| {
            if (index < substituted.items.len) substituted.items[index] = true;
        }
        if (options.glyph_stage_substituted) |substituted| {
            if (index < substituted.items.len) substituted.items[index] = true;
        }
    }
}

fn applyLigatureSubtable(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    if (length < 28) return error.BadSfnt;
    const class_count: usize = @intCast(try readU32(data, offset));
    const class_table_offset: usize = @intCast(try readU32(data, offset + 4));
    const state_array_offset: usize = @intCast(try readU32(data, offset + 8));
    const entry_table_offset: usize = @intCast(try readU32(data, offset + 12));
    const lig_action_offset_abs: usize = @intCast(try readU32(data, offset + 16));
    const component_offset: usize = @intCast(try readU32(data, offset + 20));
    const ligature_offset: usize = @intCast(try readU32(data, offset + 24));
    if (class_count == 0) return;
    if (class_table_offset > length or state_array_offset > length or entry_table_offset > length or
        lig_action_offset_abs > length or component_offset > length or ligature_offset > length)
    {
        return error.BadSfnt;
    }

    var out_glyphs = std.ArrayList(GlyphId).empty;
    defer out_glyphs.deinit(allocator);
    var out_sources = std.ArrayList(usize).empty;
    defer out_sources.deinit(allocator);
    var out_clusters = std.ArrayList(usize).empty;
    defer out_clusters.deinit(allocator);
    var out_substituted = std.ArrayList(bool).empty;
    defer out_substituted.deinit(allocator);
    var out_ligatures = ligature_provenance.Store{};
    defer out_ligatures.deinit(allocator);

    var state: usize = 0;
    var index: usize = 0;
    var match_len: usize = 0;
    var match_positions: [max_ligature_matches]usize = undefined;

    while (true) {
        const class = if (index < glyphs.items.len)
            try ligatureClassForGlyph(data, offset, length, class_table_offset, glyphs.items[index])
        else
            state_table.class_end_of_text;
        const entry = try stateEntry(data, offset, length, state_array_offset, entry_table_offset, class_count, state, class);
        if (entry.flags & set_component != 0 and index < glyphs.items.len) {
            if (match_len != 0 and match_positions[(match_len - 1) % max_ligature_matches] == out_glyphs.items.len) {
                match_len -= 1;
            }
            match_positions[match_len % max_ligature_matches] = out_glyphs.items.len;
            match_len += 1;
        }

        if (index < glyphs.items.len) {
            try appendGlyph(allocator, &out_glyphs, &out_sources, &out_clusters, &out_substituted, &out_ligatures, glyphs, options, index);
        }

        if (entry.flags & perform_action != 0) {
            try performLigatureAction(
                allocator,
                data,
                offset,
                length,
                lig_action_offset_abs,
                component_offset,
                ligature_offset,
                &out_glyphs,
                &out_sources,
                &out_clusters,
                &out_substituted,
                &out_ligatures,
                entry.payload,
                &match_len,
                &match_positions,
            );
        }

        state = entry.new_state;
        if (index >= glyphs.items.len) break;
        if (entry.flags & state_table.dont_advance == 0) index += 1;
    }

    try replaceRun(allocator, glyphs, options, out_glyphs.items, out_sources.items, out_clusters.items, out_substituted.items, &out_ligatures);
}

fn stateEntry(data: []const u8, offset: usize, length: usize, state_array_offset: usize, entry_table_offset: usize, class_count: usize, state: usize, class: u16) Error!state_table.Entry {
    return state_table.entry(data, offset, length, state_array_offset, entry_table_offset, class_count, state, class, 6);
}

fn ligatureClassForGlyph(data: []const u8, offset: usize, length: usize, class_table_offset: usize, glyph: GlyphId) Error!u16 {
    if (glyph == 0xffff) return state_table.class_deleted_glyph;
    if (class_table_offset > length) return error.BadSfnt;
    const lookup = offset + class_table_offset;

    // The existing out-buffer ligature executor is validated for trimmed
    // format-8 class tables. Sparse format-6 machines can take epsilon
    // transitions after mutating the current glyph, which requires an in-place
    // driver; treating those glyphs as out-of-bounds preserves the previously
    // verified behavior until that executor is implemented rather than
    // duplicating the current glyph on DontAdvance transitions.
    if (try readU16(data, lookup) != 8) return state_table.class_out_of_bounds;
    return (try state_table.lookupGlyphValue(data, lookup, length - class_table_offset, glyph)) orelse state_table.class_out_of_bounds;
}

fn appendGlyph(
    allocator: std.mem.Allocator,
    out_glyphs: *std.ArrayList(GlyphId),
    out_sources: *std.ArrayList(usize),
    out_clusters: *std.ArrayList(usize),
    out_substituted: *std.ArrayList(bool),
    out_ligatures: *ligature_provenance.Store,
    glyphs: *const std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    index: usize,
) Error!void {
    try out_glyphs.append(allocator, glyphs.items[index]);
    if (options.glyph_source_indices) |sources| {
        try out_sources.append(allocator, if (index < sources.items.len) sources.items[index] else index);
    }
    if (options.glyph_cluster_indices) |clusters| {
        try out_clusters.append(allocator, if (index < clusters.items.len) clusters.items[index] else index);
    }
    if (options.glyph_substituted) |substituted| {
        try out_substituted.append(allocator, index < substituted.items.len and substituted.items[index]);
    }
    if (options.ligature_components) |store| {
        try out_ligatures.infos.append(allocator, if (index < store.infos.items.len) store.infos.items[index] else .{});
    }
}

fn performLigatureAction(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    lig_action_offset_abs: usize,
    component_offset: usize,
    ligature_offset: usize,
    out_glyphs: *std.ArrayList(GlyphId),
    out_sources: *std.ArrayList(usize),
    out_clusters: *std.ArrayList(usize),
    out_substituted: *std.ArrayList(bool),
    out_ligatures: *ligature_provenance.Store,
    payload: u16,
    match_len: *usize,
    match_positions: *[max_ligature_matches]usize,
) Error!void {
    if (match_len.* == 0) return;
    var cursor = match_len.*;
    var action_index: usize = payload;
    var ligature_index: usize = 0;
    var store_position: ?usize = null;

    while (true) {
        if (cursor == 0) {
            match_len.* = 0;
            return;
        }
        cursor -= 1;
        const position = match_positions.*[cursor % max_ligature_matches];
        if (position >= out_glyphs.items.len) return error.BadSfnt;
        const action_offset = offset + lig_action_offset_abs + action_index * 4;
        if (action_offset > offset + length or offset + length - action_offset < 4) return error.BadSfnt;
        const action = try readU32(data, action_offset);
        var uoffset = action & lig_action_offset;
        if ((uoffset & lig_action_sign_bit) != 0) uoffset |= 0xc000_0000;
        const delta: i32 = @bitCast(uoffset);
        const component_index_i64 = @as(i64, out_glyphs.items[position]) + @as(i64, delta);
        if (component_index_i64 < 0) return error.BadSfnt;
        const component_index: usize = @intCast(component_index_i64);
        const component_value_offset = offset + component_offset + component_index * 2;
        if (component_value_offset > offset + length or offset + length - component_value_offset < 2) return error.BadSfnt;
        ligature_index += try readU16(data, component_value_offset);

        if ((action & (lig_action_store | lig_action_last)) != 0) {
            const ligature_value_offset = offset + ligature_offset + ligature_index * 2;
            if (ligature_value_offset > offset + length or offset + length - ligature_value_offset < 2) return error.BadSfnt;
            out_glyphs.items[position] = try readU16(data, ligature_value_offset);
            if (position < out_substituted.items.len) out_substituted.items[position] = true;
            store_position = position;
        }
        action_index += 1;
        if ((action & lig_action_last) != 0) break;
    }

    const first = match_positions.*[cursor % max_ligature_matches];
    const last = match_positions.*[(match_len.* - 1) % max_ligature_matches];
    const ligature_pos = store_position orelse first;
    if (first >= out_glyphs.items.len or last >= out_glyphs.items.len or first > last or ligature_pos > last) return error.BadSfnt;
    if (out_clusters.items.len == out_glyphs.items.len) {
        shaping_metadata.mergeMonotoneClusters(out_clusters.items, first, last + 1);
    }
    if (out_ligatures.infos.items.len == out_glyphs.items.len and out_sources.items.len == out_glyphs.items.len) {
        var component_sources: [max_ligature_matches]usize = undefined;
        const count = last - first + 1;
        if (count > component_sources.len) return error.BadSfnt;
        for (0..count) |i| component_sources[i] = out_sources.items[first + i];
        out_ligatures.infos.items[ligature_pos] = try out_ligatures.addLigature(allocator, component_sources[0..count]);
    }

    var remove_cursor = match_len.*;
    while (remove_cursor > cursor) {
        remove_cursor -= 1;
        const remove_index = match_positions.*[remove_cursor % max_ligature_matches];
        if (remove_index == ligature_pos) continue;
        _ = out_glyphs.orderedRemove(remove_index);
        if (out_sources.items.len > remove_index) _ = out_sources.orderedRemove(remove_index);
        if (out_clusters.items.len > remove_index) _ = out_clusters.orderedRemove(remove_index);
        if (out_substituted.items.len > remove_index) _ = out_substituted.orderedRemove(remove_index);
        if (out_ligatures.infos.items.len > remove_index) _ = out_ligatures.infos.orderedRemove(remove_index);
    }
    match_len.* = first;
}

fn replaceRun(
    allocator: std.mem.Allocator,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    new_glyphs: []const GlyphId,
    new_sources: []const usize,
    new_clusters: []const usize,
    new_substituted: []const bool,
    new_ligatures: *const ligature_provenance.Store,
) Error!void {
    try glyphs.replaceRange(allocator, 0, glyphs.items.len, new_glyphs);
    if (options.glyph_source_indices) |sources| try sources.replaceRange(allocator, 0, sources.items.len, new_sources);
    if (options.glyph_cluster_indices) |clusters| try clusters.replaceRange(allocator, 0, clusters.items.len, new_clusters);
    if (options.glyph_substituted) |substituted| try substituted.replaceRange(allocator, 0, substituted.items.len, new_substituted);
    if (options.ligature_components) |store| {
        store.clear();
        try store.sources.appendSlice(allocator, new_ligatures.sources.items);
        try store.infos.appendSlice(allocator, new_ligatures.infos.items);
    }
}

fn readU16(data: []const u8, offset: usize) Error!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 4) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}
