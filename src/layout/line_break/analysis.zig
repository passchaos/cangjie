//! Width-independent paragraph boundary analysis.
//!
//! UAX #14 remains the required base. Optional language segmentation can add
//! soft boundaries, but cannot remove standard hard or soft opportunities.

const std = @import("std");

const dictionary_breaks = @import("../../text/segmentation/dictionary_breaks.zig");
const hyphenation = @import("../../text/hyphenation/root.zig");
const opportunity = @import("opportunity.zig");
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
    errdefer tailored.deinit(allocator);
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
    return try tailored.toOwnedSlice(allocator);
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
    );
    defer std.testing.allocator.free(breaks);
    for (breaks) |line_break| {
        try std.testing.expect(
            line_break.byte_offset != 1 or
                !line_break.automatic_hyphen,
        );
    }
}
