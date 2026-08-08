const std = @import("std");
const cangjie = @import("cangjie");

const default_iterations = 10_000;
const default_text = "A A A A A A A A A A A A A A A A A A A A";
const widths = [_]f32{ 80, 120, 160, 200 };

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();

    _ = args.next();
    var iterations: usize = default_iterations;
    while (args.next()) |arg| {
        if (!std.mem.eql(u8, arg, "--iterations")) return usage();
        const value = args.next() orelse return usage();
        iterations = std.fmt.parseInt(usize, value, 10) catch return usage();
        if (iterations == 0) return usage();
    }

    const font_bytes = try cangjie.testing.test_font.buildMinimalTtf(allocator);
    defer allocator.free(font_bytes);
    var font = try cangjie.Font.parse(allocator, font_bytes);
    defer font.deinit();
    const fonts = [_]*const cangjie.Font{&font};
    const cascade = cangjie.FontCascade.init(&fonts);
    var shape_buffer = cangjie.LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped_cache = cangjie.ShapedRunCache.init(allocator);
    defer shaped_cache.deinit();

    // Warm the shaping and layout allocation paths before measuring either
    // strategy so compile/startup and first-capacity costs do not decide the
    // comparison.
    _ = try cangjie.TextShaper.layoutParagraphUtf8(
        cascade,
        &shape_buffer,
        default_text,
        20,
        .{ .max_width = widths[0] },
    );

    var shape_each_checksum: usize = 0;
    const shape_each_start = std.Io.Clock.now(.awake, init.io).nanoseconds;
    for (0..iterations) |iteration| {
        const layout = try cangjie.TextShaper.layoutParagraphUtf8(
            cascade,
            &shape_buffer,
            default_text,
            20,
            .{ .max_width = widths[iteration % widths.len] },
        );
        shape_each_checksum +%= layout.glyphs.len + layout.lines.len;
    }
    const shape_each_ns = std.Io.Clock.now(.awake, init.io).nanoseconds - shape_each_start;

    _ = try cangjie.TextShaper.layoutParagraphUtf8WithCaches(
        cascade,
        null,
        null,
        null,
        &shaped_cache,
        &shape_buffer,
        default_text,
        20,
        .{ .max_width = widths[0] },
    );
    var cached_layout_checksum: usize = 0;
    const cached_layout_start = std.Io.Clock.now(.awake, init.io).nanoseconds;
    for (0..iterations) |iteration| {
        const layout = try cangjie.TextShaper.layoutParagraphUtf8WithCaches(
            cascade,
            null,
            null,
            null,
            &shaped_cache,
            &shape_buffer,
            default_text,
            20,
            .{ .max_width = widths[iteration % widths.len] },
        );
        cached_layout_checksum +%= layout.glyphs.len + layout.lines.len;
    }
    const cached_layout_ns = std.Io.Clock.now(.awake, init.io).nanoseconds - cached_layout_start;

    var paragraph = try cangjie.TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        default_text,
        20,
        .{ .max_width = widths[0] },
    );
    defer paragraph.deinit();
    var reflow = cangjie.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    _ = try paragraph.layout(&reflow, .{ .max_width = widths[0] });

    var reflow_checksum: usize = 0;
    const reflow_start = std.Io.Clock.now(.awake, init.io).nanoseconds;
    for (0..iterations) |iteration| {
        const layout = try paragraph.layout(
            &reflow,
            .{ .max_width = widths[iteration % widths.len] },
        );
        reflow_checksum +%= layout.glyphs.len + layout.lines.len;
    }
    const reflow_ns = std.Io.Clock.now(.awake, init.io).nanoseconds - reflow_start;

    const speedup_vs_shape = @as(f64, @floatFromInt(shape_each_ns)) /
        @as(f64, @floatFromInt(reflow_ns));
    const speedup_vs_cached = @as(f64, @floatFromInt(cached_layout_ns)) /
        @as(f64, @floatFromInt(reflow_ns));
    std.debug.print(
        "iterations={d}\tshape_each_ns={d}\tcached_layout_ns={d}\treflow_ns={d}\t" ++
            "speedup_vs_shape={d:.3}\tspeedup_vs_cached={d:.3}\tchecksums={d}/{d}/{d}\n",
        .{
            iterations,
            shape_each_ns,
            cached_layout_ns,
            reflow_ns,
            speedup_vs_shape,
            speedup_vs_cached,
            shape_each_checksum,
            cached_layout_checksum,
            reflow_checksum,
        },
    );
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        "usage: zig build reflow-bench -Doptimize=ReleaseFast -- [--iterations N]\n",
        .{},
    );
    return error.InvalidArguments;
}
