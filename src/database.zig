const std = @import("std");
const builtin = @import("builtin");
const Font = @import("font.zig").Font;
const layout = @import("layout.zig");

pub const FontStyle = enum {
    normal,
    italic,
    oblique,
};

pub const FontFaceInfo = struct {
    font: *const Font,
    family: []const u8,
    subfamily: []const u8,
    full_name: []const u8,
    postscript_name: []const u8,
    weight: u16 = 400,
    stretch: u16 = 100,
    style: FontStyle = .normal,
};

pub const FontQuery = struct {
    family: []const u8,
    postscript_name: ?[]const u8 = null,
    weight: u16 = 400,
    stretch: u16 = 100,
    style: FontStyle = .normal,
};

pub const FontManifestEntry = struct {
    family: []const u8,
    subfamily: []const u8,
    full_name: []const u8,
    postscript_name: []const u8,
    content_hash: u64 = 0,
    content_size: u64 = 0,
    weight: u16,
    stretch: u16,
    style: FontStyle,
};

pub fn serializeManifest(allocator: std.mem.Allocator, entries: []const FontManifestEntry) ![]u8 {
    var writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer writer.deinit();
    try writeManifest(&writer.writer, entries);
    return try writer.toOwnedSlice();
}

pub fn writeManifest(writer: *std.Io.Writer, entries: []const FontManifestEntry) !void {
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

pub fn parseManifest(allocator: std.mem.Allocator, text: []const u8) ![]FontManifestEntry {
    var lines = std.mem.splitScalar(u8, text, '\n');
    const magic = stripManifestLineEnding(lines.next() orelse return error.InvalidManifest);
    if (!std.mem.eql(u8, magic, "cangjie-font-manifest-v3")) return error.InvalidManifest;
    const header = stripManifestLineEnding(lines.next() orelse return error.InvalidManifest);
    if (!std.mem.eql(u8, header, "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle")) return error.InvalidManifest;

    var entries = std.ArrayList(FontManifestEntry).empty;
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

        const entry = FontManifestEntry{
            .family = family,
            .subfamily = subfamily,
            .full_name = full_name,
            .postscript_name = postscript_name,
            .content_hash = parseManifestInt(u64, raw[4], 16) catch return error.InvalidManifest,
            .content_size = parseManifestInt(u64, raw[5], 10) catch return error.InvalidManifest,
            .weight = parseManifestWeight(raw[6]) catch return error.InvalidManifest,
            .stretch = parseManifestStretch(raw[7]) catch return error.InvalidManifest,
            .style = try parseFontStyle(raw[8]),
        };
        try entries.append(allocator, entry);
    }

    return try entries.toOwnedSlice(allocator);
}

pub fn writeManifestFile(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, entries: []const FontManifestEntry) !void {
    const text = try serializeManifest(allocator, entries);
    defer allocator.free(text);
    try dir.writeFile(io, .{ .sub_path = path, .data = text, .flags = .{ .truncate = true } });
}

pub fn readManifestFile(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, limit: std.Io.Limit) ![]FontManifestEntry {
    const text = try dir.readFileAlloc(io, path, allocator, limit);
    defer allocator.free(text);
    return try parseManifest(allocator, text);
}

pub fn manifestEntryMatchesBytes(entry: FontManifestEntry, bytes: []const u8) bool {
    if (entry.content_size != 0 and entry.content_size != bytes.len) return false;
    if (entry.content_hash != 0 and entry.content_hash != fontBytesHash(bytes)) return false;
    return true;
}

pub const FontSource = union(enum) {
    directory: Directory,
    file: File,

    pub const Directory = struct {
        path: []const u8,
        recursive: bool = true,
        ignore_missing: bool = true,
    };

    pub const File = struct {
        path: []const u8,
        ignore_missing: bool = true,
    };
};

pub fn defaultSystemFontSources() []const FontSource {
    return defaultSystemFontSourcesForOs(builtin.os.tag);
}

pub fn defaultSystemFontSourcesForOs(os_tag: std.Target.Os.Tag) []const FontSource {
    return switch (os_tag) {
        .macos => &.{
            .{ .directory = .{ .path = "/System/Library/Fonts", .recursive = true, .ignore_missing = true } },
            .{ .directory = .{ .path = "/Library/Fonts", .recursive = true, .ignore_missing = true } },
        },
        .linux => &.{
            .{ .directory = .{ .path = "/usr/share/fonts", .recursive = true, .ignore_missing = true } },
            .{ .directory = .{ .path = "/usr/local/share/fonts", .recursive = true, .ignore_missing = true } },
        },
        .windows => &.{
            .{ .directory = .{ .path = "C:\\Windows\\Fonts", .recursive = true, .ignore_missing = true } },
        },
        else => &.{},
    };
}

pub fn userFontSourcesForOs(home_path: []const u8, os_tag: std.Target.Os.Tag, buffer: []FontSource, path_buffer: []u8) ![]const FontSource {
    var count: usize = 0;
    var path_offset: usize = 0;
    switch (os_tag) {
        .macos => {
            try appendUserFontSource(buffer, &count, path_buffer, &path_offset, home_path, "Library/Fonts");
        },
        .linux => {
            try appendUserFontSource(buffer, &count, path_buffer, &path_offset, home_path, ".local/share/fonts");
            try appendUserFontSource(buffer, &count, path_buffer, &path_offset, home_path, ".fonts");
        },
        else => {},
    }
    return buffer[0..count];
}

pub fn combinedSystemFontSourcesForOs(home_path: ?[]const u8, os_tag: std.Target.Os.Tag, buffer: []FontSource, path_buffer: []u8) ![]const FontSource {
    var count: usize = 0;
    const system_sources = defaultSystemFontSourcesForOs(os_tag);
    if (system_sources.len > buffer.len) return error.NoSpaceLeft;
    for (system_sources) |source| {
        buffer[count] = source;
        count += 1;
    }
    if (home_path) |home| {
        const user_sources = try userFontSourcesForOs(home, os_tag, buffer[count..], path_buffer);
        count += user_sources.len;
    }
    return buffer[0..count];
}

pub const FontDatabase = struct {
    allocator: std.mem.Allocator,
    faces: std.ArrayList(FontFaceInfo) = .empty,
    owned_fonts: std.ArrayList(*OwnedFont) = .empty,

    pub fn init(allocator: std.mem.Allocator) FontDatabase {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FontDatabase) void {
        for (self.faces.items) |face| {
            self.allocator.free(face.family);
            self.allocator.free(face.subfamily);
            self.allocator.free(face.full_name);
            self.allocator.free(face.postscript_name);
        }
        for (self.owned_fonts.items) |owned| {
            owned.font.deinit();
            self.allocator.free(owned.bytes);
            self.allocator.destroy(owned);
        }
        self.owned_fonts.deinit(self.allocator);
        self.faces.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addFont(self: *FontDatabase, font: *const Font) !usize {
        var scratch: [256]u8 = undefined;
        const family = try self.allocator.dupe(u8, (try font.familyName(&scratch)) orelse "Unknown");
        errdefer self.allocator.free(family);
        const subfamily = try self.allocator.dupe(u8, (try font.subfamilyName(&scratch)) orelse "Regular");
        errdefer self.allocator.free(subfamily);
        const full_name = try self.allocator.dupe(u8, (try font.fullName(&scratch)) orelse family);
        errdefer self.allocator.free(full_name);
        const postscript_name = try self.allocator.dupe(u8, (try font.nameString(.postscript_name, &scratch)) orelse "");
        errdefer self.allocator.free(postscript_name);
        const attributes = try font.styleAttributes();
        const weight = if (font.hasStyleAttributes()) attributes.weight else inferWeight(subfamily);
        const stretch = if (font.hasStyleAttributes()) widthClassToStretch(attributes.width) else 100;
        const style = if (attributes.italic) .italic else inferStyle(subfamily);
        if (self.findDuplicateFace(family, subfamily, full_name, postscript_name, weight, stretch, style)) |index| {
            self.allocator.free(family);
            self.allocator.free(subfamily);
            self.allocator.free(full_name);
            self.allocator.free(postscript_name);
            return index;
        }

        const face = FontFaceInfo{
            .font = font,
            .family = family,
            .subfamily = subfamily,
            .full_name = full_name,
            .postscript_name = postscript_name,
            .weight = weight,
            .stretch = stretch,
            .style = style,
        };
        try self.faces.append(self.allocator, face);
        return self.faces.items.len - 1;
    }

    pub fn addFontBytes(self: *FontDatabase, bytes: []const u8) !usize {
        return try self.addFontFaceBytes(bytes, 0);
    }

    pub fn addFontCollectionBytes(self: *FontDatabase, bytes: []const u8) !usize {
        const count = try Font.faceCount(bytes);
        var added: usize = 0;
        errdefer {
            while (added > 0) : (added -= 1) {
                self.removeLastOwnedFace();
            }
        }
        for (0..count) |face_index| {
            const before = self.faces.items.len;
            _ = try self.addFontFaceBytes(bytes, face_index);
            if (self.faces.items.len > before) added += 1;
        }
        return added;
    }

    pub fn addFontFile(self: *FontDatabase, io: std.Io, dir: std.Io.Dir, path: []const u8, limit: std.Io.Limit) !usize {
        const bytes = try dir.readFileAlloc(io, path, self.allocator, limit);
        defer self.allocator.free(bytes);
        return try self.addFontBytes(bytes);
    }

    pub fn addFontCollectionFile(self: *FontDatabase, io: std.Io, dir: std.Io.Dir, path: []const u8, limit: std.Io.Limit) !usize {
        const bytes = try dir.readFileAlloc(io, path, self.allocator, limit);
        defer self.allocator.free(bytes);
        return try self.addFontCollectionBytes(bytes);
    }

    pub fn scanFontDir(self: *FontDatabase, io: std.Io, dir: std.Io.Dir, limit: std.Io.Limit) !usize {
        var iterator = dir.iterate();
        var added: usize = 0;
        while (try iterator.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!isSupportedFontPath(entry.name)) continue;
            if (isCollectionPath(entry.name)) {
                added += try self.addFontCollectionFile(io, dir, entry.name, limit);
            } else {
                const before = self.faces.items.len;
                _ = try self.addFontFile(io, dir, entry.name, limit);
                if (self.faces.items.len > before) added += 1;
            }
        }
        return added;
    }

    pub fn scanFontTree(self: *FontDatabase, io: std.Io, dir: std.Io.Dir, limit: std.Io.Limit) !usize {
        var walker = try dir.walk(self.allocator);
        defer walker.deinit();
        var added: usize = 0;
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!isSupportedFontPath(entry.basename)) continue;
            if (isCollectionPath(entry.basename)) {
                added += try self.addFontCollectionFile(io, entry.dir, entry.basename, limit);
            } else {
                const before = self.faces.items.len;
                _ = try self.addFontFile(io, entry.dir, entry.basename, limit);
                if (self.faces.items.len > before) added += 1;
            }
        }
        return added;
    }

    pub fn scanFontSources(self: *FontDatabase, io: std.Io, root: std.Io.Dir, sources: []const FontSource, limit: std.Io.Limit) !usize {
        var added: usize = 0;
        for (sources) |source| {
            switch (source) {
                .directory => |directory| {
                    var dir = root.openDir(io, directory.path, .{ .iterate = true }) catch |err| switch (err) {
                        error.FileNotFound => {
                            if (directory.ignore_missing) continue;
                            return err;
                        },
                        else => return err,
                    };
                    defer dir.close(io);
                    added += if (directory.recursive)
                        try self.scanFontTree(io, dir, limit)
                    else
                        try self.scanFontDir(io, dir, limit);
                },
                .file => |file| {
                    if (!isSupportedFontPath(file.path)) {
                        if (file.ignore_missing) continue;
                        return error.UnsupportedFontSource;
                    }
                    if (isCollectionPath(file.path)) {
                        added += self.addFontCollectionFile(io, root, file.path, limit) catch |err| switch (err) {
                            error.FileNotFound => {
                                if (file.ignore_missing) continue;
                                return err;
                            },
                            else => return err,
                        };
                    } else {
                        const before = self.faces.items.len;
                        _ = self.addFontFile(io, root, file.path, limit) catch |err| switch (err) {
                            error.FileNotFound => {
                                if (file.ignore_missing) continue;
                                return err;
                            },
                            else => return err,
                        };
                        if (self.faces.items.len > before) added += 1;
                    }
                },
            }
        }
        return added;
    }

    fn addFontFaceBytes(self: *FontDatabase, bytes: []const u8, face_index: usize) !usize {
        const content_hash = fontBytesHash(bytes);
        if (self.findOwnedFaceByHash(content_hash, face_index)) |index| return index;
        const owned_bytes = try self.allocator.dupe(u8, bytes);
        errdefer self.allocator.free(owned_bytes);
        const owned = try self.allocator.create(OwnedFont);
        errdefer self.allocator.destroy(owned);
        owned.* = .{ .bytes = owned_bytes, .font = try Font.parseFace(self.allocator, owned_bytes, face_index), .content_hash = content_hash, .face_index = face_index };
        errdefer owned.font.deinit();

        try self.owned_fonts.append(self.allocator, owned);
        errdefer {
            _ = self.owned_fonts.pop();
            owned.font.deinit();
            self.allocator.free(owned.bytes);
            self.allocator.destroy(owned);
        }
        const index = try self.addFont(&owned.font);
        if (self.faces.items[index].font != &owned.font) {
            _ = self.owned_fonts.pop();
            owned.font.deinit();
            self.allocator.free(owned.bytes);
            self.allocator.destroy(owned);
        }
        return index;
    }

    fn removeLastOwnedFace(self: *FontDatabase) void {
        if (self.faces.items.len != 0) {
            const face = self.faces.pop().?;
            self.allocator.free(face.family);
            self.allocator.free(face.subfamily);
            self.allocator.free(face.full_name);
            self.allocator.free(face.postscript_name);
        }
        if (self.owned_fonts.items.len != 0) {
            const owned = self.owned_fonts.pop().?;
            owned.font.deinit();
            self.allocator.free(owned.bytes);
            self.allocator.destroy(owned);
        }
    }

    pub fn match(self: *const FontDatabase, query: FontQuery) ?*const FontFaceInfo {
        if (query.postscript_name) |postscript_name| {
            for (self.faces.items) |*face| {
                if (face.postscript_name.len != 0 and std.ascii.eqlIgnoreCase(face.postscript_name, postscript_name)) return face;
            }
        }
        var best: ?usize = null;
        var best_score: u32 = std.math.maxInt(u32);
        for (self.faces.items, 0..) |face, index| {
            if (!familyMatches(face.family, query.family)) continue;
            const score = matchScore(face, query);
            if (score < best_score) {
                best = index;
                best_score = score;
            }
        }
        if (best) |index| return &self.faces.items[index];
        return null;
    }

    pub fn buildCascadeForText(self: *const FontDatabase, allocator: std.mem.Allocator, query: FontQuery, text: []const u8) ![]*const Font {
        try validateCascadeTextInput(text);

        var fonts = std.ArrayList(*const Font).empty;
        errdefer fonts.deinit(allocator);

        const primary = self.match(query);
        if (primary) |face| try appendUniqueFont(allocator, &fonts, face.font);

        var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (it.nextCodepoint()) |codepoint| {
            if (fontListCovers(fonts.items, codepoint)) continue;
            if (self.findFallbackFace(codepoint, query)) |fallback| {
                try appendUniqueFont(allocator, &fonts, fallback.font);
            }
        }

        return try fonts.toOwnedSlice(allocator);
    }

    pub fn cascadeForText(self: *const FontDatabase, allocator: std.mem.Allocator, query: FontQuery, text: []const u8) !layout.FontCascade {
        return .{ .fonts = try self.buildCascadeForText(allocator, query, text) };
    }

    pub fn familyCount(self: *const FontDatabase) usize {
        var count: usize = 0;
        for (self.faces.items, 0..) |face, index| {
            var seen = false;
            for (self.faces.items[0..index]) |previous| {
                if (familyMatches(previous.family, face.family)) {
                    seen = true;
                    break;
                }
            }
            if (!seen) count += 1;
        }
        return count;
    }

    pub fn familyNames(self: *const FontDatabase, allocator: std.mem.Allocator) ![][]const u8 {
        var names = std.ArrayList([]const u8).empty;
        errdefer names.deinit(allocator);
        for (self.faces.items) |face| {
            var seen = false;
            for (names.items) |name| {
                if (familyMatches(name, face.family)) {
                    seen = true;
                    break;
                }
            }
            if (!seen) try names.append(allocator, face.family);
        }
        return try names.toOwnedSlice(allocator);
    }

    pub fn faceIndicesForFamily(self: *const FontDatabase, allocator: std.mem.Allocator, family: []const u8) ![]usize {
        var indices = std.ArrayList(usize).empty;
        errdefer indices.deinit(allocator);
        for (self.faces.items, 0..) |face, index| {
            if (familyMatches(face.family, family)) try indices.append(allocator, index);
        }
        return try indices.toOwnedSlice(allocator);
    }

    pub fn manifest(self: *const FontDatabase, allocator: std.mem.Allocator) ![]FontManifestEntry {
        const entries = try allocator.alloc(FontManifestEntry, self.faces.items.len);
        var initialized: usize = 0;
        errdefer {
            for (entries[0..initialized]) |entry| {
                allocator.free(entry.family);
                allocator.free(entry.subfamily);
                allocator.free(entry.full_name);
                allocator.free(entry.postscript_name);
            }
            allocator.free(entries);
        }
        for (self.faces.items, 0..) |face, index| {
            const family = try allocator.dupe(u8, face.family);
            errdefer allocator.free(family);
            const subfamily = try allocator.dupe(u8, face.subfamily);
            errdefer allocator.free(subfamily);
            const full_name = try allocator.dupe(u8, face.full_name);
            errdefer allocator.free(full_name);
            const postscript_name = try allocator.dupe(u8, face.postscript_name);
            errdefer allocator.free(postscript_name);

            entries[index] = .{
                .family = family,
                .subfamily = subfamily,
                .full_name = full_name,
                .postscript_name = postscript_name,
                .content_hash = self.contentHashForFont(face.font),
                .content_size = self.contentSizeForFont(face.font),
                .weight = face.weight,
                .stretch = face.stretch,
                .style = face.style,
            };
            initialized += 1;
        }
        return entries;
    }

    pub fn freeManifest(allocator: std.mem.Allocator, entries: []FontManifestEntry) void {
        for (entries) |entry| {
            allocator.free(entry.family);
            allocator.free(entry.subfamily);
            allocator.free(entry.full_name);
            allocator.free(entry.postscript_name);
        }
        allocator.free(entries);
    }

    fn findFallbackFace(self: *const FontDatabase, codepoint: u21, query: FontQuery) ?*const FontFaceInfo {
        var best: ?usize = null;
        var best_score: u32 = std.math.maxInt(u32);
        for (self.faces.items, 0..) |face, index| {
            if (!fontCovers(face.font, codepoint)) continue;
            const score = matchScore(face, query) + if (familyMatches(face.family, query.family)) @as(u32, 0) else 5000;
            if (score < best_score) {
                best = index;
                best_score = score;
            }
        }
        if (best) |index| return &self.faces.items[index];
        return null;
    }

    fn findDuplicateFace(self: *const FontDatabase, family: []const u8, subfamily: []const u8, full_name: []const u8, postscript_name: []const u8, weight: u16, stretch: u16, style: FontStyle) ?usize {
        for (self.faces.items, 0..) |face, index| {
            if (postscript_name.len != 0 and face.postscript_name.len != 0) {
                if (std.ascii.eqlIgnoreCase(face.postscript_name, postscript_name) and face.weight == weight and face.stretch == stretch and face.style == style) return index;
                continue;
            }
            if (!std.ascii.eqlIgnoreCase(face.family, family)) continue;
            if (!std.ascii.eqlIgnoreCase(face.subfamily, subfamily)) continue;
            if (!std.ascii.eqlIgnoreCase(face.full_name, full_name)) continue;
            if (face.weight != weight or face.stretch != stretch or face.style != style) continue;
            return index;
        }
        return null;
    }

    fn findOwnedFaceByHash(self: *const FontDatabase, content_hash: u64, face_index: usize) ?usize {
        for (self.owned_fonts.items) |owned| {
            if (owned.content_hash != content_hash or owned.face_index != face_index) continue;
            for (self.faces.items, 0..) |face, index| {
                if (face.font == &owned.font) return index;
            }
        }
        return null;
    }

    fn contentHashForFont(self: *const FontDatabase, font: *const Font) u64 {
        for (self.owned_fonts.items) |owned| {
            if (&owned.font == font) return owned.content_hash;
        }
        return 0;
    }

    fn contentSizeForFont(self: *const FontDatabase, font: *const Font) u64 {
        for (self.owned_fonts.items) |owned| {
            if (&owned.font == font) return owned.bytes.len;
        }
        return 0;
    }
};

const OwnedFont = struct {
    bytes: []u8,
    font: Font,
    content_hash: u64,
    face_index: usize,
};

fn fontBytesHash(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn appendUniqueFont(allocator: std.mem.Allocator, fonts: *std.ArrayList(*const Font), font: *const Font) !void {
    for (fonts.items) |existing| {
        if (existing == font) return;
    }
    try fonts.append(allocator, font);
}

fn fontListCovers(fonts: []const *const Font, codepoint: u21) bool {
    for (fonts) |font| {
        if (fontCovers(font, codepoint)) return true;
    }
    return false;
}

fn fontCovers(font: *const Font, codepoint: u21) bool {
    return (font.glyphIndex(codepoint) catch 0) != 0;
}

fn validateCascadeTextInput(text: []const u8) !void {
    // FontDatabase fallback construction also walks public UTF-8 text with
    // Utf8Iterator. Validate before allocating the cascade list or probing
    // fonts so malformed input cannot be silently truncated at the first bad
    // byte while still returning a plausible fallback stack.
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
}

fn isSupportedFontPath(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".ttf") or
        std.ascii.endsWithIgnoreCase(path, ".otf") or
        std.ascii.endsWithIgnoreCase(path, ".ttc") or
        std.ascii.endsWithIgnoreCase(path, ".otc");
}

fn isCollectionPath(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".ttc") or
        std.ascii.endsWithIgnoreCase(path, ".otc");
}

fn appendUserFontSource(buffer: []FontSource, count: *usize, path_buffer: []u8, path_offset: *usize, home_path: []const u8, relative_path: []const u8) !void {
    if (count.* >= buffer.len) return error.NoSpaceLeft;
    const need_separator = home_path.len != 0 and home_path[home_path.len - 1] != '/';
    const path_len = home_path.len + @intFromBool(need_separator) + relative_path.len;
    if (path_len > path_buffer.len - path_offset.*) return error.NoSpaceLeft;
    const start = path_offset.*;
    @memcpy(path_buffer[start..][0..home_path.len], home_path);
    var cursor = start + home_path.len;
    if (need_separator) {
        path_buffer[cursor] = '/';
        cursor += 1;
    }
    @memcpy(path_buffer[cursor..][0..relative_path.len], relative_path);
    cursor += relative_path.len;
    buffer[count.*] = .{ .directory = .{ .path = path_buffer[start..cursor], .recursive = true, .ignore_missing = true } };
    count.* += 1;
    path_offset.* = cursor;
}

fn familyMatches(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn matchScore(face: FontFaceInfo, query: FontQuery) u32 {
    var score: u32 = 0;
    score += numericDistance(face.weight, query.weight);
    score += numericDistance(face.stretch, query.stretch) * 2;
    if (face.style != query.style) score += 1000;
    return score;
}

fn numericDistance(a: u16, b: u16) u32 {
    return if (a > b) a - b else b - a;
}

fn widthClassToStretch(width_class: u16) u16 {
    return switch (width_class) {
        1 => 50,
        2 => 62,
        3 => 75,
        4 => 87,
        5 => 100,
        6 => 112,
        7 => 125,
        8 => 150,
        9 => 200,
        else => 100,
    };
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

fn fontStyleName(style: FontStyle) []const u8 {
    return switch (style) {
        .normal => "normal",
        .italic => "italic",
        .oblique => "oblique",
    };
}

fn parseFontStyle(value: []const u8) !FontStyle {
    if (std.mem.eql(u8, value, "normal")) return .normal;
    if (std.mem.eql(u8, value, "italic")) return .italic;
    if (std.mem.eql(u8, value, "oblique")) return .oblique;
    return error.InvalidManifest;
}

fn inferWeight(subfamily: []const u8) u16 {
    if (containsIgnoreCase(subfamily, "Thin")) return 100;
    if (containsIgnoreCase(subfamily, "ExtraLight") or containsIgnoreCase(subfamily, "UltraLight")) return 200;
    if (containsIgnoreCase(subfamily, "Light")) return 300;
    if (containsIgnoreCase(subfamily, "Medium")) return 500;
    if (containsIgnoreCase(subfamily, "SemiBold") or containsIgnoreCase(subfamily, "DemiBold")) return 600;
    if (containsIgnoreCase(subfamily, "Bold")) return 700;
    if (containsIgnoreCase(subfamily, "ExtraBold") or containsIgnoreCase(subfamily, "UltraBold")) return 800;
    if (containsIgnoreCase(subfamily, "Black") or containsIgnoreCase(subfamily, "Heavy")) return 900;
    return 400;
}

fn inferStyle(subfamily: []const u8) FontStyle {
    if (containsIgnoreCase(subfamily, "Italic")) return .italic;
    if (containsIgnoreCase(subfamily, "Oblique")) return .oblique;
    return .normal;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}
