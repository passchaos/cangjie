//! Immutable result of one chaining class-rule match.

const window = @import("matching/window.zig");

pub const Action = union(enum) {
    records: struct {
        offset: usize,
        count: usize,
    },
    nested_lookup: u16,
};

pub const Match = struct {
    input: [window.max_region_glyphs]usize = undefined,
    input_count: usize,
    backtrack: [window.max_region_glyphs]usize = undefined,
    backtrack_count: usize,
    lookahead: [window.max_region_glyphs]usize = undefined,
    lookahead_count: usize,
    action: Action,

    pub fn init(
        matched_window: *const window.Window,
        input_count: usize,
        backtrack_count: usize,
        lookahead_count: usize,
        action: Action,
    ) Match {
        var result = Match{
            .input_count = input_count,
            .backtrack_count = backtrack_count,
            .lookahead_count = lookahead_count,
            .action = action,
        };
        @memcpy(
            result.input[0..input_count],
            matched_window.regions.input[0..input_count],
        );
        @memcpy(
            result.backtrack[0..backtrack_count],
            matched_window.regions.backtrack[0..backtrack_count],
        );
        @memcpy(
            result.lookahead[0..lookahead_count],
            matched_window.regions.lookahead[0..lookahead_count],
        );
        return result;
    }

    pub fn inputSlice(self: *const Match) []const usize {
        return self.input[0..self.input_count];
    }

    pub fn backtrackSlice(self: *const Match) []const usize {
        return self.backtrack[0..self.backtrack_count];
    }

    pub fn lookaheadSlice(self: *const Match) []const usize {
        return self.lookahead[0..self.lookahead_count];
    }
};
