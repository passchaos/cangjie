const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const unicode = @import("unicode.zig");

pub const ShapeScratch = struct {
    glyph_ids: std.ArrayList(GlyphId) = .empty,
    codepoints: std.ArrayList(u21) = .empty,
    clusters: std.ArrayList(usize) = .empty,
    source_ends: std.ArrayList(usize) = .empty,
    glyph_source_indices: std.ArrayList(usize) = .empty,
    ligature_components: std.ArrayList(gpos.LigatureComponentInfo) = .empty,
    joining_forms: std.ArrayList(unicode.JoiningForm) = .empty,
    source_features: std.ArrayList(u32) = .empty,
    gpos_adjustments: std.ArrayList(gpos.Adjustment) = .empty,

    pub fn deinit(self: *ShapeScratch, allocator: std.mem.Allocator) void {
        self.gpos_adjustments.deinit(allocator);
        self.source_features.deinit(allocator);
        self.joining_forms.deinit(allocator);
        self.ligature_components.deinit(allocator);
        self.glyph_source_indices.deinit(allocator);
        self.source_ends.deinit(allocator);
        self.clusters.deinit(allocator);
        self.codepoints.deinit(allocator);
        self.glyph_ids.deinit(allocator);
        self.* = .{};
    }

    pub fn clear(self: *ShapeScratch) void {
        self.glyph_ids.clearRetainingCapacity();
        self.codepoints.clearRetainingCapacity();
        self.clusters.clearRetainingCapacity();
        self.source_ends.clearRetainingCapacity();
        self.glyph_source_indices.clearRetainingCapacity();
        self.ligature_components.clearRetainingCapacity();
        self.joining_forms.clearRetainingCapacity();
        self.source_features.clearRetainingCapacity();
        self.gpos_adjustments.clearRetainingCapacity();
    }
};
