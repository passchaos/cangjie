//! Contextual record position/provenance integration after LigatureSubst.

const std = @import("std");
const fixture = @import("ligature_fixture.zig");
const ligature_provenance =
    @import("../../../../../ligature_provenance.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "contextual ligature compacts positions before later MultipleSubst" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 92;
            fixture.writeLookupList(&bytes, &.{ 6, 40 });
            fixture.writeLigatureLookup(&bytes, 16, 0, 1, 2, 10);
            fixture.writeMultipleLookup(&bytes, 50, 3, &.{ 3, 4 });
            const records = 84;
            fixture.writeRecord(&bytes, records, 0, 0);
            fixture.writeRecord(&bytes, records + 4, 1, 1);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });
            try Bindings.applyRecords(
                fixture.view(&bytes),
                &glyphs,
                records,
                2,
                &.{ 0, 1, 2 },
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 10, 3, 4 },
                glyphs.items,
            );
        }

        test "contextual ligature preserves ignored-component provenance" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 112;
            fixture.writeLookupList(&bytes, &.{ 8, 50, 82 });
            writeParentContext(&bytes);
            fixture.writeLigatureLookup(&bytes, 60, 0x0008, 1, 2, 40);
            fixture.writeSingleLookup(&bytes, 92, 40, 1);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 99, 2 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.appendSlice(allocator, &.{ 0, 1, 2 });
            var provenance = ligature_provenance.Store{};
            defer provenance.deinit(allocator);
            try provenance.infos.resize(allocator, 3);
            @memset(provenance.infos.items, .{});
            var classes = [_]u16{0} ** 100;
            classes[99] = 3;

            try Bindings.applyLookup(
                fixture.view(&bytes),
                18,
                &glyphs,
                allocator,
                .{
                    .glyph_classes = &classes,
                    .glyph_source_indices = &sources,
                    .ligature_components = &provenance,
                },
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 40, 99 },
                glyphs.items,
            );
            try std.testing.expectEqualSlices(
                usize,
                &.{ 0, 1 },
                sources.items,
            );
            try std.testing.expectEqual(
                @as(u8, 2),
                provenance.infos.items[0].component_count,
            );
            try std.testing.expectEqualSlices(
                usize,
                &.{ 0, 2 },
                provenance.componentSources(provenance.infos.items[0]).?,
            );
            try std.testing.expectEqual(
                @as(u8, 1),
                provenance.infos.items[1].component_count,
            );
        }
    };
}

fn writeParentContext(bytes: []u8) void {
    fixture.writeU16(bytes, 18, 5);
    fixture.writeU16(bytes, 22, 1);
    fixture.writeU16(bytes, 24, 8);
    const context = 26;
    fixture.writeU16(bytes, context, 1);
    fixture.writeU16(bytes, context + 2, 28);
    fixture.writeU16(bytes, context + 4, 1);
    fixture.writeU16(bytes, context + 6, 8);
    const set = context + 8;
    fixture.writeU16(bytes, set, 1);
    fixture.writeU16(bytes, set + 2, 4);
    const rule = set + 4;
    fixture.writeU16(bytes, rule, 3);
    fixture.writeU16(bytes, rule + 2, 2);
    fixture.writeU16(bytes, rule + 4, 99);
    fixture.writeU16(bytes, rule + 6, 2);
    fixture.writeRecord(bytes, rule + 8, 0, 1);
    fixture.writeRecord(bytes, rule + 12, 2, 2);
    fixture.writeU16(bytes, context + 28, 1);
    fixture.writeU16(bytes, context + 30, 1);
    fixture.writeU16(bytes, context + 32, 1);
}
