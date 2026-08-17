//! Owned font database storage, loading, scanning, matching, and fallback.

const std = @import("std");
const face_mod = @import("../face/root.zig");
const Font = @import("../../font.zig").Font;
const font_container = @import("../container/root.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const attributed_font_resolution = @import("../../text/attributed/font_resolution.zig");
const manifest_mod = @import("manifest.zig");
const matching = @import("matching.zig");
const source_mod = @import("sources.zig");
const types = @import("types.zig");

pub const FontStyle = types.Style;
pub const FontFaceInfo = types.FaceInfo;
pub const FontQuery = types.Query;
pub const FontManifestEntry = manifest_mod.Entry;
pub const FontSource = source_mod.Source;

pub const serializeManifest = manifest_mod.serializeManifest;
pub const parseManifest = manifest_mod.parseManifest;
pub const writeManifestFile = manifest_mod.writeManifestFile;
pub const readManifestFile = manifest_mod.readManifestFile;
pub const manifestEntryMatchesBytes = manifest_mod.manifestEntryMatchesBytes;
pub const defaultSystemFontSources = source_mod.defaultSystemFontSources;
pub const defaultSystemFontSourcesForOs = source_mod.defaultSystemFontSourcesForOs;
pub const userFontSourcesForOs = source_mod.userFontSourcesForOs;
pub const combinedSystemFontSourcesForOs = source_mod.combinedSystemFontSourcesForOs;

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
        const postscript_name = try self.allocator.dupe(u8, try databasePostScriptName(font, &scratch));
        errdefer self.allocator.free(postscript_name);
        const attributes = try font.styleAttributes();
        const weight = if (font.hasStyleAttributes()) attributes.weight else matching.inferWeight(subfamily);
        const stretch = if (font.hasStyleAttributes()) matching.widthClassToStretch(attributes.width) else 100;
        const style = if (attributes.italic) .italic else matching.inferStyle(subfamily);
        if (self.findDuplicateFace(family, subfamily, full_name, postscript_name, weight, stretch, style)) |index| {
            self.allocator.free(family);
            self.allocator.free(subfamily);
            self.allocator.free(full_name);
            self.allocator.free(postscript_name);
            return index;
        }

        const face = FontFaceInfo{
            .face = face_mod.backend.face(font),
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
        return try self.addFontBytesWithLimit(
            bytes,
            font_container.default_max_decoded_size,
        );
    }

    pub fn addFontBytesWithLimit(
        self: *FontDatabase,
        bytes: []const u8,
        max_decoded_size: usize,
    ) !usize {
        const owned_bytes = try font_container.decodeFontContainerAlloc(
            self.allocator,
            bytes,
            max_decoded_size,
        );
        return try self.addOwnedFontFaceBytes(
            owned_bytes,
            manifest_mod.bytesHash(bytes),
            bytes.len,
            0,
        );
    }

    pub fn addFontCollectionBytes(self: *FontDatabase, bytes: []const u8) !usize {
        return try self.addFontCollectionBytesWithLimit(
            bytes,
            font_container.default_max_decoded_size,
        );
    }

    pub fn addFontCollectionBytesWithLimit(
        self: *FontDatabase,
        bytes: []const u8,
        max_decoded_size: usize,
    ) !usize {
        const decoded = try font_container.decodeFontContainerAlloc(
            self.allocator,
            bytes,
            max_decoded_size,
        );
        defer self.allocator.free(decoded);
        const count = try Font.faceCount(decoded);
        const source_hash = manifest_mod.bytesHash(bytes);
        var added: usize = 0;
        errdefer {
            while (added > 0) : (added -= 1) {
                self.removeLastOwnedFace();
            }
        }
        for (0..count) |face_index| {
            const before = self.faces.items.len;
            _ = try self.addFontFaceBytes(
                decoded,
                source_hash,
                bytes.len,
                face_index,
            );
            if (self.faces.items.len > before) added += 1;
        }
        return added;
    }

    pub fn addFontFile(self: *FontDatabase, io: std.Io, dir: std.Io.Dir, path: []const u8, limit: std.Io.Limit) !usize {
        const bytes = try dir.readFileAlloc(io, path, self.allocator, limit);
        defer self.allocator.free(bytes);
        return try self.addFontBytesWithLimit(bytes, @intFromEnum(limit));
    }

    pub fn addFontCollectionFile(self: *FontDatabase, io: std.Io, dir: std.Io.Dir, path: []const u8, limit: std.Io.Limit) !usize {
        const bytes = try dir.readFileAlloc(io, path, self.allocator, limit);
        defer self.allocator.free(bytes);
        return try self.addFontCollectionBytesWithLimit(bytes, @intFromEnum(limit));
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

    fn addFontFaceBytes(
        self: *FontDatabase,
        bytes: []const u8,
        source_hash: u64,
        source_size: usize,
        face_index: usize,
    ) !usize {
        const owned_bytes = try self.allocator.dupe(u8, bytes);
        return try self.addOwnedFontFaceBytes(
            owned_bytes,
            source_hash,
            source_size,
            face_index,
        );
    }

    fn addOwnedFontFaceBytes(
        self: *FontDatabase,
        owned_bytes: []u8,
        source_hash: u64,
        source_size: usize,
        face_index: usize,
    ) !usize {
        const content_hash = manifest_mod.bytesHash(owned_bytes);
        if (self.findOwnedFaceByBytes(owned_bytes, content_hash, face_index)) |index| {
            self.allocator.free(owned_bytes);
            return index;
        }
        const owned = self.allocator.create(OwnedFont) catch |err| {
            self.allocator.free(owned_bytes);
            return err;
        };
        const font = Font.parseFace(self.allocator, owned_bytes, face_index) catch |err| {
            self.allocator.destroy(owned);
            self.allocator.free(owned_bytes);
            return err;
        };
        owned.* = .{
            .bytes = owned_bytes,
            .source_hash = source_hash,
            .source_size = source_size,
            .font = font,
            .content_hash = content_hash,
            .face_index = face_index,
        };
        self.owned_fonts.append(self.allocator, owned) catch |err| {
            owned.font.deinit();
            self.allocator.free(owned.bytes);
            self.allocator.destroy(owned);
            return err;
        };
        const index = self.addFont(&owned.font) catch |err| {
            _ = self.owned_fonts.pop();
            owned.font.deinit();
            self.allocator.free(owned.bytes);
            self.allocator.destroy(owned);
            return err;
        };
        if (face_mod.backend.font(self.faces.items[index].face) != &owned.font) {
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
            if (!matching.familyMatches(face.family, query.family)) continue;
            const score = matching.matchScore(face, query);
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
        if (primary) |face| {
            try appendUniqueFont(
                allocator,
                &fonts,
                face_mod.backend.font(face.face),
            );
        }

        var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (it.nextCodepoint()) |codepoint| {
            if (fontListCovers(fonts.items, codepoint)) continue;
            if (self.findFallbackFace(codepoint, query)) |fallback| {
                try appendUniqueFont(
                    allocator,
                    &fonts,
                    face_mod.backend.font(fallback.face),
                );
            }
        }

        return try fonts.toOwnedSlice(allocator);
    }

    pub fn cascadeForText(self: *const FontDatabase, allocator: std.mem.Allocator, query: FontQuery, text: []const u8) !font_fallback.Cascade {
        return .init(try self.buildCascadeForText(allocator, query, text));
    }

    /// Resolve per-style font queries and lay out one unified attributed
    /// paragraph. The result type is inferred from the attributed value, so
    /// this database layer stays independent of concrete application style
    /// records while the public root exposes a convenience wrapper. Font runs
    /// borrow faces from this database; keep it alive until the result is
    /// deinitialized.
    pub fn layoutAttributedParagraphUtf8(
        self: *const FontDatabase,
        allocator: std.mem.Allocator,
        attributed: anytype,
        default_query: FontQuery,
        max_width: f32,
    ) !attributed_font_resolution.ResultType(@TypeOf(attributed)) {
        return try attributed_font_resolution.layoutAttributed(
            self,
            allocator,
            attributed,
            default_query,
            max_width,
        );
    }

    pub fn measureAttributedTextUtf8(
        self: *const FontDatabase,
        allocator: std.mem.Allocator,
        attributed: anytype,
        default_query: FontQuery,
        max_width: f32,
    ) !paragraph_types.TextMetrics {
        return try attributed_font_resolution.measureAttributed(
            self,
            allocator,
            attributed,
            default_query,
            max_width,
        );
    }

    pub fn familyCount(self: *const FontDatabase) usize {
        var count: usize = 0;
        for (self.faces.items, 0..) |face, index| {
            var seen = false;
            for (self.faces.items[0..index]) |previous| {
                if (matching.familyMatches(previous.family, face.family)) {
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
                if (matching.familyMatches(name, face.family)) {
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
            if (matching.familyMatches(face.family, family)) try indices.append(allocator, index);
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
                .content_hash = self.contentHashForFont(
                    face_mod.backend.font(face.face),
                ),
                .content_size = self.contentSizeForFont(
                    face_mod.backend.font(face.face),
                ),
                .weight = face.weight,
                .stretch = face.stretch,
                .style = face.style,
            };
            initialized += 1;
        }
        return entries;
    }

    pub fn freeManifest(allocator: std.mem.Allocator, entries: []FontManifestEntry) void {
        manifest_mod.free(allocator, entries);
    }

    fn findFallbackFace(self: *const FontDatabase, codepoint: u21, query: FontQuery) ?*const FontFaceInfo {
        var best: ?usize = null;
        var best_score: u32 = std.math.maxInt(u32);
        for (self.faces.items, 0..) |face, index| {
            if (!fontCovers(face_mod.backend.font(face.face), codepoint)) continue;
            const score = matching.matchScore(face, query) + if (matching.familyMatches(face.family, query.family)) @as(u32, 0) else 5000;
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

    fn findOwnedFaceByBytes(
        self: *const FontDatabase,
        bytes: []const u8,
        content_hash: u64,
        face_index: usize,
    ) ?usize {
        for (self.owned_fonts.items) |owned| {
            if (owned.content_hash != content_hash or owned.face_index != face_index) continue;
            // Wyhash is only a fast rejection key. An allocator-backed font
            // database must not silently alias attacker-controlled inputs on a
            // 64-bit collision, because the retained Font would then expose
            // tables from different bytes than the caller supplied.
            if (!std.mem.eql(u8, owned.bytes, bytes)) continue;
            for (self.faces.items, 0..) |face, index| {
                if (face_mod.backend.font(face.face) == &owned.font) return index;
            }
        }
        return null;
    }

    fn contentHashForFont(self: *const FontDatabase, font: *const Font) u64 {
        for (self.owned_fonts.items) |owned| {
            if (&owned.font == font) return owned.source_hash;
        }
        return 0;
    }

    fn contentSizeForFont(self: *const FontDatabase, font: *const Font) u64 {
        for (self.owned_fonts.items) |owned| {
            if (&owned.font == font) return owned.source_size;
        }
        return 0;
    }
};

const OwnedFont = struct {
    bytes: []u8,
    source_hash: u64,
    source_size: u64,
    font: Font,
    content_hash: u64,
    face_index: usize,
};

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

fn databasePostScriptName(font: *const Font, scratch: []u8) ![]const u8 {
    return font.nameString(.postscript_name, scratch) catch |err| switch (err) {
        error.InvalidName => "",
        else => return err,
    } orelse "";
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
        std.ascii.endsWithIgnoreCase(path, ".otc") or
        std.ascii.endsWithIgnoreCase(path, ".dfont") or
        std.ascii.endsWithIgnoreCase(path, ".woff") or
        std.ascii.endsWithIgnoreCase(path, ".woff2");
}

fn isCollectionPath(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".ttc") or
        std.ascii.endsWithIgnoreCase(path, ".otc") or
        std.ascii.endsWithIgnoreCase(path, ".dfont") or
        // WOFF2 may wrap a font collection. The collection API also accepts a
        // one-face WOFF2, so scanners can discover every face without parsing
        // the compressed header twice or special-casing its flavor here.
        std.ascii.endsWithIgnoreCase(path, ".woff2");
}
