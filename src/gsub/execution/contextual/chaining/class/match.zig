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

    /// Materialize only a successful match. Keeping this as an out-parameter is
    /// important: `Match` owns three bounded index arrays and returning it
    /// through `!?Match` made every rejected class rule initialize/copy the
    /// large error-union result even though no region escaped the matcher.
    pub fn set(
        self: *Match,
        matched_window: *const window.Window,
        input_count: usize,
        backtrack_count: usize,
        lookahead_count: usize,
        action: Action,
    ) void {
        self.input_count = input_count;
        self.backtrack_count = backtrack_count;
        self.lookahead_count = lookahead_count;
        self.action = action;
        @memcpy(
            self.input[0..input_count],
            matched_window.regions.input[0..input_count],
        );
        @memcpy(
            self.backtrack[0..backtrack_count],
            matched_window.regions.backtrack[0..backtrack_count],
        );
        @memcpy(
            self.lookahead[0..lookahead_count],
            matched_window.regions.lookahead[0..lookahead_count],
        );
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
