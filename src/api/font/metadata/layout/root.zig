//! Baseline, glyph-class, kerning, and layout-table inspection records.

const font = @import("../../../../font.zig");

pub const Baseline = font.BaseInfo;
pub const BaselineAxis = font.BaseAxisInfo;
pub const BaselineScript = font.BaseScriptInfo;

pub const GlyphClass = font.GlyphClass;
pub const LigatureCaret = font.LigatureCaret;
pub const AttachmentPoint = font.AttachmentPoint;
pub const Kern = font.KernInfo;
pub const KernSubtable = font.KernSubtableInfo;
pub const Justification = font.JstfInfo;
pub const JustificationScript = font.JstfScriptInfo;
pub const JustificationLanguage = font.JstfLanguageInfo;
pub const JustificationPriority = font.JstfPriorityInfo;
pub const JustificationLookupList = font.JstfLookupListInfo;
pub const JustificationMaximumLookup = font.JstfMaxLookupInfo;

pub const Cff2 = font.Cff2Info;
pub const Cff2FontDictionary = font.Cff2FontDictInfo;
pub const Cff2PrivateDictionary = font.Cff2PrivateDictInfo;
pub const Cff2CharStringScan = font.Cff2CharStringScanInfo;
pub const Cff2CharStringBounds = font.Cff2CharStringBoundsInfo;

pub const LanguageTag = font.LtagRecordInfo;
pub const Inspection = @import("inspection.zig").View;
pub const inspect = @import("inspection.zig").inspect;
pub const aat = @import("aat.zig");
