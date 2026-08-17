//! Owned, platform-neutral text-run geometry records.
//!
//! These records intentionally describe text and layout only. Platform
//! accessibility adapters can translate them to AccessKit, UI Automation, or
//! another tree API without making Cangjie depend on one of those systems.

const std = @import("std");

const Face = @import("../../../font/face/root.zig").Face;
const paragraph_types = @import("../../types/paragraph.zig");

pub const Direction = enum {
    ltr,
    rtl,
};

/// Stable identity and font properties copied from one final paragraph run.
///
/// `run_index` is the original index in the `ParagraphLayout.runs` slice
/// supplied to the builder and remains a numeric identity inside this owner.
/// Do not use it to index a layout after that layout's reusable buffer changes.
/// The face itself remains caller-owned and must outlive consumers that inspect
/// it through this record.
pub const FontRun = struct {
    run_index: usize,
    font: *const Face,
    cascade_index: usize,
    font_size: f32,
};

/// Geometry for one extended grapheme cluster.
///
/// Positions are relative to the owning span's `bounds.x`, matching the
/// character-position convention used by platform text-run accessibility
/// APIs. Logical-order graphemes in an RTL span therefore normally have
/// decreasing positions.
pub const Grapheme = struct {
    byte_start: usize,
    byte_len: usize,
    inline_position: f32,
    width: f32,
    /// True when this grapheme's width partition came from an authored GDEF
    /// LigCaretList rather than equal division of a shaped glyph advance.
    authored_ligature_caret: bool = false,

    pub fn byteEnd(self: Grapheme) usize {
        return self.byte_start + self.byte_len;
    }
};

/// One logical-order text span with uniform layout ownership.
///
/// Spans split whenever the line, final font run, resolved bidi direction, or
/// optional style index changes. A span without `font_run` represents source
/// such as an inline-object anchor that deliberately has no font ownership.
pub const Span = struct {
    line_index: usize,
    font_run: ?FontRun,
    style_index: ?u32,
    direction: Direction,
    byte_start: usize,
    byte_len: usize,
    bounds: paragraph_types.TextRect,
    grapheme_start: usize,
    grapheme_len: usize,
    /// Range in `TextGeometry.word_starts`.
    ///
    /// Each value is a grapheme index relative to this span. Only UAX #29
    /// segments classified as words are listed.
    word_start_start: usize,
    word_start_len: usize,
    previous_on_line: ?usize = null,
    next_on_line: ?usize = null,

    pub fn byteEnd(self: Span) usize {
        return self.byte_start + self.byte_len;
    }

    pub fn graphemes(
        self: Span,
        geometry: TextGeometry,
    ) []const Grapheme {
        return geometry.graphemes[self.grapheme_start .. self.grapheme_start + self.grapheme_len];
    }

    pub fn wordStarts(
        self: Span,
        geometry: TextGeometry,
    ) []const usize {
        return geometry.word_starts[self.word_start_start .. self.word_start_start + self.word_start_len];
    }
};

/// Flat owner for paragraph text-run geometry.
///
/// The source UTF-8 is not copied. Byte ranges remain meaningful against the
/// text passed to the builder, while every geometry array is independently
/// owned and remains valid after the paragraph output buffer is reused.
pub const TextGeometry = struct {
    allocator: std.mem.Allocator,
    source_byte_len: usize,
    spans: []Span,
    graphemes: []Grapheme,
    word_starts: []usize,

    pub fn deinit(self: *TextGeometry) void {
        self.allocator.free(self.word_starts);
        self.allocator.free(self.graphemes);
        self.allocator.free(self.spans);
        self.* = undefined;
    }
};
