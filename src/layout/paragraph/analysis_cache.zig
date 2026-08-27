//! Exact single-entry cache for width-independent styled paragraph analysis.
//!
//! Attributed layout commonly rebuilds the same document text after paint or
//! width changes. UAX #29 grapheme boundaries and the untailored UAX #14 break
//! stream depend only on those bytes, so retaining one exact result avoids
//! decoding the paragraph twice on every rebuild. Dictionary, hyphenation, and
//! range-policy tailoring deliberately stay outside this cache.

const std = @import("std");

const opportunity = @import("../line_break/opportunity.zig");
const unicode = @import("../../unicode.zig");

pub const Analysis = struct {
    graphemes: []const unicode.GraphemeCluster,
    line_breaks: []const opportunity.Opportunity,
};

pub const Cache = struct {
    allocator: std.mem.Allocator,
    text: []u8 = &.{},
    graphemes: []unicode.GraphemeCluster = &.{},
    line_breaks: []opportunity.Opportunity = &.{},
    valid: bool = false,

    pub fn init(allocator: std.mem.Allocator) Cache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Cache) void {
        self.freeCurrent();
        self.* = undefined;
    }

    /// Return analysis for exactly `text`, replacing the prior entry on miss.
    ///
    /// The caller has already validated the complete styled request. Using the
    /// assume-valid iterators here avoids two redundant UTF-8 validation scans
    /// while retaining their full Unicode state machines. New storage is built
    /// transactionally so allocation failure leaves the old entry usable.
    pub fn get(self: *Cache, text: []const u8) !Analysis {
        if (self.valid and std.mem.eql(u8, self.text, text)) {
            return self.analysis();
        }

        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        var graphemes = std.ArrayList(unicode.GraphemeCluster).empty;
        defer graphemes.deinit(self.allocator);
        var grapheme_iterator = unicode.graphemeClustersAssumeValid(text);
        while (grapheme_iterator.next()) |cluster| {
            try graphemes.append(self.allocator, cluster);
        }
        const owned_graphemes = try graphemes.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned_graphemes);

        var line_breaks = std.ArrayList(opportunity.Opportunity).empty;
        defer line_breaks.deinit(self.allocator);
        var line_break_iterator = unicode.lineBreaksAssumeValid(text);
        while (line_break_iterator.next()) |line_break| {
            try line_breaks.append(
                self.allocator,
                opportunity.fromUnicode(line_break),
            );
        }
        const owned_line_breaks = try line_breaks.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned_line_breaks);

        self.freeCurrent();
        self.text = owned_text;
        self.graphemes = owned_graphemes;
        self.line_breaks = owned_line_breaks;
        self.valid = true;
        return self.analysis();
    }

    fn analysis(self: *const Cache) Analysis {
        return .{
            .graphemes = self.graphemes,
            .line_breaks = self.line_breaks,
        };
    }

    fn freeCurrent(self: *Cache) void {
        if (!self.valid) return;
        self.allocator.free(self.line_breaks);
        self.allocator.free(self.graphemes);
        self.allocator.free(self.text);
        self.text = &.{};
        self.graphemes = &.{};
        self.line_breaks = &.{};
        self.valid = false;
    }
};
