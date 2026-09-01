//! Engine integration coverage for reusable UAX #9 paragraph analysis.

const std = @import("std");

const face_mod = @import("../../../font/face/root.zig");
const Font = @import("../../../font.zig").Font;
const glyph_position = @import("../../../layout/glyph_position.zig");
const inline_object = @import("../../../layout/inline_object/root.zig");
const retained_styled = @import("../../../layout/paragraph/retained/styled.zig");
const paragraph_types = @import("../../../layout/types/paragraph.zig");
const run_types = @import("../../../layout/types/runs.zig");
const styled_buffer = @import("../../../layout/styled_buffer.zig");
const styled_paragraph = @import("../../../layout/styled_paragraph.zig");
const context_mod = @import("../root.zig");

test "one-shot uniform layout caches exact bidi paragraphs" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        std.testing.allocator,
        false,
    );
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&.{&font}));
    const request: context_mod.ParagraphRequest = .{
        .text = "abc \u{05d0}\u{05d1} 12",
        .font_size = 20,
        .options = .{ .max_width = 200, .direction = .ltr },
    };

    var engine = context_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const first = try engine.layout(cascade, request);
    const expected_glyphs = try std.testing.allocator.dupe(
        glyph_position.GlyphPosition,
        first.glyphs,
    );
    defer std.testing.allocator.free(expected_glyphs);
    const expected_lines = try std.testing.allocator.dupe(
        paragraph_types.ParagraphLine,
        first.lines,
    );
    defer std.testing.allocator.free(expected_lines);
    const analysis = &engine.state.styled_output.analysis;
    const scalar_ptr = analysis.bidi_paragraph.?.scalars.ptr;
    const class_ptr = analysis.bidi_paragraph.?.classes.ptr;
    const level_ptr = analysis.bidi_paragraph.?.levels.ptr;
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .misses = 1 },
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .misses = 1 },
        engine.stats().logical_analysis,
    );

    const second = try engine.layout(cascade, request);
    try std.testing.expectEqualSlices(
        glyph_position.GlyphPosition,
        expected_glyphs,
        second.glyphs,
    );
    try std.testing.expectEqualSlices(
        paragraph_types.ParagraphLine,
        expected_lines,
        second.lines,
    );
    try std.testing.expectEqual(scalar_ptr, analysis.bidi_paragraph.?.scalars.ptr);
    try std.testing.expectEqual(class_ptr, analysis.bidi_paragraph.?.classes.ptr);
    try std.testing.expectEqual(level_ptr, analysis.bidi_paragraph.?.levels.ptr);
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 1, .misses = 1 },
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 1, .misses = 1 },
        engine.stats().logical_analysis,
    );

    // Base direction is part of the exact cache identity even when all source
    // bytes match. A later source change must likewise replace the entry.
    _ = try engine.layout(cascade, .{
        .text = request.text,
        .font_size = request.font_size,
        .options = .{ .max_width = 200, .direction = .rtl },
    });
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 1, .misses = 2 },
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expectEqual(
        @import("../../../unicode.zig").BidiBaseDirection.rtl,
        analysis.bidi_base_direction,
    );

    const changed_text = "changed \u{05d2}";
    _ = try engine.layout(cascade, .{
        .text = changed_text,
        .font_size = request.font_size,
        .options = .{ .max_width = 200, .direction = .rtl },
    });
    try std.testing.expectEqualStrings(changed_text, analysis.bidi_text);
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 1, .misses = 3 },
        engine.stats().bidi_paragraphs,
    );

    engine.clearCaches();
    try std.testing.expectEqual(context_mod.Engine.Stats{}, engine.stats());
    try std.testing.expect(!analysis.bidi_valid);
    try std.testing.expect(analysis.bidi_paragraph == null);
    try std.testing.expectEqual(@as(usize, 0), analysis.bidi_text.len);
}

test "uniform and styled Engine layouts share exact bidi analysis" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&.{&font}));
    const text = "A \u{05d0}\u{05d1} B";
    const options: @import("../../../layout/paragraph/options.zig").Options =
        .{ .max_width = 200 };

    var engine = context_mod.Engine.init(allocator, .{});
    defer engine.deinit();
    const uniform = try engine.layout(cascade, .{
        .text = text,
        .font_size = 20,
        .options = options,
    });
    const expected_glyphs = try allocator.dupe(
        glyph_position.GlyphPosition,
        uniform.glyphs,
    );
    defer allocator.free(expected_glyphs);
    const cached_levels = engine.state.styled_output.analysis
        .bidi_paragraph.?.levels.ptr;
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .misses = 1 },
        engine.stats().bidi_paragraphs,
    );

    const spans = [_]styled_paragraph.Span{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 41,
        .font_size = 20,
    }};
    const styled = try engine.layoutStyled(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = options,
    });
    try std.testing.expectEqualSlices(
        glyph_position.GlyphPosition,
        expected_glyphs,
        styled.layout.glyphs,
    );
    // Styled itemization can expose more public font runs at style/script
    // boundaries, but the visual glyph stream and geometry remain equivalent.
    try std.testing.expectEqual(uniform.width, styled.layout.width);
    try std.testing.expectEqual(uniform.height, styled.layout.height);
    try std.testing.expectEqual(uniform.lines.len, styled.layout.lines.len);
    for (styled.glyph_metadata) |metadata| {
        try std.testing.expectEqual(@as(u32, 41), metadata.style_index);
    }
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 1, .misses = 1 },
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expectEqual(
        cached_levels,
        engine.state.styled_output.analysis.bidi_paragraph.?.levels.ptr,
    );

    // The uniform styled fast path without intrinsic-width calculation also
    // uses the same cache entry rather than a private resolver.
    const layout_only = try engine.layoutStyledWithoutContentWidths(
        cascade,
        .{
            .text = text,
            .default_font_size = 20,
            .spans = &spans,
            .options = options,
        },
    );
    try std.testing.expectEqualSlices(
        glyph_position.GlyphPosition,
        expected_glyphs,
        layout_only.layout.glyphs,
    );
    try std.testing.expectEqual(uniform.width, layout_only.layout.width);
    try std.testing.expectEqual(uniform.height, layout_only.layout.height);
    try std.testing.expectEqual(uniform.lines.len, layout_only.layout.lines.len);
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 2, .misses = 1 },
        engine.stats().bidi_paragraphs,
    );
}

test "uniform logical cache keeps explicit direction and inferred properties exact" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&.{&font}));
    const text = "Latin אבג 12 سلام";

    inline for (.{
        @import("../../../shaping/pipeline/types.zig").TextDirection.ltr,
        @import("../../../shaping/pipeline/types.zig").TextDirection.rtl,
    }) |direction| {
        var cached_engine = context_mod.Engine.init(allocator, .{});
        defer cached_engine.deinit();
        const request: context_mod.ParagraphRequest = .{
            .text = text,
            .font_size = 20,
            .options = .{ .max_width = 70, .direction = direction },
        };
        _ = try cached_engine.layout(cascade, request);
        const cached = try cached_engine.layout(cascade, request);
        const expected_glyphs = try allocator.dupe(
            glyph_position.GlyphPosition,
            cached.glyphs,
        );
        defer allocator.free(expected_glyphs);
        const expected_runs = try allocator.dupe(
            run_types.CascadeRun,
            cached.runs,
        );
        defer allocator.free(expected_runs);
        const expected_lines = try allocator.dupe(
            paragraph_types.ParagraphLine,
            cached.lines,
        );
        defer allocator.free(expected_lines);

        var fresh_engine = context_mod.Engine.init(allocator, .{});
        defer fresh_engine.deinit();
        const fresh = try fresh_engine.layout(cascade, request);
        try std.testing.expectEqualSlices(
            glyph_position.GlyphPosition,
            expected_glyphs,
            fresh.glyphs,
        );
        try std.testing.expectEqualSlices(
            run_types.CascadeRun,
            expected_runs,
            fresh.runs,
        );
        try std.testing.expectEqualSlices(
            paragraph_types.ParagraphLine,
            expected_lines,
            fresh.lines,
        );
        try std.testing.expectEqual(
            context_mod.Engine.Counter{ .hits = 1, .misses = 1 },
            cached_engine.stats().logical_analysis,
        );
    }
}

test "general styled layouts reuse bidi analysis and preserve parity" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&.{&font}));
    const text = "A \u{05d0}\u{05d1} B";
    const spans = [_]styled_paragraph.Span{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 11,
            .font_size = 20,
        },
        .{
            .byte_start = 2,
            .byte_len = text.len - 2,
            .style_index = 22,
            .font_size = 20,
            .letter_spacing = 1,
        },
    };
    const request: context_mod.StyledParagraphRequest = .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = .{ .max_width = 45 },
    };

    var engine = context_mod.Engine.init(allocator, .{});
    defer engine.deinit();
    const first = try engine.layoutStyled(cascade, request);
    const expected_glyphs = try allocator.dupe(
        glyph_position.GlyphPosition,
        first.layout.glyphs,
    );
    defer allocator.free(expected_glyphs);
    const expected_runs = try allocator.dupe(
        run_types.CascadeRun,
        first.layout.runs,
    );
    defer allocator.free(expected_runs);
    const expected_lines = try allocator.dupe(
        paragraph_types.ParagraphLine,
        first.layout.lines,
    );
    defer allocator.free(expected_lines);
    const expected_metadata = try allocator.dupe(
        styled_buffer.Metadata,
        first.glyph_metadata,
    );
    defer allocator.free(expected_metadata);
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .misses = 1 },
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .misses = 1 },
        engine.stats().logical_analysis,
    );

    const second = try engine.layoutStyled(cascade, request);
    try expectStyledSlicesEqual(
        expected_glyphs,
        expected_runs,
        expected_lines,
        expected_metadata,
        second.layout,
        second.glyph_metadata,
    );
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 1, .misses = 1 },
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 1, .misses = 1 },
        engine.stats().logical_analysis,
    );

    // Two spans force the general styled implementation in this layout-only
    // API; it must share the same analysis and preserve output/sidecar parity.
    const layout_only = try engine.layoutStyledWithoutContentWidths(
        cascade,
        request,
    );
    try expectStyledSlicesEqual(
        expected_glyphs,
        expected_runs,
        expected_lines,
        expected_metadata,
        layout_only.layout,
        layout_only.glyph_metadata,
    );
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 2, .misses = 1 },
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .hits = 2, .misses = 1 },
        engine.stats().logical_analysis,
    );
}

test "invalid bidi layout requests do not mutate the analysis cache" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&.{&font}));

    var engine = context_mod.Engine.init(allocator, .{});
    defer engine.deinit();
    _ = try engine.layout(cascade, .{
        .text = "cached \u{05d0}",
        .font_size = 20,
        .options = .{ .max_width = 100 },
    });
    const analysis = &engine.state.styled_output.analysis;
    const cached_text_ptr = analysis.bidi_text.ptr;
    const cached_logical_text_ptr = analysis.logical_text.ptr;
    const expected_stats = context_mod.Engine.Counter{ .misses = 1 };
    const expected_logical_stats = engine.stats().logical_analysis;

    try std.testing.expectError(error.InvalidFontSize, engine.layout(
        cascade,
        .{
            .text = "invalid size \u{05d1}",
            .font_size = 0,
            .options = .{ .max_width = 100 },
        },
    ));
    try std.testing.expectEqual(expected_stats, engine.stats().bidi_paragraphs);
    try std.testing.expectEqual(
        expected_logical_stats,
        engine.stats().logical_analysis,
    );
    try std.testing.expectEqual(cached_text_ptr, analysis.bidi_text.ptr);
    try std.testing.expectEqual(
        cached_logical_text_ptr,
        analysis.logical_text.ptr,
    );
    try std.testing.expectEqualStrings("cached \u{05d0}", analysis.bidi_text);

    const invalid_spans = [_]styled_paragraph.Span{.{
        .byte_start = 0,
        .byte_len = 1,
        .style_index = 1,
        .font_size = 20,
    }};
    try std.testing.expectError(error.InvalidStyleSpans, engine.layoutStyled(
        cascade,
        .{
            .text = "invalid spans \u{05d2}",
            .default_font_size = 20,
            .spans = &invalid_spans,
            .options = .{ .max_width = 100 },
        },
    ));
    try std.testing.expectEqual(expected_stats, engine.stats().bidi_paragraphs);
    try std.testing.expectEqual(
        expected_logical_stats,
        engine.stats().logical_analysis,
    );
    try std.testing.expectEqual(cached_text_ptr, analysis.bidi_text.ptr);
    try std.testing.expectEqual(
        cached_logical_text_ptr,
        analysis.logical_text.ptr,
    );
    try std.testing.expectEqualStrings("cached \u{05d0}", analysis.bidi_text);
}

test "retained styled bidi remains owning across cache replacement" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = face_mod.Cascade.init(face_mod.backend.faces(&.{&font}));
    const text = "A\u{fffc} \u{05d0}\u{05d1} B";
    const object = inline_object.Object{
        .id = 73,
        .byte_index = 1,
        .width = 13,
        .height = 18,
    };
    const spans = [_]styled_paragraph.Span{
        .{
            .byte_start = 0,
            .byte_len = 4,
            .style_index = 31,
            .font_size = 20,
        },
        .{
            .byte_start = 4,
            .byte_len = text.len - 4,
            .style_index = 47,
            .font_size = 20,
            .letter_spacing = 1,
        },
    };
    const options: @import("../../../layout/paragraph/options.zig").Options = .{
        .max_width = 45,
        .inline_objects = &.{object},
    };

    var engine = context_mod.Engine.init(allocator, .{});
    defer engine.deinit();
    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = options,
    });
    defer paragraph.deinit();
    // Preparation deliberately owns its paragraph analysis instead of
    // publishing or borrowing the one-shot cache.
    try std.testing.expectEqual(
        context_mod.Engine.Counter{},
        engine.stats().bidi_paragraphs,
    );
    try std.testing.expect(paragraph.bidi_paragraph != null);

    var reflow = retained_styled.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const first = try paragraph.layout(&reflow, options);
    const expected_glyphs = try allocator.dupe(
        glyph_position.GlyphPosition,
        first.layout.glyphs,
    );
    defer allocator.free(expected_glyphs);
    const expected_runs = try allocator.dupe(
        run_types.CascadeRun,
        first.layout.runs,
    );
    defer allocator.free(expected_runs);
    const expected_lines = try allocator.dupe(
        paragraph_types.ParagraphLine,
        first.layout.lines,
    );
    defer allocator.free(expected_lines);
    const expected_objects = try allocator.dupe(
        inline_object.Positioned,
        first.layout.inline_objects,
    );
    defer allocator.free(expected_objects);
    const expected_metadata = try allocator.dupe(
        styled_buffer.Metadata,
        first.glyph_metadata,
    );
    defer allocator.free(expected_metadata);
    try std.testing.expectEqual(@as(usize, 1), expected_objects.len);
    try std.testing.expectEqual(@as(u64, 73), expected_objects[0].id);

    // Populate and then replace the Engine-owned exact entry. Either miss
    // releases prior cached arrays, so a retained paragraph that accidentally
    // borrowed them would now be dangling.
    _ = try engine.layout(cascade, .{
        .text = text,
        .font_size = 20,
        .options = options,
    });
    _ = try engine.layout(cascade, .{
        .text = "replacement \u{05d2}",
        .font_size = 20,
        .options = .{ .max_width = 100 },
    });
    try std.testing.expectEqual(
        context_mod.Engine.Counter{ .misses = 2 },
        engine.stats().bidi_paragraphs,
    );

    const after_replacement = try paragraph.layout(&reflow, options);
    try expectStyledSlicesEqual(
        expected_glyphs,
        expected_runs,
        expected_lines,
        expected_metadata,
        after_replacement.layout,
        after_replacement.glyph_metadata,
    );
    try std.testing.expectEqualSlices(
        inline_object.Positioned,
        expected_objects,
        after_replacement.layout.inline_objects,
    );
}

test "uniform logical analysis layout is leak free under allocation failure" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        std.testing.allocator,
        false,
    );
    defer std.testing.allocator.free(bytes);

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        struct {
            fn run(allocator: std.mem.Allocator, font_bytes: []const u8) !void {
                var font = try Font.parse(allocator, font_bytes);
                defer font.deinit();
                const cascade = face_mod.Cascade.init(
                    face_mod.backend.faces(&.{&font}),
                );
                var engine = context_mod.Engine.init(allocator, .{});
                defer engine.deinit();
                const layout = try engine.layout(cascade, .{
                    .text = "A אבג سلام 12 B",
                    .font_size = 20,
                    .options = .{ .max_width = 70 },
                });
                try std.testing.expect(layout.glyphs.len != 0);
                try std.testing.expectEqual(
                    context_mod.Engine.Counter{ .misses = 1 },
                    engine.stats().logical_analysis,
                );
            }
        }.run,
        .{bytes},
    );
}

fn expectStyledSlicesEqual(
    expected_glyphs: []const glyph_position.GlyphPosition,
    expected_runs: []const run_types.CascadeRun,
    expected_lines: []const paragraph_types.ParagraphLine,
    expected_metadata: []const styled_buffer.Metadata,
    actual: paragraph_types.ParagraphLayout,
    actual_metadata: []const styled_buffer.Metadata,
) !void {
    try std.testing.expectEqualSlices(
        glyph_position.GlyphPosition,
        expected_glyphs,
        actual.glyphs,
    );
    try std.testing.expectEqualSlices(
        run_types.CascadeRun,
        expected_runs,
        actual.runs,
    );
    try std.testing.expectEqualSlices(
        paragraph_types.ParagraphLine,
        expected_lines,
        actual.lines,
    );
    try std.testing.expectEqualSlices(
        styled_buffer.Metadata,
        expected_metadata,
        actual_metadata,
    );
}
