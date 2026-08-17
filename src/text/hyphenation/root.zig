//! Optional Liang-pattern hyphenation over UTF-8 words.
//!
//! Dictionaries accept the plain token format used by tex-hyphen, libhnj, and
//! MuPDF's `resources/hyphen`: priority digits are interleaved with Unicode
//! pattern scalars, and `-` marks explicit exception boundaries. Results use
//! UTF-8 byte offsets, matching Cangjie's paragraph coordinate system.

const std = @import("std");
const model = @import("model.zig");
const parser = @import("parser.zig");
const runtime = @import("runtime.zig");

pub const Dictionary = struct {
    /// Source-visible concrete storage; applications use the methods below
    /// rather than depending on its evolving fields.
    implementation: model.Storage,

    pub const Options = model.Options;
    pub const Mapping = model.Mapping;
    pub const InitError = parser.Error;

    pub fn init(
        allocator: std.mem.Allocator,
        patterns: []const u8,
        exceptions: []const u8,
        options: Options,
    ) InitError!Dictionary {
        return .{
            .implementation = try parser.init(
                allocator,
                patterns,
                exceptions,
                options,
            ),
        };
    }

    /// Parse a pattern file with an optional blank-line exception section.
    pub fn initCombined(
        allocator: std.mem.Allocator,
        data: []const u8,
        options: Options,
    ) InitError!Dictionary {
        return .{
            .implementation = try parser.initCombined(
                allocator,
                data,
                options,
            ),
        };
    }

    pub fn deinit(self: *Dictionary) void {
        self.implementation.deinit();
        self.* = undefined;
    }

    /// Append valid hyphen boundaries for one word.
    ///
    /// `word` must be valid UTF-8. Returned boundaries are byte offsets within
    /// `word`, sorted in source order. The output list is cleared first.
    pub fn hyphenate(
        self: *const Dictionary,
        allocator: std.mem.Allocator,
        word: []const u8,
        out: *std.ArrayList(usize),
    ) (std.mem.Allocator.Error || error{InvalidUtf8})!void {
        return runtime.hyphenate(
            &self.implementation,
            allocator,
            word,
            out,
        );
    }
};

test {
    _ = @import("tests.zig");
}
