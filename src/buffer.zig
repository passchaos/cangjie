const std = @import("std");
const Font = @import("font.zig").Font;
const layout = @import("layout.zig");
const unicode = @import("unicode.zig");

pub const DirtyRange = struct {
    byte_start: usize,
    byte_end: usize,

    pub fn empty() DirtyRange {
        return .{ .byte_start = 0, .byte_end = 0 };
    }

    pub fn isEmpty(self: DirtyRange) bool {
        return self.byte_start == self.byte_end;
    }
};

pub const Selection = struct {
    anchor_byte: usize,
    focus_byte: usize,

    pub fn collapsed(byte_offset: usize) Selection {
        return .{ .anchor_byte = byte_offset, .focus_byte = byte_offset };
    }

    pub fn isCollapsed(self: Selection) bool {
        return self.anchor_byte == self.focus_byte;
    }

    pub fn start(self: Selection) usize {
        return @min(self.anchor_byte, self.focus_byte);
    }

    pub fn end(self: Selection) usize {
        return @max(self.anchor_byte, self.focus_byte);
    }
};

pub const LayoutConfig = struct {
    cascade: layout.FontCascade,
    font_size: f32,
    paragraph: layout.ParagraphOptions,
};

pub const CursorMoveDirection = enum {
    previous,
    next,
};

pub const VisibleLineRange = struct {
    start_line: usize,
    end_line: usize,

    pub fn isEmpty(self: VisibleLineRange) bool {
        return self.start_line == self.end_line;
    }
};

pub const VisibleByteRange = struct {
    byte_start: usize,
    byte_end: usize,

    pub fn isEmpty(self: VisibleByteRange) bool {
        return self.byte_start == self.byte_end;
    }
};

pub const TextBuffer = struct {
    allocator: std.mem.Allocator,
    text: std.ArrayList(u8) = .empty,
    layout_buffer: layout.LayoutBuffer,
    cursor_byte: usize = 0,
    selection: Selection = Selection.collapsed(0),
    dirty_range: DirtyRange = DirtyRange.empty(),
    layout_valid: bool = false,
    preferred_cursor_x: ?f32 = null,
    scroll_y: f32 = 0,
    grapheme_cache: std.ArrayList(unicode.GraphemeCluster) = .empty,
    word_cache: std.ArrayList(unicode.WordSegment) = .empty,

    pub fn init(allocator: std.mem.Allocator) TextBuffer {
        return .{
            .allocator = allocator,
            .layout_buffer = layout.LayoutBuffer.init(allocator),
        };
    }

    pub fn initText(allocator: std.mem.Allocator, text: []const u8) !TextBuffer {
        var buffer = TextBuffer.init(allocator);
        errdefer buffer.deinit();
        try buffer.setText(text);
        return buffer;
    }

    pub fn deinit(self: *TextBuffer) void {
        self.word_cache.deinit(self.allocator);
        self.grapheme_cache.deinit(self.allocator);
        self.layout_buffer.deinit();
        self.text.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn slice(self: *const TextBuffer) []const u8 {
        return self.text.items;
    }

    pub fn setText(self: *TextBuffer, text: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(self.allocator, text);
        self.cursor_byte = self.text.items.len;
        self.selection = Selection.collapsed(self.cursor_byte);
        self.preferred_cursor_x = null;
        self.scroll_y = 0;
        self.markDirty(0, self.text.items.len);
    }

    pub fn insertText(self: *TextBuffer, byte_offset: usize, text: []const u8) !void {
        try self.replaceRange(byte_offset, byte_offset, text);
    }

    pub fn insertAtCursor(self: *TextBuffer, text: []const u8) !void {
        const range = self.selectionRange();
        try self.replaceRange(range.start, range.end, text);
    }

    pub fn deleteRange(self: *TextBuffer, start_byte: usize, end_byte: usize) !void {
        try self.replaceRange(start_byte, end_byte, "");
    }

    pub fn replaceRange(self: *TextBuffer, start_byte: usize, end_byte: usize, replacement: []const u8) !void {
        const range = try self.checkedRange(start_byte, end_byte);
        if (!std.unicode.utf8ValidateSlice(replacement)) return error.InvalidUtf8;
        const old_len = range.end - range.start;
        try self.text.replaceRange(self.allocator, range.start, old_len, replacement);
        const new_cursor = range.start + replacement.len;
        self.cursor_byte = new_cursor;
        self.selection = Selection.collapsed(new_cursor);
        self.preferred_cursor_x = null;
        const dirty = dirtyRangeAfterReplace(range.start, range.end, replacement.len, self.text.items.len);
        self.markDirty(dirty.start, dirty.end);
    }

    pub fn deleteBackward(self: *TextBuffer) !void {
        if (!self.selection.isCollapsed()) {
            const range = self.selectionRange();
            return self.deleteRange(range.start, range.end);
        }
        const previous = try self.previousGraphemeByte(self.cursor_byte);
        if (previous == self.cursor_byte) return;
        try self.deleteRange(previous, self.cursor_byte);
    }

    pub fn deleteForward(self: *TextBuffer) !void {
        if (!self.selection.isCollapsed()) {
            const range = self.selectionRange();
            return self.deleteRange(range.start, range.end);
        }
        const next = try self.nextGraphemeByte(self.cursor_byte);
        if (next == self.cursor_byte) return;
        try self.deleteRange(self.cursor_byte, next);
    }

    pub fn setCursor(self: *TextBuffer, byte_offset: usize) !void {
        const offset = try self.checkedOffset(byte_offset);
        self.cursor_byte = offset;
        self.selection = Selection.collapsed(offset);
        self.preferred_cursor_x = null;
    }

    pub fn setSelection(self: *TextBuffer, anchor_byte: usize, focus_byte: usize) !void {
        const anchor = try self.checkedOffset(anchor_byte);
        const focus = try self.checkedOffset(focus_byte);
        self.selection = .{ .anchor_byte = anchor, .focus_byte = focus };
        self.cursor_byte = focus;
        self.preferred_cursor_x = null;
    }

    pub fn moveCursorGrapheme(self: *TextBuffer, direction: CursorMoveDirection, extend_selection: bool) !void {
        const anchor = if (extend_selection) self.selection.anchor_byte else self.cursor_byte;
        const next_byte = switch (direction) {
            .previous => try self.previousGraphemeByte(self.cursor_byte),
            .next => try self.nextGraphemeByte(self.cursor_byte),
        };
        self.cursor_byte = next_byte;
        self.preferred_cursor_x = null;
        self.selection = if (extend_selection)
            .{ .anchor_byte = anchor, .focus_byte = next_byte }
        else
            Selection.collapsed(next_byte);
    }

    pub fn moveCursorWord(self: *TextBuffer, direction: CursorMoveDirection, extend_selection: bool) !void {
        const anchor = if (extend_selection) self.selection.anchor_byte else self.cursor_byte;
        const next_byte = switch (direction) {
            .previous => try self.previousWordByte(self.cursor_byte),
            .next => try self.nextWordByte(self.cursor_byte),
        };
        self.cursor_byte = next_byte;
        self.preferred_cursor_x = null;
        self.selection = if (extend_selection)
            .{ .anchor_byte = anchor, .focus_byte = next_byte }
        else
            Selection.collapsed(next_byte);
    }

    pub fn moveCursorBidiVisual(self: *TextBuffer, base_direction: unicode.BidiClass, direction: CursorMoveDirection, extend_selection: bool) !void {
        const anchor = if (extend_selection) self.selection.anchor_byte else self.cursor_byte;
        const next_byte = try self.visualBidiByte(self.cursor_byte, base_direction, direction);
        self.cursor_byte = next_byte;
        self.preferred_cursor_x = null;
        self.selection = if (extend_selection)
            .{ .anchor_byte = anchor, .focus_byte = next_byte }
        else
            Selection.collapsed(next_byte);
    }

    pub fn moveCursorVertical(self: *TextBuffer, config: LayoutConfig, direction: CursorMoveDirection, extend_selection: bool) !void {
        const paragraph = try self.ensureLayout(config);
        if (paragraph.lines.len == 0) return;
        const anchor = if (extend_selection) self.selection.anchor_byte else self.cursor_byte;
        const current_rect = paragraph.caretRect(paragraphPositionForByte(paragraph, self.cursor_byte));
        const target_x = self.preferred_cursor_x orelse current_rect.x;
        self.preferred_cursor_x = target_x;
        const line_index = lineIndexForY(paragraph, current_rect.y);
        const target_line_index = switch (direction) {
            .previous => if (line_index == 0) 0 else line_index - 1,
            .next => if (line_index + 1 >= paragraph.lines.len) paragraph.lines.len - 1 else line_index + 1,
        };
        const target_line = paragraph.lines[target_line_index];
        const target = paragraph.hitTest(target_x, target_line.y + target_line.height / 2);
        self.cursor_byte = textPositionByteOffset(paragraph, target);
        self.selection = if (extend_selection)
            .{ .anchor_byte = anchor, .focus_byte = self.cursor_byte }
        else
            Selection.collapsed(self.cursor_byte);
    }

    pub fn ensureLayout(self: *TextBuffer, config: LayoutConfig) !layout.ParagraphLayout {
        if (!self.layout_valid) {
            _ = try layout.TextShaper.layoutParagraphUtf8(config.cascade, &self.layout_buffer, self.text.items, config.font_size, config.paragraph);
            self.layout_valid = true;
            self.dirty_range = DirtyRange.empty();
        }
        return self.layout_buffer.paragraphLayout();
    }

    pub fn hitTest(self: *TextBuffer, config: LayoutConfig, x: f32, y: f32) !layout.TextPosition {
        const paragraph = try self.ensureLayout(config);
        return paragraph.hitTest(x, y);
    }

    pub fn cursorRect(self: *TextBuffer, config: LayoutConfig) !layout.TextRect {
        const paragraph = try self.ensureLayout(config);
        return paragraph.caretRect(paragraphPositionForByte(paragraph, self.cursor_byte));
    }

    pub fn selectionRects(self: *TextBuffer, allocator: std.mem.Allocator, config: LayoutConfig) ![]layout.TextRect {
        if (self.selection.isCollapsed()) return try allocator.alloc(layout.TextRect, 0);
        const paragraph = try self.ensureLayout(config);
        const start_pos = paragraphPositionForByte(paragraph, self.selection.start());
        const end_pos = paragraphPositionForByte(paragraph, self.selection.end());
        return try paragraph.selectionRects(allocator, start_pos.glyph_index, end_pos.glyph_index + @intFromBool(end_pos.trailing));
    }

    pub fn selectionRectsBidiVisual(self: *TextBuffer, allocator: std.mem.Allocator, config: LayoutConfig, base_direction: unicode.BidiClass) ![]layout.TextRect {
        if (self.selection.isCollapsed()) return try allocator.alloc(layout.TextRect, 0);
        const paragraph = try self.ensureLayout(config);
        var bidi_map = try unicode.buildBidiMap(allocator, self.text.items, base_direction);
        defer bidi_map.deinit();

        var rects = std.ArrayList(layout.TextRect).empty;
        errdefer rects.deinit(allocator);
        const range_start = self.selection.start();
        const range_end = self.selection.end();
        for (bidi_map.items) |item| {
            const item_end = item.byte_start + item.byte_len;
            if (item_end <= range_start or item.byte_start >= range_end) continue;
            try rects.append(allocator, rectForByteRange(paragraph, item.byte_start, item_end));
        }
        return try rects.toOwnedSlice(allocator);
    }

    pub fn setScrollY(self: *TextBuffer, scroll_y: f32) void {
        self.scroll_y = @max(0, scroll_y);
    }

    pub fn visibleLineRange(self: *TextBuffer, config: LayoutConfig, viewport_height: f32) !VisibleLineRange {
        const paragraph = try self.ensureLayout(config);
        if (paragraph.lines.len == 0 or viewport_height <= 0) return .{ .start_line = 0, .end_line = 0 };
        const view_start = self.scroll_y;
        const view_end = self.scroll_y + viewport_height;
        var start: ?usize = null;
        var end: usize = 0;
        for (paragraph.lines, 0..) |line, index| {
            const line_end = line.y + line.height;
            if (line_end <= view_start or line.y >= view_end) continue;
            if (start == null) start = index;
            end = index + 1;
        }
        const actual_start = start orelse paragraph.lines.len;
        return .{ .start_line = actual_start, .end_line = end };
    }

    pub fn visibleByteRange(self: *TextBuffer, config: LayoutConfig, viewport_height: f32) !VisibleByteRange {
        const paragraph = try self.ensureLayout(config);
        const lines = try self.visibleLineRange(config, viewport_height);
        if (lines.isEmpty()) return .{ .byte_start = self.text.items.len, .byte_end = self.text.items.len };
        const start_line = paragraph.lines[lines.start_line];
        const end_line = paragraph.lines[lines.end_line - 1];
        return .{
            .byte_start = lineStartByte(paragraph, start_line),
            .byte_end = lineEndByte(paragraph, end_line, self.text.items.len),
        };
    }

    pub fn dirtyIntersectsVisible(self: *TextBuffer, config: LayoutConfig, viewport_height: f32) !bool {
        const dirty = self.dirty_range;
        if (dirty.isEmpty()) return !self.layout_valid;
        const visible = try self.visibleByteRange(config, viewport_height);
        if (visible.isEmpty()) return !self.layout_valid;
        return dirty.byte_start < visible.byte_end and dirty.byte_end > visible.byte_start;
    }

    pub fn scrollCursorIntoView(self: *TextBuffer, config: LayoutConfig, viewport_height: f32) !void {
        if (viewport_height <= 0) return;
        const cursor = try self.cursorRect(config);
        if (cursor.y < self.scroll_y) {
            self.scroll_y = @max(0, cursor.y);
        } else if (cursor.y + cursor.height > self.scroll_y + viewport_height) {
            self.scroll_y = @max(0, cursor.y + cursor.height - viewport_height);
        }
    }

    pub fn dirtyRange(self: *const TextBuffer) DirtyRange {
        return self.dirty_range;
    }

    fn selectionRange(self: *const TextBuffer) struct { start: usize, end: usize } {
        return .{ .start = self.selection.start(), .end = self.selection.end() };
    }

    fn dirtyRangeAfterReplace(start: usize, old_end: usize, replacement_len: usize, new_text_len: usize) struct { start: usize, end: usize } {
        const inserted_end = start + replacement_len;
        const surviving_old_end = @min(old_end, new_text_len);
        const dirty_end = @max(inserted_end, surviving_old_end);
        if (dirty_end == start and old_end > start and start > 0) {
            // Deleting the final byte range leaves no byte after the edit to
            // mark dirty. Expand left so viewport invalidation still observes a
            // non-empty range on the affected line. The range is only used for
            // intersection checks; it need not describe a UTF-8 scalar boundary.
            return .{ .start = start - 1, .end = start };
        }
        return .{ .start = start, .end = dirty_end };
    }

    fn markDirty(self: *TextBuffer, start_byte: usize, end_byte: usize) void {
        const start = @min(start_byte, self.text.items.len);
        const end = @min(@max(start_byte, end_byte), self.text.items.len);
        if (self.dirty_range.isEmpty()) {
            self.dirty_range = .{ .byte_start = start, .byte_end = end };
        } else {
            self.dirty_range = .{
                .byte_start = @min(self.dirty_range.byte_start, start),
                .byte_end = @max(self.dirty_range.byte_end, end),
            };
        }
        self.layout_valid = false;
        self.grapheme_cache.clearRetainingCapacity();
        self.word_cache.clearRetainingCapacity();
    }

    fn checkedRange(self: *const TextBuffer, start_byte: usize, end_byte: usize) !struct { start: usize, end: usize } {
        if (start_byte > end_byte) return error.InvalidRange;
        _ = try self.checkedOffset(start_byte);
        _ = try self.checkedOffset(end_byte);
        return .{ .start = start_byte, .end = end_byte };
    }

    fn checkedOffset(self: *const TextBuffer, byte_offset: usize) !usize {
        if (byte_offset > self.text.items.len) return error.InvalidRange;
        if (!isUtf8Boundary(self.text.items, byte_offset)) return error.InvalidUtf8Boundary;
        return byte_offset;
    }

    fn ensureGraphemes(self: *TextBuffer) ![]const unicode.GraphemeCluster {
        if (self.grapheme_cache.items.len == 0 and self.text.items.len > 0) {
            const clusters = try unicode.itemizeGraphemeClusters(self.allocator, self.text.items);
            defer self.allocator.free(clusters);
            try self.grapheme_cache.appendSlice(self.allocator, clusters);
        }
        return self.grapheme_cache.items;
    }

    fn ensureWords(self: *TextBuffer) ![]const unicode.WordSegment {
        if (self.word_cache.items.len == 0 and self.text.items.len > 0) {
            const words = try unicode.itemizeWordSegments(self.allocator, self.text.items);
            defer self.allocator.free(words);
            try self.word_cache.appendSlice(self.allocator, words);
        }
        return self.word_cache.items;
    }

    fn previousGraphemeByte(self: *TextBuffer, byte_offset: usize) !usize {
        const offset = try self.checkedOffset(byte_offset);
        const clusters = try self.ensureGraphemes();
        var previous: usize = 0;
        for (clusters) |cluster| {
            if (cluster.byte_start >= offset) return previous;
            previous = cluster.byte_start;
        }
        return previous;
    }

    fn nextGraphemeByte(self: *TextBuffer, byte_offset: usize) !usize {
        const offset = try self.checkedOffset(byte_offset);
        const clusters = try self.ensureGraphemes();
        for (clusters) |cluster| {
            const end = cluster.byte_start + cluster.byte_len;
            if (end > offset) return end;
        }
        return self.text.items.len;
    }

    fn previousWordByte(self: *TextBuffer, byte_offset: usize) !usize {
        const offset = try self.checkedOffset(byte_offset);
        const words = try self.ensureWords();
        var previous: usize = 0;
        for (words) |word| {
            if (word.byte_start >= offset) return previous;
            previous = word.byte_start;
        }
        return previous;
    }

    fn nextWordByte(self: *TextBuffer, byte_offset: usize) !usize {
        const offset = try self.checkedOffset(byte_offset);
        const words = try self.ensureWords();
        for (words) |word| {
            const end = word.byte_start + word.byte_len;
            if (end > offset) return end;
        }
        return self.text.items.len;
    }

    fn visualBidiByte(self: *TextBuffer, byte_offset: usize, base_direction: unicode.BidiClass, direction: CursorMoveDirection) !usize {
        const offset = try self.checkedOffset(byte_offset);
        if (self.text.items.len == 0) return 0;

        var bidi_map = try unicode.buildBidiMap(self.allocator, self.text.items, base_direction);
        defer bidi_map.deinit();
        if (bidi_map.items.len == 0) return 0;

        const visual_index = visualIndexForByte(bidi_map, offset);
        const next_visual = switch (direction) {
            .previous => if (visual_index == 0) return bidi_map.items[0].byte_start else visual_index - 1,
            .next => if (visual_index >= bidi_map.items.len) return self.text.items.len else if (visual_index + 1 >= bidi_map.items.len) return self.text.items.len else visual_index + 1,
        };
        return bidi_map.items[next_visual].byte_start;
    }
};

fn isUtf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0b1100_0000) != 0b1000_0000;
}

fn paragraphPositionForByte(paragraph: layout.ParagraphLayout, byte_offset: usize) layout.TextPosition {
    if (paragraph.glyphs.len == 0) return .{ .glyph_index = 0, .cluster = byte_offset };
    for (paragraph.glyphs, 0..) |glyph, index| {
        if (glyph.cluster == byte_offset) return .{ .glyph_index = index, .cluster = glyph.cluster };
        if (glyph.cluster > byte_offset) {
            if (index == 0) return .{ .glyph_index = 0, .cluster = glyph.cluster };
            return .{ .glyph_index = index - 1, .cluster = byte_offset, .trailing = true };
        }
    }
    return .{ .glyph_index = paragraph.glyphs.len - 1, .cluster = byte_offset, .trailing = true };
}

fn textPositionByteOffset(paragraph: layout.ParagraphLayout, position: layout.TextPosition) usize {
    if (paragraph.glyphs.len == 0) return position.cluster;
    if (position.glyph_index >= paragraph.glyphs.len) return position.cluster;
    const glyph = paragraph.glyphs[position.glyph_index];
    if (!position.trailing) return glyph.cluster;

    // A trailing caret can represent more than "one byte after cluster":
    // shaping folds variation selectors into their base glyph and GSUB can fold
    // several source scalars into one ligature glyph. Prefer the byte offset
    // carried by the TextPosition when it is already beyond the leading
    // cluster, and otherwise recover the shaped source extent. This keeps
    // vertical cursor movement from manufacturing invalid byte offsets at the
    // end of folded glyphs.
    if (position.cluster > glyph.cluster) return position.cluster;
    return glyphTrailingByteOffset(paragraph, position.glyph_index);
}

fn glyphTrailingByteOffset(paragraph: layout.ParagraphLayout, glyph_index: usize) usize {
    const glyph = paragraph.glyphs[glyph_index];
    if (glyph_index + 1 < paragraph.glyphs.len) {
        const next_cluster = paragraph.glyphs[glyph_index + 1].cluster;
        if (next_cluster > glyph.cluster) return next_cluster;
    }
    return glyph.cluster + @max(glyph.source_byte_len, 1);
}

fn lineIndexForY(paragraph: layout.ParagraphLayout, y: f32) usize {
    for (paragraph.lines, 0..) |line, index| {
        if (y >= line.y and y < line.y + line.height) return index;
    }
    return if (paragraph.lines.len == 0) 0 else paragraph.lines.len - 1;
}

fn lineStartByte(paragraph: layout.ParagraphLayout, line: layout.ParagraphLine) usize {
    if (line.glyph_len == 0 or line.glyph_start >= paragraph.glyphs.len) return 0;
    return paragraph.glyphs[line.glyph_start].cluster;
}

fn lineEndByte(paragraph: layout.ParagraphLayout, line: layout.ParagraphLine, text_len: usize) usize {
    if (line.glyph_len == 0) return lineStartByte(paragraph, line);
    const glyph_end = line.glyph_start + line.glyph_len;
    if (glyph_end < paragraph.glyphs.len) return paragraph.glyphs[glyph_end].cluster;
    return text_len;
}

fn rectForByteRange(paragraph: layout.ParagraphLayout, start_byte: usize, end_byte: usize) layout.TextRect {
    const start = paragraph.caretRect(paragraphPositionForByte(paragraph, start_byte));
    const end = paragraph.caretRect(paragraphPositionForByte(paragraph, end_byte));
    return .{
        .x = @min(start.x, end.x),
        .y = @min(start.y, end.y),
        .width = @abs(end.x - start.x),
        .height = @max(start.height, end.height),
    };
}

fn visualIndexForByte(bidi_map: unicode.BidiMap, byte_offset: usize) usize {
    if (byte_offset == 0) return 0;
    var nearest_visual: usize = bidi_map.items.len;
    var nearest_byte: usize = 0;
    for (bidi_map.items) |item| {
        if (item.byte_start == byte_offset) return item.visual_index;
        if (item.byte_start < byte_offset and item.byte_start >= nearest_byte) {
            nearest_byte = item.byte_start;
            nearest_visual = item.visual_index + 1;
        }
    }
    return nearest_visual;
}

test "TextBuffer edits UTF-8 text and tracks dirty byte ranges" {
    const allocator = std.testing.allocator;

    var buffer = try TextBuffer.initText(allocator, "A一");
    defer buffer.deinit();

    try std.testing.expectEqualStrings("A一", buffer.slice());
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor_byte);
    try std.testing.expectEqual(@as(usize, 0), buffer.dirtyRange().byte_start);
    try std.testing.expectEqual(@as(usize, 4), buffer.dirtyRange().byte_end);

    try buffer.insertText(1, "B");
    try std.testing.expectEqualStrings("AB一", buffer.slice());
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor_byte);
    try std.testing.expectEqual(@as(usize, 0), buffer.dirtyRange().byte_start);
    try std.testing.expectEqual(@as(usize, 4), buffer.dirtyRange().byte_end);

    try std.testing.expectError(error.InvalidUtf8Boundary, buffer.insertText(3, "X"));
    try std.testing.expectError(error.InvalidUtf8, buffer.insertText(0, "\xff"));

    try buffer.replaceRange(2, 5, "丁");
    try std.testing.expectEqualStrings("AB丁", buffer.slice());
    try std.testing.expectEqual(@as(usize, 5), buffer.cursor_byte);

    try buffer.deleteBackward();
    try std.testing.expectEqualStrings("AB", buffer.slice());
    try std.testing.expectEqual(@as(usize, 2), buffer.cursor_byte);
}

test "TextBuffer moves cursor by grapheme and word boundaries" {
    const allocator = std.testing.allocator;

    var buffer = try TextBuffer.initText(allocator, "A\u{0301} BC");
    defer buffer.deinit();

    try buffer.setCursor(0);
    try buffer.moveCursorGrapheme(.next, false);
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor_byte);
    try buffer.moveCursorGrapheme(.next, false);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor_byte);
    try buffer.moveCursorGrapheme(.previous, true);
    try std.testing.expectEqual(@as(usize, 3), buffer.cursor_byte);
    try std.testing.expectEqual(@as(usize, 4), buffer.selection.anchor_byte);
    try std.testing.expectEqual(@as(usize, 3), buffer.selection.focus_byte);

    try buffer.moveCursorWord(.next, false);
    try std.testing.expectEqual(@as(usize, 6), buffer.cursor_byte);
    try buffer.moveCursorWord(.previous, false);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor_byte);
    try buffer.moveCursorWord(.previous, false);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor_byte);
}

test "TextBuffer moves cursor visually across bidi text" {
    const allocator = std.testing.allocator;

    var ltr = try TextBuffer.initText(allocator, "abבגcd");
    defer ltr.deinit();

    try ltr.setCursor(0);
    try ltr.moveCursorBidiVisual(.ltr, .next, false);
    try std.testing.expectEqual(@as(usize, 1), ltr.cursor_byte);
    try ltr.moveCursorBidiVisual(.ltr, .next, false);
    try std.testing.expectEqual(@as(usize, 4), ltr.cursor_byte);
    try ltr.moveCursorBidiVisual(.ltr, .next, false);
    try std.testing.expectEqual(@as(usize, 2), ltr.cursor_byte);
    try ltr.moveCursorBidiVisual(.ltr, .next, false);
    try std.testing.expectEqual(@as(usize, 6), ltr.cursor_byte);
    try ltr.moveCursorBidiVisual(.ltr, .previous, true);
    try std.testing.expectEqual(@as(usize, 2), ltr.cursor_byte);
    try std.testing.expectEqual(@as(usize, 6), ltr.selection.anchor_byte);
    try std.testing.expectEqual(@as(usize, 2), ltr.selection.focus_byte);

    var rtl = try TextBuffer.initText(allocator, "abבגcd");
    defer rtl.deinit();

    try rtl.setCursor(6);
    try rtl.moveCursorBidiVisual(.rtl, .next, false);
    try std.testing.expectEqual(@as(usize, 7), rtl.cursor_byte);
    try rtl.moveCursorBidiVisual(.rtl, .next, false);
    try std.testing.expectEqual(@as(usize, 4), rtl.cursor_byte);
    try rtl.moveCursorBidiVisual(.rtl, .next, false);
    try std.testing.expectEqual(@as(usize, 2), rtl.cursor_byte);
    try rtl.moveCursorBidiVisual(.rtl, .next, false);
    try std.testing.expectEqual(@as(usize, 0), rtl.cursor_byte);
}

test "TextBuffer returns bidi visual selection rects" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const latin_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(latin_bytes);
    const hebrew_bytes = try test_font.buildSingleCodepointTtf(allocator, 0x05d0);
    defer allocator.free(hebrew_bytes);

    var latin = try Font.parse(allocator, latin_bytes);
    defer latin.deinit();
    var hebrew = try Font.parse(allocator, hebrew_bytes);
    defer hebrew.deinit();

    const fonts = [_]*const Font{ &latin, &hebrew };
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{
            .max_width = 200,
            .line_height = 24,
        },
    };

    var buffer = try TextBuffer.initText(allocator, "AאA");
    defer buffer.deinit();
    try buffer.setSelection(0, buffer.slice().len);

    const logical_rects = try buffer.selectionRects(allocator, config);
    defer allocator.free(logical_rects);
    try std.testing.expectEqual(@as(usize, 1), logical_rects.len);

    const visual_rects = try buffer.selectionRectsBidiVisual(allocator, config, .ltr);
    defer allocator.free(visual_rects);
    try std.testing.expectEqual(@as(usize, 3), visual_rects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), visual_rects[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), visual_rects[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), visual_rects[2].x, 0.001);

    try buffer.setCursor(0);
    try buffer.moveCursorBidiVisual(.ltr, .next, true);
    try buffer.moveCursorBidiVisual(.ltr, .next, true);
    const partial_rects = try buffer.selectionRectsBidiVisual(allocator, config, .ltr);
    defer allocator.free(partial_rects);
    try std.testing.expectEqual(@as(usize, 2), partial_rects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), partial_rects[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), partial_rects[1].x, 0.001);
}

test "TextBuffer vertical cursor keeps folded glyph trailing byte offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{
            .max_width = 100,
            .line_height = 24,
        },
    };

    const text = "A\u{fe0f}";
    var buffer = try TextBuffer.initText(allocator, text);
    defer buffer.deinit();

    try buffer.setCursor(text.len);
    try buffer.moveCursorVertical(config, .next, false);

    // There is no next glyph after the folded base+VS glyph. The trailing
    // caret must therefore use the glyph's shaped source extent rather than
    // fabricating `cluster + 1`, which would land inside/outside UTF-8 text.
    try std.testing.expectEqual(@as(usize, text.len), buffer.cursor_byte);
}

test "TextBuffer visible dirty check catches deleting all text" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{ .max_width = 100, .line_height = 24 },
    };

    var buffer = try TextBuffer.initText(allocator, "a");
    defer buffer.deinit();
    _ = try buffer.ensureLayout(config);
    try std.testing.expect(buffer.dirtyRange().isEmpty());

    try buffer.setCursor(buffer.slice().len);
    try buffer.deleteBackward();
    try std.testing.expectEqualStrings("", buffer.slice());
    try std.testing.expect(buffer.dirtyRange().isEmpty());
    try std.testing.expect(try buffer.dirtyIntersectsVisible(config, 24));
}

test "TextBuffer marks trailing deletions dirty after layout" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{ .max_width = 100, .line_height = 24 },
    };

    var buffer = try TextBuffer.initText(allocator, "abc");
    defer buffer.deinit();
    _ = try buffer.ensureLayout(config);
    try std.testing.expect(buffer.dirtyRange().isEmpty());

    try buffer.setCursor(buffer.slice().len);
    try buffer.deleteBackward();
    try std.testing.expectEqualStrings("ab", buffer.slice());
    try std.testing.expect(!buffer.dirtyRange().isEmpty());
    try std.testing.expectEqual(@as(usize, 2), buffer.dirtyRange().byte_end);
}

test "TextBuffer relayout supports hit testing cursor and selection geometry" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{
            .max_width = 42,
            .line_height = 24,
        },
    };

    var buffer = try TextBuffer.initText(allocator, "A A A");
    defer buffer.deinit();

    const paragraph = try buffer.ensureLayout(config);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);
    try std.testing.expect(buffer.dirtyRange().isEmpty());

    const hit = try buffer.hitTest(config, 15, 8);
    try std.testing.expectEqual(@as(usize, 0), hit.glyph_index);
    try std.testing.expect(hit.trailing);

    try buffer.setCursor(4);
    const cursor = try buffer.cursorRect(config);
    try std.testing.expect(cursor.x >= 0);
    try std.testing.expect(cursor.y >= 0);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), cursor.height, 0.001);

    try buffer.setSelection(1, 5);
    const rects = try buffer.selectionRects(allocator, config);
    defer allocator.free(rects);
    try std.testing.expectEqual(@as(usize, 2), rects.len);

    try buffer.insertAtCursor("A");
    try std.testing.expectEqualStrings("AA", buffer.slice());
    try std.testing.expect(!buffer.dirtyRange().isEmpty());
    _ = try buffer.ensureLayout(config);
    try std.testing.expect(buffer.dirtyRange().isEmpty());
}

test "TextBuffer moves cursor vertically between layout lines" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{
            .max_width = 42,
            .line_height = 24,
        },
    };

    var buffer = try TextBuffer.initText(allocator, "A A A");
    defer buffer.deinit();

    const paragraph = try buffer.ensureLayout(config);
    try std.testing.expectEqual(@as(usize, 2), paragraph.lines.len);

    try buffer.setCursor(0);
    try buffer.moveCursorVertical(config, .next, false);
    try std.testing.expectEqual(@as(usize, 4), buffer.cursor_byte);
    var cursor = try buffer.cursorRect(config);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), cursor.y, 0.001);

    try buffer.moveCursorVertical(config, .previous, false);
    try std.testing.expectEqual(@as(usize, 0), buffer.cursor_byte);
    cursor = try buffer.cursorRect(config);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), cursor.y, 0.001);

    try buffer.setCursor(0);
    try buffer.moveCursorVertical(config, .next, true);
    try std.testing.expectEqual(@as(usize, 0), buffer.selection.anchor_byte);
    try std.testing.expectEqual(@as(usize, 4), buffer.selection.focus_byte);
}

test "TextBuffer preserves preferred x across vertical cursor moves" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{
            .max_width = 200,
            .line_height = 24,
        },
    };

    var buffer = try TextBuffer.initText(allocator, "AAA\nA\nAAA");
    defer buffer.deinit();
    _ = try buffer.ensureLayout(config);

    try buffer.setCursor(2);
    var cursor = try buffer.cursorRect(config);
    try std.testing.expectApproxEqAbs(@as(f32, 28.0), cursor.x, 0.001);

    try buffer.moveCursorVertical(config, .next, false);
    try std.testing.expectEqual(@as(usize, 5), buffer.cursor_byte);
    cursor = try buffer.cursorRect(config);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), cursor.x, 0.001);

    try buffer.moveCursorVertical(config, .next, false);
    try std.testing.expectEqual(@as(usize, 8), buffer.cursor_byte);
    cursor = try buffer.cursorRect(config);
    try std.testing.expectApproxEqAbs(@as(f32, 28.0), cursor.x, 0.001);

    try buffer.moveCursorGrapheme(.previous, false);
    try std.testing.expect(buffer.preferred_cursor_x == null);
}

test "TextBuffer tracks visible line range and scrolls cursor into view" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const fonts = [_]*const Font{&font};
    const config = LayoutConfig{
        .cascade = layout.FontCascade.init(&fonts),
        .font_size = 20,
        .paragraph = .{
            .max_width = 200,
            .line_height = 24,
        },
    };

    var buffer = try TextBuffer.initText(allocator, "A\nA\nA\nA");
    defer buffer.deinit();
    const paragraph = try buffer.ensureLayout(config);
    try std.testing.expectEqual(@as(usize, 4), paragraph.lines.len);

    var visible = try buffer.visibleLineRange(config, 48);
    try std.testing.expectEqual(@as(usize, 0), visible.start_line);
    try std.testing.expectEqual(@as(usize, 2), visible.end_line);
    try std.testing.expect(!visible.isEmpty());
    var visible_bytes = try buffer.visibleByteRange(config, 48);
    try std.testing.expectEqual(@as(usize, 0), visible_bytes.byte_start);
    try std.testing.expectEqual(@as(usize, 3), visible_bytes.byte_end);

    buffer.setScrollY(24);
    visible = try buffer.visibleLineRange(config, 48);
    try std.testing.expectEqual(@as(usize, 1), visible.start_line);
    try std.testing.expectEqual(@as(usize, 3), visible.end_line);
    visible_bytes = try buffer.visibleByteRange(config, 48);
    try std.testing.expectEqual(@as(usize, 2), visible_bytes.byte_start);
    try std.testing.expectEqual(@as(usize, 5), visible_bytes.byte_end);

    buffer.setScrollY(-10);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buffer.scroll_y, 0.001);

    try buffer.setCursor(4);
    try buffer.scrollCursorIntoView(config, 24);
    try std.testing.expectApproxEqAbs(@as(f32, 48.0), buffer.scroll_y, 0.001);
    visible = try buffer.visibleLineRange(config, 24);
    try std.testing.expectEqual(@as(usize, 2), visible.start_line);
    try std.testing.expectEqual(@as(usize, 3), visible.end_line);
    visible_bytes = try buffer.visibleByteRange(config, 24);
    try std.testing.expectEqual(@as(usize, 4), visible_bytes.byte_start);
    try std.testing.expectEqual(@as(usize, 5), visible_bytes.byte_end);

    try buffer.insertText(0, "B");
    buffer.setScrollY(0);
    try std.testing.expect(try buffer.dirtyIntersectsVisible(config, 24));
    try buffer.insertText(0, "C");
    buffer.setScrollY(48);
    try std.testing.expect(!try buffer.dirtyIntersectsVisible(config, 24));
}
