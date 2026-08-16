//! fvar cross-table references into the OpenType name table.

const bin = @import("../../../../binary.zig");
const name = @import("../../../../opentype/name.zig");
const sfnt = @import("../../../sfnt/root.zig");
const table = @import("table.zig");

pub const Error = table.Error || name.Error;
pub const NameIdIndex = name.NameIdIndex;

pub fn validateAll(
    data: []const u8,
    record: sfnt.Record,
    name_index: ?*const NameIdIndex,
) Error!void {
    try validateAxes(data, record, name_index);
    try validateInstances(data, record, name_index);
}

pub fn validateAxes(
    data: []const u8,
    record: sfnt.Record,
    name_index: ?*const NameIdIndex,
) Error!void {
    const layout = try table.info(data, record);
    for (0..layout.axis_count) |index| {
        const offset = table.axisOffset(record, layout, index);
        try name.validateIdReference(
            name_index,
            try bin.readU16At(data, offset + 18),
        );
    }
}

pub fn validateInstances(
    data: []const u8,
    record: sfnt.Record,
    name_index: ?*const NameIdIndex,
) Error!void {
    const layout = try table.info(data, record);
    for (0..layout.instance_count) |index| {
        const offset = table.instanceOffset(record, layout, index);
        try name.validateIdReference(
            name_index,
            try bin.readU16At(data, offset),
        );
        // fvar uses 0xffff to mean that an optional PostScript NameID was not
        // supplied. Every other value is application-visible metadata and must
        // resolve through the complete name-table index.
        if (layout.has_postscript_name_id) {
            try name.validateOptionalIdReference(
                name_index,
                try bin.readU16At(
                    data,
                    offset + layout.postscript_name_id_offset,
                ),
            );
        }
    }
}
