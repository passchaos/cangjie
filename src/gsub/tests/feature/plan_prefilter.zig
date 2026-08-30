//! Cached-plan early necessary-condition filtering contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const feature = @import("../../feature/root.zig");
const mutation = @import("../../runtime/mutation.zig");
const prefilter = @import("../../runtime/prefilter/root.zig");
const plan_prefilter = @import("../../feature/plan/apply/prefilter.zig");
const table = @import("../../table/root.zig");
const GlyphDigest = @import("../../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const ShapeStageProfile = @import("../../../shape_profile.zig").ShapeStageProfile;

const ProbeExecutor = struct {
    var unprofiled_calls: usize = 0;
    var profiled_calls: usize = 0;

    fn reset() void {
        unprofiled_calls = 0;
        profiled_calls = 0;
    }

    pub fn applyLookupUnprofiledAfterPlanProof(
        _: table.View,
        _: usize,
        lookup_index: u16,
        glyphs: *std.ArrayList(GlyphId),
        allocator: std.mem.Allocator,
        run: feature.plan.apply.cached.Options,
        _: *prefilter.Cache,
        _: *const accelerator.Lookup,
    ) feature.plan.apply.cached.Error!void {
        unprofiled_calls += 1;
        if (lookup_index != 0) return;

        // Model an earlier cardinality-changing lookup which introduces the
        // sole first-input candidate of lookup 1. The production mutation
        // helper advances the same epoch consumed by the plan prefilter.
        const prepared = try mutation.prepareReplacement(
            allocator,
            glyphs,
            run,
            0,
            1,
            2,
            0,
        );
        prepared.commit(glyphs, &.{ 42, 9 });
    }

    pub fn applyLookup(
        _: table.View,
        _: usize,
        _: u16,
        _: *std.ArrayList(GlyphId),
        _: std.mem.Allocator,
        _: feature.plan.apply.cached.Options,
        _: *prefilter.Cache,
    ) feature.plan.apply.cached.Error!void {
        profiled_calls += 1;
    }
};

test "trusted staged plan rejects only absent complete candidates" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 10;
    writeU32(&bytes, 0, 0x00010000);
    // The trusted plan owns the real offsets; only keep the topology nonempty.
    writeU16(&bytes, 8, 8);
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 9);

    var first_digest = GlyphDigest.empty();
    first_digest.add(42);
    const sets = [_]accelerator.model.LigatureSet{.{
        .glyph = 42,
        .definition_start = 0,
        .definition_len = 1,
    }};
    const sidecars = [_]accelerator.Lookup{.{
        .lookup_offset = 8,
        .lookup_type = 4,
        .subtable_count = 1,
        .table_uses_run_digest_cache = true,
        .ligature_subst = .{
            .sets = &sets,
            .first_component_digest = first_digest,
        },
    }};
    const entries = [_]feature.LookupPlanEntry{.{
        .application = .{ .tag = 0 },
        .lookups = @constCast(&[_]u16{0}),
        .lookup_offsets = @constCast(&[_]usize{8}),
    }};
    const plan = feature.LookupPlan{ .entries = @constCast(&entries) };

    ProbeExecutor.reset();
    try feature.plan.apply.cached.staged(
        ProbeExecutor,
        true,
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        plan,
        &glyphs,
        allocator,
        .{
            .lookup_accelerators = &sidecars,
            .assume_validated = true,
        },
        false,
    );
    try std.testing.expectEqual(@as(usize, 0), ProbeExecutor.unprofiled_calls);

    glyphs.items[0] = 42;
    try feature.plan.apply.cached.staged(
        ProbeExecutor,
        true,
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        plan,
        &glyphs,
        allocator,
        .{
            .lookup_accelerators = &sidecars,
            .assume_validated = true,
        },
        false,
    );
    try std.testing.expectEqual(@as(usize, 1), ProbeExecutor.unprofiled_calls);

    // Profiling owns lookup accounting, so a definite miss must still cross
    // the ordinary executor boundary rather than disappear before timing.
    glyphs.items[0] = 9;
    var profile = ShapeStageProfile{};
    try feature.plan.apply.cached.staged(
        ProbeExecutor,
        true,
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        plan,
        &glyphs,
        allocator,
        .{
            .lookup_accelerators = &sidecars,
            .assume_validated = true,
            .shape_profile = &profile,
        },
        false,
    );
    try std.testing.expectEqual(@as(usize, 1), ProbeExecutor.profiled_calls);
}

test "trusted merged plan refreshes digest after earlier cardinality mutation" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 7);

    var first_digest = GlyphDigest.empty();
    first_digest.add(7);
    const first_sets = [_]accelerator.model.LigatureSet{.{
        .glyph = 7,
        .definition_start = 0,
        .definition_len = 1,
    }};
    var second_digest = GlyphDigest.empty();
    second_digest.add(42);
    const second_sets = [_]accelerator.model.LigatureSet{.{
        .glyph = 42,
        .definition_start = 0,
        .definition_len = 1,
    }};
    const sidecars = [_]accelerator.Lookup{
        .{
            .lookup_offset = 8,
            .lookup_type = 4,
            .subtable_count = 1,
            .table_uses_run_digest_cache = true,
            .ligature_subst = .{
                .sets = &first_sets,
                .first_component_digest = first_digest,
            },
        },
        .{
            .lookup_offset = 16,
            .lookup_type = 4,
            .subtable_count = 1,
            .ligature_subst = .{
                .sets = &second_sets,
                .first_component_digest = second_digest,
            },
        },
    };
    const lookups = [_]feature.MergedLookup{
        .{ .lookup = 0 },
        .{ .lookup = 1 },
    };
    const offsets = [_]usize{ 8, 16 };
    var bytes = [_]u8{0} ** 10;

    ProbeExecutor.reset();
    try feature.plan.apply.cached.mergedAfterPlanProof(
        ProbeExecutor,
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        .{
            .lookups = @constCast(&lookups),
            .lookup_offsets = @constCast(&offsets),
        },
        &glyphs,
        allocator,
        .{
            .lookup_accelerators = &sidecars,
            .assume_validated = true,
        },
    );

    try std.testing.expectEqualSlices(GlyphId, &.{ 42, 9 }, glyphs.items);
    try std.testing.expectEqual(@as(usize, 2), ProbeExecutor.unprofiled_calls);
}

test "trusted plan prefilter recognizes direct and extension candidates" {
    var digest = GlyphDigest.empty();
    digest.add(42);
    const sets = [_]accelerator.model.LigatureSet{.{
        .glyph = 42,
        .definition_start = 0,
        .definition_len = 1,
    }};
    const cases = [_]accelerator.Lookup{
        .{
            .lookup_type = 4,
            .subtable_count = 1,
            .ligature_subst = .{
                .sets = &sets,
                .first_component_digest = digest,
            },
        },
        .{
            .lookup_type = 7,
            .subtable_count = 1,
            .extension_lookup_type = 4,
            .ligature_subst = .{
                .sets = &sets,
                .first_component_digest = digest,
            },
        },
        .{
            .lookup_type = 6,
            .chaining_coverage_only = true,
            .chaining_input_digest = digest,
        },
        .{
            .lookup_type = 7,
            .extension_lookup_type = 6,
            .chaining_coverage_only = true,
            .chaining_input_digest = digest,
        },
    };

    for (&cases) |*sidecar| {
        var generation: usize = 0;
        var absent_cache = prefilter.Cache.init();
        try std.testing.expect(!plan_prefilter.mayMatch(
            sidecar,
            &.{9},
            .{ .glyph_mutation_generation = &generation },
            &absent_cache,
        ));
        var admitted_cache = prefilter.Cache.init();
        try std.testing.expect(plan_prefilter.mayMatch(
            sidecar,
            &.{42},
            .{ .glyph_mutation_generation = &generation },
            &admitted_cache,
        ));
    }

    // Class-based and incomplete sidecars are capability misses, not proof
    // that the underlying lookup cannot match.
    var conservative_cache = prefilter.Cache.init();
    try std.testing.expect(plan_prefilter.mayMatch(
        &.{ .lookup_type = 6 },
        &.{9},
        .{},
        &conservative_cache,
    ));

    // A detached caller without a mutation epoch cannot safely reuse a
    // cached digest across repeated plan entries. It must stay conservative.
    try std.testing.expect(plan_prefilter.mayMatch(
        &cases[0],
        &.{9},
        .{},
        &conservative_cache,
    ));
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
