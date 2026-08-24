const std = @import("std");
const builtin = @import("builtin");
const cangjie = @import("cangjie");

const system_font_path = "/System/Library/Fonts/SFNSMono.ttf";
const linux_noto_sans_arabic_path = "/usr/share/fonts/truetype/noto/NotoSansArabic-Regular.ttf";
const linux_noto_naskh_arabic_path = "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf";
const linux_noto_serif_myanmar_path =
    "/usr/share/fonts/truetype/noto/NotoSerifMyanmar-Regular.ttf";
const linux_noto_sans_cjk_path = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc";
const local_estedad_variable_path =
    "../../Work/harfbuzz/test/api/fonts/Estedad-VF.ttf";
const known_sfns_mono_sha256 = hexToBytes("55caaed55254a28ac793847e8976be16c5ba7cbad1ec2ee2d5d86d4e6b3fa0c1");
const known_raster_sha256 = hexToBytes("76440f37e0266d38bf0fc4a65e399dc527f81ef76f963470fe796bc895356a6c");

test "macOS SFNSMono parses shapes and rasterizes stable grayscale glyphs" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, system_font_path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);

    var font_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(font_bytes, &font_digest, .{});
    const known_font = std.mem.eql(u8, &font_digest, &known_sfns_mono_sha256);

    var font = cangjie.font.Face.parse(allocator, font_bytes) catch |err| switch (err) {
        error.BadSfnt,
        error.InvalidGlyph,
        error.MissingTable,
        error.UnsupportedCff,
        error.UnsupportedCmap,
        error.UnsupportedGlyph,
        => if (known_font) return err else return error.SkipZigTest,
        else => return err,
    };
    defer font.deinit();

    const properties = font.properties();
    try std.testing.expectEqual(cangjie.font.Format.truetype, properties.format);
    try std.testing.expect(properties.units_per_em >= 16);
    try std.testing.expect((try font.glyphs().index('C')) > 0);
    try std.testing.expect((try font.glyphs().index('j')) > 0);

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const run = try engine.shape(&font, .{ .text = "Cangjie", .font_size = 36 });
    try std.testing.expectEqual(@as(usize, 7), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 155.77734), run.width(), 0.001);

    var target = try cangjie.render.GrayTarget.init(allocator, 240, 96);
    defer target.deinit();

    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    try rasterizer.drawRun(&target, run, 12, 60);

    const stats = rasterStats(&target);
    try std.testing.expectEqual(@as(usize, 1173), stats.covered);
    try std.testing.expectEqual(@as(u64, 216155), stats.coverage_sum);
    try std.testing.expectEqual(@as(u8, 255), stats.max_coverage);
    try std.testing.expectEqual(RasterBounds{ .min_x = 14, .min_y = 31, .max_x = 164, .max_y = 66 }, stats.bounds.?);

    if (known_font) {
        var raster_digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(target.pixels, &raster_digest, .{});
        try std.testing.expectEqualSlices(u8, &known_raster_sha256, &raster_digest);
    }
}

test "Linux Noto Sans Arabic parses duplicate contextual GPOS coverage" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, linux_noto_sans_arabic_path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);

    var font = try cangjie.font.Face.parse(allocator, font_bytes);
    defer font.deinit();
    try std.testing.expect((try font.glyphs().index(0x0645)) > 0); // Arabic meem.

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const run = try engine.shape(
        &font,
        .{
            .text = "مرحبا بالعالم 123",
            .font_size = 32,
            .options = .{ .direction = .rtl },
        },
    );
    try std.testing.expectEqual(@as(usize, 17), run.glyphs.len);
    // These are the positional-form glyphs and advances selected by the same
    // Noto Sans Arabic file through Pango/HarfBuzz. Keep a small tolerance for
    // float scaling, but require joining to reduce the unshaped 281.824px run.
    try std.testing.expectApproxEqAbs(@as(f32, 217.408), run.width(), 0.01);
    var actual_glyph_ids: [17]cangjie.font.GlyphId = undefined;
    for (run.glyphs, &actual_glyph_ids) |glyph, *actual| actual.* = glyph.glyph_id;
    try std.testing.expectEqualSlices(
        cangjie.font.GlyphId,
        &.{ 907, 1380, 1354, 3, 770, 667, 47, 12, 667, 47, 102, 3, 47, 104, 417, 979, 771 },
        &actual_glyph_ids,
    );

    var target = try cangjie.render.GrayTarget.init(allocator, 320, 96);
    defer target.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    try rasterizer.drawRun(&target, run, 12, 64);
    const stats = rasterStats(&target);
    try std.testing.expect(stats.covered > 100);
    try std.testing.expect(stats.coverage_sum > 1000);
    try std.testing.expect(stats.bounds != null);
}

test "Linux Noto Serif Myanmar accepts null chaining lookahead ClassDef" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        linux_noto_serif_myanmar_path,
        allocator,
        .limited(16 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);

    var font = try cangjie.font.Face.parse(allocator, font_bytes);
    defer font.deinit();
    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const run = try engine.shape(
        &font,
        .{ .text = "မြန်မာ", .font_size = 32 },
    );
    try std.testing.expectEqual(@as(usize, 6), run.glyphs.len);
}

test "Linux Noto Arabic exposes HarfBuzz-compatible tatweel insertion flags" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        linux_noto_sans_arabic_path,
        allocator,
        .limited(16 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);
    var font = try cangjie.font.Face.parse(allocator, font_bytes);
    defer font.deinit();

    var engine = cangjie.shaping.Engine.init(
        allocator,
        .{ .cache_shaped_runs = true },
    );
    defer engine.deinit();
    const text = "بب";
    const request = cangjie.shaping.TextRequest{
        .text = text,
        .font_size = 32,
        .options = .{ .direction = .rtl },
    };
    const cascade = cangjie.font.Cascade.init(&.{&font});
    const first = try engine.shapeText(cascade, request);
    try expectTatweelFlags(first);

    // Complete shaped-run cache storage must preserve the public flags exactly.
    const cached = try engine.shapeText(cascade, request);
    try expectTatweelFlags(cached);
    try std.testing.expectEqual(
        @as(usize, 1),
        engine.stats().shaped_runs.hits,
    );
}

fn expectTatweelFlags(text: cangjie.shaping.Text) !void {
    try std.testing.expectEqual(@as(usize, 2), text.glyphs.len);
    // Native RTL visual order places the boundary-bearing second source first.
    try std.testing.expect(text.glyphs[0].isSafeToInsertTatweel());
    try std.testing.expect(text.glyphs[0].isUnsafeToBreakBefore());
    try std.testing.expect(!text.glyphs[1].isSafeToInsertTatweel());
}

test "Linux Noto Naskh Arabic justification inserts shaped Kashida" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        linux_noto_naskh_arabic_path,
        allocator,
        .limited(16 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);
    var font = try cangjie.font.Face.parse(allocator, font_bytes);
    defer font.deinit();

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const cascade = cangjie.font.Cascade.init(&.{&font});
    const text = "بب بب بب";
    const options = cangjie.paragraph.Options{
        .max_width = 95,
        .direction = .rtl,
        .alignment = .justify,
    };
    const layout = try engine.layout(cascade, .{
        .text = text,
        .font_size = 32,
        .options = options,
    });
    try expectShapedKashidaLayout(layout, text);

    // The retained path owns the cascade pointer list and exact font size
    // needed to repeat this line-local reshape at a different width.
    var retained = try engine.prepareParagraph(cascade, .{
        .text = text,
        .font_size = 32,
        .options = options,
    });
    defer retained.deinit();
    var reflow = cangjie.paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const retained_layout = try retained.layout(&reflow, options);
    try expectShapedKashidaLayout(retained_layout, text);
}

test "synthetic JSTF ExtenderGlyph drives source-shaped Tatweel insertion" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const base_bytes = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        linux_noto_naskh_arabic_path,
        allocator,
        .limited(16 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(base_bytes);
    var base = try cangjie.font.Face.parse(allocator, base_bytes);
    defer base.deinit();
    const tatweel_glyph = try base.glyphs().index(0x0640);
    const font_bytes = try cangjie.testing.test_font.addJstfExtenderTable(
        allocator,
        base_bytes,
        "arab",
        tatweel_glyph,
    );
    defer allocator.free(font_bytes);
    var font = try cangjie.font.Face.parse(allocator, font_bytes);
    defer font.deinit();

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const text = "بب بب بب";
    const layout = try engine.layout(
        cangjie.font.Cascade.init(&.{&font}),
        .{
            .text = text,
            .font_size = 32,
            .options = .{
                .max_width = 95,
                .direction = .rtl,
                .alignment = .justify,
                // Prove that the JSTF-specific stage, not the generic fallback,
                // owns the source insertion.
                .kashida = .{ .enabled = false },
            },
        },
    );
    try expectShapedKashidaLayout(layout, text);

    var retained = try engine.prepareParagraph(
        cangjie.font.Cascade.init(&.{&font}),
        .{
            .text = text,
            .font_size = 32,
            .options = .{
                .max_width = 95,
                .direction = .rtl,
                .alignment = .justify,
                .kashida = .{ .enabled = false },
            },
        },
    );
    defer retained.deinit();
    var reflow = cangjie.paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const retained_layout = try retained.layout(
        &reflow,
        .{
            .max_width = 95,
            .direction = .rtl,
            .alignment = .justify,
            .kashida = .{ .enabled = false },
        },
    );
    try expectShapedKashidaLayout(retained_layout, text);

    const spans = [_]cangjie.paragraph.StyledSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 23,
        .font_size = 32,
    }};
    const styled = try engine.layoutStyled(
        cangjie.font.Cascade.init(&.{&font}),
        .{
            .text = text,
            .default_font_size = 32,
            .spans = &spans,
            .options = .{
                .max_width = 95,
                .direction = .rtl,
                .alignment = .justify,
                .kashida = .{ .enabled = false },
            },
        },
    );
    try expectShapedKashidaLayout(styled.layout, text);
    try std.testing.expectEqual(
        styled.layout.glyphs.len,
        styled.glyph_metadata.len,
    );
    for (styled.glyph_metadata) |metadata| {
        try std.testing.expectEqual(@as(u32, 23), metadata.style_index);
    }

    const disabled = try engine.layout(
        cangjie.font.Cascade.init(&.{&font}),
        .{
            .text = text,
            .font_size = 32,
            .options = .{
                .max_width = 95,
                .direction = .rtl,
                .alignment = .justify,
                .jstf = .{ .enabled = false },
                .kashida = .{ .enabled = false },
            },
        },
    );
    for (disabled.glyphs) |glyph| {
        try std.testing.expect(!glyph.isKashida());
    }

    // A non-Tatweel extender set cannot be satisfied by the current source
    // safety proof and must not trigger a fabricated glyph insertion.
    const rejected_bytes = try cangjie.testing.test_font.addJstfExtenderTable(
        allocator,
        base_bytes,
        "arab",
        try base.glyphs().index(0x0628),
    );
    defer allocator.free(rejected_bytes);
    var rejected = try cangjie.font.Face.parse(allocator, rejected_bytes);
    defer rejected.deinit();
    const rejected_layout = try engine.layout(
        cangjie.font.Cascade.init(&.{&rejected}),
        .{
            .text = text,
            .font_size = 32,
            .options = .{
                .max_width = 95,
                .direction = .rtl,
                .alignment = .justify,
                .kashida = .{ .enabled = false },
            },
        },
    );
    for (rejected_layout.glyphs) |glyph| {
        try std.testing.expect(!glyph.isKashida());
    }
}

test "Linux Noto Naskh styled paragraph keeps Kashida metadata aligned" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        linux_noto_naskh_arabic_path,
        allocator,
        .limited(16 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);
    var font = try cangjie.font.Face.parse(allocator, font_bytes);
    defer font.deinit();

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const text = "بب بب بب";
    const spans = [_]cangjie.paragraph.StyledSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 9,
        .font_size = 32,
        .letter_spacing = 1,
    }};
    const result = try engine.layoutStyled(
        cangjie.font.Cascade.init(&.{&font}),
        .{
            .text = text,
            .default_font_size = 32,
            .spans = &spans,
            .options = .{
                .max_width = 95,
                .direction = .rtl,
                .alignment = .justify,
            },
        },
    );
    try expectShapedKashidaLayout(result.layout, text);
    try std.testing.expectEqual(
        result.layout.glyphs.len,
        result.glyph_metadata.len,
    );
    for (result.glyph_metadata) |metadata| {
        try std.testing.expectEqual(@as(u32, 9), metadata.style_index);
    }
    for (result.layout.glyphs, result.glyph_metadata) |glyph, metadata| {
        if (glyph.isKashida()) {
            try std.testing.expectApproxEqAbs(
                @as(f32, 0),
                metadata.layout_spacing,
                0.001,
            );
        }
    }
}

fn expectShapedKashidaLayout(
    layout: cangjie.paragraph.Layout,
    source: []const u8,
) !void {
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 95),
        layout.lines[0].width,
        0.001,
    );
    var kashida_count: usize = 0;
    for (layout.glyphs) |glyph| {
        try std.testing.expect(glyph.cluster <= source.len);
        if (!glyph.isKashida()) continue;
        kashida_count += 1;
        try std.testing.expectEqual(@as(u21, 0x0640), glyph.codepoint);
        try std.testing.expectEqual(@as(usize, 0), glyph.source_byte_len);
        try std.testing.expectEqual(glyph.cluster, glyph.sourceByteEnd());
        // This is the font's shaped U+0640 output, not a manually synthesized
        // advance: Noto Naskh's nominal Tatweel glyph is id 726.
        try std.testing.expectEqual(
            @as(cangjie.font.GlyphId, 726),
            glyph.glyph_id,
        );
    }
    try std.testing.expect(kashida_count > 0);
}

test "local Estedad width axis justifies and reaches renderer requests" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        local_estedad_variable_path,
        allocator,
        .limited(16 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);
    var font = try cangjie.font.Face.parse(allocator, font_bytes);
    defer font.deinit();

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const text = "بب بب بب بب بب";
    const layout = try engine.layout(
        cangjie.font.Cascade.init(&.{&font}),
        .{
            .text = text,
            .font_size = 32,
            .options = .{
                .max_width = 200,
                .direction = .rtl,
                .alignment = .justify,
                .kashida = .{ .enabled = false },
            },
        },
    );
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 200),
        layout.lines[0].width,
        0.01,
    );
    const shaped = cangjie.shaping.Text{
        .glyphs = layout.glyphs,
        .runs = layout.runs,
        .normalized_variation_coords = layout.normalized_variation_coords,
    };
    const run_coords = layout.runs[0].normalizedVariationCoords(shaped);
    try std.testing.expectEqual(@as(usize, 2), run_coords.len);
    try std.testing.expect(run_coords[1] > 0 and run_coords[1] < 1);

    var draw_list = try cangjie.render.buildGlyphDrawList(
        allocator,
        layout,
        .{},
    );
    defer draw_list.deinit();
    try std.testing.expectEqualSlices(
        f32,
        run_coords,
        draw_list.runs[0].normalized_variation_coords,
    );
    try std.testing.expectEqualSlices(
        f32,
        run_coords,
        draw_list.atlas_requests[0].normalized_variation_coords,
    );
}

test "Linux Noto Sans CJK vertical shaping uses real vert substitutions and vmtx" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, linux_noto_sans_cjk_path, allocator, .limited(32 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(font_bytes);

    var font = try cangjie.font.Face.parseIndex(allocator, font_bytes, 2); // Noto Sans CJK SC.
    defer font.deinit();
    try std.testing.expect(font.metrics().hasVertical());

    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const horizontal = try engine.shape(&font, .{ .text = "中、（", .font_size = 32 });
    var horizontal_ids: [3]cangjie.font.GlyphId = undefined;
    for (horizontal.glyphs, &horizontal_ids) |glyph, *id| id.* = glyph.glyph_id;

    const vertical = try engine.shape(
        &font,
        .{
            .text = "中、（",
            .font_size = 32,
            .options = .{ .writing_mode = .vertical_rl },
        },
    );
    try std.testing.expectEqual(@as(usize, 3), vertical.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), vertical.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 96), vertical.height(), 0.01);
    // Ideographs stay on the base glyph while punctuation uses the font's
    // real vertical alternates selected through vert/vrt2.
    try std.testing.expectEqual(horizontal_ids[0], vertical.glyphs[0].glyph_id);
    try std.testing.expect(horizontal_ids[1] != vertical.glyphs[1].glyph_id);
    try std.testing.expect(horizontal_ids[2] != vertical.glyphs[2].glyph_id);
    for (vertical.glyphs) |glyph| {
        try std.testing.expect(glyph.isVertical());
        try std.testing.expectApproxEqAbs(@as(f32, 0), glyph.x_advance, 0.001);
        try std.testing.expectApproxEqAbs(@as(f32, 32), glyph.y_advance, 0.01);
    }
}

const RasterBounds = struct {
    min_x: u32,
    min_y: u32,
    max_x: u32,
    max_y: u32,
};

const RasterStats = struct {
    covered: usize,
    coverage_sum: u64,
    max_coverage: u8,
    bounds: ?RasterBounds,
};

fn rasterStats(target: *const cangjie.render.GrayTarget) RasterStats {
    var stats = RasterStats{
        .covered = 0,
        .coverage_sum = 0,
        .max_coverage = 0,
        .bounds = null,
    };

    for (target.pixels, 0..) |coverage, index| {
        if (coverage == 0) continue;
        const x: u32 = @intCast(index % target.width);
        const y: u32 = @intCast(index / target.width);
        stats.covered += 1;
        stats.coverage_sum += coverage;
        stats.max_coverage = @max(stats.max_coverage, coverage);
        if (stats.bounds) |*bounds| {
            bounds.min_x = @min(bounds.min_x, x);
            bounds.min_y = @min(bounds.min_y, y);
            bounds.max_x = @max(bounds.max_x, x);
            bounds.max_y = @max(bounds.max_y, y);
        } else {
            stats.bounds = .{ .min_x = x, .min_y = y, .max_x = x, .max_y = y };
        }
    }

    return stats;
}

fn hexToBytes(comptime hex: []const u8) [hex.len / 2]u8 {
    comptime {
        if (hex.len % 2 != 0) @compileError("hex string must have an even number of digits");
    }
    var bytes: [hex.len / 2]u8 = undefined;
    for (&bytes, 0..) |*byte, index| {
        byte.* = parseHexByte(hex[index * 2], hex[index * 2 + 1]);
    }
    return bytes;
}

fn parseHexByte(comptime high: u8, comptime low: u8) u8 {
    return (hexNibble(high) << 4) | hexNibble(low);
}

fn hexNibble(comptime digit: u8) u8 {
    return switch (digit) {
        '0'...'9' => digit - '0',
        'a'...'f' => digit - 'a' + 10,
        'A'...'F' => digit - 'A' + 10,
        else => @compileError("invalid hex digit"),
    };
}
