//! OpenType script, language, and feature identifiers used by shaping.

const unicode = @import("../../../unicode.zig");

pub const Feature = unicode.FeatureOverride;
pub const FeatureRange = unicode.GsubFeatureRange;
pub const Language = unicode.OpenTypeLanguageTag;
pub const Script = unicode.OpenTypeScriptTag;

pub const tag = unicode.tag;
pub const script = unicode.openTypeScriptTag;
pub const scriptHorizontalDirection =
    unicode.openTypeScriptHorizontalDirection;
pub const inferLanguage = unicode.inferOpenTypeLanguageTag;
pub const languageForLocale = unicode.openTypeLanguageTagForLocale;
