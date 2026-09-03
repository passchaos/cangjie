//! Public mutable-document storage contracts.
//!
//! `Document` is a text-core container: it owns bytes, hard-line summaries and
//! edit revisions, but no cursor, selection, history, widget or layout state.
//! Consumers can shape borrowed `ChunkIterator` slices without materializing
//! the complete document.

const implementation = @import("../../../text/document/root.zig");
const history = @import("../../../text/document/history.zig");

pub const Document = implementation.Document;
pub const ByteRange = implementation.ByteRange;
pub const Point = implementation.Point;
pub const EditSummary = implementation.EditSummary;
pub const Chunk = implementation.Chunk;
pub const ChunkIterator = implementation.ChunkIterator;
pub const Diagnostics = implementation.Diagnostics;
pub const Error = implementation.Error;
pub const max_piece_bytes = implementation.max_piece_bytes;
pub const History = history.History;
pub const HistoryError = history.Error;
pub const HistorySelection = history.Selection;
pub const HistoryRecordOptions = history.RecordOptions;
pub const HistoryReplay = history.Replay;
pub const HistoryReplaceResult = history.ReplaceResult;
pub const HistoryActionName = history.ActionName;
pub const HistoryDiagnostics = history.Diagnostics;

test {
    @import("std").testing.refAllDecls(@This());
}
