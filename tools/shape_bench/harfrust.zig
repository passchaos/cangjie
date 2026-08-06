const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("options.zig");
const runner = @import("runner.zig");

const HarfRustGlyph = struct {
    glyph_id: u16,
    cluster: u32 = 0,
    x_advance: i32 = 0,
    y_advance: i32 = 0,
    x_offset: i32 = 0,
    y_offset: i32 = 0,
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, options: options_mod.Options) !runner.BenchResult {
    if (options.font_path == null) return error.InvalidArguments;
    const inline_text_lines = [_][]const u8{options.text};
    const text_lines = if (options.text_lines.len != 0) options.text_lines else inline_text_lines[0..];
    var line_summaries = std.ArrayList(runner.BenchResult.LineSummary).empty;
    errdefer line_summaries.deinit(allocator);

    var warmup_index: usize = 0;
    while (warmup_index < options.warmup) : (warmup_index += 1) {
        for (text_lines) |text| {
            const output = try shapeLine(io, allocator, options, text);
            allocator.free(output);
        }
    }

    var checksum: u64 = 0;
    var glyph_count: usize = 0;
    var samples = std.ArrayList(runner.BenchResult.Sample).empty;
    errdefer samples.deinit(allocator);
    var sample_index: usize = 0;
    while (sample_index < options.samples) : (sample_index += 1) {
        var sample_checksum: u64 = 0;
        var sample_glyph_count: usize = 0;
        const sample_start = std.Io.Clock.now(.awake, io).nanoseconds;
        var i: usize = 0;
        while (i < options.iterations) : (i += 1) {
            for (text_lines, 0..) |text, line_index| {
                const output = try shapeLine(io, allocator, options, text);
                defer allocator.free(output);
                const glyphs = try parseGlyphs(allocator, output);
                defer allocator.free(glyphs);
                sample_glyph_count += glyphs.len;
                const line_checksum = glyphsChecksum(glyphs);
                sample_checksum = updateChecksumWithLine(sample_checksum, line_checksum);
                if (options.line_summary and sample_index == 0 and i == 0) {
                    try line_summaries.append(allocator, .{
                        .index = line_index,
                        .text_bytes = text.len,
                        .glyph_count = glyphs.len,
                        .checksum = line_checksum,
                        .glyph_ids = if (options.glyph_summary) try glyphIds(allocator, glyphs) else &.{},
                    });
                }
            }
        }
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

fn shapeLine(io: std.Io, allocator: std.mem.Allocator, options: options_mod.Options, text: []const u8) ![]u8 {
    var size_buf: [32]u8 = undefined;
    const size_text = try std.fmt.bufPrint(&size_buf, "{d}", .{options.size});
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
        "--text",
        text,
        "--single-par",
        "--font-ptem",
        size_text,
        "--direction",
        direction_text,
        "--no-glyph-names",
    });
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
        .exited => |code| if (code != 0) return error.HarfRustFailed,
        else => return error.HarfRustFailed,
    }
    return result.stdout;
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
        .glyph_id = try std.fmt.parseInt(u16, item[0..equals], 10),
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

fn glyphIds(allocator: std.mem.Allocator, glyphs: []const HarfRustGlyph) ![]const u16 {
    const ids = try allocator.alloc(u16, glyphs.len);
    for (glyphs, ids) |glyph, *id| id.* = glyph.glyph_id;
    return ids;
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
