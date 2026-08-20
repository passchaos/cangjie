const std = @import("std");
const bin = @import("../binary.zig");
const name_languages = @import("../font/tables/metadata/name_languages.zig");

pub const Error = error{
    BadSfnt,
    InvalidName,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const Table = struct {
    offset: usize = 0,
    length: usize,
};

pub const NameId = enum(u16) {
    copyright = 0,
    family = 1,
    subfamily = 2,
    unique_id = 3,
    full_name = 4,
    version = 5,
    postscript_name = 6,
    typographic_family = 16,
    typographic_subfamily = 17,
    compatible_full_name = 18,
    sample_text = 19,
    wws_family = 21,
    wws_subfamily = 22,
    _,
};

pub const Encoding = enum {
    utf16_be,
    raw_bytes,
};

pub const RecordInfo = struct {
    platform_id: u16,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    storage_offset: usize,
    string: []const u8,
    encoding: Encoding,

    pub fn decodeUtf8(self: RecordInfo, out: []u8) Error![]const u8 {
        return switch (self.encoding) {
            .utf16_be => try decodeUtf16BeName(self.string, out),
            .raw_bytes => try decodeSingleByteName(self.string, out),
        };
    }

    /// Return the BCP-47 language of this record when the platform language
    /// identifier has a standardized mapping. Format-1 language-tag records
    /// are resolved by `LocalizedString.language` because they need the name
    /// table's LangTagRecord storage.
    pub fn legacyLanguage(self: RecordInfo) ?[]const u8 {
        return switch (self.platform_id) {
            1, 3 => name_languages.find(self.language_id),
            else => null,
        };
    }
};

/// One localized string selected by name ID. The raw value and optional
/// format-1 language tag borrow the font bytes; legacy language mappings are
/// static. Decode the value into caller storage with `decodeUtf8`.
pub const LocalizedString = struct {
    record: RecordInfo,
    language: ?Language = null,

    pub const Language = union(enum) {
        static: []const u8,
        utf16_be: []const u8,
    };

    pub fn decodeUtf8(self: LocalizedString, out: []u8) Error![]const u8 {
        return self.record.decodeUtf8(out);
    }

    /// Decode the optional BCP-47 language into caller storage. Legacy
    /// platform identifiers return a static slice; format-1 tags use `out`.
    pub fn languageUtf8(self: LocalizedString, out: []u8) Error!?[]const u8 {
        const language = self.language orelse return null;
        return switch (language) {
            .static => |value| value,
            .utf16_be => |value| try decodeUtf16BeName(value, out),
        };
    }
};

pub const LanguageTagInfo = struct {
    language_id: u16,
    storage_offset: usize,
    string: []const u8,

    pub fn decodeUtf8(self: LanguageTagInfo, out: []u8) Error![]const u8 {
        return try decodeUtf16BeName(self.string, out);
    }
};

const NameRecord = struct {
    platform_id: u16,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    offset: usize,
    length: usize,

    fn key(self: NameRecord) NameRecordKey {
        return .{
            .platform_id = self.platform_id,
            .encoding_id = self.encoding_id,
            .language_id = self.language_id,
            .name_id = self.name_id,
        };
    }
};

const NameRecordKey = struct {
    platform_id: u16,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
};

const NameTableLayout = struct {
    format: u16,
    count: u16,
    storage_offset: usize,
    storage_length: usize,
    lang_tag_records_start: usize = 0,
    lang_tag_count: usize = 0,
};

const PostScriptNamePolicy = enum {
    tolerate_invalid,
    strict,
};

const name_records_start: usize = 6;
const name_record_size: usize = 12;
const lang_tag_record_size: usize = 4;

pub fn validate(data: []const u8, name: Table) Error!void {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    var previous_key: ?NameRecordKey = null;
    for (0..layout.count) |index| {
        const record = try readNameRecord(table, index);
        try validateNameRecordOrdering(previous_key, record.key());
        previous_key = record.key();
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data, .tolerate_invalid);
    }
}

pub fn records(allocator: std.mem.Allocator, data: []const u8, name: Table) Error![]RecordInfo {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    const infos = try allocator.alloc(RecordInfo, layout.count);
    errdefer allocator.free(infos);

    var previous_key: ?NameRecordKey = null;
    for (infos, 0..) |*info, index| {
        const record = try readNameRecord(table, index);
        try validateNameRecordOrdering(previous_key, record.key());
        previous_key = record.key();
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data, .tolerate_invalid);
        info.* = .{
            .platform_id = record.platform_id,
            .encoding_id = record.encoding_id,
            .language_id = record.language_id,
            .name_id = record.name_id,
            .storage_offset = record.offset,
            .string = string_data,
            .encoding = if (isUtf16Name(record)) .utf16_be else .raw_bytes,
        };
    }
    return infos;
}

pub fn languageTags(allocator: std.mem.Allocator, data: []const u8, name: Table) Error![]LanguageTagInfo {
    // LangTagRecord payloads are part of the same name-table trust boundary as
    // normal name records. Revalidate the complete table first so callers never
    // receive language metadata from a table whose record directory would be
    // rejected by `records` or `readString`.
    try validate(data, name);

    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    if (layout.format != 1) return try allocator.alloc(LanguageTagInfo, 0);

    const infos = try allocator.alloc(LanguageTagInfo, layout.lang_tag_count);
    errdefer allocator.free(infos);
    for (infos, 0..) |*info, index| {
        const string_data = try languageTagString(table, layout, index);
        info.* = .{
            .language_id = languageIdForTagIndex(index),
            .storage_offset = try languageTagStorageOffset(table, layout, index),
            .string = string_data,
        };
    }
    return infos;
}

pub fn languageTag(data: []const u8, name: Table, language_id: u16, out: []u8) Error!?[]const u8 {
    if (language_id < 0x8000) return null;
    try validate(data, name);

    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    if (layout.format != 1) return null;

    const index: usize = @intCast(language_id & 0x7fff);
    if (index >= layout.lang_tag_count) return null;
    return try decodeUtf16BeName(try languageTagString(table, layout, index), out);
}

/// Enumerate all localized strings for one name ID in canonical name-table
/// order. The returned array is caller-owned; its string and language payloads
/// borrow `data`. This is the allocation-explicit counterpart of Skrifa's
/// `MetadataProvider::localized_strings` iterator.
pub fn localizedStrings(
    allocator: std.mem.Allocator,
    data: []const u8,
    name: Table,
    name_id: u16,
) Error![]LocalizedString {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    var count: usize = 0;
    var previous_key: ?NameRecordKey = null;
    for (0..layout.count) |index| {
        const record = try readNameRecord(table, index);
        try validateNameRecordOrdering(previous_key, record.key());
        previous_key = record.key();
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data, .tolerate_invalid);
        if (record.name_id == name_id) count += 1;
    }

    const values = try allocator.alloc(LocalizedString, count);
    errdefer allocator.free(values);
    var value_index: usize = 0;
    for (0..layout.count) |index| {
        const record = try readNameRecord(table, index);
        if (record.name_id != name_id) continue;
        const string_data = try nameRecordString(table, layout, record);
        values[value_index] = .{
            .record = .{
                .platform_id = record.platform_id,
                .encoding_id = record.encoding_id,
                .language_id = record.language_id,
                .name_id = record.name_id,
                .storage_offset = record.offset,
                .string = string_data,
                .encoding = if (isUtf16Name(record)) .utf16_be else .raw_bytes,
            },
            .language = try localizedLanguage(table, layout, record),
        };
        value_index += 1;
    }
    return values;
}

/// Select en-US, then en, then language-neutral, then the first matching name.
///
/// This parser is intended for immutable faces whose complete name table was
/// validated during `Face.parse`. It still bounds-checks every accessed record
/// but does not allocate an intermediate array or repeat whole-table ordering
/// and encoding validation.
pub fn englishOrFirstParsed(
    data: []const u8,
    name: Table,
    name_id: u16,
) Error!?LocalizedString {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    var best: ?LocalizedString = null;
    var best_rank: u2 = 0;
    for (0..layout.count) |index| {
        const record = try readNameRecord(table, index);
        if (record.name_id != name_id) continue;
        const string_data = try nameRecordString(table, layout, record);
        const value = LocalizedString{
            .record = .{
                .platform_id = record.platform_id,
                .encoding_id = record.encoding_id,
                .language_id = record.language_id,
                .name_id = record.name_id,
                .storage_offset = record.offset,
                .string = string_data,
                .encoding = if (isUtf16Name(record)) .utf16_be else .raw_bytes,
            },
            .language = try localizedLanguage(table, layout, record),
        };
        const rank = englishRank(value.language);
        if (rank == 3) return value;
        if (best == null or rank > best_rank) {
            best = value;
            best_rank = rank;
        }
    }
    return best;
}

fn englishRank(language: ?LocalizedString.Language) u2 {
    const value = language orelse return 1;
    return switch (value) {
        .static => |tag| if (std.mem.eql(u8, tag, "en-US"))
            3
        else if (std.mem.eql(u8, tag, "en"))
            2
        else
            0,
        .utf16_be => |tag| if (utf16BeAsciiEquals(tag, "en-US"))
            3
        else if (utf16BeAsciiEquals(tag, "en"))
            2
        else
            0,
    };
}

fn utf16BeAsciiEquals(data: []const u8, expected: []const u8) bool {
    if (data.len != expected.len * 2) return false;
    for (expected, 0..) |byte, index| {
        if (data[index * 2] != 0 or data[index * 2 + 1] != byte) return false;
    }
    return true;
}

fn localizedLanguage(
    table: []const u8,
    layout: NameTableLayout,
    record: NameRecord,
) Error!?LocalizedString.Language {
    if (layout.format == 1 and record.language_id >= 0x8000) {
        const index: usize = @intCast(record.language_id - 0x8000);
        return .{ .utf16_be = try languageTagString(table, layout, index) };
    }
    return switch (record.platform_id) {
        1, 3 => if (name_languages.find(record.language_id)) |tag|
            .{ .static = tag }
        else
            null,
        else => null,
    };
}

/// Compact index of name IDs that have at least one structurally valid string.
/// fvar and STAT do not identify a platform/language-specific record; they
/// reference a name ID and let normal name-table fallback choose the localized
/// string later. Tracking only IDs mirrors that contract while still forcing
/// all referenced user-facing metadata to be present and decodable.
pub const NameIdIndex = struct {
    words: [1024]u64 = .{0} ** 1024,

    fn add(self: *NameIdIndex, name_id: u16) void {
        const word_index = @as(usize, name_id) / 64;
        const bit_index: u6 = @intCast(name_id & 63);
        self.words[word_index] |= @as(u64, 1) << bit_index;
    }

    pub fn initForTest(name_ids: []const u16) NameIdIndex {
        var index = NameIdIndex{};
        for (name_ids) |name_id| index.add(name_id);
        return index;
    }

    fn contains(self: *const NameIdIndex, name_id: u16) bool {
        const word_index = @as(usize, name_id) / 64;
        const bit_index: u6 = @intCast(name_id & 63);
        return (self.words[word_index] & (@as(u64, 1) << bit_index)) != 0;
    }
};

pub fn idIndex(data: []const u8, name: Table) Error!NameIdIndex {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    // Variation metadata may reference many name IDs across fvar instances and
    // STAT AxisValue records. Index the already-validated records once so
    // cross-table checks are deterministic without repeatedly reparsing `name`.
    var index = NameIdIndex{};
    var previous_key: ?NameRecordKey = null;
    for (0..layout.count) |record_index| {
        const record = try readNameRecord(table, record_index);
        try validateNameRecordOrdering(previous_key, record.key());
        previous_key = record.key();
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data, .tolerate_invalid);
        index.add(record.name_id);
    }
    return index;
}

pub fn validateIdReference(name_index: ?*const NameIdIndex, name_id: u16) Error!void {
    const index = name_index orelse return error.InvalidName;
    if (!index.contains(name_id)) return error.InvalidName;
}

pub fn validateOptionalIdReference(name_index: ?*const NameIdIndex, name_id: u16) Error!void {
    if (name_id == 0xffff) return;
    try validateIdReference(name_index, name_id);
}

fn nameTableSlice(data: []const u8, name: Table) Error![]const u8 {
    if (name.offset > data.len or name.length > data.len - name.offset) return error.BadSfnt;
    return data[name.offset .. name.offset + name.length];
}

fn readNameTableLayout(table: []const u8) Error!NameTableLayout {
    if (table.len < 6) return error.BadSfnt;
    const format = try bin.readU16At(table, 0);
    if (format > 1) return error.InvalidName;
    const count = try bin.readU16At(table, 2);
    const storage_offset: usize = @intCast(try bin.readU16At(table, 4));

    if (@as(usize, count) > (table.len - name_records_start) / name_record_size) return error.BadSfnt;
    const records_len = @as(usize, count) * name_record_size;
    const records_end = name_records_start + records_len;

    // name.stringOffset is relative to the name table and denotes the first
    // byte of shared string storage. It must sit after every versioned metadata
    // record, otherwise a malicious NameRecord or LangTagRecord can reinterpret
    // table headers as a plausible UTF-16 string.
    var minimum_storage_offset = records_end;
    var layout = NameTableLayout{
        .format = format,
        .count = count,
        .storage_offset = storage_offset,
        .storage_length = 0,
    };
    if (format == 1) {
        if (records_end + 2 > table.len) return error.BadSfnt;
        const lang_tag_count: usize = @intCast(try bin.readU16At(table, records_end));
        // Language IDs encode LangTagRecord indexes as 0x8000 + index, leaving
        // exactly 15 bits for the index. Reject unreachable trailing records so
        // enumeration cannot synthesize duplicate or wrapped language IDs.
        if (lang_tag_count > 0x8000) return error.BadSfnt;
        const lang_tag_records_start = records_end + 2;
        if (lang_tag_count > (table.len - lang_tag_records_start) / lang_tag_record_size) return error.BadSfnt;
        minimum_storage_offset = lang_tag_records_start + lang_tag_count * lang_tag_record_size;
        layout.lang_tag_records_start = lang_tag_records_start;
        layout.lang_tag_count = lang_tag_count;
    }
    if (storage_offset < minimum_storage_offset or storage_offset > table.len) return error.BadSfnt;
    layout.storage_length = table.len - storage_offset;
    return layout;
}

fn validateNameLanguageTags(table: []const u8, layout: NameTableLayout) Error!void {
    if (layout.format != 1) return;
    for (0..layout.lang_tag_count) |index| {
        const tag_data = try languageTagString(table, layout, index);
        try validateUtf16BeNameData(tag_data);
        try validateNameLanguageTagSyntax(tag_data);
    }
}

fn languageTagString(table: []const u8, layout: NameTableLayout, index: usize) Error![]const u8 {
    const record_offset = layout.lang_tag_records_start + index * lang_tag_record_size;
    const length: usize = @intCast(try bin.readU16At(table, record_offset));
    const offset = try languageTagStorageOffset(table, layout, index);
    return try nameStorageString(table, layout, offset, length);
}

fn languageTagStorageOffset(table: []const u8, layout: NameTableLayout, index: usize) Error!usize {
    const record_offset = layout.lang_tag_records_start + index * lang_tag_record_size;
    return @intCast(try bin.readU16At(table, record_offset + 2));
}

fn languageIdForTagIndex(index: usize) u16 {
    return 0x8000 | @as(u16, @intCast(index));
}

fn validateNameLanguageTagSyntax(data: []const u8) Error!void {
    if (data.len == 0) return error.InvalidName;

    var subtag_len: usize = 0;
    var subtag_index: usize = 0;
    var first_subtag_alpha = true;
    var first_subtag_first: u8 = 0;
    var index: usize = 0;
    while (index < data.len) : (index += 2) {
        const unit = std.mem.readInt(u16, data[index..][0..2], .big);
        // BCP 47 language tags are ASCII protocol identifiers stored here as
        // UTF-16BE. Rejecting non-ASCII and separator variants prevents a
        // format-1 LangTagRecord from looking valid to Cangjie while downstream
        // locale matching treats it as an unrelated or malformed language tag.
        if (unit > 0x7f) return error.InvalidName;
        const byte: u8 = @intCast(unit);
        if (byte == '-') {
            if (subtag_len == 0 or subtag_len > 8) return error.InvalidName;
            if (subtag_index == 0) {
                if (!isValidPrimaryLanguageSubtag(first_subtag_first, subtag_len, first_subtag_alpha, true)) return error.InvalidName;
            }
            subtag_index += 1;
            subtag_len = 0;
            continue;
        }
        if (!std.ascii.isAlphanumeric(byte)) return error.InvalidName;
        if (subtag_index == 0) {
            if (subtag_len == 0) first_subtag_first = std.ascii.toLower(byte);
            first_subtag_alpha = first_subtag_alpha and std.ascii.isAlphabetic(byte);
        }
        subtag_len += 1;
    }

    if (subtag_len == 0 or subtag_len > 8) return error.InvalidName;
    if (subtag_index == 0 and !isValidPrimaryLanguageSubtag(first_subtag_first, subtag_len, first_subtag_alpha, false)) return error.InvalidName;
}

fn isValidPrimaryLanguageSubtag(first: u8, len: usize, all_alpha: bool, has_following_subtag: bool) bool {
    if (!all_alpha) return false;
    if (len == 1) return has_following_subtag and (first == 'i' or first == 'x');
    return len >= 2 and len <= 8;
}

fn readNameRecord(table: []const u8, index: usize) Error!NameRecord {
    const rec = name_records_start + index * name_record_size;
    if (rec + name_record_size > table.len) return error.BadSfnt;
    return .{
        .platform_id = try bin.readU16At(table, rec),
        .encoding_id = try bin.readU16At(table, rec + 2),
        .language_id = try bin.readU16At(table, rec + 4),
        .name_id = try bin.readU16At(table, rec + 6),
        .length = try bin.readU16At(table, rec + 8),
        .offset = try bin.readU16At(table, rec + 10),
    };
}

fn validateNameRecordOrdering(previous: ?NameRecordKey, current: NameRecordKey) Error!void {
    const previous_key = previous orelse return;
    // OpenType name records form a directory keyed by platform, encoding,
    // language, and name ID. Requiring the canonical order rejects duplicate
    // keys before nameString() has to choose between two equally-scored strings,
    // which would otherwise make localized metadata depend on record order.
    if (std.math.order(current.platform_id, previous_key.platform_id) != .eq) {
        if (current.platform_id <= previous_key.platform_id) return error.InvalidName;
        return;
    }
    if (std.math.order(current.encoding_id, previous_key.encoding_id) != .eq) {
        if (current.encoding_id <= previous_key.encoding_id) return error.InvalidName;
        return;
    }
    if (std.math.order(current.language_id, previous_key.language_id) != .eq) {
        if (current.language_id <= previous_key.language_id) return error.InvalidName;
        return;
    }
    if (current.name_id <= previous_key.name_id) return error.InvalidName;
}

fn validateNameRecordMetadata(layout: NameTableLayout, record: NameRecord) Error!void {
    try validateNameRecordPlatformEncoding(record);

    // In name table format 1, language IDs from 0x8000 upward are indexes into
    // the LangTagRecord array. Validate the reference for every record at parse
    // time so later family/style lookups cannot trip over an unrelated broken
    // localized name entry. Older format-0 language IDs remain platform-owned.
    if (layout.format == 1 and (record.language_id & 0x8000) != 0) {
        const lang_tag_index = @as(usize, record.language_id & 0x7fff);
        if (lang_tag_index >= layout.lang_tag_count) return error.BadSfnt;
    }
}

fn validateNameRecordPlatformEncoding(record: NameRecord) Error!void {
    switch (record.platform_id) {
        0 => if (record.encoding_id > 6) return error.InvalidName,
        // Macintosh encoding IDs are legacy Script Manager codes. Keep them
        // range-agnostic here: the important structural guarantee is that the
        // platform itself is registered, while many old production fonts use
        // obscure Mac encodings that Cangjie treats as opaque single-byte data.
        1 => {},
        2 => if (record.encoding_id > 2) return error.InvalidName,
        3 => switch (record.encoding_id) {
            0, 1, 2, 3, 4, 5, 6, 10 => {},
            else => return error.InvalidName,
        },
        4 => {},
        else => return error.InvalidName,
    }
}

fn nameRecordString(table: []const u8, layout: NameTableLayout, record: NameRecord) Error![]const u8 {
    return try nameStorageString(table, layout, record.offset, record.length);
}

fn nameStorageString(table: []const u8, layout: NameTableLayout, offset: usize, length: usize) Error![]const u8 {
    if (offset > layout.storage_length or length > layout.storage_length - offset) return error.BadSfnt;
    const start = layout.storage_offset + offset;
    return table[start .. start + length];
}

fn validateNameRecordEncoding(record: NameRecord, string_data: []const u8, postscript_name_policy: PostScriptNamePolicy) Error!void {
    if (isUtf16Name(record)) try validateUtf16BeNameData(string_data);
    if (record.name_id == @intFromEnum(NameId.postscript_name) and postscript_name_policy == .strict) {
        // The PostScript font name is consumed as a stable ASCII identifier by
        // font databases and document formats, unlike localized family names.
        // Validate its restricted syntax at every name-table read so a borrowed
        // font buffer mutation cannot surface spaces, delimiters, or non-ASCII
        // code points through Font.nameString(.postscript_name).
        try validatePostScriptNameString(record, string_data);
    }
}

fn validatePostScriptNameString(record: NameRecord, data: []const u8) Error!void {
    var decoded_len: usize = 0;
    if (isUtf16Name(record)) {
        var index: usize = 0;
        while (index < data.len) : (index += 2) {
            const unit = std.mem.readInt(u16, data[index..][0..2], .big);
            if (unit >= 0xd800 and unit <= 0xdbff) {
                if (index + 4 > data.len) return error.InvalidName;
                const low = std.mem.readInt(u16, data[index + 2 ..][0..2], .big);
                if (low < 0xdc00 or low > 0xdfff) return error.InvalidName;
                return error.InvalidName;
            } else if (unit >= 0xdc00 and unit <= 0xdfff) {
                return error.InvalidName;
            }
            if (unit > std.math.maxInt(u8) or !isPostScriptFontNameByte(@intCast(unit))) return error.InvalidName;
            decoded_len += 1;
        }
    } else {
        for (data) |byte| {
            if (!isPostScriptFontNameByte(byte)) return error.InvalidName;
        }
        decoded_len = data.len;
    }

    // PostScript FontName identifiers are limited to 63 ASCII bytes. Empty
    // records are also invalid: if name ID 6 is present it must identify the
    // face rather than behaving like a missing optional record.
    if (decoded_len == 0 or decoded_len > 63) return error.InvalidName;
}

fn isPostScriptFontNameByte(byte: u8) bool {
    return switch (byte) {
        // PostScript delimiters and whitespace are not legal inside FontName
        // tokens. Keep hyphen and period available because they are common in
        // production PostScript names such as "Family-BoldItalic".
        0x21...0x7e => byte != '(' and byte != ')' and
            byte != '<' and byte != '>' and
            byte != '[' and byte != ']' and
            byte != '{' and byte != '}' and
            byte != '/' and byte != '%',
        else => false,
    };
}

fn validateUtf16BeNameData(data: []const u8) Error!void {
    if (data.len % 2 != 0) return error.InvalidName;
    var index: usize = 0;
    while (index < data.len) : (index += 2) {
        const unit = std.mem.readInt(u16, data[index..][0..2], .big);
        if (unit >= 0xd800 and unit <= 0xdbff) {
            if (index + 4 > data.len) return error.InvalidName;
            const low = std.mem.readInt(u16, data[index + 2 ..][0..2], .big);
            if (low < 0xdc00 or low > 0xdfff) return error.InvalidName;
            index += 2;
        } else if (unit >= 0xdc00 and unit <= 0xdfff) {
            return error.InvalidName;
        }
    }
}

pub fn readString(data: []const u8, name: Table, name_id: u16, out: []u8) Error!?[]const u8 {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    var best: ?NameRecord = null;
    var previous_key: ?NameRecordKey = null;
    for (0..layout.count) |i| {
        const record = try readNameRecord(table, i);
        try validateNameRecordOrdering(previous_key, record.key());
        previous_key = record.key();
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data, if (record.name_id == name_id) .strict else .tolerate_invalid);
        if (record.name_id != name_id) continue;
        if (best == null or scoreNameRecord(record) > scoreNameRecord(best.?)) best = record;
    }

    const chosen = best orelse return null;
    const string_data = try nameRecordString(table, layout, chosen);
    if (isUtf16Name(chosen)) return try decodeUtf16BeName(string_data, out);
    return try decodeSingleByteName(string_data, out);
}

fn scoreNameRecord(record: NameRecord) u8 {
    var score: u8 = 0;
    if (isUtf16Name(record)) score += 8;
    if (record.platform_id == 3 and record.language_id == 0x0409) score += 4;
    if (record.platform_id == 0) score += 3;
    if (record.platform_id == 1 and record.language_id == 0) score += 1;
    return score;
}

fn isUtf16Name(record: NameRecord) bool {
    return switch (record.platform_id) {
        0 => true,
        2 => record.encoding_id == 1,
        // Windows name strings are UTF-16BE only for the Unicode encodings.
        // Legacy Shift-JIS/GBK/Big5/Wansung/Johab records are structurally
        // valid but are not Unicode strings, so do not apply surrogate rules.
        3 => record.encoding_id == 0 or record.encoding_id == 1 or record.encoding_id == 10,
        else => false,
    };
}

fn decodeUtf16BeName(data: []const u8, out: []u8) Error![]const u8 {
    if (data.len % 2 != 0) return error.InvalidName;
    var written: usize = 0;
    var index: usize = 0;
    while (index < data.len) : (index += 2) {
        const unit = std.mem.readInt(u16, data[index..][0..2], .big);
        const codepoint: u21 = if (unit >= 0xd800 and unit <= 0xdbff) blk: {
            if (index + 4 > data.len) return error.InvalidName;
            const low = std.mem.readInt(u16, data[index + 2 ..][0..2], .big);
            if (low < 0xdc00 or low > 0xdfff) return error.InvalidName;
            index += 2;
            break :blk 0x10000 + ((@as(u21, unit - 0xd800) << 10) | @as(u21, low - 0xdc00));
        } else if (unit >= 0xdc00 and unit <= 0xdfff) {
            return error.InvalidName;
        } else unit;
        const length = std.unicode.utf8CodepointSequenceLength(codepoint) catch return error.InvalidName;
        if (written + length > out.len) return error.InvalidName;
        written += std.unicode.utf8Encode(codepoint, out[written..]) catch return error.InvalidName;
    }
    return out[0..written];
}

fn decodeSingleByteName(data: []const u8, out: []u8) Error![]const u8 {
    if (data.len > out.len) return error.InvalidName;
    // Public name APIs return UTF-8 byte strings. For legacy non-Unicode name
    // records Cangjie currently supports only the ASCII-compatible subset of
    // Mac/ISO/vendor encodings; bytes above 0x7f are encoding-specific and
    // would otherwise be surfaced as malformed UTF-8 to callers.
    for (data) |byte| {
        if (byte > 0x7f) return error.InvalidName;
    }
    @memcpy(out[0..data.len], data);
    return out[0..data.len];
}
