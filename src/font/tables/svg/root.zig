//! OpenType `SVG ` table directory, record, and payload ownership rules.

const std = @import("std");

const bin = @import("../../../binary.zig");
pub const document = @import("document.zig");

pub const Error = document.Error || error{EndOfStream};

pub const Table = struct {
    offset: usize,
    length: usize,
};

pub const Document = struct {
    start_glyph_id: u16,
    end_glyph_id: u16,
    data: []const u8,
};

pub const ResolvedDocument = struct {
    start_glyph_id: u16,
    end_glyph_id: u16,
    data: []const u8,
    allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *ResolvedDocument) void {
        if (self.allocator) |allocator| allocator.free(self.data);
        self.* = undefined;
    }

    /// Transfer a decoded gzip buffer to a longer-lived owner.
    ///
    /// Returns null when the document borrows the source SFNT bytes.
    pub fn takeOwnedData(self: *ResolvedDocument) ?[]u8 {
        if (self.allocator == null) return null;
        const data: []u8 = @constCast(self.data);
        self.allocator = null;
        self.data = &.{};
        return data;
    }
};

const DocumentList = struct {
    start: usize,
    length: usize,
    entry_count: usize,
    records_start: usize,
    document_data_start: usize,
};

const DocumentRecord = struct {
    start_glyph_id: u16,
    end_glyph_id: u16,
    document_offset: usize,
    document_length: usize,
};

const DocumentByteRange = struct {
    start: usize,
    end: usize,
};

pub fn validate(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: Table,
    glyph_count: u16,
) Error!void {
    const document_list = try documentList(data, table);
    const byte_ranges = try allocator.alloc(
        DocumentByteRange,
        document_list.entry_count,
    );
    defer allocator.free(byte_ranges);

    var previous_end_glyph_id: ?u16 = null;
    for (0..document_list.entry_count) |index| {
        const record = try readDocumentRecord(
            data,
            document_list.records_start + index * 12,
        );
        try validateDocumentRecord(
            record,
            document_list,
            glyph_count,
            &previous_end_glyph_id,
        );
        byte_ranges[index] = .{
            .start = record.document_offset,
            .end = record.document_offset + record.document_length,
        };
        const document_start =
            document_list.start + record.document_offset;
        try document.validate(
            allocator,
            data[document_start .. document_start + record.document_length],
        );
    }
    try validateDocumentByteRanges(byte_ranges);
}

/// Return raw table bytes after revalidating every advertised document.
pub fn rawDocument(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: Table,
    glyph_count: u16,
    glyph_id: u16,
) Error!?Document {
    const document_list = try documentList(data, table);

    var previous_end_glyph_id: ?u16 = null;
    var match: ?Document = null;
    for (0..document_list.entry_count) |index| {
        const record = try readDocumentRecord(
            data,
            document_list.records_start + index * 12,
        );
        try validateDocumentRecord(
            record,
            document_list,
            glyph_count,
            &previous_end_glyph_id,
        );
        try validateByteRangeAgainstPreviousRecords(
            data,
            document_list,
            record,
            index,
        );
        const document_start =
            document_list.start + record.document_offset;
        const payload =
            data[document_start .. document_start + record.document_length];
        // Validate all records, not just the requested one. The SFNT bytes are
        // borrowed and may have changed since parse time.
        try document.validate(allocator, payload);
        if (glyph_id >= record.start_glyph_id and
            glyph_id <= record.end_glyph_id)
        {
            match = .{
                .start_glyph_id = record.start_glyph_id,
                .end_glyph_id = record.end_glyph_id,
                .data = payload,
            };
        }
    }
    return match;
}

/// Resolve one matching document. Parsed renderer paths may skip the O(n²)
/// byte-ownership recheck because whole-table validation already proved it.
pub fn resolvedDocument(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: Table,
    glyph_count: u16,
    glyph_id: u16,
    revalidate: bool,
) Error!?ResolvedDocument {
    const document_list = try documentList(data, table);

    var previous_end_glyph_id: ?u16 = null;
    var match: ?ResolvedDocument = null;
    errdefer if (match) |*resolved| resolved.deinit();
    for (0..document_list.entry_count) |index| {
        const record = try readDocumentRecord(
            data,
            document_list.records_start + index * 12,
        );
        try validateDocumentRecord(
            record,
            document_list,
            glyph_count,
            &previous_end_glyph_id,
        );
        if (revalidate) {
            try validateByteRangeAgainstPreviousRecords(
                data,
                document_list,
                record,
                index,
            );
        }
        if (glyph_id < record.start_glyph_id or
            glyph_id > record.end_glyph_id)
        {
            continue;
        }
        const document_start =
            document_list.start + record.document_offset;
        var resolved = try document.resolve(
            allocator,
            data[document_start .. document_start + record.document_length],
        );
        match = .{
            .start_glyph_id = record.start_glyph_id,
            .end_glyph_id = record.end_glyph_id,
            .data = resolved.data,
            .allocator = resolved.allocator,
        };
        resolved.allocator = null;
        resolved.deinit();
        if (!revalidate) break;
    }
    return match;
}

fn documentList(data: []const u8, table: Table) Error!DocumentList {
    if (table.length < 10) return error.BadSfnt;
    const version = try bin.readU16At(data, table.offset);
    if (version != 0) return error.BadSfnt;
    const document_list_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 2));
    const reserved = try bin.readU32At(data, table.offset + 6);
    if (reserved != 0) return error.BadSfnt;

    // Child regions must follow the fixed table/list metadata so malicious
    // offsets cannot reinterpret headers or record arrays as XML.
    if (document_list_offset < 10) return error.BadSfnt;
    if (document_list_offset > table.length or
        2 > table.length - document_list_offset)
    {
        return error.BadSfnt;
    }

    const list_start = table.offset + document_list_offset;
    const list_length = table.length - document_list_offset;
    const entry_count = try bin.readU16At(data, list_start);
    const records_start = list_start + 2;
    const record_bytes = @as(usize, entry_count) * 12;
    if (record_bytes > list_length - 2) return error.BadSfnt;
    return .{
        .start = list_start,
        .length = list_length,
        .entry_count = entry_count,
        .records_start = records_start,
        .document_data_start = 2 + record_bytes,
    };
}

fn readDocumentRecord(
    data: []const u8,
    offset: usize,
) Error!DocumentRecord {
    return .{
        .start_glyph_id = try bin.readU16At(data, offset),
        .end_glyph_id = try bin.readU16At(data, offset + 2),
        .document_offset = @intCast(try bin.readU32At(data, offset + 4)),
        .document_length = @intCast(try bin.readU32At(data, offset + 8)),
    };
}

fn validateDocumentRecord(
    record: DocumentRecord,
    document_list: DocumentList,
    glyph_count: u16,
    previous_end_glyph_id: *?u16,
) Error!void {
    if (record.end_glyph_id < record.start_glyph_id) {
        return error.BadSfnt;
    }
    if (record.start_glyph_id >= glyph_count or
        record.end_glyph_id >= glyph_count)
    {
        return error.BadSfnt;
    }

    if (previous_end_glyph_id.*) |previous_end| {
        if (record.start_glyph_id <= previous_end) return error.BadSfnt;
    }
    previous_end_glyph_id.* = record.end_glyph_id;

    if (record.document_offset < document_list.document_data_start) {
        return error.BadSfnt;
    }
    if (record.document_length == 0) return error.BadSfnt;
    if (record.document_offset > document_list.length or
        record.document_length >
            document_list.length - record.document_offset)
    {
        return error.BadSfnt;
    }
}

fn validateDocumentByteRanges(ranges: []DocumentByteRange) Error!void {
    if (ranges.len < 2) return;
    std.mem.sort(DocumentByteRange, ranges, {}, struct {
        fn lessThan(
            _: void,
            lhs: DocumentByteRange,
            rhs: DocumentByteRange,
        ) bool {
            if (lhs.start == rhs.start) return lhs.end < rhs.end;
            return lhs.start < rhs.start;
        }
    }.lessThan);

    for (ranges[1..], 1..) |range, index| {
        const previous = ranges[index - 1];
        if (range.start < previous.end and
            (range.start != previous.start or range.end != previous.end))
        {
            // Exact sharing is legal. Partial overlap gives two records
            // incompatible XML document boundaries.
            return error.BadSfnt;
        }
    }
}

fn validateByteRangeAgainstPreviousRecords(
    data: []const u8,
    document_list: DocumentList,
    record: DocumentRecord,
    record_index: usize,
) Error!void {
    const current = DocumentByteRange{
        .start = record.document_offset,
        .end = record.document_offset + record.document_length,
    };
    for (0..record_index) |previous_index| {
        const previous_record = try readDocumentRecord(
            data,
            document_list.records_start + previous_index * 12,
        );
        const previous = DocumentByteRange{
            .start = previous_record.document_offset,
            .end = previous_record.document_offset +
                previous_record.document_length,
        };
        if (current.start < previous.end and previous.start < current.end and
            (current.start != previous.start or current.end != previous.end))
        {
            return error.BadSfnt;
        }
    }
}
