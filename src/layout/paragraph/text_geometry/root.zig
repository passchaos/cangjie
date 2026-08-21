//! Platform-neutral paragraph text-run geometry.

const build_impl = @import("build.zig");
const types = @import("types.zig");

pub const Direction = types.Direction;
pub const Affinity = types.Affinity;
pub const CaretPosition = types.CaretPosition;
pub const CaretGeometry = types.CaretGeometry;
pub const SelectionRange = types.SelectionRange;
pub const SelectionFragment = types.SelectionFragment;
pub const WordGeometry = types.WordGeometry;
pub const AccessibilityRun = types.AccessibilityRun;
pub const AccessibilityRunIterator = types.TextGeometry.AccessibilityRunIterator;
pub const LineBreakKind = types.LineBreakKind;
pub const SelectionError = @import("selection.zig").Error;
pub const VisualCaretStop = types.VisualCaretStop;
pub const FontRun = types.FontRun;
pub const Grapheme = types.Grapheme;
pub const Line = types.Line;
pub const Span = types.Span;
pub const TextGeometry = types.TextGeometry;
pub const Options = build_impl.Options;

pub const build = build_impl.build;
pub const buildStyled = build_impl.buildStyled;
