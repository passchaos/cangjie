//! Complete greedy/balanced paragraph reflow orchestration.
//!
//! Resumable callers enter `greedy.zig` directly. This module owns only the
//! whole-layout policy that may probe greedy line count and solve a balanced
//! plan before replaying the selected boundaries through the shared greedy
//! state machine.

const std = @import("std");

const analysis = @import("../analysis.zig");
const balanced = @import("balanced.zig");
const geometry = @import("geometry.zig");
const greedy = @import("greedy.zig");
const line_break_opportunity = @import("../opportunity.zig");
const line_break_policy = @import("../../paragraph/line_break_policy.zig");
const paragraph_options = @import("../../paragraph/options.zig");
const segmentation = @import("../../../text/segmentation/root.zig");
const vertical_columns = @import("../../paragraph/vertical_columns.zig");
const white_space = @import("../../paragraph/white_space.zig");
const unicode = @import("../../../unicode.zig");

pub fn build(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
) !void {
    return buildWithJstfShrinkage(
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
        hyphenation_dictionary,
        NoShrinkageRecipe{},
    );
}

pub fn buildWithJstfShrinkage(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
    recipe: anytype,
) !void {
    if (options.writing_mode.isVertical()) {
        return vertical_columns.build(
            buffer,
            text,
            options,
            default_metrics,
            analyzed_graphemes,
            analyzed_line_breaks,
        );
    }
    if (options.line_break_strategy == .balanced and
        line_break_policy.anyWrappingEnabled(
            text.len,
            paragraph_options.defaultLineBreakPolicy(options),
            options.line_break_policy_ranges,
        ) and
        std.math.isFinite(if (options.max_width > 0)
            options.max_width
        else
            std.math.inf(f32)) and
        options.max_lines != 0 and
        buffer.glyphs.items.len != 0)
    {
        return buildBalanced(
            buffer,
            text,
            options,
            default_metrics,
            analyzed_graphemes,
            analyzed_line_breaks,
            dictionary,
            hyphenation_dictionary,
            recipe,
        );
    }
    return greedy.buildWithPlan(
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
        hyphenation_dictionary,
        recipe,
        null,
    );
}

fn buildBalanced(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
    recipe: anytype,
) !void {
    // The optimizer needs an immutable glyph snapshot and the exact number of
    // lines selected by current paragraph semantics. Run ordinary greedy
    // reflow in a temporary buffer, then solve against the untouched source.
    var probe = @TypeOf(buffer.*).init(buffer.allocator);
    defer probe.deinit();
    inheritShapeCaches(buffer, &probe);
    try copyLayoutInputs(buffer, &probe);
    var greedy_options = options;
    greedy_options.line_break_strategy = .greedy;
    {
        try recipe.beginReflowTrial();
        defer recipe.rollbackReflowTrial();
        try greedy.buildWithPlan(
            &probe,
            text,
            greedy_options,
            default_metrics,
            analyzed_graphemes,
            analyzed_line_breaks,
            dictionary,
            hyphenation_dictionary,
            recipe,
            null,
        );
    }

    var planner = @TypeOf(buffer.*).init(buffer.allocator);
    defer planner.deinit();
    inheritShapeCaches(buffer, &planner);
    try copyLayoutInputs(buffer, &planner);
    try greedy.prepareAdvances(planner.glyphs.items, options);
    white_space.prepare(
        planner.glyphs.items,
        options.white_space_collapse,
        geometry.defaultSpaceAdvance(planner.glyphs.items),
    );

    var owned_graphemes: ?[]unicode.GraphemeCluster = null;
    defer if (owned_graphemes) |clusters| buffer.allocator.free(clusters);
    const grapheme_clusters = analyzed_graphemes orelse clusters: {
        owned_graphemes = try unicode.itemizeGraphemeClusters(
            buffer.allocator,
            text,
        );
        break :clusters owned_graphemes.?;
    };
    var owned_line_breaks: ?[]line_break_opportunity.Opportunity = null;
    defer if (owned_line_breaks) |breaks| buffer.allocator.free(breaks);
    const effective_line_breaks = analyzed_line_breaks orelse breaks: {
        owned_line_breaks = try analysis.itemizeWithHyphenation(
            buffer.allocator,
            text,
            grapheme_clusters,
            dictionary,
            hyphenation_dictionary,
            paragraph_options.defaultLineBreakPolicy(options),
            options.line_break_policy_ranges,
        );
        break :breaks owned_line_breaks.?;
    };
    var plan = try balanced.build(
        &planner,
        text,
        options,
        default_metrics,
        grapheme_clusters,
        effective_line_breaks,
        probe.lines.items,
        recipe,
    );
    defer if (plan) |*selected| selected.deinit();

    try greedy.buildWithPlan(
        buffer,
        text,
        options,
        default_metrics,
        grapheme_clusters,
        effective_line_breaks,
        dictionary,
        hyphenation_dictionary,
        recipe,
        if (plan) |*selected| selected else null,
    );
}

fn copyLayoutInputs(source: anytype, destination: anytype) !void {
    try destination.variation_coords.appendSlice(
        destination.allocator,
        source.variation_coords.items,
    );
    errdefer destination.clear();
    try destination.glyphs.appendSlice(
        destination.allocator,
        source.glyphs.items,
    );
    try destination.runs.appendSlice(
        destination.allocator,
        source.runs.items,
    );
}

fn inheritShapeCaches(source: anytype, destination: anytype) void {
    destination.gdef_metadata_cache = source.gdef_metadata_cache;
    destination.gsub_table_proof_cache = source.gsub_table_proof_cache;
    destination.gpos_table_proof_cache = source.gpos_table_proof_cache;
    destination.lookup_selection_cache = source.lookup_selection_cache;
}

const NoShrinkageRecipe = struct {
    pub fn beginReflowTrial(_: @This()) !void {}
    pub fn rollbackReflowTrial(_: @This()) void {}
    pub fn minimumLineHeight(_: @This(), _: usize, _: usize) ?f32 {
        return null;
    }
    pub fn canShrinkSourceRange(_: @This(), _: usize, _: usize) bool {
        return false;
    }
    pub fn jstfTags(
        _: @This(),
        _: usize,
        _: usize,
    ) struct {
        script: unicode.OpenTypeScriptTag,
        language: unicode.OpenTypeLanguageTag,
    } {
        return .{ .script = .dflt, .language = .dflt };
    }
    pub fn shapeRangeWithJstfPriority(
        _: @This(),
        _: anytype,
        _: usize,
        _: usize,
        _: anytype,
        _: usize,
        _: anytype,
        _: []const usize,
    ) !void {
        unreachable;
    }
    pub fn prepareCommit(
        _: @This(),
        _: usize,
        _: usize,
        _: usize,
    ) !void {
        unreachable;
    }
    pub fn commit(_: @This(), _: usize, _: usize, _: usize) void {
        unreachable;
    }
};
