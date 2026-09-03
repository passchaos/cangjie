//! Incremental undo/redo history for chunked UTF-8 documents.
//!
//! Entries own only the removed and inserted bytes for each transaction. The
//! document itself remains the single text authority, and replay delegates to
//! `Document.replaceRange`, preserving its UTF-8 validation and allocation
//! failure atomicity. Transactions can merge adjacent forward typing edits
//! without copying or snapshotting the complete document.

const std = @import("std");
const document_mod = @import("root.zig");

pub const Document = document_mod.Document;
pub const DocumentError = document_mod.Error;
pub const ByteRange = document_mod.ByteRange;
pub const EditSummary = document_mod.EditSummary;

pub const Error = DocumentError || error{
    StaleDocument,
    InvalidTransaction,
    HistoryCapacityExceeded,
};

pub const Selection = struct {
    anchor: usize = 0,
    cursor: usize = 0,

    pub fn isValid(self: Selection, document: *const Document) bool {
        return self.anchor <= document.byteLen() and self.cursor <= document.byteLen() and
            document.isUtf8Boundary(self.anchor) and document.isUtf8Boundary(self.cursor);
    }
};

pub const Transaction = struct {
    start: usize,
    old_bytes: []u8,
    new_bytes: []u8,
    before_selection: Selection,
    after_selection: Selection,
    before_scroll_y: f64,
    after_scroll_y: f64,
    action_name: ActionName,

    fn deinit(self: *Transaction, allocator: std.mem.Allocator) void {
        allocator.free(self.old_bytes);
        allocator.free(self.new_bytes);
        self.* = undefined;
    }
};

pub const ActionName = struct {
    pub const capacity: usize = 48;

    bytes: [capacity]u8 = .{0} ** capacity,
    len: u8 = 0,

    pub fn init(value: []const u8) ActionName {
        var out = ActionName{};
        const source = if (std.unicode.utf8ValidateSlice(value)) value else "Text Edit";
        var len = @min(source.len, capacity);
        while (len > 0 and len < source.len and source[len] & 0xc0 == 0x80) len -= 1;
        if (len != 0) @memcpy(out.bytes[0..len], source[0..len]);
        out.len = @intCast(len);
        return out;
    }

    pub fn slice(self: *const ActionName) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const RecordOptions = struct {
    before_selection: Selection,
    after_selection: Selection,
    before_scroll_y: f64 = 0.0,
    after_scroll_y: f64 = 0.0,
    action_name: []const u8 = "Text Edit",
    merge_adjacent: bool = false,
};

pub const Replay = struct {
    edit: EditSummary,
    selection: Selection,
    scroll_y: f64,
    action_name: ActionName,
};

pub const ReplaceResult = struct {
    edit: EditSummary,
    recorded: bool,
};

pub const Diagnostics = struct {
    undo_entries: usize,
    redo_entries: usize,
    payload_bytes: usize,
    retained_bytes: usize,
    revision: u64,
    recorded_count: u64,
    merged_count: u64,
    undo_count: u64,
    redo_count: u64,
    eviction_count: u64,
    failure_count: u64,
};

pub const History = struct {
    allocator: std.mem.Allocator,
    max_entries: usize,
    max_payload_bytes: usize,
    undo_stack: std.ArrayList(Transaction) = .empty,
    redo_stack: std.ArrayList(Transaction) = .empty,
    payload_bytes: usize = 0,
    document_identity: usize = 0,
    expected_revision: u64 = 0,
    history_revision: u64 = 1,
    recorded_count: u64 = 0,
    merged_count: u64 = 0,
    undo_count: u64 = 0,
    redo_count: u64 = 0,
    eviction_count: u64 = 0,
    failure_count: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize, max_payload_bytes: usize) History {
        return .{ .allocator = allocator, .max_entries = max_entries, .max_payload_bytes = max_payload_bytes };
    }

    pub fn deinit(self: *History) void {
        self.clearStack(&self.undo_stack);
        self.clearStack(&self.redo_stack);
        self.undo_stack.deinit(self.allocator);
        self.redo_stack.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn canUndo(self: *const History, document: *const Document) bool {
        return self.currentFor(document) and self.undo_stack.items.len != 0;
    }

    pub fn canRedo(self: *const History, document: *const Document) bool {
        return self.currentFor(document) and self.redo_stack.items.len != 0;
    }

    pub fn undoActionName(self: *const History) ?[]const u8 {
        if (self.undo_stack.items.len == 0) return null;
        return self.undo_stack.items[self.undo_stack.items.len - 1].action_name.slice();
    }

    pub fn redoActionName(self: *const History) ?[]const u8 {
        if (self.redo_stack.items.len == 0) return null;
        return self.redo_stack.items[self.redo_stack.items.len - 1].action_name.slice();
    }

    pub fn revision(self: *const History) u64 {
        return self.history_revision;
    }

    pub fn ownsDocument(self: *const History, document: *const Document) bool {
        return self.document_identity == 0 or self.document_identity == @intFromPtr(document);
    }

    pub fn attach(self: *History, document: *const Document) Error!void {
        if (!self.ownsDocument(document)) return error.StaleDocument;
        if (self.document_identity != 0 and self.expected_revision != document.revision()) return error.StaleDocument;
        self.bind(document);
    }

    /// Refines the interaction state stored by the newest edit after the UI
    /// has completed caret reveal. This never changes text or allocates.
    pub fn updateLastAfterState(self: *History, document: *const Document, selection: Selection, scroll_y: f64) Error!bool {
        if (!self.currentFor(document)) return error.StaleDocument;
        if (!selection.isValid(document) or !std.math.isFinite(scroll_y) or scroll_y < 0.0) return error.InvalidTransaction;
        if (self.undo_stack.items.len == 0 or self.redo_stack.items.len != 0) return false;
        const entry = &self.undo_stack.items[self.undo_stack.items.len - 1];
        if (std.meta.eql(entry.after_selection, selection) and entry.after_scroll_y == scroll_y) return false;
        entry.after_selection = selection;
        entry.after_scroll_y = scroll_y;
        self.bumpRevision();
        return true;
    }

    /// Atomically edits the document and records its inverse. All history
    /// allocations and capacity checks complete before the document mutation.
    pub fn replaceRange(
        self: *History,
        document: *Document,
        start: usize,
        end: usize,
        replacement: []const u8,
        options: RecordOptions,
    ) Error!?ReplaceResult {
        return self.replaceRangeInner(document, start, end, replacement, options) catch |err| {
            self.failure_count +%= 1;
            return err;
        };
    }

    fn replaceRangeInner(
        self: *History,
        document: *Document,
        start: usize,
        end: usize,
        replacement: []const u8,
        options: RecordOptions,
    ) Error!?ReplaceResult {
        if (!options.before_selection.isValid(document) or start > end or end > document.byteLen() or
            !document.isUtf8Boundary(start) or !document.isUtf8Boundary(end) or !std.unicode.utf8ValidateSlice(replacement))
            return error.InvalidTransaction;
        const old_len = end - start;
        const next_len = std.math.add(usize, document.byteLen() -| old_len, replacement.len) catch return error.Overflow;
        if (!selectionValidAfter(options.after_selection, document, start, end, replacement, next_len)) return error.InvalidTransaction;
        if (start == end and replacement.len == 0) return null;
        if (self.document_identity != 0 and self.document_identity != @intFromPtr(document)) return error.StaleDocument;
        if (self.expected_revision != 0 and self.expected_revision != document.revision()) self.clear();
        const payload = std.math.add(usize, old_len, replacement.len) catch return error.Overflow;
        if (self.max_entries == 0 or payload > self.max_payload_bytes) return error.HistoryCapacityExceeded;

        const old_copy = try self.allocator.alloc(u8, old_len);
        errdefer self.allocator.free(old_copy);
        _ = try document.copyRange(.{ .start = start, .end = end }, old_copy);
        if (std.mem.eql(u8, old_copy, replacement)) {
            self.allocator.free(old_copy);
            return null;
        }
        const new_copy = try self.allocator.dupe(u8, replacement);
        errdefer self.allocator.free(new_copy);
        try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);
        const action_name = ActionName.init(options.action_name);
        const merge = options.merge_adjacent and self.redo_stack.items.len == 0 and self.undo_stack.items.len != 0 and
            old_len == 0 and self.undo_stack.items[self.undo_stack.items.len - 1].old_bytes.len == 0 and
            start == self.undo_stack.items[self.undo_stack.items.len - 1].start + self.undo_stack.items[self.undo_stack.items.len - 1].new_bytes.len and
            std.meta.eql(self.undo_stack.items[self.undo_stack.items.len - 1].after_selection, options.before_selection) and
            std.mem.eql(u8, self.undo_stack.items[self.undo_stack.items.len - 1].action_name.slice(), action_name.slice());
        var merged: ?[]u8 = null;
        if (merge) {
            const previous = self.undo_stack.items[self.undo_stack.items.len - 1].new_bytes;
            const merged_len = std.math.add(usize, previous.len, replacement.len) catch return error.Overflow;
            if (merged_len <= self.max_payload_bytes and self.payload_bytes - previous.len <= self.max_payload_bytes - merged_len) {
                merged = try self.allocator.alloc(u8, merged_len);
                @memcpy(merged.?[0..previous.len], previous);
                @memcpy(merged.?[previous.len..], replacement);
            }
        }
        errdefer if (merged) |bytes| self.allocator.free(bytes);

        const edit = (try document.replaceRange(start, end, replacement)) orelse {
            self.allocator.free(old_copy);
            self.allocator.free(new_copy);
            if (merged) |bytes| self.allocator.free(bytes);
            return null;
        };

        if (merged) |bytes| {
            var entry = &self.undo_stack.items[self.undo_stack.items.len - 1];
            self.payload_bytes -= entry.new_bytes.len;
            self.allocator.free(entry.new_bytes);
            entry.new_bytes = bytes;
            entry.after_selection = options.after_selection;
            entry.after_scroll_y = options.after_scroll_y;
            self.payload_bytes += bytes.len;
            self.allocator.free(old_copy);
            self.allocator.free(new_copy);
            self.bind(document);
            self.merged_count +%= 1;
            self.bumpRevision();
            return .{ .edit = edit, .recorded = true };
        }
        self.clearStack(&self.redo_stack);
        while (self.undo_stack.items.len >= self.max_entries or self.payload_bytes > self.max_payload_bytes - payload) {
            self.evictOldest(&self.undo_stack);
        }
        self.undo_stack.appendAssumeCapacity(.{
            .start = start,
            .old_bytes = old_copy,
            .new_bytes = new_copy,
            .before_selection = options.before_selection,
            .after_selection = options.after_selection,
            .before_scroll_y = options.before_scroll_y,
            .after_scroll_y = options.after_scroll_y,
            .action_name = action_name,
        });
        self.payload_bytes += payload;
        self.bind(document);
        self.recorded_count +%= 1;
        self.bumpRevision();
        return .{ .edit = edit, .recorded = true };
    }

    pub fn undo(self: *History, document: *Document) Error!?Replay {
        return self.replay(document, .undo) catch |err| {
            self.failure_count +%= 1;
            return err;
        };
    }

    pub fn redo(self: *History, document: *Document) Error!?Replay {
        return self.replay(document, .redo) catch |err| {
            self.failure_count +%= 1;
            return err;
        };
    }

    pub fn clear(self: *History) void {
        self.clearStack(&self.undo_stack);
        self.clearStack(&self.redo_stack);
        self.document_identity = 0;
        self.expected_revision = 0;
        self.bumpRevision();
    }

    pub fn diagnostics(self: *const History) Diagnostics {
        return .{
            .undo_entries = self.undo_stack.items.len,
            .redo_entries = self.redo_stack.items.len,
            .payload_bytes = self.payload_bytes,
            .retained_bytes = self.undo_stack.capacity * @sizeOf(Transaction) + self.redo_stack.capacity * @sizeOf(Transaction) + self.payload_bytes,
            .revision = self.history_revision,
            .recorded_count = self.recorded_count,
            .merged_count = self.merged_count,
            .undo_count = self.undo_count,
            .redo_count = self.redo_count,
            .eviction_count = self.eviction_count,
            .failure_count = self.failure_count,
        };
    }

    const Direction = enum { undo, redo };

    fn replay(self: *History, document: *Document, direction: Direction) Error!?Replay {
        const source = if (direction == .undo) &self.undo_stack else &self.redo_stack;
        const destination = if (direction == .undo) &self.redo_stack else &self.undo_stack;
        if (source.items.len == 0) return null;
        if (!self.currentFor(document)) return error.StaleDocument;
        const entry = source.getLastOrNull() orelse return null;
        const expected = if (direction == .undo) entry.new_bytes else entry.old_bytes;
        const replacement = if (direction == .undo) entry.old_bytes else entry.new_bytes;
        const end = std.math.add(usize, entry.start, expected.len) catch return error.Overflow;
        if (!try rangeEql(document, .{ .start = entry.start, .end = end }, expected)) return error.StaleDocument;
        try destination.ensureUnusedCapacity(self.allocator, 1);
        try document.reserveReplacementCapacity(&.{ replacement, expected });
        const edit = (try document.replaceRange(entry.start, end, replacement)) orelse return error.InvalidTransaction;
        const selection = if (direction == .undo) entry.before_selection else entry.after_selection;
        const scroll_y = if (direction == .undo) entry.before_scroll_y else entry.after_scroll_y;
        const action_name = entry.action_name;

        const moved = source.pop().?;
        destination.appendAssumeCapacity(moved);
        self.expected_revision = document.revision();
        if (direction == .undo) self.undo_count +%= 1 else self.redo_count +%= 1;
        self.bumpRevision();
        return .{
            .edit = edit,
            .selection = selection,
            .scroll_y = scroll_y,
            .action_name = action_name,
        };
    }

    fn bind(self: *History, document: *const Document) void {
        self.document_identity = @intFromPtr(document);
        self.expected_revision = document.revision();
    }

    fn currentFor(self: *const History, document: *const Document) bool {
        return self.document_identity == @intFromPtr(document) and self.expected_revision == document.revision();
    }

    fn clearStack(self: *History, stack: *std.ArrayList(Transaction)) void {
        for (stack.items) |*entry| {
            self.payload_bytes -= entry.old_bytes.len + entry.new_bytes.len;
            entry.deinit(self.allocator);
        }
        stack.clearRetainingCapacity();
    }

    fn evictOldest(self: *History, stack: *std.ArrayList(Transaction)) void {
        var entry = stack.orderedRemove(0);
        self.payload_bytes -= entry.old_bytes.len + entry.new_bytes.len;
        entry.deinit(self.allocator);
        self.eviction_count +%= 1;
    }

    fn bumpRevision(self: *History) void {
        self.history_revision +%= 1;
        if (self.history_revision == 0) self.history_revision = 1;
    }
};

fn rangeEql(document: *const Document, range: ByteRange, expected: []const u8) Error!bool {
    if (range.len() != expected.len) return false;
    var iterator = try document.chunks(range);
    var cursor: usize = 0;
    while (iterator.next()) |chunk| {
        if (!std.mem.eql(u8, chunk.bytes, expected[cursor..][0..chunk.bytes.len])) return false;
        cursor += chunk.bytes.len;
    }
    return cursor == expected.len;
}

fn selectionValidAfter(selection: Selection, document: *const Document, start: usize, end: usize, replacement: []const u8, next_len: usize) bool {
    return positionValidAfter(selection.anchor, document, start, end, replacement, next_len) and
        positionValidAfter(selection.cursor, document, start, end, replacement, next_len);
}

fn positionValidAfter(position: usize, document: *const Document, start: usize, end: usize, replacement: []const u8, next_len: usize) bool {
    if (position > next_len) return false;
    const inserted_end = start +| replacement.len;
    if (position < start) return document.isUtf8Boundary(position);
    if (position <= inserted_end) {
        const local = position - start;
        return local == 0 or local == replacement.len or replacement[local] & 0xc0 != 0x80;
    }
    const original = position - replacement.len + (end - start);
    return document.isUtf8Boundary(original);
}

test "document history undoes and redoes variable length UTF-8 edits" {
    var document = try Document.init(std.testing.allocator, "zero\none\ntwo");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();

    const result = (try history.replaceRange(&document, 5, 8, "中间\n", .{
        .before_selection = .{ .anchor = 5, .cursor = 8 },
        .after_selection = .{ .anchor = 12, .cursor = 12 },
        .action_name = "Replace",
    })).?;
    try std.testing.expect(result.recorded);
    const undo = (try history.undo(&document)).?;
    try std.testing.expectEqual(Selection{ .anchor = 5, .cursor = 8 }, undo.selection);
    const bytes = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("zero\none\ntwo", bytes);
    const redo = (try history.redo(&document)).?;
    try std.testing.expectEqual(Selection{ .anchor = 12, .cursor = 12 }, redo.selection);
    const redone = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(redone);
    try std.testing.expectEqualStrings("zero\n中间\n\ntwo", redone);
}

test "document history merges adjacent typing and invalidates redo" {
    var document = try Document.init(std.testing.allocator, "tail");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();
    for ([_][]const u8{ "a", "中", "b" }) |bytes| {
        const start = document.byteLen() - 4;
        _ = (try history.replaceRange(&document, start, start, bytes, .{
            .before_selection = .{ .anchor = start, .cursor = start },
            .after_selection = .{ .anchor = start + bytes.len, .cursor = start + bytes.len },
            .action_name = "Typing",
            .merge_adjacent = true,
        })).?;
    }
    try std.testing.expectEqual(@as(usize, 1), history.diagnostics().undo_entries);
    try std.testing.expectEqual(@as(u64, 2), history.diagnostics().merged_count);
    _ = try history.undo(&document);
    try std.testing.expect(history.canRedo(&document));
    _ = (try history.replaceRange(&document, 0, 0, "x", .{
        .before_selection = .{},
        .after_selection = .{ .anchor = 1, .cursor = 1 },
    })).?;
    try std.testing.expect(!history.canRedo(&document));
}

test "document history allocation failures leave document and stacks unchanged" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        struct {
            fn run(allocator: std.mem.Allocator) !void {
                var document = try Document.init(allocator, "alpha\nbeta");
                defer document.deinit();
                var history = History.init(allocator, 8, 1024);
                defer history.deinit();
                const revision = document.revision();
                const result = history.replaceRange(&document, 0, 5, "expanded", .{
                    .before_selection = .{ .anchor = 0, .cursor = 5 },
                    .after_selection = .{ .anchor = 8, .cursor = 8 },
                });
                if (result) |optional| {
                    _ = optional orelse return error.ExpectedRecordedEdit;
                    try std.testing.expectEqual(revision + 1, document.revision());
                    try std.testing.expectEqual(@as(usize, 1), history.diagnostics().undo_entries);
                } else |err| {
                    if (err != error.OutOfMemory) return err;
                    try std.testing.expectEqual(revision, document.revision());
                    try std.testing.expectEqual(@as(usize, 0), history.diagnostics().undo_entries);
                    const bytes = try document.materialize(std.testing.allocator);
                    defer std.testing.allocator.free(bytes);
                    try std.testing.expectEqualStrings("alpha\nbeta", bytes);
                    return error.OutOfMemory;
                }
            }
        }.run,
        .{},
    );
}

test "document history stale replay preserves document and stack" {
    var document = try Document.init(std.testing.allocator, "abc");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();
    _ = (try history.replaceRange(&document, 1, 2, "XYZ", .{
        .before_selection = .{ .anchor = 1, .cursor = 2 },
        .after_selection = .{ .anchor = 4, .cursor = 4 },
    })).?;
    _ = try document.replaceRange(0, 0, "!");
    try std.testing.expectError(error.StaleDocument, history.undo(&document));
    try std.testing.expectEqual(@as(usize, 1), history.diagnostics().undo_entries);
    try std.testing.expectEqual(@as(usize, 0), history.diagnostics().redo_entries);
    const bytes = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("!aXYZc", bytes);
}

test "document history external edit starts a fresh branch on next record" {
    var document = try Document.init(std.testing.allocator, "abc");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();
    _ = (try history.replaceRange(&document, 1, 2, "X", .{
        .before_selection = .{ .anchor = 1, .cursor = 2 },
        .after_selection = .{ .anchor = 2, .cursor = 2 },
    })).?;
    _ = try document.replaceRange(0, 0, "!");
    _ = (try history.replaceRange(&document, document.byteLen(), document.byteLen(), "?", .{
        .before_selection = .{ .anchor = document.byteLen(), .cursor = document.byteLen() },
        .after_selection = .{ .anchor = document.byteLen() + 1, .cursor = document.byteLen() + 1 },
    })).?;
    try std.testing.expectEqual(@as(usize, 1), history.diagnostics().undo_entries);
    try std.testing.expectEqual(@as(usize, 0), history.diagnostics().redo_entries);
    _ = try history.undo(&document);
    const bytes = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("!aXc", bytes);
}

test "document history replay allocation failure does not move stacks" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var document = try Document.init(failing.allocator(), "abc");
    defer document.deinit();
    var history = History.init(failing.allocator(), 8, 1024);
    defer history.deinit();
    _ = (try history.replaceRange(&document, 1, 2, "XYZ", .{
        .before_selection = .{ .anchor = 1, .cursor = 2 },
        .after_selection = .{ .anchor = 4, .cursor = 4 },
    })).?;
    const revision = document.revision();
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, history.undo(&document));
    try std.testing.expectEqual(revision, document.revision());
    try std.testing.expectEqual(@as(usize, 1), history.diagnostics().undo_entries);
    try std.testing.expectEqual(@as(usize, 0), history.diagnostics().redo_entries);
    const bytes = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("aXYZc", bytes);
}

test "document history replay remains reversible after later allocator failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var document = try Document.init(failing.allocator(), "abc");
    defer document.deinit();
    var history = History.init(failing.allocator(), 8, 1024);
    defer history.deinit();
    _ = (try history.replaceRange(&document, 1, 2, "XYZ", .{
        .before_selection = .{ .anchor = 1, .cursor = 2 },
        .after_selection = .{ .anchor = 4, .cursor = 4 },
    })).?;
    _ = (try history.undo(&document)).?;
    failing.fail_index = failing.alloc_index;
    _ = (try history.redo(&document)).?;
    _ = (try history.undo(&document)).?;
    const bytes = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("abc", bytes);
}

test "document history enforces payload budget and evicts oldest transaction" {
    var document = try Document.init(std.testing.allocator, "abcdef");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 2, 6);
    defer history.deinit();
    _ = (try history.replaceRange(&document, 0, 1, "A", .{ .before_selection = .{}, .after_selection = .{ .anchor = 1, .cursor = 1 } })).?;
    _ = (try history.replaceRange(&document, 1, 2, "B", .{ .before_selection = .{ .anchor = 1, .cursor = 1 }, .after_selection = .{ .anchor = 2, .cursor = 2 } })).?;
    _ = (try history.replaceRange(&document, 2, 3, "C", .{ .before_selection = .{ .anchor = 2, .cursor = 2 }, .after_selection = .{ .anchor = 3, .cursor = 3 } })).?;
    try std.testing.expectEqual(@as(usize, 2), history.diagnostics().undo_entries);
    try std.testing.expectEqual(@as(u64, 1), history.diagnostics().eviction_count);
    try std.testing.expectError(error.HistoryCapacityExceeded, history.replaceRange(&document, 0, 1, "01234567", .{
        .before_selection = .{},
        .after_selection = .{ .anchor = 8, .cursor = 8 },
    }));
    const bytes = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("ABCdef", bytes);
}

test "empty document history is an ordinary no-op before first edit" {
    var document = try Document.init(std.testing.allocator, "abc");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();
    try std.testing.expect((try history.undo(&document)) == null);
    try std.testing.expect((try history.redo(&document)) == null);
    try std.testing.expect(!history.canUndo(&document));
    try std.testing.expect(!history.canRedo(&document));
}

test "document history attachment rejects a different document" {
    var first = try Document.init(std.testing.allocator, "first");
    defer first.deinit();
    var second = try Document.init(std.testing.allocator, "second");
    defer second.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();
    try history.attach(&first);
    try std.testing.expectError(error.StaleDocument, history.attach(&second));
    try std.testing.expectError(error.StaleDocument, history.replaceRange(&second, 0, 0, "x", .{
        .before_selection = .{},
        .after_selection = .{ .anchor = 1, .cursor = 1 },
    }));
}

test "document history ignores semantic no-op replacements" {
    var document = try Document.init(std.testing.allocator, "abc");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();
    try history.attach(&document);
    const revision = document.revision();
    try std.testing.expect((try history.replaceRange(&document, 1, 2, "b", .{
        .before_selection = .{ .anchor = 1, .cursor = 2 },
        .after_selection = .{ .anchor = 2, .cursor = 2 },
    })) == null);
    try std.testing.expectEqual(revision, document.revision());
    try std.testing.expectEqual(@as(usize, 0), history.diagnostics().undo_entries);
}

test "document history refines post-edit selection and viewport without allocation" {
    var document = try Document.init(std.testing.allocator, "abc");
    defer document.deinit();
    var history = History.init(std.testing.allocator, 8, 1024);
    defer history.deinit();
    _ = (try history.replaceRange(&document, 1, 1, "中", .{
        .before_selection = .{ .anchor = 1, .cursor = 1 },
        .after_selection = .{ .anchor = 4, .cursor = 4 },
    })).?;
    try std.testing.expect(try history.updateLastAfterState(&document, .{ .anchor = 4, .cursor = 4 }, 72));
    const undo = (try history.undo(&document)).?;
    try std.testing.expectEqual(@as(f64, 0), undo.scroll_y);
    const redo = (try history.redo(&document)).?;
    try std.testing.expectEqual(@as(f64, 72), redo.scroll_y);
    try std.testing.expectEqual(Selection{ .anchor = 4, .cursor = 4 }, redo.selection);
}
