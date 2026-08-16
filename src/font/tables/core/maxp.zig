//! OpenType `maxp` decoding, validation, and outline-stack selection.

const bin = @import("../../../binary.zig");
const sfnt = @import("../../sfnt/root.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub const Info = struct {
    version: u32,
    glyph_count: u16,
    max_points: ?u16 = null,
    max_contours: ?u16 = null,
    max_composite_points: ?u16 = null,
    max_composite_contours: ?u16 = null,
    max_zones: ?u16 = null,
    max_twilight_points: ?u16 = null,
    max_storage: ?u16 = null,
    max_function_defs: ?u16 = null,
    max_instruction_defs: ?u16 = null,
    max_stack_elements: ?u16 = null,
    max_size_of_instructions: ?u16 = null,
    max_component_elements: ?u16 = null,
    max_component_depth: ?u16 = null,

    /// Extract maxima required by glyf validation after a v1.0 proof.
    ///
    /// Keeping this conversion beside the decoder prevents outline code from
    /// learning the maxp field offsets or force-unwrapping optional CFF fields.
    pub fn trueTypeLimits(self: Info) Error!TrueTypeLimits {
        if (self.version != 0x00010000) return error.BadSfnt;
        return .{
            .max_points = self.max_points orelse return error.BadSfnt,
            .max_contours = self.max_contours orelse return error.BadSfnt,
            .max_component_elements = self.max_component_elements orelse return error.BadSfnt,
            .max_component_depth = self.max_component_depth orelse return error.BadSfnt,
        };
    }
};

pub const TrueTypeLimits = struct {
    max_points: u16,
    max_contours: u16,
    max_component_elements: u16,
    max_component_depth: u16,
};

pub fn info(data: []const u8, table: sfnt.Record) Error!Info {
    try sfnt.requireLength(table, 6);
    const version = try bin.readU32At(data, table.offset);
    var result: Info = .{
        .version = version,
        .glyph_count = try bin.readU16At(data, table.offset + 4),
    };
    if (version == 0x00010000) {
        try sfnt.requireLength(table, 32);
        result.max_points = try bin.readU16At(data, table.offset + 6);
        result.max_contours = try bin.readU16At(data, table.offset + 8);
        result.max_composite_points =
            try bin.readU16At(data, table.offset + 10);
        result.max_composite_contours =
            try bin.readU16At(data, table.offset + 12);
        result.max_zones = try bin.readU16At(data, table.offset + 14);
        result.max_twilight_points =
            try bin.readU16At(data, table.offset + 16);
        result.max_storage = try bin.readU16At(data, table.offset + 18);
        result.max_function_defs = try bin.readU16At(data, table.offset + 20);
        result.max_instruction_defs =
            try bin.readU16At(data, table.offset + 22);
        result.max_stack_elements =
            try bin.readU16At(data, table.offset + 24);
        result.max_size_of_instructions =
            try bin.readU16At(data, table.offset + 26);
        result.max_component_elements =
            try bin.readU16At(data, table.offset + 28);
        result.max_component_depth =
            try bin.readU16At(data, table.offset + 30);
    }
    return result;
}

pub fn validate(
    data: []const u8,
    table: sfnt.Record,
    format: types.Format,
) Error!void {
    try sfnt.requireLength(table, 6);
    const version = try bin.readU32At(data, table.offset);
    switch (format) {
        .truetype => {
            // TrueType consumers use the complete v1.0 maxima while proving
            // glyph programs and compound recursion safe.
            if (version != 0x00010000 or table.length != 32) {
                return error.BadSfnt;
            }
        },
        .opentype_cff => {
            // CFF uses the compact v0.5 form containing only numGlyphs.
            if (version != 0x00005000 or table.length != 6) {
                return error.BadSfnt;
            }
        },
    }
}

/// Reconcile a conflicting SFNT scaler with a complete outline table stack.
///
/// Some shaping fixtures carry both glyf and CFF data. A canonical maxp v1.0
/// proves the glyf stack, while v0.5 proves CFF; malformed topologies fall back
/// to the declared flavor and are rejected by `validate` immediately after.
pub fn selectFormat(
    data: []const u8,
    table: sfnt.Record,
    declared: types.Format,
    has_glyf_outlines: bool,
    has_cff_outlines: bool,
) Error!types.Format {
    try sfnt.requireLength(table, 6);
    const version = try bin.readU32At(data, table.offset);
    if (has_glyf_outlines and
        version == 0x00010000 and
        table.length == 32)
    {
        return .truetype;
    }
    if (has_cff_outlines and
        version == 0x00005000 and
        table.length == 6)
    {
        return .opentype_cff;
    }
    return declared;
}

test "outline format follows the complete maxp-backed table stack" {
    const std = @import("std");

    var maxp_10: [32]u8 = .{0} ** 32;
    std.mem.writeInt(u32, maxp_10[0..4], 0x00010000, .big);
    const record_10: sfnt.Record = .{
        .tag = .{ 'm', 'a', 'x', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = maxp_10.len,
    };
    try std.testing.expectEqual(
        types.Format.truetype,
        try selectFormat(&maxp_10, record_10, .opentype_cff, true, true),
    );

    var maxp_05: [6]u8 = .{0} ** 6;
    std.mem.writeInt(u32, maxp_05[0..4], 0x00005000, .big);
    const record_05: sfnt.Record = .{
        .tag = .{ 'm', 'a', 'x', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = maxp_05.len,
    };
    try std.testing.expectEqual(
        types.Format.opentype_cff,
        try selectFormat(&maxp_05, record_05, .truetype, true, true),
    );
}
