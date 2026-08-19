//! Localized naming records and common face names.

const std = @import("std");

const font_mod = @import("../../../font.zig");

pub const View = struct {
    /// Borrowed source-level view backing; use the methods below.
    implementation: *const font_mod.Font,

    pub fn get(
        self: View,
        name_id: font_mod.NameId,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return self.implementation.nameString(name_id, out);
    }

    /// Enumerate all strings for a name ID, preserving their language. The
    /// array is caller-owned and must be released with `allocator.free`.
    pub fn localized(
        self: View,
        allocator: std.mem.Allocator,
        name_id: font_mod.NameId,
    ) font_mod.FontError![]font_mod.LocalizedName {
        return self.implementation.localizedNames(allocator, name_id);
    }

    /// Select en-US, then bare en, then a language-neutral Unicode record,
    /// then the first localized string, matching Skrifa's documented policy.
    pub fn englishOrFirst(
        self: View,
        allocator: std.mem.Allocator,
        name_id: font_mod.NameId,
    ) font_mod.FontError!?font_mod.LocalizedName {
        const values = try self.localized(allocator, name_id);
        defer allocator.free(values);

        var best: ?font_mod.LocalizedName = null;
        var best_rank: u2 = 0;
        for (values) |value| {
            const rank = try englishRank(value);
            if (rank == 3) return value;
            if (rank > best_rank) {
                best = value;
                best_rank = rank;
            }
            if (best == null) best = value;
        }
        return best;
    }

    pub fn family(
        self: View,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return self.implementation.familyName(out);
    }

    pub fn subfamily(
        self: View,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return self.implementation.subfamilyName(out);
    }

    pub fn full(
        self: View,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return self.implementation.fullName(out);
    }

    pub fn languageTag(
        self: View,
        language_id: u16,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return self.implementation.nameLanguageTag(language_id, out);
    }
};

fn englishRank(value: font_mod.LocalizedName) font_mod.FontError!u2 {
    const language = value.language orelse return 1;
    return switch (language) {
        .static => |tag| if (std.mem.eql(u8, tag, "en-US"))
            3
        else if (std.mem.eql(u8, tag, "en"))
            2
        else
            0,
        // Avoid an arbitrary scratch-buffer limit: compare the short English
        // tags directly in UTF-16BE rather than decoding every BCP-47 tag.
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
