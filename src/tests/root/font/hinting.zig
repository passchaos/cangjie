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
