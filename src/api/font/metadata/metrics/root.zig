//! Horizontal, vertical, decoration, and script metric records.

const font = @import("../../../../font.zig");

pub const Decoration = font.FontDecorationMetrics;
pub const DecorationSource = font.FontDecorationMetricSource;
pub const ScaledDecoration = font.ScaledFontDecorationMetrics;
pub const Script = font.FontScriptMetrics;
pub const ScaledScript = font.ScaledFontScriptMetrics;

pub const Header = font.MetricHeaderInfo;
pub const Horizontal = font.HorizontalMetricInfo;
pub const Vertical = font.VerticalMetricInfo;
pub const VerticalMetrics = font.VerticalMetrics;
pub const VerticalOrigins = font.VerticalOriginInfo;
pub const VerticalOrigin = font.VerticalOriginMetric;

pub const DeviceWidths = font.HdmxInfo;
pub const DeviceWidthRecord = font.HdmxRecord;
pub const LinearThresholds = font.LtshInfo;
