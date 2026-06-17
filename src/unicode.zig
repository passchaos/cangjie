const std = @import("std");

/// Lightweight Unicode helpers used by the shaping/layout layers.
/// The tables are intentionally compact and cover the scripts and boundaries
/// currently exercised by Cangjie; they are not a replacement for the full UAX
/// datasets yet.
pub const Script = enum {
    common,
    inherited,
    latin,
    han,
    hiragana,
    katakana,
    hangul,
    arabic,
    hebrew,
    devanagari,
    unknown,
};

pub const ScriptRun = struct {
    script: Script,
    byte_start: usize,
    byte_len: usize,
};

pub const BidiClass = enum {
    ltr,
    rtl,
    neutral,
};

pub const BidiRun = struct {
    direction: BidiClass,
    byte_start: usize,
    byte_len: usize,
};

pub const BidiMapItem = struct {
    logical_index: usize,
    visual_index: usize,
    byte_start: usize,
    byte_len: usize,
    codepoint: u21,
    visual_codepoint: u21,
    direction: BidiClass,
};

pub const BidiMap = struct {
    allocator: std.mem.Allocator,
    items: []BidiMapItem,
    logical_to_visual: []usize,

    pub fn deinit(self: *BidiMap) void {
        self.allocator.free(self.logical_to_visual);
        self.allocator.free(self.items);
        self.* = undefined;
    }

    pub fn visualToLogical(self: BidiMap, visual_index: usize) ?usize {
        if (visual_index >= self.items.len) return null;
        return self.items[visual_index].logical_index;
    }

    pub fn logicalToVisual(self: BidiMap, logical_index: usize) ?usize {
        if (logical_index >= self.logical_to_visual.len) return null;
        return self.logical_to_visual[logical_index];
    }
};

pub const GraphemeCluster = struct {
    byte_start: usize,
    byte_len: usize,
};

pub const WordSegment = struct {
    byte_start: usize,
    byte_len: usize,
};

pub const SentenceSegment = struct {
    byte_start: usize,
    byte_len: usize,
};

pub const LineBreakKind = enum {
    soft,
    hard,
};

pub const LineBreak = struct {
    byte_offset: usize,
    kind: LineBreakKind,
};

pub const OpenTypeScriptTag = enum(u32) {
    dflt = tag("DFLT"),
    latn = tag("latn"),
    hani = tag("hani"),
    hira = tag("hira"),
    kana = tag("kana"),
    hang = tag("hang"),
    arab = tag("arab"),
    hebr = tag("hebr"),
    dev2 = tag("dev2"),
};

pub const OpenTypeLanguageTag = enum(u32) {
    dflt = tag("dflt"),
    ara = tag("ARA "),
    jan = tag("JAN "),
    kor = tag("KOR "),
    zhs = tag("ZHS "),
    zht = tag("ZHT "),
    hin = tag("HIN "),
};

pub const FeatureOverride = struct {
    tag: u32,
    enabled: bool,
};

/// Map the internal script enum to the OpenType script tag used for GSUB/GPOS
/// ScriptList selection.
pub fn openTypeScriptTag(script: Script) OpenTypeScriptTag {
    return switch (script) {
        .latin => .latn,
        .han => .hani,
        .hiragana => .hira,
        .katakana => .kana,
        .hangul => .hang,
        .arabic => .arab,
        .hebrew => .hebr,
        .devanagari => .dev2,
        .common, .inherited, .unknown => .dflt,
    };
}

/// Infer a coarse OpenType language tag from script content when the caller did
/// not specify one. This gives CJK, Arabic, and Indic fonts a better default
/// LangSys than always using `dflt`.
pub fn inferOpenTypeLanguageTag(text: []const u8) OpenTypeLanguageTag {
    var saw_han = false;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        const script = scriptForCodepoint(codepoint);
        switch (script) {
            .hiragana, .katakana => return .jan,
            .hangul => return .kor,
            .arabic => return .ara,
            .devanagari => return .hin,
            .han => saw_han = true,
            else => {},
        }
    }
    if (saw_han) return .zhs;
    return .dflt;
}

pub fn tag(comptime bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

pub fn scriptForCodepoint(codepoint: u21) Script {
    if ((codepoint >= 'A' and codepoint <= 'Z') or (codepoint >= 'a' and codepoint <= 'z')) return .latin;
    if (codepoint >= 0x00c0 and codepoint <= 0x024f) return .latin;
    if (codepoint >= 0x0300 and codepoint <= 0x036f) return .inherited;
    if (codepoint >= 0x0590 and codepoint <= 0x05ff) return .hebrew;
    if (codepoint >= 0x0600 and codepoint <= 0x06ff) return .arabic;
    if (codepoint >= 0x0750 and codepoint <= 0x077f) return .arabic;
    if (codepoint >= 0x08a0 and codepoint <= 0x08ff) return .arabic;
    if (codepoint >= 0x0900 and codepoint <= 0x097f) return .devanagari;
    if (codepoint >= 0x3040 and codepoint <= 0x309f) return .hiragana;
    if (codepoint >= 0x30a0 and codepoint <= 0x30ff) return .katakana;
    if (codepoint >= 0x3130 and codepoint <= 0x318f) return .hangul;
    if (codepoint >= 0xac00 and codepoint <= 0xd7af) return .hangul;
    if (codepoint >= 0x3400 and codepoint <= 0x4dbf) return .han;
    if (codepoint >= 0x4e00 and codepoint <= 0x9fff) return .han;
    if (codepoint >= 0xf900 and codepoint <= 0xfaff) return .han;
    if (codepoint >= 0x20000 and codepoint <= 0x2fffd) return .han;
    if (codepoint >= 0x30000 and codepoint <= 0x3fffd) return .han;
    if (isCommonCodepoint(codepoint)) return .common;
    return .unknown;
}

/// Classify only strong LTR/RTL scripts and neutral punctuation/spacing. The
/// higher-level bidi functions use this coarse class to build visual runs.
pub fn bidiClassForCodepoint(codepoint: u21) BidiClass {
    const script = scriptForCodepoint(codepoint);
    return switch (script) {
        .arabic, .hebrew => .rtl,
        .latin, .han, .hiragana, .katakana, .hangul, .devanagari => .ltr,
        else => .neutral,
    };
}

pub fn itemizeBidiRuns(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]BidiRun {
    var runs = std.ArrayList(BidiRun).empty;
    errdefer runs.deinit(allocator);

    var current_direction: ?BidiClass = null;
    var run_start: usize = 0;
    var run_end: usize = 0;
    var neutral_start: ?usize = null;
    var neutral_end: usize = 0;

    // Neutral spans are attached to the surrounding run when possible. If text
    // starts with neutrals, use the paragraph base direction as their run.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const cluster = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const next_index = it.i;
        const bidi_class = bidiClassForCodepoint(codepoint);
        if (bidi_class == .neutral) {
            if (neutral_start == null) neutral_start = cluster;
            neutral_end = next_index;
            if (current_direction == null) {
                current_direction = baseDirectionOrLtr(base_direction);
                run_start = cluster;
            }
            run_end = next_index;
            continue;
        }

        if (current_direction == null) {
            current_direction = bidi_class;
            run_start = neutral_start orelse cluster;
            run_end = next_index;
            neutral_start = null;
            continue;
        }

        if (current_direction.? == bidi_class) {
            run_end = next_index;
            neutral_start = null;
            continue;
        }

        const split_at = neutral_start orelse cluster;
        try runs.append(allocator, .{
            .direction = current_direction.?,
            .byte_start = run_start,
            .byte_len = split_at - run_start,
        });
        current_direction = bidi_class;
        run_start = neutral_start orelse cluster;
        run_end = next_index;
        neutral_start = null;
    }

    if (current_direction) |direction| {
        try runs.append(allocator, .{
            .direction = direction,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
    }
    return try runs.toOwnedSlice(allocator);
}

pub fn visualOrderBidiRuns(allocator: std.mem.Allocator, runs: []const BidiRun, base_direction: BidiClass) ![]usize {
    // This is a deliberately small bidi reordering model: paragraph RTL reverses
    // run order; individual RTL runs are reversed when materialized.
    const order = try allocator.alloc(usize, runs.len);
    if (baseDirectionOrLtr(base_direction) == .rtl) {
        for (order, 0..) |*slot, index| {
            slot.* = runs.len - 1 - index;
        }
    } else {
        for (order, 0..) |*slot, index| {
            slot.* = index;
        }
    }
    return order;
}

pub fn visualOrderCodepoints(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]u21 {
    const runs = try itemizeBidiRuns(allocator, text, base_direction);
    defer allocator.free(runs);
    const order = try visualOrderBidiRuns(allocator, runs, base_direction);
    defer allocator.free(order);

    var output = std.ArrayList(u21).empty;
    errdefer output.deinit(allocator);
    for (order) |run_index| {
        const run = runs[run_index];
        const slice = text[run.byte_start .. run.byte_start + run.byte_len];
        if (run.direction == .rtl) {
            const start_len = output.items.len;
            try appendCodepoints(allocator, &output, slice);
            std.mem.reverse(u21, output.items[start_len..]);
            for (output.items[start_len..]) |*codepoint| {
                codepoint.* = mirroredCodepoint(codepoint.*);
            }
        } else {
            try appendCodepoints(allocator, &output, slice);
        }
    }
    return try output.toOwnedSlice(allocator);
}

pub fn visualOrderUtf8(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) ![]u8 {
    const codepoints = try visualOrderCodepoints(allocator, text, base_direction);
    defer allocator.free(codepoints);
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);
    for (codepoints) |codepoint| {
        var buffer: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buffer) catch continue;
        try output.appendSlice(allocator, buffer[0..len]);
    }
    return try output.toOwnedSlice(allocator);
}

pub fn buildBidiMap(allocator: std.mem.Allocator, text: []const u8, base_direction: BidiClass) !BidiMap {
    // The map keeps both visual order and logical-to-visual lookup, which lets
    // editor code move between byte offsets and rendered caret positions.
    const logical = try collectLogicalBidiItems(allocator, text);
    defer allocator.free(logical);
    const runs = try itemizeBidiRuns(allocator, text, base_direction);
    defer allocator.free(runs);
    const order = try visualOrderBidiRuns(allocator, runs, base_direction);
    defer allocator.free(order);

    var items = std.ArrayList(BidiMapItem).empty;
    errdefer items.deinit(allocator);
    const logical_to_visual = try allocator.alloc(usize, logical.len);
    errdefer allocator.free(logical_to_visual);

    for (order) |run_index| {
        const run = runs[run_index];
        const range = logicalRangeForBytes(logical, run.byte_start, run.byte_start + run.byte_len);
        if (run.direction == .rtl) {
            var index = range.end;
            while (index > range.start) {
                index -= 1;
                try appendVisualBidiItem(allocator, &items, logical_to_visual, logical[index], run.direction);
            }
        } else {
            var index = range.start;
            while (index < range.end) : (index += 1) {
                try appendVisualBidiItem(allocator, &items, logical_to_visual, logical[index], run.direction);
            }
        }
    }

    return .{
        .allocator = allocator,
        .items = try items.toOwnedSlice(allocator),
        .logical_to_visual = logical_to_visual,
    };
}

pub fn itemizeGraphemeClusters(allocator: std.mem.Allocator, text: []const u8) ![]GraphemeCluster {
    var clusters = std.ArrayList(GraphemeCluster).empty;
    errdefer clusters.deinit(allocator);

    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var cluster_start: ?usize = null;
    var cluster_end: usize = 0;
    var previous_codepoint: ?u21 = null;
    var regional_indicator_count: usize = 0;
    // Approximate UAX #29 extended grapheme clusters for the scripts supported
    // here: combining marks, variation selectors, emoji modifiers, ZWJ chains,
    // regional-indicator pairs, and Hangul Jamo syllable sequences.
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const byte_end = it.i;

        if (cluster_start == null) {
            cluster_start = byte_start;
            cluster_end = byte_end;
            previous_codepoint = codepoint;
            regional_indicator_count = if (isRegionalIndicator(codepoint)) 1 else 0;
            continue;
        }

        if (extendsGrapheme(previous_codepoint.?, codepoint, regional_indicator_count)) {
            cluster_end = byte_end;
            previous_codepoint = codepoint;
            if (isRegionalIndicator(codepoint)) {
                regional_indicator_count += 1;
            } else if (codepoint != 0x200d) {
                regional_indicator_count = 0;
            }
            continue;
        }

        try clusters.append(allocator, .{
            .byte_start = cluster_start.?,
            .byte_len = cluster_end - cluster_start.?,
        });
        cluster_start = byte_start;
        cluster_end = byte_end;
        previous_codepoint = codepoint;
        regional_indicator_count = if (isRegionalIndicator(codepoint)) 1 else 0;
    }

    if (cluster_start) |start| {
        try clusters.append(allocator, .{
            .byte_start = start,
            .byte_len = cluster_end - start,
        });
    }
    return try clusters.toOwnedSlice(allocator);
}

pub fn itemizeWordSegments(allocator: std.mem.Allocator, text: []const u8) ![]WordSegment {
    var words = std.ArrayList(WordSegment).empty;
    errdefer words.deinit(allocator);

    var current_kind: WordKind = .none;
    var word_start: usize = 0;
    var word_end: usize = 0;
    // Latin-like text forms multi-codepoint words. East Asian scripts are
    // exposed as single-codepoint words because they do not require spaces.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const byte_end = it.i;
        const kind = wordKindForCodepoint(codepoint);
        if (kind == .none) {
            if (current_kind != .none) {
                try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
                current_kind = .none;
            }
            continue;
        }
        if (kind == .single) {
            if (current_kind != .none) {
                try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
                current_kind = .none;
            }
            try words.append(allocator, .{ .byte_start = byte_start, .byte_len = byte_end - byte_start });
            continue;
        }
        if (current_kind == .none) {
            current_kind = kind;
            word_start = byte_start;
            word_end = byte_end;
            continue;
        }
        if (current_kind == kind) {
            word_end = byte_end;
            continue;
        }
        try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
        current_kind = kind;
        word_start = byte_start;
        word_end = byte_end;
    }

    if (current_kind != .none) {
        try words.append(allocator, .{ .byte_start = word_start, .byte_len = word_end - word_start });
    }
    return try words.toOwnedSlice(allocator);
}

pub fn itemizeSentenceSegments(allocator: std.mem.Allocator, text: []const u8) ![]SentenceSegment {
    var sentences = std.ArrayList(SentenceSegment).empty;
    errdefer sentences.deinit(allocator);

    var sentence_start: usize = 0;
    var sentence_end: usize = 0;
    var pending_break = false;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const byte_end = it.i;
        sentence_end = byte_end;

        if (pending_break and !isSentenceTrailingSpace(codepoint)) {
            try appendSentenceIfNotBlank(allocator, &sentences, text, sentence_start, byte_start);
            sentence_start = byte_start;
            pending_break = false;
        }

        if (isSentenceTerminator(codepoint)) {
            pending_break = true;
        }
    }

    try appendSentenceIfNotBlank(allocator, &sentences, text, sentence_start, sentence_end);
    return try sentences.toOwnedSlice(allocator);
}

pub fn itemizeLineBreaks(allocator: std.mem.Allocator, text: []const u8) ![]LineBreak {
    var breaks = std.ArrayList(LineBreak).empty;
    errdefer breaks.deinit(allocator);

    // Emit hard breaks for CR/LF and soft opportunities after whitespace or
    // East Asian characters. Paragraph layout currently uses a similar greedy
    // break policy over shaped glyphs.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const byte_end = it.i;
        if (codepoint == '\n') {
            try breaks.append(allocator, .{ .byte_offset = byte_end, .kind = .hard });
        } else if (codepoint == '\r') {
            if (it.i < text.len and text[it.i] == '\n') {
                _ = it.nextCodepoint();
                try breaks.append(allocator, .{ .byte_offset = it.i, .kind = .hard });
            } else {
                try breaks.append(allocator, .{ .byte_offset = byte_end, .kind = .hard });
            }
        } else if (isLineBreakSpace(codepoint)) {
            try breaks.append(allocator, .{ .byte_offset = byte_end, .kind = .soft });
        } else if (isLineBreakEastAsian(codepoint)) {
            try breaks.append(allocator, .{ .byte_offset = byte_end, .kind = .soft });
        }
        _ = byte_start;
    }

    return try breaks.toOwnedSlice(allocator);
}

pub fn itemizeScriptRuns(allocator: std.mem.Allocator, text: []const u8) ![]ScriptRun {
    var runs = std.ArrayList(ScriptRun).empty;
    errdefer runs.deinit(allocator);

    var current_script: ?Script = null;
    var run_start: usize = 0;
    var run_end: usize = 0;
    // Script runs drive OpenType ScriptList selection. Common/inherited
    // codepoints stay with the surrounding run so punctuation does not split a
    // Latin, Arabic, or CJK shaping segment by itself.
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const cluster = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const next_index = it.i;
        const script = scriptForCodepoint(codepoint);
        if (current_script == null) {
            current_script = if (script == .common or script == .inherited) .common else script;
            run_start = cluster;
            run_end = next_index;
            continue;
        }
        if (scriptBelongsToRun(script, current_script.?)) {
            run_end = next_index;
            continue;
        }
        try runs.append(allocator, .{
            .script = current_script.?,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
        current_script = if (script == .common or script == .inherited) .common else script;
        run_start = cluster;
        run_end = next_index;
    }

    if (current_script) |script| {
        try runs.append(allocator, .{
            .script = script,
            .byte_start = run_start,
            .byte_len = run_end - run_start,
        });
    }
    return try runs.toOwnedSlice(allocator);
}

fn baseDirectionOrLtr(direction: BidiClass) BidiClass {
    return if (direction == .rtl) .rtl else .ltr;
}

fn collectLogicalBidiItems(allocator: std.mem.Allocator, text: []const u8) ![]BidiMapItem {
    var items = std.ArrayList(BidiMapItem).empty;
    errdefer items.deinit(allocator);
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        try items.append(allocator, .{
            .logical_index = items.items.len,
            .visual_index = 0,
            .byte_start = byte_start,
            .byte_len = it.i - byte_start,
            .codepoint = codepoint,
            .visual_codepoint = codepoint,
            .direction = bidiClassForCodepoint(codepoint),
        });
    }
    return try items.toOwnedSlice(allocator);
}

fn logicalRangeForBytes(logical: []const BidiMapItem, byte_start: usize, byte_end: usize) struct { start: usize, end: usize } {
    var start: ?usize = null;
    var end: usize = 0;
    for (logical, 0..) |item, index| {
        const item_end = item.byte_start + item.byte_len;
        if (item_end <= byte_start or item.byte_start >= byte_end) continue;
        if (start == null) start = index;
        end = index + 1;
    }
    return .{ .start = start orelse 0, .end = end };
}

fn appendVisualBidiItem(allocator: std.mem.Allocator, items: *std.ArrayList(BidiMapItem), logical_to_visual: []usize, logical: BidiMapItem, direction: BidiClass) !void {
    const visual_index = items.items.len;
    logical_to_visual[logical.logical_index] = visual_index;
    try items.append(allocator, .{
        .logical_index = logical.logical_index,
        .visual_index = visual_index,
        .byte_start = logical.byte_start,
        .byte_len = logical.byte_len,
        .codepoint = logical.codepoint,
        .visual_codepoint = if (direction == .rtl) mirroredCodepoint(logical.codepoint) else logical.codepoint,
        .direction = direction,
    });
}

fn appendCodepoints(allocator: std.mem.Allocator, output: *std.ArrayList(u21), text: []const u8) !void {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        try output.append(allocator, codepoint);
    }
}

pub fn mirroredCodepoint(codepoint: u21) u21 {
    return switch (codepoint) {
        '(' => ')',
        ')' => '(',
        '[' => ']',
        ']' => '[',
        '{' => '}',
        '}' => '{',
        '<' => '>',
        '>' => '<',
        0x00ab => 0x00bb,
        0x00bb => 0x00ab,
        0x2039 => 0x203a,
        0x203a => 0x2039,
        0x2045 => 0x2046,
        0x2046 => 0x2045,
        0x3008 => 0x3009,
        0x3009 => 0x3008,
        0x300a => 0x300b,
        0x300b => 0x300a,
        0x300c => 0x300d,
        0x300d => 0x300c,
        0x300e => 0x300f,
        0x300f => 0x300e,
        else => codepoint,
    };
}

const WordKind = enum {
    none,
    single,
    latin_number,
    arabic,
    hebrew,
    devanagari,
};

fn appendSentenceIfNotBlank(allocator: std.mem.Allocator, sentences: *std.ArrayList(SentenceSegment), text: []const u8, start: usize, end: usize) !void {
    var cursor = start;
    while (cursor < end) {
        const codepoint_len = std.unicode.utf8ByteSequenceLength(text[cursor]) catch break;
        const codepoint = std.unicode.utf8Decode(text[cursor..][0..codepoint_len]) catch break;
        if (!isSentenceTrailingSpace(codepoint)) break;
        cursor += codepoint_len;
    }
    if (cursor >= end) return;
    try sentences.append(allocator, .{ .byte_start = start, .byte_len = end - start });
}

fn isSentenceTerminator(codepoint: u21) bool {
    return codepoint == '.' or codepoint == '!' or codepoint == '?' or
        codepoint == 0x3002 or codepoint == 0xff01 or codepoint == 0xff1f;
}

fn isSentenceTrailingSpace(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t' or codepoint == '\n' or codepoint == '\r';
}

fn isLineBreakSpace(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t';
}

fn isLineBreakEastAsian(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x11ff) or
        (codepoint >= 0x2e80 and codepoint <= 0x2eff) or
        (codepoint >= 0x2f00 and codepoint <= 0x2fdf) or
        (codepoint >= 0x3040 and codepoint <= 0x30ff) or
        (codepoint >= 0x3130 and codepoint <= 0x318f) or
        (codepoint >= 0x31a0 and codepoint <= 0x31ff) or
        (codepoint >= 0x3400 and codepoint <= 0x4dbf) or
        (codepoint >= 0x4e00 and codepoint <= 0x9fff) or
        (codepoint >= 0xac00 and codepoint <= 0xd7af) or
        (codepoint >= 0xf900 and codepoint <= 0xfaff) or
        (codepoint >= 0x20000 and codepoint <= 0x2fffd) or
        (codepoint >= 0x30000 and codepoint <= 0x3fffd);
}

fn wordKindForCodepoint(codepoint: u21) WordKind {
    if ((codepoint >= 'A' and codepoint <= 'Z') or
        (codepoint >= 'a' and codepoint <= 'z') or
        (codepoint >= '0' and codepoint <= '9') or
        codepoint == '_' or
        codepoint == '\'')
    {
        return .latin_number;
    }
    const script = scriptForCodepoint(codepoint);
    return switch (script) {
        .han, .hiragana, .katakana, .hangul => .single,
        .arabic => .arabic,
        .hebrew => .hebrew,
        .devanagari => .devanagari,
        else => .none,
    };
}

fn extendsGrapheme(previous: u21, current: u21, regional_indicator_count: usize) bool {
    // Keep this predicate conservative: it only returns true for continuation
    // codepoints that should share a caret stop with the previous codepoint.
    if (previous == '\r' and current == '\n') return true;
    if (previous == 0x200d) return true;
    if (current == 0x200d) return true;
    if (extendsHangulGrapheme(previous, current)) return true;
    if (isRegionalIndicator(previous) and isRegionalIndicator(current) and regional_indicator_count % 2 == 1) return true;
    return isCombiningMark(current) or isVariationSelector(current) or isEmojiModifier(current) or isSpacingMark(current);
}

const HangulGraphemeClass = enum {
    other,
    l,
    v,
    t,
    lv,
    lvt,
};

fn extendsHangulGrapheme(previous: u21, current: u21) bool {
    const previous_class = hangulGraphemeClass(previous);
    const current_class = hangulGraphemeClass(current);
    return switch (previous_class) {
        .l => current_class == .l or current_class == .v or current_class == .lv or current_class == .lvt,
        .v, .lv => current_class == .v or current_class == .t,
        .t, .lvt => current_class == .t,
        .other => false,
    };
}

fn hangulGraphemeClass(codepoint: u21) HangulGraphemeClass {
    if ((codepoint >= 0x1100 and codepoint <= 0x115f) or (codepoint >= 0xa960 and codepoint <= 0xa97c)) return .l;
    if ((codepoint >= 0x1160 and codepoint <= 0x11a7) or (codepoint >= 0xd7b0 and codepoint <= 0xd7c6)) return .v;
    if ((codepoint >= 0x11a8 and codepoint <= 0x11ff) or (codepoint >= 0xd7cb and codepoint <= 0xd7fb)) return .t;
    if (codepoint >= 0xac00 and codepoint <= 0xd7a3) {
        return if ((codepoint - 0xac00) % 28 == 0) .lv else .lvt;
    }
    return .other;
}

fn isCombiningMark(codepoint: u21) bool {
    return (codepoint >= 0x0300 and codepoint <= 0x036f) or
        (codepoint >= 0x1ab0 and codepoint <= 0x1aff) or
        (codepoint >= 0x1dc0 and codepoint <= 0x1dff) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        (codepoint >= 0xfe20 and codepoint <= 0xfe2f);
}

fn isVariationSelector(codepoint: u21) bool {
    return (codepoint >= 0xfe00 and codepoint <= 0xfe0f) or
        (codepoint >= 0xe0100 and codepoint <= 0xe01ef);
}

fn isEmojiModifier(codepoint: u21) bool {
    return codepoint >= 0x1f3fb and codepoint <= 0x1f3ff;
}

fn isRegionalIndicator(codepoint: u21) bool {
    return codepoint >= 0x1f1e6 and codepoint <= 0x1f1ff;
}

fn isSpacingMark(codepoint: u21) bool {
    return (codepoint >= 0x0903 and codepoint <= 0x0903) or
        (codepoint >= 0x093e and codepoint <= 0x0940) or
        (codepoint >= 0x0949 and codepoint <= 0x094c) or
        (codepoint >= 0x0982 and codepoint <= 0x0983) or
        (codepoint >= 0x09be and codepoint <= 0x09c0) or
        (codepoint >= 0x0bbe and codepoint <= 0x0bc2) or
        (codepoint >= 0x0d3e and codepoint <= 0x0d40);
}

fn scriptBelongsToRun(script: Script, current: Script) bool {
    // Common and inherited scripts adopt the current run script. If a run starts
    // as common, let the first strong script continue it.
    if (script == current) return true;
    if (script == .common or script == .inherited) return true;
    if (current == .common) return true;
    return false;
}

fn isCommonCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x0000 and codepoint <= 0x0040) or
        (codepoint >= 0x005b and codepoint <= 0x0060) or
        (codepoint >= 0x007b and codepoint <= 0x00a9) or
        (codepoint >= 0x2000 and codepoint <= 0x206f) or
        (codepoint >= 0x3000 and codepoint <= 0x303f);
}
