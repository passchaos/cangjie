//! Optional dictionary segmentation for scripts whose orthography normally
//! omits spaces between words.
//!
//! The public dictionary is a concrete immutable source-level type that can be
//! shared by multiple `Engine` instances. Words are stored as a Unicode-scalar
//! trie; segmentation returns UTF-8 byte boundaries so it composes directly
//! with paragraph coordinates and shaping safety checks.

const std = @import("std");

const unicode = @import("../../unicode.zig");

const Edge = struct {
    codepoint: u21,
    child: u32,
};

const Node = struct {
    edges: std.ArrayList(Edge) = .empty,
    terminal: bool = false,
};

const Impl = struct {
    allocator: std.mem.Allocator,
    script: DictionaryScript,
    nodes: std.ArrayList(Node) = .empty,
    max_word_scalars: usize = 0,

    fn deinit(self: *Impl) void {
        for (self.nodes.items) |*node| node.edges.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
    }

    fn insert(self: *Impl, word: []const u8) !void {
        if (word.len == 0) return error.EmptyDictionaryWord;
        if (!std.unicode.utf8ValidateSlice(word)) return error.InvalidUtf8;

        var node_index: u32 = 0;
        var scalar_count: usize = 0;
        var iterator = std.unicode.Utf8Iterator{ .bytes = word, .i = 0 };
        while (iterator.nextCodepoint()) |codepoint| {
            scalar_count += 1;
            if (unicode.scriptForCodepoint(codepoint) != unicodeScript(self.script)) {
                return error.DictionaryScriptMismatch;
            }
            if (findEdge(self.nodes.items[node_index].edges.items, codepoint)) |edge| {
                node_index = edge.child;
                continue;
            }
            const child = std.math.cast(u32, self.nodes.items.len) orelse
                return error.DictionaryTooLarge;
            try self.nodes.append(self.allocator, .{});
            try self.nodes.items[node_index].edges.append(
                self.allocator,
                .{ .codepoint = codepoint, .child = child },
            );
            std.mem.sort(
                Edge,
                self.nodes.items[node_index].edges.items,
                {},
                edgeLessThan,
            );
            node_index = child;
        }
        if (self.nodes.items[node_index].terminal) {
            return error.DuplicateDictionaryWord;
        }
        self.nodes.items[node_index].terminal = true;
        self.max_word_scalars = @max(self.max_word_scalars, scalar_count);
    }
};

const DictionaryScript = enum {
    thai,
    lao,
    khmer,
    myanmar,
};

/// Immutable language word list for scripts that normally omit spaces.
///
/// Construction copies words into an internal trie, so the source word slices
/// may be released immediately. The returned dictionary is safe to share between
/// contexts and concurrent layout calls; only `deinit` mutates it.
pub const WordBreakDictionary = struct {
    /// Source-visible trie storage; its layout is not a compatibility promise.
    implementation: Impl,

    pub const Script = DictionaryScript;
    pub const InitError = std.mem.Allocator.Error || error{
        EmptyDictionary,
        EmptyDictionaryWord,
        InvalidUtf8,
        DictionaryScriptMismatch,
        DuplicateDictionaryWord,
        DictionaryTooLarge,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        script: Script,
        words: []const []const u8,
    ) InitError!WordBreakDictionary {
        if (words.len == 0) return error.EmptyDictionary;
        var result = WordBreakDictionary{
            .implementation = .{
                .allocator = allocator,
                .script = script,
            },
        };
        errdefer result.implementation.deinit();
        try result.implementation.nodes.append(allocator, .{});
        for (words) |word| try result.implementation.insert(word);
        return result;
    }

    pub fn deinit(self: *WordBreakDictionary) void {
        self.implementation.deinit();
        self.* = undefined;
    }
};

/// Internal script identity used by the segmentation pass.
pub fn scriptOf(dictionary: *const WordBreakDictionary) unicode.Script {
    return unicodeScript(implConst(dictionary).script);
}

/// Upper bound for the number of prefix words beginning at one scalar.
pub fn maximumMatchCount(dictionary: *const WordBreakDictionary) usize {
    return implConst(dictionary).max_word_scalars;
}

/// Return all dictionary word ends beginning at `byte_start`, longest first.
///
/// `out` must have room for `maximumMatchCount`; this internal invariant keeps
/// segmentation exact even for dictionaries with deeply nested prefix words.
pub fn matchEnds(
    dictionary: *const WordBreakDictionary,
    text: []const u8,
    byte_start: usize,
    out: []usize,
) usize {
    if (byte_start >= text.len or out.len == 0) return 0;
    const implementation = implConst(dictionary);
    var node_index: u32 = 0;
    var cursor = byte_start;
    var count: usize = 0;
    while (cursor < text.len) {
        const decoded = decodeValid(text, cursor);
        const edge = findEdge(
            implementation.nodes.items[node_index].edges.items,
            decoded.codepoint,
        ) orelse break;
        node_index = edge.child;
        cursor = decoded.next;
        if (!implementation.nodes.items[node_index].terminal) continue;
        std.debug.assert(count < out.len);
        out[count] = cursor;
        count += 1;
    }
    std.mem.reverse(usize, out[0..count]);
    return count;
}

fn implConst(dictionary: *const WordBreakDictionary) *const Impl {
    return &dictionary.implementation;
}

fn unicodeScript(script: WordBreakDictionary.Script) unicode.Script {
    return switch (script) {
        .thai => .thai,
        .lao => .lao,
        .khmer => .khmer,
        .myanmar => .myanmar,
    };
}

fn edgeLessThan(_: void, lhs: Edge, rhs: Edge) bool {
    return lhs.codepoint < rhs.codepoint;
}

fn findEdge(edges: []const Edge, codepoint: u21) ?Edge {
    var low: usize = 0;
    var high = edges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const candidate = edges[mid];
        if (codepoint < candidate.codepoint) {
            high = mid;
        } else if (codepoint > candidate.codepoint) {
            low = mid + 1;
        } else {
            return candidate;
        }
    }
    return null;
}

const Decoded = struct {
    codepoint: u21,
    next: usize,
};

fn decodeValid(text: []const u8, offset: usize) Decoded {
    const length = std.unicode.utf8ByteSequenceLength(text[offset]) catch unreachable;
    return .{
        .codepoint = std.unicode.utf8Decode(text[offset..][0..length]) catch unreachable,
        .next = offset + length,
    };
}

test "dictionary validates script and reports longest matches first" {
    var dictionary = try WordBreakDictionary.init(
        std.testing.allocator,
        .thai,
        &.{ "ภาษา", "ภาษาไทย", "ไทย" },
    );
    defer dictionary.deinit();

    var matches: [4]usize = undefined;
    const text = "ภาษาไทย";
    const count = matchEnds(&dictionary, text, 0, &matches);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(text.len, matches[0]);
    try std.testing.expectEqual("ภาษา".len, matches[1]);

    try std.testing.expectError(
        error.DictionaryScriptMismatch,
        WordBreakDictionary.init(std.testing.allocator, .thai, &.{"hello"}),
    );
    try std.testing.expectError(
        error.EmptyDictionary,
        WordBreakDictionary.init(std.testing.allocator, .thai, &.{}),
    );
    try std.testing.expectError(
        error.EmptyDictionaryWord,
        WordBreakDictionary.init(std.testing.allocator, .thai, &.{""}),
    );
    try std.testing.expectError(
        error.DuplicateDictionaryWord,
        WordBreakDictionary.init(
            std.testing.allocator,
            .thai,
            &.{ "ไทย", "ไทย" },
        ),
    );
    try std.testing.expectError(
        error.InvalidUtf8,
        WordBreakDictionary.init(std.testing.allocator, .thai, &.{"\xff"}),
    );
}

test "dictionary accepts every supported script" {
    const samples = [_]struct {
        script: WordBreakDictionary.Script,
        word: []const u8,
    }{
        .{ .script = .thai, .word = "\u{0e01}" },
        .{ .script = .lao, .word = "\u{0e81}" },
        .{ .script = .khmer, .word = "\u{1780}" },
        .{ .script = .myanmar, .word = "\u{1000}" },
    };
    for (samples) |sample| {
        var dictionary = try WordBreakDictionary.init(
            std.testing.allocator,
            sample.script,
            &.{sample.word},
        );
        dictionary.deinit();
    }
}
