//! Width-independent paragraph boundary analysis.
//!
//! UAX #14 remains the required base. Optional language segmentation can add
//! soft boundaries, but cannot remove standard hard or soft opportunities.

const std = @import("std");

const dictionary_breaks = @import("../../text/segmentation/dictionary_breaks.zig");
const hyphenation = @import("../../text/hyphenation/root.zig");
const opportunity = @import("opportunity.zig");
const line_break_policy = @import("../paragraph/line_break_policy.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode = @import("../../unicode.zig");

/// Materialize UAX #14 plus optional word and hyphenation tailoring.
///
/// One-shot layout calls this only when a dictionary requires merging; normal
/// paragraphs continue streaming UAX #14 through `LineBreakCursor`.
pub fn itemizeWithHyphenation(
    allocator: std.mem.Allocator,
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const hyphenation.Dictionary,
    defaults: line_break_policy.Policy,
    policy_ranges: []const line_break_policy.Range,
) ![]opportunity.Opportunity {
    const base = try unicode.itemizeLineBreaks(allocator, text);
    defer allocator.free(base);
    const segmented = if (dictionary) |selected|
        try dictionary_breaks.mergeLineBreaks(
            allocator,
            selected,
            text,
            graphemes,
            base,
        )
    else
        try allocator.dupe(unicode.LineBreak, base);
    defer allocator.free(segmented);

    var tailored = std.ArrayList(opportunity.Opportunity).empty;
    defer tailored.deinit(allocator);
    try tailored.ensureTotalCapacity(allocator, segmented.len);
    for (segmented) |value| {
        tailored.appendAssumeCapacity(opportunity.fromUnicode(value));
    }
    if (hyphenation_dictionary) |selected| {
        try appendHyphenation(
            allocator,
            &tailored,
            selected,
            text,
            graphemes,
        );
    }
    return try tailorBreakPolicy(
        allocator,
        text,
        graphemes,
        tailored.items,
        defaults,
        policy_ranges,
    );
}

/// Apply width-dependent wrapping policy to an existing base opportunity set.
///
/// Retained paragraphs store UAX/dictionary/hyphenation analysis once and use
/// this operation when only `word_break` or `overflow_wrap` changes.
pub fn tailorBreakPolicy(
    allocator: std.mem.Allocator,
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
    base: []const opportunity.Opportunity,
    defaults: line_break_policy.Policy,
    policy_ranges: []const line_break_policy.Range,
) ![]opportunity.Opportunity {
    var tailored = std.ArrayList(opportunity.Opportunity).empty;
    errdefer tailored.deinit(allocator);
    try tailored.ensureTotalCapacity(allocator, base.len);
    for (base) |item| {
        if (item.kind != .soft) {
            tailored.appendAssumeCapacity(item);
            continue;
        }
        const policy = line_break_policy.beforeBoundary(
            defaults,
            policy_ranges,
            item.byte_offset,
        );
        if (policy.wrap_mode == .no_wrap or
            (item.automatic_hyphen and policy.word_break == .break_all) or
            (!item.automatic_hyphen and policy.word_break == .keep_all and
                cjkWordBoundary(text, graphemes, item.byte_offset)))
        {
            continue;
        }
        tailored.appendAssumeCapacity(item);
    }
    try appendPolicyGraphemeBreaks(
        allocator,
        &tailored,
        graphemes,
        text.len,
        defaults,
        policy_ranges,
    );
    return tailored.toOwnedSlice(allocator);
}

fn appendPolicyGraphemeBreaks(
    allocator: std.mem.Allocator,
    opportunities: *std.ArrayList(opportunity.Opportunity),
    graphemes: []const unicode.GraphemeCluster,
    text_len: usize,
    defaults: line_break_policy.Policy,
    policy_ranges: []const line_break_policy.Range,
) !void {
    for (graphemes) |cluster| {
        const byte_offset = cluster.byte_start;
        if (byte_offset == 0 or byte_offset >= text_len) continue;
        const policy = line_break_policy.beforeBoundary(
            defaults,
            policy_ranges,
            byte_offset,
        );
        if (policy.wrap_mode == .no_wrap or
            (policy.word_break != .break_all and
                policy.overflow_wrap != .anywhere))
        {
            continue;
        }
        try mergeOpportunity(opportunities, allocator, .{
            .byte_offset = byte_offset,
            .kind = .soft,
            .arbitrary = true,
        });
    }
}

fn cjkWordBoundary(
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
    byte_offset: usize,
) bool {
    if (byte_offset == 0 or byte_offset >= text.len) return false;
    var previous: ?unicode.GraphemeCluster = null;
    var next: ?unicode.GraphemeCluster = null;
    for (graphemes) |cluster| {
        const end = cluster.byte_start + cluster.byte_len;
        if (end == byte_offset) previous = cluster;
        if (cluster.byte_start == byte_offset) {
            next = cluster;
            break;
        }
        if (cluster.byte_start > byte_offset) break;
    }
    return clusterIsCjkWord(text, previous orelse return false) and
        clusterIsCjkWord(text, next orelse return false);
}

fn clusterIsCjkWord(
    text: []const u8,
    cluster: unicode.GraphemeCluster,
) bool {
    const bytes = text[cluster.byte_start..][0..cluster.byte_len];
    var iterator = std.unicode.Utf8Iterator{ .bytes = bytes, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (isCjkWordCodepoint(codepoint)) return true;
    }
    return false;
}

fn isCjkWordCodepoint(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .ideographic,
        .emoji_base,
        .emoji_modifier,
        .conditional_japanese_starter,
        .hangul_l_jamo,
        .hangul_v_jamo,
        .hangul_t_jamo,
        .hangul_lv_syllable,
        .hangul_lvt_syllable,
        => true,
        else => false,
    };
}

fn appendHyphenation(
    allocator: std.mem.Allocator,
    opportunities: *std.ArrayList(opportunity.Opportunity),
    dictionary: *const hyphenation.Dictionary,
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
) !void {
    var boundaries = std.ArrayList(usize).empty;
    defer boundaries.deinit(allocator);
    var words = try unicode.wordSegments(text);
    while (words.next()) |segment| {
        if (!segment.is_word) continue;
        const word = text[segment.byte_start .. segment.byte_start + segment.byte_len];
        try dictionary.hyphenate(allocator, word, &boundaries);
        for (boundaries.items) |local_boundary| {
            const byte_offset = segment.byte_start + local_boundary;
            // Liang operates on scalar gaps, while paragraph reuse is
            // grapheme-oriented. A caller-provided pattern must not make a
            // combining sequence splittable merely because its scalars are
            // individually valid UTF-8 boundaries.
            if (!isGraphemeBoundary(graphemes, byte_offset)) continue;
            try mergeOpportunity(opportunities, allocator, .{
                .byte_offset = byte_offset,
                .kind = .soft,
                .automatic_hyphen = true,
            });
        }
    }
}

fn mergeOpportunity(
    opportunities: *std.ArrayList(opportunity.Opportunity),
    allocator: std.mem.Allocator,
    value: opportunity.Opportunity,
) !void {
    var low: usize = 0;
    var high: usize = opportunities.items.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (opportunities.items[mid].byte_offset < value.byte_offset) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low < opportunities.items.len and
        opportunities.items[low].byte_offset == value.byte_offset)
    {
        // Mandatory Unicode boundaries stay mandatory. At a pre-existing soft
        // boundary, retaining automatic-hyphen semantics lets language data
        // request a visible glyph without duplicating the opportunity.
        if (opportunities.items[low].kind == .soft) {
            opportunities.items[low].automatic_hyphen =
                opportunities.items[low].automatic_hyphen or
                value.automatic_hyphen;
            opportunities.items[low].arbitrary =
                opportunities.items[low].arbitrary and value.arbitrary;
        }
        return;
    }
    try opportunities.replaceRange(allocator, low, 0, &.{value});
}

fn isGraphemeBoundary(
    graphemes: []const unicode.GraphemeCluster,
    byte_offset: usize,
) bool {
    var low: usize = 0;
    var high: usize = graphemes.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (graphemes[mid].byte_start < byte_offset) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low < graphemes.len and
        graphemes[low].byte_start == byte_offset;
}

test "automatic hyphenation never splits an extended grapheme cluster" {
    var dictionary = try hyphenation.Dictionary.init(
        std.testing.allocator,
        "a1́",
        "",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();
    const text = "áb";
    var dictionary_boundaries = std.ArrayList(usize).empty;
    defer dictionary_boundaries.deinit(std.testing.allocator);
    try dictionary.hyphenate(
        std.testing.allocator,
        text,
        &dictionary_boundaries,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{1},
        dictionary_boundaries.items,
    );
    const graphemes = try unicode.itemizeGraphemeClusters(
        std.testing.allocator,
        text,
    );
    defer std.testing.allocator.free(graphemes);
    const breaks = try itemizeWithHyphenation(
        std.testing.allocator,
        text,
        graphemes,
        null,
        &dictionary,
        .{
            .wrap_mode = .word,
            .word_break = .normal,
            .overflow_wrap = .break_word,
        },
        &.{},
    );
    defer std.testing.allocator.free(breaks);
    for (breaks) |line_break| {
        try std.testing.expect(
            line_break.byte_offset != 1 or
                !line_break.automatic_hyphen,
        );
    }
}

test "break policy adds grapheme edges and keeps CJK words intact" {
    const allocator = std.testing.allocator;
    const latin_text = "AAAA";
    const latin_graphemes = try unicode.itemizeGraphemeClusters(
        allocator,
        latin_text,
    );
    defer allocator.free(latin_graphemes);
    const latin_base = try itemizeWithHyphenation(
        allocator,
        latin_text,
        latin_graphemes,
        null,
        null,
        .{
            .wrap_mode = .word,
            .word_break = .normal,
            .overflow_wrap = .break_word,
        },
        &.{},
    );
    defer allocator.free(latin_base);
    const break_all = try tailorBreakPolicy(
        allocator,
        latin_text,
        latin_graphemes,
        latin_base,
        .{
            .wrap_mode = .word,
            .word_break = .break_all,
            .overflow_wrap = .normal,
        },
        &.{},
    );
    defer allocator.free(break_all);
    for ([_]usize{ 1, 2, 3 }) |byte_offset| {
        const found = for (break_all) |item| {
            if (item.byte_offset == byte_offset and item.arbitrary) break true;
        } else false;
        try std.testing.expect(found);
    }

    const cjk_text = "一丁丂";
    const cjk_graphemes = try unicode.itemizeGraphemeClusters(
        allocator,
        cjk_text,
    );
    defer allocator.free(cjk_graphemes);
    const cjk_base = try itemizeWithHyphenation(
        allocator,
        cjk_text,
        cjk_graphemes,
        null,
        null,
        .{
            .wrap_mode = .word,
            .word_break = .normal,
            .overflow_wrap = .break_word,
        },
        &.{},
    );
    defer allocator.free(cjk_base);
    var normal_soft_count: usize = 0;
    for (cjk_base) |item| {
        if (item.kind == .soft) normal_soft_count += 1;
    }
    const keep_all = try tailorBreakPolicy(
        allocator,
        cjk_text,
        cjk_graphemes,
        cjk_base,
        .{
            .wrap_mode = .word,
            .word_break = .keep_all,
            .overflow_wrap = .normal,
        },
        &.{},
    );
    defer allocator.free(keep_all);
    var kept_soft_count: usize = 0;
    for (keep_all) |item| {
        if (item.kind == .soft) kept_soft_count += 1;
    }
    try std.testing.expect(normal_soft_count > kept_soft_count);
    try std.testing.expectEqual(@as(usize, 0), kept_soft_count);

    const ivs_text = "一\u{e0100}丁";
    const ivs_graphemes = try unicode.itemizeGraphemeClusters(
        allocator,
        ivs_text,
    );
    defer allocator.free(ivs_graphemes);
    const ivs_base = try itemizeWithHyphenation(
        allocator,
        ivs_text,
        ivs_graphemes,
        null,
        null,
        .{
            .wrap_mode = .word,
            .word_break = .normal,
            .overflow_wrap = .break_word,
        },
        &.{},
    );
    defer allocator.free(ivs_base);
    const ivs_keep_all = try tailorBreakPolicy(
        allocator,
        ivs_text,
        ivs_graphemes,
        ivs_base,
        .{
            .wrap_mode = .word,
            .word_break = .keep_all,
            .overflow_wrap = .normal,
        },
        &.{},
    );
    defer allocator.free(ivs_keep_all);
    for (ivs_keep_all) |item| {
        try std.testing.expect(
            item.kind != .soft or item.byte_offset != "一\u{e0100}".len,
        );
    }
}
