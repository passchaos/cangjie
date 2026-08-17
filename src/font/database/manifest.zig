//! Stable font database manifest records and TSV codec.

const std = @import("std");
const types = @import("types.zig");

pub const Entry = struct {
    family: []const u8,
    subfamily: []const u8,
    full_name: []const u8,
    postscript_name: []const u8,
    content_hash: u64 = 0,
    content_size: u64 = 0,
    weight: u16,
    stretch: u16,
    style: types.Style,
};

pub fn serializeManifest(allocator: std.mem.Allocator, entries: []const Entry) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();
    try writeManifest(&writer.writer, entries);
    return try writer.toOwnedSlice();
}

fn writeManifest(writer: *std.Io.Writer, entries: []const Entry) !void {
    try writer.writeAll("cangjie-font-manifest-v3\n");
    try writer.writeAll("family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle\n");
    for (entries) |entry| {
        try writeEscapedField(writer, entry.family);
        try writer.writeByte('\t');
        try writeEscapedField(writer, entry.subfamily);
        try writer.writeByte('\t');
        try writeEscapedField(writer, entry.full_name);
        try writer.writeByte('\t');
        try writeEscapedField(writer, entry.postscript_name);
        try writer.print("\t{x}\t{d}\t{d}\t{d}\t{s}\n", .{ entry.content_hash, entry.content_size, entry.weight, entry.stretch, fontStyleName(entry.style) });
    }
}

pub fn parseManifest(allocator: std.mem.Allocator, text: []const u8) ![]Entry {
    var lines = std.mem.splitScalar(u8, text, '\n');
    const magic = stripManifestLineEnding(lines.next() orelse return error.InvalidManifest);
    if (!std.mem.eql(u8, magic, "cangjie-font-manifest-v3")) return error.InvalidManifest;
    const header = stripManifestLineEnding(lines.next() orelse return error.InvalidManifest);
    if (!std.mem.eql(u8, header, "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle")) return error.InvalidManifest;

    var entries = std.ArrayList(Entry).empty;
    errdefer {
        for (entries.items) |entry| {
            allocator.free(entry.family);
            allocator.free(entry.subfamily);
            allocator.free(entry.full_name);
            allocator.free(entry.postscript_name);
        }
        entries.deinit(allocator);
    }

    while (lines.next()) |raw_line| {
        const line = stripManifestLineEnding(raw_line);
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        var raw: [9][]const u8 = undefined;
        for (&raw) |*field| {
            field.* = fields.next() orelse return error.InvalidManifest;
        }
        if (fields.next() != null) return error.InvalidManifest;

        const family = try unescapeManifestField(allocator, raw[0]);
        errdefer allocator.free(family);
        const subfamily = try unescapeManifestField(allocator, raw[1]);
        errdefer allocator.free(subfamily);
        const full_name = try unescapeManifestField(allocator, raw[2]);
        errdefer allocator.free(full_name);
        const postscript_name = try unescapeManifestField(allocator, raw[3]);
        errdefer allocator.free(postscript_name);

        const entry = Entry{
            .family = family,
            .subfamily = subfamily,
            .full_name = full_name,
            .postscript_name = postscript_name,
            .content_hash = parseManifestInt(u64, raw[4], 16) catch return error.InvalidManifest,
            .content_size = parseManifestInt(u64, raw[5], 10) catch return error.InvalidManifest,
            .weight = parseManifestWeight(raw[6]) catch return error.InvalidManifest,
            .stretch = parseManifestStretch(raw[7]) catch return error.InvalidManifest,
            .style = try parseStyle(raw[8]),
        };
        try entries.append(allocator, entry);
    }

    return try entries.toOwnedSlice(allocator);
}

pub fn writeManifestFile(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, entries: []const Entry) !void {
    const text = try serializeManifest(allocator, entries);
    defer allocator.free(text);
    try dir.writeFile(io, .{ .sub_path = path, .data = text, .flags = .{ .truncate = true } });
}

pub fn readManifestFile(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, limit: std.Io.Limit) ![]Entry {
    const text = try dir.readFileAlloc(io, path, allocator, limit);
    defer allocator.free(text);
    return try parseManifest(allocator, text);
}

pub fn manifestEntryMatchesBytes(entry: Entry, bytes: []const u8) bool {
    if (entry.content_size != 0 and entry.content_size != bytes.len) return false;
    if (entry.content_hash != 0 and entry.content_hash != bytesHash(bytes)) return false;
    return true;
}

fn writeEscapedField(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |byte| {
        switch (byte) {
            '\\' => try writer.writeAll("\\\\"),
            '\t' => try writer.writeAll("\\t"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            else => try writer.writeByte(byte),
        }
    }
}

fn stripManifestLineEnding(line: []const u8) []const u8 {
    return if (line.len != 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
}

fn parseManifestInt(comptime T: type, value: []const u8, base: u8) !T {
    if (value.len == 0) return error.InvalidManifest;
    return std.fmt.parseInt(T, value, base) catch error.InvalidManifest;
}

fn parseManifestWeight(value: []const u8) !u16 {
    const weight = try parseManifestInt(u16, value, 10);
    return if (weight >= 1 and weight <= 1000) weight else error.InvalidManifest;
}

fn parseManifestStretch(value: []const u8) !u16 {
    const stretch = try parseManifestInt(u16, value, 10);
    return if (stretch >= 1 and stretch <= 1000) stretch else error.InvalidManifest;
}

fn unescapeManifestField(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        const byte = value[index];
        if (byte != '\\') {
            try out.append(allocator, byte);
            continue;
        }
        index += 1;
        if (index >= value.len) return error.InvalidManifest;
        try out.append(allocator, switch (value[index]) {
            '\\' => '\\',
            't' => '\t',
            'n' => '\n',
            'r' => '\r',
            else => return error.InvalidManifest,
        });
    }
    return try out.toOwnedSlice(allocator);
}

fn fontStyleName(style: types.Style) []const u8 {
    return switch (style) {
        .normal => "normal",
        .italic => "italic",
        .oblique => "oblique",
    };
}

fn parseStyle(value: []const u8) !types.Style {
    if (std.mem.eql(u8, value, "normal")) return .normal;
    if (std.mem.eql(u8, value, "italic")) return .italic;
    if (std.mem.eql(u8, value, "oblique")) return .oblique;
    return error.InvalidManifest;
}

pub fn free(allocator: std.mem.Allocator, entries: []Entry) void {
    for (entries) |entry| {
        allocator.free(entry.family);
        allocator.free(entry.subfamily);
        allocator.free(entry.full_name);
        allocator.free(entry.postscript_name);
    }
    allocator.free(entries);
}

pub fn bytesHash(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}
