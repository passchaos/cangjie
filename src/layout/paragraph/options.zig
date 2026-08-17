//! Public paragraph options and their width-independent shaping projection.

const std = @import("std");

const paragraph_types = @import("../types/paragraph.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const shaping_plan = @import("../../shaping/plan/root.zig");
const plan_validation = @import("../../shaping/plan/validation.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode = @import("../../unicode.zig");

pub const Options = struct {
    max_width: f32,
    wrap_mode: paragraph_types.WrapMode = .word,
    alignment: paragraph_types.TextAlign = .start,
    line_height: ?f32 = null,
    direction: pipeline_types.TextDirection = .ltr,
    max_lines: ?usize = null,
    /// Append "..." only when `max_lines` removes content.
    ellipsis: bool = false,
    tab_width: usize = 4,
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    first_line_indent: f32 = 0,
    paragraph_spacing: f32 = 0,
    /// Optional dictionary tailoring for scripts that normally omit spaces.
    ///
    /// The dictionary is borrowed and must outlive the layout call or retained
    /// paragraph. Its boundaries still pass grapheme and shaping safety checks.
    word_break_dictionary: ?*const segmentation.WordBreakDictionary = null,
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
    try plan_validation.features(options.features);
    try plan_validation.variationCoords(options.normalized_variation_coords);
}

pub fn shapeOptions(options: Options) shaping_plan.ShapeOptions {
    return .{
        .direction = options.direction,
        // Retain logical order until line boundaries are known. Homogeneous
        // runs still shape in their OpenType-native direction.
        .reorder_bidi = false,
        .native_direction_shaping = true,
        .script_tag = options.script_tag,
        .language_tag = options.language_tag,
        .features = options.features,
        .normalized_variation_coords = options.normalized_variation_coords,
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
