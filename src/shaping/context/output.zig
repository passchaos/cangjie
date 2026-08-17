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
        self.runs.deinit(self.allocator);
        self.glyphs.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *Buffer) void {
        self.glyphs.clearRetainingCapacity();
        self.runs.clearRetainingCapacity();
        self.lines.clearRetainingCapacity();
        self.inline_objects.clearRetainingCapacity();
        self.script_runs.clearRetainingCapacity();
    }

    pub fn run(
        self: *const Buffer,
        font: *const Font,
        font_size: f32,
    ) run_types.GlyphRun {
        return run_types.initGlyphRun(font, font_size, self.glyphs.items);
    }

    pub fn shapedText(self: *const Buffer) run_types.ShapedText {
        return .{ .glyphs = self.glyphs.items, .runs = self.runs.items };
    }

    pub fn scriptedText(self: *const Buffer) run_types.ScriptedText {
        return .{
            .glyphs = self.glyphs.items,
            .font_runs = self.runs.items,
            .script_runs = self.script_runs.items,
        };
    }

    pub fn paragraphLayout(self: *const Buffer) paragraph_types.ParagraphLayout {
        var max_width: f32 = 0;
        var height: f32 = 0;
        for (self.lines.items) |line| {
            max_width = @max(max_width, line.x + line.width);
            height = @max(height, line.y + line.height);
        }
        return .{
            .glyphs = self.glyphs.items,
            .runs = self.runs.items,
            .lines = self.lines.items,
            .inline_objects = self.inline_objects.items,
            .width = max_width,
            .height = height,
        };
    }
};
