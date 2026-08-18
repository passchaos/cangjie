//! Public TrueType PPEM hint-instance integration.

const std = @import("std");

const cangjie = @import("../../../root.zig");
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
