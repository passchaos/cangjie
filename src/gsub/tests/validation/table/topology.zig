//! Whole-table topology and activation-graph integration contracts.
//!
//! `Bindings` is supplied by `gsub.zig` at comptime so these tests can cover
//! its source-level entry points without exporting test hooks or storing
//! runtime callbacks.

const std = @import("std");
const acceleration = @import("../../../accelerator/root.zig");
const service = @import("../../../table/service.zig");
const table = @import("../../../table/root.zig");
const unicode = @import("../../../../unicode.zig");

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB requires each nonempty top-level list pointer" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 38;
            const subtable = writeSingleLookupTable(&bytes, 1);
            writeSingleSubtable(&bytes, subtable, 1, 1);
            var glyphs = std.ArrayList(u16).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 1);

            // A missing LookupList cannot execute and must leave the run
            // untouched before reporting the structural error.
            writeU16(&bytes, 8, 0);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(&bytes, 0, bytes.len, 4),
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.apply(&bytes, 0, bytes.len, &glyphs, allocator, .{}),
            );
            try std.testing.expectEqualSlices(u16, &.{1}, glyphs.items);

            // Selection may defensively fall back to a proven LookupList when
            // ScriptList is missing. Font-load validation remains strict.
            writeU16(&bytes, 8, 14);
            writeU16(&bytes, 4, 0);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(&bytes, 0, bytes.len, 4),
            );
            try Bindings.apply(
                &bytes,
                0,
                bytes.len,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(u16, &.{2}, glyphs.items);

            // FeatureList is needed to prove that fallback itself is safe.
            writeU16(&bytes, 4, 10);
            writeU16(&bytes, 6, 0);
            glyphs.items[0] = 1;
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(&bytes, 0, bytes.len, 4),
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.apply(&bytes, 0, bytes.len, &glyphs, allocator, .{}),
            );
            try std.testing.expectEqualSlices(u16, &.{1}, glyphs.items);

            writeU16(&bytes, 6, 12);
            try Bindings.validate(&bytes, 0, bytes.len, 4);
            try Bindings.apply(
                &bytes,
                0,
                bytes.len,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(u16, &.{2}, glyphs.items);
        }

        test "GSUB requires real LookupList children before mutation" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 38;
            const subtable = writeSingleLookupTable(&bytes, 1);
            writeSingleSubtable(&bytes, subtable, 1, 1);
            writeU16(&bytes, 16, 0);

            const view = table.View{
                .data = &bytes,
                .offset = 0,
                .length = bytes.len,
            };
            try std.testing.expectError(
                error.BadGsub,
                service.requiredLookup(view, 14, 0),
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(&bytes, 0, bytes.len, 4),
            );

            var glyphs = std.ArrayList(u16).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 1);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.apply(&bytes, 0, bytes.len, &glyphs, allocator, .{}),
            );
            try std.testing.expectEqualSlices(u16, &.{1}, glyphs.items);

            writeU16(&bytes, 16, 4);
            try Bindings.validate(&bytes, 0, bytes.len, 4);
            try Bindings.apply(
                &bytes,
                0,
                bytes.len,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(u16, &.{2}, glyphs.items);
        }

        test "GSUB all-null topology is a valid empty table across surfaces" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 10;
            writeU32(&bytes, 0, 0x00010000);

            try std.testing.expect(try Bindings.isEmpty(
                &bytes,
                0,
                bytes.len,
            ));
            try Bindings.validate(&bytes, 0, bytes.len, 4);
            try std.testing.expect(!(try Bindings.hasFeature(
                &bytes,
                0,
                bytes.len,
                unicode.tag("liga"),
            )));

            var glyphs = std.ArrayList(u16).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 2 });
            try Bindings.apply(
                &bytes,
                0,
                bytes.len,
                &glyphs,
                allocator,
                .{},
            );
            try std.testing.expectEqualSlices(u16, &.{ 1, 2 }, glyphs.items);

            const selected = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{},
            );
            defer allocator.free(selected);
            try std.testing.expectEqual(@as(usize, 0), selected.len);

            var staged = try Bindings.buildPlan(
                &bytes,
                0,
                bytes.len,
                &.{.{ .tag = unicode.tag("liga") }},
                allocator,
                .{},
            );
            defer staged.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 0), staged.entries.len);
            try Bindings.applyPlan(
                &bytes,
                0,
                bytes.len,
                staged,
                &glyphs,
                allocator,
                .{},
            );

            var merged = try Bindings.buildMergedPlan(
                &bytes,
                0,
                bytes.len,
                &.{.{ .tag = unicode.tag("liga") }},
                allocator,
                .{},
            );
            defer merged.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 0), merged.lookups.len);
            try Bindings.applyMergedPlan(
                &bytes,
                0,
                bytes.len,
                merged,
                &glyphs,
                allocator,
                .{},
            );

            const sidecars = try acceleration.build.lookup.build(
                &bytes,
                0,
                bytes.len,
                allocator,
            );
            defer allocator.free(sidecars);
            try std.testing.expectEqual(@as(usize, 0), sidecars.len);

            // One nonzero pointer is not the canonical empty topology.
            writeU16(&bytes, 4, 2);
            try std.testing.expect(!(try Bindings.isEmpty(
                &bytes,
                0,
                bytes.len,
            )));
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(&bytes, 0, bytes.len, 4),
            );
        }

        test "GSUB activation graph validates feature and lookup references" {
            var feature_bytes = [_]u8{0} ** 50;
            writeU32(&feature_bytes, 0, 0x00010000);
            writeU16(&feature_bytes, 4, 48);
            writeU16(&feature_bytes, 6, 10);
            writeU16(&feature_bytes, 8, 24);
            writeU16(&feature_bytes, 10, 1);
            writeU32(&feature_bytes, 12, unicode.tag("liga"));
            writeU16(&feature_bytes, 16, 8);
            writeU16(&feature_bytes, 20, 1);
            writeU16(&feature_bytes, 22, 1);
            writeU16(&feature_bytes, 24, 1);
            writeU16(&feature_bytes, 26, 4);
            writeSingleDeltaLookup(&feature_bytes, 28, 1, 0);
            writeU16(&feature_bytes, 48, 0);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(
                    &feature_bytes,
                    0,
                    feature_bytes.len,
                    4,
                ),
            );
            writeU16(&feature_bytes, 22, 0);
            try Bindings.validate(
                &feature_bytes,
                0,
                feature_bytes.len,
                4,
            );

            var script_bytes = [_]u8{0} ** 80;
            writeScriptFeatureGraph(&script_bytes);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(
                    &script_bytes,
                    0,
                    script_bytes.len,
                    4,
                ),
            );
            writeU16(&script_bytes, 28, 0);
            try Bindings.validate(
                &script_bytes,
                0,
                script_bytes.len,
                4,
            );
            writeU16(&script_bytes, 24, 1);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(
                    &script_bytes,
                    0,
                    script_bytes.len,
                    4,
                ),
            );
        }
    };
}

fn writeSingleLookupTable(bytes: []u8, lookup_type: u16) usize {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 12);
    writeU16(bytes, 8, 14);
    writeU16(bytes, 10, 0);
    writeU16(bytes, 12, 0);
    writeU16(bytes, 14, 1);
    writeU16(bytes, 16, 4);
    writeU16(bytes, 18, lookup_type);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 1);
    writeU16(bytes, 24, 8);
    return 26;
}

fn writeSingleSubtable(
    bytes: []u8,
    subtable: usize,
    glyph: u16,
    delta: i16,
) void {
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 6);
    writeI16(bytes, subtable + 4, delta);
    writeCoverage1(bytes, subtable + 6, glyph);
}

fn writeSingleDeltaLookup(
    bytes: []u8,
    lookup: usize,
    glyph: u16,
    delta: i16,
) void {
    writeU16(bytes, lookup, 1);
    writeU16(bytes, lookup + 2, 0);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);
    writeSingleSubtable(bytes, lookup + 8, glyph, delta);
}

fn writeScriptFeatureGraph(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 40);
    writeU16(bytes, 8, 56);
    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 1);
    writeU16(bytes, 40, 1);
    writeU32(bytes, 42, unicode.tag("liga"));
    writeU16(bytes, 46, 8);
    writeU16(bytes, 50, 0);
    writeU16(bytes, 52, 1);
    writeU16(bytes, 54, 0);
    writeU16(bytes, 56, 1);
    writeU16(bytes, 58, 4);
    writeSingleDeltaLookup(bytes, 60, 1, 0);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
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
