const std = @import("std");
const options_mod = @import("options.zig");

pub const Sample = struct {
    index: usize,
    elapsed_ns: i128,
    iterations: usize,
    checksum: u64,
};

pub const Result = struct {
    elapsed_ns: i128,
    checksum: u64,
    samples: []Sample,
    dirty_pixels: usize = 0,
};

pub fn print(options: options_mod.Options, result: Result) void {
    switch (options.output_format) {
        .text => printText(options, result),
        .tsv => printTsv(options, result),
    }
}

pub fn printComparison(options: options_mod.Options, cangjie: Result, freetype: Result) void {
    const cangjie_ns = nsPerIter(options, cangjie);
    const freetype_ns = nsPerIter(options, freetype);
    const cangjie_stats = sampleStats(cangjie.samples, options.iterations);
    const freetype_stats = sampleStats(freetype.samples, options.iterations);
    const speedup = if (cangjie_ns == 0) 0 else freetype_ns / cangjie_ns;
    const median_speedup = if (cangjie_stats.median == 0) 0 else freetype_stats.median / cangjie_stats.median;
    const faster = if (cangjie_ns <= freetype_ns) "cangjie" else "freetype";
    const median_faster = if (cangjie_stats.median <= freetype_stats.median) "cangjie" else "freetype";
    switch (options.output_format) {
        .text => std.debug.print(
            \\comparison=cangjie-vs-freetype
            \\mode={s}
            \\cangjie_ns_per_iter={d:.3}
            \\freetype_ns_per_iter={d:.3}
            \\cangjie_speedup_vs_freetype={d:.3}
            \\faster={s}
            \\cangjie_median_ns_per_iter={d:.3}
            \\freetype_median_ns_per_iter={d:.3}
            \\cangjie_median_speedup_vs_freetype={d:.3}
            \\median_faster={s}
            \\
        , .{ options.mode.label(), cangjie_ns, freetype_ns, speedup, faster, cangjie_stats.median, freetype_stats.median, median_speedup, median_faster }),
        .tsv => std.debug.print(
            "comparison\tmode\tcangjie_ns_per_iter\tfreetype_ns_per_iter\tcangjie_speedup_vs_freetype\tfaster\tcangjie_median_ns_per_iter\tfreetype_median_ns_per_iter\tcangjie_median_speedup_vs_freetype\tmedian_faster\n" ++
                "cangjie-vs-freetype\t{s}\t{d:.3}\t{d:.3}\t{d:.3}\t{s}\t{d:.3}\t{d:.3}\t{d:.3}\t{s}\n",
            .{ options.mode.label(), cangjie_ns, freetype_ns, speedup, faster, cangjie_stats.median, freetype_stats.median, median_speedup, median_faster },
        ),
    }
}

fn printText(options: options_mod.Options, result: Result) void {
    const ns_per_iter = nsPerIter(options, result);
    const stats = sampleStats(result.samples, options.iterations);
    std.debug.print(
        \\mode={s}
        \\engine={s}
        \\font={s}
        \\glyph_id={any}
        \\codepoint=U+{X}
        \\font_size={d}
        \\target_size={d}
        \\samples_per_axis={d}
        \\variation_coords={d}
        \\iterations={d}
        \\warmup={d}
        \\samples={d}
        \\elapsed_ns={d}
        \\ns_per_iter={d:.3}
        \\sample_min_ns_per_iter={d:.3}
        \\sample_median_ns_per_iter={d:.3}
        \\sample_max_ns_per_iter={d:.3}
        \\checksum={x}
        \\dirty_pixels={d}
        \\
    , .{
        options.mode.label(),
        options.engine.label(),
        options.fontLabel(),
        options.glyph_id,
        options.codepoint,
        options.font_size,
        options.target_size,
        options.samples_per_axis,
        options.normalizedVariationCoords().len,
        options.iterations,
        options.warmup,
        options.samples,
        result.elapsed_ns,
        ns_per_iter,
        stats.min,
        stats.median,
        stats.max,
        result.checksum,
        result.dirty_pixels,
    });
    for (result.samples) |sample| {
        const sample_ns_per_iter = if (sample.iterations == 0) 0 else @as(f64, @floatFromInt(sample.elapsed_ns)) / @as(f64, @floatFromInt(sample.iterations));
        std.debug.print("sample index={d} elapsed_ns={d} ns_per_iter={d:.3} checksum={x}\n", .{ sample.index, sample.elapsed_ns, sample_ns_per_iter, sample.checksum });
    }
}

fn printTsv(options: options_mod.Options, result: Result) void {
    const ns_per_iter = nsPerIter(options, result);
    const stats = sampleStats(result.samples, options.iterations);
    std.debug.print(
        "mode\tengine\tfont\tglyph_id\tcodepoint\tfont_size\ttarget_size\tsamples_per_axis\tvariation_coords\titerations\twarmup\tsamples\telapsed_ns\tns_per_iter\tsample_min_ns_per_iter\tsample_median_ns_per_iter\tsample_max_ns_per_iter\tchecksum\tdirty_pixels\n" ++
            "{s}\t{s}\t{s}\t{any}\tU+{X}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d:.3}\t{d:.3}\t{d:.3}\t{d:.3}\t{x}\t{d}\n",
        .{
            options.mode.label(),
            options.engine.label(),
            options.fontLabel(),
            options.glyph_id,
            options.codepoint,
            options.font_size,
            options.target_size,
            options.samples_per_axis,
            options.normalizedVariationCoords().len,
            options.iterations,
            options.warmup,
            options.samples,
            result.elapsed_ns,
            ns_per_iter,
            stats.min,
            stats.median,
            stats.max,
            result.checksum,
            result.dirty_pixels,
        },
    );
}

const SampleStats = struct { min: f64, median: f64, max: f64 };

fn nsPerIter(options: options_mod.Options, result: Result) f64 {
    const total_iterations = options.iterations * options.samples;
    return if (total_iterations == 0) 0 else @as(f64, @floatFromInt(result.elapsed_ns)) / @as(f64, @floatFromInt(total_iterations));
}

fn sampleStats(samples: []const Sample, iterations: usize) SampleStats {
    if (samples.len == 0 or iterations == 0) return .{ .min = 0, .median = 0, .max = 0 };
    var values_buf: [64]f64 = undefined;
    const count = @min(samples.len, values_buf.len);
    for (samples[0..count], values_buf[0..count]) |sample, *value| {
        value.* = @as(f64, @floatFromInt(sample.elapsed_ns)) / @as(f64, @floatFromInt(iterations));
    }
    std.mem.sort(f64, values_buf[0..count], {}, std.sort.asc(f64));
    return .{
        .min = values_buf[0],
        .median = values_buf[count / 2],
        .max = values_buf[count - 1],
    };
}
