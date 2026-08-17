//! Materialization of discretionary U+00AD line-end hyphens.
//!
//! Shaping keeps SOFT HYPHEN as a zero-advance source atom. Reflow calls this
//! module only after selecting its UAX #14 opportunity, preserving source,
//! caret, and bidi metadata without inserting another glyph into the stream.

const Font = @import("../font.zig").Font;
const GlyphId = @import("../glyph.zig").GlyphId;
const run_types = @import("types/runs.zig");

pub const soft_hyphen: u21 = 0x00ad;

pub const Resolved = struct {
    glyph_id: GlyphId,
    codepoint: u21,
    x_advance: f32,
};

pub const Candidate = struct {
    glyph_index: usize,
    resolved: Resolved,
};

pub const RunResolved = struct {
    run_index: usize,
    resolved: Resolved,
};

pub fn isCandidate(codepoint: u21) bool {
    return codepoint == soft_hyphen;
}

/// Resolves the visible hyphen from the font run owning `glyph_index`.
///
/// U+2010 is the typographic hyphen selected by CSS's default
/// `hyphenate-character: auto` behavior. U+002D and the font's U+00AD glyph are
/// portable fallbacks for fonts with narrower character coverage.
pub fn resolveForGlyph(
    runs: anytype,
    glyph_index: usize,
    normalized_variation_coords: []const f32,
    character: ?u21,
) !?Resolved {
    const value = try resolveForGlyphRun(
        runs,
        glyph_index,
        normalized_variation_coords,
        character,
    );
    return if (value) |resolved| resolved.resolved else null;
}

/// Resolve a hyphen and retain the font-run identity needed by a later
/// synthetic insertion. Run indexes remain stable while line selection is in
/// progress even though materialization eventually shifts glyph ranges.
pub fn resolveForGlyphRun(
    runs: anytype,
    glyph_index: usize,
    normalized_variation_coords: []const f32,
    character: ?u21,
) !?RunResolved {
    for (runs, 0..) |run, run_index| {
        if (glyph_index < run.glyph_start or
            glyph_index >= run.glyph_start + run.glyph_len)
        {
            continue;
        }
        const resolved = try resolve(
            run_types.fontForBackend(run),
            run.font_size,
            normalized_variation_coords,
            character,
        ) orelse return null;
        return .{
            .run_index = run_index,
            .resolved = resolved,
        };
    }
    return null;
}

pub fn materialize(glyph: anytype, resolved: Resolved) void {
    glyph.glyph_id = resolved.glyph_id;
    glyph.synthetic_glyph_id = null;
    glyph.codepoint = resolved.codepoint;
    glyph.x_advance = resolved.x_advance;
    glyph.y_advance = 0;
    glyph.x_offset = 0;
    glyph.y_offset = 0;
    glyph.flags.discretionary_hyphen = true;
}

pub fn synthetic(
    resolved: Resolved,
    byte_offset: usize,
    vertical: bool,
) @import("glyph_position.zig").GlyphPosition {
    return .{
        .glyph_id = resolved.glyph_id,
        .codepoint = resolved.codepoint,
        .cluster = byte_offset,
        .source_byte_len = 0,
        .x_advance = resolved.x_advance,
        .vertical = vertical,
        .flags = .{
            .discretionary_hyphen = true,
            .automatic_hyphen = true,
        },
    };
}

test "non-soft-hyphen scalars are never discretionary candidates" {
    const std = @import("std");
    try std.testing.expect(isCandidate(soft_hyphen));
    try std.testing.expect(!isCandidate('-'));
    try std.testing.expect(!isCandidate(0x2010));
    try std.testing.expect(!isCandidate(0x2011));
}

test "hyphen resolution prefers U+2010 then portable fallbacks" {
    const std = @import("std");
    const test_font = @import("../test_font.zig");

    const preferred_bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{ 0x002d, soft_hyphen, 0x2010 },
    );
    defer std.testing.allocator.free(preferred_bytes);
    var preferred = try Font.parse(std.testing.allocator, preferred_bytes);
    defer preferred.deinit();
    const preferred_value = (try resolve(&preferred, 20, &.{}, null)).?;
    try std.testing.expectEqual(@as(u21, 0x2010), preferred_value.codepoint);
    try std.testing.expect(preferred_value.x_advance > 0);

    const ascii_bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{0x002d},
    );
    defer std.testing.allocator.free(ascii_bytes);
    var ascii = try Font.parse(std.testing.allocator, ascii_bytes);
    defer ascii.deinit();
    try std.testing.expectEqual(
        @as(u21, 0x002d),
        (try resolve(&ascii, 20, &.{}, null)).?.codepoint,
    );

    const soft_bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{soft_hyphen},
    );
    defer std.testing.allocator.free(soft_bytes);
    var soft = try Font.parse(std.testing.allocator, soft_bytes);
    defer soft.deinit();
    try std.testing.expectEqual(
        soft_hyphen,
        (try resolve(&soft, 20, &.{}, null)).?.codepoint,
    );

    const missing_bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{'A'},
    );
    defer std.testing.allocator.free(missing_bytes);
    var missing = try Font.parse(std.testing.allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try resolve(&missing, 20, &.{}, null)) == null);

    const custom_bytes = try test_font.buildCodepointSetTtf(
        std.testing.allocator,
        &.{ 0x2010, 0x2022 },
    );
    defer std.testing.allocator.free(custom_bytes);
    var custom = try Font.parse(std.testing.allocator, custom_bytes);
    defer custom.deinit();
    try std.testing.expectEqual(
        @as(u21, 0x2022),
        (try resolve(&custom, 20, &.{}, 0x2022)).?.codepoint,
    );
    try std.testing.expect(
        (try resolve(&custom, 20, &.{}, 0x2603)) == null,
    );
}

fn resolve(
    font: *const Font,
    font_size: f32,
    normalized_variation_coords: []const f32,
    character: ?u21,
) !?Resolved {
    if (character) |codepoint| {
        return try resolveCodepoint(
            font,
            font_size,
            normalized_variation_coords,
            codepoint,
        );
    }
    for ([_]u21{ 0x2010, '-', soft_hyphen }) |codepoint| {
        if (try resolveCodepoint(
            font,
            font_size,
            normalized_variation_coords,
            codepoint,
        )) |resolved| return resolved;
    }
    return null;
}

fn resolveCodepoint(
    font: *const Font,
    font_size: f32,
    normalized_variation_coords: []const f32,
    codepoint: u21,
) !?Resolved {
    const glyph_id = try font.glyphIndex(codepoint);
    if (glyph_id == 0) return null;
    const metrics = try font.horizontalMetricsAtCoords(
        glyph_id,
        normalized_variation_coords,
    );
    const scale = font_size /
        @as(f32, @floatFromInt(font.units_per_em));
    return .{
        .glyph_id = glyph_id,
        .codepoint = codepoint,
        .x_advance = @as(f32, @floatFromInt(metrics.advance_width)) * scale,
    };
}
