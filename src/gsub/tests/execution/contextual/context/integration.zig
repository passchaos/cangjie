//! Root-bound accelerated ContextSubst integration contracts.
//!
//! The focused matcher tests use local executors. This suite binds the real
//! root nested dispatcher to prove authored-rule fallback, syllable bounds,
//! glyph mutation, and unsafe-cluster marking remain coherent end to end.

const std = @import("std");
const acceleration = @import("../../../../accelerator/root.zig");
const class_context = @import("../../../../../opentype/class_context.zig");
const cluster_safety =
    @import("../../../../../shaping/cluster_safety.zig");
const context = @import("../../../../execution/contextual/context/root.zig");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "accelerated ContextSubst falls back to shorter rule at syllable end" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 64;

            // Nested records resolve through an ordinary table-root LookupList
            // even though this test invokes the accelerated matcher directly.
            writeU32(&bytes, 0, 0x00010000);
            writeU16(&bytes, 8, 10);
            writeU16(&bytes, 10, 1);
            writeU16(&bytes, 12, 4);
            writeSingleDeltaLookup(&bytes, 14, 1, 10);

            const coverage = 40;
            writeCoverage1(&bytes, coverage, 1);
            const class_def = 46;
            writeU16(&bytes, class_def, 1);
            writeU16(&bytes, class_def + 2, 1);
            writeU16(&bytes, class_def + 4, 3);
            writeU16(&bytes, class_def + 6, 3);
            writeU16(&bytes, class_def + 8, 1);
            writeU16(&bytes, class_def + 10, 5);
            const records = 60;
            writeU16(&bytes, records, 0);
            writeU16(&bytes, records + 2, 0);

            const classes = [_]u16{
                1, 5,
                2, 1,
                5, acceleration.index.class_first.sorted_encoding,
                1, 0,
            };
            const rules = [_]class_context.Rule{
                .{
                    .class_set = 3,
                    .input_count = 3,
                    .lookahead_count = 0,
                    .hash = class_context.sequenceHash(classes[0..2]),
                    .order = 0,
                    .lookup_index = 0,
                    .classes_start = 0,
                    .subst_count = 1,
                    .records_offset = records,
                },
                .{
                    .class_set = 3,
                    .input_count = 4,
                    .lookahead_count = 0,
                    .hash = class_context.sequenceHash(classes[2..5]),
                    .order = 1,
                    .lookup_index = 0,
                    .classes_start = 2,
                    .subst_count = 1,
                    .records_offset = records,
                },
            };
            const groups = [_]class_context.RuleGroup{.{
                .class_set = 3,
                .start = 0,
                .len = rules.len,
                .max_input_count = 4,
                .max_lookahead_count = 0,
            }};
            const sidecar = acceleration.model.ContextClassSubtable{
                .first_index_start = 5,
                .class_def = class_def,
                .rules = &rules,
                .classes = &classes,
                .groups = &groups,
            };

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 2, 3, 9 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.appendSlice(allocator, &.{ 0, 1, 2, 3 });
            const source_byte_starts = [_]usize{ 0, 1, 2, 3 };
            const source_syllables = [_]u8{ 1, 1, 1, 2 };
            var boundaries = cluster_safety.SourceBoundaries{};
            defer boundaries.deinit(allocator);
            boundaries.reset(0, 4, &source_byte_starts);

            const result = try context.acceleratedClassAt(
                Bindings.Executor,
                table.View{
                    .data = &bytes,
                    .offset = 0,
                    .length = bytes.len,
                    .assume_validated = true,
                },
                sidecar,
                &glyphs,
                0,
                allocator,
                0,
                .{
                    .glyph_source_indices = &sources,
                    .source_boundaries = &boundaries,
                    .source_syllables = &source_syllables,
                    .match_source_syllable = true,
                },
            );

            try std.testing.expect(result.matched);
            try std.testing.expectEqual(@as(usize, 3), result.next_pos);
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 11, 2, 3, 9 },
                glyphs.items,
            );
            try std.testing.expect(!boundaries.isUnsafeBeforeByte(0));
            try std.testing.expect(boundaries.isUnsafeBeforeByte(1));
            try std.testing.expect(boundaries.isUnsafeBeforeByte(2));
            try std.testing.expect(!boundaries.isUnsafeBeforeByte(3));
        }

        test "ContextSubst root dispatch skips LookupFlag-ignored glyphs" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 72;
            writeU32(&bytes, 0, 0x00010000);
            writeU16(&bytes, 8, 10);
            writeU16(&bytes, 10, 2);
            writeU16(&bytes, 12, 6);
            writeU16(&bytes, 14, 42);

            writeU16(&bytes, 16, 5);
            writeU16(&bytes, 18, 0x0008);
            writeU16(&bytes, 20, 1);
            writeU16(&bytes, 22, 8);

            const subtable = 24;
            writeU16(&bytes, subtable, 1);
            writeU16(&bytes, subtable + 2, 22);
            writeU16(&bytes, subtable + 4, 1);
            writeU16(&bytes, subtable + 6, 8);
            const set = subtable + 8;
            writeU16(&bytes, set, 1);
            writeU16(&bytes, set + 2, 4);
            const rule = set + 4;
            writeU16(&bytes, rule, 2);
            writeU16(&bytes, rule + 2, 1);
            writeU16(&bytes, rule + 4, 2);
            writeU16(&bytes, rule + 6, 1);
            writeU16(&bytes, rule + 8, 1);
            writeCoverage1(&bytes, subtable + 22, 1);
            writeSingleDeltaLookup(&bytes, 52, 2, 10);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 3, 2 });
            const glyph_classes = [_]u16{ 0, 0, 0, 3 };

            try Bindings.applyLookup(
                table.View{
                    .data = &bytes,
                    .offset = 0,
                    .length = bytes.len,
                },
                16,
                &glyphs,
                allocator,
                .{ .glyph_classes = &glyph_classes },
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 1, 3, 12 },
                glyphs.items,
            );
        }
    };
}

fn writeSingleDeltaLookup(
    bytes: []u8,
    offset: usize,
    glyph: GlyphId,
    delta: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 6);
    writeI16(bytes, offset + 12, delta);
    writeCoverage1(bytes, offset + 14, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
