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
    number,
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
    var cursor: usize = 0;
    while (cursor < text.len) {
        const decoded = decodeCodepointAt(text, cursor) orelse return .dflt;
        const codepoint = decoded.codepoint;
        cursor = decoded.next;
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

const DecodedCodepoint = struct {
    codepoint: u21,
    next: usize,
};

fn decodeCodepointAt(text: []const u8, cursor: usize) ?DecodedCodepoint {
    if (cursor >= text.len) return null;
    const len = std.unicode.utf8ByteSequenceLength(text[cursor]) catch return null;
    const end = cursor + @as(usize, len);
    if (end > text.len) return null;
    const codepoint = std.unicode.utf8Decode(text[cursor..end]) catch return null;
    return .{ .codepoint = codepoint, .next = end };
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
    if (isBidiNumberCodepoint(codepoint)) return .number;
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

        if (current_direction.? == .rtl and bidi_class == .number) {
            const split_at = neutral_start orelse cluster;
            try runs.append(allocator, .{
                .direction = current_direction.?,
                .byte_start = run_start,
                .byte_len = split_at - run_start,
            });
            current_direction = .number;
            run_start = neutral_start orelse cluster;
            run_end = next_index;
            neutral_start = null;
            continue;
        }

        if (current_direction.? == .number and bidi_class == .rtl) {
            const split_at = neutral_start orelse cluster;
            try runs.append(allocator, .{
                .direction = current_direction.?,
                .byte_start = run_start,
                .byte_len = split_at - run_start,
            });
            current_direction = .rtl;
            run_start = neutral_start orelse cluster;
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
            try appendRtlCodepointsByGrapheme(allocator, &output, slice);
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
            try appendRtlVisualBidiItemsByGrapheme(allocator, &items, logical_to_visual, logical, text, run, range);
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
    var last_non_extend_codepoint: ?u21 = null;
    var zwj_after_extended_pictographic = false;
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
            last_non_extend_codepoint = if (isGraphemeExtendCodepoint(codepoint) or codepoint == 0x200d) null else codepoint;
            zwj_after_extended_pictographic = false;
            regional_indicator_count = if (isRegionalIndicator(codepoint)) 1 else 0;
            continue;
        }

        if (extendsGrapheme(previous_codepoint.?, codepoint, regional_indicator_count, zwj_after_extended_pictographic)) {
            cluster_end = byte_end;
            if (codepoint == 0x200d) {
                // GB11 only suppresses the break after ZWJ for emoji ZWJ
                // sequences. A generic "letter + ZWJ + letter" should keep the
                // ZWJ with the previous cluster (GB9) but still break before the
                // following non-emoji letter.
                zwj_after_extended_pictographic = if (last_non_extend_codepoint) |last|
                    isExtendedPictographic(last)
                else
                    false;
            } else {
                zwj_after_extended_pictographic = false;
                if (!isGraphemeExtendCodepoint(codepoint)) {
                    last_non_extend_codepoint = codepoint;
                }
            }
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
        last_non_extend_codepoint = if (isGraphemeExtendCodepoint(codepoint) or codepoint == 0x200d) null else codepoint;
        zwj_after_extended_pictographic = false;
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
            if (isWordExtender(codepoint)) {
                // UAX #29 treats Extend/Format-like codepoints as part of the
                // surrounding word. Preserve their bytes so caret and selection
                // logic does not strand accents, variation selectors, or joiners
                // outside the word segment they visually modify.
                if (current_kind != .none) {
                    word_end = byte_end;
                } else if (words.items.len > 0) {
                    const last = &words.items[words.items.len - 1];
                    const last_end = last.byte_start + last.byte_len;
                    if (last_end == byte_start) last.byte_len = byte_end - last.byte_start;
                }
                continue;
            }
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
    var previous_codepoint: ?u21 = null;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.i < text.len) {
        const byte_start = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        const byte_end = it.i;
        sentence_end = byte_end;

        if (pending_break and !isSentenceTrailingSpace(codepoint) and !isSentenceTrailingClose(codepoint)) {
            try appendSentenceIfNotBlank(allocator, &sentences, text, sentence_start, byte_start);
            sentence_start = byte_start;
            pending_break = false;
        }

        if (isSentenceTerminator(codepoint) and !isMidNumberSentencePeriod(codepoint, previous_codepoint, text, byte_end)) {
            pending_break = true;
        }
        previous_codepoint = codepoint;
    }

    try appendSentenceIfNotBlank(allocator, &sentences, text, sentence_start, sentence_end);
    return try sentences.toOwnedSlice(allocator);
}

pub fn itemizeLineBreaks(allocator: std.mem.Allocator, text: []const u8) ![]LineBreak {
    var breaks = std.ArrayList(LineBreak).empty;
    errdefer breaks.deinit(allocator);

    // Emit hard breaks for CR/LF and soft opportunities after whitespace or
    // East Asian grapheme clusters. Break offsets must point to cluster
    // boundaries: otherwise an ideograph followed by a variation selector, or a
    // kana base followed by a combining mark, could be split between the base
    // and its visual modifier.
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    for (clusters) |cluster| {
        const cluster_end = cluster.byte_start + cluster.byte_len;
        const codepoint = firstCodepoint(text[cluster.byte_start..cluster_end]) orelse continue;
        if (codepoint == '\n' or codepoint == '\r') {
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .hard });
        } else if (isLineBreakSpace(codepoint)) {
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .soft });
        } else if (isLineBreakEastAsian(codepoint)) {
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .soft });
        }
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
            if (current_script.? == .common and script != .common and script != .inherited) {
                current_script = script;
            }
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

fn isBidiNumberCodepoint(codepoint: u21) bool {
    // Keep common European and Arabic-Indic decimal sequences in logical LTR
    // order even when the surrounding paragraph/run order is RTL. This is a
    // deliberately compact subset of UAX #9 weak-type handling, but it avoids
    // the most visible failure mode of rendering "12" as "21" in Hebrew/Arabic
    // text while preserving existing neutral punctuation behavior.
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
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

const LogicalRange = struct { start: usize, end: usize };

fn logicalRangeForBytes(logical: []const BidiMapItem, byte_start: usize, byte_end: usize) LogicalRange {
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

fn appendRtlCodepointsByGrapheme(allocator: std.mem.Allocator, output: *std.ArrayList(u21), text: []const u8) !void {
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);
    var cluster_index = clusters.len;
    while (cluster_index > 0) {
        cluster_index -= 1;
        const cluster = clusters[cluster_index];
        const start_len = output.items.len;
        try appendCodepoints(allocator, output, text[cluster.byte_start .. cluster.byte_start + cluster.byte_len]);
        for (output.items[start_len..]) |*codepoint| {
            codepoint.* = mirroredCodepoint(codepoint.*);
        }
    }
}

fn appendRtlVisualBidiItemsByGrapheme(allocator: std.mem.Allocator, items: *std.ArrayList(BidiMapItem), logical_to_visual: []usize, logical: []const BidiMapItem, text: []const u8, run: BidiRun, range: LogicalRange) !void {
    const clusters = try itemizeGraphemeClusters(allocator, text[run.byte_start .. run.byte_start + run.byte_len]);
    defer allocator.free(clusters);
    var cluster_index = clusters.len;
    while (cluster_index > 0) {
        cluster_index -= 1;
        const cluster = clusters[cluster_index];
        const cluster_start = run.byte_start + cluster.byte_start;
        const cluster_end = cluster_start + cluster.byte_len;
        const cluster_range = logicalRangeForBytes(logical, cluster_start, cluster_end);
        var index = @max(cluster_range.start, range.start);
        const end = @min(cluster_range.end, range.end);
        while (index < end) : (index += 1) {
            try appendVisualBidiItem(allocator, items, logical_to_visual, logical[index], run.direction);
        }
    }
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

fn firstCodepoint(text: []const u8) ?u21 {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    return it.nextCodepoint();
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

fn isMidNumberSentencePeriod(codepoint: u21, previous: ?u21, text: []const u8, byte_end: usize) bool {
    // UAX #29 keeps full stops and similar STerm codepoints inside numeric
    // tokens (SB8), e.g. version strings and decimal values. The segmenter is
    // intentionally compact, but avoiding breaks in the common digit '.' digit
    // case prevents obviously incorrect sentence cuts in UI text.
    if (codepoint != '.') return false;
    const before = previous orelse return false;
    if (!isAsciiDigit(before)) return false;
    const after = nextCodepointAt(text, byte_end) orelse return false;
    return isAsciiDigit(after);
}

fn nextCodepointAt(text: []const u8, offset: usize) ?u21 {
    if (offset >= text.len) return null;
    var it = std.unicode.Utf8Iterator{ .bytes = text[offset..], .i = 0 };
    return it.nextCodepoint();
}

fn isAsciiDigit(codepoint: u21) bool {
    return codepoint >= '0' and codepoint <= '9';
}

fn isSentenceTrailingSpace(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t' or codepoint == '\n' or codepoint == '\r';
}

fn isSentenceTrailingClose(codepoint: u21) bool {
    return switch (codepoint) {
        '\'', '"', ')', ']', '}', 0x00bb, 0x2019, 0x201d, 0x3009, 0x300b, 0x300d, 0x300f, 0x3011, 0x3015, 0x3017, 0x3019, 0x301b => true,
        else => false,
    };
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

fn isWordExtender(codepoint: u21) bool {
    return codepoint == 0x200c or
        codepoint == 0x200d or
        isCombiningMark(codepoint) or
        isVariationSelector(codepoint) or
        isEmojiModifier(codepoint) or
        isSpacingMark(codepoint) or
        isWordFormat(codepoint);
}

fn isWordFormat(codepoint: u21) bool {
    return codepoint == 0x00ad or
        codepoint == 0x061c or
        codepoint == 0x180e or
        codepoint == 0x200e or
        codepoint == 0x200f or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x2064) or
        (codepoint >= 0x2066 and codepoint <= 0x206f) or
        codepoint == 0xfeff;
}

fn extendsGrapheme(previous: u21, current: u21, regional_indicator_count: usize, zwj_after_extended_pictographic: bool) bool {
    // Keep this predicate conservative: it only returns true for continuation
    // codepoints that should share a caret stop with the previous codepoint.
    if (previous == '\r' and current == '\n') return true;
    // UAX #29 GB4/GB5 make controls atomic grapheme clusters. Check this
    // before Prepend/Extend/ZWJ rules so stray format or paragraph controls do
    // not absorb adjacent marks and hide caret stops around them.
    if (isGraphemeControl(previous) or isGraphemeControl(current)) return false;
    if (isGraphemePrependCodepoint(previous)) return true;
    if (current == 0x200d) return true;
    if (extendsHangulGrapheme(previous, current)) return true;
    if (isRegionalIndicator(previous) and isRegionalIndicator(current) and regional_indicator_count % 2 == 1) return true;
    if (isGraphemeExtendCodepoint(current)) return true;
    if (previous == 0x200d) return zwj_after_extended_pictographic and isExtendedPictographic(current);
    return false;
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
        // These compact script-specific ranges cover combining marks for the
        // non-Latin scripts Cangjie already itemizes. Without them, accents,
        // vowel signs, and viramas become separate grapheme/word units even
        // though UAX #29 treats them as Extend.
        (codepoint >= 0x0591 and codepoint <= 0x05bd) or
        codepoint == 0x05bf or
        (codepoint >= 0x05c1 and codepoint <= 0x05c2) or
        (codepoint >= 0x05c4 and codepoint <= 0x05c5) or
        codepoint == 0x05c7 or
        (codepoint >= 0x0610 and codepoint <= 0x061a) or
        (codepoint >= 0x064b and codepoint <= 0x065f) or
        codepoint == 0x0670 or
        (codepoint >= 0x06d6 and codepoint <= 0x06dc) or
        (codepoint >= 0x06df and codepoint <= 0x06e4) or
        (codepoint >= 0x06e7 and codepoint <= 0x06e8) or
        (codepoint >= 0x06ea and codepoint <= 0x06ed) or
        (codepoint >= 0x0900 and codepoint <= 0x0902) or
        codepoint == 0x093a or
        codepoint == 0x093c or
        (codepoint >= 0x0941 and codepoint <= 0x0948) or
        codepoint == 0x094d or
        (codepoint >= 0x0951 and codepoint <= 0x0957) or
        (codepoint >= 0x0962 and codepoint <= 0x0963) or
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

fn isGraphemeExtendCodepoint(codepoint: u21) bool {
    return codepoint == 0x200c or
        isCombiningMark(codepoint) or
        isVariationSelector(codepoint) or
        isEmojiModifier(codepoint) or
        isEmojiTagCodepoint(codepoint) or
        isSpacingMark(codepoint);
}

fn isEmojiTagCodepoint(codepoint: u21) bool {
    // Emoji flag tag sequences (for example subdivision flags such as England)
    // encode their tag letters in Plane 14. Unicode assigns these scalars
    // Grapheme_Cluster_Break=Extend, so they must stay attached to the
    // preceding pictograph instead of creating one caret stop per tag byte.
    return codepoint >= 0xe0020 and codepoint <= 0xe007f;
}

fn isGraphemePrependCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x0600 and codepoint <= 0x0605) or
        codepoint == 0x06dd or
        codepoint == 0x070f or
        (codepoint >= 0x0890 and codepoint <= 0x0891) or
        codepoint == 0x08e2;
}

fn isGraphemeControl(codepoint: u21) bool {
    return (codepoint >= 0x0000 and codepoint <= 0x001f) or
        (codepoint >= 0x007f and codepoint <= 0x009f) or
        // Grapheme_Cluster_Break=Control also includes several format and
        // separator scalars. They are invisible text controls, but UAX #29
        // still gives them their own caret stop; otherwise a following Extend
        // mark can be incorrectly absorbed into the control's cluster.
        codepoint == 0x00ad or
        codepoint == 0x061c or
        codepoint == 0x180e or
        codepoint == 0x200b or
        (codepoint >= 0x200e and codepoint <= 0x200f) or
        codepoint == 0x2028 or
        codepoint == 0x2029 or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x206f) or
        codepoint == 0xfeff or
        (codepoint >= 0xfff0 and codepoint <= 0xfff8);
}

fn isExtendedPictographic(codepoint: u21) bool {
    // Compact Extended_Pictographic coverage for emoji families/professions and
    // symbol ZWJ sequences commonly encountered by text editors. This is not
    // the full emoji-data.txt table, but it makes GB11 conditional instead of
    // treating every ZWJ as a universal grapheme glue.
    return codepoint == 0x00a9 or
        codepoint == 0x00ae or
        codepoint == 0x203c or
        codepoint == 0x2049 or
        codepoint == 0x2122 or
        codepoint == 0x2139 or
        (codepoint >= 0x2194 and codepoint <= 0x21aa) or
        codepoint == 0x231a or
        codepoint == 0x231b or
        codepoint == 0x2328 or
        codepoint == 0x23cf or
        (codepoint >= 0x23e9 and codepoint <= 0x23f3) or
        (codepoint >= 0x23f8 and codepoint <= 0x23fa) or
        codepoint == 0x24c2 or
        codepoint == 0x25aa or
        codepoint == 0x25ab or
        codepoint == 0x25b6 or
        codepoint == 0x25c0 or
        (codepoint >= 0x25fb and codepoint <= 0x25fe) or
        (codepoint >= 0x2600 and codepoint <= 0x27bf) or
        codepoint == 0x2934 or
        codepoint == 0x2935 or
        (codepoint >= 0x2b05 and codepoint <= 0x2b55) or
        codepoint == 0x3030 or
        codepoint == 0x303d or
        codepoint == 0x3297 or
        codepoint == 0x3299 or
        (codepoint >= 0x1f000 and codepoint <= 0x1faff);
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
