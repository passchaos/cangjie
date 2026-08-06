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
        for (result.line_summaries) |summary| allocator.free(summary.glyph_ids);
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

    var font = try cangjie.Font.parse(allocator, font_bytes);
    defer font.deinit();
    const cangjie_result = try runner.runCangjie(io, allocator, &font, options);
    defer freeResult(allocator, cangjie_result);

    var harfrust_options = options;
    harfrust_options.engine = .harfrust;
    const harfrust_result = try harfrust.run(io, allocator, harfrust_options);
    defer freeResult(allocator, harfrust_result);

    const mismatch = firstGlyphIdMismatch(cangjie_result.line_summaries, harfrust_result.line_summaries);
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
            \\cangjie_glyph_ids=
        , .{
            m.line_index,
            m.line_index + 1,
            mismatch_text,
            m.cangjie.glyph_count,
            m.harfrust.glyph_count,
            m.cangjie.checksum,
            m.harfrust.checksum,
        });
        printGlyphIds(m.cangjie.glyph_ids);
        std.debug.print("\nharfrust_glyph_ids=", .{});
        printGlyphIds(m.harfrust.glyph_ids);
        std.debug.print("\n", .{});
        return error.HarfRustParityMismatch;
    }
    std.debug.print(
        \\parity=pass
        \\checksum={x}
        \\
    , .{cangjie_result.checksum});
}

const GlyphIdMismatch = struct {
    line_index: usize,
    cangjie: runner.BenchResult.LineSummary,
    harfrust: runner.BenchResult.LineSummary,
};

fn firstGlyphIdMismatch(cangjie_lines: []const runner.BenchResult.LineSummary, harfrust_lines: []const runner.BenchResult.LineSummary) ?GlyphIdMismatch {
    const count = @min(cangjie_lines.len, harfrust_lines.len);
    for (0..count) |line_index| {
        if (!std.mem.eql(u16, cangjie_lines[line_index].glyph_ids, harfrust_lines[line_index].glyph_ids)) {
            return .{
                .line_index = line_index,
                .cangjie = cangjie_lines[line_index],
                .harfrust = harfrust_lines[line_index],
            };
        }
    }
    if (cangjie_lines.len != harfrust_lines.len) {
        const line_index = count;
        return .{
            .line_index = line_index,
            .cangjie = if (line_index < cangjie_lines.len) cangjie_lines[line_index] else .{ .index = line_index, .text_bytes = 0, .glyph_count = 0, .checksum = 0 },
            .harfrust = if (line_index < harfrust_lines.len) harfrust_lines[line_index] else .{ .index = line_index, .text_bytes = 0, .glyph_count = 0, .checksum = 0 },
        };
    }
    return null;
}

fn printGlyphIds(glyph_ids: []const u16) void {
    for (glyph_ids, 0..) |glyph_id, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{glyph_id});
    }
}

fn freeResult(allocator: std.mem.Allocator, result: runner.BenchResult) void {
    for (result.line_summaries) |summary| allocator.free(summary.glyph_ids);
    allocator.free(result.line_summaries);
    allocator.free(result.samples);
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
