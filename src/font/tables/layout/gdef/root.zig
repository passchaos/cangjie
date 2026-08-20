//! OpenType GDEF table grammar and class/filtering-set reads.

const class_def = @import("class_def.zig");
const attachment_points = @import("attachment_points.zig");
const header_mod = @import("header.zig");
const ligature_carets = @import("ligature_carets.zig");
const mark_sets = @import("mark_sets.zig");
const validation = @import("validation.zig");
const types = @import("types.zig");

pub const GlyphClass = types.GlyphClass;
pub const Header = types.Header;
pub const LigatureCaret = types.LigatureCaret;
pub const AttachmentPoint = types.AttachmentPoint;

pub const header = header_mod.read;
pub const validateChildOffset = header_mod.validateChildOffset;
pub const validate = validation.validate;

pub fn validateBasic(
    data: []const u8,
    table: @import("../../../sfnt/root.zig").Record,
    glyph_count: u16,
) validation.Error!void {
    return validation.validate(data, table, glyph_count, null);
}

pub const classValue = class_def.value;
pub const readClassDefDense = class_def.readDense;
pub const glyphsInClass = class_def.glyphsInClass;
pub const validateGlyphClassValue = class_def.validateGlyphClassValue;
pub const coverageIndex = @import("coverage.zig").coverageIndex;
pub const readAttachmentPoints = attachment_points.read;

pub const validateMarkSets = mark_sets.validate;
pub const readMarkSets = mark_sets.read;
pub const markSetCount = mark_sets.setCountPublic;
pub const readMarkSet = mark_sets.readSet;
pub const freeMarkSets = mark_sets.free;

pub const LigatureCaretOptions = ligature_carets.Options;
pub const LigatureCaretError = ligature_carets.Error;
pub const readLigatureCarets = ligature_carets.read;
