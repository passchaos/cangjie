//! Differential TrueType and CFF hinted-outline gates against installed
//! FreeType.
//!
//! FreeType translates a hinted outline by `-pp1` before exposing the glyph
//! slot. Cangjie's raw transaction retains pp1, so the comparison applies the
//! same origin shift while preserving the unrounded 26.6 point coordinates.
//! The test bridge explicitly selects v35 or v40 for every comparison.

const std = @import("std");
const cangjie = @import("cangjie");
const ft = @import("freetype");

const Fixture = struct {
    path: []const u8,
    codepoint: u21,
    ppem: u16,
    location: []const f32 = &.{},
};

const Type2Fixture = struct {
    path: []const u8,
    codepoint: u21,
    ppem: u16,
    location: []const f32 = &.{},
};

const Target = enum {
    normal,
    light,
    lcd,
    vertical_lcd,
    mono,

    fn cangjieTarget(self: Target) cangjie.font.HintingTarget {
        return switch (self) {
            .normal => .normal,
            .light => .light,
            .lcd => .lcd,
            .vertical_lcd => .vertical_lcd,
            .mono => .mono,
        };
    }

    fn freeTypeFlag(self: Target) ft.FT_Int32 {
        return @intCast(switch (self) {
            .normal => ft.FT_LOAD_TARGET_NORMAL,
            .light => ft.FT_LOAD_TARGET_LIGHT,
            .lcd => ft.FT_LOAD_TARGET_LCD,
            .vertical_lcd => ft.FT_LOAD_TARGET_LCD_V,
            .mono => ft.FT_LOAD_TARGET_MONO,
        });
    }
};

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
        .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        .codepoint = 0x00c3,
        .ppem = 9,
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
        .path = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
        .codepoint = 0x0416,
        .ppem = 9,
    },
    .{
        .path = "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        .codepoint = 'X',
        .ppem = 9,
    },
    .{
        .path = "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        .codepoint = 0x0995,
        .ppem = 9,
    },
    .{
        .path = "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        .codepoint = 0x0b95,
        .ppem = 9,
    },
    .{
        .path = "/usr/share/fonts/truetype/annapurna/AnnapurnaSIL-Regular.ttf",
        .codepoint = 0x0915,
        .ppem = 9,
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

// STIXGeneral is a deployed CFF1 face with conventional Latin blue zones,
// ghost hints, ordinary stem pairs, and glyph-local hint masks. Keeping more
// than one size here is important: a coordinate match at a single PPEM can be
// produced accidentally by ordinary scaling even when blue-zone suppression
// and pair adjustment are missing.
const type2_fixtures = [_]Type2Fixture{
    .{
        .path = "/usr/share/fonts/opentype/stix/STIXGeneral-Regular.otf",
        .codepoint = 'A',
        .ppem = 9,
    },
    .{
        .path = "/usr/share/fonts/opentype/stix/STIXGeneral-Regular.otf",
        .codepoint = 'H',
        .ppem = 13,
    },
    .{
        .path = "/usr/share/fonts/opentype/stix/STIXGeneral-Regular.otf",
        .codepoint = 'o',
        .ppem = 16,
    },
    .{
        .path = "/home/passchaos/Work/fontations/fauntlet/test_fonts/Cantarell-VF.subset.otf",
        .codepoint = 'A',
        .ppem = 8,
        .location = &.{-1},
    },
    .{
        .path = "/home/passchaos/Work/fontations/fauntlet/test_fonts/Cantarell-VF.subset.otf",
        .codepoint = 'B',
        .ppem = 16,
        .location = &.{0.5},
    },
};

test "classic hinted outlines match FreeType v35" {
    for (fixtures) |fixture| {
        try compareFixture(fixture, .classic, .normal);
    }
}

test "ClearType hinted outlines match FreeType v40" {
    for (fixtures) |fixture| {
        try compareFixture(fixture, .cleartype, .normal);
    }
}

test "ClearType target modes match FreeType v40" {
    // Native `light` outlines changed between FreeType 2.13.2 and 2.14.3
    // despite identical v40 instruction traces. Keep this interpreter gate
    // on target modes whose native bytecode semantics are version-stable;
    // light rendering policy belongs to the raster/auto-hinter comparison.
    for ([_]Target{ .lcd, .vertical_lcd, .mono }) |target| {
        for (fixtures) |fixture| {
            try compareFixture(fixture, .cleartype, target);
        }
    }
}

test "Liberation compound v40 targets match current FreeType" {
    const fixture = Fixture{
        .path = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        .codepoint = 0x00c2,
        .ppem = 9,
    };
    for ([_]Target{ .normal, .light, .lcd, .vertical_lcd }) |target| {
        try compareFixture(fixture, .cleartype, target);
    }
    // FreeType 2.14 changed ROUND_XY_TO_GRID for v40 monochrome compounds
    // from an interpreter-version check to the actual compatibility state.
    // Cangjie follows that current behavior; the system 2.13 oracle retains
    // the old unrounded X placement, so only gate mono against 2.14 or newer.
    if (try freeTypeVersionAtLeast(2, 14)) {
        try compareFixture(fixture, .cleartype, .mono);
    }
}

test "ClearType light target matches stable FreeType v40" {
    if (!try freeTypeVersionAtLeast(2, 14)) return error.SkipZigTest;
    for (fixtures) |fixture| {
        try compareFixture(fixture, .cleartype, .light);
    }
}

test "DejaVu Sans printable ASCII hinting corpus matches FreeType" {
    for (33..127) |codepoint| {
        const fixture = Fixture{
            .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            .codepoint = @intCast(codepoint),
            .ppem = 9,
        };
        try compareFixture(fixture, .classic, .normal);
        try compareFixture(fixture, .cleartype, .normal);
        try compareFixture(fixture, .cleartype, .mono);
    }
}

test "DejaVu Sans superscript zero-loop hinting matches FreeType" {
    // U+00B2 deliberately executes SLOOP[0]. FreeType accepts that value and
    // makes the following loop-driven point operation a no-op.
    const fixture = Fixture{
        .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        .codepoint = 0x00b2,
        .ppem = 9,
    };
    try compareFixture(fixture, .classic, .normal);
    try compareFixture(fixture, .cleartype, .normal);
    try compareFixture(fixture, .cleartype, .mono);
}

test "CFF Type2 hinted outlines match FreeType" {
    for (type2_fixtures) |fixture| try compareType2Fixture(fixture);
}

fn compareType2Fixture(fixture: Type2Fixture) !void {
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
    const instance = try face.type2HintingInstance(fixture.ppem);
    var actual = try face.type2HintedOutline(
        allocator,
        &instance,
        glyph_id,
        fixture.location,
    );
    defer actual.deinit();
    const expected = try freeTypeOutline(
        allocator,
        bytes,
        glyph_id,
        fixture.ppem,
        fixture.location,
        null,
        .normal,
    );
    defer expected.deinit(allocator);
    errdefer |err| std.debug.print(
        "Type2 hint diff font={s} cp=U+{x} ppem={d}: {s}\n",
        .{ fixture.path, fixture.codepoint, fixture.ppem, @errorName(err) },
    );
    try expectType2Commands(expected, actual.commands.items);
    const actual_advance: i32 = @intFromFloat(@round(actual.advance_width * 64));
    if (expected.advance != actual_advance) {
        std.debug.print(
            "Type2 advance ft={d} cj={d}\n",
            .{ expected.advance, actual_advance },
        );
        return error.HintingMismatch;
    }
}

fn expectType2Commands(
    expected: FtOutline,
    commands: []const cangjie.font.OutlineCommand,
) !void {
    var point_index: usize = 0;
    var contour_index: usize = 0;
    var contour_start: ?cangjie.font.OutlinePoint = null;
    for (commands, 0..) |command, command_index| {
        switch (command) {
            .move_to => |point| {
                if (point_index != 0 and
                    (contour_index == 0 or
                        point_index != @as(usize, expected.contours[contour_index - 1]) + 1))
                {
                    return error.HintingMismatch;
                }
                contour_start = point;
                try expectType2Point(expected, point_index, point, 1, command_index);
                point_index += 1;
            },
            .line_to => |point| {
                try expectType2Point(expected, point_index, point, 1, command_index);
                point_index += 1;
            },
            .cubic_to => |curve| {
                try expectType2Point(expected, point_index, curve.c0, 2, command_index);
                point_index += 1;
                try expectType2Point(expected, point_index, curve.c1, 2, command_index);
                point_index += 1;
                // FT_Outline represents a closing cubic cyclically: when its
                // endpoint equals the contour move, that endpoint is the
                // already-present first point rather than a duplicate point.
                const closes_to_start = command_index + 1 < commands.len and
                    commands[command_index + 1] == .close and
                    contour_start != null and std.meta.eql(contour_start.?, curve.end);
                if (!closes_to_start) {
                    try expectType2Point(expected, point_index, curve.end, 1, command_index);
                    point_index += 1;
                }
            },
            .quad_to => return error.HintingMismatch,
            .close => {
                if (contour_index >= expected.contours.len or point_index == 0 or
                    point_index - 1 != expected.contours[contour_index])
                {
                    return error.HintingMismatch;
                }
                contour_index += 1;
                contour_start = null;
            },
        }
    }
    try expectEqual(usize, expected.points.len, point_index);
    try expectEqual(usize, expected.contours.len, contour_index);
}

fn expectType2Point(
    expected: FtOutline,
    index: usize,
    actual: cangjie.font.OutlinePoint,
    wanted_tag: u8,
    command_index: usize,
) !void {
    if (index >= expected.points.len or
        (expected.tags[index] & 3) != wanted_tag)
    {
        return error.HintingMismatch;
    }
    const actual_point = Point{
        .x = @intFromFloat(@round(actual.x * 64)),
        .y = @intFromFloat(@round(actual.y * 64)),
    };
    if (!std.meta.eql(expected.points[index], actual_point)) {
        const lo = index - @min(index, 3);
        const hi = @min(expected.points.len, index + 4);
        std.debug.print("nearby FT points:\n", .{});
        for (expected.points[lo..hi], expected.tags[lo..hi], lo..) |near, tag, near_index| {
            std.debug.print("  {d}: ({d},{d}) tag={d}\n", .{ near_index, near.x, near.y, tag & 3 });
        }
        std.debug.print(
            "Type2 command={d} point={d} ft=({d},{d}) cj=({d},{d})\n",
            .{
                command_index,
                index,
                expected.points[index].x,
                expected.points[index].y,
                actual_point.x,
                actual_point.y,
            },
        );
        return error.HintingMismatch;
    }
}

fn freeTypeVersionAtLeast(wanted_major: c_int, wanted_minor: c_int) !bool {
    var library: ft.FT_Library = null;
    if (ft.FT_Init_FreeType(&library) != 0) return error.FreeTypeFailed;
    defer _ = ft.FT_Done_FreeType(library);
    var major: c_int = 0;
    var minor: c_int = 0;
    var patch: c_int = 0;
    ft.FT_Library_Version(library, &major, &minor, &patch);
    return major > wanted_major or
        (major == wanted_major and minor >= wanted_minor);
}

fn compareFixture(
    fixture: Fixture,
    interpreter: cangjie.font.HintingInterpreter,
    target: Target,
) !void {
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
        try face.hintingInstanceWithOptions(
            allocator,
            fixture.ppem,
            .{
                .target = target.cangjieTarget(),
                .interpreter = interpreter,
            },
        )
    else
        try face.hintingInstanceAtWithOptions(
            allocator,
            fixture.ppem,
            .{
                .target = target.cangjieTarget(),
                .interpreter = interpreter,
            },
            fixture.location,
        );
    defer instance.deinit();
    var transaction = try face.hintingPointTransaction(
        allocator,
        &instance,
        glyph_id,
    );
    defer transaction.deinit();
    try face.executeHintingTransactionInPlace(&instance, &transaction);

    const expected = try freeTypeOutline(
        allocator,
        bytes,
        glyph_id,
        fixture.ppem,
        fixture.location,
        interpreter,
        target,
    );
    defer expected.deinit(allocator);
    dumpHintPoints(&transaction, expected);
    errdefer |err| std.debug.print(
        "hint diff version={s} target={s} font={s} cp=U+{x} ppem={d}: {s}\n",
        .{
            @tagName(interpreter),
            @tagName(target),
            fixture.path,
            fixture.codepoint,
            fixture.ppem,
            @errorName(err),
        },
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
    const actual_advance = transaction.horizontalAdvance();
    if (expected.advance != actual_advance) {
        std.debug.print(
            "advance ft={d} cj={d}\n",
            .{ expected.advance, actual_advance },
        );
        return error.HintingMismatch;
    }
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

fn dumpHintPoints(
    transaction: *const cangjie.font.HintingPointTransaction,
    expected: FtOutline,
) void {
    if (std.c.getenv("CANGJIE_DEBUG_HINT_POINTS") == null) return;
    const pp1 = transaction.phantomPoints()[0];
    for (
        transaction.points[0..transaction.real_point_count],
        transaction.original[0..transaction.real_point_count],
        transaction.unscaled[0..transaction.real_point_count],
        transaction.flags[0..transaction.real_point_count],
        0..,
    ) |point, original, unscaled, flag, index| {
        std.debug.print(
            "CJH {d} {d} {d} {d} {d} {d} {d} {d} {d}\n",
            .{
                index,
                point.x - pp1.x,
                point.y - pp1.y,
                original.x - pp1.x,
                original.y - pp1.y,
                unscaled.x,
                unscaled.y,
                @intFromBool(flag.touched_x),
                @intFromBool(flag.touched_y),
            },
        );
    }
    for (expected.points, expected.tags, 0..) |point, tag, index| {
        std.debug.print(
            "FTH {d} {d} {d} {d}\n",
            .{ index, point.x, point.y, tag & 3 },
        );
    }
}

fn freeTypeOutline(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    glyph_id: cangjie.font.GlyphId,
    ppem: u16,
    location: []const f32,
    interpreter: ?cangjie.font.HintingInterpreter,
    target: Target,
) !FtOutline {
    var library: ft.FT_Library = null;
    if (ft.FT_Init_FreeType(&library) != 0) return error.FreeTypeFailed;
    defer _ = ft.FT_Done_FreeType(library);
    if (interpreter) |selected| {
        const version: ft.FT_UInt = switch (selected) {
            .classic => 35,
            .cleartype => 40,
        };
        if (ft.cangjie_ft_select_interpreter(library, version) != 0) {
            return error.FreeTypeInterpreterUnavailable;
        }
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
        @as(ft.FT_Int32, @intCast(
            ft.FT_LOAD_NO_BITMAP | ft.FT_LOAD_NO_AUTOHINT,
        )) |
            target.freeTypeFlag(),
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
