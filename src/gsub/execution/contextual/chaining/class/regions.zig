//! Lazy physical glyph regions for chaining class matching.

const std = @import("std");
const accelerator = @import("../../../../accelerator/model.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub const max_glyphs = accelerator.max_context_region_glyphs;

pub const Regions = struct {
    glyphs: []const GlyphId,
    lookup_flag: u16,
    run: Options,
    anchor_syllable: ?u8,

    input: [max_glyphs]usize = undefined,
    input_len: usize = 0,
    input_scan: usize,
    input_exhausted: bool = false,

    backtrack: [max_glyphs]usize = undefined,
    backtrack_len: usize = 0,
    backtrack_scan: usize,
    backtrack_exhausted: bool = false,

    lookahead: [max_glyphs]usize = undefined,
    lookahead_len: usize = 0,
    lookahead_scan: usize = 0,
    lookahead_start: usize = std.math.maxInt(usize),
    lookahead_exhausted: bool = false,

    pub fn init(
        glyphs: []const GlyphId,
        position: usize,
        lookup_flag: u16,
        run: Options,
    ) Regions {
        return .{
            .glyphs = glyphs,
            .lookup_flag = lookup_flag,
            .run = run,
            .anchor_syllable = filtering.sourceSyllableForGlyph(run, position),
            .input_scan = position,
            .backtrack_scan = position,
        };
    }

    pub fn inputIndices(
        self: *Regions,
        count: usize,
    ) error{UnsupportedGsub}!?[]const usize {
        if (!try self.ensureInput(count)) return null;
        return self.input[0..count];
    }

    pub fn backtrackIndices(
        self: *Regions,
        count: usize,
    ) error{UnsupportedGsub}!?[]const usize {
        if (!try self.ensureBacktrack(count)) return null;
        return self.backtrack[0..count];
    }

    pub fn lookaheadIndices(
        self: *Regions,
        input_count: usize,
        count: usize,
    ) error{UnsupportedGsub}!?[]const usize {
        if (!try self.ensureLookahead(input_count, count)) return null;
        return self.lookahead[0..count];
    }

    fn ensureInput(
        self: *Regions,
        count: usize,
    ) error{UnsupportedGsub}!bool {
        if (count > max_glyphs) return error.UnsupportedGsub;
        while (self.input_len < count) {
            if (self.input_exhausted) return false;
            const index = self.nextForward(
                &self.input_scan,
                false,
            ) orelse {
                self.input_exhausted = true;
                return false;
            };
            self.input[self.input_len] = index;
            self.input_len += 1;
        }
        return true;
    }

    fn ensureBacktrack(
        self: *Regions,
        count: usize,
    ) error{UnsupportedGsub}!bool {
        if (count > max_glyphs) return error.UnsupportedGsub;
        while (self.backtrack_len < count) {
            if (self.backtrack_exhausted) return false;
            var found = false;
            while (self.backtrack_scan > 0) {
                self.backtrack_scan -= 1;
                const index = self.backtrack_scan;
                if (filtering.contextualMaySkipGlyph(
                    self.lookup_flag,
                    self.run,
                    self.glyphs,
                    index,
                    true,
                )) continue;
                if (!self.syllableAllows(index)) {
                    self.backtrack_exhausted = true;
                    return false;
                }
                self.backtrack[self.backtrack_len] = index;
                self.backtrack_len += 1;
                found = true;
                break;
            }
            if (!found) {
                self.backtrack_exhausted = true;
                return false;
            }
        }
        return true;
    }

    fn ensureLookahead(
        self: *Regions,
        input_count: usize,
        count: usize,
    ) error{UnsupportedGsub}!bool {
        if (input_count == 0 or input_count > max_glyphs or
            count > max_glyphs)
        {
            return error.UnsupportedGsub;
        }
        if (!try self.ensureInput(input_count)) return false;
        const start = self.input[input_count - 1] + 1;
        if (self.lookahead_start != start) {
            self.lookahead_start = start;
            self.lookahead_scan = start;
            self.lookahead_len = 0;
            self.lookahead_exhausted = false;
        }
        while (self.lookahead_len < count) {
            if (self.lookahead_exhausted) return false;
            const index = self.nextForward(
                &self.lookahead_scan,
                true,
            ) orelse {
                self.lookahead_exhausted = true;
                return false;
            };
            self.lookahead[self.lookahead_len] = index;
            self.lookahead_len += 1;
        }
        return true;
    }

    fn nextForward(
        self: *Regions,
        scan: *usize,
        context_match: bool,
    ) ?usize {
        while (scan.* < self.glyphs.len) {
            const index = scan.*;
            scan.* += 1;
            if (filtering.contextualMaySkipGlyph(
                self.lookup_flag,
                self.run,
                self.glyphs,
                index,
                context_match,
            )) continue;
            if (!self.syllableAllows(index)) return null;
            return index;
        }
        return null;
    }

    fn syllableAllows(self: *const Regions, index: usize) bool {
        return filtering.sourceSyllableAllowsGlyph(
            self.run,
            self.anchor_syllable,
            index,
        );
    }
};
