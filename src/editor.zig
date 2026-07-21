const std = @import("std");
const buffer_mod = @import("buffer.zig");
const core = @import("core.zig");
const unicode = @import("unicode.zig");

pub const EditRecord = struct {
    group_id: usize,
    start_byte: usize,
    before: []u8,
    after: []u8,
    selection_before: buffer_mod.Selection,
    selection_after: buffer_mod.Selection,

    fn deinit(self: *EditRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.before);
        allocator.free(self.after);
        self.* = undefined;
    }
};

pub const ClipboardPayload = struct {
    allocator: std.mem.Allocator,
    text: []u8,

    pub fn init(allocator: std.mem.Allocator, text: []const u8) !ClipboardPayload {
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
        return .{
            .allocator = allocator,
            .text = try allocator.dupe(u8, text),
        };
    }

    pub fn deinit(self: *ClipboardPayload) void {
        self.allocator.free(self.text);
        self.* = undefined;
    }

    pub fn slice(self: *const ClipboardPayload) []const u8 {
        return self.text;
    }
};

pub const ImeComposition = struct {
    allocator: std.mem.Allocator,
    anchor_byte: usize,
    replace_start: usize,
    replace_end: usize,
    text: []u8,

    pub fn init(allocator: std.mem.Allocator, anchor_byte: usize, replace_start: usize, replace_end: usize, text: []const u8) !ImeComposition {
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
        return .{
            .allocator = allocator,
            .anchor_byte = anchor_byte,
            .replace_start = replace_start,
            .replace_end = replace_end,
            .text = try allocator.dupe(u8, text),
        };
    }

    pub fn deinit(self: *ImeComposition) void {
        self.allocator.free(self.text);
        self.* = undefined;
    }

    pub fn slice(self: *const ImeComposition) []const u8 {
        return self.text;
    }
};

pub const MultiCursorSet = struct {
    allocator: std.mem.Allocator,
    selections: std.ArrayList(buffer_mod.Selection) = .empty,

    pub fn init(allocator: std.mem.Allocator) MultiCursorSet {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *MultiCursorSet) void {
        self.selections.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *MultiCursorSet) void {
        self.selections.clearRetainingCapacity();
    }

    pub fn add(self: *MultiCursorSet, selection: buffer_mod.Selection) !void {
        try self.selections.append(self.allocator, selection);
        sortSelections(self.selections.items);
        normalizeSelections(&self.selections);
    }

    pub fn len(self: *const MultiCursorSet) usize {
        return self.selections.items.len;
    }

    pub fn items(self: *const MultiCursorSet) []const buffer_mod.Selection {
        return self.selections.items;
    }
};

pub const SyntaxHighlightSpan = struct {
    byte_range: core.ByteRange,
    style: core.TextStyle,
    token_kind: []const u8 = "",
};

pub const SyntaxHighlightSet = struct {
    allocator: std.mem.Allocator,
    spans: std.ArrayList(SyntaxHighlightSpan) = .empty,

    pub fn init(allocator: std.mem.Allocator) SyntaxHighlightSet {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SyntaxHighlightSet) void {
        self.spans.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *SyntaxHighlightSet) void {
        self.spans.clearRetainingCapacity();
    }

    pub fn add(self: *SyntaxHighlightSet, span: SyntaxHighlightSpan) !void {
        try self.spans.append(self.allocator, span);
        std.mem.sort(SyntaxHighlightSpan, self.spans.items, {}, highlightLessThan);
    }

    pub fn validate(self: SyntaxHighlightSet, text: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
        for (self.spans.items) |span| {
            if (span.byte_range.end() > text.len) return error.InvalidRange;
            if (!isUtf8Boundary(text, span.byte_range.start)) return error.InvalidUtf8Boundary;
            if (!isUtf8Boundary(text, span.byte_range.end())) return error.InvalidUtf8Boundary;
        }
    }

    pub fn styleAtByte(self: SyntaxHighlightSet, byte_offset: usize) ?core.TextStyle {
        for (self.spans.items) |span| {
            if (span.byte_range.contains(byte_offset)) return span.style;
        }
        return null;
    }

    pub fn len(self: SyntaxHighlightSet) usize {
        return self.spans.items.len;
    }
};

pub const SyntaxHighlightPalette = struct {
    keyword: core.TextStyle = .{ .font_weight = .bold },
    comment: core.TextStyle = .{ .font_style = .italic },
    string: core.TextStyle = .{ .font_weight = .medium },
    number: core.TextStyle = .{ .font_weight = .semi_bold },
};

pub const LineColumn = struct {
    line: usize,
    column: usize,
    byte_offset: usize,
};

pub const DisplayWidthMode = enum {
    narrow,
    east_asian,
};

pub const TerminalColumnOptions = struct {
    tab_width: usize = 8,
    width_mode: DisplayWidthMode = .east_asian,
    ignore_ansi: bool = true,
};

pub fn highlightZigSyntax(allocator: std.mem.Allocator, text: []const u8, palette: SyntaxHighlightPalette) !SyntaxHighlightSet {
    var highlights = SyntaxHighlightSet.init(allocator);
    errdefer highlights.deinit();
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte = text[cursor];
        if (std.ascii.isWhitespace(byte)) {
            cursor += 1;
            continue;
        }
        if (byte == '/' and cursor + 1 < text.len and text[cursor + 1] == '/') {
            const start = cursor;
            cursor += 2;
            while (cursor < text.len and text[cursor] != '\n') : (cursor += 1) {}
            try highlights.add(.{ .byte_range = .{ .start = start, .len = cursor - start }, .style = palette.comment, .token_kind = "comment" });
            continue;
        }
        if (byte == '"') {
            const start = cursor;
            cursor += 1;
            while (cursor < text.len) : (cursor += 1) {
                if (text[cursor] == '\\' and cursor + 1 < text.len) {
                    cursor += 1;
                    continue;
                }
                if (text[cursor] == '"') {
                    cursor += 1;
                    break;
                }
            }
            try highlights.add(.{ .byte_range = .{ .start = start, .len = cursor - start }, .style = palette.string, .token_kind = "string" });
            continue;
        }
        if (std.ascii.isDigit(byte)) {
            const start = cursor;
            cursor += 1;
            while (cursor < text.len and (std.ascii.isAlphanumeric(text[cursor]) or text[cursor] == '_' or text[cursor] == '.')) : (cursor += 1) {}
            try highlights.add(.{ .byte_range = .{ .start = start, .len = cursor - start }, .style = palette.number, .token_kind = "number" });
            continue;
        }
        if (isIdentStart(byte)) {
            const start = cursor;
            cursor += 1;
            while (cursor < text.len and isIdentContinue(text[cursor])) : (cursor += 1) {}
            const token = text[start..cursor];
            if (isZigKeyword(token)) {
                try highlights.add(.{ .byte_range = .{ .start = start, .len = token.len }, .style = palette.keyword, .token_kind = "keyword" });
            }
            continue;
        }
        cursor += 1;
    }
    try highlights.validate(text);
    return highlights;
}

pub const TextEditor = struct {
    allocator: std.mem.Allocator,
    buffer: buffer_mod.TextBuffer,
    undo_stack: std.ArrayList(EditRecord) = .empty,
    redo_stack: std.ArrayList(EditRecord) = .empty,
    next_group_id: usize = 1,
    composition: ?ImeComposition = null,
    cursors: MultiCursorSet,
    highlights: SyntaxHighlightSet,

    pub fn init(allocator: std.mem.Allocator) TextEditor {
        return .{
            .allocator = allocator,
            .buffer = buffer_mod.TextBuffer.init(allocator),
            .cursors = MultiCursorSet.init(allocator),
            .highlights = SyntaxHighlightSet.init(allocator),
        };
    }

    pub fn initText(allocator: std.mem.Allocator, text: []const u8) !TextEditor {
        var editor = TextEditor.init(allocator);
        errdefer editor.deinit();
        try editor.buffer.setText(text);
        return editor;
    }

    pub fn deinit(self: *TextEditor) void {
        self.cancelComposition();
        self.highlights.deinit();
        self.cursors.deinit();
        clearRecords(self.allocator, &self.redo_stack);
        clearRecords(self.allocator, &self.undo_stack);
        self.buffer.deinit();
        self.* = undefined;
    }

    pub fn slice(self: *const TextEditor) []const u8 {
        return self.buffer.slice();
    }

    pub fn setCursor(self: *TextEditor, byte_offset: usize) !void {
        try self.buffer.setCursor(byte_offset);
    }

    pub fn setSelection(self: *TextEditor, anchor_byte: usize, focus_byte: usize) !void {
        try self.buffer.setSelection(anchor_byte, focus_byte);
    }

    pub fn clearCursors(self: *TextEditor) void {
        self.cursors.clear();
    }

    pub fn addCursor(self: *TextEditor, anchor_byte: usize, focus_byte: usize) !void {
        _ = try checkedOffset(self.buffer.slice(), anchor_byte);
        _ = try checkedOffset(self.buffer.slice(), focus_byte);
        try self.cursors.add(.{ .anchor_byte = anchor_byte, .focus_byte = focus_byte });
    }

    pub fn clearHighlights(self: *TextEditor) void {
        self.highlights.clear();
    }

    pub fn addHighlight(self: *TextEditor, span: SyntaxHighlightSpan) !void {
        try self.highlights.add(span);
        try self.highlights.validate(self.buffer.slice());
    }

    pub fn highlightStyleAtByte(self: *const TextEditor, byte_offset: usize) ?core.TextStyle {
        return self.highlights.styleAtByte(byte_offset);
    }

    pub fn lineColumnAtByte(self: *const TextEditor, byte_offset: usize, tab_width: usize) !LineColumn {
        _ = try checkedOffset(self.buffer.slice(), byte_offset);
        return try lineColumnForByte(self.buffer.slice(), byte_offset, tab_width, .narrow);
    }

    pub fn lineColumnAtByteWithWidth(self: *const TextEditor, byte_offset: usize, tab_width: usize, width_mode: DisplayWidthMode) !LineColumn {
        _ = try checkedOffset(self.buffer.slice(), byte_offset);
        return try lineColumnForByte(self.buffer.slice(), byte_offset, tab_width, width_mode);
    }

    pub fn byteOffsetForLineColumn(self: *const TextEditor, line: usize, column: usize, tab_width: usize) usize {
        return byteOffsetForLineColumnInText(self.buffer.slice(), line, column, tab_width, .narrow);
    }

    pub fn byteOffsetForLineColumnWithWidth(self: *const TextEditor, line: usize, column: usize, tab_width: usize, width_mode: DisplayWidthMode) usize {
        return byteOffsetForLineColumnInText(self.buffer.slice(), line, column, tab_width, width_mode);
    }

    pub fn lineColumnAtByteGrapheme(self: *const TextEditor, byte_offset: usize, tab_width: usize, width_mode: DisplayWidthMode) !LineColumn {
        _ = try checkedOffset(self.buffer.slice(), byte_offset);
        return try lineColumnForByteGrapheme(self.allocator, self.buffer.slice(), byte_offset, tab_width, width_mode);
    }

    pub fn byteOffsetForLineColumnGrapheme(self: *const TextEditor, line: usize, column: usize, tab_width: usize, width_mode: DisplayWidthMode) !usize {
        return try byteOffsetForLineColumnGraphemeInText(self.allocator, self.buffer.slice(), line, column, tab_width, width_mode);
    }

    pub fn terminalLineColumnAtByte(self: *const TextEditor, byte_offset: usize, options: TerminalColumnOptions) !LineColumn {
        _ = try checkedOffset(self.buffer.slice(), byte_offset);
        return try lineColumnForByteTerminal(self.buffer.slice(), byte_offset, options);
    }

    pub fn terminalByteOffsetForLineColumn(self: *const TextEditor, line: usize, column: usize, options: TerminalColumnOptions) usize {
        return byteOffsetForLineColumnTerminal(self.buffer.slice(), line, column, options);
    }

    pub fn insertTextAtCursors(self: *TextEditor, text: []const u8) !void {
        if (self.cursors.len() == 0) return self.insertText(text);
        self.cancelComposition();
        const group_id = try self.allocateGroupId();
        clearRecords(self.allocator, &self.redo_stack);
        var index = self.cursors.selections.items.len;
        while (index > 0) {
            index -= 1;
            const selection = self.cursors.selections.items[index];
            const range = selectionRange(selection);
            try self.replaceRangeGrouped(group_id, range.start, range.end, text, false);
        }
        self.cursors.clear();
    }

    pub fn beginComposition(self: *TextEditor, text: []const u8) !void {
        self.cancelComposition();
        const range = selectionRange(self.buffer.selection);
        self.composition = try ImeComposition.init(self.allocator, self.buffer.cursor_byte, range.start, range.end, text);
    }

    pub fn updateComposition(self: *TextEditor, text: []const u8) !void {
        if (self.composition == null) {
            try self.beginComposition(text);
            return;
        }
        const composition = &self.composition.?;
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
        const updated = try self.allocator.dupe(u8, text);
        self.allocator.free(composition.text);
        composition.text = updated;
    }

    pub fn cancelComposition(self: *TextEditor) void {
        if (self.composition) |*composition| {
            composition.deinit();
            self.composition = null;
        }
    }

    pub fn commitComposition(self: *TextEditor) !bool {
        if (self.composition == null) return false;
        var composition = self.composition.?;
        self.composition = null;
        defer composition.deinit();
        try self.replaceRange(composition.replace_start, composition.replace_end, composition.text);
        return true;
    }

    pub fn hasComposition(self: *const TextEditor) bool {
        return self.composition != null;
    }

    pub fn insertText(self: *TextEditor, text: []const u8) !void {
        self.cancelComposition();
        const range = selectionRange(self.buffer.selection);
        try self.replaceRange(range.start, range.end, text);
    }

    pub fn deleteBackward(self: *TextEditor) !void {
        self.cancelComposition();
        if (!self.buffer.selection.isCollapsed()) {
            const range = selectionRange(self.buffer.selection);
            return self.replaceRange(range.start, range.end, "");
        }
        const previous = try previousGraphemeBoundary(self.allocator, self.buffer.slice(), self.buffer.cursor_byte);
        if (previous == self.buffer.cursor_byte) return;
        try self.replaceRange(previous, self.buffer.cursor_byte, "");
    }

    pub fn deleteForward(self: *TextEditor) !void {
        self.cancelComposition();
        if (!self.buffer.selection.isCollapsed()) {
            const range = selectionRange(self.buffer.selection);
            return self.replaceRange(range.start, range.end, "");
        }
        const next = try nextGraphemeBoundary(self.allocator, self.buffer.slice(), self.buffer.cursor_byte);
        if (next == self.buffer.cursor_byte) return;
        try self.replaceRange(self.buffer.cursor_byte, next, "");
    }

    pub fn copySelection(self: *const TextEditor) !?ClipboardPayload {
        if (self.buffer.selection.isCollapsed()) return null;
        const range = selectionRange(self.buffer.selection);
        return try ClipboardPayload.init(self.allocator, self.buffer.slice()[range.start..range.end]);
    }

    pub fn cutSelection(self: *TextEditor) !?ClipboardPayload {
        self.cancelComposition();
        if (self.buffer.selection.isCollapsed()) return null;
        const range = selectionRange(self.buffer.selection);
        var payload = try ClipboardPayload.init(self.allocator, self.buffer.slice()[range.start..range.end]);
        errdefer payload.deinit();
        try self.replaceRange(range.start, range.end, "");
        return payload;
    }

    pub fn paste(self: *TextEditor, payload: ClipboardPayload) !void {
        try self.insertText(payload.slice());
    }

    pub fn pasteText(self: *TextEditor, text: []const u8) !void {
        try self.insertText(text);
    }

    pub fn replaceRange(self: *TextEditor, start_byte: usize, end_byte: usize, replacement: []const u8) !void {
        try self.replaceRangeGrouped(try self.allocateGroupId(), start_byte, end_byte, replacement, true);
    }

    fn replaceRangeGrouped(self: *TextEditor, group_id: usize, start_byte: usize, end_byte: usize, replacement: []const u8, clear_redo: bool) !void {
        self.cancelComposition();
        if (start_byte > end_byte or end_byte > self.buffer.slice().len) return error.InvalidRange;
        const before = try self.allocator.dupe(u8, self.buffer.slice()[start_byte..end_byte]);
        errdefer self.allocator.free(before);
        const after = try self.allocator.dupe(u8, replacement);
        errdefer self.allocator.free(after);
        const selection_before = self.buffer.selection;
        try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);

        try self.buffer.replaceRange(start_byte, end_byte, replacement);
        const selection_after = self.buffer.selection;
        if (clear_redo) clearRecords(self.allocator, &self.redo_stack);
        try self.undo_stack.append(self.allocator, .{
            .group_id = group_id,
            .start_byte = start_byte,
            .before = before,
            .after = after,
            .selection_before = selection_before,
            .selection_after = selection_after,
        });
    }

    pub fn undo(self: *TextEditor) !bool {
        if (self.undo_stack.items.len == 0) return false;
        const group_id = self.undo_stack.items[self.undo_stack.items.len - 1].group_id;
        while (self.undo_stack.items.len > 0 and self.undo_stack.items[self.undo_stack.items.len - 1].group_id == group_id) {
            var record = self.undo_stack.pop().?;
            errdefer record.deinit(self.allocator);
            try self.applyRecord(record, .undo);
            try self.redo_stack.append(self.allocator, record);
        }
        return true;
    }

    pub fn redo(self: *TextEditor) !bool {
        if (self.redo_stack.items.len == 0) return false;
        const group_id = self.redo_stack.items[self.redo_stack.items.len - 1].group_id;
        while (self.redo_stack.items.len > 0 and self.redo_stack.items[self.redo_stack.items.len - 1].group_id == group_id) {
            var record = self.redo_stack.pop().?;
            errdefer record.deinit(self.allocator);
            try self.applyRecord(record, .redo);
            try self.undo_stack.append(self.allocator, record);
        }
        return true;
    }

    pub fn canUndo(self: *const TextEditor) bool {
        return self.undo_stack.items.len > 0;
    }

    pub fn canRedo(self: *const TextEditor) bool {
        return self.redo_stack.items.len > 0;
    }

    fn applyRecord(self: *TextEditor, record: EditRecord, direction: enum { undo, redo }) !void {
        switch (direction) {
            .undo => {
                try self.buffer.replaceRange(record.start_byte, record.start_byte + record.after.len, record.before);
                try self.buffer.setSelection(record.selection_before.anchor_byte, record.selection_before.focus_byte);
            },
            .redo => {
                try self.buffer.replaceRange(record.start_byte, record.start_byte + record.before.len, record.after);
                try self.buffer.setSelection(record.selection_after.anchor_byte, record.selection_after.focus_byte);
            },
        }
    }

    fn allocateGroupId(self: *TextEditor) !usize {
        const group_id = self.next_group_id;
        if (group_id == std.math.maxInt(usize)) return error.EditGroupIdOverflow;
        self.next_group_id += 1;
        return group_id;
    }
};

fn clearRecords(allocator: std.mem.Allocator, records: *std.ArrayList(EditRecord)) void {
    for (records.items) |*record| record.deinit(allocator);
    records.deinit(allocator);
    records.* = .empty;
}

fn sortSelections(selections: []buffer_mod.Selection) void {
    std.mem.sort(buffer_mod.Selection, selections, {}, selectionLessThan);
}

fn selectionLessThan(_: void, lhs: buffer_mod.Selection, rhs: buffer_mod.Selection) bool {
    return lhs.start() < rhs.start();
}

fn normalizeSelections(selections: *std.ArrayList(buffer_mod.Selection)) void {
    if (selections.items.len < 2) return;
    var write: usize = 0;
    for (selections.items[1..]) |selection| {
        var current = selections.items[write];
        if (selection.start() <= current.end()) {
            current = .{
                .anchor_byte = @min(current.start(), selection.start()),
                .focus_byte = @max(current.end(), selection.end()),
            };
            selections.items[write] = current;
        } else {
            write += 1;
            selections.items[write] = selection;
        }
    }
    selections.shrinkRetainingCapacity(write + 1);
}

fn highlightLessThan(_: void, lhs: SyntaxHighlightSpan, rhs: SyntaxHighlightSpan) bool {
    return lhs.byte_range.start < rhs.byte_range.start;
}

fn isIdentStart(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_';
}

fn isIdentContinue(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn isZigKeyword(token: []const u8) bool {
    const keywords = [_][]const u8{
        "addrspace",   "align",    "allowzero", "and",         "anyframe",
        "anytype",     "asm",      "async",     "await",       "break",
        "callconv",    "catch",    "comptime",  "const",       "continue",
        "defer",       "else",     "enum",      "errdefer",    "error",
        "export",      "extern",   "fn",        "for",         "if",
        "inline",      "noalias",  "nosuspend", "opaque",      "or",
        "orelse",      "packed",   "pub",       "resume",      "return",
        "linksection", "struct",   "suspend",   "switch",      "test",
        "threadlocal", "try",      "union",     "unreachable", "usingnamespace",
        "var",         "volatile", "while",
    };
    for (keywords) |keyword| {
        if (std.mem.eql(u8, token, keyword)) return true;
    }
    return false;
}

fn selectionRange(selection: buffer_mod.Selection) struct { start: usize, end: usize } {
    return .{ .start = selection.start(), .end = selection.end() };
}

fn checkedOffset(text: []const u8, byte_offset: usize) !usize {
    if (byte_offset > text.len) return error.InvalidRange;
    if (byte_offset != 0 and byte_offset != text.len and (text[byte_offset] & 0b1100_0000) == 0b1000_0000) return error.InvalidUtf8Boundary;
    return byte_offset;
}

fn isUtf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0b1100_0000) != 0b1000_0000;
}

fn lineColumnForByte(text: []const u8, byte_offset: usize, tab_width: usize, width_mode: DisplayWidthMode) !LineColumn {
    var line: usize = 0;
    var column: usize = 0;
    var cursor: usize = 0;
    while (cursor < byte_offset) {
        const decoded = try decodeCodepointAt(text, cursor);
        const codepoint = decoded.codepoint;
        if (codepoint == '\n') {
            line += 1;
            column = 0;
        } else if (codepoint == '\t') {
            column += tabColumnAdvance(column, tab_width);
        } else {
            column += codepointDisplayWidth(codepoint, width_mode);
        }
        cursor = decoded.next;
    }
    return .{ .line = line, .column = column, .byte_offset = byte_offset };
}

fn byteOffsetForLineColumnInText(text: []const u8, target_line: usize, target_column: usize, tab_width: usize, width_mode: DisplayWidthMode) usize {
    var line: usize = 0;
    var column: usize = 0;
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) catch return text.len;
        const codepoint = decoded.codepoint;
        if (line == target_line and column >= target_column) return byte_start;
        if (codepoint == '\n') {
            if (line == target_line) return byte_start;
            line += 1;
            column = 0;
        } else if (codepoint == '\t') {
            const next_column = column + tabColumnAdvance(column, tab_width);
            if (line == target_line and next_column > target_column) return byte_start;
            column = next_column;
        } else {
            const next_column = column + codepointDisplayWidth(codepoint, width_mode);
            if (line == target_line and next_column > target_column) return byte_start;
            column = next_column;
        }
        cursor = decoded.next;
    }
    return text.len;
}

fn lineColumnForByteTerminal(text: []const u8, byte_offset: usize, options: TerminalColumnOptions) !LineColumn {
    var line: usize = 0;
    var column: usize = 0;
    var cursor: usize = 0;
    while (cursor < byte_offset and cursor < text.len) {
        if (options.ignore_ansi and text[cursor] == 0x1b) {
            cursor = skipAnsiEscape(text, cursor);
            continue;
        }
        const decoded = try decodeCodepointAt(text, cursor);
        const codepoint = decoded.codepoint;
        const end = decoded.next;
        if (codepoint == '\n') {
            line += 1;
            column = 0;
        } else if (codepoint == '\t') {
            column += tabColumnAdvance(column, options.tab_width);
        } else if (isC0Control(codepoint)) {
            // Non-layout C0 controls are terminal actions, not visible cells.
        } else {
            column += codepointDisplayWidth(codepoint, options.width_mode);
        }
        cursor = end;
    }
    return .{ .line = line, .column = column, .byte_offset = byte_offset };
}

fn byteOffsetForLineColumnTerminal(text: []const u8, target_line: usize, target_column: usize, options: TerminalColumnOptions) usize {
    var line: usize = 0;
    var column: usize = 0;
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        if (options.ignore_ansi and text[cursor] == 0x1b) {
            cursor = skipAnsiEscape(text, cursor);
            continue;
        }
        const decoded = decodeCodepointAt(text, cursor) catch return text.len;
        const codepoint = decoded.codepoint;
        const end = decoded.next;
        if (line == target_line and column >= target_column) return byte_start;
        if (codepoint == '\n') {
            if (line == target_line) return byte_start;
            line += 1;
            column = 0;
        } else if (codepoint == '\t') {
            const next_column = column + tabColumnAdvance(column, options.tab_width);
            if (line == target_line and next_column > target_column) return byte_start;
            column = next_column;
        } else if (isC0Control(codepoint)) {
            // Non-layout C0 controls are terminal actions, not visible cells.
        } else {
            const next_column = column + codepointDisplayWidth(codepoint, options.width_mode);
            if (line == target_line and next_column > target_column) return byte_start;
            column = next_column;
        }
        cursor = end;
    }
    return text.len;
}

const DecodedCodepoint = struct {
    codepoint: u21,
    next: usize,
};

fn decodeCodepointAt(text: []const u8, cursor: usize) !DecodedCodepoint {
    if (cursor >= text.len) return error.EndOfInput;
    const len = std.unicode.utf8ByteSequenceLength(text[cursor]) catch return error.InvalidUtf8;
    const end = cursor + @as(usize, len);
    if (end > text.len) return error.InvalidUtf8;
    const codepoint = std.unicode.utf8Decode(text[cursor..end]) catch return error.InvalidUtf8;
    return .{ .codepoint = codepoint, .next = end };
}

fn lineColumnForByteGrapheme(allocator: std.mem.Allocator, text: []const u8, byte_offset: usize, tab_width: usize, width_mode: DisplayWidthMode) !LineColumn {
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    var line: usize = 0;
    var column: usize = 0;
    for (clusters) |cluster| {
        if (cluster.byte_start >= byte_offset) break;
        const slice = text[cluster.byte_start..][0..cluster.byte_len];
        if (std.mem.eql(u8, slice, "\n") or std.mem.eql(u8, slice, "\r\n") or std.mem.eql(u8, slice, "\r")) {
            line += 1;
            column = 0;
        } else if (std.mem.eql(u8, slice, "\t")) {
            column += tabColumnAdvance(column, tab_width);
        } else {
            column += graphemeDisplayWidth(slice, width_mode);
        }
    }
    return .{ .line = line, .column = column, .byte_offset = byte_offset };
}

fn byteOffsetForLineColumnGraphemeInText(allocator: std.mem.Allocator, text: []const u8, target_line: usize, target_column: usize, tab_width: usize, width_mode: DisplayWidthMode) !usize {
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    var line: usize = 0;
    var column: usize = 0;
    for (clusters) |cluster| {
        const slice = text[cluster.byte_start..][0..cluster.byte_len];
        if (line == target_line and column >= target_column) return cluster.byte_start;
        if (std.mem.eql(u8, slice, "\n") or std.mem.eql(u8, slice, "\r\n") or std.mem.eql(u8, slice, "\r")) {
            if (line == target_line) return cluster.byte_start;
            line += 1;
            column = 0;
        } else if (std.mem.eql(u8, slice, "\t")) {
            const next_column = column + tabColumnAdvance(column, tab_width);
            if (line == target_line and next_column > target_column) return cluster.byte_start;
            column = next_column;
        } else {
            const next_column = column + graphemeDisplayWidth(slice, width_mode);
            if (line == target_line and next_column > target_column) return cluster.byte_start;
            column = next_column;
        }
    }
    return text.len;
}

fn tabColumnAdvance(column: usize, tab_width: usize) usize {
    const width = @max(1, tab_width);
    return width - (column % width);
}

fn skipAnsiEscape(text: []const u8, start: usize) usize {
    var cursor = start + 1;
    if (cursor >= text.len) return cursor;
    if (text[cursor] == '[') {
        cursor += 1;
        while (cursor < text.len) : (cursor += 1) {
            const byte = text[cursor];
            if (byte >= 0x40 and byte <= 0x7e) return cursor + 1;
        }
        return cursor;
    }
    if (text[cursor] == ']' or text[cursor] == 'P' or text[cursor] == '^' or text[cursor] == '_') {
        cursor += 1;
        while (cursor < text.len) : (cursor += 1) {
            if (text[cursor] == 0x07) return cursor + 1;
            if (text[cursor] == 0x1b and cursor + 1 < text.len and text[cursor + 1] == '\\') return cursor + 2;
        }
        return cursor;
    }
    return @min(text.len, cursor + 1);
}

fn isC0Control(codepoint: u21) bool {
    return codepoint < 0x20 or codepoint == 0x7f;
}

fn graphemeDisplayWidth(text: []const u8, width_mode: DisplayWidthMode) usize {
    var width: usize = 0;
    var saw_wide = false;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        if (isZeroWidthDisplayCodepoint(codepoint)) continue;
        const cp_width = codepointDisplayWidth(codepoint, width_mode);
        if (cp_width >= 2) saw_wide = true;
        width += cp_width;
    }
    if (saw_wide) return 2;
    return @min(width, 1);
}

pub fn codepointDisplayWidth(codepoint: u21, width_mode: DisplayWidthMode) usize {
    if (isZeroWidthDisplayCodepoint(codepoint)) return 0;
    return switch (width_mode) {
        .narrow => 1,
        .east_asian => if (isWideDisplayCodepoint(codepoint)) 2 else 1,
    };
}

fn isZeroWidthDisplayCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x0300 and codepoint <= 0x036f) or
        (codepoint >= 0x1ab0 and codepoint <= 0x1aff) or
        (codepoint >= 0x1dc0 and codepoint <= 0x1dff) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        (codepoint >= 0xfe20 and codepoint <= 0xfe2f) or
        (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef) or
        (codepoint >= 0x1f3fb and codepoint <= 0x1f3ff) or
        codepoint == 0x200d;
}

fn isWideDisplayCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x11ff) or
        (codepoint >= 0x231a and codepoint <= 0x231b) or
        (codepoint >= 0x2329 and codepoint <= 0x232a) or
        (codepoint >= 0x2e80 and codepoint <= 0xa4cf) or
        (codepoint >= 0xac00 and codepoint <= 0xd7a3) or
        (codepoint >= 0xf900 and codepoint <= 0xfaff) or
        (codepoint >= 0xfe10 and codepoint <= 0xfe19) or
        (codepoint >= 0xfe30 and codepoint <= 0xfe6f) or
        (codepoint >= 0xff00 and codepoint <= 0xff60) or
        (codepoint >= 0xffe0 and codepoint <= 0xffe6) or
        (codepoint >= 0x1f300 and codepoint <= 0x1faff) or
        (codepoint >= 0x20000 and codepoint <= 0x3fffd);
}

fn previousGraphemeBoundary(allocator: std.mem.Allocator, text: []const u8, byte_offset: usize) !usize {
    const offset = try checkedOffset(text, byte_offset);
    if (offset == 0) return 0;
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    var previous: usize = 0;
    for (clusters) |cluster| {
        if (cluster.byte_start >= offset) return previous;
        previous = cluster.byte_start;
    }
    return previous;
}

fn nextGraphemeBoundary(allocator: std.mem.Allocator, text: []const u8, byte_offset: usize) !usize {
    const offset = try checkedOffset(text, byte_offset);
    if (offset == text.len) return text.len;
    const clusters = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    for (clusters) |cluster| {
        const end = cluster.byte_start + cluster.byte_len;
        if (end > offset) return end;
    }
    return text.len;
}

test "TextEditor edit group id overflow is atomic" {
    const allocator = std.testing.allocator;
    var editor = try TextEditor.initText(allocator, "ab");
    defer editor.deinit();

    editor.next_group_id = std.math.maxInt(usize);
    try std.testing.expectError(error.EditGroupIdOverflow, editor.replaceRange(0, 1, "X"));
    try std.testing.expectEqualStrings("ab", editor.slice());
    try std.testing.expect(!editor.canUndo());
}

test "TextEditor replacement preflights undo record allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var editor = try TextEditor.initText(failing.allocator(), "ab");
    defer editor.deinit();

    failing.fail_index = failing.alloc_index + 2; // before/after snapshots succeed; undo-stack growth fails.
    try std.testing.expectError(error.OutOfMemory, editor.replaceRange(0, 1, "X"));
    try std.testing.expectEqualStrings("ab", editor.slice());
    try std.testing.expect(!editor.canUndo());
}

test "TextEditor records undo and redo for inserts replacements and deletes" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "ab");
    defer editor.deinit();

    try editor.setCursor(1);
    try editor.insertText("X");
    try std.testing.expectEqualStrings("aXb", editor.slice());
    try std.testing.expect(editor.canUndo());
    try std.testing.expect(!editor.canRedo());

    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("ab", editor.slice());
    try std.testing.expect(!editor.canUndo());
    try std.testing.expect(editor.canRedo());

    try std.testing.expect(try editor.redo());
    try std.testing.expectEqualStrings("aXb", editor.slice());

    try editor.replaceRange(1, 2, "YZ");
    try std.testing.expectEqualStrings("aYZb", editor.slice());
    try std.testing.expect(!editor.canRedo());

    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("aXb", editor.slice());
    try std.testing.expect(try editor.redo());
    try std.testing.expectEqualStrings("aYZb", editor.slice());

    try editor.setCursor(3);
    try editor.deleteBackward();
    try std.testing.expectEqualStrings("aYb", editor.slice());
    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("aYZb", editor.slice());
}

test "TextEditor delete commands handle utf8 boundaries" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "A一B");
    defer editor.deinit();

    try editor.setCursor(4);
    try editor.deleteBackward();
    try std.testing.expectEqualStrings("AB", editor.slice());
    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("A一B", editor.slice());

    try editor.setCursor(1);
    try editor.deleteForward();
    try std.testing.expectEqualStrings("AB", editor.slice());
}

test "TextEditor delete commands preserve grapheme clusters" {
    const allocator = std.testing.allocator;

    var combining = try TextEditor.initText(allocator, "A\u{0301}B");
    defer combining.deinit();

    try combining.setCursor("A\u{0301}".len);
    try combining.deleteBackward();
    try std.testing.expectEqualStrings("B", combining.slice());
    try std.testing.expect(try combining.undo());
    try std.testing.expectEqualStrings("A\u{0301}B", combining.slice());

    try combining.setCursor(0);
    try combining.deleteForward();
    try std.testing.expectEqualStrings("B", combining.slice());
    try std.testing.expect(try combining.undo());
    try std.testing.expectEqualStrings("A\u{0301}B", combining.slice());

    var emoji = try TextEditor.initText(allocator, "👩\u{200d}💻!");
    defer emoji.deinit();

    try emoji.setCursor("👩\u{200d}💻".len);
    try emoji.deleteBackward();
    try std.testing.expectEqualStrings("!", emoji.slice());
    try std.testing.expect(try emoji.undo());
    try std.testing.expectEqualStrings("👩\u{200d}💻!", emoji.slice());

    try emoji.setCursor(0);
    try emoji.deleteForward();
    try std.testing.expectEqualStrings("!", emoji.slice());
}

test "TextEditor copies cuts and pastes clipboard payloads" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "alpha beta");
    defer editor.deinit();

    try editor.setSelection(6, 10);
    var copied = (try editor.copySelection()).?;
    defer copied.deinit();
    try std.testing.expectEqualStrings("beta", copied.slice());
    try std.testing.expectEqualStrings("alpha beta", editor.slice());
    try std.testing.expect(!editor.canUndo());

    var cut = (try editor.cutSelection()).?;
    defer cut.deinit();
    try std.testing.expectEqualStrings("beta", cut.slice());
    try std.testing.expectEqualStrings("alpha ", editor.slice());
    try std.testing.expect(editor.canUndo());

    try editor.setCursor(0);
    try editor.paste(cut);
    try std.testing.expectEqualStrings("betaalpha ", editor.slice());
    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("alpha ", editor.slice());
    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("alpha beta", editor.slice());

    try editor.setCursor(editor.slice().len);
    try editor.pasteText("!");
    try std.testing.expectEqualStrings("alpha beta!", editor.slice());
    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("alpha beta", editor.slice());

    try editor.setCursor(0);
    try std.testing.expect((try editor.copySelection()) == null);
    try std.testing.expect((try editor.cutSelection()) == null);

    try std.testing.expectError(error.InvalidUtf8, ClipboardPayload.init(allocator, "\xff"));
}

test "TextEditor tracks and commits IME composition" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "ab");
    defer editor.deinit();

    try editor.setCursor(1);
    try std.testing.expectError(error.InvalidUtf8, editor.beginComposition("\xff"));
    try std.testing.expect(!editor.hasComposition());

    try editor.beginComposition("x");
    try std.testing.expect(editor.hasComposition());
    try std.testing.expectEqualStrings("ab", editor.slice());
    try std.testing.expectEqualStrings("x", editor.composition.?.slice());

    try std.testing.expectError(error.InvalidUtf8, editor.updateComposition("\xff"));
    try std.testing.expectEqualStrings("x", editor.composition.?.slice());

    try editor.updateComposition("一");
    try std.testing.expectEqualStrings("一", editor.composition.?.slice());
    try std.testing.expect(try editor.commitComposition());
    try std.testing.expectEqualStrings("a一b", editor.slice());
    try std.testing.expect(!editor.hasComposition());
    try std.testing.expect(editor.canUndo());
    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("ab", editor.slice());

    try editor.setSelection(0, 2);
    try editor.beginComposition("中");
    try std.testing.expectEqual(@as(usize, 0), editor.composition.?.replace_start);
    try std.testing.expectEqual(@as(usize, 2), editor.composition.?.replace_end);
    editor.cancelComposition();
    try std.testing.expect(!editor.hasComposition());
    try std.testing.expectEqualStrings("ab", editor.slice());
}

test "TextEditor cancels IME composition on normal edits" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "ab");
    defer editor.deinit();

    try editor.setCursor(1);
    try editor.beginComposition("x");
    try editor.insertText("Z");
    try std.testing.expect(!editor.hasComposition());
    try std.testing.expectEqualStrings("aZb", editor.slice());
}

test "TextEditor inserts text at multiple cursors" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "abcd");
    defer editor.deinit();

    try editor.addCursor(3, 3);
    try editor.addCursor(1, 1);
    try std.testing.expectEqual(@as(usize, 2), editor.cursors.len());
    try std.testing.expectEqual(@as(usize, 1), editor.cursors.items()[0].start());
    try std.testing.expectEqual(@as(usize, 3), editor.cursors.items()[1].start());

    try editor.insertTextAtCursors("X");
    try std.testing.expectEqualStrings("aXbcXd", editor.slice());
    try std.testing.expectEqual(@as(usize, 0), editor.cursors.len());
    try std.testing.expect(editor.canUndo());

    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("abcd", editor.slice());
    try std.testing.expect(try editor.redo());
    try std.testing.expectEqualStrings("aXbcXd", editor.slice());
}

test "TextEditor replaces multiple cursor selections" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "abc def");
    defer editor.deinit();

    try editor.addCursor(0, 3);
    try editor.addCursor(4, 7);
    try editor.insertTextAtCursors("x");
    try std.testing.expectEqualStrings("x x", editor.slice());

    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("abc def", editor.slice());
    try std.testing.expect(try editor.redo());
    try std.testing.expectEqualStrings("x x", editor.slice());
}

test "TextEditor normalizes overlapping multi-cursor selections" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "abcdef");
    defer editor.deinit();

    try editor.addCursor(1, 4);
    try editor.addCursor(2, 5);
    try editor.addCursor(3, 3);
    try editor.addCursor(5, 5);
    try std.testing.expectEqual(@as(usize, 1), editor.cursors.len());
    try std.testing.expectEqual(@as(usize, 1), editor.cursors.items()[0].start());
    try std.testing.expectEqual(@as(usize, 5), editor.cursors.items()[0].end());

    try editor.insertTextAtCursors("X");
    try std.testing.expectEqualStrings("aXf", editor.slice());
    try std.testing.expect(try editor.undo());
    try std.testing.expectEqualStrings("abcdef", editor.slice());

    try editor.addCursor(1, 1);
    try editor.addCursor(1, 1);
    try std.testing.expectEqual(@as(usize, 1), editor.cursors.len());
}

test "TextEditor stores syntax highlight spans" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "const 一 = 1");
    defer editor.deinit();

    try editor.addHighlight(.{
        .byte_range = .{ .start = 10, .len = 1 },
        .style = .{ .font_size = 14, .font_weight = .bold },
        .token_kind = "number",
    });
    try editor.addHighlight(.{
        .byte_range = .{ .start = 0, .len = 5 },
        .style = .{ .font_size = 14, .font_style = .italic },
        .token_kind = "keyword",
    });

    try std.testing.expectEqual(@as(usize, 2), editor.highlights.len());
    try std.testing.expectEqual(@as(usize, 0), editor.highlights.spans.items[0].byte_range.start);
    try std.testing.expectEqual(@as(usize, 10), editor.highlights.spans.items[1].byte_range.start);
    try std.testing.expectEqual(.italic, editor.highlightStyleAtByte(1).?.font_style);
    try std.testing.expectEqual(.bold, editor.highlightStyleAtByte(10).?.font_weight);
    try std.testing.expect(editor.highlightStyleAtByte(6) == null);

    try std.testing.expectError(error.InvalidUtf8Boundary, editor.addHighlight(.{
        .byte_range = .{ .start = 7, .len = 1 },
        .style = .{},
        .token_kind = "bad",
    }));

    editor.clearHighlights();
    try std.testing.expectEqual(@as(usize, 0), editor.highlights.len());
}

test "Zig syntax highlighter emits keyword string number and comment spans" {
    const allocator = std.testing.allocator;
    const source = "const x = 42; // hi\npub fn main() void { return \"ok\"; }";

    var highlights = try highlightZigSyntax(allocator, source, .{});
    defer highlights.deinit();

    try std.testing.expect(highlights.len() >= 6);
    try std.testing.expectEqualStrings("keyword", highlights.spans.items[0].token_kind);
    try std.testing.expectEqual(@as(usize, 0), highlights.spans.items[0].byte_range.start);

    var saw_comment = false;
    var saw_string = false;
    var saw_number = false;
    var saw_pub = false;
    var saw_return = false;
    for (highlights.spans.items) |span| {
        const token = source[span.byte_range.start..span.byte_range.end()];
        if (std.mem.eql(u8, span.token_kind, "comment")) {
            saw_comment = true;
            try std.testing.expectEqualStrings("// hi", token);
        } else if (std.mem.eql(u8, span.token_kind, "string")) {
            saw_string = true;
            try std.testing.expectEqualStrings("\"ok\"", token);
        } else if (std.mem.eql(u8, span.token_kind, "number")) {
            saw_number = true;
            try std.testing.expectEqualStrings("42", token);
        } else if (std.mem.eql(u8, token, "pub")) {
            saw_pub = true;
            try std.testing.expectEqualStrings("keyword", span.token_kind);
        } else if (std.mem.eql(u8, token, "return")) {
            saw_return = true;
            try std.testing.expectEqualStrings("keyword", span.token_kind);
        }
    }
    try std.testing.expect(saw_comment);
    try std.testing.expect(saw_string);
    try std.testing.expect(saw_number);
    try std.testing.expect(saw_pub);
    try std.testing.expect(saw_return);
}

test "TextEditor maps byte offsets to line columns" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "a\tb\n一c");
    defer editor.deinit();

    const at_tab = try editor.lineColumnAtByte(1, 4);
    try std.testing.expectEqual(@as(usize, 0), at_tab.line);
    try std.testing.expectEqual(@as(usize, 1), at_tab.column);

    const at_b = try editor.lineColumnAtByte(2, 4);
    try std.testing.expectEqual(@as(usize, 0), at_b.line);
    try std.testing.expectEqual(@as(usize, 4), at_b.column);

    const second_line = try editor.lineColumnAtByte(4, 4);
    try std.testing.expectEqual(@as(usize, 1), second_line.line);
    try std.testing.expectEqual(@as(usize, 0), second_line.column);

    const after_cjk = try editor.lineColumnAtByte(7, 4);
    try std.testing.expectEqual(@as(usize, 1), after_cjk.line);
    try std.testing.expectEqual(@as(usize, 1), after_cjk.column);

    try std.testing.expectEqual(@as(usize, 2), editor.byteOffsetForLineColumn(0, 4, 4));
    try std.testing.expectEqual(@as(usize, 1), editor.byteOffsetForLineColumn(0, 2, 4));
    try std.testing.expectEqual(@as(usize, 4), editor.byteOffsetForLineColumn(1, 0, 4));
    try std.testing.expectEqual(@as(usize, 7), editor.byteOffsetForLineColumn(1, 1, 4));

    try std.testing.expectError(error.InvalidUtf8Boundary, editor.lineColumnAtByte(5, 4));
}

test "TextEditor line column APIs reject mutated invalid UTF-8" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "ab");
    defer editor.deinit();
    editor.buffer.text.items[1] = 0xff;

    try std.testing.expectError(error.InvalidUtf8, editor.lineColumnAtByte(editor.slice().len, 4));
    try std.testing.expectError(error.InvalidUtf8, editor.lineColumnAtByteWithWidth(editor.slice().len, 4, .east_asian));
    try std.testing.expectError(error.InvalidUtf8, editor.terminalLineColumnAtByte(editor.slice().len, .{}));

    try std.testing.expectEqual(editor.slice().len, editor.byteOffsetForLineColumn(0, 2, 4));
    try std.testing.expectEqual(editor.slice().len, editor.terminalByteOffsetForLineColumn(0, 2, .{}));
}

test "TextEditor maps wide display columns" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "a一b😀");
    defer editor.deinit();

    const narrow_after_cjk = try editor.lineColumnAtByte(4, 4);
    try std.testing.expectEqual(@as(usize, 2), narrow_after_cjk.column);
    const wide_after_cjk = try editor.lineColumnAtByteWithWidth(4, 4, .east_asian);
    try std.testing.expectEqual(@as(usize, 3), wide_after_cjk.column);

    const narrow_after_emoji = try editor.lineColumnAtByte(editor.slice().len, 4);
    try std.testing.expectEqual(@as(usize, 4), narrow_after_emoji.column);
    const wide_after_emoji = try editor.lineColumnAtByteWithWidth(editor.slice().len, 4, .east_asian);
    try std.testing.expectEqual(@as(usize, 6), wide_after_emoji.column);

    try std.testing.expectEqual(@as(usize, 1), editor.byteOffsetForLineColumnWithWidth(0, 1, 4, .east_asian));
    try std.testing.expectEqual(@as(usize, 1), editor.byteOffsetForLineColumnWithWidth(0, 2, 4, .east_asian));
    try std.testing.expectEqual(@as(usize, 4), editor.byteOffsetForLineColumnWithWidth(0, 3, 4, .east_asian));
    try std.testing.expectEqual(@as(usize, 5), editor.byteOffsetForLineColumnWithWidth(0, 4, 4, .east_asian));
}

test "TextEditor treats combining and joiner codepoints as zero width" {
    const allocator = std.testing.allocator;

    var combining = try TextEditor.initText(allocator, "a\u{0301}b");
    defer combining.deinit();
    try std.testing.expectEqual(@as(usize, 0), codepointDisplayWidth(0x0301, .east_asian));
    const after_combining = try combining.lineColumnAtByteWithWidth(3, 4, .east_asian);
    try std.testing.expectEqual(@as(usize, 1), after_combining.column);
    const after_b = try combining.lineColumnAtByteWithWidth(combining.slice().len, 4, .east_asian);
    try std.testing.expectEqual(@as(usize, 2), after_b.column);

    var emoji = try TextEditor.initText(allocator, "✌\u{fe0f}👍\u{1f3fd}👩\u{200d}💻");
    defer emoji.deinit();
    try std.testing.expectEqual(@as(usize, 0), codepointDisplayWidth(0xfe0f, .east_asian));
    try std.testing.expectEqual(@as(usize, 0), codepointDisplayWidth(0x1f3fd, .east_asian));
    try std.testing.expectEqual(@as(usize, 0), codepointDisplayWidth(0x200d, .east_asian));

    const emoji_end = try emoji.lineColumnAtByteWithWidth(emoji.slice().len, 4, .east_asian);
    try std.testing.expectEqual(@as(usize, 7), emoji_end.column);
}

test "TextEditor maps grapheme cluster display columns" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "A👩‍💻B");
    defer editor.deinit();

    const codepoint_columns = try editor.lineColumnAtByteWithWidth(editor.slice().len, 4, .east_asian);
    try std.testing.expectEqual(@as(usize, 6), codepoint_columns.column);

    const grapheme_columns = try editor.lineColumnAtByteGrapheme(editor.slice().len, 4, .east_asian);
    try std.testing.expectEqual(@as(usize, 4), grapheme_columns.column);

    try std.testing.expectEqual(@as(usize, 1), try editor.byteOffsetForLineColumnGrapheme(0, 1, 4, .east_asian));
    try std.testing.expectEqual(@as(usize, 1), try editor.byteOffsetForLineColumnGrapheme(0, 2, 4, .east_asian));
    try std.testing.expectEqual(@as(usize, 12), try editor.byteOffsetForLineColumnGrapheme(0, 3, 4, .east_asian));
}

test "TextEditor maps terminal columns while ignoring ANSI controls" {
    const allocator = std.testing.allocator;

    var editor = try TextEditor.initText(allocator, "A\x1b[31m一\x1b[0mB");
    defer editor.deinit();

    const end = try editor.terminalLineColumnAtByte(editor.slice().len, .{});
    try std.testing.expectEqual(@as(usize, 4), end.column);

    try std.testing.expectEqual(@as(usize, 6), editor.terminalByteOffsetForLineColumn(0, 1, .{}));
    try std.testing.expectEqual(@as(usize, 6), editor.terminalByteOffsetForLineColumn(0, 2, .{}));
    try std.testing.expectEqual(@as(usize, 14), editor.terminalByteOffsetForLineColumn(0, 4, .{}));

    const raw = try editor.terminalLineColumnAtByte(editor.slice().len, .{ .ignore_ansi = false, .width_mode = .narrow });
    try std.testing.expect(raw.column > end.column);
}

test "TextEditor ignores OSC DCS and C0 terminal controls" {
    const allocator = std.testing.allocator;

    var osc = try TextEditor.initText(allocator, "A\x1b]0;title\x07B");
    defer osc.deinit();
    const osc_end = try osc.terminalLineColumnAtByte(osc.slice().len, .{});
    try std.testing.expectEqual(@as(usize, 2), osc_end.column);
    try std.testing.expectEqual(@as(usize, 11), osc.terminalByteOffsetForLineColumn(0, 1, .{}));

    var dcs = try TextEditor.initText(allocator, "A\x1bPdata\x1b\\B");
    defer dcs.deinit();
    const dcs_end = try dcs.terminalLineColumnAtByte(dcs.slice().len, .{});
    try std.testing.expectEqual(@as(usize, 2), dcs_end.column);

    var controls = try TextEditor.initText(allocator, "A\x08\x0cB");
    defer controls.deinit();
    const controls_end = try controls.terminalLineColumnAtByte(controls.slice().len, .{});
    try std.testing.expectEqual(@as(usize, 2), controls_end.column);
}
