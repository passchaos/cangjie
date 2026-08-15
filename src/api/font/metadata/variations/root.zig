//! OpenType variable-font axes, instances, deltas, and composite records.

const font = @import("../../../../font.zig");

pub const Axis = font.VariationAxis;
pub const Coordinate = font.VariationCoordinate;
pub const Instance = font.VariationInstance;
pub const StatAxis = font.StatDesignAxis;
pub const StatValue = font.StatAxisValue;
pub const StatCoordinate = font.StatAxisValueCoordinate;

pub const GlyphVariations = font.GvarInfo;
pub const GlyphVariation = font.GvarGlyphInfo;
pub const Tuple = font.GvarTupleInfo;
pub const PointDelta = font.GvarScaledPointDelta;
pub const PhantomPointDeltas = font.GvarPhantomPointDeltas;
pub const ControlValueVariations = font.CvarInfo;
pub const ControlValueTuple = font.CvarTupleInfo;

pub const HorizontalMetrics = font.HvarInfo;
pub const VerticalMetrics = font.VvarInfo;
pub const Metrics = font.MvarInfo;
pub const MetricValue = font.MvarValueRecordInfo;
pub const MetricIndexMap = font.MetricVariationIndexMapInfo;
pub const MetricIndex = font.MetricVariationIndexMapEntryInfo;
pub const Composite = font.VarcInfo;
