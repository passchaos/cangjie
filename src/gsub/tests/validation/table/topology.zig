//! Whole-table topology and activation-graph integration contracts.
//!
//! `Bindings` is supplied by `gsub.zig` at comptime so these tests can cover
//! its source-level entry points without exporting test hooks or storing
//! runtime callbacks.

const std = @import("std");
const acceleration = @import("../../../accelerator/root.zig");
const fixture = @import("fixture.zig");
const service = @import("../../../table/service.zig");
const table = @import("../../../table/root.zig");
const unicode = @import("../../../../unicode.zig");

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB requires each nonempty top-level list pointer" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 38;
            const subtable = fixture.writeSingleLookupTable(&bytes, 1);
            fixture.writeSingleDeltaSubtable(&bytes, subtable, 1, 1);
            var glyphs = std.ArrayList(u16).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 1);

            // A missing LookupList cannot execute and must leave the run
            // untouched before reporting the structural error.
            fixture.writeU16(&bytes, 8, 0);
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
            fixture.writeU16(&bytes, 8, 14);
            fixture.writeU16(&bytes, 4, 0);
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
            fixture.writeU16(&bytes, 4, 10);
            fixture.writeU16(&bytes, 6, 0);
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

            fixture.writeU16(&bytes, 6, 12);
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
            const subtable = fixture.writeSingleLookupTable(&bytes, 1);
            fixture.writeSingleDeltaSubtable(&bytes, subtable, 1, 1);
            fixture.writeU16(&bytes, 16, 0);

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

            fixture.writeU16(&bytes, 16, 4);
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
            fixture.writeU32(&bytes, 0, 0x00010000);

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
            fixture.writeU16(&bytes, 4, 2);
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
            fixture.writeU32(&feature_bytes, 0, 0x00010000);
            fixture.writeU16(&feature_bytes, 4, 48);
            fixture.writeU16(&feature_bytes, 6, 10);
            fixture.writeU16(&feature_bytes, 8, 24);
            fixture.writeU16(&feature_bytes, 10, 1);
            fixture.writeU32(&feature_bytes, 12, unicode.tag("liga"));
            fixture.writeU16(&feature_bytes, 16, 8);
            fixture.writeU16(&feature_bytes, 20, 1);
            fixture.writeU16(&feature_bytes, 22, 1);
            fixture.writeU16(&feature_bytes, 24, 1);
            fixture.writeU16(&feature_bytes, 26, 4);
            fixture.writeSingleDeltaLookup(&feature_bytes, 28, 1, 0);
            fixture.writeU16(&feature_bytes, 48, 0);
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(
                    &feature_bytes,
                    0,
                    feature_bytes.len,
                    4,
                ),
            );
            fixture.writeU16(&feature_bytes, 22, 0);
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
            fixture.writeU16(&script_bytes, 28, 0);
            try Bindings.validate(
                &script_bytes,
                0,
                script_bytes.len,
                4,
            );
            fixture.writeU16(&script_bytes, 24, 1);
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

fn writeScriptFeatureGraph(bytes: []u8) void {
    fixture.writeU32(bytes, 0, 0x00010000);
    fixture.writeU16(bytes, 4, 10);
    fixture.writeU16(bytes, 6, 40);
    fixture.writeU16(bytes, 8, 56);
    fixture.writeU16(bytes, 10, 1);
    fixture.writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    fixture.writeU16(bytes, 16, 8);
    fixture.writeU16(bytes, 18, 4);
    fixture.writeU16(bytes, 20, 0);
    fixture.writeU16(bytes, 22, 0);
    fixture.writeU16(bytes, 24, 0xffff);
    fixture.writeU16(bytes, 26, 1);
    fixture.writeU16(bytes, 28, 1);
    fixture.writeU16(bytes, 40, 1);
    fixture.writeU32(bytes, 42, unicode.tag("liga"));
    fixture.writeU16(bytes, 46, 8);
    fixture.writeU16(bytes, 50, 0);
    fixture.writeU16(bytes, 52, 1);
    fixture.writeU16(bytes, 54, 0);
    fixture.writeU16(bytes, 56, 1);
    fixture.writeU16(bytes, 58, 4);
    fixture.writeSingleDeltaLookup(bytes, 60, 1, 0);
}
