const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("options.zig");
const runner = @import("runner.zig");

const HarfRustGlyph = struct {
    glyph_id: u32,
    cluster: u32 = 0,
    x_advance: i32 = 0,
    y_advance: i32 = 0,
    x_offset: i32 = 0,
    y_offset: i32 = 0,
};

const ParsedLine = struct {
    text_bytes: usize,
    glyphs: []HarfRustGlyph,
    checksum: u64,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, options: options_mod.Options) !runner.BenchResult {
    if (options.font_path == null) return error.InvalidArguments;
    const inline_text_lines = [_][]const u8{options.text};
    const text_lines = if (options.text_lines.len != 0) options.text_lines else inline_text_lines[0..];
    var line_summaries = std.ArrayList(runner.BenchResult.LineSummary).empty;
    errdefer line_summaries.deinit(allocator);

    if (options.warmup != 0) {
        const output = try shapeBatch(io, allocator, options, options.warmup);
        allocator.free(output);
    }

    var checksum: u64 = 0;
    var glyph_count: usize = 0;
    var samples = std.ArrayList(runner.BenchResult.Sample).empty;
    errdefer samples.deinit(allocator);
    var sample_index: usize = 0;
    while (sample_index < options.samples) : (sample_index += 1) {
        var sample_checksum: u64 = 0;
        const sample_start = std.Io.Clock.now(.awake, io).nanoseconds;
        const output = try shapeBatch(io, allocator, options, options.iterations);
        defer allocator.free(output);
        const parsed_lines = try parseGlyphLines(allocator, output, text_lines);
        defer freeParsedLines(allocator, parsed_lines);

        var glyphs_per_iteration: usize = 0;
        for (parsed_lines) |line| glyphs_per_iteration += line.glyphs.len;
        var i: usize = 0;
        while (i < options.iterations) : (i += 1) {
            for (parsed_lines, 0..) |line, line_index| {
                sample_checksum = updateChecksumWithLine(sample_checksum, line.checksum);
                if (options.line_summary and sample_index == 0 and i == 0) {
                    try line_summaries.append(allocator, .{
                        .index = line_index,
                        .text_bytes = line.text_bytes,
                        .glyph_count = line.glyphs.len,
                        .checksum = line.checksum,
                        .glyph_ids = if (options.glyph_summary) try glyphIds(allocator, line.glyphs) else &.{},
                        .clusters = if (options.glyph_summary) try glyphClusters(allocator, line.glyphs) else &.{},
                        .x_advances = if (options.glyph_summary) try glyphXAdvances(allocator, line.glyphs) else &.{},
                        .y_advances = if (options.glyph_summary) try glyphYAdvances(allocator, line.glyphs) else &.{},
                        .x_offsets = if (options.glyph_summary) try glyphXOffsets(allocator, line.glyphs) else &.{},
                        .y_offsets = if (options.glyph_summary) try glyphYOffsets(allocator, line.glyphs) else &.{},
                    });
                }
            }
        }
        const sample_glyph_count = glyphs_per_iteration * options.iterations;
        const sample_elapsed = std.Io.Clock.now(.awake, io).nanoseconds - sample_start;
        try samples.append(allocator, .{
            .index = sample_index,
            .elapsed_ns = sample_elapsed,
            .glyph_count = sample_glyph_count,
            .checksum = sample_checksum,
        });
        glyph_count += sample_glyph_count;
        checksum = updateChecksumWithLine(checksum, sample_checksum);
    }

    var elapsed: i128 = 0;
    for (samples.items) |sample| elapsed += sample.elapsed_ns;
    return .{
        .elapsed_ns = elapsed,
        .glyph_count = glyph_count,
        .checksum = checksum,
        .profile = cangjie.ShapeStageProfile{},
        .line_summaries = try line_summaries.toOwnedSlice(allocator),
        .samples = try samples.toOwnedSlice(allocator),
    };
}

fn shapeBatch(io: std.Io, allocator: std.mem.Allocator, options: options_mod.Options, iterations: usize) ![]u8 {
    var size_buf: [32]u8 = undefined;
    const size_text = try std.fmt.bufPrint(&size_buf, "{d}", .{options.size});
    var iterations_buf: [32]u8 = undefined;
    const iterations_text = try std.fmt.bufPrint(&iterations_buf, "{d}", .{iterations});
    const direction_text = switch (options.direction) {
        .ltr => "ltr",
        .rtl => "rtl",
    };
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{
        options.harfrust_bin,
        "--font-file",
        options.font_path.?,
        "--font-ptem",
        size_text,
        "--direction",
        direction_text,
        "--no-glyph-names",
        "--utf8-clusters",
        "-n",
        iterations_text,
    });
    if (options.language_tag) |language_tag| {
        if (options_mod.harfrustLanguageArgument(language_tag)) |language_text| {
            try args.appendSlice(allocator, &.{ "--language", language_text });
        }
    }
    var not_found_glyph_buf: [32]u8 = undefined;
    if (options.not_found_variation_selector_glyph) |glyph_id| {
        const glyph_text = try std.fmt.bufPrint(&not_found_glyph_buf, "{d}", .{glyph_id});
        try args.append(allocator, "--not-found-variation-selector-glyph");
        try args.append(allocator, glyph_text);
    }
    if (options.text_path) |path| {
        try args.appendSlice(allocator, &.{ "--text-file", path });
    } else {
        try args.appendSlice(allocator, &.{ "--text", options.text });
        if (options.text_lines.len <= 1) try args.append(allocator, "--single-par");
    }
    for (options.featureOverrides()) |feature| {
        var tag_buf: [4]u8 = undefined;
        options_mod.writeFeatureTag(&tag_buf, feature.tag);
        const value: u8 = if (feature.enabled) '1' else '0';
        const feature_text = try std.fmt.allocPrint(allocator, "{s}={c}", .{ tag_buf[0..], value });
        defer allocator.free(feature_text);
        try args.append(allocator, "--features");
        try args.append(allocator, feature_text);
    }

    const result = std.process.run(allocator, io, .{
        .argv = args.items,
        .stdout_limit = .limited(64 * 1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| switch (err) {
        error.FileNotFound => return error.HarfRustNotFound,
        else => return err,
    };
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return error.HarfRustFailed;
        },
        else => {
            allocator.free(result.stdout);
            return error.HarfRustFailed;
        },
    }
    return result.stdout;
}

fn parseGlyphLines(allocator: std.mem.Allocator, output: []const u8, text_lines: []const []const u8) ![]ParsedLine {
    var parsed = std.ArrayList(ParsedLine).empty;
    errdefer {
        for (parsed.items) |line| allocator.free(line.glyphs);
        parsed.deinit(allocator);
    }
    var line_it = std.mem.splitScalar(u8, output, '\n');
    while (line_it.next()) |raw_line| {
        const line_output = std.mem.trim(u8, raw_line, "\r");
        if (line_output.len == 0) continue;
        const line_index = parsed.items.len;
        const glyphs = try parseGlyphs(allocator, line_output);
        errdefer allocator.free(glyphs);
        try parsed.append(allocator, .{
            .text_bytes = if (line_index < text_lines.len) text_lines[line_index].len else 0,
            .glyphs = glyphs,
            .checksum = glyphsChecksum(glyphs),
        });
    }
    if (text_lines.len != 0 and parsed.items.len != text_lines.len) return error.BadHarfRustOutput;
    return try parsed.toOwnedSlice(allocator);
}

fn freeParsedLines(allocator: std.mem.Allocator, lines: []ParsedLine) void {
    for (lines) |line| allocator.free(line.glyphs);
    allocator.free(lines);
}

fn parseGlyphs(allocator: std.mem.Allocator, output: []const u8) ![]HarfRustGlyph {
    var glyphs = std.ArrayList(HarfRustGlyph).empty;
    errdefer glyphs.deinit(allocator);
    var pos: usize = 0;
    while (pos < output.len) {
        const start_rel = std.mem.indexOfScalarPos(u8, output, pos, '[') orelse break;
        const end = std.mem.indexOfScalarPos(u8, output, start_rel + 1, ']') orelse return error.BadHarfRustOutput;
        var items = std.mem.splitScalar(u8, output[start_rel + 1 .. end], '|');
        while (items.next()) |item| {
            if (item.len == 0) continue;
            try glyphs.append(allocator, try parseGlyph(item));
        }
        pos = end + 1;
    }
    return try glyphs.toOwnedSlice(allocator);
}

fn parseGlyph(item: []const u8) !HarfRustGlyph {
    const equals = std.mem.indexOfScalar(u8, item, '=') orelse return error.BadHarfRustOutput;
    const at = std.mem.indexOfScalarPos(u8, item, equals + 1, '@');
    const plus = std.mem.indexOfScalarPos(u8, item, equals + 1, '+');
    const id_end = at orelse plus orelse item.len;
    var glyph = HarfRustGlyph{
        .glyph_id = try std.fmt.parseInt(u32, item[0..equals], 10),
        .cluster = try std.fmt.parseInt(u32, item[equals + 1 .. id_end], 10),
    };
    if (at) |at_index| {
        const offset_end = plus orelse item.len;
        try parsePairI32(item[at_index + 1 .. offset_end], &glyph.x_offset, &glyph.y_offset);
    }
    if (plus) |plus_index| {
        try parsePairI32(item[plus_index + 1 ..], &glyph.x_advance, &glyph.y_advance);
    }
    return glyph;
}

fn parsePairI32(text: []const u8, first: *i32, second: *i32) !void {
    if (std.mem.indexOfScalar(u8, text, ',')) |comma| {
        first.* = try std.fmt.parseInt(i32, text[0..comma], 10);
        second.* = try std.fmt.parseInt(i32, text[comma + 1 ..], 10);
        return;
    }
    first.* = try std.fmt.parseInt(i32, text, 10);
    second.* = 0;
}

fn glyphIds(allocator: std.mem.Allocator, glyphs: []const HarfRustGlyph) ![]const u32 {
    const ids = try allocator.alloc(u32, glyphs.len);
    for (glyphs, ids) |glyph, *id| id.* = glyph.glyph_id;
    return ids;
}

fn glyphClusters(allocator: std.mem.Allocator, glyphs: []const HarfRustGlyph) ![]const u32 {
    const clusters = try allocator.alloc(u32, glyphs.len);
    for (glyphs, clusters) |glyph, *cluster| cluster.* = glyph.cluster;
    return clusters;
}

fn glyphXAdvances(allocator: std.mem.Allocator, glyphs: []const HarfRustGlyph) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| value.* = glyph.x_advance;
    return values;
}

fn glyphYAdvances(allocator: std.mem.Allocator, glyphs: []const HarfRustGlyph) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| value.* = glyph.y_advance;
    return values;
}

fn glyphXOffsets(allocator: std.mem.Allocator, glyphs: []const HarfRustGlyph) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| value.* = glyph.x_offset;
    return values;
}

fn glyphYOffsets(allocator: std.mem.Allocator, glyphs: []const HarfRustGlyph) ![]const i32 {
    const values = try allocator.alloc(i32, glyphs.len);
    for (glyphs, values) |glyph, *value| value.* = glyph.y_offset;
    return values;
}

fn glyphsChecksum(glyphs: []const HarfRustGlyph) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (glyphs) |glyph| {
        hasher.update(std.mem.asBytes(&glyph.glyph_id));
        hasher.update(std.mem.asBytes(&glyph.cluster));
        hasher.update(std.mem.asBytes(&glyph.x_advance));
        hasher.update(std.mem.asBytes(&glyph.y_advance));
        hasher.update(std.mem.asBytes(&glyph.x_offset));
        hasher.update(std.mem.asBytes(&glyph.y_offset));
    }
    return hasher.final();
}

fn updateChecksumWithLine(seed: u64, line_checksum: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    hasher.update(std.mem.asBytes(&line_checksum));
    return hasher.final();
}
