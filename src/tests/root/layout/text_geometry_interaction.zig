//! Affinity-aware caret, hit-test, and selection fragment coverage.

const std = @import("std");

const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "text geometry affinity distinguishes both sides of a soft wrap" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    const text = "A A";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 20 },
    );
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expectEqual(layout.lines.len, geometry.lines.len);

    const boundary = layout.lines[1].byte_start;
    const upstream = geometry.caret(.{
        .byte_offset = boundary,
        .affinity = .upstream,
    }).?;
    const downstream = geometry.caret(.{
        .byte_offset = boundary,
        .affinity = .downstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 0), upstream.line_index);
    try std.testing.expectEqual(@as(usize, 1), downstream.line_index);
    try std.testing.expect(upstream.rect.y < downstream.rect.y);

    const second_line_hit = geometry.hitTest(
        downstream.rect.x,
        downstream.rect.y + 1,
    ).?;
    try std.testing.expectEqual(@as(usize, 1), second_line_hit.line_index);

    const across_lines = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = text.len },
    );
    defer allocator.free(across_lines);
    try std.testing.expectEqual(@as(usize, 2), across_lines.len);
    try std.testing.expectEqual(@as(usize, 0), across_lines[0].line_index);
    try std.testing.expectEqual(@as(usize, 1), across_lines[1].line_index);
}

test "text geometry retains trailing hard-break and empty paragraph carets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const text = "A\n";
    const trailing_layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{ .max_width = 100 },
    );
    var trailing = try paragraph.buildGeometry(
        allocator,
        text,
        trailing_layout,
        .{},
    );
    defer trailing.deinit();
    try std.testing.expectEqual(@as(usize, 2), trailing.lines.len);
    try std.testing.expectEqual(@as(usize, 0), trailing.lines[1].span_len);
    const final_caret = trailing.caret(.{
        .byte_offset = text.len,
        .affinity = .downstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 1), final_caret.line_index);
    try std.testing.expectApproxEqAbs(
        trailing.lines[1].bounds.y,
        final_caret.rect.y,
        0.001,
    );
    const final_hit = trailing.hitTest(
        final_caret.rect.x + 50,
        final_caret.rect.y + 1,
    ).?;
    try std.testing.expectEqual(text.len, final_hit.position.byte_offset);

    const empty_layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        "",
        20,
        .{ .max_width = 100 },
    );
    var empty = try paragraph.buildGeometry(
        allocator,
        "",
        empty_layout,
        .{},
    );
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 1), empty.lines.len);
    try std.testing.expectEqual(@as(usize, 0), empty.spans.len);
    const empty_caret = empty.caret(.{ .byte_offset = 0 }).?;
    try std.testing.expectEqual(@as(usize, 0), empty_caret.position.byte_offset);
    try std.testing.expect(empty_caret.rect.height > 0);
}

test "text geometry rejects non-boundary caret offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\u{0301}";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 100 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expect(geometry.caret(.{ .byte_offset = 1 }) == null);
    try std.testing.expect(geometry.caret(.{
        .byte_offset = text.len + 1,
    }) == null);
    try std.testing.expectError(
        error.InvalidTextRange,
        geometry.selectionFragments(
            allocator,
            .{ .byte_start = 1, .byte_end = text.len },
        ),
    );
    try std.testing.expectError(
        error.InvalidTextRange,
        geometry.selectionFragments(
            allocator,
            .{ .byte_start = text.len, .byte_end = 0 },
        ),
    );
    const empty_selection = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = 0 },
    );
    defer allocator.free(empty_selection);
    try std.testing.expectEqual(@as(usize, 0), empty_selection.len);
}

test "text geometry rejects selection ranges hidden by truncation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A A A";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{
            .max_width = 20,
            .max_lines = 1,
        },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectError(
        error.InvalidTextRange,
        geometry.selectionFragments(
            allocator,
            .{ .byte_start = 0, .byte_end = text.len },
        ),
    );
}
