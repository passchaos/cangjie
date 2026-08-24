//! Coverage-guided malformed-font fuzz entry point for Zig's built-in fuzzer.

const std = @import("std");
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

test "coverage-guided malformed font parsing and rendering" {
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
