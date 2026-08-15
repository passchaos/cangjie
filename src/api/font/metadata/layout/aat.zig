//! Apple Advanced Typography inspection records.
//!
//! AAT remains relevant for portable parsing and shaping of deployed fonts,
//! but its table-specific records stay nested rather than occupying the
//! primary OpenType metadata surface.

const font = @import("../../../../font.zig");

pub const Anchors = font.AnkrInfo;
pub const GlyphAnchors = font.AnkrGlyphAnchorsInfo;
pub const Anchor = font.AnkrAnchorInfo;

pub const Feature = font.FeatureNameInfo;
pub const FeatureSetting = font.FeatureSettingInfo;
pub const TrackTable = font.TrackTableInfo;
pub const Track = font.TrackInfo;
pub const TrackValue = font.TrackValueInfo;

pub const KernDialect = font.KernTableDialect;
pub const Kerx = font.KerxInfo;
pub const KerxSubtable = font.KerxSubtableInfo;
pub const KerxPair = font.KerxPairInfo;
pub const Morx = font.MorxInfo;
pub const MorxChain = font.MorxChainInfo;
pub const MorxFeature = font.MorxFeatureInfo;
pub const MorxSubtable = font.MorxSubtableInfo;
