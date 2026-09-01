//! Allocation-free logical shaping items at script and resolved-bidi edges.
//!
//! Unicode script runs are scalar based, but shaping boundaries must not split
//! an extended grapheme cluster. The script cursor therefore promotes an
//! interior script boundary to the grapheme end. A second cursor promotes the
//! resolved scalar levels in the same way, and `Iterator` intersects the two
//! monotone partitions without allocating temporary run arrays.

const std = @import("std");

const pipeline_types = @import("../pipeline/types.zig");
const unicode = @import("../../unicode.zig");
const BidiScalar = @import("../../unicode/bidi/paragraph.zig").Scalar;

pub const Direction = pipeline_types.TextDirection;

/// One grapheme-safe, homogeneous script range.
///
/// This is deliberately private to shaping even though the type is exported
/// from this module: the public `unicode.ScriptRun` contract remains scalar
/// based. Shaping callers use this stronger range when they do not need bidi
/// resolution but still must not split a grapheme before font fallback.
pub const ScriptRun = struct {
    script: unicode.Script,
    byte_start: usize,
    byte_len: usize,

    pub fn byteEnd(self: ScriptRun) usize {
        return self.byte_start + self.byte_len;
    }
};

/// Descriptive alias for callers that treat script runs as logical items.
pub const ScriptItem = ScriptRun;

/// One grapheme-safe intersection of a script item and an exact bidi-level
/// item. `script_byte_start`/`script_byte_len` retain the complete enclosing
/// script item so language inference and shaping context need not be narrowed
/// merely because bidi introduced an interior boundary.
pub const Run = struct {
    script: unicode.Script,
    level: u8,
    direction: Direction,
    byte_start: usize,
    byte_len: usize,
    script_byte_start: usize,
    script_byte_len: usize,

    pub fn byteEnd(self: Run) usize {
        return self.byte_start + self.byte_len;
    }

    pub fn scriptByteEnd(self: Run) usize {
        return self.script_byte_start + self.script_byte_len;
    }
};

const LevelItem = struct {
    level: u8,
    byte_start: usize,
    byte_len: usize,

    fn byteEnd(self: LevelItem) usize {
        return self.byte_start + self.byte_len;
    }
};

/// Allocation-free grapheme-safe script itemization for already-valid UTF-8.
///
/// The raw Unicode script iterator remains scalar based. When one of its
/// boundaries falls inside an EGC, the raw run active at the EGC's first
/// scalar owns the whole grapheme. Adjacent graphemes with the same resulting
/// script are coalesced.
pub const ScriptIterator = struct {
    graphemes: unicode.GraphemeClusterIterator,
    scripts: unicode.ScriptRunIterator,
    script_run: ?unicode.ScriptRun = null,
    pending: ?ScriptItem = null,

    pub fn init(text: []const u8) ScriptIterator {
        return .{
            .graphemes = unicode.graphemeClustersAssumeValid(text),
            .scripts = unicode.scriptRuns(text),
        };
    }

    pub fn next(self: *ScriptIterator) ?ScriptRun {
        const first = self.takeGrapheme() orelse return null;
        var result = first;
        while (self.nextGrapheme()) |item| {
            if (item.script == result.script) {
                std.debug.assert(item.byte_start == result.byteEnd());
                result.byte_len = item.byteEnd() - result.byte_start;
                continue;
            }
            self.pending = item;
            break;
        }
        return result;
    }

    fn takeGrapheme(self: *ScriptIterator) ?ScriptRun {
        if (self.pending) |item| {
            self.pending = null;
            return item;
        }
        return self.nextGrapheme();
    }

    fn nextGrapheme(self: *ScriptIterator) ?ScriptRun {
        const grapheme = self.graphemes.next() orelse return null;
        return .{
            // The raw run active at the EGC's first scalar owns the complete
            // grapheme. All raw boundaries inside it are consumed lazily when
            // the next EGC queries its owner.
            .script = self.scriptAt(grapheme.byte_start),
            .byte_start = grapheme.byte_start,
            .byte_len = grapheme.byte_len,
        };
    }

    fn scriptAt(self: *ScriptIterator, byte_start: usize) unicode.Script {
        var current = self.script_run orelse
            (self.scripts.next() catch unreachable) orelse unreachable;
        while (current.byte_start + current.byte_len <= byte_start) {
            current = (self.scripts.next() catch unreachable) orelse unreachable;
        }
        std.debug.assert(current.byte_start <= byte_start);
        std.debug.assert(byte_start < current.byte_start + current.byte_len);
        self.script_run = current;
        return current.script;
    }
};

const LevelIterator = struct {
    // Borrow only the resolved arrays. Storing a shallow BidiParagraph copy
    // here would duplicate its allocator ownership and expose a second
    // `deinit` path through an otherwise non-owning iterator.
    scalars: []const BidiScalar,
    levels: []const u8,
    base_level: u8,
    resolved: bool = true,
    graphemes: unicode.GraphemeClusterIterator,
    scalar_index: usize = 0,
    pending: ?LevelItem = null,

    fn init(text: []const u8, paragraph: unicode.BidiParagraph) LevelIterator {
        return .{
            .scalars = paragraph.scalars,
            .levels = paragraph.levels,
            .base_level = paragraph.base_level,
            .graphemes = unicode.graphemeClustersAssumeValid(text),
        };
    }

    fn next(self: *LevelIterator) ?LevelItem {
        const first = self.takeGrapheme() orelse return null;
        var result = first;
        while (self.nextGrapheme()) |item| {
            if (item.level == result.level) {
                std.debug.assert(item.byte_start == result.byteEnd());
                result.byte_len = item.byteEnd() - result.byte_start;
                continue;
            }
            self.pending = item;
            break;
        }
        return result;
    }

    fn takeGrapheme(self: *LevelIterator) ?LevelItem {
        if (self.pending) |item| {
            self.pending = null;
            return item;
        }
        return self.nextGrapheme();
    }

    fn nextGrapheme(self: *LevelIterator) ?LevelItem {
        const grapheme = self.graphemes.next() orelse {
            if (self.resolved) {
                std.debug.assert(self.scalar_index == self.scalars.len);
            }
            return null;
        };
        if (!self.resolved) {
            return .{
                .level = self.base_level,
                .byte_start = grapheme.byte_start,
                .byte_len = grapheme.byte_len,
            };
        }
        const end = grapheme.byte_start + grapheme.byte_len;
        std.debug.assert(self.scalar_index < self.scalars.len);
        std.debug.assert(
            self.scalars[self.scalar_index].byte_start == grapheme.byte_start,
        );
        var level: ?u8 = null;
        while (self.scalar_index < self.scalars.len) {
            const scalar = self.scalars[self.scalar_index];
            if (scalar.byte_start >= end) break;
            std.debug.assert(scalar.byte_start + scalar.byte_len <= end);
            const candidate = self.levels[self.scalar_index];
            // X9-removed controls use 0xff. Never interpret that sentinel as
            // odd; a control-only EGC inherits the paragraph base level.
            if (candidate != 0xff) {
                level = if (level) |current| @max(current, candidate) else candidate;
            }
            self.scalar_index += 1;
        }
        std.debug.assert(
            self.scalar_index == self.scalars.len or
                self.scalars[self.scalar_index].byte_start == end,
        );
        return .{
            .level = level orelse self.base_level,
            .byte_start = grapheme.byte_start,
            .byte_len = grapheme.byte_len,
        };
    }
};

pub const Iterator = struct {
    scripts: ScriptIterator,
    levels: ?LevelIterator,
    script_item: ?ScriptItem = null,
    level_item: ?LevelItem = null,
    cursor: usize = 0,
    base_level: u8 = 0,

    pub fn init(text: []const u8, paragraph: unicode.BidiParagraph) Iterator {
        std.debug.assert(paragraph.scalars.len == paragraph.classes.len);
        std.debug.assert(paragraph.scalars.len == paragraph.levels.len);
        if (paragraph.scalars.len == 0) {
            std.debug.assert(text.len == 0);
        } else {
            std.debug.assert(paragraph.scalars[0].byte_start == 0);
            const last = paragraph.scalars[paragraph.scalars.len - 1];
            std.debug.assert(last.byte_start + last.byte_len == text.len);
        }
        return .{
            .scripts = .init(text),
            .levels = .init(text, paragraph),
        };
    }

    pub fn initBase(text: []const u8, base_level: u8) Iterator {
        return .{
            .scripts = .init(text),
            .levels = null,
            .base_level = base_level,
        };
    }

    pub fn next(self: *Iterator) ?Run {
        // Without resolved bidi levels, script items are already the final
        // partition. Do not walk the same grapheme stream a second time merely
        // to attach one constant paragraph level.
        if (self.levels == null) {
            const script = self.scripts.next() orelse return null;
            return .{
                .script = script.script,
                .level = self.base_level,
                .direction = directionForLevel(self.base_level),
                .byte_start = script.byte_start,
                .byte_len = script.byte_len,
                .script_byte_start = script.byte_start,
                .script_byte_len = script.byte_len,
            };
        }
        if (self.script_item == null) self.script_item = self.scripts.next();
        if (self.level_item == null) {
            if (self.levels) |*levels| {
                self.level_item = levels.next();
            } else unreachable;
        }
        const script = self.script_item orelse return null;
        const level = self.level_item orelse return null;
        std.debug.assert(self.cursor >= script.byte_start);
        std.debug.assert(self.cursor >= level.byte_start);

        const end = @min(script.byteEnd(), level.byteEnd());
        const result = Run{
            .script = script.script,
            .level = level.level,
            .direction = directionForLevel(level.level),
            .byte_start = self.cursor,
            .byte_len = end - self.cursor,
            .script_byte_start = script.byte_start,
            .script_byte_len = script.byte_len,
        };
        self.cursor = end;
        if (end == script.byteEnd()) self.script_item = null;
        if (end == level.byteEnd()) self.level_item = null;
        return result;
    }
};

/// A two-item lookahead which answers whether itemization produced multiple
/// runs without restarting the Unicode iterators. Callers then consume the
/// prefetched items followed by the already-advanced underlying iterator.
pub const ProbedIterator = struct {
    iterator: Iterator,
    prefetched: [2]?Run,
    replay_index: usize = 0,

    pub fn next(self: *ProbedIterator) ?Run {
        if (self.replay_index < self.prefetched.len) {
            const result = self.prefetched[self.replay_index];
            self.replay_index += 1;
            if (result != null) return result;
        }
        return self.iterator.next();
    }

    pub fn isItemized(self: *const ProbedIterator) bool {
        return self.prefetched[1] != null;
    }

    pub fn isEmpty(self: *const ProbedIterator) bool {
        return self.prefetched[0] == null;
    }
};

fn probe(iterator: Iterator) ProbedIterator {
    var advanced = iterator;
    const first = advanced.next();
    const second = advanced.next();
    return .{
        .iterator = advanced,
        .prefetched = .{ first, second },
    };
}

pub fn runs(text: []const u8, paragraph: unicode.BidiParagraph) Iterator {
    return .init(text, paragraph);
}

pub fn baseRuns(text: []const u8, base_level: u8) Iterator {
    return .initBase(text, base_level);
}

pub fn probedRuns(text: []const u8, paragraph: unicode.BidiParagraph) ProbedIterator {
    return probe(.init(text, paragraph));
}

pub fn probedBaseRuns(text: []const u8, base_level: u8) ProbedIterator {
    return probe(.initBase(text, base_level));
}

/// Construct the script-only iterator used by proven pure-LTR shaping paths.
pub fn scriptRuns(text: []const u8) ScriptIterator {
    return .init(text);
}

fn directionForLevel(level: u8) Direction {
    return if (level & 1 == 0) .ltr else .rtl;
}

fn expectRuns(
    text: []const u8,
    base_direction: unicode.BidiBaseDirection,
    expected: []const Run,
) !void {
    var paragraph = try unicode.resolveBidiParagraph(
        std.testing.allocator,
        text,
        base_direction,
    );
    defer paragraph.deinit();
    var iterator = runs(text, paragraph);
    for (expected) |wanted| {
        const actual = iterator.next() orelse return error.MissingLogicalRun;
        try std.testing.expectEqualDeep(wanted, actual);
    }
    try std.testing.expectEqual(@as(?Run, null), iterator.next());
}

fn expectScriptRuns(text: []const u8, expected: []const ScriptRun) !void {
    var iterator = scriptRuns(text);
    for (expected) |wanted| {
        const actual = iterator.next() orelse return error.MissingScriptRun;
        try std.testing.expectEqualDeep(wanted, actual);
    }
    try std.testing.expectEqual(@as(?ScriptRun, null), iterator.next());
}

test "script-only runs snap interior boundaries to grapheme ends" {
    const text = "A\u{0951}A";
    try expectScriptRuns(text, &.{.{
        .script = .latin,
        .byte_start = 0,
        .byte_len = text.len,
    }});

    // The Vedic mark starts a raw scalar script run, but the preceding Latin
    // base owns its whole EGC. Arabic begins at the next safe boundary.
    const mixed = "A\u{0951}\u{0627}";
    try expectScriptRuns(mixed, &.{
        .{
            .script = .latin,
            .byte_start = 0,
            .byte_len = "A\u{0951}".len,
        },
        .{
            .script = .arabic,
            .byte_start = "A\u{0951}".len,
            .byte_len = "\u{0627}".len,
        },
    });
}

test "script-only empty text remains exhausted" {
    var iterator = scriptRuns("");
    try std.testing.expectEqual(@as(?ScriptRun, null), iterator.next());
    try std.testing.expectEqual(@as(?ScriptRun, null), iterator.next());
}

test "probed base runs replay lookahead without restarting itemization" {
    const text = "A\u{0951}\u{0627}12B";
    var expected = baseRuns(text, 0);
    var probed = probedBaseRuns(text, 0);
    try std.testing.expect(probed.isItemized());
    while (expected.next()) |run| {
        try std.testing.expectEqualDeep(run, probed.next().?);
    }
    try std.testing.expectEqual(@as(?Run, null), probed.next());
}

test "probed resolved runs replay lookahead without losing X9 levels" {
    const text = "A\u{202e}B\u{202c}\u{0627}";
    var paragraph = try unicode.resolveBidiParagraph(
        std.testing.allocator,
        text,
        .ltr,
    );
    defer paragraph.deinit();
    var expected = runs(text, paragraph);
    var probed = probedRuns(text, paragraph);
    try std.testing.expect(probed.isItemized());
    while (expected.next()) |run| {
        const replayed = probed.next() orelse
            return error.MissingLogicalRun;
        try std.testing.expectEqualDeep(run, replayed);
        try std.testing.expect(replayed.level != 0xff);
    }
    try std.testing.expectEqual(@as(?Run, null), probed.next());
}

test "script edges inside a grapheme preserve preceding-base ownership" {
    const text = "A\u{0951}A";
    try expectRuns(text, .ltr, &.{.{
        .script = .latin,
        .level = 0,
        .direction = .ltr,
        .byte_start = 0,
        .byte_len = text.len,
        .script_byte_start = 0,
        .script_byte_len = text.len,
    }});
}

test "Arabic letters and digits retain exact resolved levels" {
    const text = "A\u{0644}\u{0627}12B";
    try expectRuns(text, .ltr, &.{
        .{ .script = .latin, .level = 0, .direction = .ltr, .byte_start = 0, .byte_len = 1, .script_byte_start = 0, .script_byte_len = 1 },
        .{ .script = .arabic, .level = 1, .direction = .rtl, .byte_start = 1, .byte_len = 4, .script_byte_start = 1, .script_byte_len = 6 },
        .{ .script = .arabic, .level = 2, .direction = .ltr, .byte_start = 5, .byte_len = 2, .script_byte_start = 1, .script_byte_len = 6 },
        .{ .script = .latin, .level = 0, .direction = .ltr, .byte_start = 7, .byte_len = 1, .script_byte_start = 7, .script_byte_len = 1 },
    });
}

test "same-direction exact levels remain distinct within one script item" {
    const text = "\u{05d0}\u{202b}\u{05d1}\u{202c}\u{05d2}";
    try expectRuns(text, .rtl, &.{
        .{ .script = .hebrew, .level = 1, .direction = .rtl, .byte_start = 0, .byte_len = 5, .script_byte_start = 0, .script_byte_len = text.len },
        .{ .script = .hebrew, .level = 3, .direction = .rtl, .byte_start = 5, .byte_len = 2, .script_byte_start = 0, .script_byte_len = text.len },
        .{ .script = .hebrew, .level = 1, .direction = .rtl, .byte_start = 7, .byte_len = 5, .script_byte_start = 0, .script_byte_len = text.len },
    });
}

test "X9-only graphemes use the paragraph base level" {
    const text = "A\u{202e}B\u{202c}C";
    var paragraph = try unicode.resolveBidiParagraph(
        std.testing.allocator,
        text,
        .ltr,
    );
    defer paragraph.deinit();
    var iterator = runs(text, paragraph);
    while (iterator.next()) |run| try std.testing.expect(run.level != 0xff);

    const only_x9 = "\u{202a}\u{202c}";
    try expectRuns(only_x9, .rtl, &.{.{
        .script = .common,
        .level = 1,
        .direction = .rtl,
        .byte_start = 0,
        .byte_len = only_x9.len,
        .script_byte_start = 0,
        .script_byte_len = only_x9.len,
    }});
}
