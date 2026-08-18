//! Reusable shaping and paragraph output owned by a shaping context.
//!
//! The buffer stores public result records, transient shaping scratch, optional
//! profiling state, and borrowed font-derived caches. Algorithms remain in
//! their domain modules and receive this concrete owner by pointer.

const std = @import("std");

const Font = @import("../../font.zig").Font;
const glyph_position = @import("../../layout/glyph_position.zig");
const inline_object = @import("../../layout/inline_object/root.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const run_types = @import("../../layout/types/runs.zig");
const ShapeStageProfile = @import("../../shape_profile.zig").ShapeStageProfile;
const cache = @import("cache/root.zig");
const scratch = @import("scratch.zig");

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    glyphs: std.ArrayList(glyph_position.GlyphPosition) = .empty,
    runs: std.ArrayList(run_types.CascadeRun) = .empty,
    /// Deduplicated-by-construction normalized coordinates referenced by runs.
    variation_coords: std.ArrayList(f32) = .empty,
    lines: std.ArrayList(paragraph_types.ParagraphLine) = .empty,
    inline_objects: std.ArrayList(inline_object.Positioned) = .empty,
    script_runs: std.ArrayList(run_types.ScriptedRun) = .empty,
    shape_profile: ?*ShapeStageProfile = null,
    profile_io: ?std.Io = null,
    profile_fast_path: bool = false,
    gdef_metadata_cache: ?*cache.GdefMetadataCache = null,
    gsub_table_proof_cache: ?*cache.GsubTableProofCache = null,
    gpos_table_proof_cache: ?*cache.GposTableProofCache = null,
    lookup_selection_cache: ?*cache.LookupSelectionCache = null,
    shape_scratch: scratch.ShapeScratch = .{},

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Buffer) void {
        self.shape_scratch.deinit(self.allocator);
        self.script_runs.deinit(self.allocator);
        self.inline_objects.deinit(self.allocator);
        self.lines.deinit(self.allocator);
        self.variation_coords.deinit(self.allocator);
        self.runs.deinit(self.allocator);
        self.glyphs.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *Buffer) void {
        self.glyphs.clearRetainingCapacity();
        self.runs.clearRetainingCapacity();
        self.variation_coords.clearRetainingCapacity();
        self.lines.clearRetainingCapacity();
        self.inline_objects.clearRetainingCapacity();
        self.script_runs.clearRetainingCapacity();
    }

    pub fn run(
        self: *Buffer,
        font: *const Font,
        font_size: f32,
        normalized_variation_coords: []const f32,
    ) !run_types.GlyphRun {
        const range = try self.internVariationCoords(
            normalized_variation_coords,
        );
        return run_types.initGlyphRun(
            font,
            font_size,
            self.glyphs.items,
            self.variation_coords.items[range.start .. range.start + range.len],
        );
    }

    pub fn shapedText(self: *const Buffer) run_types.ShapedText {
        return .{
            .glyphs = self.glyphs.items,
            .runs = self.runs.items,
            .normalized_variation_coords = self.variation_coords.items,
        };
    }

    pub fn scriptedText(self: *const Buffer) run_types.ScriptedText {
        return .{
            .glyphs = self.glyphs.items,
            .font_runs = self.runs.items,
            .script_runs = self.script_runs.items,
            .normalized_variation_coords = self.variation_coords.items,
        };
    }

    pub fn paragraphLayout(
        self: *const Buffer,
        writing_mode: @import("../pipeline/types.zig").WritingMode,
    ) paragraph_types.ParagraphLayout {
        var max_width: f32 = 0;
        var height: f32 = 0;
        for (self.lines.items) |line| {
            // `line.x` is the first glyph origin. `width` starts after any
            // physical-start hanging, so add that optical offset back when
            // reporting the occupied paragraph measure.
            max_width = @max(
                max_width,
                line.x + line.hang_start + line.width,
            );
            height = @max(height, line.y + line.height);
        }
        return .{
            .glyphs = self.glyphs.items,
            .runs = self.runs.items,
            .normalized_variation_coords = self.variation_coords.items,
            .lines = self.lines.items,
            .inline_objects = self.inline_objects.items,
            .writing_mode = writing_mode,
            .width = max_width,
            .height = height,
        };
    }

    /// Return a stable range for one run's normalized fvar coordinates.
    ///
    /// Equal slices share storage so a paragraph with many fallback/style
    /// fragments does not repeat the same coordinate vector per run.
    pub fn internVariationCoords(
        self: *Buffer,
        coords: []const f32,
    ) !struct { start: usize, len: usize } {
        if (coords.len == 0) return .{ .start = 0, .len = 0 };
        var start: usize = 0;
        while (start + coords.len <= self.variation_coords.items.len) : (start += 1) {
            var equal = true;
            for (self.variation_coords.items[start..][0..coords.len], coords) |
                existing,
                requested,
            | {
                if (@as(u32, @bitCast(existing)) !=
                    @as(u32, @bitCast(requested)))
                {
                    equal = false;
                    break;
                }
            }
            if (equal) return .{ .start = start, .len = coords.len };
        }
        const range_start = self.variation_coords.items.len;
        try self.variation_coords.appendSlice(self.allocator, coords);
        return .{ .start = range_start, .len = coords.len };
    }
};
