//! Unicode bidirectional analysis and visual-order utilities.

const unicode = @import("../../../unicode.zig");

pub const Class = unicode.ExactBidiClass;
pub const BaseDirection = unicode.BidiBaseDirection;
pub const Paragraph = unicode.BidiParagraph;
pub const Scalar = @import("../../../unicode/bidi/paragraph.zig").Scalar;

pub const unicode_version = unicode.bidi_unicode_version;

pub const class = unicode.exactBidiClassForCodepoint;
pub const resolve = unicode.resolveBidiParagraph;
pub const mirroredCodepoint = unicode.mirroredCodepoint;

/// Resolve the first-strong paragraph direction as a full UAX #9 direction.
pub fn direction(text: []const u8) !BaseDirection {
    return switch (try unicode.paragraphDirection(text)) {
        .rtl => .rtl,
        else => .ltr,
    };
}
