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

        result.view.joining_before = before;
        result.view.joining_after = after;
        result.view.external_joining_before = external_previous;
        result.view.external_joining_after = external_next;
        return result;
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

fn hasJoiningRelevantScalar(text: []const u8) bool {
    var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (unicode.joiningTypeForCodepoint(codepoint) != .non_joining) {
            return true;
        }
    }
    return false;
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
