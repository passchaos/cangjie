//! Integration tests for v40 policy across size and glyph execution.

const std = @import("std");

const instance_mod = @import("../instance.zig");
const outline = @import("../outline.zig");
const types = @import("../types.zig");

test "v40 compatibility suppresses X and post-IUP Y movement" {
    var source = glyphTestSource(0x4040);
    source.interpreter = .cleartype;
    var instance = try instance_mod.Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    const instructions = &.{
        0xb0, 0, 0x2f, // X MDAP: touched, but compatibility blocks movement.
        0x00, // SVTCA[Y].
        0xb0, 0, 0x2f, // Y MDAP still moves before both IUP axes.
        0xb0, 1, 0x2e, // Touch point 1 on Y without moving it.
        0x30, 0x31, // IUP[Y], IUP[X] enter the post-IUP state.
        0xb0, 1, 0x2f, // Post-IUP Y movement is blocked.
    };
    var transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        instructions,
    );
    defer transaction.deinit();
    transaction.interpreter = .cleartype;
    transaction.backward_compatibility = true;
    for (
        transaction.points[0..2],
        transaction.original[0..2],
        transaction.unscaled[0..2],
    ) |*point, *original, *unscaled| {
        point.y = 35;
        original.y = 35;
        unscaled.y = 35;
    }

    try instance.executeGlyph(&transaction, null);
    try std.testing.expectEqual(
        outline.Point{ .x = 35, .y = 64 },
        transaction.points[0],
    );
    try std.testing.expectEqual(@as(i32, 35), transaction.points[1].y);
    try std.testing.expect(transaction.flags[0].touched_x);
    try std.testing.expect(transaction.flags[0].touched_y);
    try std.testing.expect(transaction.flags[1].touched_y);
}

test "v40 filters SHPIX DELTAP and post-IUP curve edits" {
    var source = glyphTestSource(0x4041);
    source.interpreter = .cleartype;
    var instance = try instance_mod.Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    const instructions = &.{
        0x00, // SVTCA[Y].
        0xb1, 0, 64, 0x38, // Untouched point 0 SHPIX is fully filtered.
        0xb0, 0, 0x2e, // A separate Y instruction touches point 0.
        0xb1, 0, 64, 0x38, // A previously Y-touched point may move.
        0xb2, 0x78, 1, 1, 0x5d, // Untouched point 1 DELTAP is blocked.
        0xb0, 1, 0x2e, // Touch point 1 on Y.
        0xb2, 0x78, 1, 1, 0x5d, // The same DELTAP now moves it by 1/8px.
        0x30, 0x31, // Post-IUP curfew.
        0xb0, 0, 0x80, // FLIPPT is blocked.
        0xb1, 0, 1, 0x82, // FLIPRGOFF is blocked.
    };
    var transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        instructions,
    );
    defer transaction.deinit();
    transaction.interpreter = .cleartype;
    transaction.backward_compatibility = true;

    try instance.executeGlyph(&transaction, null);
    try std.testing.expectEqual(@as(i32, 64), transaction.points[0].y);
    try std.testing.expectEqual(@as(i32, 8), transaction.points[1].y);
    try std.testing.expect(transaction.flags[0].on_curve);
    try std.testing.expect(transaction.flags[1].on_curve);
}

test "v40 native ClearType waivers restore classic movement" {
    var source = glyphTestSource(0x4042);
    source.interpreter = .cleartype;
    source.control_value_program = &.{
        0xb1, 4, 3, 0x8e, // prep INSTCTRL[value=4, selector=3].
    };
    var prep_waived = try instance_mod.Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer prep_waived.deinit();
    var prep_transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        &.{ 0xb0, 0, 0x2f },
    );
    defer prep_transaction.deinit();
    prep_transaction.interpreter = .cleartype;
    prep_transaction.backward_compatibility = false;
    try prep_waived.executeGlyph(&prep_transaction, null);
    try std.testing.expectEqual(@as(i32, 64), prep_transaction.points[0].x);

    source.control_value_program = &.{};
    var glyph_waived = try instance_mod.Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer glyph_waived.deinit();
    var glyph_transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        &.{
            0xb1, 4, 3,    0x8e, // glyph-local native ClearType waiver.
            0xb0, 0, 0x2f,
        },
    );
    defer glyph_transaction.deinit();
    glyph_transaction.interpreter = .cleartype;
    glyph_transaction.backward_compatibility = true;
    try glyph_waived.executeGlyph(&glyph_transaction, null);
    try std.testing.expectEqual(@as(i32, 64), glyph_transaction.points[0].x);
}

test "v40 compatibility preserves pre-program phantom metrics" {
    var source = glyphTestSource(0x4043);
    source.interpreter = .cleartype;
    var instance = try instance_mod.Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    var transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        &.{
            0x00, // SVTCA[Y].
            0xb1, 5, 44, 0x48, // SCFS top phantom Y from 640 to 44.
        },
    );
    defer transaction.deinit();
    transaction.interpreter = .cleartype;
    transaction.backward_compatibility = true;
    transaction.points[transaction.real_point_count + 1].x = 650;
    transaction.original[transaction.real_point_count + 1].x = 650;
    transaction.unscaled[transaction.real_point_count + 1].x = 650;

    try instance.executeGlyph(&transaction, null);
    try std.testing.expectEqual(
        @as(i32, 640),
        transaction.phantomPoints()[2].y,
    );
    try std.testing.expectEqual(
        @as(i32, 650),
        transaction.phantomPoints()[1].x,
    );
    try std.testing.expectEqual(
        @as(i32, 640),
        transaction.horizontalAdvance(),
    );
}

test "v40 compatibility preserves a non-grid-fitted source advance" {
    var source = glyphTestSource(0x4045);
    source.interpreter = .cleartype;
    var instance = try instance_mod.Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    var transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        &.{ 0xb1, 5, 44, 0x48 },
    );
    defer transaction.deinit();
    transaction.interpreter = .cleartype;
    transaction.backward_compatibility = true;
    transaction.points[transaction.real_point_count].x = 13;
    transaction.points[transaction.real_point_count + 1].x = 663;

    try instance.executeGlyph(&transaction, null);
    try std.testing.expectEqual(@as(i32, 640), transaction.horizontalAdvance());
}

test "disabled hinting does not round or execute glyph programs" {
    var source = glyphTestSource(0x4044);
    source.control_value_program = &.{
        0xb1, 1, 1, 0x8e, // prep INSTCTRL[value=1, selector=1].
    };
    var instance = try instance_mod.Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    var transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        &.{ 0xb0, 0, 0x2f },
    );
    defer transaction.deinit();
    transaction.hinting_enabled = false;
    transaction.points[transaction.real_point_count + 1].x = 650;
    transaction.original[transaction.real_point_count + 1].x = 650;
    transaction.unscaled[transaction.real_point_count + 1].x = 650;

    try instance.executeGlyph(&transaction, null);
    try std.testing.expectEqual(@as(i32, 35), transaction.points[0].x);
    try std.testing.expectEqual(@as(i32, 650), transaction.horizontalAdvance());
    try std.testing.expect(!transaction.grid_fit_metrics);
}

fn glyphTestSource(face_identity: usize) types.Source {
    return .{
        .face_identity = face_identity,
        .units_per_em = 1024,
        .font_program = &.{},
        .control_value_program = &.{},
        .control_value_data = &.{ 0, 64 },
        .limits = .{
            .max_storage = 1,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = 16,
            .max_twilight_points = 2,
        },
    };
}

fn glyphTestTransaction(
    allocator: std.mem.Allocator,
    face_identity: usize,
    instructions: []const u8,
) !outline.Transaction {
    const source_points = [_]outline.Point{
        .{ .x = 35, .y = 0 },
        .{ .x = 96, .y = 0 },
        .{ .x = 150, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = 640, .y = 0 },
        .{ .x = 0, .y = 640 },
        .{ .x = 0, .y = -640 },
    };
    const points = try allocator.dupe(outline.Point, &source_points);
    errdefer allocator.free(points);
    const original = try allocator.dupe(outline.Point, &source_points);
    errdefer allocator.free(original);
    const unscaled = try allocator.dupe(outline.Point, &source_points);
    errdefer allocator.free(unscaled);
    const flags = try allocator.alloc(outline.PointFlag, source_points.len);
    errdefer allocator.free(flags);
    @memset(flags, .{ .on_curve = true });
    const contours = try allocator.dupe(u16, &.{2});
    errdefer allocator.free(contours);
    return .{
        .allocator = allocator,
        .face_identity = face_identity,
        .target = .normal,
        .interpreter = .classic,
        .glyph_id = 1,
        .real_point_count = 3,
        .points = points,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = contours,
        .instructions = instructions,
        .scale_16_16 = 0x10000,
    };
}
