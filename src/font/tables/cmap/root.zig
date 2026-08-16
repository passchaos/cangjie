//! OpenType cmap directory, validation, and selection-policy surface.

const directory = @import("directory.zig");
const policy = @import("policy.zig");
const types = @import("types.zig");
const validation = @import("validation/root.zig");
const formats = @import("validation/formats.zig");
const glyphs = @import("validation/glyphs.zig");

pub const Info = types.Info;
pub const Subtable = types.Subtable;
pub const parse = directory.parse;
pub const relativeOffset = directory.relativeOffset;
pub const validateCachedEncodingRecord = directory.validateCachedEncodingRecord;
pub const subtableLength = directory.subtableLength;
pub const validate = validation.validate;
pub const validateGlyphIds = glyphs.validate;
pub const validateNumericFormat = formats.validate;
pub const validateFormat14 = validation.format14.validate;

pub const supportsGlyphLookup = policy.supportsGlyphLookup;
pub const language = policy.language;
pub const isMacintoshRoman = policy.isMacintoshRoman;
pub const score = policy.score;
pub const validatePublicScalar = policy.validatePublicScalar;
pub const validatePublicVariationSelector = policy.validatePublicVariationSelector;
pub const isVariationSelector = policy.isVariationSelector;
pub const readU24 = policy.readU24;

pub const format8_groups_offset = formats.format8_groups_offset;
pub const validateFormat0 = formats.validateFormat0;
pub const format14PayloadOffset = validation.format14.payloadOffset;
pub const format14RecordsEnd = validation.format14.recordsEnd;
