//! Canonical hinted-point summary shared by Cangjie and FreeType benchmarks.

const std = @import("std");
const cangjie = @import("cangjie");
const ft = @import("freetype");

pub fn cangjieChecksum(
    transaction: *const cangjie.font.HintingPointTransaction,
) u64 {
    var hasher = startHasher(
        transaction.real_point_count,
        transaction.contours.len,
        transaction.horizontalAdvance(),
    );
    const origin = transaction.phantomPoints()[0];
    for (
        transaction.points[0..transaction.real_point_count],
        transaction.flags[0..transaction.real_point_count],
    ) |point, flags| {
        updatePoint(
            &hasher,
            point.x - origin.x,
            point.y - origin.y,
            flags.on_curve,
        );
    }
    for (transaction.contours) |contour| {
        hasher.update(std.mem.asBytes(&contour));
    }
    return hasher.final();
}

pub fn freeTypeChecksum(slot: ft.FT_GlyphSlot) !u64 {
    if (slot == null or slot.*.format != ft.FT_GLYPH_FORMAT_OUTLINE) {
        return error.FreeTypeFailed;
    }
    const outline = slot.*.outline;
    if (outline.n_points < 0 or outline.n_contours < 0) {
        return error.FreeTypeFailed;
    }
    const point_count: usize = @intCast(outline.n_points);
    const contour_count: usize = @intCast(outline.n_contours);
    if ((point_count != 0 and
        (outline.points == null or outline.tags == null)) or
        (contour_count != 0 and outline.contours == null))
    {
        return error.FreeTypeFailed;
    }
    const advance: i32 = @intCast(slot.*.metrics.horiAdvance);
    var hasher = startHasher(point_count, contour_count, advance);
    const points: [*]const ft.FT_Vector = @ptrCast(outline.points);
    const tags: [*]const u8 = @ptrCast(outline.tags);
    for (points[0..point_count], tags[0..point_count]) |point, tag| {
        updatePoint(
            &hasher,
            @intCast(point.x),
            @intCast(point.y),
            (tag & 1) != 0,
        );
    }
    const contours: [*]const c_short = @ptrCast(outline.contours);
    for (contours[0..contour_count]) |contour| {
        if (contour < 0) return error.FreeTypeFailed;
        const canonical: u16 = @intCast(contour);
        hasher.update(std.mem.asBytes(&canonical));
    }
    return hasher.final();
}

fn startHasher(
    point_count: usize,
    contour_count: usize,
    advance: i32,
) std.hash.Wyhash {
    var hasher = std.hash.Wyhash.init(0);
    const points: u32 = @intCast(point_count);
    const contours: u32 = @intCast(contour_count);
    hasher.update(std.mem.asBytes(&points));
    hasher.update(std.mem.asBytes(&contours));
    hasher.update(std.mem.asBytes(&advance));
    return hasher;
}

fn updatePoint(
    hasher: *std.hash.Wyhash,
    x: i32,
    y: i32,
    on_curve: bool,
) void {
    hasher.update(std.mem.asBytes(&x));
    hasher.update(std.mem.asBytes(&y));
    hasher.update(&.{@intFromBool(on_curve)});
}
