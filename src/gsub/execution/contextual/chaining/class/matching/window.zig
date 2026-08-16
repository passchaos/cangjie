//! Lazy class and physical-index window for chaining class rules.

const std = @import("std");
const Options = @import("../../../../../runtime/options.zig").Options;
const table = @import("../../../../../table/root.zig");
const regions_mod = @import("regions.zig");
const GlyphId = @import("../../../../../../glyph.zig").GlyphId;

const Error = table.class_def.Error;
const View = table.View;

pub const max_region_glyphs = regions_mod.max_glyphs;

pub const ClassDefs = struct {
    backtrack: usize,
    input: usize,
    lookahead: usize,
};

/// Rules in one class set may have different region lengths. Cache discovered
/// physical indexes and class values incrementally so a longer later rule
/// cannot make an earlier short rule fail at the end of a run or syllable.
pub const Window = struct {
    view: View,
    glyphs: []const GlyphId,
    class_defs: ClassDefs,
    regions: regions_mod.Regions,

    input_classes: [max_region_glyphs]u16 = undefined,
    input_class_valid: [max_region_glyphs]bool =
        [_]bool{false} ** max_region_glyphs,

    backtrack_classes: [max_region_glyphs]u16 = undefined,
    backtrack_class_valid: [max_region_glyphs]bool =
        [_]bool{false} ** max_region_glyphs,

    lookahead_classes: [max_region_glyphs]u16 = undefined,
    lookahead_class_valid: [max_region_glyphs]bool =
        [_]bool{false} ** max_region_glyphs,
    cached_lookahead_start: usize = std.math.maxInt(usize),

    pub fn init(
        view: View,
        glyphs: []const GlyphId,
        position: usize,
        class_defs: ClassDefs,
        lookup_flag: u16,
        run: Options,
    ) Window {
        return .{
            .view = view,
            .glyphs = glyphs,
            .class_defs = class_defs,
            .regions = .init(glyphs, position, lookup_flag, run),
        };
    }

    pub fn inputIndices(
        self: *Window,
        count: usize,
    ) Error!?[]const usize {
        return try self.regions.inputIndices(count);
    }

    pub fn backtrackIndices(
        self: *Window,
        count: usize,
    ) Error!?[]const usize {
        return try self.regions.backtrackIndices(count);
    }

    pub fn lookaheadIndices(
        self: *Window,
        input_count: usize,
        count: usize,
    ) Error!?[]const usize {
        return try self.regions.lookaheadIndices(input_count, count);
    }

    pub fn inputClassAt(self: *Window, index: usize) Error!?u16 {
        const indices = (try self.inputIndices(index + 1)) orelse return null;
        if (!self.input_class_valid[index]) {
            self.input_classes[index] = try table.class_def.value(
                self.view,
                self.class_defs.input,
                self.glyphs[indices[index]],
            );
            self.input_class_valid[index] = true;
        }
        return self.input_classes[index];
    }

    pub fn backtrackClassAt(self: *Window, index: usize) Error!?u16 {
        const indices =
            (try self.backtrackIndices(index + 1)) orelse return null;
        if (!self.backtrack_class_valid[index]) {
            self.backtrack_classes[index] = try table.class_def.value(
                self.view,
                self.class_defs.backtrack,
                self.glyphs[indices[index]],
            );
            self.backtrack_class_valid[index] = true;
        }
        return self.backtrack_classes[index];
    }

    pub fn lookaheadClassAt(
        self: *Window,
        input_count: usize,
        index: usize,
    ) Error!?u16 {
        const indices = (try self.lookaheadIndices(
            input_count,
            index + 1,
        )) orelse return null;
        const start = self.regions.input[input_count - 1] + 1;
        if (self.cached_lookahead_start != start) {
            self.cached_lookahead_start = start;
            @memset(&self.lookahead_class_valid, false);
        }
        if (!self.lookahead_class_valid[index]) {
            self.lookahead_classes[index] = try table.class_def.value(
                self.view,
                self.class_defs.lookahead,
                self.glyphs[indices[index]],
            );
            self.lookahead_class_valid[index] = true;
        }
        return self.lookahead_classes[index];
    }
};
