//! Borrowed logical context for nested shaping items.
//!
//! Script, bidi, style, and fallback segmentation all carve subranges from one
//! source request. Keeping that root plus byte bounds avoids materializing an
//! ever-growing prefix and suffix for each child. Arabic joining additionally
//! gets nearest-neighbor summaries computed once for the whole request.

const std = @import("std");

const pipeline_types = @import("../pipeline/types.zig");
const unicode = @import("../../unicode.zig");

pub const Prepared = struct {
    allocator: std.mem.Allocator,
    view: pipeline_types.LogicalContext,
    owned_before: ?[]?unicode.JoiningType = null,
    owned_after: ?[]?unicode.JoiningType = null,

    pub fn init(
        allocator: std.mem.Allocator,
        external_before: []const u8,
        text: []const u8,
        external_after: []const u8,
        summarize_joining_boundaries: bool,
    ) !Prepared {
        var result = Prepared{
            .allocator = allocator,
            .view = .{
                .external_before = external_before,
                .text = text,
                .external_after = external_after,
                .active_end = text.len,
            },
        };
        errdefer result.deinit();

        // Ordinary Latin/UI text never enters the Arabic-family joining
        // shaper, so it should not pay for two byte-indexed sidecars.
        if (!summarize_joining_boundaries or
            !hasJoiningRelevantScalar(text)) return result;

        const before = try allocator.alloc(?unicode.JoiningType, text.len + 1);
        result.owned_before = before;
        @memset(before, null);
        const after = try allocator.alloc(?unicode.JoiningType, text.len + 1);
        result.owned_after = after;
        @memset(after, null);

        const external_previous = lastNonTransparent(external_before);
        const external_next = firstNonTransparent(external_after);
        fillJoiningBoundaries(
            text,
            before,
            after,
            external_previous,
            external_next,
        );

        result.view.joining_before = before;
        result.view.joining_after = after;
        result.view.external_joining_before = external_previous;
        result.view.external_joining_after = external_next;
        return result;
    }

    /// Construct a non-owning view over cache-owned joining summaries. The
    /// caller must keep the cache entry stable until this value is deinitialized
    /// or otherwise discarded. Empty summary slices mean that no summaries
    /// were requested, exactly like the allocation-free branch of `init`.
    pub fn initBorrowed(
        allocator: std.mem.Allocator,
        external_before: []const u8,
        text: []const u8,
        external_after: []const u8,
        joining_before: []const ?unicode.JoiningType,
        joining_after: []const ?unicode.JoiningType,
    ) Prepared {
        std.debug.assert(joining_before.len == joining_after.len);
        std.debug.assert(
            joining_before.len == 0 or joining_before.len == text.len + 1,
        );
        return .{
            .allocator = allocator,
            .view = .{
                .external_before = external_before,
                .text = text,
                .external_after = external_after,
                .active_end = text.len,
                .joining_before = if (joining_before.len == 0)
                    null
                else
                    joining_before,
                .joining_after = if (joining_after.len == 0)
                    null
                else
                    joining_after,
                // Cached arrays are intrinsic to `text`. The accessors overlay
                // these request-specific neighbors only where the intrinsic
                // prefix or suffix has no non-transparent scalar.
                .external_joining_before = lastNonTransparent(external_before),
                .external_joining_after = firstNonTransparent(external_after),
            },
        };
    }

    pub fn deinit(self: *Prepared) void {
        if (self.owned_after) |items| self.allocator.free(items);
        if (self.owned_before) |items| self.allocator.free(items);
        self.* = undefined;
    }
};

pub fn needsJoiningSummary(
    text: []const u8,
    cascade: @import("../fallback/font/root.zig").Cascade,
) bool {
    if (cascade.fonts.len <= 1 or !hasJoiningRelevantScalar(text)) {
        return false;
    }
    var graphemes = unicode.graphemeClustersAssumeValid(text);
    const first = graphemes.next() orelse return false;
    const first_end = first.byte_start + first.byte_len;
    const first_font = cascade.selectFontForCluster(
        text[first.byte_start..first_end],
    ) catch return true;
    while (graphemes.next()) |grapheme| {
        const end = grapheme.byte_start + grapheme.byte_len;
        const font_index = cascade.selectFontForCluster(
            text[grapheme.byte_start..end],
        ) catch return true;
        if (font_index != first_font) return true;
    }
    return false;
}

/// Narrow an already-resolved item without allocating context bytes. `start`
/// and `end` are relative to the parent's active range.
pub fn scopeResolved(
    parent: pipeline_types.ResolvedLookupOptions,
    start: usize,
    end: usize,
) pipeline_types.ResolvedLookupOptions {
    var result = parent;
    const context = parent.lookup.logical_context orelse {
        result.lookup.beginning_of_text =
            parent.lookup.beginning_of_text and start == 0;
        // Without a logical root this is the legacy flat-context path. The
        // caller supplies offsets relative to its current item, so only BOT
        // can be narrowed reliably; ordinary ASCII fallback does not consume
        // the internal joining context for which EOT would matter.
        if (start != 0) result.lookup.end_of_text = false;
        return result;
    };
    const parent_len = context.active_end - context.active_start;
    std.debug.assert(start <= end);
    std.debug.assert(end <= parent_len);
    result.lookup.logical_context = context.subrange(
        context.active_start + start,
        context.active_start + end,
    );
    result.lookup.beginning_of_text =
        parent.lookup.beginning_of_text and start == 0;
    result.lookup.end_of_text =
        parent.lookup.end_of_text and end == parent_len;
    return result;
}

pub fn hasJoiningRelevantScalar(text: []const u8) bool {
    var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (unicode.joiningTypeForCodepoint(codepoint) != .non_joining) {
            return true;
        }
    }
    return false;
}

/// Populate nearest-neighbor sidecars for a validated complete paragraph.
/// Cache owners use this after allocating their immutable destination arrays.
pub fn summarizeJoiningBoundaries(
    text: []const u8,
    before: []?unicode.JoiningType,
    after: []?unicode.JoiningType,
) void {
    fillJoiningBoundaries(text, before, after, null, null);
}

fn fillJoiningBoundaries(
    text: []const u8,
    before: []?unicode.JoiningType,
    after: []?unicode.JoiningType,
    external_previous: ?unicode.JoiningType,
    external_next: ?unicode.JoiningType,
) void {
    std.debug.assert(before.len == text.len + 1);
    std.debug.assert(after.len == text.len + 1);

    var previous = external_previous;
    var cursor: usize = 0;
    while (cursor < text.len) {
        before[cursor] = previous;
        const decoded = decodeValid(text, cursor);
        cursor = decoded.next;
        const kind = unicode.joiningTypeForCodepoint(decoded.codepoint);
        if (kind != .transparent) previous = kind;
    }
    before[text.len] = previous;

    var next = external_next;
    after[text.len] = next;
    cursor = text.len;
    while (cursor != 0) {
        const start = previousScalarStart(text, cursor);
        const decoded = decodeValid(text, start);
        const kind = unicode.joiningTypeForCodepoint(decoded.codepoint);
        if (kind != .transparent) next = kind;
        after[start] = next;
        cursor = start;
    }
}

fn firstNonTransparent(text: []const u8) ?unicode.JoiningType {
    var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        const kind = unicode.joiningTypeForCodepoint(codepoint);
        if (kind != .transparent) return kind;
    }
    return null;
}

fn lastNonTransparent(text: []const u8) ?unicode.JoiningType {
    var result: ?unicode.JoiningType = null;
    var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        const kind = unicode.joiningTypeForCodepoint(codepoint);
        if (kind != .transparent) result = kind;
    }
    return result;
}

fn previousScalarStart(text: []const u8, end: usize) usize {
    var start = end - 1;
    while (start != 0 and text[start] & 0xc0 == 0x80) start -= 1;
    return start;
}

const Decoded = struct { codepoint: u21, next: usize };

fn decodeValid(text: []const u8, start: usize) Decoded {
    const sequence_len = std.unicode.utf8ByteSequenceLength(text[start]) catch
        unreachable;
    const end = start + sequence_len;
    return .{
        .codepoint = std.unicode.utf8Decode(text[start..end]) catch unreachable,
        .next = end,
    };
}

test "logical context summarizes joining neighbors at byte boundaries" {
    var prepared = try Prepared.init(
        std.testing.allocator,
        "ب",
        "بَت",
        "ب",
        true,
    );
    defer prepared.deinit();
    const middle = prepared.view.subrange(2, 4);
    try std.testing.expectEqual(
        unicode.JoiningType.dual,
        middle.joiningBefore().?,
    );
    try std.testing.expectEqual(
        unicode.JoiningType.dual,
        middle.joiningAfter().?,
    );
}

test "borrowed intrinsic summaries overlay alternating external context" {
    const text = "َبَ";
    var before: [text.len + 1]?unicode.JoiningType = undefined;
    var after: [text.len + 1]?unicode.JoiningType = undefined;
    @memset(&before, null);
    @memset(&after, null);
    summarizeJoiningBoundaries(text, &before, &after);

    var left = Prepared.initBorrowed(
        std.testing.allocator,
        "ت",
        text,
        "ا",
        &before,
        &after,
    );
    defer left.deinit();
    try std.testing.expectEqual(
        unicode.JoiningType.dual,
        left.view.subrange(0, "َ".len).joiningBefore().?,
    );
    try std.testing.expectEqual(
        unicode.JoiningType.dual,
        left.view.subrange("َب".len, text.len).joiningBefore().?,
    );
    try std.testing.expectEqual(
        unicode.JoiningType.right,
        left.view.subrange("َب".len, text.len).joiningAfter().?,
    );

    var changed = Prepared.initBorrowed(
        std.testing.allocator,
        "ا",
        text,
        "ت",
        &before,
        &after,
    );
    defer changed.deinit();
    try std.testing.expectEqual(
        unicode.JoiningType.right,
        changed.view.subrange(0, "َ".len).joiningBefore().?,
    );
    try std.testing.expectEqual(
        unicode.JoiningType.dual,
        changed.view.subrange("َب".len, text.len).joiningAfter().?,
    );

    var owned_left = try Prepared.init(
        std.testing.allocator,
        "ت",
        text,
        "ا",
        true,
    );
    defer owned_left.deinit();
    var owned_changed = try Prepared.init(
        std.testing.allocator,
        "ا",
        text,
        "ت",
        true,
    );
    defer owned_changed.deinit();
    for ([_]usize{ 0, "َ".len, "َب".len, text.len }) |boundary| {
        const left_scope = left.view.subrange(boundary, boundary);
        const owned_left_scope = owned_left.view.subrange(boundary, boundary);
        try std.testing.expectEqual(
            owned_left_scope.joiningBefore(),
            left_scope.joiningBefore(),
        );
        try std.testing.expectEqual(
            owned_left_scope.joiningAfter(),
            left_scope.joiningAfter(),
        );

        const changed_scope = changed.view.subrange(boundary, boundary);
        const owned_changed_scope = owned_changed.view.subrange(boundary, boundary);
        try std.testing.expectEqual(
            owned_changed_scope.joiningBefore(),
            changed_scope.joiningBefore(),
        );
        try std.testing.expectEqual(
            owned_changed_scope.joiningAfter(),
            changed_scope.joiningAfter(),
        );
    }
}
