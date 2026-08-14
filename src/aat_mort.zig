const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gsub = @import("gsub.zig");
const state_table = @import("aat_morx/state_table.zig");

pub const Error = error{ BadSfnt, InvalidShapingInput } || std.mem.Allocator.Error || error{EndOfStream};

pub fn validate(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
) Error!void {
    if (table_offset > data.len or table_length > data.len - table_offset or table_length < 8) return error.BadSfnt;
    if (try readU32(data, table_offset) != 0x0001_0000) return error.BadSfnt;
    const chain_count: usize = @intCast(try readU32(data, table_offset + 4));
    var chain_relative: usize = 8;
    for (0..chain_count) |_| {
        if (chain_relative > table_length or table_length - chain_relative < 12) return error.BadSfnt;
        const chain_start = table_offset + chain_relative;
        const chain_length: usize = @intCast(try readU32(data, chain_start + 4));
        const feature_count: usize = try readU16(data, chain_start + 8);
        const subtable_count: usize = try readU16(data, chain_start + 10);
        if (chain_length < 12 or chain_length > table_length - chain_relative) return error.BadSfnt;
        const feature_bytes = std.math.mul(usize, feature_count, 12) catch return error.BadSfnt;
        if (feature_bytes > chain_length - 12) return error.BadSfnt;

        var subtable_relative = chain_relative + 12 + feature_bytes;
        const chain_end = chain_relative + chain_length;
        for (0..subtable_count) |_| {
            if (subtable_relative > chain_end or chain_end - subtable_relative < 8) return error.BadSfnt;
            const subtable_start = table_offset + subtable_relative;
            const subtable_length: usize = try readU16(data, subtable_start);
            const format: u8 = @intCast((try readU16(data, subtable_start + 2)) & 0xff);
            if (subtable_length < 8 or subtable_length > chain_end - subtable_relative) return error.BadSfnt;
            switch (format) {
                4 => try state_table.validateLookupU16(
                    data,
                    subtable_start + 8,
                    subtable_length - 8,
                    glyph_count,
                ),
                0, 1, 2, 5 => {},
                else => return error.BadSfnt,
            }
            subtable_relative += subtable_length;
        }
        if (subtable_relative > chain_end) return error.BadSfnt;
        chain_relative += chain_length;
    }
    if (chain_relative > table_length) return error.BadSfnt;
}

/// Apply the supported subset of the legacy AAT `mort` table.
///
/// `mort` predates `morx`: chain and subtable lengths/counts are 16-bit and
/// coverage is an 8-bit flag byte packed above the subtable type. The deployed
/// Honoka Mincho face motivating this path uses only type-4 noncontextual
/// substitution. Stateful obsolete formats remain intentionally unsupported;
/// accepting their structure without executing it would be worse than exposing
/// the current, explicit coverage boundary.
pub fn apply(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    try validateParallelMetadata(glyphs.items.len, options);
    try validate(data, table_offset, table_length, glyph_count);
    const chain_count: usize = @intCast(try readU32(data, table_offset + 4));

    var chain_relative: usize = 8;
    for (0..chain_count) |_| {
        if (chain_relative > table_length or table_length - chain_relative < 12) return error.BadSfnt;
        const chain_start = table_offset + chain_relative;
        const default_flags = try readU32(data, chain_start);
        const chain_length: usize = @intCast(try readU32(data, chain_start + 4));
        const feature_count: usize = try readU16(data, chain_start + 8);
        const subtable_count: usize = try readU16(data, chain_start + 10);
        if (chain_length < 12 or chain_length > table_length - chain_relative) return error.BadSfnt;
        const feature_bytes = std.math.mul(usize, feature_count, 12) catch return error.BadSfnt;
        if (feature_bytes > chain_length - 12) return error.BadSfnt;

        // The full AAT feature map will eventually fold caller-selected feature
        // types/settings. For the initial production path, chain default flags
        // are authoritative; Honoka's vertical substitution is enabled by
        // default and feature records only describe optional overrides.
        const flags = default_flags;
        var subtable_relative = chain_relative + 12 + feature_bytes;
        const chain_end = chain_relative + chain_length;
        for (0..subtable_count) |_| {
            if (subtable_relative > chain_end or chain_end - subtable_relative < 8) return error.BadSfnt;
            const subtable_start = table_offset + subtable_relative;
            const subtable_length: usize = try readU16(data, subtable_start);
            const coverage = try readU16(data, subtable_start + 2);
            const sub_feature_flags = try readU32(data, subtable_start + 4);
            if (subtable_length < 8 or subtable_length > chain_end - subtable_relative) return error.BadSfnt;

            if ((flags & sub_feature_flags) != 0) {
                const coverage_flags: u8 = @intCast(coverage >> 8);
                const vertical = (coverage_flags & 0x80) != 0;
                const all_directions = (coverage_flags & 0x20) != 0;
                if (all_directions or vertical == options.vertical) {
                    switch (@as(u8, @intCast(coverage & 0xff))) {
                        4 => try applyNoncontextual(
                            data,
                            subtable_start + 8,
                            subtable_length - 8,
                            glyph_count,
                            glyphs,
                            options,
                        ),
                        // Obsolete state-table formats use different class and
                        // offset bases from their morx successors. Keep them
                        // inert until each executor has dedicated fixtures.
                        0, 1, 2, 5 => {},
                        else => return error.BadSfnt,
                    }
                }
            }
            subtable_relative += subtable_length;
        }
        if (subtable_relative > chain_end) return error.BadSfnt;
        chain_relative += chain_length;
    }
    if (chain_relative > table_length) return error.BadSfnt;
}

fn applyNoncontextual(
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
) Error!void {
    if (length < 2) return error.BadSfnt;
    try state_table.validateLookupU16(data, offset, length, glyph_count);
    for (glyphs.items, 0..) |*glyph, index| {
        const replacement = (try state_table.lookupGlyphValueBounded(
            data,
            offset,
            length,
            glyph.*,
            glyph_count,
        )) orelse continue;
        if (replacement >= glyph_count) return error.BadSfnt;
        glyph.* = replacement;
        if (options.glyph_substituted) |substituted| substituted.items[index] = true;
        if (options.glyph_stage_substituted) |substituted| substituted.items[index] = true;
    }
}

fn validateParallelMetadata(glyph_count: usize, options: gsub.LookupOptions) Error!void {
    if (options.glyph_source_indices) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.glyph_cluster_indices) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.glyph_substituted) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.glyph_stage_substituted) |values| if (values.items.len != glyph_count) return error.InvalidShapingInput;
    if (options.ligature_components) |store| {
        if (store.infos.items.len != glyph_count or !store.isValid()) return error.InvalidShapingInput;
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

test "legacy mort noncontextual substitutions update glyph metadata" {
    var bytes = [_]u8{0} ** 42;
    std.mem.writeInt(u32, bytes[0..4], 0x0001_0000, .big);
    std.mem.writeInt(u32, bytes[4..8], 1, .big);
    std.mem.writeInt(u32, bytes[8..12], 1, .big);
    std.mem.writeInt(u32, bytes[12..16], 34, .big);
    std.mem.writeInt(u16, bytes[16..18], 0, .big);
    std.mem.writeInt(u16, bytes[18..20], 1, .big);
    std.mem.writeInt(u16, bytes[20..22], 22, .big);
    std.mem.writeInt(u16, bytes[22..24], 0x2004, .big);
    std.mem.writeInt(u32, bytes[24..28], 1, .big);
    // Lookup format 8: glyph 1 -> glyph 2.
    std.mem.writeInt(u16, bytes[28..30], 8, .big);
    std.mem.writeInt(u16, bytes[30..32], 1, .big);
    std.mem.writeInt(u16, bytes[32..34], 1, .big);
    std.mem.writeInt(u16, bytes[34..36], 2, .big);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 1);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.append(std.testing.allocator, false);

    try apply(&bytes, 0, bytes.len, 3, &glyphs, .{ .glyph_substituted = &substituted });
    try std.testing.expectEqual(@as(GlyphId, 2), glyphs.items[0]);
    try std.testing.expect(substituted.items[0]);
}
