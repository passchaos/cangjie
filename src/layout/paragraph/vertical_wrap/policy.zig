//! Resolve global vertical wrapping policy against retained base boundaries.
//!
//! Retained paragraphs deliberately store width-independent UAX/dictionary
//! analysis. Reflow must therefore tailor that base for the current
//! `word-break` / `overflow-wrap` request exactly as horizontal reflow does.

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
        &.{},
    )) {
        return .{ .allocator = allocator, .items = base };
    }
    const owned = try analysis.tailorBreakPolicy(
        allocator,
        text,
        graphemes,
        base,
        defaults,
        &.{},
    );
    return .{
        .allocator = allocator,
        .items = owned,
        .owned = owned,
    };
}
