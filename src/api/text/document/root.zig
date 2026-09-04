//! Public mutable-document storage contracts.
//!
//! `Document` is a text-core container: it owns bytes, hard-line summaries and
//! edit revisions, but no cursor, selection, history, widget or layout state.
//! Consumers can shape borrowed `ChunkIterator` slices without materializing
//! the complete document, or retain an immutable `DocumentSnapshot` for
//! lock-free worker-thread analysis.

const implementation = @import("../../../text/document/root.zig");
const history = @import("../../../text/document/history.zig");
pub const span_transform = @import("../../../text/document/span_transform.zig");

pub const Document = implementation.Document;
pub const DocumentSnapshot = implementation.DocumentSnapshot;
pub const Identity = implementation.Identity;
pub const ByteRange = implementation.ByteRange;
pub const Point = implementation.Point;
pub const EditSummary = implementation.EditSummary;
pub const Chunk = implementation.Chunk;
pub const ChunkIterator = implementation.ChunkIterator;
pub const SnapshotChunkIterator = implementation.SnapshotChunkIterator;
pub const Diagnostics = implementation.Diagnostics;
pub const SnapshotDiagnostics = implementation.SnapshotDiagnostics;
pub const Error = implementation.Error;
pub const max_piece_bytes = implementation.max_piece_bytes;
pub const History = history.History;
pub const HistoryError = history.Error;
pub const HistorySelection = history.Selection;
pub const HistoryRecordOptions = history.RecordOptions;
pub const HistoryReplayOptions = history.ReplayOptions;
pub const HistoryCommitFn = history.CommitFn;
pub const HistoryReplay = history.Replay;
pub const HistoryReplaceResult = history.ReplaceResult;
pub const HistoryActionName = history.ActionName;
pub const HistoryDiagnostics = history.Diagnostics;
pub const SpanEdit = span_transform.Edit;
pub const SpanTransformOptions = span_transform.Options;
pub const SpanTransformResult = span_transform.Result;
pub const SpanTransformError = span_transform.Error;
pub const transformSpans = span_transform.transform;
pub const transformedSpanCount = span_transform.transformedCount;

test {
    @import("std").testing.refAllDecls(@This());
}
