//! Paragraph-tailored line-break opportunities.
//!
//! Unicode's public UAX #14 `Break` remains standards-only. This internal
//! record adds whether taking one optional boundary must draw an automatic
//! hyphen, keeping language tailoring out of the Unicode iterator contract.

const unicode = @import("../../unicode.zig");

pub const Opportunity = struct {
    byte_offset: usize,
    kind: unicode.LineBreakKind,
    automatic_hyphen: bool = false,
    /// A boundary introduced at a reusable grapheme edge by paragraph policy,
    /// rather than Unicode/dictionary analysis.
    arbitrary: bool = false,
};

pub fn fromUnicode(value: unicode.LineBreak) Opportunity {
    return .{
        .byte_offset = value.byte_offset,
        .kind = value.kind,
    };
}
