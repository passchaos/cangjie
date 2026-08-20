//! GDEF LigCaretList lookup and CaretValue decoding.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const glyph_mod = @import("../../../../glyph.zig");
const metric_variation = @import("../../../../opentype/metric_variation.zig");
const sfnt = @import("../../../sfnt/root.zig");
const coverage = @import("coverage.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error ||
    metric_variation.Error ||
    std.mem.Allocator.Error ||
    error{
        EndOfStream,
        UnavailableContourPoint,
        NonCanonicalCaretOrder,
    };

pub const ContourPointResolver = *const fn (
    context: *const anyopaque,
    glyph_id: glyph_mod.GlyphId,
    point_index: u16,
    normalized_coords: []const f32,
) Error!?f32;

pub const Options = struct {
    normalized_coords: []const f32 = &.{},
    item_variation_store_offset: ?usize = null,
    contour_context: ?*const anyopaque = null,
    resolve_contour_point: ?ContourPointResolver = null,
};

/// Read all authored horizontal caret positions for one ligature glyph.
///
/// The returned values are design-unit coordinates from the glyph's horizontal
/// origin. Ordinary Device tables are intentionally ignored because this is a
/// resolution-independent font API; VariationIndex records are evaluated
/// against GDEF 1.3's ItemVariationStore. Resolved positions must be strictly
/// increasing; `NonCanonicalCaretOrder` lets higher layers decline the optional
/// metadata without treating an otherwise usable font as malformed.
pub fn read(
    allocator: std.mem.Allocator,
    data: []const u8,
    lig_caret_list_offset: usize,
    glyph_id: glyph_mod.GlyphId,
    options: Options,
) Error![]types.LigatureCaret {
    if (lig_caret_list_offset > data.len or
        data.len - lig_caret_list_offset < 4)
    {
        return error.BadSfnt;
    }
    const coverage_relative = try bin.readU16At(
        data,
        lig_caret_list_offset,
    );
    const ligature_count = try bin.readU16At(
        data,
        lig_caret_list_offset + 2,
    );
    const offsets_start = lig_caret_list_offset + 4;
    if (@as(usize, ligature_count) * 2 > data.len - offsets_start) {
        return error.BadSfnt;
    }
    const coverage_offset = try requiredChildOffset(
        data,
        lig_caret_list_offset,
        coverage_relative,
        4 + @as(usize, ligature_count) * 2,
    );
    const coverage_index = try coverage.coverageIndex(
        data,
        coverage_offset,
        glyph_id,
    ) orelse return allocator.alloc(types.LigatureCaret, 0);
    if (coverage_index >= ligature_count) return error.BadSfnt;

    const lig_glyph_relative = try bin.readU16At(
        data,
        offsets_start + coverage_index * 2,
    );
    const lig_glyph_offset = try requiredChildOffset(
        data,
        lig_caret_list_offset,
        lig_glyph_relative,
        4 + @as(usize, ligature_count) * 2,
    );
    if (data.len - lig_glyph_offset < 2) return error.BadSfnt;
    const caret_count = try bin.readU16At(data, lig_glyph_offset);
    const caret_offsets_start = lig_glyph_offset + 2;
    if (@as(usize, caret_count) * 2 > data.len - caret_offsets_start) {
        return error.BadSfnt;
    }

    const result = try allocator.alloc(types.LigatureCaret, caret_count);
    errdefer allocator.free(result);
    var previous: ?f32 = null;
    for (result, 0..) |*caret, index| {
        const relative = try bin.readU16At(
            data,
            caret_offsets_start + index * 2,
        );
        const caret_offset = try requiredChildOffset(
            data,
            lig_glyph_offset,
            relative,
            2 + @as(usize, caret_count) * 2,
        );
        caret.position = try readCaretValue(
            data,
            caret_offset,
            glyph_id,
            options,
        );
        if (!std.math.isFinite(caret.position)) return error.BadSfnt;
        if (previous) |value| {
            if (caret.position <= value) {
                return error.NonCanonicalCaretOrder;
            }
        }
        previous = caret.position;
    }
    return result;
}

fn readCaretValue(
    data: []const u8,
    offset: usize,
    glyph_id: glyph_mod.GlyphId,
    options: Options,
) Error!f32 {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    return switch (try bin.readU16At(data, offset)) {
        1 => coordinate(data, offset),
        2 => blk: {
            try requireBytes(data, offset, 4);
            const context = options.contour_context orelse
                return error.BadSfnt;
            const resolve = options.resolve_contour_point orelse
                return error.BadSfnt;
            break :blk (try resolve(
                context,
                glyph_id,
                try bin.readU16At(data, offset + 2),
                options.normalized_coords,
            )) orelse return error.UnavailableContourPoint;
        },
        3 => blk: {
            try requireBytes(data, offset, 6);
            const base = try coordinate(data, offset);
            const relative = try bin.readU16At(data, offset + 4);
            const device_offset = try requiredChildOffset(
                data,
                offset,
                relative,
                6,
            );
            break :blk base + @as(f32, @floatFromInt(
                try variationDelta(data, device_offset, options),
            ));
        },
        else => error.BadSfnt,
    };
}

fn coordinate(data: []const u8, offset: usize) Error!f32 {
    try requireBytes(data, offset, 4);
    return @floatFromInt(try bin.readI16At(data, offset + 2));
}

fn variationDelta(
    data: []const u8,
    device_offset: usize,
    options: Options,
) Error!i32 {
    try requireBytes(data, device_offset, 6);
    if (try bin.readU16At(data, device_offset + 4) != 0x8000 or
        options.normalized_coords.len == 0)
    {
        return 0;
    }
    const store_offset = options.item_variation_store_offset orelse return 0;
    return metric_variation.itemVariationDelta(
        data,
        0,
        data.len,
        store_offset,
        .{
            .outer = try bin.readU16At(data, device_offset),
            .inner = try bin.readU16At(data, device_offset + 2),
        },
        options.normalized_coords,
    ) catch |err| switch (err) {
        error.BadSfnt, error.EndOfStream => return error.BadSfnt,
        error.OutOfMemory => return error.OutOfMemory,
    };
}

fn requiredChildOffset(
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
