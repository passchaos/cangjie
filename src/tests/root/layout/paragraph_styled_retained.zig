//! Public retained-styled paragraph ownership and repeatable reflow coverage.

const std = @import("std");
const cangjie = @import("../../../root.zig");
const test_font = @import("../../../test_font.zig");

test "retained styled paragraph matches one-shot narrow and wide layouts" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&face});
    const text = "A A A A";
    const spans = [_]cangjie.paragraph.StyledSpan{
        .{
            .byte_start = 0,
            .byte_len = 4,
            .style_index = 11,
            .font_size = 20,
            .letter_spacing = 1,
        },
        .{
            .byte_start = 4,
            .byte_len = text.len - 4,
            .style_index = 22,
            .font_size = 20,
            .letter_spacing = 3,
        },
    };

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = .{ .max_width = 500 },
    });
    defer paragraph.deinit();

    var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
    defer reflow.deinit();

    const narrow_options: cangjie.paragraph.Options = .{ .max_width = 45 };
    const narrow = try paragraph.layout(&reflow, narrow_options);
    try std.testing.expect(narrow.layout.lines.len > 1);
    try std.testing.expectEqual(
        narrow.layout.glyphs.len,
        narrow.glyph_metadata.len,
    );

    // The owning paragraph is independent of Engine output, so a one-shot
    // operation may safely reuse the engine while this reflow view is live.
    const expected_narrow = try engine.layoutStyled(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = narrow_options,
    });
    try expectStyledLayoutEqual(expected_narrow, narrow);

    // Save the first transaction before reusing its buffer. Views returned by
    // layout deliberately last only until the next call with that buffer.
    const narrow_glyphs = try allocator.dupe(
        cangjie.shaping.Glyph,
        narrow.layout.glyphs,
    );
    defer allocator.free(narrow_glyphs);
    const narrow_lines = try allocator.dupe(
        cangjie.paragraph.Line,
        narrow.layout.lines,
    );
    defer allocator.free(narrow_lines);
    const narrow_metadata = try allocator.dupe(
        cangjie.paragraph.StyledGlyphMetadata,
        narrow.glyph_metadata,
    );
    defer allocator.free(narrow_metadata);
    const narrow_width = narrow.layout.width;
    const narrow_height = narrow.layout.height;

    const wide_options: cangjie.paragraph.Options = .{ .max_width = 500 };
    const wide = try paragraph.layout(&reflow, wide_options);
    try std.testing.expectEqual(@as(usize, 1), wide.layout.lines.len);
    const expected_wide = try engine.layoutStyled(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = wide_options,
    });
    try expectStyledLayoutEqual(expected_wide, wide);

    const narrow_again = try paragraph.layout(&reflow, narrow_options);
    try std.testing.expectEqualSlices(
        cangjie.shaping.Glyph,
        narrow_glyphs,
        narrow_again.layout.glyphs,
    );
    try std.testing.expectEqualSlices(
        cangjie.paragraph.Line,
        narrow_lines,
        narrow_again.layout.lines,
    );
    try std.testing.expectEqualSlices(
        cangjie.paragraph.StyledGlyphMetadata,
        narrow_metadata,
        narrow_again.glyph_metadata,
    );
    try std.testing.expectApproxEqAbs(
        narrow_width,
        narrow_again.layout.width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        narrow_height,
        narrow_again.layout.height,
        0.001,
    );

    const retained_widths = try paragraph.contentWidths(wide_options);
    try std.testing.expectApproxEqAbs(
        expected_wide.content_widths.min,
        retained_widths.min,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        expected_wide.content_widths.max,
        retained_widths.max,
        0.001,
    );
}

test "retained styled paragraph deep-copies text spans and nested slices" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMetricVariationTtf(allocator);
    defer allocator.free(bytes);
    const replacement_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(replacement_bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var replacement_face = try cangjie.font.Face.parse(
        allocator,
        replacement_bytes,
    );
    defer replacement_face.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&face});

    var source = [_]u8{ 'A', ' ', 'A' };
    var faces = [_]*const cangjie.font.Face{&face};
    var features = [_]cangjie.shaping.Feature{.{
        .tag = cangjie.text.opentype.tag("kern"),
        .enabled = false,
    }};
    var coordinates = [_]f32{0.5};
    var spans = [_]cangjie.paragraph.StyledSpan{.{
        .byte_start = 0,
        .byte_len = source.len,
        .style_index = 71,
        .font_size = 20,
        .faces = &faces,
        .features = &features,
        .normalized_variation_coords = &coordinates,
        .letter_spacing = 2,
        .word_spacing = 3,
        .minimum_line_height = 28,
    }};

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = &source,
        .default_font_size = 20,
        .spans = &spans,
        .options = .{ .max_width = 200 },
    });
    defer paragraph.deinit();

    // Mutate every caller-owned container in the request. The retained owner
    // must keep independent text, span records, face-pointer arrays, feature
    // arrays, and variation-coordinate arrays (but it still borrows faces).
    source[0] = 'Z';
    faces[0] = &replacement_face;
    features[0].enabled = true;
    coordinates[0] = -0.5;
    spans[0].style_index = 99;
    spans[0].font_size = 7;
    spans[0].letter_spacing = 40;
    spans[0].word_spacing = 50;
    spans[0].minimum_line_height = null;

    // Reusing Engine output must likewise leave the owning paragraph intact.
    _ = try engine.layoutStyled(cascade, .{
        .text = "A",
        .default_font_size = 10,
        .spans = &.{.{
            .byte_start = 0,
            .byte_len = 1,
            .style_index = 1,
            .font_size = 10,
        }},
        .options = .{ .max_width = 100 },
    });

    try std.testing.expectEqualStrings("A A", paragraph.text);
    try std.testing.expectEqual(@as(usize, 1), paragraph.spans.len);
    const retained_span = paragraph.spans[0];
    try std.testing.expectEqual(@as(u32, 71), retained_span.style_index);
    try std.testing.expectEqual(@as(f32, 20), retained_span.font_size);
    try std.testing.expectEqual(@as(f32, 2), retained_span.letter_spacing);
    try std.testing.expectEqual(@as(f32, 3), retained_span.word_spacing);
    try std.testing.expectEqual(@as(f32, 28), retained_span.minimum_line_height.?);
    try std.testing.expectEqual(
        @as(*const cangjie.font.Face, &face),
        retained_span.faces.?[0],
    );
    try std.testing.expect(!retained_span.features[0].enabled);
    try std.testing.expectEqual(
        @as(f32, 0.5),
        retained_span.normalized_variation_coords[0],
    );

    var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
    defer reflow.deinit();
    const result = try paragraph.layout(
        &reflow,
        .{ .max_width = 200 },
    );
    try std.testing.expectEqual(@as(usize, 1), result.layout.lines.len);
    try std.testing.expectEqual(
        result.layout.glyphs.len,
        result.glyph_metadata.len,
    );
    for (result.glyph_metadata) |metadata| {
        try std.testing.expectEqual(@as(u32, 71), metadata.style_index);
    }
    try std.testing.expectEqualSlices(
        f32,
        &.{0.5},
        result.layout.normalized_variation_coords,
    );
}

test "retained styled vertical paragraphs reuse shaping across column modes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&face});
    const text = "A\nA";
    const spans = [_]cangjie.paragraph.StyledSpan{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 31,
            .font_size = 20,
        },
        .{
            .byte_start = 2,
            .byte_len = 1,
            .style_index = 47,
            .font_size = 20,
            .letter_spacing = 2,
        },
    };
    const prepare_options: cangjie.paragraph.Options = .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
        .text_orientation = .upright,
    };

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = prepare_options,
    });
    defer paragraph.deinit();
    var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
    defer reflow.deinit();

    // RL and LR differ only in physical column progression, so both share the
    // normalized vertical shaping key retained during preparation.
    const lr_options: cangjie.paragraph.Options = .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_lr,
        .text_orientation = .upright,
    };
    const retained = try paragraph.layout(&reflow, lr_options);
    try std.testing.expectEqual(
        cangjie.paragraph.WritingMode.vertical_lr,
        retained.layout.writing_mode,
    );
    try std.testing.expectEqual(@as(usize, 2), retained.layout.lines.len);
    try std.testing.expect(
        retained.layout.lines[0].x < retained.layout.lines[1].x,
    );

    const one_shot = try engine.layoutStyled(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = lr_options,
    });
    try expectStyledLayoutEqual(one_shot, retained);
}

test "retained styled bidi keeps metadata parallel to visual glyphs" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&face});
    const text = "A אב B";
    const spans = [_]cangjie.paragraph.StyledSpan{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = 2,
            .byte_len = 4,
            .style_index = 2,
            .font_size = 20,
            .letter_spacing = 1,
        },
        .{
            .byte_start = 6,
            .byte_len = 2,
            .style_index = 3,
            .font_size = 20,
        },
    };
    const options: cangjie.paragraph.Options = .{ .max_width = 42 };

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = options,
    });
    defer paragraph.deinit();
    var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
    defer reflow.deinit();

    const retained = try paragraph.layout(&reflow, options);
    const one_shot = try engine.layoutStyled(cascade, .{
        .text = text,
        .default_font_size = 20,
        .spans = &spans,
        .options = options,
    });
    try expectStyledLayoutEqual(one_shot, retained);
    try std.testing.expectEqual(
        retained.layout.glyphs.len,
        retained.glyph_metadata.len,
    );

    // Bidi reordering moves glyphs and metadata as one transaction. Checking
    // the source cluster against its owning span catches a sidecar that merely
    // has the right length but remains in logical rather than visual order.
    var saw_descending_cluster = false;
    for (
        retained.layout.glyphs,
        retained.glyph_metadata,
        0..,
    ) |glyph, metadata, index| {
        if (index != 0 and
            glyph.cluster < retained.layout.glyphs[index - 1].cluster)
        {
            saw_descending_cluster = true;
        }
        try std.testing.expectEqual(
            styleIndexForCluster(&spans, glyph.cluster).?,
            metadata.style_index,
        );
        try std.testing.expectEqual(
            @as(f32, if (metadata.style_index == 2) 1 else 0),
            metadata.layout_spacing,
        );
    }
    try std.testing.expect(saw_descending_cluster);
}

test "retained styled paragraph rejects shaping changes without buffer mutation" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&face});
    const spans = [_]cangjie.paragraph.StyledSpan{.{
        .byte_start = 0,
        .byte_len = 2,
        .style_index = 5,
        .font_size = 20,
    }};

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = "AA",
        .default_font_size = 20,
        .spans = &spans,
        .options = .{ .max_width = 100 },
    });
    defer paragraph.deinit();
    var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
    defer reflow.deinit();

    try std.testing.expectError(
        error.ParagraphShapingOptionsChanged,
        paragraph.layout(&reflow, .{
            .max_width = 100,
            .direction = .rtl,
        }),
    );
    // Validation happens before restoration, so rejecting against a clean
    // buffer cannot expose a partially populated glyph or metadata stream.
    try std.testing.expectEqual(@as(usize, 0), reflow.buffer.glyphs.items.len);
    try std.testing.expectEqual(@as(usize, 0), reflow.buffer.runs.items.len);
    try std.testing.expectEqual(@as(usize, 0), reflow.buffer.lines.items.len);
    try std.testing.expectEqual(
        @as(usize, 0),
        reflow.styled.glyphMetadata().len,
    );

    const accepted = try paragraph.layout(&reflow, .{ .max_width = 100 });
    const accepted_glyphs = try allocator.dupe(
        cangjie.shaping.Glyph,
        accepted.layout.glyphs,
    );
    defer allocator.free(accepted_glyphs);
    const accepted_runs = try allocator.dupe(
        cangjie.shaping.FontRun,
        accepted.layout.runs,
    );
    defer allocator.free(accepted_runs);
    const accepted_lines = try allocator.dupe(
        cangjie.paragraph.Line,
        accepted.layout.lines,
    );
    defer allocator.free(accepted_lines);
    const accepted_metadata = try allocator.dupe(
        cangjie.paragraph.StyledGlyphMetadata,
        accepted.glyph_metadata,
    );
    defer allocator.free(accepted_metadata);

    try std.testing.expectError(
        error.ParagraphShapingOptionsChanged,
        paragraph.layout(&reflow, .{
            .max_width = 100,
            .direction = .rtl,
        }),
    );
    try std.testing.expectEqualSlices(
        cangjie.shaping.Glyph,
        accepted_glyphs,
        reflow.buffer.glyphs.items,
    );
    try std.testing.expectEqualSlices(
        cangjie.shaping.FontRun,
        accepted_runs,
        reflow.buffer.runs.items,
    );
    try std.testing.expectEqualSlices(
        cangjie.paragraph.Line,
        accepted_lines,
        reflow.buffer.lines.items,
    );
    try std.testing.expectEqualSlices(
        cangjie.paragraph.StyledGlyphMetadata,
        accepted_metadata,
        reflow.styled.glyphMetadata(),
    );
}

test "retained styled preparation is leak free under allocation failure" {
    const bytes = try test_font.buildMetricVariationTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        struct {
            fn run(allocator: std.mem.Allocator, font_bytes: []const u8) !void {
                var face = try cangjie.font.Face.parse(allocator, font_bytes);
                defer face.deinit();
                const cascade = cangjie.font.Cascade.init(&.{&face});
                const feature = cangjie.shaping.Feature{
                    .tag = cangjie.text.opentype.tag("kern"),
                    .enabled = false,
                };
                var engine = cangjie.shaping.Engine.init(allocator, .{});
                defer engine.deinit();
                var paragraph = try engine.prepareStyledParagraph(cascade, .{
                    .text = "A A",
                    .default_font_size = 20,
                    .spans = &.{
                        .{
                            .byte_start = 0,
                            .byte_len = 2,
                            .style_index = 17,
                            .font_size = 20,
                            .faces = &.{&face},
                            .features = &.{feature},
                            .normalized_variation_coords = &.{0.5},
                        },
                        .{
                            .byte_start = 2,
                            .byte_len = 1,
                            .style_index = 23,
                            .font_size = 20,
                            .faces = &.{&face},
                            .features = &.{feature},
                            .normalized_variation_coords = &.{0.5},
                        },
                    },
                    .options = .{
                        .max_width = 100,
                        .features = &.{feature},
                        .normalized_variation_coords = &.{0.5},
                    },
                });
                defer paragraph.deinit();

                // Reach deinit after every retained nested slice has been
                // copied; checkAllAllocationFailures also exercises each
                // earlier partial-initialization cleanup path.
                try std.testing.expectEqualStrings("A A", paragraph.text);
                try std.testing.expectEqual(@as(usize, 2), paragraph.spans.len);
            }
        }.run,
        .{bytes},
    );
}

test "retained styled paragraphs own a union of style-local cascades" {
    const allocator = std.testing.allocator;
    const primary_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(primary_bytes);
    const foreign_bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(foreign_bytes);

    var primary = try cangjie.font.Face.parse(allocator, primary_bytes);
    defer primary.deinit();
    var foreign = try cangjie.font.Face.parse(allocator, foreign_bytes);
    defer foreign.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&primary});
    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();

    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = "A",
        .default_font_size = 20,
        .spans = &.{.{
            .byte_start = 0,
            .byte_len = 1,
            .style_index = 1,
            .font_size = 20,
            .faces = &.{&foreign},
        }},
        .options = .{ .max_width = 100 },
    });
    defer paragraph.deinit();
    try std.testing.expectEqual(@as(usize, 1), paragraph.cascade_fonts.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.font_index_fonts.len);
    var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
    defer reflow.deinit();
    const retained = try paragraph.layout(&reflow, .{ .max_width = 100 });
    try std.testing.expectEqual(@as(usize, 1), retained.layout.runs.len);
    try std.testing.expectEqual(
        @as(*const cangjie.font.Face, &foreign),
        retained.layout.runs[0].font,
    );
    try std.testing.expectEqual(@as(usize, 1), retained.layout.runs[0].font_index);

    // This retained-only ownership restriction must not narrow the existing
    // one-shot styled API, whose style cascade may be independently resolved.
    const one_shot = try engine.layoutStyled(cascade, .{
        .text = "A",
        .default_font_size = 20,
        .spans = &.{.{
            .byte_start = 0,
            .byte_len = 1,
            .style_index = 1,
            .font_size = 20,
            .faces = &.{&foreign},
        }},
        .options = .{ .max_width = 100 },
    });
    try std.testing.expectEqual(@as(usize, 1), one_shot.layout.runs.len);
    try std.testing.expectEqual(
        @as(*const cangjie.font.Face, &foreign),
        one_shot.layout.runs[0].font,
    );
}

test "retained styled inherited spans keep the original base cascade" {
    const allocator = std.testing.allocator;
    const primary_bytes = try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(primary_bytes);
    const foreign_bytes = try test_font.buildCodepointSetTtf(allocator, &.{ 'A', 'B' });
    defer allocator.free(foreign_bytes);

    var primary = try cangjie.font.Face.parse(allocator, primary_bytes);
    defer primary.deinit();
    var foreign = try cangjie.font.Face.parse(allocator, foreign_bytes);
    defer foreign.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&primary});
    const spans = [_]cangjie.paragraph.StyledSpan{
        .{
            .byte_start = 0,
            .byte_len = 1,
            .style_index = 1,
            .font_size = 20,
        },
        .{
            .byte_start = 1,
            .byte_len = 1,
            .style_index = 2,
            .font_size = 20,
            .faces = &.{&foreign},
        },
    };

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    var paragraph = try engine.prepareStyledParagraph(cascade, .{
        .text = "AB",
        .default_font_size = 20,
        .spans = &spans,
        .options = .{ .max_width = 100 },
    });
    defer paragraph.deinit();

    // Null still means the original paragraph cascade, not the retained union
    // that also contains fonts contributed by unrelated explicit spans.
    try std.testing.expect(paragraph.spans[0].faces == null);
    try std.testing.expectEqual(@as(usize, 1), paragraph.cascade_fonts.len);
    try std.testing.expectEqual(@as(usize, 2), paragraph.font_index_fonts.len);

    var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
    defer reflow.deinit();
    const retained = try paragraph.layout(&reflow, .{ .max_width = 100 });
    try std.testing.expectEqual(@as(usize, 2), retained.layout.runs.len);
    try std.testing.expectEqual(@as(usize, 0), retained.layout.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), retained.layout.runs[1].font_index);
}

fn styleIndexForCluster(
    spans: []const cangjie.paragraph.StyledSpan,
    cluster: usize,
) ?u32 {
    for (spans) |span| {
        if (cluster >= span.byte_start and
            cluster < span.byte_start + span.byte_len)
        {
            return span.style_index;
        }
    }
    return null;
}

fn expectStyledLayoutEqual(
    expected: cangjie.paragraph.StyledResult,
    actual: anytype,
) !void {
    try std.testing.expectEqualSlices(
        cangjie.shaping.Glyph,
        expected.layout.glyphs,
        actual.layout.glyphs,
    );
    try std.testing.expectEqualSlices(
        cangjie.shaping.FontRun,
        expected.layout.runs,
        actual.layout.runs,
    );
    try std.testing.expectEqualSlices(
        f32,
        expected.layout.normalized_variation_coords,
        actual.layout.normalized_variation_coords,
    );
    try std.testing.expectEqualSlices(
        cangjie.paragraph.Line,
        expected.layout.lines,
        actual.layout.lines,
    );
    try std.testing.expectEqualSlices(
        cangjie.paragraph.PositionedInlineObject,
        expected.layout.inline_objects,
        actual.layout.inline_objects,
    );
    try std.testing.expectEqual(
        expected.layout.writing_mode,
        actual.layout.writing_mode,
    );
    try std.testing.expectEqualSlices(
        cangjie.paragraph.StyledGlyphMetadata,
        expected.glyph_metadata,
        actual.glyph_metadata,
    );
    try std.testing.expectApproxEqAbs(
        expected.layout.width,
        actual.layout.width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        expected.layout.height,
        actual.layout.height,
        0.001,
    );
}
