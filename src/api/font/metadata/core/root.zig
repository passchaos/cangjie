//! Core SFNT identity, naming, character-map, and inspection records.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");
const glyph = @import("../../../../glyph.zig");

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

/// Borrowed core-SFNT inspection view.
///
/// Every method revalidates lazily read table bytes. Returned scalar records
/// are values; returned byte slices borrow the Face; returned arrays are owned
/// by the allocator passed to that method.
pub const Inspection = struct {
    face: *const face_mod.Face,

    fn implementation(self: Inspection) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn header(self: Inspection) font.FontError!Header {
        return self.implementation().headInfo();
    }

    pub fn maxProfile(self: Inspection) font.FontError!MaxProfile {
        return self.implementation().maxpInfo();
    }

    pub fn os2(self: Inspection) font.FontError!?Os2 {
        return self.implementation().os2Info();
    }

    pub fn post(self: Inspection) font.FontError!?Post {
        return self.implementation().postInfo();
    }

    pub fn pclt(self: Inspection) font.FontError!?Pclt {
        return self.implementation().pcltInfo();
    }

    pub fn tables(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error![]Table {
        return self.implementation().tables(allocator);
    }

    /// Return validated raw table bytes borrowed from the Face.
    pub fn tableData(
        self: Inspection,
        tag_value: [4]u8,
    ) font.FontError!?[]const u8 {
        return self.implementation().tableData(tag_value);
    }

    pub fn charmaps(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]Charmap {
        return self.implementation().charmaps(allocator);
    }

    pub fn defaultCharmap(self: Inspection) font.FontError!?Charmap {
        return self.implementation().defaultCharmap();
    }

    pub fn glyphIndex(
        self: Inspection,
        charmap: Charmap,
        codepoint: u21,
    ) font.FontError!glyph.GlyphId {
        return self.implementation().glyphIndexWithCharmap(
            charmap,
            codepoint,
        );
    }

    pub fn firstMapping(
        self: Inspection,
        charmap: Charmap,
    ) font.FontError!?CharmapMapping {
        return self.implementation().firstCharmapMapping(charmap);
    }

    pub fn nextMapping(
        self: Inspection,
        charmap: Charmap,
        codepoint: u21,
    ) font.FontError!?CharmapMapping {
        return self.implementation().nextCharmapMapping(
            charmap,
            codepoint,
        );
    }

    pub fn nameRecords(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]NameRecord {
        return self.implementation().nameRecords(allocator);
    }

    pub fn nameLanguages(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]NameLanguage {
        return self.implementation().nameLanguageTags(allocator);
    }

    pub fn metaRecords(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]MetaRecord {
        return self.implementation().metaRecords(allocator);
    }

    /// Return one validated `meta` payload borrowed from the Face.
    pub fn metaData(
        self: Inspection,
        tag_value: [4]u8,
    ) font.FontError!?[]const u8 {
        return self.implementation().metaData(tag_value);
    }

    pub fn digitalSignature(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?DigitalSignature {
        return self.implementation().dsigInfo(allocator);
    }

    pub fn freeDigitalSignature(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: DigitalSignature,
    ) void {
        self.implementation().freeDsigInfo(allocator, info);
    }

    pub fn gridFitAndScan(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?GridFitAndScan {
        return self.implementation().gaspInfo(allocator);
    }

    pub fn freeGridFitAndScan(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: GridFitAndScan,
    ) void {
        self.implementation().freeGaspInfo(allocator, info);
    }

    pub fn gridFitBehavior(
        self: Inspection,
        ppem: u16,
    ) font.FontError!?u16 {
        return self.implementation().gaspBehavior(ppem);
    }

    pub fn fontProgram(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?TrueTypeProgram {
        return self.implementation().fontProgramInfo(allocator);
    }

    pub fn controlValueProgram(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError!?TrueTypeProgram {
        return self.implementation().controlValueProgramInfo(allocator);
    }

    pub fn freeProgram(
        self: Inspection,
        allocator: std.mem.Allocator,
        info: TrueTypeProgram,
    ) void {
        self.implementation().freeTrueTypeProgramInfo(allocator, info);
    }

    pub fn glyphLocations(
        self: Inspection,
        allocator: std.mem.Allocator,
    ) font.FontError![]GlyphLocation {
        return self.implementation().glyphLocations(allocator);
    }
};

pub fn inspect(face: *const face_mod.Face) Inspection {
    return .{ .face = face };
}
