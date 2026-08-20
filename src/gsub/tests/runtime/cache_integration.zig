//! Cached lookup selection and shared run-digest integration contracts.
//!
//! This suite is instantiated by `gsub.zig` with private static orchestration
//! entry points. Keeping the binding comptime avoids exporting test-only hooks
//! or introducing runtime callbacks merely to organize integration tests.

const std = @import("std");
const acceleration = @import("../../accelerator/root.zig");
const direct_single = @import("../../execution/direct/single/root.zig");
const options = @import("../../runtime/options.zig");
const prefilter = @import("../../runtime/prefilter/root.zig");
const state = @import("../../runtime/state.zig");
const table = @import("../../table/root.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const unicode = @import("../../../unicode.zig");

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB run digest cache invalidates after direct substitution" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 12;
            writeU16(&bytes, 0, 1);
            writeU16(&bytes, 2, 6);
            writeI16(&bytes, 4, 1);
            writeCoverage1(&bytes, 6, 1);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 1);
            var generation: usize = 0;
            const run = options.Options{
                .glyph_mutation_generation = &generation,
            };
            var cache = prefilter.Cache.init();
            try std.testing.expect(
                cache.digestForRun(glyphs.items, 0, run).mayHave(1),
            );
            try std.testing.expect(try direct_single.at(
                .{ .data = &bytes, .offset = 0, .length = bytes.len },
                0,
                &glyphs,
                0,
                0,
                run,
            ));
            const refreshed = cache.digestForRun(glyphs.items, 0, run);
            try std.testing.expect(refreshed.mayHave(2));
            try std.testing.expect(!refreshed.mayHave(1));
            try std.testing.expectEqual(generation, cache.generation);
        }

        test "GSUB ligature digest state activates only for reusable tables" {
            const allocator = std.testing.allocator;
            var one = [_]u8{0} ** 46;
            writeU32(&one, 0, 0x00010000);
            writeU16(&one, 8, 10);
            writeU16(&one, 10, 1);
            writeU16(&one, 12, 4);
            writeLigatureLookup(&one, 14, 1, 2, 5);
            const one_sidecars = try acceleration.build.lookup.build(
                &one,
                0,
                one.len,
                allocator,
            );
            defer acceleration.ownership.deinit(allocator, one_sidecars);
            try std.testing.expect(
                !one_sidecars[0].table_uses_run_digest_cache,
            );
            var generation: usize = 0;
            const one_run = state.withDigestGeneration(
                .{ .lookup_accelerators = one_sidecars },
                &generation,
            );
            try std.testing.expect(
                one_run.glyph_mutation_generation == null,
            );

            var two = [_]u8{0} ** 80;
            writeTwoLigatureTable(&two);
            const two_sidecars = try acceleration.build.lookup.build(
                &two,
                0,
                two.len,
                allocator,
            );
            defer acceleration.ownership.deinit(allocator, two_sidecars);
            try std.testing.expect(
                two_sidecars[0].table_uses_run_digest_cache,
            );
            const two_run = state.withDigestGeneration(
                .{ .lookup_accelerators = two_sidecars },
                &generation,
            );
            try std.testing.expect(
                two_run.glyph_mutation_generation != null,
            );
        }

        test "GSUB shared digest observes ligatures introduced by earlier lookup" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 80;
            writeTwoLigatureTable(&bytes);
            const sidecars = try acceleration.build.lookup.build(
                &bytes,
                0,
                bytes.len,
                allocator,
            );
            defer acceleration.ownership.deinit(allocator, sidecars);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });
            var generation: usize = 0;
            const run = options.Options{
                .lookup_accelerators = sidecars,
                .glyph_mutation_generation = &generation,
                .assume_validated = true,
            };
            var cache = prefilter.Cache.init();
            const view = table.View{
                .data = &bytes,
                .offset = 0,
                .length = bytes.len,
                .assume_validated = true,
            };
            try Bindings.applyLookup(
                view,
                16,
                0,
                &glyphs,
                allocator,
                run,
                &cache,
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 5, 3 },
                glyphs.items,
            );
            try Bindings.applyLookup(
                view,
                48,
                1,
                &glyphs,
                allocator,
                run,
                &cache,
            );
            try std.testing.expectEqualSlices(GlyphId, &.{9}, glyphs.items);
            const final = cache.digestForRun(glyphs.items, 0, run);
            try std.testing.expect(final.mayHave(9));
            try std.testing.expect(!final.mayHave(5));
        }

        test "GSUB cached selection requires exact nonempty bounded inputs" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 80;
            writeCachedSingleFeature(&bytes);

            const sidecars = try acceleration.build.lookup.build(
                &bytes,
                0,
                bytes.len,
                allocator,
            );
            defer acceleration.ownership.deinit(allocator, sidecars);
            var operations_left: usize = 64;
            const run = options.Options{
                .selected_lookups = &.{0},
                .lookup_accelerators = sidecars,
                .operations_left = &operations_left,
                .max_glyph_count = 64,
                .assume_validated = true,
            };

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 10);
            try std.testing.expect(try Bindings.applyCachedSelection(
                &bytes,
                0,
                bytes.len,
                &glyphs,
                allocator,
                run,
            ));
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{11},
                glyphs.items,
            );

            // Every rejection must happen before the valid first lookup can
            // mutate the run; generic fallback is safe only under that atomic
            // decline contract.
            glyphs.items[0] = 10;
            var empty = run;
            empty.selected_lookups = &.{};
            try expectCachedDecline(
                Bindings,
                &bytes,
                &glyphs,
                allocator,
                empty,
            );

            var foreign_bytes = bytes;
            try std.testing.expect(!try Bindings.applyCachedSelection(
                &foreign_bytes,
                0,
                foreign_bytes.len,
                &glyphs,
                allocator,
                run,
            ));
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{10},
                glyphs.items,
            );

            const copied_sidecars = try allocator.dupe(
                acceleration.Lookup,
                sidecars,
            );
            defer allocator.free(copied_sidecars);
            var copied = run;
            copied.lookup_accelerators = copied_sidecars;
            try expectCachedDecline(
                Bindings,
                &bytes,
                &glyphs,
                allocator,
                copied,
            );

            var invalid = run;
            invalid.selected_lookups = &.{ 0, 1 };
            try expectCachedDecline(
                Bindings,
                &bytes,
                &glyphs,
                allocator,
                invalid,
            );

            var unbounded = run;
            unbounded.operations_left = null;
            try expectCachedDecline(
                Bindings,
                &bytes,
                &glyphs,
                allocator,
                unbounded,
            );
        }
    };
}

fn expectCachedDecline(
    comptime Bindings: type,
    bytes: []const u8,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: options.Options,
) !void {
    try std.testing.expect(!try Bindings.applyCachedSelection(
        bytes,
        0,
        bytes.len,
        glyphs,
        allocator,
        run,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{10}, glyphs.items);
}

fn writeCachedSingleFeature(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 30);
    writeU16(bytes, 8, 44);

    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 30, 1);
    writeU32(bytes, 32, unicode.tag("liga"));
    writeU16(bytes, 36, 8);
    writeU16(bytes, 38, 0);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 0);

    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 4);
    writeU16(bytes, 48, 1);
    writeU16(bytes, 50, 0);
    writeU16(bytes, 52, 1);
    writeU16(bytes, 54, 8);
    writeU16(bytes, 56, 1);
    writeU16(bytes, 58, 6);
    writeI16(bytes, 60, 1);
    writeCoverage1(bytes, 62, 10);
}

fn writeTwoLigatureTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 2);
    writeU16(bytes, 12, 6);
    writeU16(bytes, 14, 38);
    writeLigatureLookup(bytes, 16, 1, 2, 5);
    writeLigatureLookup(bytes, 48, 5, 3, 9);
}

fn writeLigatureLookup(
    bytes: []u8,
    lookup: usize,
    first: GlyphId,
    second: GlyphId,
    output: GlyphId,
) void {
    writeU16(bytes, lookup, 4);
    writeU16(bytes, lookup + 2, 0);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    const subtable = lookup + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 18);
    writeU16(bytes, subtable + 4, 1);
    writeU16(bytes, subtable + 6, 8);
    const set = subtable + 8;
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, 4);
    writeU16(bytes, set + 4, output);
    writeU16(bytes, set + 6, 2);
    writeU16(bytes, set + 8, second);
    writeCoverage1(bytes, subtable + 18, first);
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
