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
        return font_mod.immutable_face_backend.localizedNames(
            self.implementation,
            allocator,
            name_id,
        );
    }

    /// Select en-US, then bare en, then a language-neutral Unicode record,
    /// then the first localized string, matching Skrifa's documented policy.
    pub fn englishOrFirst(
        self: View,
        allocator: std.mem.Allocator,
        name_id: font_mod.NameId,
    ) font_mod.FontError!?font_mod.LocalizedName {
        _ = allocator;
        return font_mod.immutable_face_backend.englishOrFirstName(
            self.implementation,
            name_id,
        );
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
