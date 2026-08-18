const std = @import("std");
const face_mod = @import("../font/face/root.zig");
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
    /// cascade; a non-null slice is owned by the caller for the layout call.
    faces: ?[]const *const face_mod.Face = null,
    script_tag: ?unicode.OpenTypeScriptTag = null,
    language_tag: ?unicode.OpenTypeLanguageTag = null,
    features: []const unicode.FeatureOverride = &.{},
    normalized_variation_coords: []const f32 = &.{},
    letter_spacing: f32 = 0,
    word_spacing: f32 = 0,
    minimum_line_height: ?f32 = null,
    vertical_align: @import("types/paragraph.zig").VerticalAlign = .baseline,

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
    try context.finish(spans);
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
