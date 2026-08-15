//! Width-independent paragraph boundary analysis.
//!
//! UAX #14 remains the required base. Optional language segmentation can add
//! soft boundaries, but cannot remove standard hard or soft opportunities.

const std = @import("std");

const dictionary_breaks = @import("../../text/segmentation/dictionary_breaks.zig");
const segmentation = @import("../../text/segmentation/root.zig");
const unicode = @import("../../unicode.zig");

/// Materialize the complete boundary set retained by a shaped paragraph.
///
/// One-shot layout calls this only when a dictionary requires merging; normal
/// paragraphs continue streaming UAX #14 through `LineBreakCursor`.
pub fn itemize(
    allocator: std.mem.Allocator,
    text: []const u8,
    graphemes: []const unicode.GraphemeCluster,
    dictionary: ?*const segmentation.WordBreakDictionary,
) ![]unicode.LineBreak {
    const base = try unicode.itemizeLineBreaks(allocator, text);
    if (dictionary == null) return base;
    defer allocator.free(base);
    return try dictionary_breaks.mergeLineBreaks(
        allocator,
        dictionary.?,
        text,
        graphemes,
        base,
    );
}
