//! Shared SFNT table-directory surface.

const checksum_mod = @import("checksum.zig");
const directory_mod = @import("directory.zig");
const record_mod = @import("record.zig");

pub const Error = record_mod.Error;
pub const Range = record_mod.Range;
pub const Record = record_mod.Record;

pub const find = record_mod.find;
pub const findTag = record_mod.findTag;
pub const overlaps = record_mod.overlaps;
pub const requireLength = record_mod.requireLength;
pub const validateTag = record_mod.validateTag;

pub const validateSearchParameters = directory_mod.validateSearchParameters;
pub const expectedRangeShift = directory_mod.expectedRangeShift;
pub const directoryEnd = directory_mod.end;
pub const validateDirectory = directory_mod.validate;
pub const validateRanges = directory_mod.validateRanges;
pub const validatePadding = directory_mod.validatePadding;
pub const validateDisjoint = directory_mod.validateDisjoint;

pub const checksum = struct {
    pub const validateAll = checksum_mod.validateAll;
    pub const validate = checksum_mod.validate;
    pub const table = checksum_mod.table;
    pub const head = checksum_mod.head;
};
