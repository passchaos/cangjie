const std = @import("std");
const cangjie = @import("cangjie");

const coretext = @import("shape_bench/coretext.zig");
const harfrust = @import("shape_bench/harfrust.zig");
const options_mod = @import("shape_bench/options.zig");
const report = @import("shape_bench/report.zig");
const runner = @import("shape_bench/runner.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;

    var args_iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iterator.deinit();

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    while (args_iterator.next()) |arg| {
        try args.append(allocator, arg);
    }

    var options = options_mod.parse(args.items) catch |err| switch (err) {
        error.InvalidArguments => {
            options_mod.printUsage(args.items);
            return;
        },
        else => {
            options_mod.printUsage(args.items);
            return err;
        },
    };
    const text_bytes = if (options.text_path) |path|
        try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(64 * 1024 * 1024))
    else
        null;
    defer if (text_bytes) |bytes| allocator.free(bytes);
    if (text_bytes) |bytes| options.text = bytes;
    const text_lines = try splitTextLines(allocator, options.text);
    defer allocator.free(text_lines);
    options.text_lines = text_lines;

    const font_bytes = try runner.loadFontBytes(init.io, allocator, options);
    defer allocator.free(font_bytes);

    if (options.engine == .compare_harfrust) {
        try runHarfRustComparison(init.io, allocator, font_bytes, options);
        return;
    }

    const result = switch (options.engine) {
        .cangjie => result: {
            var font = try cangjie.Font.parse(allocator, font_bytes);
            defer font.deinit();
            break :result try runner.runCangjie(init.io, allocator, &font, options);
        },
        .coretext => try coretext.run(init.io, allocator, font_bytes, options),
        .harfrust => try harfrust.run(init.io, allocator, options),
        .compare_harfrust => unreachable,
    };
    defer {
        freeLineSummaries(allocator, result.line_summaries);
        allocator.free(result.line_summaries);
        allocator.free(result.samples);
    }
    report.print(options, result);
}

fn runHarfRustComparison(io: std.Io, allocator: std.mem.Allocator, font_bytes: []const u8, base_options: options_mod.Options) !void {
    var options = base_options;
    options.engine = .cangjie;
    options.iterations = 1;
    options.warmup = 0;
    options.samples = 1;
    options.line_summary = true;
    options.glyph_summary = true;
    options.reorder_bidi = false;
    options.language_tag = base_options.language_tag orelse .dflt;

    var font = try cangjie.Font.parse(allocator, font_bytes);
    defer font.deinit();
    const cangjie_result = try runner.runCangjie(io, allocator, &font, options);
    defer freeResult(allocator, cangjie_result);

    var harfrust_options = options;
    harfrust_options.engine = .harfrust;
    const harfrust_result = try harfrust.run(io, allocator, harfrust_options);
    defer freeResult(allocator, harfrust_result);

    const mismatch = try firstLineMismatch(allocator, cangjie_result.line_summaries, harfrust_result.line_summaries, base_options.direction);
    std.debug.print(
        \\engine=compare-harfrust
        \\font={s}
        \\text={s}
        \\lines={d}
        \\cangjie_glyphs={d}
        \\harfrust_glyphs={d}
        \\
    , .{
        base_options.fontLabel(),
        base_options.textLabel(),
        cangjie_result.line_summaries.len,
        cangjie_result.glyph_count,
        harfrust_result.glyph_count,
    });
    if (mismatch) |m| {
        defer allocator.free(m.cangjie_glyph_ids);
        defer allocator.free(m.cangjie_clusters);
        const mismatch_text = if (m.line_index < base_options.text_lines.len) base_options.text_lines[m.line_index] else "";
        std.debug.print(
            \\parity=fail
            \\mismatch_index={d}
            \\mismatch_line={d}
            \\mismatch_text={s}
            \\cangjie_line_glyphs={d}
            \\harfrust_line_glyphs={d}
            \\cangjie_line_checksum={x}
            \\harfrust_line_checksum={x}
            \\mismatch_kind={s}
            \\cangjie_glyph_ids=
        , .{
            m.line_index,
            m.line_index + 1,
            mismatch_text,
            m.cangjie.glyph_count,
            m.harfrust.glyph_count,
            m.cangjie.checksum,
            m.harfrust.checksum,
            m.kind.label(),
        });
        printGlyphIds(m.cangjie_glyph_ids);
        std.debug.print("\nharfrust_glyph_ids=", .{});
        printGlyphIds(m.harfrust.glyph_ids);
        if (m.kind == .cluster) {
            std.debug.print("\ncangjie_clusters=", .{});
            printClusters(m.cangjie_clusters);
            std.debug.print("\nharfrust_clusters=", .{});
            printClusters(m.harfrust.clusters);
        }
        std.debug.print("\n", .{});
        return error.HarfRustParityMismatch;
    }
    std.debug.print(
        \\parity=pass
        \\checksum={x}
        \\
    , .{cangjie_result.checksum});
}

const MismatchKind = enum {
    glyph_id,
    cluster,
    line_count,

    fn label(self: MismatchKind) []const u8 {
        return switch (self) {
            .glyph_id => "glyph_id",
            .cluster => "cluster",
            .line_count => "line_count",
        };
    }
};

const LineMismatch = struct {
    kind: MismatchKind,
    line_index: usize,
    cangjie: runner.BenchResult.LineSummary,
    harfrust: runner.BenchResult.LineSummary,
    cangjie_glyph_ids: []const u16,
    cangjie_clusters: []const u32,
};

fn firstLineMismatch(allocator: std.mem.Allocator, cangjie_lines: []const runner.BenchResult.LineSummary, harfrust_lines: []const runner.BenchResult.LineSummary, direction: cangjie.TextDirection) !?LineMismatch {
    const count = @min(cangjie_lines.len, harfrust_lines.len);
    for (0..count) |line_index| {
        const cangjie_ids = try comparableSlice(u16, allocator, cangjie_lines[line_index].glyph_ids, direction);
        errdefer allocator.free(cangjie_ids);
        if (!std.mem.eql(u16, cangjie_ids, harfrust_lines[line_index].glyph_ids)) {
            return .{
                .kind = .glyph_id,
                .line_index = line_index,
                .cangjie = cangjie_lines[line_index],
                .harfrust = harfrust_lines[line_index],
                .cangjie_glyph_ids = cangjie_ids,
                .cangjie_clusters = try comparableSlice(u32, allocator, cangjie_lines[line_index].clusters, direction),
            };
        }
        const cangjie_clusters = try comparableSlice(u32, allocator, cangjie_lines[line_index].clusters, direction);
        errdefer allocator.free(cangjie_clusters);
        if (!std.mem.eql(u32, cangjie_clusters, harfrust_lines[line_index].clusters)) {
            return .{
                .kind = .cluster,
                .line_index = line_index,
                .cangjie = cangjie_lines[line_index],
                .harfrust = harfrust_lines[line_index],
                .cangjie_glyph_ids = cangjie_ids,
                .cangjie_clusters = cangjie_clusters,
            };
        }
        allocator.free(cangjie_ids);
        allocator.free(cangjie_clusters);
    }
    if (cangjie_lines.len != harfrust_lines.len) {
        const line_index = count;
        const cangjie_ids = if (line_index < cangjie_lines.len)
            try comparableSlice(u16, allocator, cangjie_lines[line_index].glyph_ids, direction)
        else
            try allocator.alloc(u16, 0);
        errdefer allocator.free(cangjie_ids);
        const cangjie_clusters = if (line_index < cangjie_lines.len)
            try comparableSlice(u32, allocator, cangjie_lines[line_index].clusters, direction)
        else
            try allocator.alloc(u32, 0);
        return .{
            .kind = .line_count,
            .line_index = line_index,
            .cangjie = if (line_index < cangjie_lines.len) cangjie_lines[line_index] else emptyLineSummary(line_index),
            .harfrust = if (line_index < harfrust_lines.len) harfrust_lines[line_index] else emptyLineSummary(line_index),
            .cangjie_glyph_ids = cangjie_ids,
            .cangjie_clusters = cangjie_clusters,
        };
    }
    return null;
}

fn emptyLineSummary(line_index: usize) runner.BenchResult.LineSummary {
    return .{ .index = line_index, .text_bytes = 0, .glyph_count = 0, .checksum = 0 };
}

fn comparableSlice(comptime T: type, allocator: std.mem.Allocator, items: []const T, direction: cangjie.TextDirection) ![]const T {
    const comparable = try allocator.alloc(T, items.len);
    switch (direction) {
        .ltr => @memcpy(comparable, items),
        .rtl => {
            for (items, 0..) |item, index| {
                comparable[items.len - 1 - index] = item;
            }
        },
    }
    return comparable;
}

fn printGlyphIds(glyph_ids: []const u16) void {
    for (glyph_ids, 0..) |glyph_id, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{glyph_id});
    }
}

fn printClusters(clusters: []const u32) void {
    for (clusters, 0..) |cluster, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{cluster});
    }
}

fn freeResult(allocator: std.mem.Allocator, result: runner.BenchResult) void {
    freeLineSummaries(allocator, result.line_summaries);
    allocator.free(result.line_summaries);
    allocator.free(result.samples);
}

fn freeLineSummaries(allocator: std.mem.Allocator, summaries: []const runner.BenchResult.LineSummary) void {
    for (summaries) |summary| {
        allocator.free(summary.glyph_ids);
        allocator.free(summary.clusters);
    }
}

fn splitTextLines(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var lines = std.ArrayList([]const u8).empty;
    errdefer lines.deinit(allocator);

    var it = std.mem.splitScalar(u8, std.mem.trim(u8, text, "\n\r"), '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        if (line.len == 0) continue;
        try lines.append(allocator, line);
    }
    if (lines.items.len == 0 and text.len != 0) {
        try lines.append(allocator, text);
    }
    return try lines.toOwnedSlice(allocator);
}
