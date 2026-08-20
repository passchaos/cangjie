//! Caller-driven retained breaking for vertical paragraph columns.

const std = @import("std");
const paragraph = @import("../../../../api/paragraph/root.zig");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "vertical breaker commits columns and matches retained layout" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "AAAAA",
        20,
        .{ .max_width = 40, .writing_mode = .vertical_lr, .text_orientation = .upright },
    );
    defer shaped.deinit();
    const options = paragraph.Options{
        .max_width = 40,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    };
    var expected_buffer = support.ReflowBuffer.init(allocator);
    defer expected_buffer.deinit();
    const expected = try shaped.layout(&expected_buffer, options);
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var breaker = try shaped.breakLines(&reflow, options);
    defer breaker.deinit();

    var count: usize = 0;
    while (true) {
        switch (try breaker.advance(.{})) {
            .line => {
                count += 1;
                try std.testing.expectEqual(count, (try breaker.partialLayout()).lines.len);
            },
            .height_exceeded => return error.UnexpectedHeightExceeded,
            .complete => |result| {
                try std.testing.expectEqual(expected.lines.len, count);
                try std.testing.expectEqualSlices(paragraph.Line, expected.lines, result.lines);
                try std.testing.expectEqualSlices(@TypeOf(expected.glyphs[0]), expected.glyphs, result.glyphs);
                break;
            },
        }
    }
}

test "vertical breaker retries the same source column in a caller region" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "AAAA",
        20,
        .{ .max_width = 60, .writing_mode = .vertical_rl, .text_orientation = .upright },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var breaker = try shaped.breakLines(&reflow, .{
        .max_width = 60,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    defer breaker.deinit();

    const exceeded = switch (try breaker.advance(.{
        .region = .{ .x = 100, .y = 10, .width = 60 },
        .max_height = 30,
    })) {
        .height_exceeded => |value| value,
        else => return error.ExpectedHeightExceeded,
    };
    try std.testing.expectEqual(@as(usize, 0), (try breaker.partialLayout()).lines.len);
    const moved = switch (try breaker.advance(.{
        .region = .{ .x = 70, .y = 20, .width = 40 },
        .max_height = 40,
    })) {
        .line => |line| line,
        else => return error.ExpectedMovedColumn,
    };
    try std.testing.expectEqual(exceeded.byte_start, moved.byte_start);
    try std.testing.expectApproxEqAbs(@as(f32, 70), moved.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), moved.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), moved.region_inline_size, 0.001);
}

test "vertical breaker finalizes bidi objects and optical presentation once" {
    const allocator = std.testing.allocator;
    const marker = paragraph.object_replacement_utf8;
    const bytes = try @import("../../../../test_font.zig").buildCodepointSetTtf(
        allocator,
        &.{ 'A', 'B', 0x05d0, 0x05d1, 0x3002 },
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const text = "AאבB" ++ marker ++ "A。";
    const object = paragraph.InlineObject{
        .id = 9,
        .byte_index = "AאבB".len,
        .width = 24,
        .height = 20,
    };
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{
            .max_width = 200,
            .inline_objects = &.{object},
            .writing_mode = .vertical_lr,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var breaker = try shaped.breakLines(&reflow, .{
        .max_width = 200,
        .punctuation = .{ .end_hanging_fraction = 0.5 },
        .inline_objects = &.{object},
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    defer breaker.deinit();

    while (true) switch (try breaker.advance(.{})) {
        .line => {},
        .height_exceeded => return error.UnexpectedHeightExceeded,
        .complete => |result| {
            try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
            var saw_hanging = false;
            for (result.lines) |line| saw_hanging = saw_hanging or line.hang_end > 0;
            try std.testing.expect(saw_hanging);
            try std.testing.expectEqual(@as(u64, 9), result.inline_objects[0].id);
            break;
        },
    };
}
