//! Intentional public surface for paragraph text geometry values.

const owner = @import("owner.zig");
const records = @import("records.zig");

pub const Direction = records.Direction;
pub const Affinity = records.Affinity;
pub const CaretPosition = records.CaretPosition;
pub const CaretGeometry = records.CaretGeometry;
pub const Cursor = records.Cursor;
pub const SelectionRange = records.SelectionRange;
pub const SelectionFragment = records.SelectionFragment;
pub const WordGeometry = records.WordGeometry;
pub const AccessibilityRun = records.AccessibilityRun;
pub const LineBreakKind = records.LineBreakKind;
pub const VisualCaretStop = records.VisualCaretStop;
pub const FontRun = records.FontRun;
pub const Grapheme = records.Grapheme;
pub const Span = records.Span;
pub const Line = records.Line;
pub const TextGeometry = owner.TextGeometry;
