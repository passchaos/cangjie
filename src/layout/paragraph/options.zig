//! Public paragraph options and their width-independent shaping projection.

const std = @import("std");

const paragraph_types = @import("../types/paragraph.zig");
const exclusions = @import("exclusions.zig");
const inline_object = @import("../inline_object/root.zig");
const line_break_policy = @import("line_break_policy.zig");
const line_regions = @import("line_regions.zig");
const tabs = @import("tabs.zig");
const hyphenation = @import("../../text/hyphenation/root.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const shaping_plan = @import("../../shaping/plan/root.zig");
const plan_validation = @import("../../shaping/plan/validation.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode = @import("../../unicode.zig");

pub const Exclusion = exclusions.Exclusion;
pub const LineBreakPolicy = line_break_policy.Policy;
pub const LineBreakPolicyRange = line_break_policy.Range;
pub const TabAlignment = tabs.Alignment;
pub const TabStop = tabs.Stop;
pub const LineRegion = line_regions.Region;

/// Optional language-aware discretionary line-breaking policy.
///
/// The dictionary determines width-independent source opportunities. The
/// character and line limit are reflow-only policy and may change between
/// layouts of one retained paragraph.
pub const Hyphenation = struct {
    /// Borrowed Liang-pattern dictionary. Null disables automatic boundaries
    /// while retaining explicit U+00AD soft-hyphen behavior.
    dictionary: ?*const hyphenation.Dictionary = null,
    /// Visible scalar drawn for a selected discretionary break.
    ///
    /// Null selects U+2010, then U+002D, then the font's U+00AD glyph. An
    /// explicit scalar is used only when the owning font contains it.
    character: ?u21 = null,
    /// Maximum immediately consecutive lines ending in a visible hyphen.
    ///
    /// Null is unlimited. Zero suppresses visible discretionary hyphens while
    /// preserving emergency wrapping.
    max_consecutive_lines: ?usize = null,
};

/// Optional optical punctuation treatment applied after line selection.
pub const PunctuationConvention = enum {
    /// Unicode-property-only behavior without regional typographic inference.
    generic,
    /// Mainland Chinese GB/T 15834-style punctuation alignment.
    gb,
    /// Taiwan/Hong Kong CNS-style centered stop punctuation.
    cns,
    /// Japanese JIS X 4051-style punctuation alignment.
    jis,
};

pub const Punctuation = struct {
    /// Explicit punctuation convention. Cangjie never infers this from locale
    /// or OpenType language tags because application language policy may differ
    /// from shaping-language selection.
    convention: PunctuationConvention = .generic,
    /// Maximum fraction of CLREQ's half-advance punctuation shrinkability.
    ///
    /// Zero disables compression. One permits at most half a glyph advance per
    /// eligible punctuation side, and compression occurs only when needed to
    /// keep an otherwise overfull selected line within its measure.
    max_compression_fraction: f32 = 0,
    /// Fraction of eligible line-end punctuation advance that may protrude past
    /// the inline-end measure. Zero disables hanging; one permits a full
    /// advance. Cangjie currently applies this to East Asian closing,
    /// exclamation, and nonstarter classes.
    end_hanging_fraction: f32 = 0,
};

/// Arabic elongation policy used by justified soft-wrapped lines.
///
/// Cangjie inserts real U+0640 source scalars into a temporary line and shapes
/// that line again. The inserted bytes never alter the caller's source text or
/// public byte coordinates.
pub const Kashida = struct {
    /// Prefer Arabic elongation before generic inter-word expansion when the
    /// shaper retained a safe Tatweel boundary.
    enabled: bool = true,
    /// Bound repeated reshaping and prevent a very wide measure from producing
    /// an impractically long run. Zero disables insertion without changing the
    /// rest of justification.
    max_insertions_per_line: usize = 8,
};

/// Variable-font expansion policy for justified soft-wrapped lines.
///
/// Cangjie prefers a custom `jstf` variation axis, matching HarfBuzz's
/// experimental convention, then falls back to the registered `wdth` axis.
/// This is distinct from the OpenType `JSTF` table.
pub const FontExpansion = struct {
    /// Shape a single-font line at a bounded wider variation coordinate before
    /// trying Kashida or generic spacing expansion.
    enabled: bool = true,
};

/// OpenType JSTF line-level justification policy.
pub const Jstf = struct {
    /// Apply shrinkage/extension priority lists and ExtenderGlyph suggestions.
    enabled: bool = true,
    /// Bound source-level U+0640 attempts made for an authored ExtenderGlyph
    /// set. Zero disables only extender insertion; priority modifications and
    /// JstfMax remain active.
    max_extender_insertions_per_line: usize = 8,
};

pub const Options = struct {
    max_width: f32,
    wrap_mode: paragraph_types.WrapMode = .word,
    word_break: paragraph_types.WordBreak = .normal,
    /// Preserve Cangjie's historical emergency-wrap behavior by default.
    overflow_wrap: paragraph_types.OverflowWrap = .break_word,
    /// Optional UTF-8 ranges overriding paragraph wrapping policy.
    ///
    /// A soft boundary uses the policy of the preceding source scalar. Ranges
    /// are ordered, non-overlapping, and may leave gaps that inherit the three
    /// paragraph-level defaults above.
    line_break_policy_ranges: []const line_break_policy.Range = &.{},
    /// Preserve the historical source-visible whitespace contract by default.
    white_space_collapse: paragraph_types.WhiteSpaceCollapse = .preserve,
    line_break_strategy: paragraph_types.LineBreakStrategy = .greedy,
    /// Inline-axis alignment.
    ///
    /// Vertical paragraphs support direction-aware `.start` and `.end`,
    /// `.center`, and `.justify` for generic inline-axis space/CJK expansion.
    /// Physical `.left`/`.right` remain horizontal-only.
    alignment: paragraph_types.TextAlign = .start,
    line_height: ?f32 = null,
    /// Paragraph base/inline direction.
    ///
    /// In vertical paragraphs `.ltr` selects a top-to-bottom inline base and
    /// `.rtl` selects bottom-to-top. UAX #9 still resolves strong directional
    /// source, explicit embeddings/overrides, and isolates inside each final
    /// column; final glyph arrays remain in physical top-to-bottom order.
    direction: pipeline_types.TextDirection = .ltr,
    /// Physical writing mode shared by shaping and final paragraph geometry.
    ///
    /// The vertical paragraph contract wraps against `max_width` as the
    /// column inline-size/height measure; `direction` selects which physical
    /// edge is logical inline start. Global and ranged
    /// `wrap_mode`, `word_break`, and `overflow_wrap` tailor safe UAX #14
    /// opportunities; emergency modes use grapheme boundaries that remain
    /// safe for shaped-output reuse. `white_space_collapse` applies along the
    /// same positive-down inline axis. `vertical_rl` and `vertical_lr` select
    /// physical column progression.
    writing_mode: pipeline_types.WritingMode = .horizontal_tb,
    text_orientation: pipeline_types.TextOrientation = .mixed,
    /// Maximum visible lines/columns in source order. Null is unlimited.
    max_lines: ?usize = null,
    /// Append "..." only when `max_lines` removes content.
    ///
    /// Horizontal lines fit the dots along x; vertical columns fit upright or
    /// sideways dots along their positive-down y axis.
    ellipsis: bool = false,
    /// Width in ordinary space advances of the repeating fallback grid.
    ///
    /// This remains active after the final explicit `tab_stops` entry and maps
    /// to the current writing mode's inline axis.
    tab_width: usize = 4,
    /// Absolute stops from each line/column fragment's logical inline start.
    tab_stops: []const tabs.Stop = &.{},
    /// Signed post-shaping adjustment for non-space source glyph advances.
    ///
    /// In vertical paragraphs, every resulting positive-down source advance
    /// must remain nonnegative so wrapping and caret topology stay monotone.
    letter_spacing: f32 = 0,
    /// Signed post-shaping adjustment for U+0020 source glyph advances.
    ///
    /// Vertical layout rejects a request whose resulting space advance would
    /// become negative; an exact zero advance remains valid.
    word_spacing: f32 = 0,
    /// Inline-axis inset reserved before each hard-break segment's first line.
    ///
    /// This maps to x horizontally and positive-down y vertically. Negative
    /// values are accepted for compatibility but clamp to zero at layout.
    first_line_indent: f32 = 0,
    /// Block-axis distance inserted after each explicit hard-break segment.
    ///
    /// This maps to positive-down y horizontally and follows the selected
    /// left-to-right/right-to-left column progression vertically. Negative
    /// values intentionally overlap adjacent paragraph segments.
    paragraph_spacing: f32 = 0,
    /// Rectangular paragraph-space areas unavailable to wrapped text.
    ///
    /// Horizontal lines and vertical columns choose the widest remaining
    /// contiguous inline fragment. Fully blocked vertical-lr/vertical-rl
    /// bands advance in their respective physical block directions.
    /// Exclusions are ignored by `.no_wrap`.
    exclusions: []const exclusions.Exclusion = &.{},
    /// Caller-selected paragraph-space geometry for a visual-fragment prefix.
    ///
    /// Entry `i` overrides the natural region for final visual fragment `i`.
    /// Horizontal x/width describe the line fragment. Vertical x is the block
    /// origin while y/width describe the column's inline origin/height.
    /// Explicit regions bypass indentation and exclusions for that fragment.
    line_regions: []const line_regions.Region = &.{},
    /// Inline objects anchored by U+FFFC markers in the paragraph text.
    ///
    /// This slice may change between retained reflows as long as object count
    /// and byte anchors remain identical; geometry does not affect shaping.
    inline_objects: []const inline_object.Object = &.{},
    /// Absolute placements for `.custom_out_of_flow` objects.
    ///
    /// Ordinary layout may consume caller-authored placements directly.
    /// `paragraph.OutOfFlowResolver` produces this slice while coordinating
    /// placement-dependent exclusions across replayed reflow passes.
    out_of_flow_placements: []const inline_object.Placement = &.{},
    /// Optional dictionary tailoring for scripts that normally omit spaces.
    ///
    /// The dictionary is borrowed and must outlive the layout call or retained
    /// paragraph. Its boundaries still pass grapheme and shaping safety checks.
    word_break_dictionary: ?*const segmentation.WordBreakDictionary = null,
    /// Optional automatic-hyphenation data and line-level policy.
    hyphenation: Hyphenation = .{},
    /// Optional optical punctuation policy.
    punctuation: Punctuation = .{},
    /// Optional Arabic Kashida insertion for justified soft-wrapped lines.
    kashida: Kashida = .{},
    /// Optional variable-font width adaptation before discrete expansion.
    font_expansion: FontExpansion = .{},
    /// OpenType JSTF table policy, independent from generic Kashida fallback.
    jstf: Jstf = .{},
    /// Shaping controls resolved before line breaking.
    script_tag: ?unicode.OpenTypeScriptTag = null,
    language_tag: ?unicode.OpenTypeLanguageTag = null,
    features: []const unicode.FeatureOverride = &.{},
    normalized_variation_coords: []const f32 = &.{},
};

pub fn validate(options: Options) !void {
    // Infinite max width means unbounded layout. NaN and non-finite spacing
    // values cannot participate in deterministic line geometry.
    if (std.math.isNan(options.max_width)) {
        return error.InvalidParagraphOptions;
    }
    if (options.line_height) |line_height| {
        if (!std.math.isFinite(line_height) or line_height <= 0) {
            return error.InvalidParagraphOptions;
        }
    }
    if (!std.math.isFinite(options.letter_spacing) or
        !std.math.isFinite(options.word_spacing) or
        !std.math.isFinite(options.first_line_indent) or
        !std.math.isFinite(options.paragraph_spacing))
    {
        return error.InvalidParagraphOptions;
    }
    try line_break_policy.validate(options.line_break_policy_ranges);
    try exclusions.validate(options.exclusions);
    try line_regions.validate(options.line_regions);
    try tabs.validate(options.tab_stops);
    try inline_object.validatePlacements(
        options.inline_objects,
        options.out_of_flow_placements,
    );
    if (!std.math.isFinite(options.punctuation.end_hanging_fraction) or
        options.punctuation.end_hanging_fraction < 0 or
        options.punctuation.end_hanging_fraction > 1)
    {
        return error.InvalidParagraphOptions;
    }
    if (!std.math.isFinite(options.punctuation.max_compression_fraction) or
        options.punctuation.max_compression_fraction < 0 or
        options.punctuation.max_compression_fraction > 1)
    {
        return error.InvalidParagraphOptions;
    }
    if (options.hyphenation.character) |character| {
        if (!std.unicode.utf8ValidCodepoint(character)) {
            return error.InvalidParagraphOptions;
        }
    }
    try plan_validation.features(options.features);
    try plan_validation.variationCoords(options.normalized_variation_coords);
}

pub fn validateForText(text: []const u8, options: Options) !void {
    try validate(options);
    try line_break_policy.validateForText(
        text,
        options.line_break_policy_ranges,
    );
    if (options.writing_mode.isVertical()) {
        try validateVerticalForText(text, options);
    }
}

pub fn defaultLineBreakPolicy(options: Options) line_break_policy.Policy {
    return .{
        .wrap_mode = options.wrap_mode,
        .word_break = options.word_break,
        .overflow_wrap = options.overflow_wrap,
    };
}

pub fn shapeOptions(options: Options) shaping_plan.ShapeOptions {
    return .{
        .direction = options.direction,
        // Retain logical order until line boundaries are known. Homogeneous
        // runs still shape in their OpenType-native direction.
        .reorder_bidi = false,
        .native_direction_shaping = true,
        // RL/LR selects paragraph block progression, not OpenType shaping.
        // Normalizing both vertical modes lets one retained shaped snapshot
        // reflow into either physical column order.
        .writing_mode = if (options.writing_mode.isVertical())
            .vertical_rl
        else
            .horizontal_tb,
        .text_orientation = options.text_orientation,
        .script_tag = options.script_tag,
        .language_tag = options.language_tag,
        .features = options.features,
        .normalized_variation_coords = options.normalized_variation_coords,
    };
}

/// Guard the intentionally small first vertical-paragraph surface.
///
/// Every rejected feature currently owns horizontal-only geometry somewhere
/// after shaping. Keeping this list explicit makes new support an auditable
/// axis-conversion task instead of allowing a newly added paragraph option to
/// become an accidental vertical no-op.
fn validateVerticalForText(_: []const u8, options: Options) !void {
    if (!verticalAlignmentSupported(options.alignment)) {
        return error.UnsupportedVerticalParagraphOptions;
    }
}

fn verticalAlignmentSupported(alignment: paragraph_types.TextAlign) bool {
    return switch (alignment) {
        .start, .center, .end, .justify => true,
        .left, .right => false,
    };
}

pub fn matchesShapeKey(
    text: []const u8,
    options: Options,
    key: shaping_plan.ShapePlanKey,
) bool {
    return shaping_plan.ShapePlanKey.fromText(
        text,
        shapeOptions(options),
    ).eql(key);
}

test "hyphenation character must be a Unicode scalar" {
    try std.testing.expectError(
        error.InvalidParagraphOptions,
        validate(.{
            .max_width = 100,
            .hyphenation = .{ .character = 0xd800 },
        }),
    );
    try validate(.{
        .max_width = 100,
        .hyphenation = .{ .character = 0x10ffff },
    });
}

test "punctuation hanging fraction stays normalized" {
    for ([_]f32{ -0.01, 1.01, std.math.inf(f32), std.math.nan(f32) }) |value| {
        try std.testing.expectError(
            error.InvalidParagraphOptions,
            validate(.{
                .max_width = 100,
                .punctuation = .{ .end_hanging_fraction = value },
            }),
        );
    }
    try validate(.{
        .max_width = 100,
        .punctuation = .{ .end_hanging_fraction = 1 },
    });
}

test "punctuation compression fraction stays normalized" {
    for ([_]f32{ -0.01, 1.01, std.math.inf(f32), std.math.nan(f32) }) |value| {
        try std.testing.expectError(
            error.InvalidParagraphOptions,
            validate(.{
                .max_width = 100,
                .punctuation = .{ .max_compression_fraction = value },
            }),
        );
    }
    try validate(.{
        .max_width = 100,
        .punctuation = .{ .max_compression_fraction = 1 },
    });
}

test "paragraph exclusions require finite nonnegative rectangles" {
    for ([_]Exclusion{
        .{ .x = std.math.nan(f32), .y = 0, .width = 1, .height = 1 },
        .{ .x = 0, .y = std.math.inf(f32), .width = 1, .height = 1 },
        .{ .x = 0, .y = 0, .width = -1, .height = 1 },
        .{ .x = 0, .y = 0, .width = 1, .height = -1 },
    }) |item| {
        try std.testing.expectError(
            error.InvalidParagraphOptions,
            validate(.{
                .max_width = 100,
                .exclusions = &.{item},
            }),
        );
    }
    try validate(.{
        .max_width = 100,
        .exclusions = &.{.{
            .x = -10,
            .y = 0,
            .width = 20,
            .height = 20,
        }},
    });
}

test "zero Kashida insertion limit is an explicit disable" {
    const options = Options{
        .max_width = 100,
        .kashida = .{ .max_insertions_per_line = 0 },
    };
    try validate(options);
    try std.testing.expectEqual(
        @as(usize, 0),
        options.kashida.max_insertions_per_line,
    );
}

test "JSTF extender limit is independent from generic Kashida" {
    const options = Options{
        .max_width = 100,
        .jstf = .{ .max_extender_insertions_per_line = 0 },
        .kashida = .{ .max_insertions_per_line = 7 },
    };
    try validate(options);
    try std.testing.expectEqual(
        @as(usize, 0),
        options.jstf.max_extender_insertions_per_line,
    );
    try std.testing.expectEqual(
        @as(usize, 7),
        options.kashida.max_insertions_per_line,
    );
}

test "vertical paragraph validation admits only implemented columns" {
    try validateForText("AA", .{
        .max_width = 100,
        .writing_mode = .vertical_rl,
    });
    try validateForText("אב", .{
        .max_width = 100,
        .direction = .rtl,
        .writing_mode = .vertical_lr,
    });
    try validateForText("AA", .{
        .max_width = 100,
        .exclusions = &.{.{ .x = 0, .y = 0, .width = 20, .height = 20 }},
        .writing_mode = .vertical_lr,
    });
    try validateForText("AA", .{
        .max_width = 100,
        .line_regions = &.{.{ .x = 10, .y = 20, .width = 30 }},
        .writing_mode = .vertical_rl,
    });
    try validateForText("AA", .{
        .max_width = 100,
        .word_break = .break_all,
        .overflow_wrap = .anywhere,
        .writing_mode = .vertical_rl,
    });
    try validateForText("AA", .{
        .max_width = 100,
        .word_break = .keep_all,
        .overflow_wrap = .normal,
        .writing_mode = .vertical_lr,
    });
    try validateForText("AA", .{
        .max_width = 100,
        .line_break_strategy = .balanced,
        .alignment = .justify,
        .writing_mode = .vertical_lr,
    });
    try validateForText("A\u{00ad}A", .{
        .max_width = 100,
        .hyphenation = .{ .character = 0x2010 },
        .writing_mode = .vertical_lr,
    });
    try validateForText("一。", .{
        .max_width = 100,
        .punctuation = .{
            .max_compression_fraction = 1,
            .end_hanging_fraction = 0.5,
        },
        .writing_mode = .vertical_lr,
    });
    var hyphenation_dictionary =
        try hyphenation.Dictionary.init(
            std.testing.allocator,
            "a1b",
            "",
            .{ .left_min = 1, .right_min = 1 },
        );
    defer hyphenation_dictionary.deinit();
    try validateForText("ab", .{
        .max_width = 100,
        .hyphenation = .{
            .dictionary = &hyphenation_dictionary,
            .max_consecutive_lines = 1,
        },
        .writing_mode = .vertical_rl,
    });
    var dictionary = try segmentation.WordBreakDictionary.init(
        std.testing.allocator,
        .thai,
        &.{"ภาษา"},
    );
    defer dictionary.deinit();
    try validateForText("ภาษา", .{
        .max_width = 100,
        .word_break_dictionary = &dictionary,
        .writing_mode = .vertical_rl,
    });
    try validateForText("AA", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .word_break = .break_all,
        .overflow_wrap = .anywhere,
        .writing_mode = .vertical_lr,
    });
    try validateForText("AA", .{
        .max_width = 100,
        .writing_mode = .vertical_lr,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = 1,
            .word_break = .break_all,
        }},
    });
    try validateForText("A\nA", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .writing_mode = .vertical_rl,
    });
    try validateForText("A\tA", .{
        .max_width = 100,
        .wrap_mode = .no_wrap,
        .tab_stops = &.{.{ .position = 40 }},
        .writing_mode = .vertical_rl,
    });
}
