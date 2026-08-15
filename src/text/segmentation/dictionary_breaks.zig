//! Dynamic-programming word boundaries over one dictionary-script run.

const std = @import("std");

const dictionary_mod = @import("dictionary.zig");
const unicode = @import("../../unicode.zig");

const Score = struct {
    unknown_graphemes: usize = std.math.maxInt(usize),
    word_count: usize = std.math.maxInt(usize),

    fn betterThan(self: Score, other: Score) bool {
        return self.unknown_graphemes < other.unknown_graphemes or
            (self.unknown_graphemes == other.unknown_graphemes and
                self.word_count < other.word_count);
    }
};

/// Append soft break boundaries for dictionary-script runs in `text`.
///
/// Existing UAX #14 opportunities are not passed here; the caller merges and
/// deduplicates this optional tailoring. Unknown text consumes one grapheme at
/// a time for scoring, but boundaries are emitted only when at least one side
/// belongs to a dictionary word, avoiding arbitrary breaks through wholly
/// unknown names or foreign text.
pub fn append(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(usize),
    dictionary: *const dictionary_mod.WordBreakDictionary,
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
) !void {
    const target_script = dictionary_mod.scriptOf(dictionary);
    var run_start: ?usize = null;
    var run_end: usize = 0;
    for (graphemes) |cluster| {
        if (clusterBelongsToScript(text, cluster, target_script)) {
            if (run_start == null) run_start = cluster.byte_start;
            run_end = cluster.byte_start + cluster.byte_len;
            continue;
        }
        if (run_start) |start| {
            try appendRun(
                allocator,
                out,
                dictionary,
                text,
                start,
                run_end,
                graphemes,
            );
            run_start = null;
        }
    }
    if (run_start) |start| {
        try appendRun(
            allocator,
            out,
            dictionary,
            text,
            start,
            run_end,
            graphemes,
        );
    }
}

pub fn mergeLineBreaks(
    allocator: std.mem.Allocator,
    dictionary: *const dictionary_mod.WordBreakDictionary,
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
    base: []const unicode.LineBreak,
) ![]unicode.LineBreak {
    var dictionary_boundaries = std.ArrayList(usize).empty;
    defer dictionary_boundaries.deinit(allocator);
    try append(
        allocator,
        &dictionary_boundaries,
        dictionary,
        text,
        graphemes,
    );
    if (dictionary_boundaries.items.len == 0) {
        return try allocator.dupe(unicode.LineBreak, base);
    }

    var merged = std.ArrayList(unicode.LineBreak).empty;
    errdefer merged.deinit(allocator);
    try merged.ensureTotalCapacity(
        allocator,
        base.len + dictionary_boundaries.items.len,
    );
    var base_index: usize = 0;
    var dictionary_index: usize = 0;
    while (base_index < base.len or
        dictionary_index < dictionary_boundaries.items.len)
    {
        const base_boundary = if (base_index < base.len)
            base[base_index].byte_offset
        else
            std.math.maxInt(usize);
        const dictionary_boundary =
            if (dictionary_index < dictionary_boundaries.items.len)
                dictionary_boundaries.items[dictionary_index]
            else
                std.math.maxInt(usize);
        if (base_boundary < dictionary_boundary) {
            merged.appendAssumeCapacity(base[base_index]);
            base_index += 1;
        } else if (dictionary_boundary < base_boundary) {
            merged.appendAssumeCapacity(.{
                .byte_offset = dictionary_boundary,
                .kind = .soft,
            });
            dictionary_index += 1;
        } else {
            merged.appendAssumeCapacity(base[base_index]);
            base_index += 1;
            dictionary_index += 1;
        }
    }
    return try merged.toOwnedSlice(allocator);
}

const Step = struct {
    next: usize = 0,
    known: bool = false,
};

fn appendRun(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(usize),
    dictionary: *const dictionary_mod.WordBreakDictionary,
    text: []const u8,
    run_start: usize,
    run_end: usize,
    graphemes: []const unicode.GraphemeCluster,
) !void {
    if (run_start >= run_end) return;
    const byte_len = run_end - run_start;
    const scores = try allocator.alloc(Score, byte_len + 1);
    defer allocator.free(scores);
    const steps = try allocator.alloc(Step, byte_len + 1);
    defer allocator.free(steps);
    // A chain may contain one terminal at every scalar. Allocate from the
    // dictionary's actual depth so no arbitrary cap can silently discard a
    // valid segmentation path.
    const matches = try allocator.alloc(
        usize,
        dictionary_mod.maximumMatchCount(dictionary),
    );
    defer allocator.free(matches);
    @memset(scores, .{});
    @memset(steps, .{});
    scores[byte_len] = .{ .unknown_graphemes = 0, .word_count = 0 };

    var cluster_index = graphemes.len;
    while (cluster_index > 0) {
        cluster_index -= 1;
        const cluster = graphemes[cluster_index];
        const cursor = cluster.byte_start;
        if (cursor < run_start or cursor >= run_end) continue;
        const local = cursor - run_start;
        var best = Score{};
        var best_step = Step{};

        const match_count = dictionary_mod.matchEnds(
            dictionary,
            text,
            cursor,
            matches,
        );
        for (matches[0..match_count]) |match_end| {
            if (match_end > run_end or
                !isGraphemeBoundary(graphemes, match_end, run_end))
            {
                continue;
            }
            const suffix = scores[match_end - run_start];
            if (suffix.unknown_graphemes == std.math.maxInt(usize)) continue;
            const candidate = Score{
                .unknown_graphemes = suffix.unknown_graphemes,
                .word_count = suffix.word_count + 1,
            };
            if (candidate.betterThan(best)) {
                best = candidate;
                best_step = .{ .next = match_end, .known = true };
            }
        }

        const unknown_end = @min(
            run_end,
            cluster.byte_start + cluster.byte_len,
        );
        const suffix = scores[unknown_end - run_start];
        if (suffix.unknown_graphemes != std.math.maxInt(usize)) {
            const candidate = Score{
                .unknown_graphemes = suffix.unknown_graphemes + 1,
                .word_count = suffix.word_count,
            };
            if (candidate.betterThan(best)) {
                best = candidate;
                best_step = .{ .next = unknown_end, .known = false };
            }
        }
        scores[local] = best;
        steps[local] = best_step;
    }

    var cursor = run_start;
    while (cursor < run_end) {
        const step = steps[cursor - run_start];
        if (step.next <= cursor or step.next > run_end) break;
        const next_step = if (step.next < run_end)
            steps[step.next - run_start]
        else
            Step{};
        if (step.next < run_end and (step.known or next_step.known)) {
            try appendUnique(out, allocator, step.next);
        }
        cursor = step.next;
    }
}

fn appendUnique(
    out: *std.ArrayList(usize),
    allocator: std.mem.Allocator,
    boundary: usize,
) !void {
    if (out.items.len != 0 and out.items[out.items.len - 1] == boundary) return;
    try out.append(allocator, boundary);
}

fn isGraphemeBoundary(
    graphemes: []const unicode.GraphemeCluster,
    byte_offset: usize,
    run_end: usize,
) bool {
    if (byte_offset == run_end) return true;
    for (graphemes) |cluster| {
        if (cluster.byte_start == byte_offset) return true;
        if (cluster.byte_start > byte_offset) return false;
    }
    return false;
}

fn clusterBelongsToScript(
    text: []const u8,
    cluster: unicode.GraphemeCluster,
    target: unicode.Script,
) bool {
    const cluster_text =
        text[cluster.byte_start..][0..cluster.byte_len];
    var saw_target = false;
    var iterator = std.unicode.Utf8Iterator{ .bytes = cluster_text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        const script = unicode.scriptForCodepoint(codepoint);
        if (script == target) {
            saw_target = true;
        } else if (script != .common and script != .inherited) {
            return false;
        }
    }
    // Common punctuation is deliberately not absorbed into a dictionary run.
    // Otherwise a known word followed by a closing bracket could manufacture
    // a break that UAX #14 correctly prohibits before that punctuation.
    return saw_target;
}

test "dictionary segmentation minimizes unknown text then word count" {
    var dictionary = try dictionary_mod.WordBreakDictionary.init(
        std.testing.allocator,
        .thai,
        &.{ "ภาษา", "ไทย", "ภาษาไทย", "ดี" },
    );
    defer dictionary.deinit();
    const text = "ภาษาไทยดี";
    const graphemes = try unicode.itemizeGraphemeClusters(
        std.testing.allocator,
        text,
    );
    defer std.testing.allocator.free(graphemes);
    var breaks = std.ArrayList(usize).empty;
    defer breaks.deinit(std.testing.allocator);
    try append(
        std.testing.allocator,
        &breaks,
        &dictionary,
        text,
        graphemes,
    );
    // Fewer words wins when both paths cover all scalars: ภาษาไทย + ดี.
    try std.testing.expectEqualSlices(
        usize,
        &.{"ภาษาไทย".len},
        breaks.items,
    );
}

test "dictionary segmentation does not absorb common punctuation" {
    var dictionary = try dictionary_mod.WordBreakDictionary.init(
        std.testing.allocator,
        .thai,
        &.{ "ก", "ข" },
    );
    defer dictionary.deinit();
    const text = "ก)ข";
    const graphemes = try unicode.itemizeGraphemeClusters(
        std.testing.allocator,
        text,
    );
    defer std.testing.allocator.free(graphemes);
    var breaks = std.ArrayList(usize).empty;
    defer breaks.deinit(std.testing.allocator);
    try append(
        std.testing.allocator,
        &breaks,
        &dictionary,
        text,
        graphemes,
    );
    try std.testing.expectEqual(@as(usize, 0), breaks.items.len);
}
