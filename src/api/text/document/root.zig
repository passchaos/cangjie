//! Public mutable-document storage contracts.
//!
//! `Document` is a text-core container: it owns bytes, hard-line summaries and
//! edit revisions, but no cursor, selection, history, widget or layout state.
//! Consumers can shape borrowed `ChunkIterator` slices without materializing
//! the complete document.

const implementation = @import("../../../text/document/root.zig");

pub const Document = implementation.Document;
pub const ByteRange = implementation.ByteRange;
pub const Point = implementation.Point;
pub const EditSummary = implementation.EditSummary;
pub const Chunk = implementation.Chunk;
pub const ChunkIterator = implementation.ChunkIterator;
pub const Diagnostics = implementation.Diagnostics;
pub const Error = implementation.Error;
pub const max_piece_bytes = implementation.max_piece_bytes;

test {
    @import("std").testing.refAllDecls(@This());
}
