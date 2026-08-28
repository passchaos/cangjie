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
const gvar = @import("../../opentype/gvar.zig");
const outline = @import("outline.zig");
const truetype_compound = @import("../outline/truetype/compound.zig");
const types = @import("types.zig");

pub const Source = struct {
    glyph_id: glyph.GlyphId,
    data: []const u8,
    metrics: outline.Metrics,
};

pub const Variation = outline.Variation;

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
    interpreter: types.Interpreter,
    hinting_enabled: bool,
    backward_compatibility: bool,
    root: Source,
    scale_16_16: i32,
    max_component_depth: u16,
    resolver: Resolver,
    variation: ?Variation,
) types.Error!outline.Transaction {
    var builder = Builder{
        .allocator = allocator,
        .target = target,
        .interpreter = interpreter,
        .hinting_enabled = hinting_enabled,
        .backward_compatibility = backward_compatibility,
        .scale_16_16 = scale_16_16,
        .max_component_depth = max_component_depth,
        .resolver = resolver,
        .variation = variation,
    };
    defer builder.deinit();
    const result = try builder.appendGlyph(root, 0, true, false);
    if (!result.is_compound) return error.UnsupportedHintGlyph;

    const real_point_count = builder.points.items.len;
    try builder.appendPhantoms(result.effective_phantoms);
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
    const component_points = try builder.component_points.toOwnedSlice(allocator);
    errdefer allocator.free(component_points);
    const component_original = try builder.component_original.toOwnedSlice(allocator);
    errdefer allocator.free(component_original);
    const component_unscaled = try builder.component_unscaled.toOwnedSlice(allocator);
    errdefer allocator.free(component_unscaled);
    const component_flags = try builder.component_flags.toOwnedSlice(allocator);
    errdefer allocator.free(component_flags);
    const component_contours = try builder.component_contours.toOwnedSlice(allocator);
    errdefer allocator.free(component_contours);
    return .{
        .allocator = allocator,
        .face_identity = face_identity,
        .target = target,
        .interpreter = interpreter,
        .glyph_id = root.glyph_id,
        .real_point_count = real_point_count,
        .points = points,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = contours,
        .components = components,
        .component_points = component_points,
        .component_original = component_original,
        .component_unscaled = component_unscaled,
        .component_flags = component_flags,
        .component_contours = component_contours,
        .instructions = result.instructions,
        .scale_16_16 = scale_16_16,
        .variation = variation,
        .is_compound = true,
        .hinting_enabled = hinting_enabled,
        .backward_compatibility = backward_compatibility,
    };
}

const Result = struct {
    effective_metrics: outline.Metrics,
    effective_phantoms: [4]outline.Point,
    instructions: []const u8 = &.{},
    is_compound: bool = false,
    retained_source: ?SourceRange = null,
};

const SourceRange = struct {
    point_start: usize,
    point_len: usize,
    contour_start: usize,
    contour_len: usize,
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
    target: types.Target,
    interpreter: types.Interpreter,
    hinting_enabled: bool,
    backward_compatibility: bool,
    scale_16_16: i32,
    max_component_depth: u16,
    resolver: Resolver,
    variation: ?Variation,
    points: std.ArrayList(outline.Point) = .empty,
    unscaled: std.ArrayList(outline.Point) = .empty,
    flags: std.ArrayList(outline.PointFlag) = .empty,
    contours: std.ArrayList(u16) = .empty,
    components: std.ArrayList(outline.ComponentRecord) = .empty,
    component_points: std.ArrayList(outline.Point) = .empty,
    component_original: std.ArrayList(outline.Point) = .empty,
    component_unscaled: std.ArrayList(outline.Point) = .empty,
    component_flags: std.ArrayList(outline.PointFlag) = .empty,
    component_contours: std.ArrayList(u16) = .empty,

    fn deinit(self: *Builder) void {
        self.component_contours.deinit(self.allocator);
        self.component_flags.deinit(self.allocator);
        self.component_unscaled.deinit(self.allocator);
        self.component_original.deinit(self.allocator);
        self.component_points.deinit(self.allocator);
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
        retain_simple_source: bool,
    ) types.Error!Result {
        if (depth > self.max_component_depth) {
            return error.UnsupportedHintGlyph;
        }
        if (source.data.len == 0) {
            return .{
                .effective_metrics = source.metrics,
                .effective_phantoms = self.phantoms(source.metrics),
            };
        }
        const contour_count = bin.readI16At(source.data, 0) catch
            return error.BadSfnt;
        if (contour_count >= 0) {
            return self.appendSimple(
                source,
                @intCast(contour_count),
                retain_simple_source,
            );
        }
        return self.appendCompound(source, depth, record_components);
    }

    fn appendSimple(
        self: *Builder,
        source: Source,
        contour_count: u16,
        retain_source: bool,
    ) types.Error!Result {
        const variation: ?outline.Variation = if (self.variation) |context|
            .{
                .data = context.data,
                .table_offset = context.table_offset,
                .table_length = context.table_length,
                .glyph_count = context.glyph_count,
                .axis_count = context.axis_count,
                .normalized_coords = context.normalized_coords,
            }
        else
            null;
        var decoded = try outline.decodeSimple(
            self.allocator,
            0,
            self.target,
            self.interpreter,
            source.glyph_id,
            source.data,
            contour_count,
            source.metrics,
            self.scale_16_16,
            variation,
        );
        defer decoded.deinit();
        const retained_source: ?SourceRange = if (retain_source) retained: {
            const source_point_start = self.component_points.items.len;
            const source_contour_start = self.component_contours.items.len;
            try self.component_points.appendSlice(self.allocator, decoded.points);
            try self.component_original.appendSlice(self.allocator, decoded.original);
            try self.component_unscaled.appendSlice(self.allocator, decoded.unscaled);
            try self.component_flags.appendSlice(self.allocator, decoded.flags);
            try self.component_contours.appendSlice(self.allocator, decoded.contours);
            break :retained .{
                .point_start = source_point_start,
                .point_len = decoded.points.len,
                .contour_start = source_contour_start,
                .contour_len = decoded.contours.len,
            };
        } else null;
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
        return .{
            .effective_metrics = source.metrics,
            .effective_phantoms = decoded.unscaled[decoded.real_point_count..][0..4].*,
            .instructions = decoded.instructions,
            .retained_source = retained_source,
        };
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
        const component_count = gvar.glyfVariationPointCount(source.data) catch
            return error.BadSfnt;
        const variation_deltas = try self.compoundVariationDeltas(
            source.glyph_id,
            component_count,
        );
        defer if (variation_deltas) |owned| self.allocator.free(owned);
        var effective_phantoms = variedCompoundPhantoms(
            self.phantoms(source.metrics),
            variation_deltas,
            component_count,
        );
        var component_index: usize = 0;
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
                record_components,
            );
            const child_point_end = self.points.items.len;
            const transform = fixedTransform(component.fixed_transform);
            self.transformPoints(
                child_point_start,
                child_point_end,
                transform,
            );
            const varied_placement: outline.ComponentPlacement =
                switch (component.placement) {
                    .offset => |raw| .{ .offset = .{
                        .x = addRoundedDelta(
                            raw.x,
                            variationDelta(
                                variation_deltas,
                                component_index,
                            ).x,
                        ),
                        .y = addRoundedDelta(
                            raw.y,
                            variationDelta(
                                variation_deltas,
                                component_index,
                            ).y,
                        ),
                    } },
                    .points => |match| .{ .points = .{
                        .parent_point = match.parent_point,
                        .child_point = match.child_point,
                    } },
                };
            const offsets = switch (varied_placement) {
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
                const retained = child_result.retained_source;
                try self.components.append(self.allocator, .{
                    .glyph_id = component.glyph_id,
                    .data = child.data,
                    .metrics = child.metrics,
                    .flags = component.flags,
                    .point_start = child_point_start,
                    .point_len = child_point_end - child_point_start,
                    .contour_start = child_contour_start,
                    .contour_len = self.contours.items.len - child_contour_start,
                    .source_point_start = if (retained) |value|
                        value.point_start
                    else
                        0,
                    .source_point_len = if (retained) |value|
                        value.point_len
                    else
                        0,
                    .source_contour_start = if (retained) |value|
                        value.contour_start
                    else
                        0,
                    .source_contour_len = if (retained) |value|
                        value.contour_len
                    else
                        0,
                    .transform = .{
                        .xx = component.fixed_transform.xx,
                        .yx = component.fixed_transform.yx,
                        .xy = component.fixed_transform.xy,
                        .yy = component.fixed_transform.yy,
                    },
                    .placement = varied_placement,
                    .use_my_metrics = (component.flags & 0x0200) != 0,
                    .is_compound = child_result.is_compound,
                    .instructions = child_result.instructions,
                });
            }
            if ((component.flags & 0x0200) != 0) {
                effective_metrics = child_result.effective_metrics;
                effective_phantoms = child_result.effective_phantoms;
            }
            component_index += 1;
            if (!component.hasMore()) break;
        }
        if (component_index != component_count) return error.BadSfnt;
        const instructions = if ((last_flags & 0x0100) != 0)
            try compoundInstructions(source.data, reader.offset)
        else
            &.{};
        return .{
            .effective_metrics = effective_metrics,
            .effective_phantoms = effective_phantoms,
            .instructions = instructions,
            .is_compound = true,
        };
    }

    fn compoundVariationDeltas(
        self: *Builder,
        glyph_id: glyph.GlyphId,
        component_count: usize,
    ) types.Error!?[]gvar.ScaledPointDelta {
        const context = self.variation orelse return null;
        const target_count = component_count + 4;
        const raw = try self.allocator.alloc(gvar.PointDelta, target_count);
        defer self.allocator.free(raw);
        const deltas = try self.allocator.alloc(
            gvar.ScaledPointDelta,
            target_count,
        );
        errdefer self.allocator.free(deltas);
        const count = gvar.accumulateGlyphPointDeltasForPointCountRawScratchWithFlags(
            context.data,
            context.table_offset,
            context.table_length,
            context.glyph_count,
            context.axis_count,
            glyph_id,
            context.normalized_coords,
            target_count,
            raw,
            deltas,
            null,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.BadSfnt,
        };
        if (count == 0) {
            self.allocator.free(deltas);
            return null;
        }
        if (count != target_count) return error.BadSfnt;
        return deltas;
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
        x: i32,
        y: i32,
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
            if (self.hinting_enabled) {
                if (!self.backward_compatibility) {
                    scaled.x = roundGrid(scaled.x);
                }
                scaled.y = roundGrid(scaled.y);
            }
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
        values: [4]outline.Point,
    ) types.Error!void {
        for (values) |point| {
            try self.unscaled.append(self.allocator, point);
            try self.points.append(self.allocator, .{
                .x = types.scaleFUnits(point.x, self.scale_16_16),
                .y = types.scaleFUnits(point.y, self.scale_16_16),
            });
            try self.flags.append(self.allocator, .{});
        }
    }

    fn phantoms(self: Builder, metrics: outline.Metrics) [4]outline.Point {
        const left = metrics.bounds.x_min - metrics.left_side_bearing;
        const vertical_x = outline.verticalPhantomX(
            self.interpreter,
            self.target,
            metrics.advance_width,
        );
        return .{
            .{ .x = left, .y = 0 },
            .{ .x = left + metrics.advance_width, .y = 0 },
            .{
                .x = vertical_x,
                .y = metrics.bounds.y_max + metrics.top_side_bearing,
            },
            .{
                .x = vertical_x,
                .y = metrics.bounds.y_max + metrics.top_side_bearing -
                    metrics.vertical_advance,
            },
        };
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
    // Identity transforms dominate ordinary composite accents and are encoded
    // explicitly as 1.0 diagonal F2Dot14 values. Avoid four saturating fixed-
    // point multiplications in that overwhelmingly common case.
    if (isIdentityTransform(transform)) return point;
    if (transform.xy == 0 and transform.yx == 0) {
        return .{
            .x = mulF2Dot14(point.x, transform.xx),
            .y = mulF2Dot14(point.y, transform.yy),
        };
    }
    return .{
        .x = mulF2Dot14(point.x, transform.xx) +|
            mulF2Dot14(point.y, transform.xy),
        .y = mulF2Dot14(point.x, transform.yx) +|
            mulF2Dot14(point.y, transform.yy),
    };
}

pub fn isIdentityTransform(transform: FixedTransform) bool {
    return transform.xx == 0x4000 and transform.yy == 0x4000 and
        transform.xy == 0 and transform.yx == 0;
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

test "compound offset rounding follows hinting compatibility policy" {
    var builder = Builder{
        .allocator = std.testing.allocator,
        .target = .normal,
        .interpreter = .cleartype,
        .hinting_enabled = true,
        .backward_compatibility = true,
        .scale_16_16 = 0x10000,
        .max_component_depth = 1,
        .resolver = undefined,
        .variation = null,
    };
    const transform = FixedTransform{
        .xx = 0x4000,
        .yx = 0,
        .xy = 0,
        .yy = 0x4000,
    };
    const compatible = builder.offsetPlacement(
        10,
        10,
        0x0004,
        transform,
    );
    try std.testing.expectEqual(
        outline.Point{ .x = 10, .y = 0 },
        compatible.scaled,
    );

    builder.backward_compatibility = false;
    const native = builder.offsetPlacement(10, 10, 0x0004, transform);
    try std.testing.expectEqual(
        outline.Point{ .x = 0, .y = 0 },
        native.scaled,
    );

    builder.hinting_enabled = false;
    const disabled = builder.offsetPlacement(10, 10, 0x0004, transform);
    try std.testing.expectEqual(
        outline.Point{ .x = 10, .y = 10 },
        disabled.scaled,
    );
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

fn variationDelta(
    deltas: ?[]const gvar.ScaledPointDelta,
    index: usize,
) gvar.ScaledPointDelta {
    const values = deltas orelse return .{
        .point = @intCast(index),
        .x = 0,
        .y = 0,
    };
    return values[index];
}

fn variedCompoundPhantoms(
    base: [4]outline.Point,
    deltas: ?[]const gvar.ScaledPointDelta,
    component_count: usize,
) [4]outline.Point {
    var result = base;
    const values = deltas orelse return result;
    for (&result, values[component_count..]) |*point, delta| {
        point.x = addRoundedDelta(point.x, delta.x);
        point.y = addRoundedDelta(point.y, delta.y);
    }
    return result;
}

fn addRoundedDelta(value: i32, delta: f32) i32 {
    const result = @as(f64, @floatFromInt(value)) + delta;
    if (result <= @as(f64, @floatFromInt(std.math.minInt(i32)))) {
        return std.math.minInt(i32);
    }
    if (result >= @as(f64, @floatFromInt(std.math.maxInt(i32)))) {
        return std.math.maxInt(i32);
    }
    return @intFromFloat(@round(result));
}
