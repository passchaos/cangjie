const std = @import("std");
const cangjie = @import("cangjie");

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

    var checksum: u64 = 0;
    var break_count: usize = 0;
    const start = std.Io.Clock.now(.awake, init.io).nanoseconds;
    for (0..iterations) |_| {
        var iterator = try cangjie.lineBreaks(text);
        while (iterator.next()) |opportunity| {
            break_count += 1;
            checksum +%= @as(u64, @intCast(opportunity.byte_offset)) *% 0x9e3779b97f4a7c15;
            checksum +%= @intFromEnum(opportunity.kind);
        }
    }
    const elapsed = std.Io.Clock.now(.awake, init.io).nanoseconds - start;
    const total_bytes = text.len * iterations;
    const ns_per_byte = if (total_bytes == 0)
        0
    else
        @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(total_bytes));

    std.debug.print(
        "text_bytes={d}\titerations={d}\telapsed_ns={d}\tns_per_byte={d:.3}\tbreaks={d}\tchecksum={x}\n",
        .{ text.len, iterations, elapsed, ns_per_byte, break_count, checksum },
    );
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        "usage: zig build line-break-bench -Doptimize=ReleaseFast -- [--text-file PATH] [--iterations N]\n",
        .{},
    );
    return error.InvalidArguments;
}
