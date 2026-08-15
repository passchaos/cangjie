//! Text-buffer and editor-oriented helpers.

const buffer = @import("../../buffer.zig");
const editor = @import("../../editor.zig");

pub const TextBuffer = buffer.TextBuffer;
pub const DirtyRange = buffer.DirtyRange;
pub const LayoutConfig = buffer.LayoutConfig;
pub const Selection = buffer.Selection;
pub const CursorMoveDirection = buffer.CursorMoveDirection;
pub const VisibleByteRange = buffer.VisibleByteRange;
pub const VisibleLineRange = buffer.VisibleLineRange;

pub const TextEditor = editor.TextEditor;
pub const ImeComposition = editor.ImeComposition;
pub const LineColumn = editor.LineColumn;
pub const EditRecord = editor.EditRecord;
pub const DisplayWidthMode = editor.DisplayWidthMode;
pub const MultiCursorSet = editor.MultiCursorSet;
pub const SyntaxHighlightSet = editor.SyntaxHighlightSet;
pub const SyntaxHighlightSpan = editor.SyntaxHighlightSpan;
pub const SyntaxHighlightPalette = editor.SyntaxHighlightPalette;
pub const TerminalColumnOptions = editor.TerminalColumnOptions;
pub const ClipboardPayload = editor.ClipboardPayload;

pub const codepointDisplayWidth = editor.codepointDisplayWidth;
pub const highlightZigSyntax = editor.highlightZigSyntax;
