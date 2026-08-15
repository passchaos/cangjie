//! Bounded OpenType SVG document decoding and XML-structure validation.
//!
//! OpenType permits either cleartext XML or one gzip member. This module
//! validates only the document envelope needed by a renderer: a single SVG
//! root, balanced element tags, bounded decompression, and no trailing
//! top-level payload. Full SVG styling and geometry remain renderer concerns.

const std = @import("std");
const vort = @import("vort");
const xml = @import("xml.zig");

pub const Error = error{ BadSfnt, OutOfMemory };

const gzip_magic = [_]u8{ 0x1f, 0x8b };
const gzip_deflate_method = 8;
pub const max_document_size = 16 * 1024 * 1024;

pub const Resolved = struct {
    data: []const u8,
    allocator: ?std.mem.Allocator = null,

    pub fn deinit(self: *Resolved) void {
        if (self.allocator) |allocator| allocator.free(self.data);
        self.* = undefined;
    }
};

pub fn validate(
    allocator: std.mem.Allocator,
    document: []const u8,
) Error!void {
    var resolved = try resolve(allocator, document);
    defer resolved.deinit();
}

pub fn resolve(
    allocator: std.mem.Allocator,
    document: []const u8,
) Error!Resolved {
    const payload = stripUtf8Bom(document);
    if (payload.len == 0) return error.BadSfnt;
    if (payload.len > max_document_size and !isGzip(payload)) {
        return error.BadSfnt;
    }
    if (std.mem.startsWith(u8, payload, &gzip_magic)) {
        if (!isGzip(payload)) return error.BadSfnt;
        const decoded = vort.decodeGzipAllocLimited(
            allocator,
            payload,
            max_document_size,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.BadSfnt,
        };
        errdefer allocator.free(decoded);
        try validateCleartext(allocator, decoded);
        return .{ .data = decoded, .allocator = allocator };
    }
    try validateCleartext(allocator, payload);
    return .{ .data = payload };
}

fn validateCleartext(
    allocator: std.mem.Allocator,
    payload: []const u8,
) Error!void {
    if (payload.len == 0 or payload.len > max_document_size) {
        return error.BadSfnt;
    }
    return try xml.validate(allocator, payload);
}

fn stripUtf8Bom(document: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, document, "\xef\xbb\xbf"))
        document[3..]
    else
        document;
}

fn isGzip(document: []const u8) bool {
    // The trailer is eight bytes. Vort validates CRC32 and ISIZE and rejects
    // concatenated/trailing members for this single-document payload.
    return document.len >= 18 and
        std.mem.startsWith(u8, document, &gzip_magic) and
        document[2] == gzip_deflate_method;
}
