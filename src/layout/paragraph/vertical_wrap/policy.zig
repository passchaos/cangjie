//! Resolve ranged vertical wrapping policy against retained base boundaries.
//!
//! Retained paragraphs deliberately store width-independent UAX/dictionary
//! analysis. Reflow must therefore tailor that base for the current
//! `wrap-mode` / `word-break` / `overflow-wrap` request exactly as horizontal
//! reflow does. Boundary policy belongs to the preceding source scalar.

const std = @import("std");
const analysis = @import("../../line_break/analysis.zig");
const opportunity = @import("../../line_break/opportunity.zig");
const line_break_policy = @import("../line_break_policy.zig");
const paragraph_options = @import("../options.zig");
const unicode = @import("../../../unicode.zig");

pub const Resolved = struct {
    allocator: std.mem.Allocator,
    items: []const opportunity.Opportunity,
    owned: ?[]opportunity.Opportunity = null,

    pub fn deinit(self: *Resolved) void {
        if (self.owned) |items| self.allocator.free(items);
        self.* = undefined;
    }
};

pub fn resolve(
    allocator: std.mem.Allocator,
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
    base: []const opportunity.Opportunity,
    options: paragraph_options.Options,
) !Resolved {
    const defaults = paragraph_options.defaultLineBreakPolicy(options);
    if (!line_break_policy.requiresOpportunityTailoring(
        defaults,
        options.line_break_policy_ranges,
    )) {
        return .{ .allocator = allocator, .items = base };
    }
    const owned = try analysis.tailorBreakPolicy(
        allocator,
        text,
        graphemes,
        base,
        defaults,
        options.line_break_policy_ranges,
    );
    return .{
        .allocator = allocator,
        .items = owned,
        .owned = owned,
    };
}

pub fn anyWrappingEnabled(
    text_len: usize,
    options: paragraph_options.Options,
) bool {
    return line_break_policy.anyWrappingEnabled(
        text_len,
        paragraph_options.defaultLineBreakPolicy(options),
        options.line_break_policy_ranges,
    );
}

pub fn emergencyAllowedBefore(
    options: paragraph_options.Options,
    byte_offset: usize,
) bool {
    const selected = line_break_policy.beforeBoundary(
        paragraph_options.defaultLineBreakPolicy(options),
        options.line_break_policy_ranges,
        byte_offset,
    );
    return selected.wrap_mode != .no_wrap and
        (selected.overflow_wrap != .normal or
            selected.word_break == .break_all);
}

pub fn wrappingAllowedBefore(
    options: paragraph_options.Options,
    byte_offset: usize,
) bool {
    return line_break_policy.beforeBoundary(
        paragraph_options.defaultLineBreakPolicy(options),
        options.line_break_policy_ranges,
        byte_offset,
    ).wrap_mode != .no_wrap;
}
