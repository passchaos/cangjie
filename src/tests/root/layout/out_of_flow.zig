//! Replay/resume custom out-of-flow placement across paragraph paths.

const std = @import("std");

const paragraph_api = @import("../../../api/paragraph/root.zig");
const inline_object = @import("../../../layout/inline_object/root.zig");
const render_bridge = @import("../../../render/bridge/root.zig");
const support = @import("../support.zig");
const test_font = @import("../../../test_font.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const ReflowBuffer = support.ReflowBuffer;
const StyledParagraphBuffer = support.StyledParagraphBuffer;
const StyledParagraphSpan = support.StyledParagraphSpan;
const TextShaper = support.TextShaper;

test "direct custom out-of-flow placement overrides the anchor fallback" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A" ++ inline_object.object_replacement_utf8 ++ "A";
    const object = inline_object.Object{
        .id = 70,
        .kind = .custom_out_of_flow,
        .byte_index = 1,
        .width = 10,
        .height = 10,
    };
    const placement = inline_object.Placement{
        .byte_index = 1,
        .geometry = .{
            .x = 71,
            .y = 83,
            .width = 23,
            .height = 29,
            .baseline = 17,
        },
    };
    const options = paragraph_api.Options{
        .max_width = 100,
        .inline_objects = &.{object},
        .out_of_flow_placements = &.{placement},
    };

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var resolver = paragraph_api.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(options);
    const pass_value = try resolver.pass();
    const paragraph = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        pass_value.options,
    );

    const positioned = paragraph.inline_objects[0];
    try std.testing.expectEqual(inline_object.Kind.custom_out_of_flow, positioned.kind);
    try std.testing.expectApproxEqAbs(@as(f32, 71), positioned.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 83), positioned.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 23), positioned.width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 29), positioned.height, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 17), positioned.baseline, 0.001);
    try std.testing.expect(positioned.anchor_x != positioned.x);
    try std.testing.expect(positioned.anchor_y != positioned.y);
    // Absolute out-of-flow paint bounds do not redefine the text paragraph's
    // occupied measure. Callers reserve text space explicitly via exclusions.
    try std.testing.expect(paragraph.height < positioned.y);
    try std.testing.expectEqual(
        paragraph_api.OutOfFlowStep.complete,
        try resolver.next(pass_value, paragraph),
    );
    try std.testing.expectEqual(@as(usize, 1), resolver.placements().len);

    var draw_list = try render_bridge.buildGlyphDrawList(
        allocator,
        paragraph,
        .{ .origin_x = 5, .origin_y = 7 },
    );
    defer draw_list.deinit();
    try std.testing.expectApproxEqAbs(
        positioned.x + 5,
        draw_list.inline_objects[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        positioned.y + 7,
        draw_list.inline_objects[0].y,
        0.001,
    );
}

test "retained custom resolver replays exclusions and preserves placements" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const marker = inline_object.object_replacement_utf8;
    const text = marker ++ "A A " ++ marker ++ "A A A";
    const objects = [_]inline_object.Object{
        .{
            .id = 1,
            .kind = .custom_out_of_flow,
            .byte_index = 0,
            .width = 18,
            .height = 20,
        },
        .{
            .id = 2,
            .kind = .custom_out_of_flow,
            .byte_index = marker.len + "A A ".len,
            .width = 12,
            .height = 20,
        },
    };
    const static_exclusion = paragraph_api.Exclusion{
        .x = 100,
        .y = 0,
        .width = 10,
        .height = 20,
    };
    const base_options = paragraph_api.Options{
        .max_width = 80,
        .inline_objects = &objects,
        .exclusions = &.{static_exclusion},
    };

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&fonts),
        &shape_buffer,
        text,
        20,
        base_options,
    );
    defer shaped.deinit();
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var resolver = paragraph_api.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(base_options);
    try std.testing.expectError(
        error.OutOfFlowPlacementIncomplete,
        resolver.resolvedOptions(),
    );

    const first_pass = try resolver.pass();
    const first_layout = try shaped.layout(&reflow, first_pass.options);
    const first_step = try resolver.next(first_pass, first_layout);
    const first_request = switch (first_step) {
        .place => |request| request,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try std.testing.expectError(
        error.OutOfFlowPlacementPending,
        resolver.pass(),
    );
    try std.testing.expectEqual(
        first_request,
        switch (try resolver.next(first_pass, first_layout)) {
            .place => |request| request,
            .complete => return error.TestExpectedPlacementRequest,
        },
    );
    try std.testing.expectEqual(@as(u64, 1), first_request.object_id);
    try std.testing.expectEqual(@as(usize, 0), first_request.byte_index);
    try resolver.submit(first_request, .{
        .geometry = .{
            .x = first_request.anchor_x,
            .y = first_request.anchor_y,
            .width = 28,
            .height = 30,
            .baseline = 20,
        },
        .exclusion = .{
            .x = 0,
            .y = 0,
            .width = 40,
            .height = 60,
        },
    });

    try std.testing.expectError(
        error.StaleOutOfFlowPass,
        resolver.next(first_pass, first_layout),
    );
    const second_pass = try resolver.pass();
    const second_layout = try shaped.layout(&reflow, second_pass.options);
    const second_request = switch (try resolver.next(second_pass, second_layout)) {
        .place => |request| request,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try std.testing.expectEqual(@as(u64, 2), second_request.object_id);
    try std.testing.expect(second_request.anchor_x >= 40);
    try resolver.submit(second_request, .{
        .geometry = .{
            .x = 50,
            .y = 70,
            .width = 16,
            .height = 18,
        },
    });

    const final_pass = try resolver.pass();
    const final_layout = try shaped.layout(&reflow, final_pass.options);
    try std.testing.expectEqual(
        paragraph_api.OutOfFlowStep.complete,
        try resolver.next(final_pass, final_layout),
    );
    const resolved_options = try resolver.resolvedOptions();
    try std.testing.expectEqual(@as(usize, 2), resolved_options.out_of_flow_placements.len);
    try std.testing.expectEqual(@as(usize, 2), resolver.exclusions().len);
    try std.testing.expectEqual(static_exclusion, resolver.exclusions()[0]);
    try std.testing.expectEqual(@as(usize, 2), final_layout.inline_objects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 28), final_layout.inline_objects[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50), final_layout.inline_objects[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 70), final_layout.inline_objects[1].y, 0.001);

    // The final options are resolver-owned but are valid input to a fresh
    // session on that same resolver; `begin` snapshots before mutating storage.
    try resolver.begin(resolved_options);
    try std.testing.expectEqual(@as(usize, 2), resolver.placements().len);
    try std.testing.expectEqual(@as(usize, 2), resolver.exclusions().len);
}

test "custom resolver skips truncated objects" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const marker = inline_object.object_replacement_utf8;
    const text = "A A A A " ++ marker;
    const object = inline_object.Object{
        .id = 11,
        .kind = .custom_out_of_flow,
        .byte_index = "A A A A ".len,
        .width = 10,
        .height = 10,
    };
    const options = paragraph_api.Options{
        .max_width = 30,
        .max_lines = 1,
        .inline_objects = &.{object},
    };
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var resolver = paragraph_api.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(options);
    const pass_value = try resolver.pass();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        pass_value.options,
    );
    try std.testing.expectEqual(@as(usize, 0), layout.inline_objects.len);
    try std.testing.expectEqual(
        paragraph_api.OutOfFlowStep.complete,
        try resolver.next(pass_value, layout),
    );
}

test "resolver rejects a replay that hides an accepted placement" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const marker = inline_object.object_replacement_utf8;
    const text = marker ++ " A A A A";
    const object = inline_object.Object{
        .id = 12,
        .kind = .custom_out_of_flow,
        .byte_index = 0,
        .width = 10,
        .height = 10,
    };
    const options = paragraph_api.Options{
        .max_width = 50,
        .max_lines = 1,
        .inline_objects = &.{object},
    };
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var resolver = paragraph_api.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(options);

    const first_pass = try resolver.pass();
    const first_layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        first_pass.options,
    );
    const request = switch (try resolver.next(first_pass, first_layout)) {
        .place => |value| value,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try resolver.submit(request, .{
        .geometry = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .exclusion = .{
            .x = 0,
            .y = 0,
            .width = 50,
            .height = 100,
        },
    });

    const replay_pass = try resolver.pass();
    // Deliberately supply an incompatible layout to exercise the resolver's
    // protection against accepting completion after a visible object vanished.
    var incompatible = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        "A",
        20,
        .{ .max_width = 50 },
    );
    incompatible.inline_objects = &.{};
    try std.testing.expectError(
        error.ResolvedOutOfFlowObjectHidden,
        resolver.next(replay_pass, incompatible),
    );
}

test "styled custom resolver preserves metadata across replay" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const marker = inline_object.object_replacement_utf8;
    const text = "A " ++ marker ++ " A A";
    const object = inline_object.Object{
        .id = 21,
        .kind = .custom_out_of_flow,
        .byte_index = "A ".len,
        .width = 12,
        .height = 12,
    };
    const spans = [_]StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 77,
        .font_size = 20,
    }};
    const base_options = paragraph_api.Options{
        .max_width = 60,
        .inline_objects = &.{object},
    };

    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    var resolver = paragraph_api.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(base_options);

    const first_pass = try resolver.pass();
    const first = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        first_pass.options,
    );
    const request = switch (try resolver.next(first_pass, first)) {
        .place => |value| value,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try resolver.submit(request, .{
        .geometry = .{
            .x = request.anchor_x + 5,
            .y = request.anchor_y + 7,
            .width = 24,
            .height = 26,
        },
        .exclusion = .{
            .x = 0,
            .y = 0,
            .width = 20,
            .height = 40,
        },
    });

    const final_pass = try resolver.pass();
    const final = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        final_pass.options,
    );
    try std.testing.expectEqual(
        paragraph_api.OutOfFlowStep.complete,
        try resolver.next(final_pass, final),
    );
    try std.testing.expectEqual(final.glyphs.len, styled.glyphMetadata().len);
    for (styled.glyphMetadata()) |metadata| {
        try std.testing.expectEqual(@as(u32, 77), metadata.style_index);
    }
    try std.testing.expectApproxEqAbs(
        request.anchor_x + 5,
        final.inline_objects[0].x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        request.anchor_y + 7,
        final.inline_objects[0].y,
        0.001,
    );
}

test "RTL custom resolver yields objects in logical source order" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const marker = inline_object.object_replacement_utf8;
    const first_index = "א".len;
    const second_index = first_index + marker.len + "ב".len;
    const text = "א" ++ marker ++ "ב" ++ marker ++ "ג";
    const objects = [_]inline_object.Object{
        .{
            .id = 31,
            .kind = .custom_out_of_flow,
            .byte_index = first_index,
            .width = 10,
            .height = 10,
        },
        .{
            .id = 32,
            .kind = .custom_out_of_flow,
            .byte_index = second_index,
            .width = 10,
            .height = 10,
        },
    };
    const options = paragraph_api.Options{
        .max_width = 100,
        .direction = .rtl,
        .inline_objects = &objects,
    };
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var resolver = paragraph_api.OutOfFlowResolver.init(allocator);
    defer resolver.deinit();
    try resolver.begin(options);

    const first_pass = try resolver.pass();
    const first_layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        first_pass.options,
    );
    const request = switch (try resolver.next(first_pass, first_layout)) {
        .place => |value| value,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try std.testing.expectEqual(first_index, request.byte_index);
    try std.testing.expectEqual(@as(u64, 31), request.object_id);
    try resolver.submit(request, .{
        .geometry = .{
            .x = request.anchor_x,
            .y = request.anchor_y,
            .width = 10,
            .height = 10,
        },
    });

    const second_pass = try resolver.pass();
    const second_layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &buffer,
        text,
        20,
        second_pass.options,
    );
    const second_request = switch (try resolver.next(second_pass, second_layout)) {
        .place => |value| value,
        .complete => return error.TestExpectedPlacementRequest,
    };
    try std.testing.expectEqual(second_index, second_request.byte_index);
    try std.testing.expectEqual(@as(u64, 32), second_request.object_id);
}
