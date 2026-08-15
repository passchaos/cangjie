//! Localized naming records and common face names.

const font_mod = @import("../../../font.zig");

pub const View = opaque {
    pub fn get(
        self: *const View,
        name_id: font_mod.NameId,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return font(self).nameString(name_id, out);
    }

    pub fn family(
        self: *const View,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return font(self).familyName(out);
    }

    pub fn subfamily(
        self: *const View,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return font(self).subfamilyName(out);
    }

    pub fn full(
        self: *const View,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return font(self).fullName(out);
    }

    pub fn languageTag(
        self: *const View,
        language_id: u16,
        out: []u8,
    ) font_mod.FontError!?[]const u8 {
        return font(self).nameLanguageTag(language_id, out);
    }
};

fn font(view: *const View) *const font_mod.Font {
    return @ptrCast(@alignCast(view));
}
