//! Bounded recursive materialization of EBDT/CBDT compound glyphs.
//!
//! Image formats 8/9 define a parent canvas and place other strike glyphs by
//! integer pixel offsets. This module owns recursion, cycle limits, decoding,
//! and compositing so table parsing and renderer integration stay independent.

const std = @import("std");

const data_mod = @import("data.zig");
const index = @import("index.zig");
const cblc_types = @import("types.zig");
const types = @import("../types.zig");

const max_depth = 100; // Match FreeType's deployed compound-sbit guard.

pub fn glyphAlloc(
    allocator: std.mem.Allocator,
    data: []const u8,
    data_table: types.Table,
    selected: cblc_types.SelectedGlyph,
    source: types.StrikeSource,
) types.Error!?types.OwnedGlyphData {
    if (selected.location.image_format != 8 and
        selected.location.image_format != 9) return null;
    var path: [max_depth + 1]u16 = undefined;
    const rendered = try render(
        allocator,
        data,
        data_table,
        selected.strike,
        selected.location,
        source,
        &path,
        0,
    );
    return .{
        .allocator = allocator,
        .source = source,
        .ppem = selected.strike.ppem,
        .ppi = selected.strike.ppi,
        .origin_offset_x = rendered.metrics.bearing_x,
        .origin_offset_y = rendered.metrics.bearing_y,
        .width = rendered.metrics.width,
        .height = rendered.metrics.height,
        .kind = rendered.kind,
        .data = rendered.data,
    };
}

const Rendered = struct {
    metrics: types.Metrics,
    kind: types.OwnedGlyphData.Kind,
    data: []u8,
};

fn render(
    allocator: std.mem.Allocator,
    data: []const u8,
    data_table: types.Table,
    strike: cblc_types.Strike,
    location: cblc_types.GlyphLocation,
    source: types.StrikeSource,
    path: *[max_depth + 1]u16,
    depth: usize,
) types.Error!Rendered {
    if (depth > max_depth) return error.BadSfnt;
    if (try data_mod.compound(data, data_table, location)) |compound| {
        const pixel_count = std.math.mul(
            usize,
            compound.metrics.width,
            compound.metrics.height,
        ) catch return error.BadSfnt;
        var output_kind: ?types.OwnedGlyphData.Kind = null;
        var output: ?[]u8 = null;
        errdefer if (output) |pixels| allocator.free(pixels);

        for (0..compound.count()) |component_index| {
            const component = try compound.component(component_index);
            for (path[0..depth]) |ancestor| {
                if (ancestor == component.glyph_id) return error.BadSfnt;
            }
            const child_location = (try index.glyphLocation(
                data,
                strike,
                component.glyph_id,
            )) orelse return error.BadSfnt;
            path[depth] = component.glyph_id;
            const child = try render(
                allocator,
                data,
                data_table,
                strike,
                child_location,
                source,
                path,
                depth + 1,
            );
            defer allocator.free(child.data);

            if (output_kind == null) {
                output_kind = child.kind;
                const bytes_per_pixel: usize = switch (child.kind) {
                    .mask8 => 1,
                    .premultiplied_bgra8 => 4,
                };
                output = try allocator.alloc(
                    u8,
                    std.math.mul(usize, pixel_count, bytes_per_pixel) catch
                        return error.BadSfnt,
                );
                @memset(output.?, 0);
            } else if (output_kind.? != child.kind) {
                // A strike has one bit depth, so mixed decoded kinds indicate
                // corrupt or unsupported component data rather than a blend.
                return error.BadSfnt;
            }
            try blit(
                output.?,
                compound.metrics.width,
                compound.metrics.height,
                child,
                component.x_offset,
                component.y_offset,
            );
        }
        if (output == null) {
            const kind: types.OwnedGlyphData.Kind = if (strike.bit_depth == 32)
                .premultiplied_bgra8
            else
                .mask8;
            const bytes_per_pixel: usize = if (kind == .mask8) 1 else 4;
            output = try allocator.alloc(
                u8,
                std.math.mul(usize, pixel_count, bytes_per_pixel) catch
                    return error.BadSfnt,
            );
            @memset(output.?, 0);
            output_kind = kind;
        }
        return .{
            .metrics = compound.metrics,
            .kind = output_kind.?,
            .data = output.?,
        };
    }

    if (try data_mod.glyphBgra(
        data,
        data_table,
        strike,
        location,
        source,
    )) |bgra| {
        return .{
            .metrics = metricsFromBgra(bgra),
            .kind = .premultiplied_bgra8,
            .data = try allocator.dupe(u8, bgra.data),
        };
    }
    if (try data_mod.glyphMask(
        data,
        data_table,
        strike,
        location,
        source,
    )) |mask| {
        return .{
            .metrics = metricsFromMask(mask),
            .kind = .mask8,
            .data = try mask.decodeAlloc(allocator),
        };
    }
    return error.BadSfnt;
}

fn blit(
    destination: []u8,
    destination_width: usize,
    destination_height: usize,
    source: Rendered,
    x_offset: i8,
    y_offset: i8,
) types.Error!void {
    const x: i32 = x_offset;
    const y: i32 = y_offset;
    if (x < 0 or y < 0 or
        @as(usize, @intCast(x)) + source.metrics.width > destination_width or
        @as(usize, @intCast(y)) + source.metrics.height > destination_height)
    {
        return error.BadSfnt;
    }
    const bytes_per_pixel: usize = switch (source.kind) {
        .mask8 => 1,
        .premultiplied_bgra8 => 4,
    };
    for (0..source.metrics.height) |source_y| {
        for (0..source.metrics.width) |source_x| {
            const source_index =
                (source_y * source.metrics.width + source_x) * bytes_per_pixel;
            const destination_index =
                ((@as(usize, @intCast(y)) + source_y) * destination_width +
                    @as(usize, @intCast(x)) + source_x) * bytes_per_pixel;
            if (source.kind == .mask8) {
                destination[destination_index] = @max(
                    destination[destination_index],
                    source.data[source_index],
                );
            } else {
                blendBgra(
                    destination[destination_index..][0..4],
                    source.data[source_index..][0..4],
                );
            }
        }
    }
}

fn blendBgra(destination: *[4]u8, source: *const [4]u8) void {
    const inverse_alpha = 255 - @as(u16, source[3]);
    inline for (0..4) |channel| {
        destination[channel] = @intCast(@min(
            @as(u16, 255),
            @as(u16, source[channel]) +
                (@as(u16, destination[channel]) * inverse_alpha) / 255,
        ));
    }
}

fn metricsFromBgra(glyph: types.GlyphBgra) types.Metrics {
    return .{
        .height = @intCast(glyph.height),
        .width = @intCast(glyph.width),
        .bearing_x = @intCast(glyph.origin_offset_x),
        .bearing_y = @intCast(glyph.origin_offset_y),
        .advance = 0,
    };
}

fn metricsFromMask(glyph: types.GlyphMask) types.Metrics {
    return .{
        .height = @intCast(glyph.height),
        .width = @intCast(glyph.width),
        .bearing_x = @intCast(glyph.origin_offset_x),
        .bearing_y = @intCast(glyph.origin_offset_y),
        .advance = 0,
    };
}
