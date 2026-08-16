//! Whole-table GSUB feature application and plan integration contracts.
//!
//! `Bindings` supplies root orchestration statically so tests cover source
//! scoping, FeatureVariations, staged plans, and mutations without public test
//! hooks or runtime callbacks.

const std = @import("std");
const feature = @import("../../../feature/root.zig");
const fixture = @import("application_fixture.zig");
const unicode = @import("../../../../unicode.zig");

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB ranged feature selection applies only assigned sources" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 80;
            fixture.writeSingleDeltaFeature(
                &bytes,
                .dflt,
                unicode.tag("liga"),
                10,
                1,
            );

            const lookups = try Bindings.selectedFeatureLookups(
                &bytes,
                0,
                bytes.len,
                unicode.tag("liga"),
                allocator,
                .{ .script_tag = .dflt },
            );
            defer allocator.free(lookups);
            try std.testing.expectEqualSlices(u16, &.{0}, lookups);

            var glyphs = std.ArrayList(u16).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 10, 10, 10 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.appendSlice(allocator, &.{ 0, 1, 2 });
            var clusters = std.ArrayList(usize).empty;
            defer clusters.deinit(allocator);
            try clusters.appendSlice(allocator, &.{ 0, 1, 2 });
            const source_features =
                [_]u32{ unicode.tag("liga"), 0, unicode.tag("liga") };

            try Bindings.applySelectedSource(
                &bytes,
                0,
                bytes.len,
                lookups,
                unicode.tag("liga"),
                1,
                &glyphs,
                allocator,
                .{
                    .script_tag = .dflt,
                    .glyph_source_indices = &sources,
                    .glyph_cluster_indices = &clusters,
                    .source_features = &source_features,
                },
            );
            try std.testing.expectEqualSlices(
                u16,
                &.{ 11, 10, 11 },
                glyphs.items,
            );
        }

        test "GSUB staged plans retain random AlternateSubst semantics" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 80;
            fixture.writeRandomAlternate(&bytes);
            const applications = [_]feature.Application{.{
                .tag = unicode.tag("rand"),
                .value = feature.random_value,
            }};
            const expected = [_]u16{ 30, 20, 20, 30 };

            // All three executors must retain the semantic random bit. Treating
            // the sentinel as the literal alternate index 255 would be a no-op.
            var direct = std.ArrayList(u16).empty;
            defer direct.deinit(allocator);
            try direct.appendSlice(allocator, &.{ 10, 10, 10, 10 });
            var direct_state: u32 = 1;
            try Bindings.applySequence(
                &bytes,
                0,
                bytes.len,
                &applications,
                &direct,
                allocator,
                .{ .script_tag = .dflt, .random_state = &direct_state },
            );
            try std.testing.expectEqualSlices(u16, &expected, direct.items);

            var staged_plan = try Bindings.buildPlan(
                &bytes,
                0,
                bytes.len,
                &applications,
                allocator,
                .{ .script_tag = .dflt },
            );
            defer staged_plan.deinit(allocator);
            var staged = std.ArrayList(u16).empty;
            defer staged.deinit(allocator);
            try staged.appendSlice(allocator, &.{ 10, 10, 10, 10 });
            var staged_state: u32 = 1;
            try Bindings.applyPlan(
                &bytes,
                0,
                bytes.len,
                staged_plan,
                &staged,
                allocator,
                .{ .script_tag = .dflt, .random_state = &staged_state },
            );
            try std.testing.expectEqualSlices(u16, &expected, staged.items);

            var merged_plan = try Bindings.buildMergedPlan(
                &bytes,
                0,
                bytes.len,
                &applications,
                allocator,
                .{ .script_tag = .dflt },
            );
            defer merged_plan.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 1), merged_plan.lookups.len);
            try std.testing.expect(merged_plan.lookups[0].random);
            var merged = std.ArrayList(u16).empty;
            defer merged.deinit(allocator);
            try merged.appendSlice(allocator, &.{ 10, 10, 10, 10 });
            var merged_state: u32 = 1;
            try Bindings.applyMergedPlan(
                &bytes,
                0,
                bytes.len,
                merged_plan,
                &merged,
                allocator,
                .{ .script_tag = .dflt, .random_state = &merged_state },
            );
            try std.testing.expectEqualSlices(u16, &expected, merged.items);
        }

        test "GSUB FeatureVariations replace active feature lookups" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 120;
            fixture.writeFeatureVariations(&bytes);

            var low = std.ArrayList(u16).empty;
            defer low.deinit(allocator);
            try low.append(allocator, 1);
            try Bindings.apply(
                &bytes,
                0,
                bytes.len,
                &low,
                allocator,
                .{
                    .normalized_variation_coords = &.{ 0.0, 0.25 },
                    .apply_all_if_unselected = false,
                },
            );
            try std.testing.expectEqualSlices(u16, &.{1}, low.items);

            var high = std.ArrayList(u16).empty;
            defer high.deinit(allocator);
            try high.append(allocator, 1);
            try Bindings.apply(
                &bytes,
                0,
                bytes.len,
                &high,
                allocator,
                .{
                    .normalized_variation_coords = &.{ 0.0, 0.75 },
                    .apply_all_if_unselected = false,
                },
            );
            try std.testing.expectEqualSlices(u16, &.{2}, high.items);
        }

        test "GSUB source-scoped single feature gates substitution starts" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 68;
            fixture.writeSingleDeltaFeature(
                &bytes,
                .arab,
                unicode.tag("init"),
                1,
                1,
            );

            var scoped = std.ArrayList(u16).empty;
            defer scoped.deinit(allocator);
            try scoped.appendSlice(allocator, &.{ 1, 1, 1 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.appendSlice(allocator, &.{ 0, 1, 2 });
            const source_features =
                [_]u32{ 0, unicode.tag("init"), 0 };
            try Bindings.applySource(
                &bytes,
                0,
                bytes.len,
                unicode.tag("init"),
                &scoped,
                allocator,
                .{
                    .script_tag = .arab,
                    .glyph_source_indices = &sources,
                    .source_features = &source_features,
                },
            );
            try std.testing.expectEqualSlices(
                u16,
                &.{ 1, 2, 1 },
                scoped.items,
            );

            var global = std.ArrayList(u16).empty;
            defer global.deinit(allocator);
            try global.appendSlice(allocator, &.{ 1, 1, 1 });
            try Bindings.applyFeature(
                &bytes,
                0,
                bytes.len,
                unicode.tag("init"),
                &global,
                allocator,
                .{ .script_tag = .arab },
            );
            try std.testing.expectEqualSlices(
                u16,
                &.{ 2, 2, 2 },
                global.items,
            );
        }

        test "GSUB source-scoped multiple feature preserves sidecar alignment" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 78;
            fixture.writeMultipleFeature(
                &bytes,
                .arab,
                unicode.tag("fina"),
                1,
                &.{ 2, 3 },
            );

            var glyphs = std.ArrayList(u16).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 1, 1 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.appendSlice(allocator, &.{ 0, 1, 2 });
            const source_features =
                [_]u32{ 0, unicode.tag("fina"), 0 };
            try Bindings.applySource(
                &bytes,
                0,
                bytes.len,
                unicode.tag("fina"),
                &glyphs,
                allocator,
                .{
                    .script_tag = .arab,
                    .glyph_source_indices = &sources,
                    .source_features = &source_features,
                },
            );
            try std.testing.expectEqualSlices(
                u16,
                &.{ 1, 2, 3, 1 },
                glyphs.items,
            );
            try std.testing.expectEqualSlices(
                usize,
                &.{ 0, 1, 1, 2 },
                sources.items,
            );
        }

        test "GSUB explicit Bengali feature stages chain ligatures" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 160;
            fixture.writeBengaliLigatureStages(&bytes);

            var full = std.ArrayList(u16).empty;
            defer full.deinit(allocator);
            try full.appendSlice(allocator, &.{ 1, 2, 1 });
            try Bindings.apply(
                &bytes,
                0,
                bytes.len,
                &full,
                allocator,
                .{
                    .script_tag = .beng,
                    .features = &.{
                        .{
                            .tag = unicode.tag("half"),
                            .enabled = true,
                        },
                        .{
                            .tag = unicode.tag("pres"),
                            .enabled = true,
                        },
                    },
                },
            );
            try std.testing.expectEqualSlices(u16, &.{6}, full.items);

            var staged = std.ArrayList(u16).empty;
            defer staged.deinit(allocator);
            try staged.appendSlice(allocator, &.{ 1, 2, 1 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.appendSlice(allocator, &.{ 0, 1, 2 });
            var clusters = std.ArrayList(usize).empty;
            defer clusters.deinit(allocator);
            try clusters.appendSlice(allocator, &.{ 0, 0, 0 });
            const syllables = [_]u8{ 1, 1, 1 };
            const source_features = [_]u32{
                feature.sourceMaskForTag(unicode.tag("half")).?,
                0,
                0,
            };
            try Bindings.applySequence(
                &bytes,
                0,
                bytes.len,
                &.{
                    .{
                        .tag = unicode.tag("half"),
                        .source_scoped = true,
                        .match_source_syllable = true,
                        .auto_zwj = false,
                    },
                    .{
                        .tag = unicode.tag("pres"),
                        .auto_zwj = false,
                    },
                },
                &staged,
                allocator,
                .{
                    .script_tag = .beng,
                    .glyph_source_indices = &sources,
                    .glyph_cluster_indices = &clusters,
                    .source_features = &source_features,
                    .source_syllables = &syllables,
                },
            );
            try std.testing.expectEqualSlices(u16, &.{6}, staged.items);
        }
    };
}
