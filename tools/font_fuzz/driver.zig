//! Shared malformed-font parser, shaping, and renderer exercise path.

const std = @import("std");
const cangjie = @import("cangjie");

const shaping_font_size: f32 = 20;
const shaping_cases = [_]cangjie.shaping.Request{
    // Supplying surrounding text reaches contextual joining without increasing
    // the shaped output or allowing a mutated font to choose the input size.
    .{
        .text = "AVA",
        .font_size = shaping_font_size,
        .options = .{
            .script_tag = .latn,
            .context_before = "f",
            .context_after = "i",
        },
    },
    .{
        .text = "\u{0628}\u{064e}\u{062a}\u{0651}",
        .font_size = shaping_font_size,
        .options = .{
            .direction = .rtl,
            .script_tag = .arab,
            .language_tag = .ara,
        },
    },
    .{
        .text = "\u{0915}\u{094d}\u{0937}\u{093f}",
        .font_size = shaping_font_size,
        .options = .{
            .script_tag = .deva,
            .language_tag = .hin,
        },
    },
    .{
        .text = "AAA",
        .font_size = shaping_font_size,
        .options = .{ .script_tag = .latn },
        .feature_ranges = &.{.{
            .tag = cangjie.text.opentype.tag("sups"),
            .value = 1,
            .byte_start = 1,
            .byte_end = 3,
        }},
    },
};

/// Drive one caller-owned byte slice through the public font APIs. Invalid
/// inputs and malformed optional tables are expected to return errors;
/// allocator failures must escape so fuzzing still detects swallowed OOMs.
pub fn exerciseCase(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var face = cangjie.font.Face.parse(allocator, bytes) catch |err| {
        try tolerateMalformedInput(err);
        return;
    };
    defer face.deinit();

    try exerciseShaping(allocator, &face);

    const glyphs = face.glyphs();
    // Prefer a cmap-derived glyph so successful mutations exercise the link
    // between cmap and outline tables. Fonts without U+0041 still exercise
    // the required .notdef geometry.
    const glyph_id = glyphs.index('A') catch |err| fallback: {
        try tolerateMalformedInput(err);
        break :fallback 0;
    };
    _ = glyphs.extents(glyph_id) catch |err| try tolerateMalformedInput(err);
    var outline_buffer = cangjie.font.OutlineBuffer.init(allocator);
    defer outline_buffer.deinit();
    _ = glyphs.session().outlineInto(&outline_buffer, glyph_id) catch |err|
        try tolerateMalformedInput(err);
    var outline = glyphs.outline(allocator, glyph_id) catch |err| fallback: {
        try tolerateMalformedInput(err);
        break :fallback null;
    };
    defer if (outline) |*value| value.deinit();

    // Exercise variation-aware outline decoding whenever the mutated face
    // still exposes axes. Default and non-default coordinates take different
    // gvar/CFF2/VARC paths and the reusable variant owns additional cache-key
    // storage that must remain transactional on malformed input.
    const variation_summary = face.variations().summary() catch |err| fallback: {
        try tolerateMalformedInput(err);
        break :fallback null;
    };
    const axis_count = if (variation_summary) |summary| summary.axis_count else 0;
    if (axis_count != 0) {
        const coords = try allocator.alloc(f32, axis_count);
        defer allocator.free(coords);
        @memset(coords, 0.5);
        var varied = glyphs.outlineAt(allocator, glyph_id, coords) catch |err| fallback: {
            try tolerateMalformedInput(err);
            break :fallback null;
        };
        if (varied) |*value| value.deinit();
        _ = glyphs.session().outlineAtInto(
            &outline_buffer,
            glyph_id,
            coords,
        ) catch |err| try tolerateMalformedInput(err);
    }

    // Parsed metadata and bitmap/color accessors share the same table graph
    // but not the outline decoder, so keep them live in malformed-font fuzzing.
    const palettes = face.color().palettes(allocator) catch |err| fallback: {
        try tolerateMalformedInput(err);
        break :fallback null;
    };
    if (palettes) |values| allocator.free(values);
    const bitmap_strikes = face.color().bitmapStrikes(allocator) catch |err| fallback: {
        try tolerateMalformedInput(err);
        break :fallback null;
    };
    if (bitmap_strikes) |values| allocator.free(values);

    // Bitmap-only and color-only faces need not have a conventional outline.
    // Keep their metadata paths reachable, and raster only when the selected
    // glyph did produce geometry.
    if (outline) |*value| {
        var target = try cangjie.render.GrayTarget.init(allocator, 32, 32);
        defer target.deinit();
        var rasterizer = cangjie.render.Rasterizer.init(allocator);
        defer rasterizer.deinit();
        rasterizer.setSampling(4);
        // The grayscale path currently exposes only allocation failure. Keep
        // this catch explicit so a future malformed-geometry error remains an
        // ordinary fuzz outcome rather than accidentally tightening the driver.
        rasterizer.drawOutline(
            &target,
            value,
            0,
            24,
            24,
            face.properties().units_per_em,
        ) catch |err| try tolerateMalformedInput(err);
    }
}

fn exerciseShaping(
    allocator: std.mem.Allocator,
    face: *const cangjie.font.Face,
) !void {
    // Keep one engine alive for the complete corpus. Besides amortizing its
    // bounded scratch allocations, this stresses cache/output reuse after both
    // successful and rejected requests against one parsed face.
    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();

    const baseline_succeeded = if (engine.shape(face, shaping_cases[0])) |_|
        true
    else |err| failed: {
        try tolerateMalformedInput(err);
        break :failed false;
    };

    // Request validation fails before output mutation. Follow the deliberately
    // malformed call with the same request that established the baseline. If
    // that baseline worked, recovery must work too; a new error is engine-state
    // corruption rather than an ordinary malformed-font result.
    if (engine.shape(face, .{
        .text = "\xff",
        .font_size = shaping_font_size,
    })) |_| {
        return error.MalformedRequestAccepted;
    } else |err| {
        if (err != error.InvalidUtf8) return err;
    }
    if (baseline_succeeded) {
        _ = try engine.shape(face, shaping_cases[0]);
    } else {
        _ = engine.shape(face, shaping_cases[0]) catch |err|
            try tolerateMalformedInput(err);
    }

    for (shaping_cases[1..]) |request| {
        _ = engine.shape(face, request) catch |err|
            try tolerateMalformedInput(err);
    }
}

/// Malformed font and shaping errors are normal fuzzer outcomes. Keep this
/// allowlist explicit: allocator failure must escape for rollback audits, and a
/// newly introduced logic error must fail fuzzing rather than disappear here.
fn tolerateMalformedInput(err: anyerror) !void {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.BadCff,
        error.BadGpos,
        error.BadGsub,
        error.BadSfnt,
        error.CompoundDepthExceeded,
        error.EndOfStream,
        error.InvalidBitmapSize,
        error.InvalidGlyph,
        error.InvalidJoiningInput,
        error.InvalidLoca,
        error.InvalidMarkGlyphSet,
        error.InvalidMetrics,
        error.InvalidName,
        error.InvalidShapingInput,
        error.MissingTable,
        error.NoSpaceLeft,
        error.ShapingLimitExceeded,
        error.UnsupportedCff,
        error.UnsupportedCmap,
        error.UnsupportedGlyph,
        error.UnsupportedGpos,
        error.UnsupportedGsub,
        => {},
        else => return err,
    }
}
