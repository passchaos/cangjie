//! Whole-table glyph bounds and indexed-coverage integration contracts.
//!
//! These tests cross lookup kinds through the complete validation walker. They
//! complement lookup-local validator tests by proving maxp and Coverage index
//! contracts remain enforced when reached from a GSUB table root.

const std = @import("std");
const fixture = @import("fixture.zig");

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB whole-table validation bounds glyph ids across lookup kinds" {
            const glyph_count: u16 = 3;

            {
                var bytes = [_]u8{0} ** 38;
                const subtable = fixture.writeSingleLookupTable(&bytes, 1);
                fixture.writeSingleDeltaSubtable(&bytes, subtable, 3, 0);
                try expectBadBounds(Bindings, &bytes, glyph_count);
            }

            {
                var bytes = [_]u8{0} ** 38;
                const subtable = fixture.writeSingleLookupTable(&bytes, 1);
                fixture.writeSingleDeltaSubtable(
                    &bytes,
                    subtable,
                    1,
                    0x7fff,
                );
                // Shaping may feed a transient full-domain delta output into a
                // later lookup; strict font-load validation must still reject
                // an output that maxp cannot render.
                try expectBadBounds(Bindings, &bytes, glyph_count);
                try Bindings.validateForShaping(
                    &bytes,
                    0,
                    bytes.len,
                    glyph_count,
                );
            }

            {
                var bytes = [_]u8{0} ** 42;
                const subtable = fixture.writeSingleLookupTable(&bytes, 1);
                fixture.writeU16(&bytes, subtable, 2);
                fixture.writeU16(&bytes, subtable + 2, 10);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 3);
                fixture.writeCoverage1(&bytes, subtable + 10, 1);
                try expectBadBounds(Bindings, &bytes, glyph_count);
            }

            {
                var bytes = [_]u8{0} ** 46;
                const subtable = fixture.writeSingleLookupTable(&bytes, 2);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 14);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 8);
                fixture.writeU16(&bytes, subtable + 8, 2);
                fixture.writeU16(&bytes, subtable + 10, 1);
                fixture.writeU16(&bytes, subtable + 12, 3);
                fixture.writeCoverage1(&bytes, subtable + 14, 1);
                try expectBadBounds(Bindings, &bytes, glyph_count);
            }

            {
                var bytes = [_]u8{0} ** 46;
                const subtable = fixture.writeSingleLookupTable(&bytes, 3);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 14);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 8);
                fixture.writeU16(&bytes, subtable + 8, 2);
                fixture.writeU16(&bytes, subtable + 10, 2);
                fixture.writeU16(&bytes, subtable + 12, 3);
                fixture.writeCoverage1(&bytes, subtable + 14, 1);
                try expectBadBounds(Bindings, &bytes, glyph_count);
            }

            {
                var bytes = [_]u8{0} ** 50;
                const subtable = fixture.writeSingleLookupTable(&bytes, 4);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 18);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 8);
                fixture.writeU16(&bytes, subtable + 8, 1);
                fixture.writeU16(&bytes, subtable + 10, 4);
                fixture.writeU16(&bytes, subtable + 12, 2);
                fixture.writeU16(&bytes, subtable + 14, 2);
                fixture.writeU16(&bytes, subtable + 16, 3);
                fixture.writeCoverage1(&bytes, subtable + 18, 1);
                try expectBadBounds(Bindings, &bytes, glyph_count);
            }

            {
                var bytes = [_]u8{0} ** 48;
                const subtable = fixture.writeSingleLookupTable(&bytes, 5);
                fixture.writeU16(&bytes, subtable, 2);
                fixture.writeU16(&bytes, subtable + 2, 8);
                fixture.writeU16(&bytes, subtable + 4, 14);
                fixture.writeU16(&bytes, subtable + 6, 0);
                fixture.writeCoverage1(&bytes, subtable + 8, 1);
                fixture.writeU16(&bytes, subtable + 14, 1);
                fixture.writeU16(&bytes, subtable + 16, 3);
                fixture.writeU16(&bytes, subtable + 18, 1);
                fixture.writeU16(&bytes, subtable + 20, 1);
                try expectBadBounds(Bindings, &bytes, glyph_count);
            }

            {
                var bytes = [_]u8{0} ** 44;
                const subtable = fixture.writeSingleLookupTable(&bytes, 8);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 12);
                fixture.writeU16(&bytes, subtable + 4, 0);
                fixture.writeU16(&bytes, subtable + 6, 0);
                fixture.writeU16(&bytes, subtable + 8, 1);
                fixture.writeU16(&bytes, subtable + 10, 3);
                fixture.writeCoverage1(&bytes, subtable + 12, 1);
                try expectBadBounds(Bindings, &bytes, glyph_count);
            }
        }

        test "GSUB whole-table validation matches indexed Coverage cardinality" {
            {
                var bytes = [_]u8{0} ** 44;
                const subtable = fixture.writeSingleLookupTable(&bytes, 1);
                fixture.writeU16(&bytes, subtable, 2);
                fixture.writeU16(&bytes, subtable + 2, 10);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 2);
                fixture.writeCoverage1List(
                    &bytes,
                    subtable + 10,
                    &.{ 1, 2 },
                );
                try expectBadBounds(Bindings, &bytes, 4);
            }

            {
                var bytes = [_]u8{0} ** 46;
                const subtable = fixture.writeSingleLookupTable(&bytes, 2);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 12);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 8);
                fixture.writeU16(&bytes, subtable + 8, 1);
                fixture.writeU16(&bytes, subtable + 10, 2);
                fixture.writeCoverage1List(
                    &bytes,
                    subtable + 12,
                    &.{ 1, 2 },
                );
                try expectBadBounds(Bindings, &bytes, 4);
            }

            {
                var bytes = [_]u8{0} ** 46;
                const subtable = fixture.writeSingleLookupTable(&bytes, 3);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 12);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 8);
                fixture.writeU16(&bytes, subtable + 8, 1);
                fixture.writeU16(&bytes, subtable + 10, 2);
                fixture.writeCoverage1List(
                    &bytes,
                    subtable + 12,
                    &.{ 1, 2 },
                );
                try expectBadBounds(Bindings, &bytes, 4);
            }

            {
                var bytes = [_]u8{0} ** 50;
                const subtable = fixture.writeSingleLookupTable(&bytes, 4);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 16);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 8);
                fixture.writeU16(&bytes, subtable + 8, 1);
                fixture.writeU16(&bytes, subtable + 10, 4);
                fixture.writeU16(&bytes, subtable + 12, 2);
                fixture.writeU16(&bytes, subtable + 14, 1);
                fixture.writeCoverage1List(
                    &bytes,
                    subtable + 16,
                    &.{ 1, 2 },
                );
                try expectBadBounds(Bindings, &bytes, 4);
            }
        }
    };
}

fn expectBadBounds(
    comptime Bindings: type,
    bytes: []const u8,
    glyph_count: u16,
) !void {
    try std.testing.expectError(
        error.BadGsub,
        Bindings.validate(bytes, 0, bytes.len, glyph_count),
    );
}
