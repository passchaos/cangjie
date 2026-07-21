const std = @import("std");

/// Lightweight Unicode helpers used by the shaping/layout layers.
/// The tables are intentionally compact and cover the scripts and boundaries
/// currently exercised by Cangjie; they are not a replacement for the full UAX
/// datasets yet.
pub const Script = enum {
    common,
    inherited,
    latin,
    greek,
    cyrillic,
    han,
    hiragana,
    katakana,
    hangul,
    arabic,
    hebrew,
    syriac,
    armenian,
    thai,
    lao,
    devanagari,
    sinhala,
    tamil,
    ethiopic,
    georgian,
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
    grek = tag("grek"),
    cyrl = tag("cyrl"),
    hani = tag("hani"),
    hira = tag("hira"),
    kana = tag("kana"),
    hang = tag("hang"),
    arab = tag("arab"),
    hebr = tag("hebr"),
    syrc = tag("syrc"),
    armn = tag("armn"),
    thai = tag("thai"),
    lao = tag("lao "),
    dev2 = tag("dev2"),
    sinh = tag("sinh"),
    taml = tag("taml"),
    ethi = tag("ethi"),
    geor = tag("geor"),
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
        .greek => .grek,
        .cyrillic => .cyrl,
        .han => .hani,
        .hiragana => .hira,
        .katakana => .kana,
        .hangul => .hang,
        .arabic => .arab,
        .hebrew => .hebr,
        .syriac => .syrc,
        .armenian => .armn,
        .thai => .thai,
        .lao => .lao,
        .devanagari => .dev2,
        .sinhala => .sinh,
        .tamil => .taml,
        .ethiopic => .ethi,
        .georgian => .geor,
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
            .tamil, .thai, .lao => return .dflt,
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
    if (isLatinScriptCodepoint(codepoint)) return .latin;
    if (isGreekScriptCodepoint(codepoint)) return .greek;
    if (isCyrillicScriptCodepoint(codepoint)) return .cyrillic;
    if (codepoint >= 0x0300 and codepoint <= 0x036f) return .inherited;
    if (isHebrewScriptCodepoint(codepoint)) return .hebrew;
    if (isSyriacScriptCodepoint(codepoint)) return .syriac;
    if (isArmenianScriptCodepoint(codepoint)) return .armenian;
    if (isArabicScriptCodepoint(codepoint)) return .arabic;
    if (isThaiScriptCodepoint(codepoint)) return .thai;
    if (isLaoScriptCodepoint(codepoint)) return .lao;
    if (codepoint >= 0x0900 and codepoint <= 0x097f) return .devanagari;
    if (isSinhalaScriptCodepoint(codepoint)) return .sinhala;
    if (isTamilScriptCodepoint(codepoint)) return .tamil;
    if (isEthiopicScriptCodepoint(codepoint)) return .ethiopic;
    if (isGeorgianScriptCodepoint(codepoint)) return .georgian;
    if (codepoint >= 0x3040 and codepoint <= 0x309f) return .hiragana;
    if (codepoint >= 0x30a0 and codepoint <= 0x30ff) return .katakana;
    // Katakana is also encoded in phonetic-extension and halfwidth forms.
    // These are real script letters used by Japanese fonts; classifying them
    // as unknown would split shaping runs and bypass `kana` OpenType lookups.
    if (codepoint >= 0x31f0 and codepoint <= 0x31ff) return .katakana;
    if (codepoint >= 0xff66 and codepoint <= 0xff9d) return .katakana;
    if (codepoint == 0xff9e or codepoint == 0xff9f) return .inherited;
    // Modern and archaic Hangul Jamo must select the Hangul shaping script even
    // before they are composed into precomposed syllables. Grapheme clustering
    // already treats these ranges as Hangul L/V/T components; keeping script
    // classification in sync ensures conjoining-jamo text reaches `hang`
    // OpenType lookups instead of falling into DFLT/unknown runs.
    if (codepoint >= 0x1100 and codepoint <= 0x11ff) return .hangul;
    if (codepoint >= 0x3130 and codepoint <= 0x318f) return .hangul;
    if (codepoint >= 0xa960 and codepoint <= 0xa97f) return .hangul;
    if (codepoint >= 0xac00 and codepoint <= 0xd7af) return .hangul;
    if (codepoint >= 0xd7b0 and codepoint <= 0xd7ff) return .hangul;
    if (codepoint >= 0x3400 and codepoint <= 0x4dbf) return .han;
    if (codepoint >= 0x4e00 and codepoint <= 0x9fff) return .han;
    if (codepoint >= 0xf900 and codepoint <= 0xfaff) return .han;
    if (codepoint >= 0x20000 and codepoint <= 0x2fffd) return .han;
    if (codepoint >= 0x30000 and codepoint <= 0x3fffd) return .han;
    if (isCommonCodepoint(codepoint)) return .common;
    return .unknown;
}

fn isThaiScriptCodepoint(codepoint: u21) bool {
    // Thai bases, dependent vowels, tone marks, digits, and punctuation select
    // the `thai` OpenType script system. Treat the whole assigned block as one
    // shaping script so marks and bases are not split through DFLT runs before
    // GSUB/GPOS lookup selection.
    return codepoint >= 0x0e01 and codepoint <= 0x0e5b;
}

fn isLaoScriptCodepoint(codepoint: u21) bool {
    // Lao is encoded analogously to Thai and uses its own `lao ` OpenType
    // ScriptList entry. Keeping letters, dependent signs, digits, and Lao
    // punctuation in one run avoids losing script-specific shaping lookups.
    return codepoint >= 0x0e81 and codepoint <= 0x0edf;
}

fn isSyriacScriptCodepoint(codepoint: u21) bool {
    // Syriac is a right-to-left cursive script with script-specific OpenType
    // shaping. Its base letters, combining marks, abbreviations, and
    // supplementary letters all need to stay in one `syrc` shaping run rather
    // than being treated as DFLT/neutral text between Arabic/Hebrew support.
    return (codepoint >= 0x0700 and codepoint <= 0x074f) or
        (codepoint >= 0x0860 and codepoint <= 0x086f);
}

fn isGeorgianScriptCodepoint(codepoint: u21) bool {
    // Georgian has casing split across Mkhedruli, Mtavruli, Nuskhuri, and
    // historic Asomtavruli blocks. Fonts expose substitutions and positioning
    // under the `geor` ScriptList entry, so all Georgian letters must remain in
    // one shaping run instead of falling back to DFLT/unknown.
    return (codepoint >= 0x10a0 and codepoint <= 0x10ff) or
        (codepoint >= 0x1c90 and codepoint <= 0x1cbf) or
        (codepoint >= 0x2d00 and codepoint <= 0x2d2f);
}

fn isEthiopicScriptCodepoint(codepoint: u21) bool {
    // Ethiopic has no complex OpenType shaper, but fonts still commonly put
    // language and punctuation-sensitive substitutions/positioning under the
    // `ethi` ScriptList entry. Keep the base block, supplement, extended, and
    // extended-A letters/numerals in one LTR script run instead of routing them
    // through DFLT/unknown.
    return (codepoint >= 0x1200 and codepoint <= 0x139f) or
        (codepoint >= 0x2d80 and codepoint <= 0x2ddf) or
        (codepoint >= 0xab00 and codepoint <= 0xab2f);
}

fn isSinhalaScriptCodepoint(codepoint: u21) bool {
    // Sinhala vowels, consonants, dependent signs, punctuation, and numerals
    // live in one Unicode block and are shaped through the `sinh` OpenType
    // script system. Keeping the full block together prevents valid aksharas
    // from being split through DFLT/unknown runs before GSUB/GPOS selection.
    return codepoint >= 0x0d80 and codepoint <= 0x0dff;
}

fn isTamilScriptCodepoint(codepoint: u21) bool {
    // Tamil shaping depends on keeping consonants, dependent vowels, virama,
    // numerals, and historic additions in one `taml` script run. Unicode's
    // Tamil block has unassigned holes, but treating the assigned range as the
    // script is a safer primitive than splitting common Tamil syllables through
    // DFLT/unknown before OpenType lookup selection.
    return (codepoint >= 0x0b82 and codepoint <= 0x0bfa) or
        (codepoint >= 0x11fc0 and codepoint <= 0x11fff);
}

fn isArabicScriptCodepoint(codepoint: u21) bool {
    // Arabic Presentation Forms are compatibility encodings, but Unicode still
    // assigns them Script=Arabic. Legacy text and normalized-later input should
    // remain in Arabic RTL shaping runs so fonts can select `arab` features
    // instead of falling back to DFLT/neutral handling.
    return (codepoint >= 0x0600 and codepoint <= 0x06ff) or
        (codepoint >= 0x0750 and codepoint <= 0x077f) or
        (codepoint >= 0x0870 and codepoint <= 0x089f) or
        (codepoint >= 0x08a0 and codepoint <= 0x08ff) or
        (codepoint >= 0xfb50 and codepoint <= 0xfdff) or
        (codepoint >= 0xfe70 and codepoint <= 0xfeff);
}

fn isLatinScriptCodepoint(codepoint: u21) bool {
    // Keep all encoded Latin extension blocks in the Latin shaping script.
    // Precomposed Vietnamese, phonetic, and medievalist letters are alphabetic
    // bases, not inherited combining marks; splitting them into DFLT/unknown
    // runs prevents fonts from selecting their `latn` GSUB/GPOS features.
    return (codepoint >= 0x00c0 and codepoint <= 0x024f) or
        (codepoint >= 0x1d00 and codepoint <= 0x1d7f) or
        (codepoint >= 0x1d80 and codepoint <= 0x1dbf) or
        (codepoint >= 0x1e00 and codepoint <= 0x1eff) or
        (codepoint >= 0x2c60 and codepoint <= 0x2c7f) or
        (codepoint >= 0xa720 and codepoint <= 0xa7ff) or
        (codepoint >= 0xab30 and codepoint <= 0xab6f) or
        (codepoint >= 0x1df00 and codepoint <= 0x1dfff);
}

fn isGreekScriptCodepoint(codepoint: u21) bool {
    // Greek letters commonly rely on `grek` OpenType lookup selection for
    // mark positioning and localized alternates. Keep the full encoded Greek
    // script repertoire in one shaping script, including Coptic-era additions
    // and ancient Greek notation blocks whose Script property is Greek.
    return (codepoint >= 0x0370 and codepoint <= 0x03ff) or
        (codepoint >= 0x1d200 and codepoint <= 0x1d245) or
        (codepoint >= 0x1f00 and codepoint <= 0x1fff) or
        (codepoint >= 0x10140 and codepoint <= 0x1018f);
}

fn isHebrewScriptCodepoint(codepoint: u21) bool {
    // Hebrew presentation forms are compatibility characters, but they still
    // carry Script=Hebrew in Unicode. Treating them as unknown would split
    // Hebrew script runs and classify them as bidi-neutral, which breaks
    // low-level shaping and visual ordering for legacy or normalized-later text.
    return (codepoint >= 0x0590 and codepoint <= 0x05ff) or
        (codepoint >= 0xfb1d and codepoint <= 0xfb4f);
}

fn isArmenianScriptCodepoint(codepoint: u21) bool {
    // Armenian has dedicated OpenType shaping/script selection (`armn`) for
    // localized forms and mark positioning. Keep alphabetic letters,
    // punctuation, ligature codepoints, and modifier letters in one script run;
    // otherwise Armenian text is split through DFLT/unknown and loses script-
    // specific GSUB/GPOS coverage.
    return (codepoint >= 0x0531 and codepoint <= 0x058f) or
        (codepoint >= 0xfb13 and codepoint <= 0xfb17) or
        codepoint == 0x0559 or
        codepoint == 0x055a or
        codepoint == 0x055b or
        codepoint == 0x055c or
        codepoint == 0x055d or
        codepoint == 0x055e or
        codepoint == 0x055f;
}

fn isCyrillicScriptCodepoint(codepoint: u21) bool {
    // Cyrillic has several extension blocks used by living orthographies.
    // Classifying them as unknown would split runs and route GSUB/GPOS through
    // DFLT instead of the font's `cyrl` script system.
    return (codepoint >= 0x0400 and codepoint <= 0x052f) or
        (codepoint >= 0x1c80 and codepoint <= 0x1c8f) or
        (codepoint >= 0x2de0 and codepoint <= 0x2dff) or
        (codepoint >= 0xa640 and codepoint <= 0xa69f) or
        (codepoint >= 0x1e030 and codepoint <= 0x1e08f);
}

/// Classify only strong LTR/RTL scripts and neutral punctuation/spacing. The
/// higher-level bidi functions use this coarse class to build visual runs.
pub fn bidiClassForCodepoint(codepoint: u21) BidiClass {
    if (isBidiNumberCodepoint(codepoint)) return .number;
    const script = scriptForCodepoint(codepoint);
    return switch (script) {
        .arabic, .hebrew, .syriac => .rtl,
        .latin, .greek, .cyrillic, .han, .hiragana, .katakana, .hangul, .armenian, .thai, .lao, .devanagari, .sinhala, .tamil, .ethiopic, .georgian => .ltr,
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
    var cursor: usize = 0;
    while (cursor < text.len) {
        const cluster = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const next_index = decoded.next;
        cursor = next_index;
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

    var cursor: usize = 0;
    var cluster_start: ?usize = null;
    var cluster_end: usize = 0;
    var previous_codepoint: ?u21 = null;
    var last_non_extend_codepoint: ?u21 = null;
    var zwj_after_extended_pictographic = false;
    var zwj_after_indic_virama = false;
    var regional_indicator_count: usize = 0;
    // Approximate UAX #29 extended grapheme clusters for the scripts supported
    // here: combining marks, variation selectors, emoji modifiers, emoji ZWJ
    // chains, Indic virama conjuncts, regional-indicator pairs, and Hangul Jamo
    // syllable sequences.
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const byte_end = decoded.next;
        cursor = byte_end;

        if (cluster_start == null) {
            cluster_start = byte_start;
            cluster_end = byte_end;
            previous_codepoint = codepoint;
            last_non_extend_codepoint = if (isGraphemeExtendCodepoint(codepoint) or codepoint == 0x200d) null else codepoint;
            zwj_after_extended_pictographic = false;
            zwj_after_indic_virama = false;
            regional_indicator_count = if (isRegionalIndicator(codepoint)) 1 else 0;
            continue;
        }

        if (extendsGrapheme(previous_codepoint.?, codepoint, regional_indicator_count, zwj_after_extended_pictographic, zwj_after_indic_virama)) {
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
                // UAX #29's InCB rule keeps virama+ZWJ Indic conjuncts at a
                // single caret stop. Without this side state, "क्‍ष" splits
                // before the final consonant even though the ZWJ requests a
                // conjunct glyph.
                zwj_after_indic_virama = previous_codepoint.? == 0x094d;
            } else {
                zwj_after_extended_pictographic = false;
                zwj_after_indic_virama = false;
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
        zwj_after_indic_virama = false;
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
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const byte_end = decoded.next;
        cursor = byte_end;
        var kind = wordKindForCodepoint(codepoint);
        if (isAsciiApostrophe(codepoint)) {
            // Keep common contractions such as "don't" as one word without
            // letting leading/trailing quote marks become part of a word span.
            // This intentionally requires a word on the left and an alphanumeric
            // continuation on the right; otherwise the apostrophe behaves like
            // punctuation and closes the current segment.
            const next_kind = if (nextCodepointAt(text, byte_end)) |next_codepoint| wordKindForCodepoint(next_codepoint) else .none;
            kind = if (current_kind == .latin_number and next_kind == .latin_number) .latin_number else .none;
        }
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
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const byte_end = decoded.next;
        cursor = byte_end;
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
    for (clusters, 0..) |cluster, cluster_index| {
        const cluster_end = cluster.byte_start + cluster.byte_len;
        const codepoint = firstCodepoint(text[cluster.byte_start..cluster_end]) orelse continue;
        if (codepoint == '\n' or codepoint == '\r') {
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .hard });
        } else if (isLineBreakSpace(codepoint)) {
            try breaks.append(allocator, .{ .byte_offset = cluster_end, .kind = .soft });
        } else if (isLineBreakEastAsian(codepoint) and !nextClusterProhibitsEastAsianBreak(text, clusters, cluster_index)) {
            // East Asian text permits breaks between most ideographic/kana
            // clusters, but not immediately before closing punctuation. Keeping
            // that small UAX #14 invariant here prevents wrapped lines from
            // starting with common CJK closers such as U+3002 IDEOGRAPHIC FULL
            // STOP while preserving the compact line-break model.
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
    var cursor: usize = 0;
    while (cursor < text.len) {
        const cluster = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        const next_index = decoded.next;
        cursor = next_index;
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
    var cursor: usize = 0;
    while (cursor < text.len) {
        const byte_start = cursor;
        const decoded = decodeCodepointAt(text, cursor) orelse return error.InvalidUtf8;
        const codepoint = decoded.codepoint;
        cursor = decoded.next;
        try items.append(allocator, .{
            .logical_index = items.items.len,
            .visual_index = 0,
            .byte_start = byte_start,
            .byte_len = cursor - byte_start,
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
        0x207d => 0x207e,
        0x207e => 0x207d,
        0x208d => 0x208e,
        0x208e => 0x208d,
        0x2308 => 0x2309,
        0x2309 => 0x2308,
        0x230a => 0x230b,
        0x230b => 0x230a,
        0x2329 => 0x232a,
        0x232a => 0x2329,
        0x2768 => 0x2769,
        0x2769 => 0x2768,
        0x276a => 0x276b,
        0x276b => 0x276a,
        0x276c => 0x276d,
        0x276d => 0x276c,
        0x276e => 0x276f,
        0x276f => 0x276e,
        0x2770 => 0x2771,
        0x2771 => 0x2770,
        0x2772 => 0x2773,
        0x2773 => 0x2772,
        0x2774 => 0x2775,
        0x2775 => 0x2774,
        0x27c5 => 0x27c6,
        0x27c6 => 0x27c5,
        0x27e6 => 0x27e7,
        0x27e7 => 0x27e6,
        0x27e8 => 0x27e9,
        0x27e9 => 0x27e8,
        0x27ea => 0x27eb,
        0x27eb => 0x27ea,
        0x27ec => 0x27ed,
        0x27ed => 0x27ec,
        0x27ee => 0x27ef,
        0x27ef => 0x27ee,
        0x2983 => 0x2984,
        0x2984 => 0x2983,
        0x2985 => 0x2986,
        0x2986 => 0x2985,
        0x2987 => 0x2988,
        0x2988 => 0x2987,
        0x2989 => 0x298a,
        0x298a => 0x2989,
        0x298b => 0x298c,
        0x298c => 0x298b,
        0x298d => 0x2990,
        0x298e => 0x298f,
        0x298f => 0x298e,
        0x2990 => 0x298d,
        0x2991 => 0x2992,
        0x2992 => 0x2991,
        0x2993 => 0x2994,
        0x2994 => 0x2993,
        0x2995 => 0x2996,
        0x2996 => 0x2995,
        0x2997 => 0x2998,
        0x2998 => 0x2997,
        0x29d8 => 0x29d9,
        0x29d9 => 0x29d8,
        0x29da => 0x29db,
        0x29db => 0x29da,
        0x29fc => 0x29fd,
        0x29fd => 0x29fc,
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

test "Latin extension letters stay in Latin script runs" {
    const allocator = std.testing.allocator;

    const text = "Cafẹ Ạꞵ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.latin, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.latn, openTypeScriptTag(scriptForCodepoint(0x1ea0)));
    try std.testing.expectEqual(OpenTypeScriptTag.latn, openTypeScriptTag(scriptForCodepoint(0xa7b5)));
}

test "Greek and Cyrillic letters select script-specific OpenType tags" {
    const allocator = std.testing.allocator;

    const text = "ῼЖ ҄";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(Script.greek, runs[0].script);
    try std.testing.expectEqualStrings("ῼ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(Script.cyrillic, runs[1].script);
    try std.testing.expectEqualStrings("Ж ҄", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(OpenTypeScriptTag.grek, openTypeScriptTag(scriptForCodepoint(0x03a9)));
    try std.testing.expectEqual(OpenTypeScriptTag.grek, openTypeScriptTag(scriptForCodepoint(0x1f88)));
    try std.testing.expectEqual(OpenTypeScriptTag.cyrl, openTypeScriptTag(scriptForCodepoint(0x0416)));
    try std.testing.expectEqual(OpenTypeScriptTag.cyrl, openTypeScriptTag(scriptForCodepoint(0xa66e)));
}

test "Arabic presentation forms keep Arabic script and RTL direction" {
    const allocator = std.testing.allocator;

    const text = "اﻟ ﻢ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.arabic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.arab, openTypeScriptTag(scriptForCodepoint(0xfedf)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0xfedf));
}

test "Hebrew presentation forms keep Hebrew script and RTL direction" {
    const allocator = std.testing.allocator;

    const text = "אשׁ ב";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.hebrew, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.hebr, openTypeScriptTag(scriptForCodepoint(0xfb2a)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0xfb2a));
}

test "Syriac text selects Syriac script and RTL shaping direction" {
    const allocator = std.testing.allocator;

    const text = "ܫܠܡ ݍ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.syriac, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.syrc, openTypeScriptTag(scriptForCodepoint(0x072b)));
    try std.testing.expectEqual(OpenTypeScriptTag.syrc, openTypeScriptTag(scriptForCodepoint(0x086d)));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x072b));
    try std.testing.expectEqual(BidiClass.rtl, bidiClassForCodepoint(0x086d));
}

test "Thai and Lao text select script-specific OpenType tags" {
    const allocator = std.testing.allocator;

    const text = "ไทย ລາວ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(Script.thai, runs[0].script);
    try std.testing.expectEqualStrings("ไทย ", text[runs[0].byte_start..][0..runs[0].byte_len]);
    try std.testing.expectEqual(Script.lao, runs[1].script);
    try std.testing.expectEqualStrings("ລາວ", text[runs[1].byte_start..][0..runs[1].byte_len]);
    try std.testing.expectEqual(OpenTypeScriptTag.thai, openTypeScriptTag(scriptForCodepoint(0x0e17)));
    try std.testing.expectEqual(OpenTypeScriptTag.thai, openTypeScriptTag(scriptForCodepoint(0x0e48)));
    try std.testing.expectEqual(OpenTypeScriptTag.lao, openTypeScriptTag(scriptForCodepoint(0x0ea5)));
    try std.testing.expectEqual(OpenTypeScriptTag.lao, openTypeScriptTag(scriptForCodepoint(0x0eb5)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0e17));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0ea5));
}

test "Armenian text selects Armenian script, words, and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "Հայոց ﬓ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.armenian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.armn, openTypeScriptTag(scriptForCodepoint(0x0540)));
    try std.testing.expectEqual(OpenTypeScriptTag.armn, openTypeScriptTag(scriptForCodepoint(0xfb13)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0540));

    const words = try itemizeWordSegments(allocator, text);
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 2), words.len);
    try std.testing.expectEqualStrings("Հայոց", text[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("ﬓ", text[words[1].byte_start..][0..words[1].byte_len]);
}

test "bidi mirroring covers mathematical bracket pairs" {
    try std.testing.expectEqual(@as(u21, 0x27e9), mirroredCodepoint(0x27e8));
    try std.testing.expectEqual(@as(u21, 0x27e8), mirroredCodepoint(0x27e9));
    try std.testing.expectEqual(@as(u21, 0x2309), mirroredCodepoint(0x2308));
    try std.testing.expectEqual(@as(u21, 0x298f), mirroredCodepoint(0x298e));
    try std.testing.expectEqual(@as(u21, 0x298d), mirroredCodepoint(0x2990));
}

test "word segmentation keeps interior apostrophes but trims quotes" {
    const allocator = std.testing.allocator;

    const words = try itemizeWordSegments(allocator, "'alpha' don't rock 'n' roll");
    defer allocator.free(words);

    try std.testing.expectEqual(@as(usize, 5), words.len);
    try std.testing.expectEqualStrings("alpha", "'alpha' don't rock 'n' roll"[words[0].byte_start..][0..words[0].byte_len]);
    try std.testing.expectEqualStrings("don't", "'alpha' don't rock 'n' roll"[words[1].byte_start..][0..words[1].byte_len]);
    try std.testing.expectEqualStrings("rock", "'alpha' don't rock 'n' roll"[words[2].byte_start..][0..words[2].byte_len]);
    try std.testing.expectEqualStrings("n", "'alpha' don't rock 'n' roll"[words[3].byte_start..][0..words[3].byte_len]);
    try std.testing.expectEqualStrings("roll", "'alpha' don't rock 'n' roll"[words[4].byte_start..][0..words[4].byte_len]);
}

test "line breaks do not start lines with East Asian closing punctuation" {
    const allocator = std.testing.allocator;

    const text = "你。好";
    const breaks = try itemizeLineBreaks(allocator, text);
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 1), breaks.len);
    try std.testing.expectEqual(@as(usize, text.len), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
}

test "line breaks include breakable Unicode space separators" {
    const allocator = std.testing.allocator;

    const breaks = try itemizeLineBreaks(allocator, "a\xe3\x80\x80b\xc2\xa0c\xe2\x80\x83d");
    defer allocator.free(breaks);

    try std.testing.expectEqual(@as(usize, 2), breaks.len);
    try std.testing.expectEqual(@as(usize, 4), breaks[0].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[0].kind);
    try std.testing.expectEqual(@as(usize, 11), breaks[1].byte_offset);
    try std.testing.expectEqual(LineBreakKind.soft, breaks[1].kind);
}

test "sentence segmentation keeps Arabic-Indic decimal numbers together" {
    const allocator = std.testing.allocator;

    const text = "القيمة ١.٢ جيدة. انتهى";
    const sentences = try itemizeSentenceSegments(allocator, text);
    defer allocator.free(sentences);

    try std.testing.expectEqual(@as(usize, 2), sentences.len);
    try std.testing.expectEqualStrings("القيمة ١.٢ جيدة. ", text[sentences[0].byte_start..][0..sentences[0].byte_len]);
    try std.testing.expectEqualStrings("انتهى", text[sentences[1].byte_start..][0..sentences[1].byte_len]);
}

test "grapheme clusters keep Devanagari virama ZWJ conjuncts atomic" {
    const allocator = std.testing.allocator;

    const text = "क्‍ष क्ष";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 4), clusters.len);
    try std.testing.expectEqualStrings("क्‍ष", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("क्", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings("ष", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
}

test "grapheme clusters keep Thai and Lao marks with their base letters" {
    const allocator = std.testing.allocator;

    const text = "ก้ ກີ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ก้", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ກີ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "grapheme clusters keep Myanmar dependent signs with their base letters" {
    const allocator = std.testing.allocator;

    const text = "ကေ့ ကွာ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ကေ့", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ကွာ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "halfwidth katakana voiced marks stay in kana grapheme and script runs" {
    const allocator = std.testing.allocator;

    const text = "ｶﾞ ㇰ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ｶﾞ", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ㇰ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.katakana, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.kana, openTypeScriptTag(scriptForCodepoint(0xff76)));
    try std.testing.expectEqual(OpenTypeScriptTag.kana, openTypeScriptTag(scriptForCodepoint(0x31f0)));
}

test "grapheme clusters keep Khmer dependent signs with their base letters" {
    const allocator = std.testing.allocator;

    const text = "កា ក់ កៀ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("កា", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ក់", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("កៀ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
}

test "Telugu and Kannada dependent signs stay with base graphemes" {
    const allocator = std.testing.allocator;

    const text = "కి కా ಕಿ ಕಾ";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 7), clusters.len);
    try std.testing.expectEqualStrings("కి", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("కా", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ಕಿ", text[clusters[4].byte_start..][0..clusters[4].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[5].byte_start..][0..clusters[5].byte_len]);
    try std.testing.expectEqualStrings("ಕಾ", text[clusters[6].byte_start..][0..clusters[6].byte_len]);
}

test "Sinhala syllables keep dependent signs and select Sinhala OpenType script" {
    const allocator = std.testing.allocator;

    const text = "සිංහල ක්";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("සිං", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings("හ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("ල", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("ක්", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.sinhala, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.sinh, openTypeScriptTag(scriptForCodepoint(0x0dc3)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0dc3));
}

test "Tamil syllables keep marks and select Tamil OpenType script" {
    const allocator = std.testing.allocator;

    const text = "கி கோ 𑿀";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 5), clusters.len);
    try std.testing.expectEqualStrings("கி", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("கோ", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[3].byte_start..][0..clusters[3].byte_len]);
    try std.testing.expectEqualStrings("𑿀", text[clusters[4].byte_start..][0..clusters[4].byte_len]);

    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.tamil, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.taml, openTypeScriptTag(scriptForCodepoint(0x0b95)));
    try std.testing.expectEqual(OpenTypeScriptTag.taml, openTypeScriptTag(scriptForCodepoint(0x11fc0)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x0b95));
}

test "grapheme clusters attach non-Arabic prepend signs to following bases" {
    const allocator = std.testing.allocator;

    const text = "ൎക 𑂽𑂦";
    const clusters = try itemizeGraphemeClusters(allocator, text);
    defer allocator.free(clusters);

    try std.testing.expectEqual(@as(usize, 3), clusters.len);
    try std.testing.expectEqualStrings("ൎക", text[clusters[0].byte_start..][0..clusters[0].byte_len]);
    try std.testing.expectEqualStrings(" ", text[clusters[1].byte_start..][0..clusters[1].byte_len]);
    try std.testing.expectEqualStrings("𑂽𑂦", text[clusters[2].byte_start..][0..clusters[2].byte_len]);
}

test "Hangul conjoining jamo classify as Hangul script runs" {
    const allocator = std.testing.allocator;

    const text = "한 한";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.hangul, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.hang, openTypeScriptTag(scriptForCodepoint(0x1100)));
    try std.testing.expectEqual(OpenTypeScriptTag.hang, openTypeScriptTag(scriptForCodepoint(0xA960)));
    try std.testing.expectEqual(OpenTypeScriptTag.hang, openTypeScriptTag(scriptForCodepoint(0xD7B0)));
}

test "Georgian text selects Georgian script runs and OpenType tag" {
    const allocator = std.testing.allocator;

    const text = "ქართული Ქⴐ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.georgian, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.geor, openTypeScriptTag(scriptForCodepoint(0x10d0)));
    try std.testing.expectEqual(OpenTypeScriptTag.geor, openTypeScriptTag(scriptForCodepoint(0x1c90)));
    try std.testing.expectEqual(OpenTypeScriptTag.geor, openTypeScriptTag(scriptForCodepoint(0x2d10)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x10d0));
}

test "Ethiopic text selects Ethiopic script runs and direction" {
    const allocator = std.testing.allocator;

    const text = "ሰላም። ግዕዝ";
    const runs = try itemizeScriptRuns(allocator, text);
    defer allocator.free(runs);

    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expectEqual(Script.ethiopic, runs[0].script);
    try std.testing.expectEqual(@as(usize, 0), runs[0].byte_start);
    try std.testing.expectEqual(@as(usize, text.len), runs[0].byte_len);
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0x1230)));
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0x1380)));
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0x2d80)));
    try std.testing.expectEqual(OpenTypeScriptTag.ethi, openTypeScriptTag(scriptForCodepoint(0xab20)));
    try std.testing.expectEqual(BidiClass.ltr, bidiClassForCodepoint(0x1230));
}

const WordKind = enum {
    none,
    single,
    latin_number,
    arabic,
    hebrew,
    armenian,
    devanagari,
    sinhala,
    tamil,
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
    // case prevents obviously incorrect sentence cuts in UI text. Treat the
    // decimal digit sets already recognized by the bidi layer as digits here
    // too, so Arabic-Indic and Extended Arabic-Indic numbers are not split in
    // mixed-script documents.
    if (codepoint != '.') return false;
    const before = previous orelse return false;
    if (!isDecimalDigit(before)) return false;
    const after = nextCodepointAt(text, byte_end) orelse return false;
    return isDecimalDigit(after);
}

fn nextCodepointAt(text: []const u8, offset: usize) ?u21 {
    return (decodeCodepointAt(text, offset) orelse return null).codepoint;
}

fn isDecimalDigit(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
}

fn isAsciiApostrophe(codepoint: u21) bool {
    return codepoint == '\'';
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
    return codepoint == ' ' or
        codepoint == '\t' or
        // Unicode space separators that permit wrapping should behave like
        // ASCII spaces here. Keep no-break spaces out of this compact list so
        // callers do not wrap inside intentionally glued labels or numbers.
        codepoint == 0x1680 or
        (codepoint >= 0x2000 and codepoint <= 0x200a) or
        codepoint == 0x205f or
        codepoint == 0x3000;
}

fn nextClusterProhibitsEastAsianBreak(text: []const u8, clusters: []const GraphemeCluster, cluster_index: usize) bool {
    const next_index = cluster_index + 1;
    if (next_index >= clusters.len) return false;
    const next = clusters[next_index];
    const next_end = next.byte_start + next.byte_len;
    const next_codepoint = firstCodepoint(text[next.byte_start..next_end]) orelse return false;
    return isEastAsianClosingPunctuation(next_codepoint);
}

fn isEastAsianClosingPunctuation(codepoint: u21) bool {
    return switch (codepoint) {
        0x3001,
        0x3002,
        0xff0c,
        0xff0e,
        0xff1a,
        0xff1b,
        0xff01,
        0xff1f,
        0x3009,
        0x300b,
        0x300d,
        0x300f,
        0x3011,
        0x3015,
        0x3017,
        0x3019,
        0x301b,
        0xff09,
        0xff3d,
        0xff5d,
        0xff60,
        => true,
        else => false,
    };
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
        codepoint == '_')
    {
        return .latin_number;
    }
    const script = scriptForCodepoint(codepoint);
    return switch (script) {
        .han, .hiragana, .katakana, .hangul => .single,
        .arabic => .arabic,
        .hebrew => .hebrew,
        .armenian => .armenian,
        .devanagari => .devanagari,
        .sinhala => .sinhala,
        .tamil => .tamil,
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

fn extendsGrapheme(previous: u21, current: u21, regional_indicator_count: usize, zwj_after_extended_pictographic: bool, zwj_after_indic_virama: bool) bool {
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
    if (previous == 0x200d) {
        return (zwj_after_extended_pictographic and isExtendedPictographic(current)) or
            (zwj_after_indic_virama and isIndicConsonant(current));
    }
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
        // Sinhala nonspacing signs include anusvara/visarga-like marks,
        // dependent vowels, and virama. They are typed after the base but form
        // one akshara for caret and shaping boundaries.
        (codepoint >= 0x0d81 and codepoint <= 0x0d81) or
        codepoint == 0x0d82 or
        (codepoint >= 0x0dca and codepoint <= 0x0dca) or
        (codepoint >= 0x0dd2 and codepoint <= 0x0dd4) or
        codepoint == 0x0dd6 or
        // Tamil dependent vowel signs, pulli, and length mark are Extend in
        // UAX #29. Keeping them attached prevents caret/shaping clusters from
        // bisecting syllables such as கி, க், and கோ.
        codepoint == 0x0b82 or
        codepoint == 0x0bc0 or
        codepoint == 0x0bcd or
        codepoint == 0x0bd7 or
        // Thai and Lao vowels/tone marks are typed after their base consonant
        // but render as a single unit. Treating them as Extend avoids extra
        // caret stops between the consonant and its visible accent/vowel.
        (codepoint >= 0x0e31 and codepoint <= 0x0e31) or
        (codepoint >= 0x0e34 and codepoint <= 0x0e3a) or
        (codepoint >= 0x0e47 and codepoint <= 0x0e4e) or
        (codepoint >= 0x0eb1 and codepoint <= 0x0eb1) or
        (codepoint >= 0x0eb4 and codepoint <= 0x0ebc) or
        (codepoint >= 0x0ec8 and codepoint <= 0x0ecd) or
        // Khmer vowel signs, robat, coeng, and register/shifter signs are
        // encoded after the consonant but participate in one orthographic
        // syllable. Treating them as Extend preserves UAX #29 grapheme cluster
        // boundaries for Khmer text without requiring a full Khmer shaper.
        (codepoint >= 0x17b7 and codepoint <= 0x17bd) or
        codepoint == 0x17c6 or
        (codepoint >= 0x17c9 and codepoint <= 0x17d3) or
        codepoint == 0x17dd or
        // Myanmar dependent signs are encoded after the base consonant but
        // include both nonspacing and visible-spacing pieces of one orthographic
        // syllable. Keeping the compact GCB coverage here prevents caret and
        // shaping clusters from splitting between kinzi/medial/vowel/tone signs.
        (codepoint >= 0x102d and codepoint <= 0x1030) or
        (codepoint >= 0x1032 and codepoint <= 0x1037) or
        (codepoint >= 0x1039 and codepoint <= 0x103a) or
        (codepoint >= 0x103d and codepoint <= 0x103e) or
        (codepoint >= 0x1058 and codepoint <= 0x1059) or
        (codepoint >= 0x105e and codepoint <= 0x1060) or
        (codepoint >= 0x1071 and codepoint <= 0x1074) or
        codepoint == 0x1082 or
        (codepoint >= 0x1085 and codepoint <= 0x1086) or
        codepoint == 0x108d or
        codepoint == 0x109d or
        (codepoint >= 0x1ab0 and codepoint <= 0x1aff) or
        (codepoint >= 0x1dc0 and codepoint <= 0x1dff) or
        (codepoint >= 0x20d0 and codepoint <= 0x20ff) or
        (codepoint >= 0xfe20 and codepoint <= 0xfe2f) or
        // Halfwidth katakana voiced/semi-voiced marks are compatibility
        // combining marks (GCB=Extend). They are spacing glyphs, but a base
        // halfwidth kana plus U+FF9E/U+FF9F is one user-perceived character.
        codepoint == 0xff9e or
        codepoint == 0xff9f;
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

fn isIndicConsonant(codepoint: u21) bool {
    // Compact InCB=Consonant coverage for the Devanagari block Cangjie already
    // classifies as a shaped script. The range is deliberately narrow so ZWJ
    // after a virama only glues to real consonants, not punctuation or digits.
    return (codepoint >= 0x0915 and codepoint <= 0x0939) or
        codepoint == 0x0958 or
        codepoint == 0x0959 or
        codepoint == 0x095a or
        codepoint == 0x095b or
        codepoint == 0x095c or
        codepoint == 0x095d or
        codepoint == 0x095e or
        codepoint == 0x095f;
}

fn isGraphemePrependCodepoint(codepoint: u21) bool {
    // Grapheme_Cluster_Break=Prepend signs render with the following base and
    // therefore must not expose a caret/shaping boundary after themselves. Keep
    // this compact table current for the non-Arabic prepend scalars as well;
    // otherwise scripts such as Malayalam and Kaithi split a single user-
    // perceived cluster before the base character.
    return (codepoint >= 0x0600 and codepoint <= 0x0605) or
        codepoint == 0x06dd or
        codepoint == 0x070f or
        (codepoint >= 0x0890 and codepoint <= 0x0891) or
        codepoint == 0x08e2 or
        codepoint == 0x0d4e or
        codepoint == 0x110bd or
        codepoint == 0x110cd;
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
        // Telugu and Kannada dependent vowels/viramas are encoded after the
        // consonant but form a single orthographic unit. Covering both Extend
        // and SpacingMark classes here prevents layout/caret primitives from
        // creating invalid boundaries inside common South Indian syllables.
        (codepoint >= 0x0c00 and codepoint <= 0x0c04) or
        (codepoint >= 0x0c3c and codepoint <= 0x0c44) or
        (codepoint >= 0x0c46 and codepoint <= 0x0c48) or
        (codepoint >= 0x0c4a and codepoint <= 0x0c4d) or
        (codepoint >= 0x0c55 and codepoint <= 0x0c56) or
        (codepoint >= 0x0c62 and codepoint <= 0x0c63) or
        (codepoint >= 0x0cbc and codepoint <= 0x0cbe) or
        (codepoint >= 0x0cbf and codepoint <= 0x0cc4) or
        (codepoint >= 0x0cc6 and codepoint <= 0x0cc8) or
        (codepoint >= 0x0cca and codepoint <= 0x0ccd) or
        (codepoint >= 0x0cd5 and codepoint <= 0x0cd6) or
        (codepoint >= 0x0ce2 and codepoint <= 0x0ce3) or
        // Bengali dependent vowels/length marks with Grapheme_Cluster_Break=SpacingMark.
        // Bengali split vowels such as U+09CB are encoded after the consonant
        // but render around it; exposing a caret stop between base and vowel
        // would bisect one orthographic syllable and desynchronize shaping clusters.
        (codepoint >= 0x09be and codepoint <= 0x09c0) or
        (codepoint >= 0x09c7 and codepoint <= 0x09c8) or
        (codepoint >= 0x09cb and codepoint <= 0x09cc) or
        codepoint == 0x09d7 or
        (codepoint >= 0x0dcf and codepoint <= 0x0dd1) or
        (codepoint >= 0x0dd8 and codepoint <= 0x0ddf) or
        (codepoint >= 0x0bbe and codepoint <= 0x0bbf) or
        (codepoint >= 0x0bc1 and codepoint <= 0x0bc2) or
        (codepoint >= 0x0bc6 and codepoint <= 0x0bc8) or
        (codepoint >= 0x0bca and codepoint <= 0x0bcc) or
        (codepoint >= 0x0d3e and codepoint <= 0x0d40) or
        // Khmer split/spaced dependent vowels are GCB=SpacingMark. They render
        // around or after the base consonant, so a cluster break before them
        // would expose an invalid low-level caret/shaping boundary.
        codepoint == 0x17b6 or
        (codepoint >= 0x17be and codepoint <= 0x17c5) or
        (codepoint >= 0x17c7 and codepoint <= 0x17c8) or
        (codepoint >= 0x102b and codepoint <= 0x102c) or
        codepoint == 0x1031 or
        codepoint == 0x1038 or
        (codepoint >= 0x103b and codepoint <= 0x103c) or
        (codepoint >= 0x1056 and codepoint <= 0x1057) or
        (codepoint >= 0x1062 and codepoint <= 0x1064) or
        (codepoint >= 0x1067 and codepoint <= 0x106d) or
        (codepoint >= 0x1083 and codepoint <= 0x1084) or
        (codepoint >= 0x1087 and codepoint <= 0x108c) or
        codepoint == 0x108f or
        (codepoint >= 0x109a and codepoint <= 0x109c);
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
