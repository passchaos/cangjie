//! Raw integer point ownership for compound TrueType `glyf` glyphs.
//!
//! Component glyphs are recursively expanded into one top-level point/contour
//! zone.  Both design-space FUnits and scaled 26.6 coordinates are transformed
//! independently so point matching is exact in each domain.  This module does
//! not execute child or parent bytecode; the executor must reject compound
//! transactions until that lifecycle can be committed atomically.

const std = @import("std");

const bin = @import("../../binary.zig");
const glyph = @import("../../glyph.zig");
const outline = @import("outline.zig");
const truetype_compound = @import("../outline/truetype/compound.zig");
const types = @import("types.zig");

pub const Source = struct {
    glyph_id: glyph.GlyphId,
    data: []const u8,
    metrics: outline.Metrics,
};

pub const Resolver = struct {
    context: *const anyopaque,
    resolveFn: *const fn (
        context: *const anyopaque,
        glyph_id: glyph.GlyphId,
    ) types.Error!Source,

    pub fn resolve(self: Resolver, glyph_id: glyph.GlyphId) types.Error!Source {
        return self.resolveFn(self.context, glyph_id);
    }
};

pub fn decode(
    allocator: std.mem.Allocator,
    face_identity: usize,
    target: types.Target,
    root: Source,
    scale_16_16: i32,
    max_component_depth: u16,
    resolver: Resolver,
) types.Error!outline.Transaction {
    var builder = Builder{
        .allocator = allocator,
        .scale_16_16 = scale_16_16,
        .max_component_depth = max_component_depth,
        .resolver = resolver,
    };
    defer builder.deinit();
    const result = try builder.appendGlyph(root, 0, true);
    if (!result.is_compound) return error.UnsupportedHintGlyph;

    const real_point_count = builder.points.items.len;
    try builder.appendPhantoms(result.effective_metrics);
    const points = try builder.points.toOwnedSlice(allocator);
    errdefer allocator.free(points);
    const original = try allocator.dupe(outline.Point, points);
    errdefer allocator.free(original);
    const unscaled = try builder.unscaled.toOwnedSlice(allocator);
    errdefer allocator.free(unscaled);
    const flags = try builder.flags.toOwnedSlice(allocator);
    errdefer allocator.free(flags);
    const contours = try builder.contours.toOwnedSlice(allocator);
    errdefer allocator.free(contours);
    const components = try builder.components.toOwnedSlice(allocator);
    errdefer allocator.free(components);
    return .{
        .allocator = allocator,
        .face_identity = face_identity,
        .target = target,
        .glyph_id = root.glyph_id,
        .real_point_count = real_point_count,
        .points = points,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = contours,
        .components = components,
        .instructions = result.instructions,
        .scale_16_16 = scale_16_16,
        .is_compound = true,
    };
}

const Result = struct {
    effective_metrics: outline.Metrics,
    instructions: []const u8 = &.{},
    is_compound: bool = false,
};

pub const FixedTransform = struct {
    xx: i32,
    yx: i32,
    xy: i32,
    yy: i32,
};

const Offsets = struct {
    scaled: outline.Point,
    unscaled: outline.Point,
};

const Builder = struct {
    allocator: std.mem.Allocator,
    scale_16_16: i32,
    max_component_depth: u16,
    resolver: Resolver,
    points: std.ArrayList(outline.Point) = .empty,
    unscaled: std.ArrayList(outline.Point) = .empty,
    flags: std.ArrayList(outline.PointFlag) = .empty,
    contours: std.ArrayList(u16) = .empty,
    components: std.ArrayList(outline.ComponentRecord) = .empty,

    fn deinit(self: *Builder) void {
        self.components.deinit(self.allocator);
        self.contours.deinit(self.allocator);
        self.flags.deinit(self.allocator);
        self.unscaled.deinit(self.allocator);
        self.points.deinit(self.allocator);
    }

    fn appendGlyph(
        self: *Builder,
        source: Source,
        depth: usize,
        record_components: bool,
    ) types.Error!Result {
        if (depth > self.max_component_depth) {
            return error.UnsupportedHintGlyph;
        }
        if (source.data.len == 0) {
            return .{ .effective_metrics = source.metrics };
        }
        const contour_count = bin.readI16At(source.data, 0) catch
            return error.BadSfnt;
        if (contour_count >= 0) {
            const instructions =
                try self.appendSimple(source, @intCast(contour_count));
            return .{
                .effective_metrics = source.metrics,
                .instructions = instructions,
            };
        }
        return self.appendCompound(source, depth, record_components);
    }

    fn appendSimple(
        self: *Builder,
        source: Source,
        contour_count: u16,
    ) types.Error![]const u8 {
        var decoded = try outline.decodeSimple(
            self.allocator,
            0,
            .normal,
            source.glyph_id,
            source.data,
            contour_count,
            source.metrics,
            self.scale_16_16,
            null,
        );
        defer decoded.deinit();
        const point_start = self.points.items.len;
        try self.points.appendSlice(
            self.allocator,
            decoded.points[0..decoded.real_point_count],
        );
        try self.unscaled.appendSlice(
            self.allocator,
            decoded.unscaled[0..decoded.real_point_count],
        );
        try self.flags.appendSlice(
            self.allocator,
            decoded.flags[0..decoded.real_point_count],
        );
        for (decoded.contours) |end| {
            const adjusted = std.math.add(
                usize,
                point_start,
                end,
            ) catch return error.BadSfnt;
            if (adjusted > std.math.maxInt(u16)) return error.BadSfnt;
            try self.contours.append(self.allocator, @intCast(adjusted));
        }
        return decoded.instructions;
    }

    fn appendCompound(
        self: *Builder,
        source: Source,
        depth: usize,
        record_components: bool,
    ) types.Error!Result {
        var reader = bin.Reader.init(source.data);
        _ = reader.readI16() catch return error.BadSfnt;
        reader.skip(8) catch return error.BadSfnt;
        const parent_point_start = self.points.items.len;
        var last_flags: u16 = 0;
        var effective_metrics = source.metrics;
        while (true) {
            const component = truetype_compound.readComponent(&reader) catch
                return error.BadSfnt;
            last_flags = component.flags;
            const child = try self.resolver.resolve(component.glyph_id);
            const child_point_start = self.points.items.len;
            const child_contour_start = self.contours.items.len;
            const child_result = try self.appendGlyph(
                child,
                depth + 1,
                false,
            );
            const child_point_end = self.points.items.len;
            const transform = fixedTransform(component.fixed_transform);
            self.transformPoints(
                child_point_start,
                child_point_end,
                transform,
            );
            const offsets = switch (component.placement) {
                .offset => |raw| self.offsetPlacement(
                    raw.x,
                    raw.y,
                    component.flags,
                    transform,
                ),
                .points => |match| try self.pointPlacement(
                    parent_point_start,
                    child_point_start,
                    child_point_end,
                    match.parent_point,
                    match.child_point,
                ),
            };
            self.translatePoints(
                child_point_start,
                child_point_end,
                offsets,
            );
            if (record_components) {
                try self.components.append(self.allocator, .{
                    .glyph_id = component.glyph_id,
                    .flags = component.flags,
                    .point_start = child_point_start,
                    .point_len = child_point_end - child_point_start,
                    .contour_start = child_contour_start,
                    .contour_len = self.contours.items.len - child_contour_start,
                    .transform = .{
                        .xx = component.fixed_transform.xx,
                        .yx = component.fixed_transform.yx,
                        .xy = component.fixed_transform.xy,
                        .yy = component.fixed_transform.yy,
                    },
                    .placement = switch (component.placement) {
                        .offset => |offset| .{ .offset = .{
                            .x = offset.x,
                            .y = offset.y,
                        } },
                        .points => |match| .{ .points = .{
                            .parent_point = match.parent_point,
                            .child_point = match.child_point,
                        } },
                    },
                    .use_my_metrics = (component.flags & 0x0200) != 0,
                    .is_compound = child_result.is_compound,
                    .instructions = child_result.instructions,
                });
            }
            if ((component.flags & 0x0200) != 0) {
                effective_metrics = child_result.effective_metrics;
            }
            if (!component.hasMore()) break;
        }
        const instructions = if ((last_flags & 0x0100) != 0)
            try compoundInstructions(source.data, reader.offset)
        else
            &.{};
        return .{
            .effective_metrics = effective_metrics,
            .instructions = instructions,
            .is_compound = true,
        };
    }

    fn transformPoints(
        self: *Builder,
        start: usize,
        end: usize,
        transform: FixedTransform,
    ) void {
        for (self.points.items[start..end]) |*point| {
            point.* = applyTransform(point.*, transform);
        }
        for (self.unscaled.items[start..end]) |*point| {
            point.* = applyTransform(point.*, transform);
        }
    }

    fn offsetPlacement(
        self: *Builder,
        x: i16,
        y: i16,
        component_flags: u16,
        transform: FixedTransform,
    ) Offsets {
        var unscaled = outline.Point{ .x = x, .y = y };
        if ((component_flags & 0x0800) != 0) {
            unscaled = scaleComponentOffset(unscaled, transform);
        }
        var scaled = outline.Point{
            .x = types.scaleFUnits(unscaled.x, self.scale_16_16),
            .y = types.scaleFUnits(unscaled.y, self.scale_16_16),
        };
        if ((component_flags & 0x0004) != 0) {
            scaled.x = roundGrid(scaled.x);
            scaled.y = roundGrid(scaled.y);
        }
        return .{ .scaled = scaled, .unscaled = unscaled };
    }

    fn pointPlacement(
        self: *Builder,
        parent_start: usize,
        child_start: usize,
        child_end: usize,
        parent_point: u16,
        child_point: u16,
    ) types.Error!Offsets {
        const parent_index = parent_start + parent_point;
        const child_index = child_start + child_point;
        if (parent_index >= child_start or child_index >= child_end) {
            return error.BadSfnt;
        }
        return .{
            .scaled = .{
                .x = self.points.items[parent_index].x -|
                    self.points.items[child_index].x,
                .y = self.points.items[parent_index].y -|
                    self.points.items[child_index].y,
            },
            .unscaled = .{
                .x = self.unscaled.items[parent_index].x -|
                    self.unscaled.items[child_index].x,
                .y = self.unscaled.items[parent_index].y -|
                    self.unscaled.items[child_index].y,
            },
        };
    }

    fn translatePoints(
        self: *Builder,
        start: usize,
        end: usize,
        offsets: Offsets,
    ) void {
        for (self.points.items[start..end]) |*point| {
            point.x +|= offsets.scaled.x;
            point.y +|= offsets.scaled.y;
        }
        for (self.unscaled.items[start..end]) |*point| {
            point.x +|= offsets.unscaled.x;
            point.y +|= offsets.unscaled.y;
        }
    }

    fn appendPhantoms(
        self: *Builder,
        metrics: outline.Metrics,
    ) types.Error!void {
        for (phantoms(metrics)) |point| {
            try self.unscaled.append(self.allocator, point);
            try self.points.append(self.allocator, .{
                .x = types.scaleFUnits(point.x, self.scale_16_16),
                .y = types.scaleFUnits(point.y, self.scale_16_16),
            });
            try self.flags.append(self.allocator, .{});
        }
    }
};

fn fixedTransform(
    value: truetype_compound.FixedTransform,
) FixedTransform {
    return .{
        .xx = value.xx,
        .yx = value.yx,
        .xy = value.xy,
        .yy = value.yy,
    };
}

pub fn applyTransform(
    point: outline.Point,
    transform: FixedTransform,
) outline.Point {
    return .{
        .x = mulF2Dot14(point.x, transform.xx) +|
            mulF2Dot14(point.y, transform.xy),
        .y = mulF2Dot14(point.x, transform.yx) +|
            mulF2Dot14(point.y, transform.yy),
    };
}

pub fn scaleComponentOffset(
    point: outline.Point,
    transform: FixedTransform,
) outline.Point {
    return .{
        .x = mulF2Dot14(
            point.x,
            hypotF2Dot14(transform.xx, transform.xy),
        ),
        .y = mulF2Dot14(
            point.y,
            hypotF2Dot14(transform.yy, transform.yx),
        ),
    };
}

fn hypotF2Dot14(a: i32, b: i32) i32 {
    const af: f64 = @floatFromInt(a);
    const bf: f64 = @floatFromInt(b);
    return @intFromFloat(@round(@sqrt(af * af + bf * bf)));
}

fn mulF2Dot14(value: i32, factor: i32) i32 {
    const product = @as(i64, value) * factor;
    const magnitude: u64 = @intCast(if (product < 0)
        -product
    else
        product);
    const rounded: i64 = @intCast((magnitude + 0x2000) >> 14);
    const signed = if (product < 0) -rounded else rounded;
    if (signed <= std.math.minInt(i32)) return std.math.minInt(i32);
    if (signed >= std.math.maxInt(i32)) return std.math.maxInt(i32);
    return @intCast(signed);
}

pub fn roundGrid(value: i32) i32 {
    return (value +| 32) & ~@as(i32, 63);
}

fn compoundInstructions(
    data: []const u8,
    offset: usize,
) types.Error![]const u8 {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    const len = bin.readU16At(data, offset) catch return error.BadSfnt;
    const start = offset + 2;
    if (len > data.len - start) return error.BadSfnt;
    return data[start .. start + len];
}

fn phantoms(metrics: outline.Metrics) [4]outline.Point {
    const left = metrics.bounds.x_min - metrics.left_side_bearing;
    return .{
        .{ .x = left, .y = 0 },
        .{ .x = left + metrics.advance_width, .y = 0 },
        .{
            .x = 0,
            .y = metrics.bounds.y_max + metrics.top_side_bearing,
        },
        .{
            .x = 0,
            .y = metrics.bounds.y_max + metrics.top_side_bearing -
                metrics.vertical_advance,
        },
    };
}
