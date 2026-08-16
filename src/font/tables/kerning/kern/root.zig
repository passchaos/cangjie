//! Legacy OpenType and Apple kern table surface.

const metadata = @import("metadata.zig");
const lookup = @import("lookup.zig");
const validation = @import("validation.zig");
const types = @import("types.zig");

pub const Dialect = types.Dialect;
pub const Subtable = types.Subtable;
pub const Info = types.Info;

pub const validate = validation.validate;
pub const info = metadata.info;
pub const kerningAfterProof = lookup.kerningAfterProof;

pub fn free(allocator: @import("std").mem.Allocator, value: Info) void {
    allocator.free(value.subtables);
}
