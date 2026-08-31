//! Simple `glyf` decoding, gvar application, and quadratic contour building.

const std = @import("std");
const bin = @import("../../../binary.zig");
const glyph = @import("../../../glyph.zig");
const gvar = @import("../../../opentype/gvar.zig");
const glyf = @import("../../tables/truetype/glyf/root.zig");
const geometry = @import("../geometry.zig");
const numeric = @import("../numeric.zig");

const Transform = geometry.Transform;

/// Internal sink for the capacity-proved simple-glyph command stream.
const ReservedOutlineBuilder = struct {
    commands: *std.ArrayList(glyph.PathCommand),

    inline fn moveTo(self: *ReservedOutlineBuilder, point: glyph.Point) void {
        self.commands.appendAssumeCapacity(.{ .move_to = point });
    }

    inline fn lineTo(self: *ReservedOutlineBuilder, point: glyph.Point) void {
        self.commands.appendAssumeCapacity(.{ .line_to = point });
    }

    inline fn quadTo(
        self: *ReservedOutlineBuilder,
        control: glyph.Point,
        end: glyph.Point,
    ) void {
        self.commands.appendAssumeCapacity(.{
            .quad_to = .{ .control = control, .end = end },
        });
    }

    inline fn close(self: *ReservedOutlineBuilder) void {
        self.commands.appendAssumeCapacity(.close);
    }
};

pub const Error = error{
    BadSfnt,
    InvalidGlyph,
    EndOfStream,
} || std.mem.Allocator.Error;

pub const Variation = struct {
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    axis_count: usize,
    glyph_id: glyph.GlyphId,
    normalized_coords: []const f32,
    /// Metadata retained by `Font.parse` for immutable session reads. Public
    /// mutation-aware outline APIs leave this null and keep reparsing/validating
    /// the borrowed gvar table before consuming it.
    parsed: ?gvar.Info = null,
    validate_inactive_payloads: bool,
};

pub fn append(
    outline: *glyph.GlyphOutline,
    transformed_points: ?*std.ArrayList(glyph.Point),
    data: []const u8,
    contour_count: u16,
    transform: Transform,
    variation: ?Variation,
) Error!?gvar.PhantomPointDeltas {
    return appendImpl(
        outline,
        transformed_points,
        data,
        contour_count,
        transform,
        variation,
        false,
    );
}

/// Decode bytes whose complete `glyf` grammar was proved by `Face.parse`.
/// Bounds checks required for slicing remain below; only the redundant flag
/// grammar predicate is omitted from the hot immutable-face path.
pub fn appendParsed(
    outline: *glyph.GlyphOutline,
    transformed_points: ?*std.ArrayList(glyph.Point),
    data: []const u8,
    contour_count: u16,
    transform: Transform,
    variation: ?Variation,
) Error!?gvar.PhantomPointDeltas {
    return appendImpl(
        outline,
        transformed_points,
        data,
        contour_count,
        transform,
        variation,
        true,
    );
}

fn appendImpl(
    outline: *glyph.GlyphOutline,
    transformed_points: ?*std.ArrayList(glyph.Point),
    data: []const u8,
    contour_count: u16,
    transform: Transform,
    variation: ?Variation,
    comptime parsed: bool,
) Error!?gvar.PhantomPointDeltas {
    if (contour_count == 0) {
        // A contourless simple glyph can still vary its four metric phantom
        // points. Do not require real contours merely to preserve its advance
        // and side-bearing deltas.
        const context = variation orelse return null;
        const parsed_gvar = context.parsed orelse try gvar.info(
            context.data,
            context.table_offset,
            context.table_length,
            context.glyph_count,
            context.axis_count,
        );
        const deltas = try gvar.accumulateSimpleGlyphPointDeltasWithReaderFromParsed(
            outline.allocator,
            context.data,
            context.table_offset,
            context.table_length,
            parsed_gvar,
            context.glyph_id,
            context.normalized_coords,
            []const FlaggedPoint,
            &.{},
            0,
            flaggedPointForGvarIup,
            &.{},
            context.validate_inactive_payloads,
        );
        defer if (deltas) |owned| outline.allocator.free(owned);
        return if (deltas) |all_deltas|
            try gvar.phantomPointDeltasFromDense(0, all_deltas)
        else
            null;
    }

    var reader = bin.Reader.init(data);
    _ = try reader.readI16();
    try reader.skip(8);
    var inline_end_points: [8]u16 = undefined;
    const end_points = if (contour_count <= inline_end_points.len)
        inline_end_points[0..contour_count]
    else
        try outline.allocator.alloc(u16, contour_count);
    defer if (contour_count > inline_end_points.len) {
        outline.allocator.free(end_points);
    };

    var total_points: usize = 0;
    var previous_end: ?u16 = null;
    for (end_points) |*end| {
        end.* = try reader.readU16();
        if (previous_end) |previous| {
            // Repeated or decreasing end points would create empty or
            // overlapping contour slices during reconstruction.
            if (end.* <= previous) return error.InvalidGlyph;
        }
        previous_end = end.*;
        total_points = @as(usize, end.*) + 1;
    }
    const instruction_length = try reader.readU16();
    try reader.skip(instruction_length);
    try outline.commands.ensureUnusedCapacity(
        outline.allocator,
        // Every contour emits move/close in addition to at most one command
        // per point. Usually its explicit start consumes one point, but the
        // legal all-off-curve case needs both extra slots.
        total_points + @as(usize, contour_count) * 2,
    );

    // X and Y values use separate delta streams. Expand flag RLE directly into
    // point records so outline materialization needs no second point-sized
    // allocation.
    var inline_points: [64]FlaggedPoint = undefined;
    const points = if (total_points <= inline_points.len)
        inline_points[0..total_points]
    else
        try outline.allocator.alloc(FlaggedPoint, total_points);
    defer if (total_points > inline_points.len) outline.allocator.free(points);
    var point_index: usize = 0;
    while (point_index < total_points) : (point_index += 1) {
        const flag = try reader.readU8();
        if (!parsed) try glyf.validateSimpleFlag(flag, point_index);
        points[point_index].flags = flag;
        if ((flag & 0x08) != 0) {
            const repeat = try reader.readU8();
            for (0..repeat) |_| {
                point_index += 1;
                if (point_index >= total_points) return error.InvalidGlyph;
                if (!parsed) try glyf.validateSimpleFlag(flag, point_index);
                points[point_index].flags = flag;
            }
        }
    }

    var x: i16 = 0;
    for (points) |*point| {
        const flag = point.flags;
        const delta: i16 = if ((flag & 0x02) != 0)
            if ((flag & 0x10) != 0)
                try reader.readU8()
            else
                -@as(i16, try reader.readU8())
        else if ((flag & 0x10) != 0)
            0
        else
            try reader.readI16();
        x += delta;
        point.x = x;
    }
    var y: i16 = 0;
    for (points) |*point| {
        const flag = point.flags;
        const delta: i16 = if ((flag & 0x04) != 0)
            if ((flag & 0x20) != 0)
                try reader.readU8()
            else
                -@as(i16, try reader.readU8())
        else if ((flag & 0x20) != 0)
            0
        else
            try reader.readI16();
        y += delta;
        point.y = y;
    }

    var phantom_deltas: ?gvar.PhantomPointDeltas = null;
    if (variation) |context| {
        const parsed_gvar = context.parsed orelse try gvar.info(
            context.data,
            context.table_offset,
            context.table_length,
            context.glyph_count,
            context.axis_count,
        );
        const deltas = try gvar.accumulateSimpleGlyphPointDeltasWithReaderFromParsed(
            outline.allocator,
            context.data,
            context.table_offset,
            context.table_length,
            parsed_gvar,
            context.glyph_id,
            context.normalized_coords,
            []const FlaggedPoint,
            points,
            points.len,
            flaggedPointForGvarIup,
            end_points,
            context.validate_inactive_payloads,
        );
        defer if (deltas) |owned| outline.allocator.free(owned);
        if (deltas) |all_deltas| {
            const real_deltas = all_deltas[0..points.len];
            std.debug.assert(densePointIdsMatch(real_deltas));
            for (points, real_deltas) |*point, delta| {
                point.x = numeric.clampF32ToI16(numeric.roundOpenType(
                    @as(f32, @floatFromInt(point.x)) + delta.x,
                ));
                point.y = numeric.clampF32ToI16(numeric.roundOpenType(
                    @as(f32, @floatFromInt(point.y)) + delta.y,
                ));
            }
            // Static glyf header bounds remain authoritative when no tuple is
            // active; recompute only after gvar changed the decoded points.
            outline.bounds = boundsForPoints(points);
            phantom_deltas =
                try gvar.phantomPointDeltasFromDense(points.len, all_deltas);
        }
    }

    if (transformed_points) |raw_points| {
        // Compound point anchors address the original glyf points, including
        // off-curve controls omitted from the final path command stream.
        try raw_points.ensureUnusedCapacity(outline.allocator, points.len);
        for (points) |point| {
            raw_points.appendAssumeCapacity(transform.apply(point.point()));
        }
    }

    var start: usize = 0;
    // A contour emits at most one path command per source point plus move and
    // close. Capacity for that exact upper bound was reserved above.
    var builder = ReservedOutlineBuilder{ .commands = &outline.commands };
    if (transform.isIdentity()) {
        for (end_points) |end_point| {
            const end: usize = end_point;
            appendContour(&builder, points[start .. end + 1], transform, true);
            start = end + 1;
        }
    } else {
        for (end_points) |end_point| {
            const end: usize = end_point;
            appendContour(&builder, points[start .. end + 1], transform, false);
            start = end + 1;
        }
    }
    return phantom_deltas;
}

fn densePointIdsMatch(deltas: []const gvar.ScaledPointDelta) bool {
    for (deltas, 0..) |delta, index| {
        if (delta.point != index) return false;
    }
    return true;
}

fn flaggedPointForGvarIup(
    points: []const FlaggedPoint,
    index: usize,
) gvar.Point {
    return .{
        .x = @floatFromInt(points[index].x),
        .y = @floatFromInt(points[index].y),
    };
}

fn boundsForPoints(points: []const FlaggedPoint) glyph.Bounds {
    if (points.len == 0) {
        return .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
    }
    var result = glyph.Bounds{
        .x_min = points[0].x,
        .y_min = points[0].y,
        .x_max = points[0].x,
        .y_max = points[0].y,
    };
    for (points[1..]) |point| {
        result.x_min = @min(result.x_min, point.x);
        result.y_min = @min(result.y_min, point.y);
        result.x_max = @max(result.x_max, point.x);
        result.y_max = @max(result.y_max, point.y);
    }
    return result;
}

const FlaggedPoint = struct {
    x: i16 = 0,
    y: i16 = 0,
    flags: u8 = 0,

    fn onCurve(self: FlaggedPoint) bool {
        return (self.flags & 0x01) != 0;
    }

    fn point(self: FlaggedPoint) glyph.Point {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    }
};

fn appendContour(
    builder: *ReservedOutlineBuilder,
    contour: []const FlaggedPoint,
    transform: Transform,
    comptime identity_transform: bool,
) void {
    if (contour.len == 0) return;
    const first = contour[0];
    const last = contour[contour.len - 1];
    var current: glyph.Point = undefined;
    var index: usize = 0;
    // A TrueType contour may begin off-curve. Its visible start is the final
    // on-curve point, or the midpoint of the first and last controls.
    if (first.onCurve()) {
        current = first.point();
        index = 1;
    } else if (last.onCurve()) {
        current = last.point();
    } else {
        current = glyph.midpoint(last.point(), first.point());
    }
    builder.moveTo(if (identity_transform) current else transform.apply(current));

    while (index < contour.len) {
        const point = contour[index];
        if (point.onCurve()) {
            current = point.point();
            builder.lineTo(if (identity_transform) current else transform.apply(current));
            index += 1;
        } else {
            // Consecutive controls imply an on-curve midpoint, preserving
            // quadratic continuity without an explicit stored endpoint.
            const control = point.point();
            const next_index = if (index + 1 < contour.len) index + 1 else 0;
            const next = contour[next_index];
            const end = if (next.onCurve())
                next.point()
            else
                glyph.midpoint(control, next.point());
            builder.quadTo(
                if (identity_transform) control else transform.apply(control),
                if (identity_transform) end else transform.apply(end),
            );
            current = end;
            index += if (next.onCurve() and next_index != 0) 2 else 1;
        }
    }
    builder.close();
}
