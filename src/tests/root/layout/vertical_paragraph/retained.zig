//! Retained vertical reflow and writing-mode reuse.

const std = @import("std");
const support = @import("../../support.zig");
const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "retained vertical paragraph reflows without mutating its snapshot" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../../test_font.zig")
        .buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();

    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "AA",
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const first = try shaped.layout(&reflow, .{
        .max_width = 10,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
        .letter_spacing = 2,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 44), first.height, 0.001);
    const second = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), second.height, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        shaped.glyphs[0].y_advance,
        0.001,
    );
    const widths = try shaped.contentWidths(.{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 40), widths.min, 0.001);
    try std.testing.expectApproxEqAbs(widths.min, widths.max, 0.001);
    try std.testing.expectError(
        error.UnsupportedVerticalParagraphBreaker,
        shaped.breakLines(&reflow, .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        }),
    );
}

test "retained hard-break columns switch RL and LR without reshaping" {
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
        "A\nA",
        20,
        .{
            .max_width = 100,
            .wrap_mode = .no_wrap,
            .writing_mode = .vertical_rl,
            .text_orientation = .upright,
        },
    );
    defer shaped.deinit();
    var reflow = support.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const rl = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    });
    try std.testing.expect(rl.lines[0].x > rl.lines[1].x);
    const lr = try shaped.layout(&reflow, .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    });
    try std.testing.expect(lr.lines[0].x < lr.lines[1].x);
    try std.testing.expectApproxEqAbs(
        // The retained snapshot still contains the shaper's nominal control
        // advance. Each reflow output zeroes it transactionally.
        @as(f32, 20),
        shaped.glyphs[1].y_advance,
        0.001,
    );
}
