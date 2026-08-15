//! Unicode bidirectional analysis and visual-order utilities.

const unicode = @import("../../../unicode.zig");

pub const Class = unicode.BidiClass;
pub const ExactClass = unicode.ExactBidiClass;
pub const BaseDirection = unicode.BidiBaseDirection;
pub const Paragraph = unicode.BidiParagraph;
pub const Map = unicode.BidiMap;
pub const MapItem = unicode.BidiMapItem;
pub const Run = unicode.BidiRun;

pub const unicode_version = unicode.bidi_unicode_version;

pub const class = unicode.bidiClassForCodepoint;
pub const exactClass = unicode.exactBidiClassForCodepoint;
pub const paragraphDirection = unicode.paragraphDirection;
pub const resolve = unicode.resolveBidiParagraph;
pub const buildMap = unicode.buildBidiMap;
pub const mirroredCodepoint = unicode.mirroredCodepoint;

/// Allocating operations are explicit so streaming analysis remains the
/// obvious default at call sites.
pub const collect = struct {
    pub const runs = unicode.itemizeBidiRuns;
    pub const visualRunOrder = unicode.visualOrderBidiRuns;
    pub const visualCodepoints = unicode.visualOrderCodepoints;
    pub const visualUtf8 = unicode.visualOrderUtf8;
};
