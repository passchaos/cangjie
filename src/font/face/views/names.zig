//! Localized naming records and common face names.

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
