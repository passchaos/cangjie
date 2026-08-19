//! End-to-end paragraph construction benchmark comparable to Parley's
//! `RangedBuilder::build + break_all_lines + align` default benchmark.

const std = @import("std");
const cangjie = @import("cangjie");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const font_path = args.next() orelse return usage();
    const text_path = args.next() orelse return usage();
    const iterations = try parsePositive(args.next() orelse return usage());
    const sample_count = try parsePositive(args.next() orelse return usage());
    const width = if (args.next()) |value| try parseFinitePositiveFloat(value) else 200.0;
    const phase = if (args.next()) |value| try parsePhase(value) else Phase.layout;
    if (args.next() != null) return usage();

    const font_bytes: []u8 = if (std.mem.eql(u8, font_path, "builtin:minimal"))
        try cangjie.testing.test_font.buildMinimalTtf(allocator)
    else
        try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            font_path,
            allocator,
            .limited(256 * 1024 * 1024),
        );
    defer allocator.free(font_bytes);
    var face = try cangjie.font.Face.parse(allocator, font_bytes);
    defer face.deinit();

    const text_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        text_path,
        allocator,
        .limited(64 * 1024 * 1024),
    );
    defer allocator.free(text_bytes);
    const text = firstLine(text_bytes);
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    const faces = [_]*const cangjie.font.Face{&face};
    const cascade = cangjie.font.Cascade.init(&faces);
    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    var retained = if (phase == .reflow)
        try engine.prepareParagraph(cascade, .{
            .text = text,
            .font_size = 16,
            .options = .{ .max_width = width },
        })
    else
        null;
    defer if (retained) |*paragraph| paragraph.deinit();
    var reflow = cangjie.paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const samples = try allocator.alloc(i128, sample_count);
    defer allocator.free(samples);
    var checksum: u64 = 0;
    var glyph_count: usize = 0;
    var line_count: usize = 0;
    for (samples) |*sample| {
        for (0..3) |_| {
            const layout = try benchmarkOnce(
                phase,
                &engine,
                cascade,
                text,
                width,
                if (retained) |*paragraph| paragraph else null,
                &reflow,
            );
            const current_checksum = layoutChecksum(layout);
            if (checksum != 0 and checksum != current_checksum) return error.UnstableOutput;
            checksum = current_checksum;
            glyph_count = layout.glyphs.len;
            line_count = layout.lines.len;
        }
        var batch_checksum: u64 = 0;
        const start = std.Io.Clock.now(.awake, init.io).nanoseconds;
        for (0..iterations) |_| {
            const layout = try benchmarkOnce(
                phase,
                &engine,
                cascade,
                text,
                width,
                if (retained) |*paragraph| paragraph else null,
                &reflow,
            );
            if (layout.glyphs.len != glyph_count or layout.lines.len != line_count) {
                return error.UnstableOutput;
            }
            const current_checksum = layoutChecksum(layout);
            if (current_checksum != checksum) return error.UnstableOutput;
            batch_checksum = mix(batch_checksum, current_checksum);
        }
        sample.* = std.Io.Clock.now(.awake, init.io).nanoseconds - start;
        std.mem.doNotOptimizeAway(batch_checksum);
    }
    std.mem.sort(i128, samples, {}, std.sort.asc(i128));
    const median = @as(f64, @floatFromInt(samples[samples.len / 2])) /
        @as(f64, @floatFromInt(iterations));
    std.debug.print(
        "engine=cangjie\tphase={s}\ttext_bytes={d}\twidth={d:.3}\titerations={d}\tsamples={d}\t" ++
            "median_ns_per_iter={d:.3}\tglyphs={d}\tlines={d}\tchecksum={x:0>16}\n",
        .{ @tagName(phase), text.len, width, iterations, sample_count, median, glyph_count, line_count, checksum },
    );
}

const Phase = enum { layout, reflow };

fn benchmarkOnce(
    phase: Phase,
    engine: *cangjie.shaping.Engine,
    cascade: cangjie.font.Cascade,
    text: []const u8,
    width: f32,
    retained: ?*const cangjie.paragraph.Shaped,
    reflow: *cangjie.paragraph.ReflowBuffer,
) !cangjie.paragraph.Layout {
    return switch (phase) {
        .layout => layoutOnce(engine, cascade, text, width),
        .reflow => retained.?.layout(reflow, .{ .max_width = width }),
    };
}

fn layoutOnce(
    engine: *cangjie.shaping.Engine,
    cascade: cangjie.font.Cascade,
    text: []const u8,
    width: f32,
) !cangjie.paragraph.Layout {
    return engine.layout(cascade, .{
        .text = text,
        .font_size = 16,
        .options = .{ .max_width = width },
    });
}

fn layoutChecksum(layout: cangjie.paragraph.Layout) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (layout.lines) |line| {
        hash = bytes(hash, std.mem.asBytes(&line.byte_start));
        hash = bytes(hash, std.mem.asBytes(&line.byte_len));
        hash = bytes(hash, std.mem.asBytes(&line.width));
    }
    for (layout.glyphs) |glyph| {
        hash = bytes(hash, std.mem.asBytes(&glyph.glyph_id));
        hash = bytes(hash, std.mem.asBytes(&glyph.cluster));
        hash = bytes(hash, std.mem.asBytes(&glyph.x_advance));
        hash = bytes(hash, std.mem.asBytes(&glyph.x_offset));
        hash = bytes(hash, std.mem.asBytes(&glyph.y_offset));
    }
    return hash;
}

fn bytes(initial: u64, value: []const u8) u64 {
    var hash = initial;
    for (value) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

fn mix(seed: u64, value: u64) u64 {
    return bytes(seed ^ 0xcbf29ce484222325, std.mem.asBytes(&value));
}

fn firstLine(text: []const u8) []const u8 {
    const end = std.mem.indexOfAny(u8, text, "\r\n") orelse text.len;
    return text[0..end];
}

fn parsePositive(value: []const u8) !usize {
    const parsed = try std.fmt.parseInt(usize, value, 10);
    if (parsed == 0) return error.InvalidArguments;
    return parsed;
}

fn parseFinitePositiveFloat(value: []const u8) !f32 {
    const parsed = try std.fmt.parseFloat(f32, value);
    if (!std.math.isFinite(parsed) or parsed <= 0) return error.InvalidArguments;
    return parsed;
}

fn parsePhase(value: []const u8) !Phase {
    if (std.mem.eql(u8, value, "layout")) return .layout;
    if (std.mem.eql(u8, value, "reflow")) return .reflow;
    return error.InvalidArguments;
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        "usage: paragraph-bench FONT TEXT ITERATIONS SAMPLES [WIDTH] [layout|reflow]\n",
        .{},
    );
    return error.InvalidArguments;
}
