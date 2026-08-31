//! Deterministic malformed-font smoke coverage for parser, shaper, and renderer entry points.

const std = @import("std");
const driver = @import("font_fuzz/driver.zig");

// Keep accidental huge inputs bounded while still admitting ordinary variable
// and color-font seeds, which routinely exceed one MiB.
const max_input_bytes = 32 << 20;
const mutations_per_seed = 256;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();

    var seed_count: usize = 0;
    var case_count: usize = 0;
    while (args.next()) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            path,
            allocator,
            .limited(max_input_bytes),
        );
        defer allocator.free(bytes);
        try exerciseSeed(allocator, bytes, &case_count);
        seed_count += 1;
    }
    if (seed_count == 0) return error.InvalidArguments;

    std.debug.print(
        "font_fuzz_smoke seeds={d} cases={d} status=pass\n",
        .{ seed_count, case_count },
    );
}

fn exerciseSeed(
    allocator: std.mem.Allocator,
    seed: []const u8,
    case_count: *usize,
) !void {
    // Exercise every prefix around table-directory and fixed-header
    // boundaries. Parsers must fail transactionally rather than reading past
    // the caller-owned byte range.
    const prefix_limit = @min(seed.len, 256);
    for (0..prefix_limit + 1) |len| {
        try driver.exerciseCase(allocator, seed[0..len]);
        case_count.* += 1;
    }

    if (seed.len == 0) return;
    // The prefix loop already includes short seeds. Keep one unmodified full
    // case for larger fonts so that deeper APIs are exercised even when every
    // checksum-breaking mutation is rejected during parsing.
    if (seed.len > prefix_limit) {
        try driver.exerciseCase(allocator, seed);
        case_count.* += 1;
    }

    const mutable = try allocator.dupe(u8, seed);
    defer allocator.free(mutable);
    var state: u64 = 0x9e3779b97f4a7c15 ^ @as(u64, seed.len);
    for (0..mutations_per_seed) |_| {
        state = state *% 6364136223846793005 +% 1442695040888963407;
        const index: usize = @intCast(state % mutable.len);
        const original = mutable[index];
        // A deterministic mix of bit flips and arbitrary replacement bytes
        // reaches both small flag fields and large offset/count words.
        const shift: u3 = @truncate(state >> 32);
        if ((state & 1) == 0) {
            mutable[index] = original ^ (@as(u8, 1) << shift);
        } else {
            const replacement: u8 = @truncate(state >> 40);
            mutable[index] = if (replacement == original) replacement +% 1 else replacement;
        }
        try driver.exerciseCase(allocator, mutable);
        mutable[index] = original;
        case_count.* += 1;
    }
}
