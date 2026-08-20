//! Materialization of discretionary U+00AD line-end hyphens.
//!
//! Horizontal shaping normally keeps SOFT HYPHEN as a zero-advance source
//! atom. Vertical shaping may omit that default-ignorable output entirely, so
//! paragraph reflow either replaces the retained atom or inserts one
//! source-owning visible glyph at the selected UAX #14 boundary.

const font_mod = @import("../font.zig");
const Font = font_mod.Font;
const GlyphId = @import("../glyph.zig").GlyphId;
const glyph_position = @import("glyph_position.zig");
const GlyphOrientation = glyph_position.Orientation;
const run_types = @import("types/runs.zig");
const pipeline_types = @import("../shaping/pipeline/types.zig");
const positioning_policy =
    @import("../shaping/pipeline/positioning/policy.zig");

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

/// Vertical geometry for a materialized U+00AD source atom.
///
/// This is distinct from `Resolved`: horizontal reflow needs only the
/// replacement advance, while a vertical glyph also needs orientation and its
/// OpenType vertical origin. Keeping both records here ensures explicit and
/// future automatic hyphens resolve through one font-instance contract.
pub const VerticalResolved = struct {
    glyph_id: GlyphId,
    codepoint: u21,
    y_advance: f32,
    x_offset: f32,
    y_offset: f32,
    orientation: GlyphOrientation,
};

pub const VerticalCandidate = struct {
    /// Original glyph index to replace, or source-order insertion boundary
    /// when `synthetic` is true.
    glyph_index: usize,
    run_index: usize,
    source_byte_start: usize,
    source_byte_len: usize,
    synthetic: bool = false,
    automatic: bool = false,
    resolved: VerticalResolved,
};

const GlyphOwner = struct {
    run_index: usize,
    run: run_types.CascadeRun,
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

/// Resolve a visible vertical hyphen through the run owning `glyph_index`.
///
/// Run-local variation coordinates are authoritative. Styled vertical
/// paragraphs can contain several font instances, so using paragraph-global
/// coordinates here would select correct source boundaries but wrong metrics.
pub fn resolveVerticalForGlyph(
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    glyph_index: usize,
    writing_mode: pipeline_types.WritingMode,
    text_orientation: pipeline_types.TextOrientation,
    character: ?u21,
) !?VerticalCandidate {
    const owner = glyphOwner(runs, glyph_index) orelse return null;
    return resolveVerticalForRun(
        owner,
        variation_coords,
        glyph_index,
        writing_mode,
        text_orientation,
        character,
    );
}

pub fn resolveVerticalAtBoundary(
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    glyphs: []const glyph_position.GlyphPosition,
    insert_index: usize,
    source_byte_start: usize,
    source_byte_len: usize,
    writing_mode: pipeline_types.WritingMode,
    text_orientation: pipeline_types.TextOrientation,
    character: ?u21,
) !?VerticalCandidate {
    if (insert_index == 0 or insert_index > glyphs.len) return null;
    const owner_index = insert_index - 1;
    const owner = glyphOwner(runs, owner_index) orelse return null;
    const candidate = try resolveVerticalForRun(
        owner,
        variation_coords,
        owner_index,
        writing_mode,
        text_orientation,
        character,
    ) orelse return null;
    var result = candidate;
    result.glyph_index = insert_index;
    result.source_byte_start = source_byte_start;
    result.source_byte_len = source_byte_len;
    result.synthetic = true;
    return result;
}

pub fn resolveVerticalAutomaticAtBoundary(
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    glyphs: []const glyph_position.GlyphPosition,
    insert_index: usize,
    source_boundary: usize,
    writing_mode: pipeline_types.WritingMode,
    text_orientation: pipeline_types.TextOrientation,
    character: ?u21,
) !?VerticalCandidate {
    if (insert_index == 0 or insert_index > glyphs.len) return null;
    const owner_index = insert_index - 1;
    const owner = glyphOwner(runs, owner_index) orelse return null;
    const candidate = try resolveVerticalForRun(
        owner,
        variation_coords,
        owner_index,
        writing_mode,
        text_orientation,
        character,
    ) orelse return null;
    var result = candidate;
    result.glyph_index = insert_index;
    result.source_byte_start = source_boundary;
    result.source_byte_len = 0;
    result.synthetic = true;
    result.automatic = true;
    return result;
}

fn glyphOwner(
    runs: []const run_types.CascadeRun,
    glyph_index: usize,
) ?GlyphOwner {
    for (runs, 0..) |run, run_index| {
        if (glyph_index >= run.glyph_start and
            glyph_index < run.glyph_start + run.glyph_len)
        {
            return .{ .run_index = run_index, .run = run };
        }
    }
    return null;
}

fn resolveVerticalForRun(
    owner: GlyphOwner,
    variation_coords: []const f32,
    glyph_index: usize,
    writing_mode: pipeline_types.WritingMode,
    text_orientation: pipeline_types.TextOrientation,
    character: ?u21,
) !?VerticalCandidate {
    const run = owner.run;
    const coord_end =
        run.variation_coord_start + run.variation_coord_len;
    if (coord_end > variation_coords.len) {
        return error.InvalidParagraphLayout;
    }
    const coords =
        variation_coords[run.variation_coord_start..coord_end];
    const font = run_types.fontForBackend(run);
    const horizontal =
        try resolve(font, run.font_size, coords, character) orelse
        return null;
    const orientation = positioning_policy.glyphOrientation(
        horizontal.codepoint,
        writing_mode,
        text_orientation,
    );
    const vertical_metrics = try positioning_policy.verticalMetrics(
        font,
        null,
        horizontal.glyph_id,
        coords,
    );
    const y_advance = if (orientation == .sideways)
        horizontal.x_advance
    else if (vertical_metrics) |metrics|
        @as(f32, @floatFromInt(metrics.advance_height)) *
            (run.font_size /
                @as(f32, @floatFromInt(font.units_per_em)))
    else
        run.font_size;
    const scale = run.font_size /
        @as(f32, @floatFromInt(font.units_per_em));
    const origin_y = try font_mod.shaping.verticalOriginYAtCoords(
        font,
        horizontal.glyph_id,
        coords,
    );
    return .{
        .glyph_index = glyph_index,
        .run_index = owner.run_index,
        .source_byte_start = 0,
        .source_byte_len = 0,
        .resolved = .{
            .glyph_id = horizontal.glyph_id,
            .codepoint = horizontal.codepoint,
            .y_advance = y_advance,
            .x_offset = -horizontal.x_advance / 2,
            .y_offset = -@as(f32, @floatFromInt(origin_y)) * scale,
            .orientation = orientation,
        },
    };
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

pub fn materializeVertical(
    glyph: *glyph_position.GlyphPosition,
    resolved: VerticalResolved,
) void {
    glyph.glyph_id = resolved.glyph_id;
    glyph.synthetic_glyph_id = null;
    glyph.codepoint = resolved.codepoint;
    glyph.x_advance = 0;
    glyph.y_advance = resolved.y_advance;
    glyph.x_offset = resolved.x_offset;
    glyph.y_offset = resolved.y_offset;
    glyph.orientation = resolved.orientation;
    glyph.flags.discretionary_hyphen = true;
}

pub fn syntheticVertical(
    candidate: VerticalCandidate,
) glyph_position.GlyphPosition {
    return .{
        .glyph_id = candidate.resolved.glyph_id,
        .codepoint = candidate.resolved.codepoint,
        .cluster = candidate.source_byte_start,
        .source_byte_len = candidate.source_byte_len,
        .x_advance = 0,
        .y_advance = candidate.resolved.y_advance,
        .x_offset = candidate.resolved.x_offset,
        .y_offset = candidate.resolved.y_offset,
        .orientation = candidate.resolved.orientation,
        .flags = .{
            .discretionary_hyphen = true,
            .automatic_hyphen = candidate.automatic,
        },
    };
}

pub fn synthetic(
    resolved: Resolved,
    byte_offset: usize,
    orientation: GlyphOrientation,
) @import("glyph_position.zig").GlyphPosition {
    return .{
        .glyph_id = resolved.glyph_id,
        .codepoint = resolved.codepoint,
        .cluster = byte_offset,
        .source_byte_len = 0,
        .x_advance = resolved.x_advance,
        .orientation = orientation,
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
