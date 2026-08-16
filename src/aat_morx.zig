const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gsub = @import("gsub.zig");
const contextual = @import("aat_morx/contextual.zig");
const insertion = @import("aat_morx/insertion.zig");
const ligature = @import("aat_morx/ligature.zig");
const rearrangement = @import("aat_morx/rearrangement.zig");
const run_metadata = @import("aat_morx/run_metadata.zig");
const state_table = @import("aat_morx/state_table.zig");

const Error = error{ BadSfnt, InvalidShapingInput } || std.mem.Allocator.Error || error{EndOfStream};

pub fn apply(
    allocator: std.mem.Allocator,
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
) Error!void {
    try validateParallelMetadata(glyphs.items.len, options);
    if (table_offset > data.len or table_length > data.len - table_offset or table_length < 8) return error.BadSfnt;
    const version = try readU16(data, table_offset);
    if (version != 2 and version != 3) return error.BadSfnt;
    if (try readU16(data, table_offset + 2) != 0) return error.BadSfnt;
    const chain_count = try readU32(data, table_offset + 4);
    var operations_left = try state_table.operationBudget(glyphs.items.len);
    var buffer_is_reversed = options.aat_buffer_reversed;
    defer if (buffer_is_reversed != options.aat_buffer_reversed) {
        run_metadata.reverse(glyphs, options);
    };
    var chain_offset: usize = 8;
    var chain_index: u32 = 0;
    while (chain_index < chain_count) : (chain_index += 1) {
        if (chain_offset > table_length or table_length - chain_offset < 16) return error.BadSfnt;
        const absolute_chain = table_offset + chain_offset;
        const default_flags = try readU32(data, absolute_chain);
        const chain_length: usize = @intCast(try readU32(data, absolute_chain + 4));
        const feature_count: usize = @intCast(try readU32(data, absolute_chain + 8));
        const subtable_count: usize = @intCast(try readU32(data, absolute_chain + 12));
        if (chain_length < 16 or chain_length > table_length - chain_offset) return error.BadSfnt;

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
                const vertical = (coverage & 0x80000000) != 0;
                const all_directions = (coverage & 0x20000000) != 0;
                if (!all_directions and vertical != options.vertical) {
                    subtable_offset += subtable_length;
                    continue;
                }
                const reverse = if ((coverage & 0x10000000) != 0)
                    (coverage & 0x40000000) != 0
                else
                    ((coverage & 0x40000000) != 0) != (options.text_direction == .rtl);
                if (reverse != buffer_is_reversed) {
                    run_metadata.reverse(glyphs, options);
                    buffer_is_reversed = reverse;
                }
                switch (coverage & 0xff) {
                    0 => try rearrangement.apply(
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyphs,
                        options,
                        &operations_left,
                    ),
                    1 => try contextual.apply(
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyph_count,
                        glyphs,
                        options,
                        &operations_left,
                    ),
                    2 => try ligature.applyExtended(
                        allocator,
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyph_count,
                        glyphs,
                        options,
                        &operations_left,
                    ),
                    4 => try applyNoncontextualSubtable(
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyphs,
                        options,
                    ),
                    5 => try insertion.apply(
                        allocator,
                        data,
                        absolute_subtable + 12,
                        subtable_length - 12,
                        glyph_count,
                        glyphs,
                        options,
                        &operations_left,
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

fn validateParallelMetadata(glyph_count: usize, options: gsub.runtime.Options) Error!void {
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
    options: gsub.runtime.Options,
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

fn readU16(data: []const u8, offset: usize) Error!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 4) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}
