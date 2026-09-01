//! GPOS plan execution and lookup-kind integration contracts.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const feature = @import("../../../feature/root.zig");
const fixtures = @import("fixtures.zig");
const positioning = @import("../../../positioning/root.zig");
const runtime_run = @import("../../../runtime/run.zig");
const ShapeStageProfile = @import("../../../../shape_profile.zig").ShapeStageProfile;
const unicode = @import("../../../../unicode.zig");

const writeFeatureTable = fixtures.writeFeatureTable;
const writeI16 = fixtures.writeI16;
const writeMarkBaseTable = fixtures.writeMarkBaseTable;
const writePairTable = fixtures.writePairTable;
const writeU16 = fixtures.writeU16;

test "GPOS plan leaves disabled filtering to the dispatcher" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;
    writeFeatureTable(&bytes);
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    var plan = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{ .lookup_accelerators = sidecars, .assume_validated = true },
    );
    defer plan.deinit(allocator);
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expect(try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{5},
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .disabled_lookups = &.{0},
            .assume_validated = true,
        },
    ));
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 17), adjustments.items[0].x_placement);
}

test "GPOS plan keeps variation coordinates live at execution time" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;
    writeFeatureTable(&bytes);
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    const build_coords = [_]f32{0.25};
    var plan = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{
            .normalized_variation_coords = &build_coords,
            .lookup_accelerators = sidecars,
            .assume_validated = true,
        },
    );
    defer plan.deinit(allocator);

    // The plan stores only stable lookup tuples, so a different live variation
    // vector is valid at application time rather than part of cache identity.
    const apply_coords = [_]f32{0.75};
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expect(try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{5},
        &adjustments,
        allocator,
        .{
            .normalized_variation_coords = &apply_coords,
            .lookup_accelerators = sidecars,
            .assume_validated = true,
        },
    ));
    try std.testing.expectEqual(@as(i16, 28), adjustments.items[0].x_placement);
}

test "GPOS plan executes owned direct PairPos data" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 52;
    writePairTable(&bytes, false, -25);
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    var plan = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{ .lookup_accelerators = sidecars, .assume_validated = true },
    );
    defer plan.deinit(allocator);
    var ordinary = std.ArrayList(positioning.Adjustment).empty;
    defer ordinary.deinit(allocator);
    try runtime_run.collectAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &.{ 5, 7 },
        &ordinary,
        allocator,
        .{
            .run_has_default_ignorables = false,
        },
    );

    // The accelerator owns this common xAdvance-only PairValue. Mutating the
    // backing record after construction distinguishes exact accelerated plan
    // execution from an accidental generic-table fallback.
    writeI16(&bytes, 38, 99);
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expect(try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .assume_validated = true,
            .run_has_default_ignorables = false,
        },
    ));
    try expectPairAdjustment(adjustments.items, -25);
    try std.testing.expectEqualDeep(ordinary.items, adjustments.items);
}

test "GPOS plan executes owned homogeneous ExtensionPos PairPos data" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 60;
    writePairTable(&bytes, true, -35);
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    try std.testing.expectEqual(@as(?u16, 2), sidecars[0].extension_lookup_type);
    try std.testing.expect(sidecars[0].pair_pos_extension);
    var plan = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{ .lookup_accelerators = sidecars, .assume_validated = true },
    );
    defer plan.deinit(allocator);
    var ordinary = std.ArrayList(positioning.Adjustment).empty;
    defer ordinary.deinit(allocator);
    try runtime_run.collectAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &.{ 5, 7 },
        &ordinary,
        allocator,
        .{
            .run_has_default_ignorables = false,
        },
    );

    // The wrapped PairPos payload is owned by the homogeneous-extension
    // accelerator just as it is for a direct lookup.
    writeI16(&bytes, 46, 99);
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expect(try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .assume_validated = true,
            .run_has_default_ignorables = false,
        },
    ));
    try expectPairAdjustment(adjustments.items, -35);
    try std.testing.expectEqualDeep(ordinary.items, adjustments.items);
}

test "GPOS plan executes owned MarkBase coverage data" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 74;
    writeMarkBaseTable(&bytes);
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    var plan = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{
            .run_may_have_mark_attachments = true,
            .lookup_accelerators = sidecars,
            .assume_validated = true,
        },
    );
    defer plan.deinit(allocator);
    var ordinary = std.ArrayList(positioning.Adjustment).empty;
    defer ordinary.deinit(allocator);
    try runtime_run.collectAfterMetadataProof(
        &bytes,
        0,
        bytes.len,
        &.{ 20, 22 },
        &ordinary,
        allocator,
        .{
            .run_may_have_mark_attachments = true,
        },
    );

    // MarkBase sidecars own both coverage maps but continue borrowing anchors.
    // Poison only the source coverage glyphs to prove the owned path is used.
    writeU16(&bytes, 38, 99);
    writeU16(&bytes, 44, 99);
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expect(try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{ 20, 22 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .assume_validated = true,
            .run_may_have_mark_attachments = true,
        },
    ));
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    const mark = adjustments.items[0];
    try std.testing.expectEqual(@as(usize, 1), mark.index);
    try std.testing.expectEqual(@as(i16, 90), mark.x_placement);
    try std.testing.expectEqual(@as(i16, 105), mark.y_placement);
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);
    try std.testing.expectEqualDeep(ordinary.items, adjustments.items);
}

test "GPOS plan empty no-op succeeds and dynamic modes decline atomically" {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);

    // An arbitrary empty value cannot suppress positioning for an unrelated
    // table: successful no-op plans are still bound to their build source.
    try std.testing.expect(!try feature.plan.apply.afterProof(
        &.{},
        99,
        99,
        .{ .entries = &.{} },
        &.{5},
        &adjustments,
        allocator,
        .{},
    ));

    var bytes = [_]u8{0} ** 112;
    writeFeatureTable(&bytes);
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    var empty = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{
            .features = &.{.{
                .tag = unicode.tag("kern"),
                .enabled = false,
            }},
            .lookup_accelerators = sidecars,
            .assume_validated = true,
        },
    );
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.entries.len);
    try std.testing.expect(try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        empty,
        &.{5},
        &adjustments,
        allocator,
        .{ .lookup_accelerators = sidecars, .assume_validated = true },
    ));

    var plan = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{ .lookup_accelerators = sidecars, .assume_validated = true },
    );
    defer plan.deinit(allocator);

    try std.testing.expect(!try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{5},
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .enabled_lookups = &.{1},
            .assume_validated = true,
        },
    ));
    var profile = ShapeStageProfile{};
    try std.testing.expect(!try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{5},
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .assume_validated = true,
            .shape_profile = &profile,
            .profile_io = std.testing.io,
        },
    ));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    try std.testing.expectEqual(@as(u64, 0), profile.gpos_lookup_count);
}

fn expectPairAdjustment(
    adjustments: []const positioning.Adjustment,
    advance: i16,
) !void {
    try std.testing.expectEqual(@as(usize, 1), adjustments.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments[0].index);
    try std.testing.expectEqual(advance, adjustments[0].x_advance);
    try std.testing.expect(adjustments[0].pair_positioned);
}
