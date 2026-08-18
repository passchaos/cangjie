//! Differential TrueType hinted-outline gates against installed FreeType v35.
//!
//! FreeType translates a hinted outline by `-pp1` before exposing the glyph
//! slot. Cangjie's raw transaction retains pp1, so the comparison applies the
//! same origin shift while preserving the unrounded 26.6 point coordinates.
//! The test bridge explicitly selects the classic interpreter because
//! Cangjie's VM does not yet implement FreeType v40 compatibility suppression.

const std = @import("std");
const cangjie = @import("cangjie");
const ft = @import("freetype");

const Fixture = struct {
    path: []const u8,
    codepoint: u21,
    ppem: u16,
    location: []const f32 = &.{},
};

test "hinted outlines match FreeType representative corpus" {
    const fixtures = [_]Fixture{
        .{
            .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            .codepoint = 'A',
            .ppem = 9,
        },
        .{
            .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            .codepoint = 'X',
            .ppem = 16,
        },
        .{
            .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            .codepoint = 0x00c2,
            .ppem = 20,
        },
        .{
            .path = "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
            .codepoint = 0x0915,
            .ppem = 16,
        },
        .{
            .path = "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf",
            .codepoint = 0x0627,
            .ppem = 16,
        },
        .{
            .path = "/usr/share/fonts/truetype/cascadia-code/CascadiaCode.ttf",
            .codepoint = 'A',
            .ppem = 16,
            .location = &.{0.5},
        },
        .{
            .path = "/usr/share/fonts/truetype/cascadia-code/CascadiaCode.ttf",
            .codepoint = 0x00c2,
            .ppem = 16,
            .location = &.{0.5},
        },
    };
    for (fixtures) |fixture| {
        try compareFixture(fixture);
    }
}

fn compareFixture(fixture: Fixture) !void {
    const allocator = std.testing.allocator;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        fixture.path,
        allocator,
        .limited(32 * 1024 * 1024),
    );
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const glyph_id = try face.glyphs().index(fixture.codepoint);
    var instance = if (fixture.location.len == 0)
        try face.hintingInstance(allocator, fixture.ppem, .normal)
    else
        try face.hintingInstanceAt(
            allocator,
            fixture.ppem,
            .normal,
            fixture.location,
        );
    defer instance.deinit();
    var transaction = try face.hintingPointTransaction(
        allocator,
        &instance,
        glyph_id,
    );
    defer transaction.deinit();
    try face.executeHintingTransaction(&instance, &transaction);

    const expected = try freeTypeOutline(
        allocator,
        bytes,
        glyph_id,
        fixture.ppem,
        fixture.location,
    );
    defer expected.deinit(allocator);
    errdefer |err| std.debug.print(
        "hint diff font={s} cp=U+{x} ppem={d}: {s}\n",
        .{ fixture.path, fixture.codepoint, fixture.ppem, @errorName(err) },
    );
    try expectEqual(
        usize,
        expected.points.len,
        transaction.real_point_count,
    );
    try expectSlicesEqual(u16, expected.contours, transaction.contours);
    const pp1 = transaction.phantomPoints()[0];
    for (
        expected.points,
        expected.tags,
        transaction.points[0..transaction.real_point_count],
        transaction.flags[0..transaction.real_point_count],
        0..,
    ) |wanted, wanted_tag, actual, actual_flag, point_index| {
        const actual_point = Point{
            .x = actual.x - pp1.x,
            .y = actual.y - pp1.y,
        };
        if (!std.meta.eql(wanted, actual_point)) {
            std.debug.print(
                "point={d} ft=({d},{d}) cj=({d},{d}) pp1=({d},{d})\n",
                .{
                    point_index,
                    wanted.x,
                    wanted.y,
                    actual_point.x,
                    actual_point.y,
                    pp1.x,
                    pp1.y,
                },
            );
            return error.HintingMismatch;
        }
        try expectEqual(
            bool,
            (wanted_tag & 1) != 0,
            actual_flag.on_curve,
        );
    }
    const actual_advance = transaction.phantomPoints()[1].x -
        transaction.phantomPoints()[0].x;
    try expectEqual(i32, expected.advance, actual_advance);
}

fn expectEqual(comptime T: type, expected: T, actual: T) !void {
    if (!std.meta.eql(expected, actual)) return error.HintingMismatch;
}

fn expectSlicesEqual(
    comptime T: type,
    expected: []const T,
    actual: []const T,
) !void {
    if (!std.mem.eql(T, expected, actual)) return error.HintingMismatch;
}

const FtOutline = struct {
    points: []Point,
    tags: []u8,
    contours: []u16,
    advance: i32,

    fn deinit(self: FtOutline, allocator: std.mem.Allocator) void {
        allocator.free(self.points);
        allocator.free(self.tags);
        allocator.free(self.contours);
    }
};

const Point = struct {
    x: i32,
    y: i32,
};

fn freeTypeOutline(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    glyph_id: cangjie.font.GlyphId,
    ppem: u16,
    location: []const f32,
) !FtOutline {
    var library: ft.FT_Library = null;
    if (ft.FT_Init_FreeType(&library) != 0) return error.FreeTypeFailed;
    defer _ = ft.FT_Done_FreeType(library);
    if (ft.cangjie_ft_select_classic_interpreter(library) != 0) {
        return error.FreeTypeClassicInterpreterUnavailable;
    }
    var face: ft.FT_Face = null;
    if (ft.FT_New_Memory_Face(
        library,
        @ptrCast(bytes.ptr),
        @intCast(bytes.len),
        0,
        &face,
    ) != 0) return error.FreeTypeFailed;
    defer _ = ft.FT_Done_Face(face);
    if (ft.FT_Set_Pixel_Sizes(face, 0, ppem) != 0) {
        return error.FreeTypeFailed;
    }
    if (location.len != 0) {
        var coordinates: [32]ft.FT_Fixed = undefined;
        if (location.len > coordinates.len) return error.InvalidArguments;
        for (location, coordinates[0..location.len]) |value, *fixed| {
            fixed.* = @intFromFloat(@round(value * 65536.0));
        }
        if (ft.FT_Set_Var_Blend_Coordinates(
            face,
            @intCast(location.len),
            &coordinates,
        ) != 0) return error.FreeTypeFailed;
    }
    if (ft.FT_Load_Glyph(
        face,
        glyph_id,
        ft.FT_LOAD_NO_BITMAP | ft.FT_LOAD_TARGET_NORMAL,
    ) != 0) return error.FreeTypeFailed;
    const slot = face.*.glyph;
    if (slot == null or slot.*.format != ft.FT_GLYPH_FORMAT_OUTLINE) {
        return error.FreeTypeFailed;
    }
    const value = slot.*.outline;
    const point_count: usize = @intCast(value.n_points);
    const contour_count: usize = @intCast(value.n_contours);
    const points = try allocator.alloc(Point, point_count);
    errdefer allocator.free(points);
    const tags = try allocator.alloc(u8, point_count);
    errdefer allocator.free(tags);
    const contours = try allocator.alloc(u16, contour_count);
    errdefer allocator.free(contours);
    const raw_points: [*]const ft.FT_Vector = @ptrCast(value.points);
    const raw_tags: [*]const u8 = @ptrCast(value.tags);
    const raw_contours: [*]const c_short = @ptrCast(value.contours);
    for (points, raw_points[0..point_count]) |*point, raw| {
        point.* = .{ .x = @intCast(raw.x), .y = @intCast(raw.y) };
    }
    @memcpy(tags, raw_tags[0..point_count]);
    for (contours, raw_contours[0..contour_count]) |*end, raw| {
        if (raw < 0) return error.FreeTypeFailed;
        end.* = @intCast(raw);
    }
    return .{
        .points = points,
        .tags = tags,
        .contours = contours,
        .advance = @intCast(slot.*.metrics.horiAdvance),
    };
}
