const std = @import("std");
const line_break = @import("line_break");

const default_iterations = 10_000;

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();

    _ = args.next();
    var iterations: usize = default_iterations;
    var text_path: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--iterations")) {
            const value = args.next() orelse return usage();
            iterations = std.fmt.parseInt(usize, value, 10) catch return usage();
            if (iterations == 0) return usage();
        } else if (std.mem.eql(u8, arg, "--text-file")) {
            text_path = args.next() orelse return usage();
        } else {
            return usage();
        }
    }

    const owned_text = if (text_path) |path|
        try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(64 * 1024 * 1024))
    else
        null;
    defer if (owned_text) |text| allocator.free(text);
    const text = owned_text orelse
        "Hello world! 你好，世界。 مرحبا بالعالم. " ++
            "👩‍💻 keeps working; flags 🇨🇳🇺🇳 stay paired.\r\n";

    var checked_checksum: u64 = 0;
    var checked_break_count: usize = 0;
    const checked_start = std.Io.Clock.now(.awake, init.io).nanoseconds;
    for (0..iterations) |_| {
        var iterator = try line_break.breaks(text);
        while (iterator.next()) |opportunity| {
            checked_break_count += 1;
            checked_checksum = updateChecksum(checked_checksum, opportunity);
        }
    }
    const checked_elapsed = std.Io.Clock.now(.awake, init.io).nanoseconds - checked_start;

    // `&str`-based references receive validity from their type. Measure the
    // equivalent Cangjie contract separately after one ingestion-time check so
    // iterator comparisons do not accidentally benchmark different work.
    _ = try line_break.breaks(text);
    var iterator_checksum: u64 = 0;
    var iterator_break_count: usize = 0;
    const iterator_start = std.Io.Clock.now(.awake, init.io).nanoseconds;
    for (0..iterations) |_| {
        var iterator = line_break.breaksAssumeValid(text);
        while (iterator.next()) |opportunity| {
            iterator_break_count += 1;
            iterator_checksum = updateChecksum(iterator_checksum, opportunity);
        }
    }
    const iterator_elapsed = std.Io.Clock.now(.awake, init.io).nanoseconds - iterator_start;

    const total_bytes = text.len * iterations;
    const checked_ns_per_byte = if (total_bytes == 0)
        0
    else
        @as(f64, @floatFromInt(checked_elapsed)) / @as(f64, @floatFromInt(total_bytes));
    const iterator_ns_per_byte = if (total_bytes == 0)
        0
    else
        @as(f64, @floatFromInt(iterator_elapsed)) / @as(f64, @floatFromInt(total_bytes));

    std.debug.print(
        "text_bytes={d}\titerations={d}\tchecked_elapsed_ns={d}\titerator_elapsed_ns={d}\t" ++
            "checked_ns_per_byte={d:.3}\titerator_ns_per_byte={d:.3}\tbreaks={d}/{d}\tchecksums={x}/{x}\n",
        .{
            text.len,
            iterations,
            checked_elapsed,
            iterator_elapsed,
            checked_ns_per_byte,
            iterator_ns_per_byte,
            checked_break_count,
            iterator_break_count,
            checked_checksum,
            iterator_checksum,
        },
    );
}

fn updateChecksum(checksum: u64, opportunity: line_break.Break) u64 {
    var result = checksum;
    result +%= @as(u64, @intCast(opportunity.byte_offset)) *% 0x9e3779b97f4a7c15;
    result +%= @intFromEnum(opportunity.kind);
    return result;
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        "usage: zig build line-break-bench -Doptimize=ReleaseFast -- [--text-file PATH] [--iterations N]\n",
        .{},
    );
    return error.InvalidArguments;
}
