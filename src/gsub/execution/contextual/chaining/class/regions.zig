//! Lazy physical glyph regions for chaining class matching.

const std = @import("std");
const accelerator = @import("../../../../accelerator/model.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub const max_glyphs = accelerator.max_context_region_glyphs;

pub const SimpleRegions = struct {
    syllables: []const u8,
    sources: []const usize,
    anchor_syllable: ?u8,

    pub fn init(
        position: usize,
        run: Options,
    ) SimpleRegions {
        // Script-shaper metadata is validated before its feature stages. A
        // low-level caller with incomplete metadata keeps the same permissive
        // behavior as `sourceSyllableForGlyph`: no anchor means no syllable
        // restriction, never an invalid memory access.
        if (run.match_source_syllable) {
            if (run.source_syllables) |syllables| {
                if (run.glyph_source_indices) |sources| {
                    if (position < sources.items.len) {
                        const source = sources.items[position];
                        if (source < syllables.len) {
                            return .{
                                .syllables = syllables,
                                .sources = sources.items,
                                .anchor_syllable = syllables[source],
                            };
                        }
                    }
                }
            }
        }
        return .{
            .syllables = &.{},
            .sources = &.{},
            .anchor_syllable = null,
        };
    }

    pub inline fn allows(
        self: *const SimpleRegions,
        glyph_index: usize,
    ) bool {
        if (self.anchor_syllable) |anchor| {
            if (glyph_index >= self.sources.len) return false;
            const source = self.sources[glyph_index];
            if (source >= self.syllables.len or
                self.syllables[source] != anchor) return false;
        }
        return true;
    }
};

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
        if (self.lookup_flag == 0 and
            self.run.run_has_default_ignorables == false)
        {
            while (self.backtrack_len < count) {
                if (self.backtrack_scan == 0) {
                    self.backtrack_exhausted = true;
                    return false;
                }
                self.backtrack_scan -= 1;
                const index = self.backtrack_scan;
                if (!self.syllableAllows(index)) {
                    self.backtrack_exhausted = true;
                    return false;
                }
                self.backtrack[self.backtrack_len] = index;
                self.backtrack_len += 1;
            }
            return true;
        }
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
        // With neither LookupFlag filtering nor source default-ignorables, a
        // physical glyph is necessarily the next contextual glyph. The
        // whole-run proof is established before GSUB and remains valid across
        // substitutions because it describes the immutable source stream.
        // Indic syllable boundaries still need their ordinary source check.
        if (self.lookup_flag == 0 and
            self.run.run_has_default_ignorables == false)
        {
            if (scan.* >= self.glyphs.len) return null;
            const index = scan.*;
            scan.* += 1;
            if (!self.syllableAllows(index)) return null;
            return index;
        }
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
