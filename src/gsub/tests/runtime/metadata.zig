//! GSUB runtime metadata validation contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const runtime = @import("../../runtime/root.zig");

test "runtime metadata requires parallel glyph sidecars" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.append(std.testing.allocator, 0);

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.metadata.validate(.{
            .glyph_source_indices = &sources,
            .glyph_cluster_indices = &clusters,
        }, 1),
    );
}

test "feature plans derive source metadata requirements" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.append(std.testing.allocator, 0);

    const source_scoped_entries = [_]feature.LookupPlanEntry{.{
        .application = .{ .tag = 1, .source_scoped = true },
        .lookups = &.{},
        .lookup_offsets = &.{},
    }};
    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.metadata.validateLookupPlan(
            .{ .glyph_source_indices = &sources },
            1,
            .{ .entries = @constCast(&source_scoped_entries) },
        ),
    );

    const syllable_application = [_]feature.Application{.{
        .tag = 2,
        .match_source_syllable = true,
    }};
    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.metadata.validateApplications(
            .{ .glyph_source_indices = &sources },
            1,
            &syllable_application,
        ),
    );

    const merged_lookups = [_]feature.MergedLookup{.{
        .lookup = 0,
        .source_mask = 1,
    }};
    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.metadata.validateMergedLookupPlan(
            .{ .glyph_source_indices = &sources },
            1,
            .{ .lookups = @constCast(&merged_lookups), .lookup_offsets = &.{} },
        ),
    );
}

test "script shaper metadata validates source domains once" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.append(std.testing.allocator, 1);

    try std.testing.expectError(
        error.InvalidShapingInput,
        runtime.validateScriptShaperMetadata(.{
            .glyph_source_indices = &sources,
            .source_features = &.{1},
            .source_syllables = &.{1},
        }, 1),
    );
    try runtime.validateScriptShaperMetadata(.{
        .glyph_source_indices = &sources,
        .source_features = &.{ 1, 2 },
        .source_syllables = &.{ 1, 2 },
        .source_codepoints = &.{ 0x41, 0x42 },
    }, 1);
}
