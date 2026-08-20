//! SequenceLookupRecord array, lookup-index, and SequenceIndex atomicity.

const std = @import("std");
const fixture = @import("fixture.zig");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "contextual record truncation is atomic" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 96;
            fixture.writeLookupList(&bytes, &.{ 6, 14 });
            fixture.writeU16(&bytes, 16, 5);
            fixture.writeU16(&bytes, 20, 1);
            fixture.writeU16(&bytes, 22, 28);
            fixture.writeSingleDeltaLookup(&bytes, 24, 1, 9);

            const context = 44;
            const rule = writeGlyphContext(
                &bytes,
                context,
                8,
                14,
                2,
                0,
                1,
            );
            var glyphs = try oneGlyph(allocator);
            defer glyphs.deinit(allocator);
            const truncated = table.View{
                .data = &bytes,
                .offset = 0,
                .length = rule + 8,
            };
            try expectAtomicBadGsub(
                Bindings,
                truncated,
                16,
                &glyphs,
                allocator,
            );
        }

        test "contextual records reject dangling lookup indexes atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 90;
            writeValidatedTableHeader(&bytes);
            fixture.writeU16(&bytes, 14, 2);
            fixture.writeU16(&bytes, 16, 6);
            fixture.writeU16(&bytes, 18, 50);

            const context_lookup = 20;
            fixture.writeU16(&bytes, context_lookup, 5);
            fixture.writeU16(&bytes, context_lookup + 4, 1);
            fixture.writeU16(&bytes, context_lookup + 6, 8);
            const rule = writeGlyphContext(
                &bytes,
                context_lookup + 8,
                8,
                14,
                2,
                0,
                1,
            );
            fixture.writeU16(&bytes, rule + 8, 0);
            fixture.writeU16(&bytes, rule + 10, 2);
            fixture.writeSingleDeltaLookup(&bytes, 64, 1, 9);

            var glyphs = try oneGlyph(allocator);
            defer glyphs.deinit(allocator);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validateTable(&bytes, 0, bytes.len, 20),
            );
            try expectAtomicBadGsub(
                Bindings,
                fixture.view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
            );

            fixture.writeU16(&bytes, rule + 10, 1);
            try Bindings.validateTable(&bytes, 0, bytes.len, 20);
            try Bindings.applyLookup(
                fixture.view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{10},
                glyphs.items,
            );
        }

        test "contextual records safely skip out-of-range SequenceIndex" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 84;
            writeValidatedTableHeader(&bytes);
            fixture.writeU16(&bytes, 14, 2);
            fixture.writeU16(&bytes, 16, 6);
            fixture.writeU16(&bytes, 18, 50);

            const context_lookup = 20;
            fixture.writeU16(&bytes, context_lookup, 5);
            fixture.writeU16(&bytes, context_lookup + 4, 1);
            fixture.writeU16(&bytes, context_lookup + 6, 8);
            const rule = writeGlyphContext(
                &bytes,
                context_lookup + 8,
                8,
                14,
                1,
                1,
                1,
            );
            fixture.writeSingleDeltaLookup(&bytes, 64, 1, 9);

            var glyphs = try oneGlyph(allocator);
            defer glyphs.deinit(allocator);
            try Bindings.validateTable(&bytes, 0, bytes.len, 20);
            try Bindings.applyLookup(
                fixture.view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{1},
                glyphs.items,
            );

            fixture.writeU16(&bytes, rule + 4, 0);
            try Bindings.applyLookup(
                fixture.view(&bytes),
                context_lookup,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{10},
                glyphs.items,
            );
        }
    };
}

fn oneGlyph(allocator: std.mem.Allocator) !std.ArrayList(GlyphId) {
    var glyphs = std.ArrayList(GlyphId).empty;
    try glyphs.append(allocator, 1);
    return glyphs;
}

fn writeValidatedTableHeader(bytes: []u8) void {
    fixture.writeU32(bytes, 0, 0x00010000);
    fixture.writeU16(bytes, 4, 10);
    fixture.writeU16(bytes, 6, 12);
    fixture.writeU16(bytes, 8, 14);
    fixture.writeU16(bytes, 10, 0);
    fixture.writeU16(bytes, 12, 0);
}

fn writeGlyphContext(
    bytes: []u8,
    context: usize,
    coverage_relative: u16,
    set_relative: u16,
    record_count: u16,
    sequence_index: u16,
    lookup_index: u16,
) usize {
    fixture.writeU16(bytes, context, 1);
    fixture.writeU16(bytes, context + 2, coverage_relative);
    fixture.writeU16(bytes, context + 4, 1);
    fixture.writeU16(bytes, context + 6, set_relative);
    fixture.writeCoverage1(bytes, context + coverage_relative, 1);
    const set = context + set_relative;
    fixture.writeU16(bytes, set, 1);
    fixture.writeU16(bytes, set + 2, 4);
    const rule = set + 4;
    fixture.writeU16(bytes, rule, 1);
    fixture.writeU16(bytes, rule + 2, record_count);
    fixture.writeU16(bytes, rule + 4, sequence_index);
    fixture.writeU16(bytes, rule + 6, lookup_index);
    return rule;
}

fn expectAtomicBadGsub(
    comptime Bindings: type,
    view: table.View,
    lookup_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
) !void {
    try std.testing.expectError(
        error.BadGsub,
        Bindings.applyLookup(
            view,
            lookup_offset,
            glyphs,
            allocator,
            .{},
        ),
    );
    try std.testing.expectEqualSlices(GlyphId, &.{1}, glyphs.items);
}
