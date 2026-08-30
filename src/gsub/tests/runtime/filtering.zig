//! GSUB LookupFlag, source-scope, and default-ignorable filtering contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const filtering = @import("../../runtime/filtering.zig");

test "LookupFlag combines mark set and attachment filtering" {
    var glyph_classes = [_]u16{0} ** 8;
    glyph_classes[5] = 3;
    glyph_classes[7] = 3;
    var attach_classes = [_]u16{0} ** 8;
    attach_classes[5] = 1;
    attach_classes[7] = 2;
    const mark_sets = [_][]const u16{&.{ 5, 7 }};
    const run = filtering.Options{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &attach_classes,
        .mark_filtering_sets = &mark_sets,
        .active_mark_filtering_set = 0,
    };

    try std.testing.expect(filtering.lookupIgnoresGlyph(0x0210, run, 5));
    try std.testing.expect(!filtering.lookupIgnoresGlyph(0x0210, run, 7));
    try std.testing.expectError(
        error.BadGsub,
        filtering.validateMarkFilteringSetIndex(.{
            .mark_filtering_sets = &mark_sets,
            .active_mark_filtering_set = 1,
        }),
    );
}

test "MarkAttachmentType classifies marks without GlyphClassDef" {
    var attach_classes = [_]u16{0} ** 9;
    attach_classes[5] = 2;
    attach_classes[7] = 1;
    const run = filtering.Options{ .mark_attach_classes = &attach_classes };

    try std.testing.expect(filtering.lookupIgnoresGlyph(0x0100, run, 5));
    try std.testing.expect(!filtering.lookupIgnoresGlyph(0x0100, run, 7));
    try std.testing.expect(!filtering.lookupIgnoresGlyph(0x0100, run, 8));
}

test "source filtering handles raw tags compact masks and syllables" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 1, 0 });
    const raw_features = [_]u32{ 0x61626364, 0x65666768 };

    try std.testing.expect(filtering.sourceFeatureAllowsGlyph(.{
        .glyph_source_indices = &sources,
        .source_features = &raw_features,
        .active_source_feature = raw_features[1],
    }, 0));
    try std.testing.expect(!filtering.sourceFeatureAllowsGlyph(.{
        .glyph_source_indices = &sources,
        .source_features = &raw_features,
        .active_source_feature = raw_features[1],
    }, 1));

    const masks = [_]u32{
        feature.sourceMaskForTag(0x68616c66).?,
        0,
    };
    try std.testing.expect(filtering.sourceFeatureAllowsGlyph(.{
        .glyph_source_indices = &sources,
        .source_features = &masks,
        .active_source_feature = 0x68616c66,
    }, 1));
    try std.testing.expect(!filtering.sourceFeatureAllowsGlyph(.{
        .glyph_source_indices = &sources,
        .source_features = &masks,
        .active_source_feature = 0x72706866,
    }, 1));

    const syllables = [_]u8{ 3, 4 };
    const syllable_run = filtering.Options{
        .glyph_source_indices = &sources,
        .source_syllables = &syllables,
        .match_source_syllable = true,
    };
    try std.testing.expectEqual(
        @as(?u8, 4),
        filtering.sourceSyllableForGlyph(syllable_run, 0),
    );
    try std.testing.expect(
        !filtering.sourceSyllableAllowsGlyph(syllable_run, 4, 1),
    );
}

test "user ranges and script candidates independently enable cursors" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3 });
    const half_mask = feature.sourceMaskForTag(0x68616c66).?;
    const script_candidates = [_]u32{ half_mask, half_mask, 0, 0 };
    const user_values = [_]u32{ 0, 1, 1, 0 };
    const user_feature = filtering.UserFeature{
        .values = &user_values,
        .tag = 0x68616c66,
    };
    const run = filtering.Options{
        .glyph_source_indices = &sources,
        .source_features = &script_candidates,
        .user_feature = &user_feature,
        .active_source_feature_mask = half_mask,
    };

    // HarfBuzz applies user masks before the Indic shaper adds candidates. A
    // ranged zero therefore does not remove source 0's automatic candidate,
    // while source 2 is admitted by the user range alone.
    try std.testing.expect(filtering.scriptOrUserFeatureAllowsGlyph(run, 0));
    try std.testing.expect(filtering.scriptOrUserFeatureAllowsGlyph(run, 1));
    try std.testing.expect(filtering.scriptOrUserFeatureAllowsGlyph(run, 2));
    try std.testing.expect(!filtering.scriptOrUserFeatureAllowsGlyph(run, 3));

    var user_only = user_feature;
    user_only.include_script_candidates = false;
    var user_only_run = run;
    user_only_run.user_feature = &user_only;
    try std.testing.expect(!filtering.scriptOrUserFeatureAllowsGlyph(
        user_only_run,
        0,
    ));
    try std.testing.expect(filtering.scriptOrUserFeatureAllowsGlyph(
        user_only_run,
        1,
    ));
}

test "context filtering preserves substituted joiners CGJ and Mongolian FVS rules" {
    const glyphs = [_]u16{ 10, 11, 12 };
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(
        std.testing.allocator,
        &.{ false, false, false },
    );

    const joiners = [_]u21{ 'A', 0x200c, 'B' };
    const run = filtering.Options{
        .glyph_source_indices = &sources,
        .glyph_substituted = &substituted,
        .source_codepoints = &joiners,
    };
    try std.testing.expect(
        filtering.contextualMaySkipGlyph(0, run, &glyphs, 1, true),
    );
    try std.testing.expect(
        filtering.contextualMaySkipGlyph(0, run, &glyphs, 1, false),
    );
    var manual_joiners = run;
    manual_joiners.active_auto_zwnj = false;
    try std.testing.expect(
        !filtering.contextualMaySkipGlyph(
            0,
            manual_joiners,
            &glyphs,
            1,
            false,
        ),
    );
    const zwj = [_]u21{ 'A', 0x200d, 'B' };
    manual_joiners.source_codepoints = &zwj;
    manual_joiners.active_auto_zwj = false;
    try std.testing.expect(
        !filtering.contextualMaySkipGlyph(
            0,
            manual_joiners,
            &glyphs,
            1,
            false,
        ),
    );
    try std.testing.expect(
        filtering.contextualMaySkipGlyph(
            0,
            manual_joiners,
            &glyphs,
            1,
            true,
        ),
    );
    substituted.items[1] = true;
    try std.testing.expect(
        !filtering.contextualMaySkipGlyph(0, run, &glyphs, 1, true),
    );

    const cgj = [_]u21{ 'A', 0x034f, 'B' };
    var cgj_run = run;
    cgj_run.source_codepoints = &cgj;
    try std.testing.expect(
        filtering.contextualMaySkipGlyph(0, cgj_run, &glyphs, 1, false),
    );

    const mongolian = [_]u21{ 0x1868, 0x180d, 0x180a };
    var mongolian_run = run;
    mongolian_run.source_codepoints = &mongolian;
    try std.testing.expect(
        !filtering.contextualMaySkipGlyph(
            0,
            mongolian_run,
            &glyphs,
            1,
            true,
        ),
    );
}

test "ligature filtering skips fallback VS but honors CGJ reorder barriers" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });

    const vs_glyphs = [_]u16{ 1, 0, 2 };
    const variation = [_]u21{ 'f', 0xfe00, 'i' };
    try std.testing.expect(filtering.ligatureMaySkipGlyph(
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &variation,
        },
        &vs_glyphs,
        0,
        1,
    ));

    const cgj = [_]u21{ 0x064e, 0x034f, 0x0651 };
    try std.testing.expect(!filtering.ligatureMaySkipGlyph(
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &cgj,
        },
        &vs_glyphs,
        0,
        1,
    ));
}
