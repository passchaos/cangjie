//! GSUB runtime options source-level API contracts.

const std = @import("std");
const runtime = @import("../../runtime/root.zig");

test "GSUB runtime options are concrete values with borrowed sidecars" {
    var operations_left: usize = 32;
    var mutation_generation: usize = 4;
    const selected = [_]u16{ 1, 3 };
    const options = runtime.Options{
        .text_direction = .rtl,
        .selected_lookups = &selected,
        .operations_left = &operations_left,
        .glyph_mutation_generation = &mutation_generation,
    };

    try std.testing.expectEqual(runtime.options.Direction.rtl, options.text_direction);
    try std.testing.expectEqualSlices(u16, &selected, options.selected_lookups.?);
    try std.testing.expect(options.operations_left == &operations_left);
    try std.testing.expect(
        options.glyph_mutation_generation == &mutation_generation,
    );

    // Copies retain ordinary borrowed pointers/slices rather than transferring
    // hidden ownership through a handle.
    var stage = options;
    stage.active_feature_value = 7;
    stage.context_depth = 3;
    try std.testing.expectEqual(@as(u32, 1), options.active_feature_value);
    try std.testing.expectEqual(@as(u32, 7), stage.active_feature_value);
    try std.testing.expectEqual(@as(usize, 0), options.context_depth);
    try std.testing.expectEqual(@as(usize, 3), stage.context_depth);
    try std.testing.expect(stage.operations_left == options.operations_left);
}

test "GSUB runtime options default to an unscoped defensive run" {
    const options = runtime.Options{};

    try std.testing.expectEqual(runtime.options.Direction.ltr, options.text_direction);
    try std.testing.expectEqual(@as(usize, 0), options.features.len);
    try std.testing.expectEqual(@as(usize, 0), options.normalized_variation_coords.len);
    try std.testing.expect(options.selected_lookups == null);
    try std.testing.expect(options.lookup_accelerators == null);
    try std.testing.expectEqual(@as(usize, 0), options.context_depth);
    try std.testing.expect(!options.assume_validated);
}
