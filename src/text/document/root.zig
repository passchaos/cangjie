//! Mutable chunked UTF-8 document storage.
//!
//! The document owns immutable original/add buffers and stores byte ranges as
//! an implicit treap. Subtree summaries make byte/line queries logarithmic,
//! while edits append replacement bytes and splice only the affected pieces.
//! Cursor, selection, history, layout and widgets deliberately remain outside
//! this reusable text-core boundary.

const std = @import("std");

pub const max_piece_bytes: usize = 4096;

pub const Error = std.mem.Allocator.Error || error{
    InvalidUtf8,
    InvalidRange,
    InvalidUtf8Boundary,
    NoSpaceLeft,
    Overflow,
};

pub const ByteRange = struct {
    start: usize,
    end: usize,

    pub fn len(self: ByteRange) usize {
        return self.end - self.start;
    }
};

/// UTF-8 byte point. `column` is a byte offset from the hard-line start;
/// grapheme/UTF-16 projections are intentionally owned by segmentation APIs.
pub const Point = struct {
    line: usize,
    column: usize,
};

pub const EditSummary = struct {
    revision: u64,
    start: usize,
    old_end: usize,
    new_end: usize,
    old_bytes: usize,
    new_bytes: usize,
    old_newlines: usize,
    new_newlines: usize,
};

pub const Diagnostics = struct {
    bytes: usize,
    newlines: usize,
    lines: usize,
    pieces: usize,
    node_slots: usize,
    tree_depth: usize,
    original_bytes: usize,
    addition_bytes: usize,
    owned_bytes: usize,
};

const Source = enum(u8) { original, additions };

const Summary = struct {
    bytes: usize = 0,
    newlines: usize = 0,
    trailing_bytes: usize = 0,

    fn combine(a: Summary, b: Summary) Summary {
        return .{
            .bytes = a.bytes + b.bytes,
            .newlines = a.newlines + b.newlines,
            .trailing_bytes = if (b.newlines == 0) a.trailing_bytes + b.bytes else b.trailing_bytes,
        };
    }
};

const Piece = struct {
    source: Source,
    start: usize,
    len: usize,
    summary: Summary,
};

const Node = struct {
    piece: Piece,
    left: ?usize = null,
    right: ?usize = null,
    priority: u64,
    summary: Summary,
    piece_count: usize = 1,
    next_free: ?usize = null,
};

const Split = struct { left: ?usize, right: ?usize };
const Location = struct { node: usize, local: usize, global_start: usize };

pub const Chunk = struct {
    bytes: []const u8,
    byte_start: usize,
    byte_end: usize,
};

pub const ChunkIterator = struct {
    document: *const Document,
    cursor: usize,
    end: usize,

    /// Returned slices borrow the document and are invalidated by mutation.
    pub fn next(self: *ChunkIterator) ?Chunk {
        if (self.cursor >= self.end) return null;
        const location = self.document.locate(self.cursor) orelse return null;
        const node = self.document.nodes.items[location.node];
        const piece_bytes = self.document.pieceBytes(node.piece);
        const count = @min(piece_bytes.len - location.local, self.end - self.cursor);
        const start = self.cursor;
        self.cursor += count;
        return .{
            .bytes = piece_bytes[location.local .. location.local + count],
            .byte_start = start,
            .byte_end = self.cursor,
        };
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    original: []u8 = &.{},
    additions: std.ArrayList(u8) = .empty,
    nodes: std.ArrayList(Node) = .empty,
    root: ?usize = null,
    free_head: ?usize = null,
    live_pieces: usize = 0,
    priority_sequence: u64 = 0,
    source_revision: u64 = 0,
    last_edit: ?EditSummary = null,

    pub fn init(allocator: std.mem.Allocator, text: []const u8) Error!Document {
        if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
        var self = Document{ .allocator = allocator };
        errdefer self.deinit();
        self.original = try allocator.dupe(u8, text);
        const count = pieceCountForBytes(text);
        try self.nodes.ensureTotalCapacity(allocator, count);
        self.root = self.buildPieces(.original, 0, text);
        return self;
    }

    pub fn deinit(self: *Document) void {
        self.nodes.deinit(self.allocator);
        self.additions.deinit(self.allocator);
        if (self.original.len != 0) self.allocator.free(self.original);
        self.* = undefined;
    }

    pub fn byteLen(self: *const Document) usize {
        return self.nodeSummary(self.root).bytes;
    }

    pub fn newlineCount(self: *const Document) usize {
        return self.nodeSummary(self.root).newlines;
    }

    pub fn lineCount(self: *const Document) usize {
        return self.newlineCount() + 1;
    }

    pub fn pieceCount(self: *const Document) usize {
        return self.live_pieces;
    }

    pub fn revision(self: *const Document) u64 {
        return self.source_revision;
    }

    pub fn editSince(self: *const Document, previous_revision: u64) ?EditSummary {
        const edit = self.last_edit orelse return null;
        if (previous_revision +% 1 != self.source_revision or edit.revision != self.source_revision) return null;
        return edit;
    }

    pub fn isUtf8Boundary(self: *const Document, offset: usize) bool {
        if (offset > self.byteLen()) return false;
        if (offset == 0 or offset == self.byteLen()) return true;
        const location = self.locate(offset) orelse return false;
        if (location.local == 0) return true;
        return (self.pieceBytes(self.nodes.items[location.node].piece)[location.local] & 0xc0) != 0x80;
    }

    pub fn chunks(self: *const Document, range: ByteRange) Error!ChunkIterator {
        try self.validateRange(range.start, range.end);
        return .{ .document = self, .cursor = range.start, .end = range.end };
    }

    pub fn materialize(self: *const Document, allocator: std.mem.Allocator) Error![]u8 {
        const out = try allocator.alloc(u8, self.byteLen());
        errdefer allocator.free(out);
        _ = try self.copyRange(.{ .start = 0, .end = self.byteLen() }, out);
        return out;
    }

    pub fn copyRange(self: *const Document, range: ByteRange, out: []u8) Error!usize {
        try self.validateRange(range.start, range.end);
        if (out.len < range.len()) return error.NoSpaceLeft;
        var iterator = ChunkIterator{ .document = self, .cursor = range.start, .end = range.end };
        var written: usize = 0;
        while (iterator.next()) |chunk| {
            @memcpy(out[written..][0..chunk.bytes.len], chunk.bytes);
            written += chunk.bytes.len;
        }
        return written;
    }

    pub fn pointForByte(self: *const Document, offset: usize) Error!Point {
        if (offset > self.byteLen()) return error.InvalidRange;
        if (!self.isUtf8Boundary(offset)) return error.InvalidUtf8Boundary;
        const summary = self.prefixSummary(self.root, offset);
        return .{ .line = summary.newlines, .column = summary.trailing_bytes };
    }

    pub fn lineStart(self: *const Document, line: usize) Error!usize {
        if (line >= self.lineCount()) return error.InvalidRange;
        if (line == 0) return 0;
        return self.byteAfterNewline(line - 1) orelse error.InvalidRange;
    }

    pub fn lineRange(self: *const Document, line: usize) Error!ByteRange {
        const start = try self.lineStart(line);
        const end = if (line + 1 < self.lineCount()) (try self.lineStart(line + 1)) - 1 else self.byteLen();
        return .{ .start = start, .end = end };
    }

    pub fn byteForPoint(self: *const Document, point: Point) Error!usize {
        const range = try self.lineRange(point.line);
        if (point.column > range.len()) return error.InvalidRange;
        const offset = range.start + point.column;
        if (!self.isUtf8Boundary(offset)) return error.InvalidUtf8Boundary;
        return offset;
    }

    /// Replace one UTF-8 byte range. The edit is atomic with respect to
    /// allocation failure: storage and node capacity are reserved before the
    /// treap is modified. Empty insertion is a no-op and returns null.
    pub fn replaceRange(self: *Document, start: usize, end: usize, replacement: []const u8) Error!?EditSummary {
        try self.validateRange(start, end);
        if (!std.unicode.utf8ValidateSlice(replacement)) return error.InvalidUtf8;
        if (start == end and replacement.len == 0) return null;

        const old_bytes = end - start;
        const old_newlines = self.prefixSummary(self.root, end).newlines - self.prefixSummary(self.root, start).newlines;
        const new_summary = summarize(replacement);
        const retained_bytes = self.byteLen() - old_bytes;
        _ = std.math.add(usize, retained_bytes, replacement.len) catch return error.Overflow;
        const add_start = self.additions.items.len;
        const add_end = std.math.add(usize, add_start, replacement.len) catch return error.Overflow;
        const required_nodes = std.math.add(usize, pieceCountForBytes(replacement), 2) catch return error.Overflow;
        const total_slots = std.math.add(usize, self.nodes.items.len, required_nodes) catch return error.Overflow;
        try self.nodes.ensureTotalCapacity(self.allocator, total_slots);
        try self.additions.ensureTotalCapacity(self.allocator, add_end);
        self.additions.appendSliceAssumeCapacity(replacement);

        const left_and_rest = self.split(self.root, start);
        const removed_and_right = self.split(left_and_rest.right, old_bytes);
        self.recycleTree(removed_and_right.left);
        const inserted = self.buildPieces(.additions, add_start, replacement);
        self.root = self.mergeCoalesced(self.mergeCoalesced(left_and_rest.left, inserted), removed_and_right.right);

        self.source_revision +%= 1;
        if (self.source_revision == 0) self.source_revision = 1;
        const new_end = start + replacement.len;
        const edit = EditSummary{
            .revision = self.source_revision,
            .start = start,
            .old_end = end,
            .new_end = new_end,
            .old_bytes = old_bytes,
            .new_bytes = replacement.len,
            .old_newlines = old_newlines,
            .new_newlines = new_summary.newlines,
        };
        self.last_edit = edit;
        return edit;
    }

    pub fn compact(self: *Document) Error!void {
        const bytes = try self.materialize(self.allocator);
        defer self.allocator.free(bytes);
        var replacement = try Document.init(self.allocator, bytes);
        replacement.source_revision = self.source_revision +% 1;
        if (replacement.source_revision == 0) replacement.source_revision = 1;
        std.mem.swap(Document, self, &replacement);
        replacement.deinit();
    }

    pub fn diagnostics(self: *const Document) Diagnostics {
        return .{
            .bytes = self.byteLen(),
            .newlines = self.newlineCount(),
            .lines = self.lineCount(),
            .pieces = self.live_pieces,
            .node_slots = self.nodes.items.len,
            .tree_depth = self.depth(self.root),
            .original_bytes = self.original.len,
            .addition_bytes = self.additions.items.len,
            .owned_bytes = self.original.len + self.additions.capacity + self.nodes.capacity * @sizeOf(Node),
        };
    }

    fn validateRange(self: *const Document, start: usize, end: usize) Error!void {
        if (start > end or end > self.byteLen()) return error.InvalidRange;
        if (!self.isUtf8Boundary(start) or !self.isUtf8Boundary(end)) return error.InvalidUtf8Boundary;
    }

    fn pieceBytes(self: *const Document, piece: Piece) []const u8 {
        const source = switch (piece.source) {
            .original => self.original,
            .additions => self.additions.items,
        };
        return source[piece.start .. piece.start + piece.len];
    }

    fn nodeSummary(self: *const Document, index: ?usize) Summary {
        return if (index) |value| self.nodes.items[value].summary else .{};
    }

    fn nodePieceCount(self: *const Document, index: ?usize) usize {
        return if (index) |value| self.nodes.items[value].piece_count else 0;
    }

    fn pull(self: *Document, index: usize) void {
        const node = &self.nodes.items[index];
        node.summary = Summary.combine(Summary.combine(self.nodeSummary(node.left), node.piece.summary), self.nodeSummary(node.right));
        node.piece_count = self.nodePieceCount(node.left) + 1 + self.nodePieceCount(node.right);
    }

    fn nextPriority(self: *Document) u64 {
        self.priority_sequence +%= 0x9e37_79b9_7f4a_7c15;
        var value = self.priority_sequence;
        value = (value ^ (value >> 30)) *% 0xbf58_476d_1ce4_e5b9;
        value = (value ^ (value >> 27)) *% 0x94d0_49bb_1331_11eb;
        return value ^ (value >> 31);
    }

    fn allocNodeAssumeCapacity(self: *Document, piece: Piece) usize {
        const node = Node{ .piece = piece, .priority = self.nextPriority(), .summary = piece.summary };
        const index = if (self.free_head) |free| blk: {
            self.free_head = self.nodes.items[free].next_free;
            self.nodes.items[free] = node;
            break :blk free;
        } else blk: {
            self.nodes.appendAssumeCapacity(node);
            break :blk self.nodes.items.len - 1;
        };
        self.live_pieces += 1;
        return index;
    }

    fn recycleTree(self: *Document, root: ?usize) void {
        const index = root orelse return;
        const left = self.nodes.items[index].left;
        const right = self.nodes.items[index].right;
        self.recycleTree(left);
        self.recycleTree(right);
        self.nodes.items[index].next_free = self.free_head;
        self.nodes.items[index].left = null;
        self.nodes.items[index].right = null;
        self.free_head = index;
        self.live_pieces -= 1;
    }

    fn buildPieces(self: *Document, source: Source, source_start: usize, bytes: []const u8) ?usize {
        var root: ?usize = null;
        var cursor: usize = 0;
        while (cursor < bytes.len) {
            const end = chunkEnd(bytes, cursor);
            const slice = bytes[cursor..end];
            const node = self.allocNodeAssumeCapacity(.{
                .source = source,
                .start = source_start + cursor,
                .len = slice.len,
                .summary = summarize(slice),
            });
            root = self.merge(root, node);
            cursor = end;
        }
        return root;
    }

    fn higherPriority(self: *const Document, a: usize, b: usize) bool {
        const lhs = self.nodes.items[a].priority;
        const rhs = self.nodes.items[b].priority;
        return lhs > rhs or (lhs == rhs and a > b);
    }

    fn merge(self: *Document, left: ?usize, right: ?usize) ?usize {
        const a = left orelse return right;
        const b = right orelse return left;
        if (self.higherPriority(a, b)) {
            self.nodes.items[a].right = self.merge(self.nodes.items[a].right, right);
            self.pull(a);
            return a;
        }
        self.nodes.items[b].left = self.merge(left, self.nodes.items[b].left);
        self.pull(b);
        return b;
    }

    fn mergeCoalesced(self: *Document, left: ?usize, right: ?usize) ?usize {
        const a = left orelse return right;
        const b = right orelse return left;
        const last = self.rightmost(a);
        const first = self.leftmost(b);
        const last_piece = self.nodes.items[last].piece;
        const first_piece = self.nodes.items[first].piece;
        if (last_piece.source != first_piece.source or
            last_piece.start + last_piece.len != first_piece.start or
            last_piece.len + first_piece.len > max_piece_bytes)
        {
            return self.merge(left, right);
        }

        const left_total = self.nodeSummary(left).bytes;
        const left_parts = self.split(left, left_total - last_piece.len);
        const right_parts = self.split(right, first_piece.len);
        const retained = left_parts.right orelse unreachable;
        const removed = right_parts.left orelse unreachable;
        std.debug.assert(self.nodePieceCount(retained) == 1);
        std.debug.assert(self.nodePieceCount(removed) == 1);
        self.nodes.items[retained].piece.len += first_piece.len;
        self.nodes.items[retained].piece.summary = Summary.combine(last_piece.summary, first_piece.summary);
        self.pull(retained);
        self.recycleTree(removed);
        return self.merge(self.merge(left_parts.left, retained), right_parts.right);
    }

    fn leftmost(self: *const Document, root: usize) usize {
        var index = root;
        while (self.nodes.items[index].left) |left| index = left;
        return index;
    }

    fn rightmost(self: *const Document, root: usize) usize {
        var index = root;
        while (self.nodes.items[index].right) |right| index = right;
        return index;
    }

    fn split(self: *Document, root: ?usize, offset: usize) Split {
        const index = root orelse return .{ .left = null, .right = null };
        const left_bytes = self.nodeSummary(self.nodes.items[index].left).bytes;
        const piece_len = self.nodes.items[index].piece.len;
        if (offset < left_bytes) {
            const parts = self.split(self.nodes.items[index].left, offset);
            self.nodes.items[index].left = parts.right;
            self.pull(index);
            return .{ .left = parts.left, .right = index };
        }
        if (offset > left_bytes + piece_len) {
            const parts = self.split(self.nodes.items[index].right, offset - left_bytes - piece_len);
            self.nodes.items[index].right = parts.left;
            self.pull(index);
            return .{ .left = index, .right = parts.right };
        }
        if (offset == left_bytes) {
            const left = self.nodes.items[index].left;
            self.nodes.items[index].left = null;
            self.pull(index);
            return .{ .left = left, .right = index };
        }
        if (offset == left_bytes + piece_len) {
            const right = self.nodes.items[index].right;
            self.nodes.items[index].right = null;
            self.pull(index);
            return .{ .left = index, .right = right };
        }

        const local = offset - left_bytes;
        const original_piece = self.nodes.items[index].piece;
        const bytes = self.pieceBytes(original_piece);
        const old_right = self.nodes.items[index].right;
        self.nodes.items[index].piece.len = local;
        self.nodes.items[index].piece.summary = summarize(bytes[0..local]);
        self.nodes.items[index].right = null;
        self.pull(index);

        const suffix_piece = Piece{
            .source = original_piece.source,
            .start = original_piece.start + local,
            .len = original_piece.len - local,
            .summary = summarize(bytes[local..]),
        };
        const suffix = self.allocNodeAssumeCapacity(suffix_piece);
        return .{ .left = index, .right = self.merge(suffix, old_right) };
    }

    fn locate(self: *const Document, offset: usize) ?Location {
        if (offset >= self.byteLen()) return null;
        var root = self.root;
        var remaining = offset;
        var global_start: usize = 0;
        while (root) |index| {
            const node = self.nodes.items[index];
            const left_bytes = self.nodeSummary(node.left).bytes;
            if (remaining < left_bytes) {
                root = node.left;
                continue;
            }
            remaining -= left_bytes;
            global_start += left_bytes;
            if (remaining < node.piece.len) return .{ .node = index, .local = remaining, .global_start = global_start };
            remaining -= node.piece.len;
            global_start += node.piece.len;
            root = node.right;
        }
        return null;
    }

    fn prefixSummary(self: *const Document, root: ?usize, count: usize) Summary {
        const index = root orelse return .{};
        const node = self.nodes.items[index];
        const left_summary = self.nodeSummary(node.left);
        if (count <= left_summary.bytes) return self.prefixSummary(node.left, count);
        var out = left_summary;
        const after_left = count - left_summary.bytes;
        if (after_left <= node.piece.len) {
            return Summary.combine(out, summarize(self.pieceBytes(node.piece)[0..after_left]));
        }
        out = Summary.combine(out, node.piece.summary);
        return Summary.combine(out, self.prefixSummary(node.right, after_left - node.piece.len));
    }

    fn byteAfterNewline(self: *const Document, ordinal: usize) ?usize {
        var root = self.root;
        var target = ordinal;
        var base: usize = 0;
        while (root) |index| {
            const node = self.nodes.items[index];
            const left = self.nodeSummary(node.left);
            if (target < left.newlines) {
                root = node.left;
                continue;
            }
            target -= left.newlines;
            base += left.bytes;
            if (target < node.piece.summary.newlines) {
                var remaining = target;
                for (self.pieceBytes(node.piece), 0..) |byte, local| {
                    if (byte != '\n') continue;
                    if (remaining == 0) return base + local + 1;
                    remaining -= 1;
                }
                return null;
            }
            target -= node.piece.summary.newlines;
            base += node.piece.len;
            root = node.right;
        }
        return null;
    }

    fn depth(self: *const Document, root: ?usize) usize {
        const index = root orelse return 0;
        return 1 + @max(self.depth(self.nodes.items[index].left), self.depth(self.nodes.items[index].right));
    }
};

fn summarize(bytes: []const u8) Summary {
    var newlines: usize = 0;
    var trailing: usize = 0;
    for (bytes) |byte| {
        if (byte == '\n') {
            newlines += 1;
            trailing = 0;
        } else {
            trailing += 1;
        }
    }
    return .{ .bytes = bytes.len, .newlines = newlines, .trailing_bytes = trailing };
}

fn chunkEnd(bytes: []const u8, start: usize) usize {
    var end = @min(bytes.len, start + max_piece_bytes);
    while (end > start and end < bytes.len and (bytes[end] & 0xc0) == 0x80) end -= 1;
    return end;
}

fn pieceCountForBytes(bytes: []const u8) usize {
    var count: usize = 0;
    var cursor: usize = 0;
    while (cursor < bytes.len) : (count += 1) cursor = chunkEnd(bytes, cursor);
    return count;
}

test "piece tree replaces UTF-8 ranges and preserves line queries" {
    var document = try Document.init(std.testing.allocator, "alpha\n中界\nomega");
    defer document.deinit();

    try std.testing.expectEqual(@as(usize, 3), document.lineCount());
    try std.testing.expectEqual(@as(usize, "alpha\n".len), try document.lineStart(1));
    try std.testing.expectEqual(Point{ .line = 1, .column = "中".len }, try document.pointForByte("alpha\n中".len));

    const edit = (try document.replaceRange("alpha\n".len, "alpha\n中".len, "hello\n")).?;
    try std.testing.expectEqual(@as(usize, 0), edit.old_newlines);
    try std.testing.expectEqual(@as(usize, 1), edit.new_newlines);
    try std.testing.expectEqual(@as(usize, 4), document.lineCount());
    const materialized = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(materialized);
    try std.testing.expectEqualStrings("alpha\nhello\n界\nomega", materialized);

    const newline = (try document.replaceRange("alpha".len, "alpha\n".len, "")).?;
    try std.testing.expectEqual(@as(usize, 1), newline.old_newlines);
    try std.testing.expectEqual(@as(usize, 0), newline.new_newlines);
    try std.testing.expectEqual(@as(usize, 3), document.lineCount());
}

test "piece tree chunk iterator and compaction preserve bytes" {
    const source = "0123456789abcdef" ** 600;
    var document = try Document.init(std.testing.allocator, source);
    defer document.deinit();
    _ = try document.replaceRange(4100, 4110, "中间 replacement");

    const before = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(before);
    try document.compact();
    const after = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
    try std.testing.expectEqual(@as(usize, 0), document.diagnostics().addition_bytes);
}

test "piece tree rejects invalid ranges without mutation" {
    var document = try Document.init(std.testing.allocator, "a中b");
    defer document.deinit();
    const revision = document.revision();
    try std.testing.expectError(error.InvalidUtf8Boundary, document.replaceRange(2, 2, "x"));
    try std.testing.expectError(error.InvalidUtf8, document.replaceRange(0, 1, "\xff"));
    try std.testing.expectEqual(revision, document.revision());
    const bytes = try document.materialize(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("a中b", bytes);
}

test "piece tree randomized edits match contiguous reference" {
    var document = try Document.init(std.testing.allocator, "zero\none\ntwo\nthree");
    defer document.deinit();
    var reference = std.ArrayList(u8).empty;
    defer reference.deinit(std.testing.allocator);
    try reference.appendSlice(std.testing.allocator, "zero\none\ntwo\nthree");

    const replacements = [_][]const u8{ "", "x", "longer", "a\nb", "中", "tail\n" };
    var random: u64 = 0x7a75_692d_646f_6375;
    for (0..512) |iteration| {
        random = random *% 6364136223846793005 +% 1442695040888963407;
        const a = @as(usize, @intCast(random % (reference.items.len + 1)));
        random = random *% 6364136223846793005 +% 1442695040888963407;
        const b = @as(usize, @intCast(random % (reference.items.len + 1)));
        var start = @min(a, b);
        var end = @max(a, b);
        while (start > 0 and start < reference.items.len and (reference.items[start] & 0xc0) == 0x80) start -= 1;
        while (end > 0 and end < reference.items.len and (reference.items[end] & 0xc0) == 0x80) end -= 1;
        random = random *% 6364136223846793005 +% 1442695040888963407;
        const replacement = replacements[@as(usize, @intCast(random % replacements.len))];

        _ = try document.replaceRange(start, end, replacement);
        try reference.replaceRange(std.testing.allocator, start, end - start, replacement);
        const actual = try document.materialize(std.testing.allocator);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualSlices(u8, reference.items, actual);

        var expected_lines: usize = 1;
        for (reference.items) |byte| if (byte == '\n') {
            expected_lines += 1;
        };
        try std.testing.expectEqual(expected_lines, document.lineCount());
        const sampled_line = iteration % expected_lines;
        const range = try document.lineRange(sampled_line);
        const point = try document.pointForByte(range.start);
        try std.testing.expectEqual(Point{ .line = sampled_line, .column = 0 }, point);
        try std.testing.expectEqual(range.start, try document.byteForPoint(point));
    }
}

test "piece tree replacement is semantically atomic on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        struct {
            fn run(allocator: std.mem.Allocator) !void {
                const source = "0123456789abcdef" ** 300;
                var document = try Document.init(allocator, source);
                defer document.deinit();
                const revision = document.revision();
                const result = document.replaceRange(1024, 1032, "expanded replacement across pieces\n");
                if (result) |edit_optional| {
                    const edit = edit_optional orelse return error.ExpectedCommittedEdit;
                    try std.testing.expectEqual(revision + 1, document.revision());
                    try std.testing.expectEqual(@as(usize, 8), edit.old_bytes);
                    try std.testing.expectEqual(@as(usize, "expanded replacement across pieces\n".len), edit.new_bytes);
                } else |err| {
                    if (err != error.OutOfMemory) return err;
                    try std.testing.expectEqual(revision, document.revision());
                    try std.testing.expectEqual(source.len, document.byteLen());
                    const actual = try document.materialize(std.testing.allocator);
                    defer std.testing.allocator.free(actual);
                    try std.testing.expectEqualStrings(source, actual);
                    return error.OutOfMemory;
                }
            }
        }.run,
        .{},
    );
}
