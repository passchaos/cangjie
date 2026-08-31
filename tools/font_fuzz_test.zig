//! Coverage-guided malformed-font fuzz entry point for Zig's built-in fuzzer.

const std = @import("std");
const cangjie = @import("cangjie");
const driver = @import("font_fuzz/driver.zig");

const seeds = [_][]const u8{
    @embedFile("font_fuzz/seeds/fontations_cmap12_font1.ttf"),
    @embedFile("font_fuzz/seeds/fontations_names_only.ttf"),
    @embedFile("font_fuzz/seeds/fontations_simple_glyf.ttf"),
    @embedFile("font_fuzz/seeds/fontations_cmap14_font1.ttf"),
    @embedFile("font_fuzz/seeds/fontations_vazirmatn_var.ttf"),
    @embedFile("font_fuzz/seeds/vorg.ttf"),
};

const max_seed_bytes = blk: {
    var result: usize = 0;
    for (seeds) |seed| result = @max(result, seed.len);
    break :blk result;
};

test "coverage-guided malformed font parsing, shaping, and rendering" {
    // Ordinary `zig build font-fuzz` remains a deterministic smoke gate for
    // every seed. `--fuzz` then lets Smith mutate the same structured inputs.
    for (seeds) |seed| {
        try driver.exerciseCase(std.testing.allocator, seed);
    }
    try std.testing.fuzz({}, fuzzOne, .{});
}

fn fuzzOne(_: void, smith: *std.testing.Smith) !void {
    const seed = seeds[smith.index(seeds.len)];
    var input: [max_seed_bytes]u8 = undefined;
    @memcpy(input[0..seed.len], seed);

    // A bounded edit script preserves useful valid-font ancestry while still
    // allowing the coverage engine to explore correlated offset/count edits.
    const mutation_count = smith.valueRangeAtMost(u8, 0, 32);
    for (0..mutation_count) |_| {
        const index = smith.index(seed.len);
        input[index] = smith.value(u8);
    }

    // Prefixes stress table-directory and child-record bounds. Bias toward the
    // full seed so deeper cmap/outline/raster code remains reachable.
    const truncate = smith.boolWeighted(8, 1);
    const input_len = if (truncate)
        smith.valueRangeAtMost(u16, 0, @intCast(seed.len))
    else
        @as(u16, @intCast(seed.len));
    try driver.exerciseCase(std.testing.allocator, input[0..input_len]);
}

test "coverage-guided AAT table parsing" {
    inline for (std.enums.values(AatKind)) |kind| {
        const seed = try buildAatSeed(std.testing.allocator, kind);
        defer std.testing.allocator.free(seed);
        try driver.exerciseCase(std.testing.allocator, seed);
    }
    try std.testing.fuzz({}, fuzzAatTables, .{});
}

const AatKind = enum(u8) { morx, mort, kerx, trak };

fn buildAatSeed(allocator: std.mem.Allocator, kind: AatKind) ![]u8 {
    return switch (kind) {
        .morx => try cangjie.testing.test_font.buildMorxTtf(allocator),
        .mort => try cangjie.testing.test_font.buildMortTtf(allocator),
        .kerx => try cangjie.testing.test_font.buildKerxTtf(allocator),
        .trak => try cangjie.testing.test_font.buildTrakTtf(allocator),
    };
}

fn fuzzAatTables(_: void, smith: *std.testing.Smith) !void {
    const allocator = std.testing.allocator;
    const seed = try buildAatSeed(allocator, smith.value(AatKind));
    defer allocator.free(seed);
    try mutateAndExercise(allocator, seed, smith);
}

test "coverage-guided OpenType shaping tables" {
    // Exercise every valid builder before Smith selects one mutation lineage.
    // This keeps the deterministic build gate representative of each GSUB,
    // GPOS, and mixed AAT table family listed below.
    inline for (std.enums.values(OpenTypeShapingKind)) |kind| {
        const seed = try buildOpenTypeShapingSeed(std.testing.allocator, kind);
        defer std.testing.allocator.free(seed);
        try driver.exerciseCase(std.testing.allocator, seed);
    }
    try std.testing.fuzz({}, fuzzOpenTypeShapingTables, .{});
}

const OpenTypeShapingKind = enum(u8) {
    gsub_ligature,
    gsub_multiple,
    gsub_context,
    gsub_chaining,
    gsub_feature_range,
    gpos_pair,
    gpos_mark_to_ligature,
    gpos_context,
    gpos_cursive,
    gsub_gpos_aat,
};

fn buildOpenTypeShapingSeed(
    allocator: std.mem.Allocator,
    kind: OpenTypeShapingKind,
) ![]u8 {
    return switch (kind) {
        .gsub_ligature => try cangjie.testing.test_font.buildMinimalGsubTtf(allocator),
        .gsub_multiple => try cangjie.testing.test_font.buildMultipleGsubTtf(allocator),
        .gsub_context => try cangjie.testing.test_font.buildContextGsubTtf(allocator),
        .gsub_chaining => try cangjie.testing.test_font.buildChainingGsubTtf(allocator),
        .gsub_feature_range => try cangjie.testing.test_font.buildScriptFeatureGsubTtf(allocator),
        .gpos_pair => try cangjie.testing.test_font.buildMinimalGposTtf(allocator),
        .gpos_mark_to_ligature => try cangjie.testing.test_font
            .buildGsubGposMarkToLigatureComponentsTtf(allocator),
        .gpos_context => try cangjie.testing.test_font.buildMinimalGposChainingTtf(allocator),
        .gpos_cursive => try cangjie.testing.test_font.buildMinimalGposCursiveTtf(allocator),
        .gsub_gpos_aat => try cangjie.testing.test_font
            .buildKerxGsubGposTtf(allocator, "kern"),
    };
}

fn fuzzOpenTypeShapingTables(_: void, smith: *std.testing.Smith) !void {
    const allocator = std.testing.allocator;
    const seed = try buildOpenTypeShapingSeed(
        allocator,
        smith.value(OpenTypeShapingKind),
    );
    defer allocator.free(seed);
    try mutateAndExercise(allocator, seed, smith);
}

fn mutateAndExercise(
    allocator: std.mem.Allocator,
    seed: []u8,
    smith: *std.testing.Smith,
) !void {
    const mutation_count = smith.valueRangeAtMost(u8, 0, 32);
    for (0..mutation_count) |_| {
        seed[smith.index(seed.len)] = smith.value(u8);
    }
    const truncate = smith.boolWeighted(8, 1);
    const input_len = if (truncate) smith.index(seed.len + 1) else seed.len;
    try driver.exerciseCase(allocator, seed[0..input_len]);
}

test "driver propagates allocation failures through shaping" {
    const bytes = try cangjie.testing.test_font.buildScriptFeatureGsubTtf(
        std.testing.allocator,
    );
    defer std.testing.allocator.free(bytes);

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        driver.exerciseCase,
        .{bytes},
    );
}
