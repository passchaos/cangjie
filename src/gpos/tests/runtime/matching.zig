//! GPOS LookupFlag and source-metadata matching contracts.

const std = @import("std");
const runtime = @import("../../runtime/root.zig");

test "LookupFlag combines mark filtering sets and attachment classes" {
    const glyphs = [_]u16{ 5, 7, 8 };
    var glyph_classes = [_]u16{0} ** 9;
    glyph_classes[5] = 3;
    glyph_classes[7] = 3;
    var attach_classes = [_]u16{0} ** 9;
    attach_classes[5] = 1;
    attach_classes[7] = 2;
    const sets = [_][]const u16{&.{ 5, 7 }};
    const options = runtime.Options{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &attach_classes,
        .mark_filtering_sets = &sets,
        .active_mark_filtering_set = 0,
    };

    // MarkAttachmentType 2 rejects glyph 5 and accepts glyph 7. Glyph 8 is an
    // ordinary glyph and remains visible to the lookup.
    try std.testing.expect(
        runtime.matching.lookupIgnoresGlyph(0x0210, options, glyphs[0]),
    );
    try std.testing.expect(
        !runtime.matching.lookupIgnoresGlyph(0x0210, options, glyphs[1]),
    );
    try std.testing.expect(
        !runtime.matching.lookupIgnoresGlyph(0x0210, options, glyphs[2]),
    );
}

test "source metadata controls default-ignorable visibility" {
    const sources = [_]usize{ 0, 1, 2 };
    const codepoints = [_]u21{ 'A', 0x034f, 'B' };
    const unsubstituted = runtime.Options{
        .run_metadata = &.{
            .glyph_source_indices = &sources,
            .source_codepoints = &codepoints,
            .glyph_substituted = &.{ false, false, false },
        },
    };
    try std.testing.expect(
        runtime.matching.markAttachmentSearchSkipsGlyph(unsubstituted, 1),
    );

    var substituted = unsubstituted;
    substituted.run_metadata = &.{
        .glyph_source_indices = &sources,
        .source_codepoints = &codepoints,
        .glyph_substituted = &.{ false, true, false },
    };
    try std.testing.expect(
        !runtime.matching.markAttachmentSearchSkipsGlyph(substituted, 1),
    );
}

test "runtime validation rejects uncorrelated source metadata and coordinates" {
    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.matching.validate(.{
            .run_metadata = &.{ .source_codepoints = &.{'A'} },
        }, 1),
    );
    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.matching.validate(.{
            .normalized_variation_coords = &.{1.01},
        }, 1),
    );
    try std.testing.expectError(
        error.BadGpos,
        runtime.matching.validateMarkFilteringSetIndex(.{
            .mark_filtering_sets = &.{&.{5}},
            .active_mark_filtering_set = 1,
        }),
    );
}
