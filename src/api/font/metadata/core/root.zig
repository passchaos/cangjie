//! Core SFNT identity, naming, character-map, and inspection records.

const font = @import("../../../../font.zig");

pub const Header = font.FontHeaderInfo;
pub const MaxProfile = font.MaxProfileInfo;
pub const Table = font.FontTableInfo;
pub const Os2 = font.Os2Info;
pub const Post = font.PostInfo;
pub const Pclt = font.PcltInfo;

pub const Charmap = font.CharmapInfo;
pub const CharmapMapping = font.CharmapMapping;
pub const VariationSequenceKind = font.VariationSequenceKind;

pub const NameEncoding = font.NameEncoding;
pub const NameId = font.NameId;
pub const NameLanguage = font.NameLanguageTagInfo;
pub const NameRecord = font.NameRecordInfo;
pub const MetaRecord = font.MetaRecordInfo;

pub const DigitalSignature = font.DsigInfo;
pub const DigitalSignatureRecord = font.DsigSignatureInfo;
pub const GridFitAndScan = font.GaspInfo;
pub const GridFitAndScanRange = font.GaspRange;

pub const TrueTypeProgram = font.TrueTypeProgramInfo;
pub const TrueTypeInstruction = font.TrueTypeProgramInstructionInfo;
pub const TrueTypeProgramKind = font.TrueTypeProgramKind;
pub const GlyphLocation = font.GlyphLocationInfo;
