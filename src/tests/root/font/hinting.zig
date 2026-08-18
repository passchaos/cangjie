//! Public TrueType PPEM hint-instance integration.

const std = @import("std");

const cangjie = @import("../../../root.zig");
const glyph = @import("../../../glyph.zig");
const test_font = @import("../../../test_font.zig");

test "TrueType hinting instance executes fpgm and prep" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildTrueTypeHintingTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();

    var instance = try face.hintingInstance(allocator, 16, .normal);
    defer instance.deinit();
    try std.testing.expectEqual(@as(u16, 16), instance.ppem);
    try std.testing.expectEqual(
        @as(usize, 2),
        instance.controlValues().len,
    );
    try std.testing.expectEqual(@as(i32, 96), instance.controlValues()[0]);
    try std.testing.expectEqual(@as(i32, -5), instance.controlValues()[1]);
    // MPPEM 16 plus FDEF0's +2.
    try std.testing.expectEqual(@as(i32, 18), instance.storageValues()[0]);
    try std.testing.expectEqual(
        @as(i32, 72),
        instance.graphicsState().control_value_cutin,
    );
    try std.testing.expect(instance.isEnabled());

    var larger = try face.hintingInstance(allocator, 20, .light);
    defer larger.deinit();
    try std.testing.expectEqual(@as(i32, 22), larger.storageValues()[0]);
    try std.testing.expectEqual(
        cangjie.font.HintingTarget.light,
        larger.graphicsState().target,
    );
}

test "TrueType hinting rejects invalid sizes and borrowed mutations" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildTrueTypeHintingTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();

    try std.testing.expectError(
        error.InvalidHintPpem,
        face.hintingInstance(allocator, 0, .normal),
    );

    const tables = try cangjie.font.metadata.core.inspect(&face).tables(
        allocator,
    );
    defer allocator.free(tables);
    var prep_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "prep")) prep_offset = table.offset;
    }
    bytes[prep_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(
        error.BadSfnt,
        face.hintingInstance(allocator, 16, .normal),
    );
}

test "CFF faces do not expose TrueType hinting instances" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    try std.testing.expectError(
        error.UnsupportedGlyph,
        face.hintingInstance(allocator, 16, .normal),
    );
}

test "installed TrueType size programs execute for representative fonts" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
        "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf",
    };
    var found: usize = 0;
    for (paths) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            path,
            allocator,
            .limited(16 * 1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(bytes);
        var face = try cangjie.font.Face.parse(allocator, bytes);
        defer face.deinit();
        var instance = try face.hintingInstance(allocator, 16, .normal);
        defer instance.deinit();
        try std.testing.expectEqual(@as(u16, 16), instance.ppem);
        found += 1;
    }
    if (found == 0) return error.SkipZigTest;
}

test "installed simple glyph programs execute transactionally" {
    const allocator = std.testing.allocator;
    const fixtures = [_]struct {
        path: []const u8,
        codepoint: u21,
    }{
        .{
            .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            .codepoint = 'A',
        },
        .{
            .path = "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
            .codepoint = 0x0915,
        },
        .{
            .path = "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf",
            .codepoint = 0x0627,
        },
    };
    var found: usize = 0;
    for (fixtures) |fixture| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            fixture.path,
            allocator,
            .limited(16 * 1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(bytes);
        var face = try cangjie.font.Face.parse(allocator, bytes);
        defer face.deinit();
        var instance = try face.hintingInstance(allocator, 16, .normal);
        defer instance.deinit();
        const glyph_id = try face.glyphs().index(fixture.codepoint);
        var transaction = face.hintingPointTransaction(
            allocator,
            &instance,
            glyph_id,
        ) catch |err| switch (err) {
            error.UnsupportedHintGlyph => continue,
            else => return err,
        };
        defer transaction.deinit();
        try face.executeHintingTransaction(&instance, &transaction);
        var pixel = try transaction.toPixelOutline();
        defer pixel.deinit();
        try std.testing.expect(pixel.commands.items.len != 0);
        found += 1;
    }
    if (found == 0) return error.SkipZigTest;
}

test "installed compound glyph programs execute child-to-parent" {
    const allocator = std.testing.allocator;
    const fixtures = [_]struct {
        path: []const u8,
        codepoint: u21,
    }{
        .{
            .path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            .codepoint = 0x00c2,
        },
        .{
            .path = "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
            .codepoint = 0x0958,
        },
        .{
            .path = "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf",
            .codepoint = 0x060b,
        },
    };
    var found: usize = 0;
    for (fixtures) |fixture| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            fixture.path,
            allocator,
            .limited(16 * 1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(bytes);
        var face = try cangjie.font.Face.parse(allocator, bytes);
        defer face.deinit();
        var instance = try face.hintingInstance(allocator, 16, .normal);
        defer instance.deinit();
        const glyph_id = try face.glyphs().index(fixture.codepoint);
        var transaction = face.hintingPointTransaction(
            allocator,
            &instance,
            glyph_id,
        ) catch |err| switch (err) {
            error.UnsupportedHintGlyph => continue,
            else => return err,
        };
        defer transaction.deinit();
        if (!transaction.is_compound) continue;
        try face.executeHintingTransaction(&instance, &transaction);
        var pixel = try transaction.toPixelOutline();
        defer pixel.deinit();
        try std.testing.expect(pixel.commands.items.len != 0);
        found += 1;
    }
    if (found == 0) return error.SkipZigTest;
}

test "simple glyf transaction retains raw point and phantom ownership" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildTrueTypeHintingTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var instance = try face.hintingInstance(allocator, 16, .normal);
    defer instance.deinit();
    var transaction = try face.hintingPointTransaction(
        allocator,
        &instance,
        1,
    );
    defer transaction.deinit();

    try std.testing.expectEqual(@as(usize, 3), transaction.real_point_count);
    try std.testing.expectEqualSlices(u16, &.{2}, transaction.contours);
    try std.testing.expectEqual(@as(usize, 7), transaction.points.len);
    try std.testing.expectEqual(@as(usize, 0), transaction.instructions.len);
    try std.testing.expect(transaction.flags[0].on_curve);
    try std.testing.expect(transaction.flags[1].on_curve);
    try std.testing.expect(transaction.flags[2].on_curve);
    const phantom = transaction.phantomPoints();
    try std.testing.expectEqual(
        @as(i32, 819),
        phantom[1].x - phantom[0].x,
    );

    try face.executeHintingTransaction(&instance, &transaction);
    try std.testing.expectEqual(
        @as(i32, 832),
        transaction.phantomPoints()[1].x -
            transaction.phantomPoints()[0].x,
    );
    var pixel = try transaction.toPixelOutline();
    defer pixel.deinit();
    var design = try face.glyphs().outline(allocator, 1);
    defer design.deinit();
    try std.testing.expectEqual(design.commands.items.len, pixel.commands.items.len);
    const scale = 16.0 / @as(f32, @floatFromInt(face.properties().units_per_em));
    for (design.commands.items, pixel.commands.items) |expected, actual| {
        try expectScaledCommand(expected, actual, scale);
    }
}

test "point transactions reject foreign compound and variable ownership" {
    const allocator = std.testing.allocator;
    const first_bytes = try test_font.buildTrueTypeHintingTtf(allocator);
    defer allocator.free(first_bytes);
    const second_bytes = try test_font.buildTrueTypeHintingTtf(allocator);
    defer allocator.free(second_bytes);
    var first = try cangjie.font.Face.parse(allocator, first_bytes);
    defer first.deinit();
    var second = try cangjie.font.Face.parse(allocator, second_bytes);
    defer second.deinit();
    var instance = try first.hintingInstance(allocator, 16, .normal);
    defer instance.deinit();
    try std.testing.expectError(
        error.StaleHintingInstance,
        second.hintingPointTransaction(allocator, &instance, 1),
    );

    const compound_bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(compound_bytes);
    var compound = try cangjie.font.Face.parse(allocator, compound_bytes);
    defer compound.deinit();
    var compound_instance =
        try compound.hintingInstance(allocator, 16, .normal);
    defer compound_instance.deinit();
    try std.testing.expectError(
        error.UnsupportedHintGlyph,
        compound.hintingPointTransaction(
            allocator,
            &compound_instance,
            2,
        ),
    );

    const variable_bytes = try test_font.buildGvarTtf(allocator);
    defer allocator.free(variable_bytes);
    var variable = try cangjie.font.Face.parse(allocator, variable_bytes);
    defer variable.deinit();
    var variable_instance =
        try variable.hintingInstance(allocator, 16, .normal);
    defer variable_instance.deinit();
    try std.testing.expectError(
        error.UnsupportedHintGlyph,
        variable.hintingPointTransaction(
            allocator,
            &variable_instance,
            1,
        ),
    );
}

test "compound point transactions preserve transformed raw topology" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCompoundPointMatchTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var instance = try face.hintingInstance(allocator, 20, .normal);
    defer instance.deinit();

    var matched = try face.hintingPointTransaction(
        allocator,
        &instance,
        2,
    );
    defer matched.deinit();
    try std.testing.expect(matched.is_compound);
    try std.testing.expectEqual(@as(usize, 6), matched.real_point_count);
    try std.testing.expectEqualSlices(u16, &.{ 2, 5 }, matched.contours);
    try std.testing.expectEqual(@as(usize, 2), matched.components.len);
    try std.testing.expectEqual(
        @as(cangjie.font.GlyphId, 1),
        matched.components[0].glyph_id,
    );
    try std.testing.expectEqual(
        @as(cangjie.font.GlyphId, 1),
        matched.components[1].glyph_id,
    );
    const expected = [_]struct { x: i32, y: i32 }{
        .{ .x = 10, .y = 0 },
        .{ .x = 110, .y = 100 },
        .{ .x = 10, .y = 100 },
        .{ .x = 60, .y = 50 },
        .{ .x = 110, .y = 100 },
        .{ .x = 60, .y = 100 },
    };
    for (matched.unscaled[0..matched.real_point_count], expected) |actual, wanted| {
        try std.testing.expectEqual(wanted.x, actual.x);
        try std.testing.expectEqual(wanted.y, actual.y);
    }
    try std.testing.expectEqual(
        matched.unscaled[1],
        matched.unscaled[4],
    );
    try face.executeHintingTransaction(&instance, &matched);

    var nested = try face.hintingPointTransaction(
        allocator,
        &instance,
        3,
    );
    defer nested.deinit();
    try std.testing.expectEqual(@as(usize, 9), nested.real_point_count);
    try std.testing.expectEqualSlices(u16, &.{ 2, 5, 8 }, nested.contours);
    try std.testing.expectEqual(@as(i32, 110), nested.unscaled[6].x);
    try std.testing.expectEqual(@as(i32, 100), nested.unscaled[6].y);
    try std.testing.expectEqual(@as(i32, 210), nested.unscaled[7].x);
    try std.testing.expectEqual(@as(i32, 200), nested.unscaled[7].y);

    var pixel = try nested.toPixelOutline();
    defer pixel.deinit();
    var design = try face.glyphs().outline(allocator, 3);
    defer design.deinit();
    try std.testing.expectEqual(
        design.commands.items.len,
        pixel.commands.items.len,
    );
    const scale =
        20.0 / @as(f32, @floatFromInt(face.properties().units_per_em));
    for (design.commands.items, pixel.commands.items) |wanted, actual| {
        try expectScaledCommand(wanted, actual, scale);
    }
}

test "compound transactions retain parent bytecode and USE_MY_METRICS" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildTrueTypeCompoundHintingTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var instance = try face.hintingInstance(allocator, 20, .normal);
    defer instance.deinit();
    var transaction = try face.hintingPointTransaction(
        allocator,
        &instance,
        2,
    );
    defer transaction.deinit();

    try std.testing.expect(transaction.is_compound);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xb0, 0, 0x46, 0xb0, 0, 0x23, 0x42 },
        transaction.instructions,
    );
    try std.testing.expectEqual(@as(usize, 1), transaction.components.len);
    try std.testing.expect(transaction.components[0].use_my_metrics);
    try std.testing.expect(!transaction.components[0].is_compound);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xb1, 64, 0, 0x38 },
        transaction.components[0].instructions,
    );
    // Top-level glyph 2 advances 1000 FUnits, while USE_MY_METRICS selects
    // component glyph 1's 800-FUnit metric. At 20 PPEM / 1000 UPEM this is
    // exactly 16 pixels, or 1024 in 26.6.
    try std.testing.expectEqual(
        @as(i32, 1024),
        transaction.phantomPoints()[1].x -
            transaction.phantomPoints()[0].x,
    );
    try face.executeHintingTransaction(&instance, &transaction);
    // Child point 0 moves from 0 to 64, then receives the compound's scaled
    // +10 FUnit offset (13 in 26.6 at 20 PPEM).
    try std.testing.expectEqual(@as(i32, 77), transaction.points[0].x);
    try std.testing.expectEqual(@as(i32, 77), instance.storageValues()[0]);
    // Parent bytecode resets child touched flags before observing the zone.
    try std.testing.expect(!transaction.flags[0].touched_x);
}

test "compound parent failure rolls back child hinting and VM writes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildTrueTypeCompoundHintingTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var instance = try face.hintingInstance(allocator, 20, .normal);
    defer instance.deinit();
    var transaction = try face.hintingPointTransaction(
        allocator,
        &instance,
        2,
    );
    defer transaction.deinit();
    const before_points = try allocator.dupe(
        @TypeOf(transaction.points[0]),
        transaction.points,
    );
    defer allocator.free(before_points);
    const before_flags = try allocator.dupe(
        @TypeOf(transaction.flags[0]),
        transaction.flags,
    );
    defer allocator.free(before_flags);
    const before_storage = instance.storageValues()[0];

    // Tentatively write storage[0], then fail on an out-of-range CVT read.
    // The child program has already moved point 0 by the time this parent
    // program runs, so unchanged points prove rollback spans the full
    // child-to-parent lifecycle rather than only the failing VM invocation.
    const failing_program = [_]u8{ 0xb1, 0, 9, 0x42, 0xb0, 99, 0x45 };
    transaction.instructions = &failing_program;
    try std.testing.expectError(
        error.InvalidHintCvt,
        face.executeHintingTransaction(&instance, &transaction),
    );
    try std.testing.expectEqualSlices(
        @TypeOf(transaction.points[0]),
        before_points,
        transaction.points,
    );
    try std.testing.expectEqualSlices(
        @TypeOf(transaction.flags[0]),
        before_flags,
        transaction.flags,
    );
    try std.testing.expectEqual(
        before_storage,
        instance.storageValues()[0],
    );
}

test "hint transaction execution rejects stale PPEM ownership" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildTrueTypeHintingTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var source = try face.hintingInstance(allocator, 16, .normal);
    defer source.deinit();
    var other_size = try face.hintingInstance(allocator, 17, .normal);
    defer other_size.deinit();
    var transaction = try face.hintingPointTransaction(
        allocator,
        &source,
        1,
    );
    defer transaction.deinit();

    try std.testing.expectError(
        error.StaleHintingInstance,
        face.executeHintingTransaction(&other_size, &transaction),
    );
}

test "hinted pixel outlines rasterize without units-per-em rescaling" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildTrueTypeHintingTtf(allocator);
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var instance = try face.hintingInstance(allocator, 16, .normal);
    defer instance.deinit();
    var transaction = try face.hintingPointTransaction(
        allocator,
        &instance,
        1,
    );
    defer transaction.deinit();
    try face.executeHintingTransaction(&instance, &transaction);
    var pixel_outline = try transaction.toPixelOutline();
    defer pixel_outline.deinit();

    var direct = try cangjie.render.GrayTarget.init(allocator, 32, 32);
    defer direct.deinit();
    var prepared_target = try cangjie.render.GrayTarget.init(
        allocator,
        32,
        32,
    );
    defer prepared_target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    // The hinted path must not receive the design-outline small-glyph
    // alignment or emboldening policy a second time.
    rasterizer.setSmallGlyphEmboldening(true);
    try rasterizer.drawPixelOutline(
        &direct,
        &pixel_outline,
        3,
        24,
    );
    var prepared = try rasterizer.preparePixelOutline(
        &pixel_outline,
        3,
        24,
    );
    defer prepared.deinit();
    try rasterizer.drawPrepared(&prepared_target, &prepared);

    try std.testing.expectEqualSlices(
        u8,
        direct.pixels,
        prepared_target.pixels,
    );
    const bounds = coverageBounds(&direct) orelse
        return error.TestUnexpectedResult;
    // Glyph 1 spans roughly 11 pixels at 16 PPEM. A mistaken UPEM scale would
    // collapse that width to a subpixel or move it out of this placement.
    try std.testing.expect(bounds.max_x - bounds.min_x >= 8);
    try std.testing.expect(bounds.min_x >= 2);
    try std.testing.expect(bounds.max_x <= 16);
}

const CoverageBounds = struct {
    min_x: u32,
    min_y: u32,
    max_x: u32,
    max_y: u32,
};

fn coverageBounds(
    target: *const cangjie.render.GrayTarget,
) ?CoverageBounds {
    var result: ?CoverageBounds = null;
    for (0..target.height) |y_value| {
        const y: u32 = @intCast(y_value);
        for (0..target.width) |x_value| {
            const x: u32 = @intCast(x_value);
            if (target.at(x, y) == 0) continue;
            if (result) |*bounds| {
                bounds.min_x = @min(bounds.min_x, x);
                bounds.min_y = @min(bounds.min_y, y);
                bounds.max_x = @max(bounds.max_x, x);
                bounds.max_y = @max(bounds.max_y, y);
            } else {
                result = .{
                    .min_x = x,
                    .min_y = y,
                    .max_x = x,
                    .max_y = y,
                };
            }
        }
    }
    return result;
}

fn expectScaledCommand(
    expected: glyph.PathCommand,
    actual: glyph.PathCommand,
    scale: f32,
) !void {
    switch (expected) {
        .move_to => |point| switch (actual) {
            .move_to => |found| try expectScaledPoint(point, found, scale),
            else => return error.TestExpectedEqual,
        },
        .line_to => |point| switch (actual) {
            .line_to => |found| try expectScaledPoint(point, found, scale),
            else => return error.TestExpectedEqual,
        },
        .quad_to => |curve| switch (actual) {
            .quad_to => |found| {
                try expectScaledPoint(curve.control, found.control, scale);
                try expectScaledPoint(curve.end, found.end, scale);
            },
            else => return error.TestExpectedEqual,
        },
        .cubic_to => return error.TestUnexpectedResult,
        .close => switch (actual) {
            .close => {},
            else => return error.TestExpectedEqual,
        },
    }
}

fn expectScaledPoint(
    expected: glyph.Point,
    actual: glyph.Point,
    scale: f32,
) !void {
    // Raw VM coordinates are quantized to signed 26.6 pixels.
    const half_step = 1.0 / 128.0;
    try std.testing.expectApproxEqAbs(
        expected.x * scale,
        actual.x,
        half_step,
    );
    try std.testing.expectApproxEqAbs(
        expected.y * scale,
        actual.y,
        half_step,
    );
}
