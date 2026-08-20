//! Resumable retained paragraph line-breaking integration.

const std = @import("std");

const paragraph_api = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");
const test_font = @import("../../../test_font.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const ReflowBuffer = support.ReflowBuffer;
const TextShaper = support.TextShaper;

test "retained breaker commits one line at a time and matches final layout" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    const text = "A אב A A אב A";
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{ .max_width = 52 },
    );
    defer shaped.deinit();

    var expected_reflow = ReflowBuffer.init(allocator);
    defer expected_reflow.deinit();
    const options = paragraph_api.Options{
        .max_width = 52,
        .alignment = .justify,
    };
    const expected = try shaped.layout(&expected_reflow, options);

    var incremental_reflow = ReflowBuffer.init(allocator);
    defer incremental_reflow.deinit();
    var breaker = try shaped.breakLines(&incremental_reflow, options);
    defer breaker.deinit();

    var committed: usize = 0;
    while (true) {
        switch (try breaker.advance(.{})) {
            .line => |line| {
                committed += 1;
                const partial = try breaker.partialLayout();
                try std.testing.expectEqual(committed, partial.lines.len);
                try std.testing.expectEqual(line, partial.lines[committed - 1]);
            },
            .height_exceeded => return error.UnexpectedHeightExceeded,
            .complete => |actual| {
                try std.testing.expectEqual(expected.lines.len, committed);
                try std.testing.expectEqualSlices(
                    @TypeOf(expected.glyphs[0]),
                    expected.glyphs,
                    actual.glyphs,
                );
                try std.testing.expectEqualSlices(
                    @TypeOf(expected.runs[0]),
                    expected.runs,
                    actual.runs,
                );
                try std.testing.expectEqualSlices(
                    paragraph_api.Line,
                    expected.lines,
                    actual.lines,
                );
                try std.testing.expectEqual(expected.width, actual.width);
                try std.testing.expectEqual(expected.height, actual.height);
                try std.testing.expectError(
                    error.ParagraphBreakerComplete,
                    breaker.advance(.{}),
                );
                break;
            },
        }
    }
}

test "retained breaker checkpoint retries the same source line in a new column" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "A A A A A A A",
        20,
        .{ .max_width = 45 },
    );
    defer shaped.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var breaker = try shaped.breakLines(&reflow, .{ .max_width = 45 });
    defer breaker.deinit();

    const first = switch (try breaker.advance(.{ .region = .{
        .x = 0,
        .y = 0,
        .width = 45,
    } })) {
        .line => |line| line,
        else => return error.ExpectedFirstLine,
    };
    try std.testing.expectEqual(@as(usize, 0), first.byte_start);

    var checkpoint = try breaker.save();
    defer checkpoint.deinit();
    var foreign_reflow = ReflowBuffer.init(allocator);
    defer foreign_reflow.deinit();
    var foreign_breaker = try shaped.breakLines(
        &foreign_reflow,
        .{ .max_width = 45 },
    );
    defer foreign_breaker.deinit();
    try std.testing.expectError(
        error.StaleParagraphBreakerCheckpoint,
        foreign_breaker.restore(&checkpoint),
    );
    const old_second = switch (try breaker.advance(.{ .region = .{
        .x = 0,
        .y = 24,
        .width = 25,
    } })) {
        .line => |line| line,
        else => return error.ExpectedSecondLine,
    };
    try std.testing.expectApproxEqAbs(@as(f32, 0), old_second.region_x, 0.001);

    try breaker.restore(&checkpoint);
    try std.testing.expectEqual(
        @as(usize, 1),
        (try breaker.partialLayout()).lines.len,
    );
    const retried = switch (try breaker.advance(.{ .region = .{
        .x = 80,
        .y = 0,
        .width = 45,
    } })) {
        .line => |line| line,
        else => return error.ExpectedRetriedLine,
    };
    try std.testing.expectEqual(old_second.byte_start, retried.byte_start);
    try std.testing.expect(retried.byte_len > old_second.byte_len);
    try std.testing.expectApproxEqAbs(@as(f32, 80), retried.region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), retried.y, 0.001);

    while (true) {
        switch (try breaker.advance(.{})) {
            .line => {},
            .height_exceeded => return error.UnexpectedHeightExceeded,
            .complete => |layout| {
                try std.testing.expect(layout.lines.len >= 2);
                try std.testing.expectEqual(
                    retried.byte_start,
                    layout.lines[1].byte_start,
                );
                try std.testing.expectApproxEqAbs(
                    @as(f32, 80),
                    layout.lines[1].region_x,
                    0.001,
                );
                break;
            },
        }
    }
}

test "retained breaker checkpoint restores discretionary glyph mutations" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(allocator, &.{
        0x0020,
        0x002d,
        'a',
        'c',
        'e',
        'o',
        'p',
        'r',
        't',
        0x00ad,
        0x2010,
    });
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "co\u{00ad}operate",
        20,
        .{ .max_width = 1000 },
    );
    defer shaped.deinit();
    const hyphen_metrics = try font.horizontalMetrics(
        try font.glyphIndex(0x2010),
    );
    const narrow_width =
        shaped.glyphs[0].x_advance +
        shaped.glyphs[1].x_advance +
        @as(f32, @floatFromInt(hyphen_metrics.advance_width)) *
            (20.0 / @as(f32, @floatFromInt(font.units_per_em))) +
        0.5;
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var breaker = try shaped.breakLines(
        &reflow,
        .{ .max_width = narrow_width },
    );
    defer breaker.deinit();

    const pristine = try allocator.dupe(
        @TypeOf(shaped.glyphs[0]),
        shaped.glyphs,
    );
    defer allocator.free(pristine);
    var checkpoint = try breaker.save();
    defer checkpoint.deinit();
    _ = switch (try breaker.advance(.{})) {
        .line => |line| line,
        else => return error.ExpectedHyphenatedLine,
    };
    const selected = try breaker.partialLayout();
    var found_hyphen = false;
    for (selected.glyphs) |glyph| {
        found_hyphen = found_hyphen or glyph.isDiscretionaryHyphen();
    }
    try std.testing.expect(found_hyphen);

    try breaker.restore(&checkpoint);
    const restored = try breaker.partialLayout();
    try std.testing.expectEqual(@as(usize, 0), restored.lines.len);
    try std.testing.expectEqualSlices(
        @TypeOf(shaped.glyphs[0]),
        pristine,
        restored.glyphs,
    );
}

test "retained breaker rolls back height failures and rejects stale sessions" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "A A A",
        20,
        .{ .max_width = 40 },
    );
    defer shaped.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();

    try std.testing.expectError(
        error.ResumableBreakerRequiresGreedyStrategy,
        shaped.breakLines(&reflow, .{
            .max_width = 40,
            .line_break_strategy = .balanced,
        }),
    );

    var breaker = try shaped.breakLines(&reflow, .{ .max_width = 40 });
    defer breaker.deinit();
    try std.testing.expectError(
        error.InvalidParagraphBreakerInput,
        breaker.advance(.{ .max_height = std.math.nan(f32) }),
    );
    const exceeded = switch (try breaker.advance(.{
        .region = .{ .x = 0, .y = 0, .width = 40 },
        .max_height = 1,
    })) {
        .height_exceeded => |value| value,
        else => return error.ExpectedHeightExceeded,
    };
    try std.testing.expect(exceeded.required_height > 1);
    try std.testing.expectEqual(
        @as(usize, 0),
        (try breaker.partialLayout()).lines.len,
    );

    const moved = switch (try breaker.advance(.{
        .region = .{ .x = 70, .y = 100, .width = 40 },
        .max_height = 100,
    })) {
        .line => |line| line,
        else => return error.ExpectedMovedLine,
    };
    try std.testing.expectEqual(exceeded.byte_start, moved.byte_start);
    try std.testing.expectEqual(exceeded.byte_len, moved.byte_len);
    try std.testing.expectApproxEqAbs(@as(f32, 70), moved.region_x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 100), moved.y, 0.001);

    // Reusing the same output owner invalidates the breaker's borrowed session
    // rather than letting it continue over unrelated mutable arrays.
    _ = try shaped.layout(&reflow, .{ .max_width = 200 });
    try std.testing.expectError(
        error.StaleParagraphBreaker,
        breaker.advance(.{}),
    );
}

test "retained breaker preserves hard breaks and terminal truncation" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    const text = "A A\nA A A A";
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{ .max_width = 52 },
    );
    defer shaped.deinit();
    const options = paragraph_api.Options{
        .max_width = 52,
        .max_lines = 2,
        .ellipsis = true,
        .paragraph_spacing = 7,
    };

    var expected_reflow = ReflowBuffer.init(allocator);
    defer expected_reflow.deinit();
    const expected = try shaped.layout(&expected_reflow, options);

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var breaker = try shaped.breakLines(&reflow, options);
    defer breaker.deinit();
    var line_count: usize = 0;
    while (true) {
        switch (try breaker.advance(.{})) {
            .line => |line| {
                line_count += 1;
                if (line_count == 1) {
                    try std.testing.expectEqual(
                        @as(usize, "A A\n".len),
                        line.byte_len,
                    );
                }
            },
            .height_exceeded => return error.UnexpectedHeightExceeded,
            .complete => |layout| {
                try std.testing.expectEqual(@as(usize, 2), line_count);
                try std.testing.expectEqualSlices(
                    @TypeOf(expected.glyphs[0]),
                    expected.glyphs,
                    layout.glyphs,
                );
                try std.testing.expectEqualSlices(
                    paragraph_api.Line,
                    expected.lines,
                    layout.lines,
                );
                try std.testing.expectEqual(
                    @as(u21, '.'),
                    layout.glyphs[layout.glyphs.len - 1].codepoint,
                );
                break;
            },
        }
    }
}
