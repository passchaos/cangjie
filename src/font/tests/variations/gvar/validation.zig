//! Focused gvar table and glyf-target validation contracts.

const std = @import("std");
const validation = @import("../../../tables/variations/gvar/root.zig");
const sfnt = @import("../../../sfnt/root.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("support.zig");

const Record = sfnt.Record;

test "gvar table matches fvar axes and maxp glyph count" {
    var bytes: [62]u8 = .{0} ** 62;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 16);
    fixture.writeU16(&bytes, 6, 2);
    fixture.writeU16(&bytes, 8, 1);
    fixture.writeU16(&bytes, 10, 20);
    support.writeFvarAxis(&bytes);

    const gvar_offset = 36;
    fixture.writeU16(&bytes, gvar_offset + 0, 1);
    fixture.writeU16(&bytes, gvar_offset + 2, 0);
    fixture.writeU16(&bytes, gvar_offset + 4, 1); // axisCount matches fvar.
    fixture.writeU16(&bytes, gvar_offset + 12, 2); // glyphCount matches maxp.
    fixture.writeU32(&bytes, gvar_offset + 16, 26); // Glyph data begins after three short offsets.

    const fvar = Record{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = gvar_offset };
    const gvar = Record{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = bytes.len - gvar_offset };
    try validateTables(&bytes, 2, fvar, gvar, null, null, null, null);

    var axis_mismatch = bytes;
    fixture.writeU16(&axis_mismatch, gvar_offset + 4, 2);
    try std.testing.expectError(error.BadSfnt, validateTables(&axis_mismatch, 2, fvar, gvar, null, null, null, null));

    var glyph_mismatch = bytes;
    fixture.writeU16(&glyph_mismatch, gvar_offset + 12, 3);
    try std.testing.expectError(error.BadSfnt, validateTables(&glyph_mismatch, 2, fvar, gvar, null, null, null, null));
}

test "gvar glyph variation data validates tuple payloads" {
    var bytes: [76]u8 = .{0} ** 76;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 16);
    fixture.writeU16(&bytes, 6, 2);
    fixture.writeU16(&bytes, 8, 1);
    fixture.writeU16(&bytes, 10, 20);
    support.writeFvarAxis(&bytes);

    const gvar_offset = 36;
    support.writePrivatePointTuple(&bytes, gvar_offset);

    const fvar = Record{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = gvar_offset };
    const gvar = Record{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = bytes.len - gvar_offset };
    try validateTables(&bytes, 1, fvar, gvar, null, null, null, null);

    var with_glyf_context: [104]u8 = .{0} ** 104;
    @memcpy(with_glyf_context[0..bytes.len], &bytes);
    const loca_offset = bytes.len;
    const glyf_offset = loca_offset + 4;
    fixture.writeU16(&with_glyf_context, loca_offset + 0, 0);
    fixture.writeU16(&with_glyf_context, loca_offset + 2, 12); // Short loca: glyph byte length 24.
    fixture.writeI16(&with_glyf_context, glyf_offset + 0, 1); // one simple contour.
    fixture.writeU16(&with_glyf_context, glyf_offset + 10, 2); // three real points plus four phantom points.
    const context = validation.TargetContext{
        .loca = .{ .tag = .{ 'l', 'o', 'c', 'a' }, .checksum = 0, .offset = loca_offset, .length = 4 },
        .glyf = .{ .tag = .{ 'g', 'l', 'y', 'f' }, .checksum = 0, .offset = glyf_offset, .length = 24 },
        .index_to_loc_format = 0,
    };
    try validateTables(&with_glyf_context, 1, fvar, gvar, null, null, null, context);

    var point_past_glyf_target_count = with_glyf_context;
    point_past_glyf_target_count[gvar_offset + 24 + 12] = 7; // Valid structure, but only points 0..6 exist.
    try std.testing.expectError(error.BadSfnt, validateTables(&point_past_glyf_target_count, 1, fvar, gvar, null, null, null, context));

    var truncated_y_delta = bytes;
    fixture.writeU16(&truncated_y_delta, gvar_offset + 24 + 4, 4); // tuple variationDataSize excludes the Y delta byte.
    try std.testing.expectError(error.BadSfnt, validateTables(&truncated_y_delta, 1, fvar, gvar, null, null, null, null));

    var overstated_point_run = bytes;
    overstated_point_run[gvar_offset + 24 + 11] = 1; // One-point tuple declares a two-entry point-number run.
    try std.testing.expectError(error.BadSfnt, validateTables(&overstated_point_run, 1, fvar, gvar, null, null, null, null));

    var missing_peak_tuple = bytes;
    fixture.writeU16(&missing_peak_tuple, gvar_offset + 24 + 6, 0x2000); // Private points, but no embedded peak or shared tuple.
    try std.testing.expectError(error.BadSfnt, validateTables(&missing_peak_tuple, 1, fvar, gvar, null, null, null, null));

    var reserved_flags = bytes;
    fixture.writeU16(&reserved_flags, gvar_offset + 14, 0x0002);
    try std.testing.expectError(error.BadSfnt, validateTables(&reserved_flags, 1, fvar, gvar, null, null, null, null));
}

test "gvar tuple coordinates validate normalized peaks and intermediate regions" {
    const gvar_offset = 36;

    var embedded_peak: [76]u8 = .{0} ** 76;
    fixture.writeU32(&embedded_peak, 0, 0x00010000);
    fixture.writeU16(&embedded_peak, 4, 16);
    fixture.writeU16(&embedded_peak, 6, 2);
    fixture.writeU16(&embedded_peak, 8, 1);
    fixture.writeU16(&embedded_peak, 10, 20);
    support.writeFvarAxis(&embedded_peak);
    support.writePrivatePointTuple(&embedded_peak, gvar_offset);

    const fvar = Record{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = gvar_offset };
    const embedded_gvar = Record{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = embedded_peak.len - gvar_offset };
    try validateTables(&embedded_peak, 1, fvar, embedded_gvar, null, null, null, null);

    var peak_outside_normalized_space = embedded_peak;
    fixture.writeI16(&peak_outside_normalized_space, gvar_offset + 24 + 8, 0x4001);
    try std.testing.expectError(error.BadSfnt, validateTables(&peak_outside_normalized_space, 1, fvar, embedded_gvar, null, null, null, null));

    var shared_peak: [78]u8 = .{0} ** 78;
    fixture.writeU32(&shared_peak, 0, 0x00010000);
    fixture.writeU16(&shared_peak, 4, 16);
    fixture.writeU16(&shared_peak, 6, 2);
    fixture.writeU16(&shared_peak, 8, 1);
    fixture.writeU16(&shared_peak, 10, 20);
    support.writeFvarAxis(&shared_peak);
    support.writeSharedTuple(&shared_peak, gvar_offset, 1.0);

    const shared_gvar = Record{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = shared_peak.len - gvar_offset };
    try validateTables(&shared_peak, 1, fvar, shared_gvar, null, null, null, null);

    var shared_peak_outside_normalized_space = shared_peak;
    fixture.writeI16(&shared_peak_outside_normalized_space, gvar_offset + 24, 0x4001);
    try std.testing.expectError(error.BadSfnt, validateTables(&shared_peak_outside_normalized_space, 1, fvar, shared_gvar, null, null, null, null));

    var intermediate: [80]u8 = .{0} ** 80;
    fixture.writeU32(&intermediate, 0, 0x00010000);
    fixture.writeU16(&intermediate, 4, 16);
    fixture.writeU16(&intermediate, 6, 2);
    fixture.writeU16(&intermediate, 8, 1);
    fixture.writeU16(&intermediate, 10, 20);
    support.writeFvarAxis(&intermediate);
    support.writeIntermediateTuple(&intermediate, gvar_offset, 0.0, 0.5, 1.0);

    const intermediate_gvar = Record{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = intermediate.len - gvar_offset };
    try validateTables(&intermediate, 1, fvar, intermediate_gvar, null, null, null, null);

    var reversed_intermediate = intermediate;
    @import("../support.zig").writeF2Dot14(&reversed_intermediate, gvar_offset + 24 + 10, 0.75); // start > peak.
    try std.testing.expectError(error.BadSfnt, validateTables(&reversed_intermediate, 1, fvar, intermediate_gvar, null, null, null, null));

    var crossing_intermediate = intermediate;
    @import("../support.zig").writeF2Dot14(&crossing_intermediate, gvar_offset + 24 + 10, -1.0); // Crosses zero with a non-zero peak.
    try std.testing.expectError(error.BadSfnt, validateTables(&crossing_intermediate, 1, fvar, intermediate_gvar, null, null, null, null));

    var ignored_axis_intermediate = intermediate;
    support.writeIntermediateTuple(&ignored_axis_intermediate, gvar_offset, -1.0, 0.0, 1.0);
    try validateTables(&ignored_axis_intermediate, 1, fvar, intermediate_gvar, null, null, null, null);
}

fn validateTables(
    data: []const u8,
    glyph_count: u16,
    fvar_record: Record,
    gvar_record: Record,
    _: ?Record,
    _: ?Record,
    _: ?Record,
    context: ?validation.TargetContext,
) !void {
    _ = fvar_record;
    try validation.validate(data, gvar_record, glyph_count, 1, context);
}
