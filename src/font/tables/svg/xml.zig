//! Minimal XML envelope validation for OpenType SVG glyph documents.
//!
//! This is deliberately not a general XML parser. It proves that the decoded
//! payload has one SVG root and balanced markup before the renderer performs
//! its own style and geometry parsing.

const std = @import("std");

pub const Error = error{ BadSfnt, OutOfMemory };

pub fn validate(
    allocator: std.mem.Allocator,
    payload: []const u8,
) Error!void {
    var stack = std.ArrayList([]const u8).empty;
    defer stack.deinit(allocator);

    var cursor = try skipBeforeRootTrivia(payload, 0);
    var root_seen = false;
    while (cursor < payload.len) {
        if (payload[cursor] != '<') {
            const next_tag =
                std.mem.indexOfScalarPos(u8, payload, cursor, '<') orelse
                payload.len;
            if (stack.items.len == 0 and
                !isWhitespaceOnly(payload[cursor..next_tag]))
            {
                return error.BadSfnt;
            }
            cursor = next_tag;
            continue;
        }

        if (std.mem.startsWith(u8, payload[cursor..], "<!--")) {
            cursor = (try commentEnd(payload, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<?")) {
            cursor = (try processingInstructionEnd(payload, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<![CDATA[")) {
            if (stack.items.len == 0) return error.BadSfnt;
            cursor = (try cdataEnd(payload, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<!DOCTYPE")) {
            // A declaration belongs to the XML prolog. Accepting it after the
            // root starts would permit a second top-level construct.
            if (root_seen or stack.items.len != 0) return error.BadSfnt;
            cursor = (try declarationEnd(payload, cursor)) + 1;
            cursor = try skipBeforeRootTrivia(payload, cursor);
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<!")) {
            return error.BadSfnt;
        }

        const tag_end = try tagEnd(payload, cursor);
        const closing =
            cursor + 1 < payload.len and payload[cursor + 1] == '/';
        const name =
            tagName(payload, cursor, tag_end, closing) orelse
            return error.BadSfnt;
        if (closing) {
            if (stack.items.len == 0) return error.BadSfnt;
            const active_name = stack.items[stack.items.len - 1];
            stack.items.len -= 1;
            if (!std.mem.eql(u8, active_name, name)) return error.BadSfnt;
            cursor = tag_end + 1;
            if (stack.items.len == 0) {
                cursor = try skipTrailingTrivia(payload, cursor);
                if (cursor != payload.len) return error.BadSfnt;
                return;
            }
            continue;
        }

        if (stack.items.len == 0) {
            if (root_seen) return error.BadSfnt;
            if (!std.mem.eql(u8, localName(name), "svg")) {
                return error.BadSfnt;
            }
            root_seen = true;
        }
        if (tagSelfCloses(payload, cursor, tag_end)) {
            cursor = tag_end + 1;
            if (stack.items.len == 0) {
                cursor = try skipTrailingTrivia(payload, cursor);
                if (cursor != payload.len) return error.BadSfnt;
                return;
            }
        } else {
            try stack.append(allocator, name);
            cursor = tag_end + 1;
        }
    }

    if (!root_seen or stack.items.len != 0) return error.BadSfnt;
}

fn skipBeforeRootTrivia(
    document: []const u8,
    start: usize,
) Error!usize {
    var cursor = start;
    while (cursor < document.len) {
        cursor = skipWhitespace(document, cursor);
        if (std.mem.startsWith(u8, document[cursor..], "<?")) {
            cursor = (try processingInstructionEnd(document, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, document[cursor..], "<!--")) {
            cursor = (try commentEnd(document, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, document[cursor..], "<!DOCTYPE")) {
            cursor = (try declarationEnd(document, cursor)) + 1;
            continue;
        }
        return cursor;
    }
    return cursor;
}

fn skipTrailingTrivia(
    document: []const u8,
    start: usize,
) Error!usize {
    var cursor = start;
    while (cursor < document.len) {
        cursor = skipWhitespace(document, cursor);
        if (std.mem.startsWith(u8, document[cursor..], "<?")) {
            cursor = (try processingInstructionEnd(document, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, document[cursor..], "<!--")) {
            cursor = (try commentEnd(document, cursor)) + 1;
            continue;
        }
        return cursor;
    }
    return cursor;
}

fn skipWhitespace(document: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < document.len and isWhitespace(document[cursor])) {
        cursor += 1;
    }
    return cursor;
}

fn isWhitespaceOnly(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (!isWhitespace(byte)) return false;
    }
    return true;
}

fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
}

fn processingInstructionEnd(
    document: []const u8,
    start: usize,
) Error!usize {
    return std.mem.indexOfPos(u8, document, start + 2, "?>") orelse
        error.BadSfnt;
}

fn commentEnd(document: []const u8, start: usize) Error!usize {
    return (std.mem.indexOfPos(u8, document, start + 4, "-->") orelse
        return error.BadSfnt) + 2;
}

fn cdataEnd(document: []const u8, start: usize) Error!usize {
    return (std.mem.indexOfPos(
        u8,
        document,
        start + "<![CDATA[".len,
        "]]>",
    ) orelse return error.BadSfnt) + 2;
}

fn declarationEnd(document: []const u8, start: usize) Error!usize {
    var cursor = start + 2;
    var quote: ?u8 = null;
    var bracket_depth: usize = 0;
    while (cursor < document.len) : (cursor += 1) {
        const byte = document[cursor];
        if (quote) |active_quote| {
            if (byte == active_quote) quote = null;
            continue;
        }
        switch (byte) {
            '"', '\'' => quote = byte,
            '[' => bracket_depth += 1,
            ']' => if (bracket_depth != 0) {
                bracket_depth -= 1;
            },
            '>' => if (bracket_depth == 0) return cursor,
            else => {},
        }
    }
    return error.BadSfnt;
}

fn tagEnd(document: []const u8, start: usize) Error!usize {
    var cursor = start + 1;
    var quote: ?u8 = null;
    while (cursor < document.len) : (cursor += 1) {
        const byte = document[cursor];
        if (quote) |active_quote| {
            if (byte == active_quote) quote = null;
            continue;
        }
        switch (byte) {
            '"', '\'' => quote = byte,
            '>' => return cursor,
            else => {},
        }
    }
    return error.BadSfnt;
}

fn tagName(
    document: []const u8,
    tag_start: usize,
    tag_end: usize,
    closing: bool,
) ?[]const u8 {
    var cursor = tag_start + 1;
    if (closing) cursor += 1;
    if (cursor >= tag_end or !isNameByte(document[cursor])) return null;
    const name_start = cursor;
    while (cursor < tag_end and isNameByte(document[cursor])) {
        cursor += 1;
    }
    return document[name_start..cursor];
}

fn tagSelfCloses(
    document: []const u8,
    tag_start: usize,
    tag_end: usize,
) bool {
    var cursor = tag_end;
    while (cursor > tag_start + 1) {
        cursor -= 1;
        if (isWhitespace(document[cursor])) continue;
        return document[cursor] == '/';
    }
    return false;
}

fn localName(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, name, ':')) |colon|
        name[colon + 1 ..]
    else
        name;
}

fn isNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or
        byte == '_' or byte == '-' or byte == ':' or byte == '.';
}
