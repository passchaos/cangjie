const std = @import("std");
const cangjie = @import("cangjie");
const hb = @import("harfbuzz");

const options_mod = @import("options.zig");
const runner = @import("runner.zig");

const HarfBuzzFont = struct {
    blob: *hb.hb_blob_t,
    face: *hb.hb_face_t,
    font: *hb.hb_font_t,

    fn init(font_bytes: []const u8, size: f32) !HarfBuzzFont {
        if (font_bytes.len > std.math.maxInt(c_uint)) return error.InvalidArguments;
        const blob = hb.hb_blob_create(
            @ptrCast(font_bytes.ptr),
            @intCast(font_bytes.len),
            hb.HB_MEMORY_MODE_READONLY,
            null,
            null,
        ) orelse return error.HarfBuzzFailed;
        errdefer hb.hb_blob_destroy(blob);

        const face = hb.hb_face_create(blob, 0) orelse return error.HarfBuzzFailed;
        errdefer hb.hb_face_destroy(face);

        const font = hb.hb_font_create(face) orelse return error.HarfBuzzFailed;
        errdefer hb.hb_font_destroy(font);
        _ = size;
        const upem: c_int = @intCast(hb.hb_face_get_upem(face));
        hb.hb_font_set_scale(font, upem, upem);

        return .{ .blob = blob, .face = face, .font = font };
    }

    fn deinit(self: HarfBuzzFont) void {
        hb.hb_font_destroy(self.font);
        hb.hb_face_destroy(self.face);
        hb.hb_blob_destroy(self.blob);
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator, font_bytes: []const u8, options: options_mod.Options) !runner.BenchResult {
    if (options.font_path == null) return error.InvalidArguments;
    const hb_font = try HarfBuzzFont.init(font_bytes, options.size);
    defer hb_font.deinit();
    const normalized_coords = try harfBuzzNormalizedCoords(allocator, options.normalizedVariationCoords());
    defer allocator.free(normalized_coords);
    if (normalized_coords.len != 0) {
        hb.hb_font_set_var_coords_normalized(hb_font.font, normalized_coords.ptr, @intCast(normalized_coords.len));
    }
    const features = try harfBuzzFeatures(allocator, options);
    defer allocator.free(features);

    const inline_text_lines = [_][]const u8{options.text};
    const text_lines = if (options.text_lines.len != 0) options.text_lines else inline_text_lines[0..];

    var line_summaries = std.ArrayList(runner.BenchResult.LineSummary).empty;
    errdefer {
        freeLineSummaries(allocator, line_summaries.items);
        line_summaries.deinit(allocator);
    }

    var warmup_index: usize = 0;
    while (warmup_index < options.warmup) : (warmup_index += 1) {
        for (text_lines) |line| {
            var shaped = try shapeLine(allocator, hb_font.font, line, options, features, false);
            shaped.deinit(allocator);
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
            for (text_lines, 0..) |line, line_index| {
                var shaped = try shapeLine(allocator, hb_font.font, line, options, features, options.glyph_summary and sample_index == 0 and i == 0);
                defer shaped.deinit(allocator);
                sample_glyph_count += shaped.glyph_count;
                sample_checksum = updateChecksumWithLine(sample_checksum, shaped.checksum);
                if (options.line_summary and sample_index == 0 and i == 0) {
                    try line_summaries.append(allocator, .{
                        .index = line_index,
                        .text_bytes = line.len,
                        .glyph_count = shaped.glyph_count,
                        .checksum = shaped.checksum,
                        .glyph_ids = shaped.glyph_ids,
                        .clusters = shaped.clusters,
                        .x_advances = shaped.x_advances,
                        .y_advances = shaped.y_advances,
                        .x_offsets = shaped.x_offsets,
                        .y_offsets = shaped.y_offsets,
                    });
                    shaped.transferred_summary_storage = true;
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

const ShapedLine = struct {
    glyph_count: usize,
    checksum: u64,
    glyph_ids: []u32 = &.{},
    clusters: []u32 = &.{},
    x_advances: []i32 = &.{},
    y_advances: []i32 = &.{},
    x_offsets: []i32 = &.{},
    y_offsets: []i32 = &.{},
    transferred_summary_storage: bool = false,

    fn deinit(self: *ShapedLine, allocator: std.mem.Allocator) void {
        if (self.transferred_summary_storage) return;
        allocator.free(self.glyph_ids);
        allocator.free(self.clusters);
        allocator.free(self.x_advances);
        allocator.free(self.y_advances);
        allocator.free(self.x_offsets);
        allocator.free(self.y_offsets);
    }
};

fn shapeLine(allocator: std.mem.Allocator, font: *hb.hb_font_t, line: []const u8, options: options_mod.Options, features: []const hb.hb_feature_t, capture_summary: bool) !ShapedLine {
    if (line.len > std.math.maxInt(c_int)) return error.InvalidArguments;
    const buffer = hb.hb_buffer_create() orelse return error.HarfBuzzFailed;
    defer hb.hb_buffer_destroy(buffer);

    hb.hb_buffer_set_direction(buffer, switch (options.direction) {
        .ltr => hb.HB_DIRECTION_LTR,
        .rtl => hb.HB_DIRECTION_RTL,
        .ttb => hb.HB_DIRECTION_TTB,
        .btt => hb.HB_DIRECTION_BTT,
    });
    if (scriptTagForText(line)) |script_tag| {
        hb.hb_buffer_set_script(buffer, hb.hb_ot_tag_to_script(script_tag));
    }
    if (options.language_tag) |language_tag| {
        if (options_mod.harfrustLanguageArgument(language_tag)) |language_text| {
            hb.hb_buffer_set_language(buffer, hb.hb_language_from_string(@ptrCast(language_text.ptr), @intCast(language_text.len)));
        }
    }
    if (options.not_found_variation_selector_glyph) |glyph_id| {
        hb.hb_buffer_set_not_found_variation_selector_glyph(buffer, glyph_id);
    }
    hb.hb_buffer_add_utf8(buffer, @ptrCast(line.ptr), @intCast(line.len), 0, @intCast(line.len));
    hb.hb_shape(font, buffer, if (features.len == 0) null else features.ptr, @intCast(features.len));

    var length: c_uint = 0;
    const infos = hb.hb_buffer_get_glyph_infos(buffer, &length);
    const positions = hb.hb_buffer_get_glyph_positions(buffer, null);
    if (infos == null or positions == null) return error.HarfBuzzFailed;
    const glyph_count: usize = @intCast(length);

    var shaped = ShapedLine{
        .glyph_count = glyph_count,
        .checksum = 0,
    };
    errdefer shaped.deinit(allocator);
    if (capture_summary) {
        shaped.glyph_ids = try allocator.alloc(u32, glyph_count);
        shaped.clusters = try allocator.alloc(u32, glyph_count);
        shaped.x_advances = try allocator.alloc(i32, glyph_count);
        shaped.y_advances = try allocator.alloc(i32, glyph_count);
        shaped.x_offsets = try allocator.alloc(i32, glyph_count);
        shaped.y_offsets = try allocator.alloc(i32, glyph_count);
    }

    var hasher = std.hash.Wyhash.init(0);
    for (0..glyph_count) |index| {
        const info = infos[index];
        const position = positions[index];
        if (capture_summary) {
            shaped.glyph_ids[index] = @intCast(info.codepoint);
            shaped.clusters[index] = info.cluster;
            shaped.x_advances[index] = position.x_advance;
            shaped.y_advances[index] = position.y_advance;
            shaped.x_offsets[index] = position.x_offset;
            shaped.y_offsets[index] = position.y_offset;
        }
        hasher.update(std.mem.asBytes(&info.codepoint));
        hasher.update(std.mem.asBytes(&info.cluster));
        hasher.update(std.mem.asBytes(&position.x_advance));
        hasher.update(std.mem.asBytes(&position.y_advance));
        hasher.update(std.mem.asBytes(&position.x_offset));
        hasher.update(std.mem.asBytes(&position.y_offset));
    }
    shaped.checksum = hasher.final();
    return shaped;
}

fn freeLineSummaries(allocator: std.mem.Allocator, summaries: []const runner.BenchResult.LineSummary) void {
    for (summaries) |summary| {
        allocator.free(summary.glyph_ids);
        allocator.free(summary.clusters);
        allocator.free(summary.x_advances);
        allocator.free(summary.y_advances);
        allocator.free(summary.x_offsets);
        allocator.free(summary.y_offsets);
    }
}

fn harfBuzzFeatures(allocator: std.mem.Allocator, options: options_mod.Options) ![]hb.hb_feature_t {
    const overrides = options.featureOverrides();
    const features = try allocator.alloc(hb.hb_feature_t, overrides.len);
    for (overrides, features) |feature, *hb_feature| {
        hb_feature.* = .{
            .tag = feature.tag,
            .value = @intFromBool(feature.enabled),
            .start = 0,
            .end = std.math.maxInt(c_uint),
        };
    }
    return features;
}

fn harfBuzzNormalizedCoords(allocator: std.mem.Allocator, coords: []const f32) ![]c_int {
    const out = try allocator.alloc(c_int, coords.len);
    for (coords, out) |coord, *value| {
        value.* = @intFromFloat(@round(coord * 16384.0));
    }
    return out;
}

fn scriptTagForText(text: []const u8) ?c_uint {
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        const script = cangjie.scriptForCodepoint(codepoint);
        if (script == .common or script == .inherited or script == .unknown) continue;
        return @intFromEnum(cangjie.openTypeScriptTag(script));
    }
    return null;
}

fn runtimeOpenTypeTag(bytes: []const u8) c_uint {
    std.debug.assert(bytes.len == 4);
    return (@as(c_uint, bytes[0]) << 24) |
        (@as(c_uint, bytes[1]) << 16) |
        (@as(c_uint, bytes[2]) << 8) |
        @as(c_uint, bytes[3]);
}

fn updateChecksumWithLine(seed: u64, line_checksum: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    hasher.update(std.mem.asBytes(&line_checksum));
    return hasher.final();
}
