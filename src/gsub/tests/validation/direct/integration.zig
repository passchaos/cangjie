//! Direct-subtable validation and low-level execution integration contracts.
//!
//! These cases prove malformed indexed children fail before mutation while
//! preserving shaping-mode compatibility for authored empty ligature data.

const std = @import("std");
const fixture = @import("../table/fixture.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB SingleSubst rejects unsorted Coverage before mutation" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 18;
            fixture.writeU16(&bytes, 0, 2);
            fixture.writeU16(&bytes, 2, 10);
            fixture.writeU16(&bytes, 4, 1);
            fixture.writeU16(&bytes, 6, 20);
            fixture.writeCoverage1List(&bytes, 10, &.{ 10, 5 });

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 10);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.applySingle(
                    view(&bytes),
                    0,
                    &glyphs,
                    0,
                    .{},
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{10},
                glyphs.items,
            );
        }

        test "GSUB MultipleSubst requires a real Sequence child" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 44;
            const subtable = fixture.writeSingleLookupTable(&bytes, 2);
            writeIndexedChildHeader(&bytes, subtable, 8, 0);
            fixture.writeCoverage1(&bytes, subtable + 8, 1);

            try std.testing.expectError(
                error.BadGsub,
                Bindings.validateMultiple(view(&bytes), subtable),
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validateTable(&bytes, 0, bytes.len, 4),
            );

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 1);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.applyMultiple(
                    view(&bytes),
                    subtable,
                    &glyphs,
                    allocator,
                    0,
                    .{},
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{1},
                glyphs.items,
            );

            // An explicitly authored empty Sequence is valid; only the child
            // offset itself is mandatory.
            fixture.writeU16(&bytes, subtable + 6, 14);
            fixture.writeU16(&bytes, subtable + 14, 0);
            try Bindings.validateMultiple(view(&bytes), subtable);
            try Bindings.validateTable(&bytes, 0, bytes.len, 4);
        }

        test "GSUB AlternateSubst requires a real AlternateSet child" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 44;
            const subtable = fixture.writeSingleLookupTable(&bytes, 3);
            writeIndexedChildHeader(&bytes, subtable, 8, 0);
            fixture.writeCoverage1(&bytes, subtable + 8, 1);

            try std.testing.expectError(
                error.BadGsub,
                Bindings.validateAlternate(view(&bytes), subtable),
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validateTable(&bytes, 0, bytes.len, 4),
            );

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 1);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.applyAlternate(
                    view(&bytes),
                    subtable,
                    &glyphs,
                    0,
                    .{},
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{1},
                glyphs.items,
            );

            fixture.writeU16(&bytes, subtable + 6, 14);
            fixture.writeU16(&bytes, subtable + 14, 0);
            try Bindings.validateAlternate(view(&bytes), subtable);
            try Bindings.validateTable(&bytes, 0, bytes.len, 4);
        }

        test "GSUB LigatureSubst keeps strict and shaping child policy distinct" {
            const allocator = std.testing.allocator;

            {
                var bytes = [_]u8{0} ** 44;
                const subtable = fixture.writeSingleLookupTable(&bytes, 4);
                writeIndexedChildHeader(&bytes, subtable, 8, 0);
                fixture.writeCoverage1(&bytes, subtable + 8, 1);

                try std.testing.expectError(
                    error.BadGsub,
                    Bindings.validateLigature(
                        view(&bytes),
                        subtable,
                        .strict,
                    ),
                );
                try std.testing.expectError(
                    error.BadGsub,
                    Bindings.validateTable(&bytes, 0, bytes.len, 4),
                );

                var glyphs = std.ArrayList(GlyphId).empty;
                defer glyphs.deinit(allocator);
                try glyphs.appendSlice(allocator, &.{ 1, 2 });
                try Bindings.applyLigature(
                    view(&bytes),
                    subtable,
                    &glyphs,
                    allocator,
                    0,
                    .{},
                );
                try std.testing.expectEqualSlices(
                    GlyphId,
                    &.{ 1, 2 },
                    glyphs.items,
                );
                try std.testing.expectEqual(
                    null,
                    try Bindings.applyNestedLigature(
                        view(&bytes),
                        subtable,
                        &glyphs,
                        0,
                        allocator,
                        0,
                        .{},
                    ),
                );

                fixture.writeU16(&bytes, subtable + 6, 14);
                fixture.writeU16(&bytes, subtable + 14, 0);
                try Bindings.validateLigature(
                    view(&bytes),
                    subtable,
                    .strict,
                );
                try Bindings.validateTable(&bytes, 0, bytes.len, 4);
            }

            {
                var bytes = [_]u8{0} ** 44;
                const subtable = fixture.writeSingleLookupTable(&bytes, 4);
                fixture.writeU16(&bytes, subtable, 1);
                fixture.writeU16(&bytes, subtable + 2, 12);
                fixture.writeU16(&bytes, subtable + 4, 1);
                fixture.writeU16(&bytes, subtable + 6, 8);
                fixture.writeU16(&bytes, subtable + 8, 1);
                fixture.writeU16(&bytes, subtable + 10, 0);
                fixture.writeCoverage1(&bytes, subtable + 12, 1);

                try std.testing.expectError(
                    error.BadGsub,
                    Bindings.validateLigature(
                        view(&bytes),
                        subtable,
                        .strict,
                    ),
                );
                var glyphs = std.ArrayList(GlyphId).empty;
                defer glyphs.deinit(allocator);
                try glyphs.appendSlice(allocator, &.{ 1, 2 });
                try Bindings.applyLigature(
                    view(&bytes),
                    subtable,
                    &glyphs,
                    allocator,
                    0,
                    .{},
                );
                try std.testing.expectEqualSlices(
                    GlyphId,
                    &.{ 1, 2 },
                    glyphs.items,
                );
                try std.testing.expectEqual(
                    null,
                    try Bindings.applyNestedLigature(
                        view(&bytes),
                        subtable,
                        &glyphs,
                        0,
                        allocator,
                        0,
                        .{},
                    ),
                );
            }
        }
    };
}

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeIndexedChildHeader(
    bytes: []u8,
    subtable: usize,
    coverage_relative: u16,
    child_relative: u16,
) void {
    fixture.writeU16(bytes, subtable, 1);
    fixture.writeU16(bytes, subtable + 2, coverage_relative);
    fixture.writeU16(bytes, subtable + 4, 1);
    fixture.writeU16(bytes, subtable + 6, child_relative);
}
