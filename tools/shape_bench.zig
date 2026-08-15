const std = @import("std");
const cangjie = @import("cangjie");
const build_options = @import("shape_bench_options");

const coretext = @import("shape_bench/coretext.zig");
const harfrust = @import("shape_bench/harfrust.zig");
const options_mod = @import("shape_bench/options.zig");
const report = @import("shape_bench/report.zig");
const runner = @import("shape_bench/runner.zig");
const harfbuzz = if (build_options.enable_harfbuzz) @import("shape_bench/harfbuzz.zig") else DisabledHarfBuzz;

const DisabledHarfBuzz = struct {
    pub fn run(io: std.Io, allocator: std.mem.Allocator, font_bytes: []const u8, options: options_mod.Options) !runner.BenchResult {
        _ = io;
        _ = allocator;
        _ = font_bytes;
        _ = options;
        return error.HarfBuzzUnavailable;
    }
};

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
    if (!build_options.enable_harfbuzz and (options.engine == .harfbuzz or options.engine == .compare_harfbuzz)) {
        std.debug.print(
            \\error: HarfBuzz reference engine is not enabled in this build.
            \\rebuild with -Denable-harfbuzz=true and provide HarfBuzz through pkg-config or -Dharfbuzz-prefix.
            \\
        , .{});
        return error.HarfBuzzUnavailable;
    }
    const resolved_harfrust_bin = try resolveDefaultHarfRustBin(init.io, allocator, init.environ_map, &options);
    defer if (resolved_harfrust_bin) |path| allocator.free(path);

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
    if (options.export_font_path) |path| {
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = font_bytes });
        return;
    }

    if (options.engine == .compare_coretext or options.engine == .compare_harfrust or options.engine == .compare_harfbuzz) {
        try runReferenceComparison(init.io, allocator, font_bytes, options);
        return;
    }

    const result = switch (options.engine) {
        .cangjie => result: {
            const font = try runner.parseFont(allocator, font_bytes, options);
            defer font.deinit();
            break :result try runner.runCangjie(init.io, allocator, font, options);
        },
        .coretext => try coretext.run(init.io, allocator, font_bytes, options),
        .harfrust => try harfrust.run(init.io, allocator, options),
        .harfbuzz => try harfbuzz.run(init.io, allocator, font_bytes, options),
        .compare_coretext, .compare_harfrust, .compare_harfbuzz => unreachable,
    };
    defer {
        freeLineSummaries(allocator, result.line_summaries);
        allocator.free(result.line_summaries);
        allocator.free(result.samples);
    }
    if (options.expected_checksum) |expected| {
        if (result.checksum != expected) return error.ExpectedChecksumMismatch;
    }
    try verifyExpectedSummary(allocator, options, result.line_summaries);
    report.print(options, result);
}

fn resolveDefaultHarfRustBin(io: std.Io, allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map, options: *options_mod.Options) !?[]u8 {
    if (options.engine != .harfrust and options.engine != .compare_harfrust) return null;
    if (options.harfrust_bin_explicit or !std.mem.eql(u8, options.harfrust_bin, options_mod.default_harfrust_bin)) return null;

    const home = environ_map.get("HOME") orelse return null;
    if (home.len == 0 or !std.fs.path.isAbsolute(home)) return null;

    const path = try std.fs.path.join(allocator, &.{ home, "Work/harfrust/target/release/hr-shape" });
    errdefer allocator.free(path);

    // The local reference repositories live under ~/Work in this project. Prefer
    // that checked-out binary when it exists so documented parity gates work on
    // the user's checkout without baking a per-machine absolute path into the
    // command-line default. If the binary has not been built, fall back to PATH
    // lookup for "hr-shape".
    std.Io.Dir.accessAbsolute(io, path, .{ .execute = true }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.PermissionDenied => {
            allocator.free(path);
            return null;
        },
        else => return err,
    };
    options.harfrust_bin = path;
    return path;
}

fn runReferenceComparison(io: std.Io, allocator: std.mem.Allocator, font_bytes: []const u8, base_options: options_mod.Options) !void {
    var options = base_options;
    options.engine = .cangjie;
    options.iterations = 1;
    options.warmup = 0;
    options.samples = 1;
    options.line_summary = true;
    options.glyph_summary = true;
    options.reorder_bidi = false;
    options.native_direction_shaping = true;
    options.normalize_clusters_to_graphemes = base_options.cluster_level == null;
    options.language_tag = base_options.language_tag orelse .dflt;
    if (base_options.engine == .compare_coretext) {
        options.compare_positions = false;
    }

    const font = try runner.parseFont(allocator, font_bytes, options);
    defer font.deinit();
    const cangjie_result = try runner.runCangjie(io, allocator, font, options);
    defer freeResult(allocator, cangjie_result);

    var reference_options = options;
    reference_options.engine = switch (base_options.engine) {
        .compare_coretext => .coretext,
        .compare_harfrust => .harfrust,
        .compare_harfbuzz => .harfbuzz,
        else => unreachable,
    };
    const reference_result = switch (reference_options.engine) {
        .coretext => try coretext.run(io, allocator, font_bytes, reference_options),
        .harfrust => try harfrust.run(io, allocator, reference_options),
        .harfbuzz => try harfbuzz.run(io, allocator, font_bytes, reference_options),
        else => unreachable,
    };
    defer freeResult(allocator, reference_result);

    const mismatch = try firstLineMismatch(allocator, base_options, cangjie_result.line_summaries, reference_result.line_summaries);
    const reference_label = reference_options.engine.label();
    std.debug.print(
        \\engine={s}
        \\font={s}
        \\text={s}
        \\lines={d}
        \\cangjie_glyphs={d}
        \\{s}_glyphs={d}
        \\
    , .{
        base_options.engine.label(),
        base_options.fontLabel(),
        base_options.textLabel(),
        cangjie_result.line_summaries.len,
        cangjie_result.glyph_count,
        reference_label,
        reference_result.glyph_count,
    });
    if (mismatch) |m| {
        defer allocator.free(m.cangjie_glyph_ids);
        defer allocator.free(m.cangjie_clusters);
        defer allocator.free(m.cangjie_position_values);
        const mismatch_text = if (m.line_index < base_options.text_lines.len) base_options.text_lines[m.line_index] else "";
        std.debug.print(
            \\parity=fail
            \\mismatch_index={d}
            \\mismatch_line={d}
            \\mismatch_text={s}
            \\cangjie_line_glyphs={d}
            \\{s}_line_glyphs={d}
            \\cangjie_line_checksum={x}
            \\{s}_line_checksum={x}
            \\mismatch_kind={s}
            \\cangjie_glyph_ids=
        , .{
            m.line_index,
            m.line_index + 1,
            mismatch_text,
            m.cangjie.glyph_count,
            reference_label,
            m.harfrust.glyph_count,
            m.cangjie.checksum,
            reference_label,
            m.harfrust.checksum,
            m.kind.label(),
        });
        printGlyphIds(m.cangjie_glyph_ids);
        std.debug.print("\n{s}_glyph_ids=", .{reference_label});
        printGlyphIds(m.harfrust.glyph_ids);
        if (m.kind == .glyph_id) {
            const diff_index = firstDifferentGlyphIndex(m.cangjie_glyph_ids, m.harfrust.glyph_ids);
            std.debug.print("\nfirst_glyph_diff_index={d}", .{diff_index});
            std.debug.print("\nsource_codepoints=", .{});
            printSourceCodepoints(mismatch_text);
            std.debug.print("\ncangjie_glyph_window=", .{});
            try printGlyphWindow(font, m.cangjie_glyph_ids, m.cangjie_clusters, diff_index);
            std.debug.print("\n{s}_glyph_window=", .{reference_label});
            try printGlyphWindow(font, m.harfrust.glyph_ids, m.harfrust.clusters, diff_index);
        }
        if (m.kind == .cluster) {
            std.debug.print("\ncangjie_clusters=", .{});
            printClusters(m.cangjie_clusters);
            std.debug.print("\n{s}_clusters=", .{reference_label});
            printClusters(m.harfrust.clusters);
        }
        if (m.kind.isPosition()) {
            std.debug.print("\ncangjie_{s}=", .{m.kind.label()});
            printI32Values(m.cangjie_position_values);
            std.debug.print("\n{s}_{s}=", .{ reference_label, m.kind.label() });
            printI32Values(positionValues(m.harfrust, m.kind));
        }
        if (m.kind == .glyph_flags) {
            std.debug.print("\ncangjie_glyph_flags=", .{});
            printGlyphIds(m.cangjie.glyph_flags);
            std.debug.print("\n{s}_glyph_flags=", .{reference_label});
            printGlyphIds(m.harfrust.glyph_flags);
        }
        if (m.kind == .glyph_extents) {
            std.debug.print("\ncangjie_glyph_extents=", .{});
            printI32Values(m.cangjie.glyph_extents);
            std.debug.print("\n{s}_glyph_extents=", .{reference_label});
            printI32Values(m.harfrust.glyph_extents);
        }
        std.debug.print("\n", .{});
        return error.ReferenceParityMismatch;
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
    x_advance,
    y_advance,
    x_offset,
    y_offset,
    glyph_flags,
    glyph_extents,
    line_count,

    fn label(self: MismatchKind) []const u8 {
        return switch (self) {
            .glyph_id => "glyph_id",
            .cluster => "cluster",
            .x_advance => "x_advance",
            .y_advance => "y_advance",
            .x_offset => "x_offset",
            .y_offset => "y_offset",
            .glyph_flags => "glyph_flags",
            .glyph_extents => "glyph_extents",
            .line_count => "line_count",
        };
    }

    fn isPosition(self: MismatchKind) bool {
        return switch (self) {
            .x_advance, .y_advance, .x_offset, .y_offset => true,
            else => false,
        };
    }
};

const LineMismatch = struct {
    kind: MismatchKind,
    line_index: usize,
    cangjie: runner.BenchResult.LineSummary,
    harfrust: runner.BenchResult.LineSummary,
    cangjie_glyph_ids: []const u32,
    cangjie_clusters: []const u32,
    cangjie_position_values: []const i32,
};

const CompareOrder = enum {
    source,
    reverse_source,
};

fn compareOrder(text: []const u8, direction: options_mod.Direction) CompareOrder {
    if (direction == .ltr or direction == .ttb) return .source;
    if (direction == .btt) return .reverse_source;
    const native_direction = cangjie.text.opentype.scriptHorizontalDirection(scriptTagForText(text)) orelse .rtl;
    return if (native_direction == .ltr) .source else .reverse_source;
}

fn scriptTagForText(text: []const u8) cangjie.text.opentype.Script {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        const script = cangjie.text.script.of(codepoint);
        if (script != .common and script != .inherited and script != .unknown) {
            return cangjie.text.opentype.script(script);
        }
    }
    return .dflt;
}

fn firstLineMismatch(allocator: std.mem.Allocator, options: options_mod.Options, cangjie_lines: []const runner.BenchResult.LineSummary, harfrust_lines: []const runner.BenchResult.LineSummary) !?LineMismatch {
    const count = @min(cangjie_lines.len, harfrust_lines.len);
    for (0..count) |line_index| {
        const order = compareOrder(if (line_index < options.text_lines.len) options.text_lines[line_index] else "", options.direction);
        const cangjie_ids = try comparableSlice(u32, allocator, cangjie_lines[line_index].glyph_ids, order);
        errdefer allocator.free(cangjie_ids);
        if (!std.mem.eql(u32, cangjie_ids, harfrust_lines[line_index].glyph_ids)) {
            return .{
                .kind = .glyph_id,
                .line_index = line_index,
                .cangjie = cangjie_lines[line_index],
                .harfrust = harfrust_lines[line_index],
                .cangjie_glyph_ids = cangjie_ids,
                .cangjie_clusters = try comparableSlice(u32, allocator, cangjie_lines[line_index].clusters, order),
                .cangjie_position_values = try allocator.alloc(i32, 0),
            };
        }
        const cangjie_clusters = try comparableSlice(u32, allocator, cangjie_lines[line_index].clusters, order);
        errdefer allocator.free(cangjie_clusters);
        if (harfrust_lines[line_index].clusters.len != 0 and !std.mem.eql(u32, cangjie_clusters, harfrust_lines[line_index].clusters)) {
            return .{
                .kind = .cluster,
                .line_index = line_index,
                .cangjie = cangjie_lines[line_index],
                .harfrust = harfrust_lines[line_index],
                .cangjie_glyph_ids = cangjie_ids,
                .cangjie_clusters = cangjie_clusters,
                .cangjie_position_values = try allocator.alloc(i32, 0),
            };
        }
        if (options.compare_positions and options.engine != .compare_coretext) {
            inline for (.{ MismatchKind.x_advance, MismatchKind.y_advance, MismatchKind.x_offset, MismatchKind.y_offset }) |kind| {
                const cangjie_values = try comparableSlice(i32, allocator, positionValues(cangjie_lines[line_index], kind), order);
                errdefer allocator.free(cangjie_values);
                if (!std.mem.eql(i32, cangjie_values, positionValues(harfrust_lines[line_index], kind))) {
                    return .{
                        .kind = kind,
                        .line_index = line_index,
                        .cangjie = cangjie_lines[line_index],
                        .harfrust = harfrust_lines[line_index],
                        .cangjie_glyph_ids = cangjie_ids,
                        .cangjie_clusters = cangjie_clusters,
                        .cangjie_position_values = cangjie_values,
                    };
                }
                allocator.free(cangjie_values);
            }
        }
        const cangjie_flags = try comparableSlice(u32, allocator, cangjie_lines[line_index].glyph_flags, order);
        errdefer allocator.free(cangjie_flags);
        if (!std.mem.eql(u32, cangjie_flags, harfrust_lines[line_index].glyph_flags)) {
            return .{
                .kind = .glyph_flags,
                .line_index = line_index,
                .cangjie = cangjie_lines[line_index],
                .harfrust = harfrust_lines[line_index],
                .cangjie_glyph_ids = cangjie_ids,
                .cangjie_clusters = cangjie_clusters,
                .cangjie_position_values = try allocator.alloc(i32, 0),
            };
        }
        allocator.free(cangjie_flags);
        const cangjie_extents = try comparableExtents(allocator, cangjie_lines[line_index].glyph_extents, order);
        errdefer allocator.free(cangjie_extents);
        if (!std.mem.eql(i32, cangjie_extents, harfrust_lines[line_index].glyph_extents)) {
            return .{
                .kind = .glyph_extents,
                .line_index = line_index,
                .cangjie = cangjie_lines[line_index],
                .harfrust = harfrust_lines[line_index],
                .cangjie_glyph_ids = cangjie_ids,
                .cangjie_clusters = cangjie_clusters,
                .cangjie_position_values = try allocator.alloc(i32, 0),
            };
        }
        allocator.free(cangjie_extents);
        allocator.free(cangjie_ids);
        allocator.free(cangjie_clusters);
    }
    if (cangjie_lines.len != harfrust_lines.len) {
        const line_index = count;
        const order = compareOrder(if (line_index < options.text_lines.len) options.text_lines[line_index] else "", options.direction);
        const cangjie_ids = if (line_index < cangjie_lines.len)
            try comparableSlice(u32, allocator, cangjie_lines[line_index].glyph_ids, order)
        else
            try allocator.alloc(u32, 0);
        errdefer allocator.free(cangjie_ids);
        const cangjie_clusters = if (line_index < cangjie_lines.len)
            try comparableSlice(u32, allocator, cangjie_lines[line_index].clusters, order)
        else
            try allocator.alloc(u32, 0);
        return .{
            .kind = .line_count,
            .line_index = line_index,
            .cangjie = if (line_index < cangjie_lines.len) cangjie_lines[line_index] else emptyLineSummary(line_index),
            .harfrust = if (line_index < harfrust_lines.len) harfrust_lines[line_index] else emptyLineSummary(line_index),
            .cangjie_glyph_ids = cangjie_ids,
            .cangjie_clusters = cangjie_clusters,
            .cangjie_position_values = try allocator.alloc(i32, 0),
        };
    }
    return null;
}

fn positionValues(summary: runner.BenchResult.LineSummary, kind: MismatchKind) []const i32 {
    return switch (kind) {
        .x_advance => summary.x_advances,
        .y_advance => summary.y_advances,
        .x_offset => summary.x_offsets,
        .y_offset => summary.y_offsets,
        else => &.{},
    };
}

fn emptyLineSummary(line_index: usize) runner.BenchResult.LineSummary {
    return .{ .index = line_index, .text_bytes = 0, .glyph_count = 0, .checksum = 0 };
}

fn verifyExpectedSummary(allocator: std.mem.Allocator, options: options_mod.Options, summaries: []const runner.BenchResult.LineSummary) !void {
    if (options.expected_glyph_ids == null and
        options.expected_clusters == null and
        options.expected_x_advances == null and
        options.expected_y_advances == null and
        options.expected_x_offsets == null and
        options.expected_y_offsets == null)
    {
        return;
    }
    if (summaries.len == 0) return error.ExpectedSummaryMismatch;
    const summary = summaries[0];
    if (options.expected_glyph_ids) |text| try expectCsv(u32, allocator, text, summary.glyph_ids);
    if (options.expected_clusters) |text| try expectCsv(u32, allocator, text, summary.clusters);
    if (options.expected_x_advances) |text| try expectCsv(i32, allocator, text, summary.x_advances);
    if (options.expected_y_advances) |text| try expectCsv(i32, allocator, text, summary.y_advances);
    if (options.expected_x_offsets) |text| try expectCsv(i32, allocator, text, summary.x_offsets);
    if (options.expected_y_offsets) |text| try expectCsv(i32, allocator, text, summary.y_offsets);
}

fn expectCsv(comptime T: type, allocator: std.mem.Allocator, text: []const u8, actual: []const T) !void {
    const expected = try parseCsv(T, allocator, text);
    defer allocator.free(expected);
    if (!std.mem.eql(T, expected, actual)) return error.ExpectedSummaryMismatch;
}

fn parseCsv(comptime T: type, allocator: std.mem.Allocator, text: []const u8) ![]T {
    var values = std.ArrayList(T).empty;
    errdefer values.deinit(allocator);
    var parts = std.mem.splitScalar(u8, text, ',');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) return error.InvalidArguments;
        try values.append(allocator, try std.fmt.parseInt(T, part, 10));
    }
    return try values.toOwnedSlice(allocator);
}

fn comparableSlice(comptime T: type, allocator: std.mem.Allocator, items: []const T, order: CompareOrder) ![]const T {
    const comparable = try allocator.alloc(T, items.len);
    switch (order) {
        .source => @memcpy(comparable, items),
        .reverse_source => {
            for (items, 0..) |item, index| {
                comparable[items.len - 1 - index] = item;
            }
        },
    }
    return comparable;
}

fn comparableExtents(allocator: std.mem.Allocator, items: []const i32, order: CompareOrder) ![]const i32 {
    if (items.len % 4 != 0) return error.InvalidArguments;
    const comparable = try allocator.alloc(i32, items.len);
    const glyph_count = items.len / 4;
    switch (order) {
        .source => @memcpy(comparable, items),
        .reverse_source => {
            for (0..glyph_count) |index| {
                const dest_index = glyph_count - 1 - index;
                @memcpy(comparable[dest_index * 4 ..][0..4], items[index * 4 ..][0..4]);
            }
        },
    }
    return comparable;
}

fn printGlyphIds(glyph_ids: []const u32) void {
    for (glyph_ids, 0..) |glyph_id, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{glyph_id});
    }
}

fn firstDifferentGlyphIndex(lhs: []const u32, rhs: []const u32) usize {
    const shared_len = @min(lhs.len, rhs.len);
    for (0..shared_len) |index| {
        if (lhs[index] != rhs[index]) return index;
    }
    return shared_len;
}

fn printGlyphWindow(font: *const cangjie.font.Face, glyph_ids: []const u32, clusters: []const u32, center: usize) !void {
    const start = center -| 8;
    const end = @min(glyph_ids.len, center + 9);
    for (glyph_ids[start..end], start..) |glyph_id, index| {
        if (index != start) std.debug.print(",", .{});
        const cluster = if (index < clusters.len) clusters[index] else 0;
        const name = if (glyph_id <= std.math.maxInt(cangjie.font.GlyphId))
            try font.glyphs().name(@intCast(glyph_id))
        else
            null;
        if (name) |value| {
            std.debug.print("{d}@{d}:{s}", .{ glyph_id, cluster, value });
        } else {
            std.debug.print("{d}@{d}", .{ glyph_id, cluster });
        }
    }
}

fn printSourceCodepoints(text: []const u8) void {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var first = true;
    while (it.i < text.len) {
        const offset = it.i;
        const codepoint = it.nextCodepoint() orelse break;
        if (!first) std.debug.print(",", .{});
        first = false;
        std.debug.print("{d}:U+{X}", .{ offset, codepoint });
    }
}

fn printClusters(clusters: []const u32) void {
    for (clusters, 0..) |cluster, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{cluster});
    }
}

fn printI32Values(values: []const i32) void {
    for (values, 0..) |value, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{value});
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
        allocator.free(summary.x_advances);
        allocator.free(summary.y_advances);
        allocator.free(summary.x_offsets);
        allocator.free(summary.y_offsets);
        allocator.free(summary.glyph_flags);
        allocator.free(summary.glyph_extents);
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
