//! Stable, pointer-free font face descriptors for persistence boundaries.
//!
//! Runtime font handles are process-local. A descriptor instead carries an
//! exact source identity when font bytes are owned, plus names and CSS-like
//! traits for an explicitly requested portable fallback.

const std = @import("std");
const types = @import("types.zig");

pub const name_capacity: usize = 192;
pub const digest_bytes: usize = 32;
pub const Digest = [digest_bytes]u8;
pub const SourceDigest = Digest;
pub const wire_version: u16 = 1;
pub const wire_size: usize = 644;
const wire_magic = "CFD1";

pub const Name = struct {
    bytes: [name_capacity]u8 = .{0} ** name_capacity,
    len: u16 = 0,

    pub fn init(value: []const u8) !Name {
        if (value.len > name_capacity) return error.NameTooLong;
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        var out = Name{ .len = @intCast(value.len) };
        @memcpy(out.bytes[0..value.len], value);
        return out;
    }

    pub fn slice(self: *const Name) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn valid(self: *const Name) bool {
        if (self.len > name_capacity or !std.unicode.utf8ValidateSlice(self.slice())) return false;
        for (self.bytes[self.len..]) |byte| if (byte != 0) return false;
        return true;
    }
};

pub const Descriptor = struct {
    family: Name,
    subfamily: Name,
    postscript_name: Name = .{},
    weight: u16 = 400,
    stretch: u16 = 100,
    style: types.Style = .normal,
    source_digest: Digest = .{0} ** digest_bytes,
    source_size: u64 = 0,
    face_index: u32 = 0,
    has_content_identity: bool = false,

    pub fn init(options: struct {
        family: []const u8,
        subfamily: []const u8,
        postscript_name: []const u8 = "",
        weight: u16 = 400,
        stretch: u16 = 100,
        style: types.Style = .normal,
        source_digest: ?Digest = null,
        source_size: u64 = 0,
        face_index: u32 = 0,
    }) !Descriptor {
        if (options.family.len == 0 or options.weight < 1 or options.weight > 1000 or
            options.stretch < 1 or options.stretch > 1000) return error.InvalidDescriptor;
        const has_content = options.source_digest != null;
        if (has_content != (options.source_size != 0)) return error.InvalidDescriptor;
        return .{
            .family = try Name.init(options.family),
            .subfamily = try Name.init(options.subfamily),
            .postscript_name = try Name.init(options.postscript_name),
            .weight = options.weight,
            .stretch = options.stretch,
            .style = options.style,
            .source_digest = options.source_digest orelse .{0} ** digest_bytes,
            .source_size = options.source_size,
            .face_index = options.face_index,
            .has_content_identity = has_content,
        };
    }

    pub fn valid(self: *const Descriptor) bool {
        if (!self.family.valid() or self.family.len == 0 or !self.subfamily.valid() or
            !self.postscript_name.valid() or self.weight < 1 or self.weight > 1000 or
            self.stretch < 1 or self.stretch > 1000) return false;
        if (self.has_content_identity) return self.source_size != 0;
        return self.source_size == 0 and self.face_index == 0 and digestIsZero(self.source_digest);
    }

    pub fn fingerprint(self: *const Descriptor) u64 {
        if (!self.valid()) return 0;
        var hash = std.hash.Wyhash.init(0x6361_6e67_6a69_652d);
        hash.update(self.family.slice());
        hash.update(&.{0});
        hash.update(self.subfamily.slice());
        hash.update(&.{0});
        hash.update(self.postscript_name.slice());
        hash.update(&.{0});
        hashInt(&hash, self.weight);
        hashInt(&hash, self.stretch);
        hash.update(&.{ @intFromEnum(self.style), @intFromBool(self.has_content_identity) });
        if (self.has_content_identity) {
            hash.update(&self.source_digest);
            hashInt(&hash, self.source_size);
            hashInt(&hash, self.face_index);
        }
        const value = hash.final();
        return if (value == 0) 1 else value;
    }
};

pub const ResolveMode = enum { exact, portable };
pub const ResolveStatus = enum { exact_content, postscript, family_style, content_unavailable, content_mismatch, ambiguous, not_found, invalid_descriptor };

pub const Resolution = struct {
    status: ResolveStatus,
    face_index: ?usize = null,

    pub fn resolved(self: Resolution) bool {
        return self.face_index != null;
    }

    pub fn exact(self: Resolution) bool {
        return self.status == .exact_content;
    }
};

pub const Candidate = struct {
    family: []const u8,
    subfamily: []const u8,
    postscript_name: []const u8,
    weight: u16,
    stretch: u16,
    style: types.Style,
    source_digest: ?Digest = null,
    source_size: u64 = 0,
    face_index: u32 = 0,
};

pub const Resolver = struct {
    descriptor: Descriptor,
    mode: ResolveMode,
    descriptor_valid: bool,
    exact_index: ?usize = null,
    postscript_index: ?usize = null,
    family_index: ?usize = null,
    postscript_ambiguous: bool = false,
    family_ambiguous: bool = false,

    pub fn init(descriptor: Descriptor, mode: ResolveMode) Resolver {
        return .{ .descriptor = descriptor, .mode = mode, .descriptor_valid = descriptor.valid() };
    }

    pub fn add(self: *Resolver, index: usize, candidate: Candidate) void {
        if (!self.descriptor_valid) return;
        if (candidate.source_digest) |digest| {
            if (exactContentMatch(self.descriptor, digest, candidate.source_size, candidate.face_index))
                self.exact_index = if (self.exact_index) |current| @min(current, index) else index;
        }
        if (self.mode == .exact) return;
        if (candidate.weight != self.descriptor.weight or candidate.stretch != self.descriptor.stretch or candidate.style != self.descriptor.style) return;
        if (self.descriptor.postscript_name.len != 0 and candidate.postscript_name.len != 0 and
            std.ascii.eqlIgnoreCase(candidate.postscript_name, self.descriptor.postscript_name.slice()))
            addUnique(&self.postscript_index, &self.postscript_ambiguous, index);
        if (std.ascii.eqlIgnoreCase(candidate.family, self.descriptor.family.slice()) and
            std.ascii.eqlIgnoreCase(candidate.subfamily, self.descriptor.subfamily.slice()))
            addUnique(&self.family_index, &self.family_ambiguous, index);
    }

    pub fn finish(self: Resolver) Resolution {
        if (!self.descriptor_valid) return .{ .status = .invalid_descriptor };
        if (self.exact_index) |index| return .{ .status = .exact_content, .face_index = index };
        if (self.mode == .exact) return .{ .status = if (self.descriptor.has_content_identity) .content_mismatch else .content_unavailable };
        if (self.postscript_ambiguous) return .{ .status = .ambiguous };
        if (self.postscript_index) |index| return .{ .status = .postscript, .face_index = index };
        if (self.family_ambiguous) return .{ .status = .ambiguous };
        if (self.family_index) |index| return .{ .status = .family_style, .face_index = index };
        return .{ .status = .not_found };
    }
};

pub fn sourceDigest(bytes: []const u8) Digest {
    var out: Digest = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
    return out;
}

pub fn encode(descriptor: Descriptor, out: []u8) ![]const u8 {
    if (!descriptor.valid()) return error.InvalidDescriptor;
    if (out.len < wire_size) return error.NoSpaceLeft;
    var cursor: usize = 0;
    @memcpy(out[cursor..][0..wire_magic.len], wire_magic);
    cursor += wire_magic.len;
    writeInt(u16, out, &cursor, wire_version);
    writeInt(u16, out, &cursor, 0);
    try writeName(out, &cursor, descriptor.family);
    try writeName(out, &cursor, descriptor.subfamily);
    try writeName(out, &cursor, descriptor.postscript_name);
    writeInt(u16, out, &cursor, descriptor.weight);
    writeInt(u16, out, &cursor, descriptor.stretch);
    writeInt(u8, out, &cursor, @intFromEnum(descriptor.style));
    writeInt(u8, out, &cursor, @intFromBool(descriptor.has_content_identity));
    writeInt(u16, out, &cursor, 0);
    @memcpy(out[cursor..][0..digest_bytes], &descriptor.source_digest);
    cursor += digest_bytes;
    writeInt(u64, out, &cursor, descriptor.source_size);
    writeInt(u32, out, &cursor, descriptor.face_index);
    writeInt(u16, out, &cursor, 0);
    std.debug.assert(cursor == wire_size);
    return out[0..wire_size];
}

pub fn decode(bytes: []const u8) !Descriptor {
    if (bytes.len != wire_size) return error.InvalidDescriptorSize;
    var cursor: usize = 0;
    if (!std.mem.eql(u8, bytes[cursor..][0..wire_magic.len], wire_magic)) return error.InvalidMagic;
    cursor += wire_magic.len;
    if (readInt(u16, bytes, &cursor) != wire_version) return error.UnsupportedVersion;
    if (readInt(u16, bytes, &cursor) != 0) return error.InvalidReserved;
    const family = try readName(bytes, &cursor);
    const subfamily = try readName(bytes, &cursor);
    const postscript_name = try readName(bytes, &cursor);
    const weight = readInt(u16, bytes, &cursor);
    const stretch = readInt(u16, bytes, &cursor);
    const style_raw = readInt(u8, bytes, &cursor);
    const style: types.Style = switch (style_raw) {
        0 => .normal,
        1 => .italic,
        2 => .oblique,
        else => return error.InvalidStyle,
    };
    const has_content_identity = switch (readInt(u8, bytes, &cursor)) {
        0 => false,
        1 => true,
        else => return error.InvalidBoolean,
    };
    if (readInt(u16, bytes, &cursor) != 0) return error.InvalidReserved;
    var source_digest: Digest = undefined;
    @memcpy(&source_digest, bytes[cursor..][0..digest_bytes]);
    cursor += digest_bytes;
    const source_size = readInt(u64, bytes, &cursor);
    const face_index = readInt(u32, bytes, &cursor);
    if (readInt(u16, bytes, &cursor) != 0 or cursor != wire_size) return error.InvalidReserved;
    const descriptor = Descriptor{
        .family = family,
        .subfamily = subfamily,
        .postscript_name = postscript_name,
        .weight = weight,
        .stretch = stretch,
        .style = style,
        .source_digest = source_digest,
        .source_size = source_size,
        .face_index = face_index,
        .has_content_identity = has_content_identity,
    };
    if (!descriptor.valid()) return error.InvalidDescriptor;
    return descriptor;
}

pub fn namesAndTraitsMatch(descriptor: Descriptor, family: []const u8, subfamily: []const u8, postscript_name: []const u8, weight: u16, stretch: u16, style: types.Style) bool {
    if (descriptor.weight != weight or descriptor.stretch != stretch or descriptor.style != style) return false;
    if (descriptor.postscript_name.len != 0 and postscript_name.len != 0)
        return std.ascii.eqlIgnoreCase(descriptor.postscript_name.slice(), postscript_name);
    return std.ascii.eqlIgnoreCase(descriptor.family.slice(), family) and
        std.ascii.eqlIgnoreCase(descriptor.subfamily.slice(), subfamily);
}

pub fn exactContentMatch(descriptor: Descriptor, digest: Digest, source_size: u64, face_index: u32) bool {
    return descriptor.has_content_identity and descriptor.source_size == source_size and
        descriptor.face_index == face_index and std.mem.eql(u8, &descriptor.source_digest, &digest);
}

pub fn resolveCandidates(candidates: []const Candidate, descriptor: Descriptor, mode: ResolveMode) Resolution {
    var resolver = Resolver.init(descriptor, mode);
    for (candidates, 0..) |candidate, index| resolver.add(index, candidate);
    return resolver.finish();
}

fn addUnique(index: *?usize, ambiguous: *bool, candidate: usize) void {
    if (index.* != null and index.*.? != candidate) ambiguous.* = true else index.* = candidate;
}

fn digestIsZero(digest: Digest) bool {
    for (digest) |byte| if (byte != 0) return false;
    return true;
}

fn hashInt(hash: *std.hash.Wyhash, value: anytype) void {
    const T = @TypeOf(value);
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    hash.update(&bytes);
}

fn writeName(out: []u8, cursor: *usize, name: Name) !void {
    if (!name.valid()) return error.InvalidDescriptor;
    writeInt(u16, out, cursor, name.len);
    @memcpy(out[cursor.*..][0..name.len], name.slice());
    @memset(out[cursor.* + name.len ..][0 .. name_capacity - name.len], 0);
    cursor.* += name_capacity;
}

fn readName(bytes: []const u8, cursor: *usize) !Name {
    const len = readInt(u16, bytes, cursor);
    if (len > name_capacity) return error.NameTooLong;
    var name = Name{ .len = len };
    @memcpy(name.bytes[0..len], bytes[cursor.*..][0..len]);
    for (bytes[cursor.* + len ..][0 .. name_capacity - len]) |byte| if (byte != 0) return error.InvalidPadding;
    cursor.* += name_capacity;
    if (!name.valid()) return error.InvalidDescriptor;
    return name;
}

fn writeInt(comptime T: type, out: []u8, cursor: *usize, value: T) void {
    std.mem.writeInt(T, out[cursor.*..][0..@sizeOf(T)], value, .little);
    cursor.* += @sizeOf(T);
}

fn readInt(comptime T: type, bytes: []const u8, cursor: *usize) T {
    const value = std.mem.readInt(T, bytes[cursor.*..][0..@sizeOf(T)], .little);
    cursor.* += @sizeOf(T);
    return value;
}

test "font descriptors are canonical pointer-free values" {
    const digest = sourceDigest("font bytes");
    const descriptor = try Descriptor.init(.{
        .family = "Example Sans",
        .subfamily = "Bold",
        .postscript_name = "ExampleSans-Bold",
        .weight = 700,
        .source_digest = digest,
        .source_size = 10,
        .face_index = 2,
    });
    try std.testing.expect(descriptor.valid());
    try std.testing.expect(descriptor.fingerprint() != 0);
    try std.testing.expect(exactContentMatch(descriptor, digest, 10, 2));
    try std.testing.expect(namesAndTraitsMatch(descriptor, "Other", "Regular", "examplesans-bold", 700, 100, .normal));
    var wire: [wire_size]u8 = undefined;
    const encoded = try encode(descriptor, &wire);
    const decoded = try decode(encoded);
    try std.testing.expectEqual(descriptor, decoded);
    wire[8 + 2 + name_capacity - 1] = 1;
    try std.testing.expectError(error.InvalidPadding, decode(&wire));
}

test "exact content identity is independent of mutable font metadata" {
    const digest = sourceDigest("same collection bytes");
    const descriptor = try Descriptor.init(.{
        .family = "Source Family",
        .subfamily = "Regular",
        .postscript_name = "SourceFamily-Regular",
        .weight = 400,
        .source_digest = digest,
        .source_size = 21,
        .face_index = 3,
    });
    const candidates = [_]Candidate{.{
        .family = "Normalized Family",
        .subfamily = "Book",
        .postscript_name = "NormalizedFamily-Book",
        .weight = 450,
        .stretch = 90,
        .style = .oblique,
        .source_digest = digest,
        .source_size = 21,
        .face_index = 3,
    }};
    const exact = resolveCandidates(&candidates, descriptor, .exact);
    try std.testing.expectEqual(ResolveStatus.exact_content, exact.status);
    try std.testing.expectEqual(@as(?usize, 0), exact.face_index);
}
