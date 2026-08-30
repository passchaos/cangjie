const std = @import("std");
const face_mod = @import("../font/face/root.zig");
const line_break_policy = @import("paragraph/line_break_policy.zig");
const paragraph_options = @import("paragraph/options.zig");
const unicode = @import("../unicode.zig");

/// One contiguous style item for unified paragraph shaping.
///
/// Spans form an exact, ordered partition of the UTF-8 input. Font family
/// resolution remains the caller's responsibility; this type contains only
/// shaping and geometry choices used after a cascade has been selected.
pub const Span = struct {
    byte_start: usize,
    byte_len: usize,
    style_index: u32,
    font_size: f32,
    /// Optional style-resolved cascade. A null slice inherits the paragraph
    /// cascade; a non-null slice is owned by the caller for one-shot layout and
    /// copied by retained preparation. Retained preparation keeps inheritance
    /// bound to the original paragraph cascade and uses a separate union only
    /// to assign stable public run indexes.
    faces: ?[]const *const face_mod.Face = null,
    script_tag: ?unicode.OpenTypeScriptTag = null,
    language_tag: ?unicode.OpenTypeLanguageTag = null,
    features: []const unicode.FeatureOverride = &.{},
    normalized_variation_coords: []const f32 = &.{},
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    minimum_line_height: ?f32 = null,
    vertical_align: @import("types/paragraph.zig").VerticalAlign = .baseline,
    /// Optional attributed overrides of paragraph wrapping policy.
    ///
    /// These affect line analysis only and therefore do not split otherwise
    /// shaping-equivalent spans.
    wrap_mode: ?@import("types/paragraph.zig").WrapMode = null,
    word_break: ?@import("types/paragraph.zig").WordBreak = null,
    overflow_wrap: ?@import("types/paragraph.zig").OverflowWrap = null,

    pub fn byteEnd(self: Span) usize {
        return self.byte_start + self.byte_len;
    }
};

/// Glyph-parallel metadata allocated only for unified attributed paragraphs.
pub const GlyphMetadata = struct {
    style_index: u32,
    layout_spacing: f32,
    minimum_line_height: ?f32,
    vertical_align: @import("types/paragraph.zig").VerticalAlign = .baseline,
};

/// Drive script/style itemization through a layout-owned context.
///
/// Keeping the driver generic avoids a dependency cycle with the large layout
/// module while moving partition traversal and shaping-equivalence policy into
/// this focused module. The context owns actual shaping, fallback, reflow, and
/// bidi operations.
pub fn layout(context: anytype, text: []const u8, spans: []const Span) !void {
    try shape(context, text, spans);
    try context.finish(spans);
}

/// Validate and shape the unified logical glyph stream without performing
/// width-dependent paragraph presentation. Retained styled paragraphs use
/// this boundary to snapshot the pristine glyphs and metadata once.
pub fn shape(context: anytype, text: []const u8, spans: []const Span) !void {
    try validatePartition(text, spans);
    for (spans) |span| try context.validateSpan(span);

    const script_runs = try unicode.itemizeScriptRuns(context.allocator(), text);
    defer context.allocator().free(script_runs);
    var script_index: usize = 0;
    var span_index: usize = 0;
    while (span_index < spans.len) {
        const span = spans[span_index];
        var shaping_end_index = span_index + 1;
        while (shaping_end_index < spans.len and
            shapeEquivalent(span, spans[shaping_end_index]))
        {
            shaping_end_index += 1;
        }
        const span_end = spans[shaping_end_index - 1].byteEnd();
        while (script_index < script_runs.len and
            script_runs[script_index].byte_start +
                script_runs[script_index].byte_len <= span.byte_start)
        {
            script_index += 1;
        }
        var item_script_index = script_index;
        while (item_script_index < script_runs.len) : (item_script_index += 1) {
            const script_run = script_runs[item_script_index];
            const script_end = script_run.byte_start + script_run.byte_len;
            if (script_run.byte_start >= span_end) break;
            const item_start = @max(span.byte_start, script_run.byte_start);
            const item_end = @min(span_end, script_end);
            if (item_start >= item_end) continue;
            try context.shapeItem(item_start, item_end, script_run.script, span);
        }
        span_index = shaping_end_index;
    }
}

pub fn validatePartition(text: []const u8, spans: []const Span) !void {
    if (text.len == 0) {
        if (spans.len != 0) return error.InvalidStyleSpans;
        return;
    }
    if (spans.len == 0) return error.InvalidStyleSpans;
    var expected_start: usize = 0;
    for (spans) |span| {
        if (span.byte_start != expected_start or span.byte_len == 0) {
            return error.InvalidStyleSpans;
        }
        if (span.byte_start > text.len or
            span.byte_len > text.len - span.byte_start or
            !isUtf8Boundary(text, span.byte_start) or
            !isUtf8Boundary(text, span.byteEnd()))
        {
            return error.InvalidStyleSpans;
        }
        expected_start = span.byteEnd();
    }
    if (expected_start != text.len) return error.InvalidStyleSpans;
}

pub fn spanForCluster(spans: []const Span, cluster: usize) ?Span {
    // Visual bidi order is not monotone in source clusters. Binary search the
    // canonical logical partition rather than carrying a forward-only cursor.
    var low: usize = 0;
    var high: usize = spans.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (spans[mid].byteEnd() <= cluster) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low >= spans.len) return null;
    const span = spans[low];
    if (cluster < span.byte_start or cluster >= span.byteEnd()) return null;
    return span;
}

pub fn shapeEquivalent(a: Span, b: Span) bool {
    if (a.byteEnd() != b.byte_start or
        a.font_size != b.font_size or
        !optionalFontSlicesEqual(a.faces, b.faces) or
        a.script_tag != b.script_tag or
        a.language_tag != b.language_tag or
        !featureSlicesEqual(a.features, b.features) or
        a.normalized_variation_coords.len != b.normalized_variation_coords.len)
    {
        return false;
    }
    for (a.normalized_variation_coords, b.normalized_variation_coords) |lhs, rhs| {
        if (@as(u32, @bitCast(lhs)) != @as(u32, @bitCast(rhs))) return false;
    }
    return true;
}

/// Resolve paragraph and attributed range policy into canonical intervals.
///
/// `spans` is an exact source partition. Paragraph-authored ranges may split a
/// span, while each span overrides only its non-null fields. Adjacent equal
/// intervals are merged and paragraph-default intervals are omitted.
pub fn resolveLineBreakPolicyRanges(
    allocator: std.mem.Allocator,
    text_len: usize,
    spans: []const Span,
    options: paragraph_options.Options,
) ![]line_break_policy.Range {
    var boundaries = std.ArrayList(usize).empty;
    defer boundaries.deinit(allocator);
    try boundaries.ensureTotalCapacity(
        allocator,
        2 + spans.len * 2 + options.line_break_policy_ranges.len * 2,
    );
    boundaries.appendAssumeCapacity(0);
    boundaries.appendAssumeCapacity(text_len);
    for (spans) |span| {
        boundaries.appendAssumeCapacity(span.byte_start);
        boundaries.appendAssumeCapacity(span.byteEnd());
    }
    for (options.line_break_policy_ranges) |range| {
        boundaries.appendAssumeCapacity(range.byte_start);
        boundaries.appendAssumeCapacity(range.byteEnd());
    }
    std.mem.sort(usize, boundaries.items, {}, lessThanUsize);
    boundaries.shrinkRetainingCapacity(uniqueSorted(boundaries.items));

    const defaults = paragraph_options.defaultLineBreakPolicy(options);
    var output = std.ArrayList(line_break_policy.Range).empty;
    errdefer output.deinit(allocator);
    for (boundaries.items[0 .. boundaries.items.len - 1], boundaries.items[1..]) |
        start,
        end,
    | {
        if (start >= end or start >= text_len) continue;
        var policy = line_break_policy.atByte(
            defaults,
            options.line_break_policy_ranges,
            start,
        );
        const span = spanForCluster(spans, start) orelse
            return error.InvalidStyleSpans;
        policy.wrap_mode = span.wrap_mode orelse policy.wrap_mode;
        policy.word_break = span.word_break orelse policy.word_break;
        policy.overflow_wrap =
            span.overflow_wrap orelse policy.overflow_wrap;
        if (policy.eql(defaults)) continue;

        if (output.items.len != 0) {
            const previous = &output.items[output.items.len - 1];
            if (previous.byteEnd() == start and
                previous.wrap_mode.? == policy.wrap_mode and
                previous.word_break.? == policy.word_break and
                previous.overflow_wrap.? == policy.overflow_wrap)
            {
                previous.byte_len += end - start;
                continue;
            }
        }
        try output.append(allocator, .{
            .byte_start = start,
            .byte_len = end - start,
            .wrap_mode = policy.wrap_mode,
            .word_break = policy.word_break,
            .overflow_wrap = policy.overflow_wrap,
        });
    }
    return output.toOwnedSlice(allocator);
}

fn optionalFontSlicesEqual(
    a: ?[]const *const face_mod.Face,
    b: ?[]const *const face_mod.Face,
) bool {
    if ((a == null) != (b == null)) return false;
    const lhs = a orelse return true;
    const rhs = b.?;
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |lhs_font, rhs_font| {
        if (lhs_font != rhs_font) return false;
    }
    return true;
}

fn featureSlicesEqual(
    a: []const unicode.FeatureOverride,
    b: []const unicode.FeatureOverride,
) bool {
    if (a.len != b.len) return false;
    for (a, b) |lhs, rhs| {
        if (lhs.tag != rhs.tag or
            lhs.enabled != rhs.enabled or
            lhs.value != rhs.value)
        {
            return false;
        }
    }
    return true;
}

fn isUtf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset > text.len) return false;
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0xc0) != 0x80;
}

fn lessThanUsize(_: void, lhs: usize, rhs: usize) bool {
    return lhs < rhs;
}

fn uniqueSorted(values: []usize) usize {
    if (values.len == 0) return 0;
    var write: usize = 1;
    for (values[1..]) |value| {
        if (value == values[write - 1]) continue;
        values[write] = value;
        write += 1;
    }
    return write;
}

test "styled spans distinguish shaping from paint geometry" {
    const a = Span{
        .byte_start = 0,
        .byte_len = 1,
        .style_index = 0,
        .font_size = 16,
        .letter_spacing = 1,
    };
    var b = a;
    b.byte_start = 1;
    b.style_index = 1;
    b.letter_spacing = 9;
    b.vertical_align = .top;
    b.wrap_mode = .no_wrap;
    b.word_break = .break_all;
    b.overflow_wrap = .normal;
    try std.testing.expect(shapeEquivalent(a, b));

    b.font_size = 17;
    try std.testing.expect(!shapeEquivalent(a, b));
}

test "styled span lookup handles visual cluster order" {
    const spans = [_]Span{
        .{ .byte_start = 0, .byte_len = 2, .style_index = 4, .font_size = 16 },
        .{ .byte_start = 2, .byte_len = 4, .style_index = 7, .font_size = 16 },
    };
    try std.testing.expectEqual(@as(u32, 7), spanForCluster(&spans, 4).?.style_index);
    try std.testing.expectEqual(@as(u32, 4), spanForCluster(&spans, 0).?.style_index);
    try std.testing.expect(spanForCluster(&spans, 6) == null);
}

test "styled line policy overrides merge independently with paragraph ranges" {
    const spans = [_]Span{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 0,
            .font_size = 16,
            .word_break = .break_all,
        },
        .{
            .byte_start = 2,
            .byte_len = 2,
            .style_index = 1,
            .font_size = 16,
        },
    };
    const options = paragraph_options.Options{
        .max_width = 20,
        .line_break_policy_ranges = &.{.{
            .byte_start = 0,
            .byte_len = 4,
            .wrap_mode = .no_wrap,
        }},
    };
    const ranges = try resolveLineBreakPolicyRanges(
        std.testing.allocator,
        4,
        &spans,
        options,
    );
    defer std.testing.allocator.free(ranges);

    try std.testing.expectEqual(@as(usize, 2), ranges.len);
    try std.testing.expectEqual(@as(usize, 0), ranges[0].byte_start);
    try std.testing.expectEqual(@as(usize, 2), ranges[0].byte_len);
    try std.testing.expectEqual(
        @import("types/paragraph.zig").WrapMode.no_wrap,
        ranges[0].wrap_mode.?,
    );
    try std.testing.expectEqual(
        @import("types/paragraph.zig").WordBreak.break_all,
        ranges[0].word_break.?,
    );
    try std.testing.expectEqual(@as(usize, 2), ranges[1].byte_start);
    try std.testing.expectEqual(@as(usize, 2), ranges[1].byte_len);
    try std.testing.expectEqual(
        @import("types/paragraph.zig").WrapMode.no_wrap,
        ranges[1].wrap_mode.?,
    );
    try std.testing.expectEqual(
        @import("types/paragraph.zig").WordBreak.normal,
        ranges[1].word_break.?,
    );
}
