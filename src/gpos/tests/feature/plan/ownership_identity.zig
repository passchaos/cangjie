//! GPOS plan construction, ownership, and identity contracts.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const feature = @import("../../../feature/root.zig");
const fixtures = @import("fixtures.zig");
const positioning = @import("../../../positioning/root.zig");

const writeFeatureTable = fixtures.writeFeatureTable;
const writeTopologyFreeTable = fixtures.writeTopologyFreeTable;

test "GPOS plan owns canonical feature-selected index and offset tuples" {
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
    try std.testing.expectEqual(@as(usize, 2), plan.entries.len);
    try std.testing.expectEqualDeep(
        feature.LookupPlanEntry{
            .lookup_index = 0,
            .lookup_offset = 60,
        },
        plan.entries[0],
    );
    try std.testing.expectEqualDeep(
        feature.LookupPlanEntry{
            .lookup_index = 1,
            .lookup_offset = 84,
        },
        plan.entries[1],
    );

    // Selection inputs are only needed while building. The plan retains no
    // caller-owned slices, including the feature-override array.
    bytes[50] = 0xff;
    try std.testing.expectEqual(@as(usize, 60), plan.entries[0].lookup_offset);
}

test "GPOS plan preserves topology-free apply-all fallback" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeTopologyFreeTable(&bytes);
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
            .apply_all_if_unselected = false,
            .lookup_accelerators = sidecars,
            .assume_validated = true,
        },
    );
    defer plan.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), plan.entries.len);
    try std.testing.expectEqual(@as(u16, 0), plan.entries[0].lookup_index);
    try std.testing.expectEqual(@as(u16, 1), plan.entries[1].lookup_index);
}

test "GPOS plan builder releases owned entries on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildPlanForAllocationFailure,
        .{},
    );
}

test "GPOS nonempty plan construction requires exact sidecars" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;
    writeFeatureTable(&bytes);
    try std.testing.expectError(
        error.InvalidShapingInput,
        feature.plan.build.lookupPlan(
            &bytes,
            0,
            bytes.len,
            allocator,
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidShapingInput,
        feature.plan.build.lookupPlan(
            &bytes,
            0,
            bytes.len,
            allocator,
            .{ .assume_validated = true },
        ),
    );
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    try std.testing.expectError(
        error.InvalidShapingInput,
        feature.plan.build.lookupPlan(
            &bytes,
            0,
            bytes.len,
            allocator,
            .{
                .selected_lookups = &.{0},
                .lookup_accelerators = sidecars,
                .assume_validated = true,
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidShapingInput,
        feature.plan.build.lookupPlan(
            &bytes,
            0,
            bytes.len,
            allocator,
            .{
                .enabled_lookups = &.{0},
                .lookup_accelerators = sidecars,
                .assume_validated = true,
            },
        ),
    );
}

test "GPOS plan executes with exact table and sidecar identity" {
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
            .assume_validated = true,
        },
    ));
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    // Both selected lookups target the same glyph, so adjustment coalescing
    // retains one record containing their summed placement.
    try std.testing.expectEqual(@as(i16, 28), adjustments.items[0].x_placement);
}

test "GPOS plan declines copied and foreign sidecars without output" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;
    var foreign_bytes = [_]u8{0} ** 112;
    writeFeatureTable(&bytes);
    writeFeatureTable(&foreign_bytes);
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    const foreign_sidecars = try accelerator.build.lookup.all(
        &foreign_bytes,
        0,
        foreign_bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, foreign_sidecars);
    const copied = try allocator.dupe(accelerator.Lookup, sidecars);
    defer allocator.free(copied);
    var plan = try feature.plan.build.lookupPlan(
        &bytes,
        0,
        bytes.len,
        allocator,
        .{ .lookup_accelerators = sidecars, .assume_validated = true },
    );
    defer plan.deinit(allocator);
    const foreign_plan = try feature.plan.build.lookupPlan(
        &foreign_bytes,
        0,
        foreign_bytes.len,
        allocator,
        .{
            .lookup_accelerators = foreign_sidecars,
            .assume_validated = true,
        },
    );
    var owned_foreign_plan = foreign_plan;
    defer owned_foreign_plan.deinit(allocator);
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expect(!try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{5},
        &adjustments,
        allocator,
        .{ .lookup_accelerators = copied, .assume_validated = true },
    ));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    // Even identical tuple values do not make a plan portable between backing
    // allocations. This rejects a wrong-font selection before any lookup runs.
    try std.testing.expect(!try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        foreign_plan,
        &.{5},
        &adjustments,
        allocator,
        .{ .lookup_accelerators = sidecars, .assume_validated = true },
    ));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    try std.testing.expect(!try feature.plan.apply.afterProof(
        &foreign_bytes,
        0,
        foreign_bytes.len,
        plan,
        &.{5},
        &adjustments,
        allocator,
        .{ .lookup_accelerators = foreign_sidecars, .assume_validated = true },
    ));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS plan is bound to its exact accelerator allocation" {
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
    const replacement = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, replacement);
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

    try std.testing.expect(!try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        plan,
        &.{5},
        &adjustments,
        allocator,
        .{ .lookup_accelerators = replacement, .assume_validated = true },
    ));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS plan preflights every tuple before the first adjustment" {
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
    var entries = [_]feature.LookupPlanEntry{
        .{ .lookup_index = 0, .lookup_offset = 60 },
        .{ .lookup_index = 1, .lookup_offset = 83 },
    };
    const identity = feature.PlanIdentity{
        .data_ptr = @as([]const u8, &bytes).ptr,
        .data_len = bytes.len,
        .table_offset = 0,
        .table_length = bytes.len,
        .accelerators_addr = @intFromPtr(sidecars.ptr),
        .accelerator_count = sidecars.len,
    };
    var adjustments = std.ArrayList(positioning.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expect(!try feature.plan.apply.afterProof(
        &bytes,
        0,
        bytes.len,
        .{ .entries = &entries, .identity = identity },
        &.{5},
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = sidecars,
            .disabled_lookups = &.{1},
            .assume_validated = true,
        },
    ));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

fn buildPlanForAllocationFailure(allocator: std.mem.Allocator) !void {
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
    try std.testing.expectEqual(@as(usize, 2), plan.entries.len);
}
