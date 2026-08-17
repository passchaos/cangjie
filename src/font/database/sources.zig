//! Platform font source descriptions and default discovery paths.

const std = @import("std");
const builtin = @import("builtin");

pub const Source = union(enum) {
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

pub fn defaultSystemFontSources() []const Source {
    return defaultSystemFontSourcesForOs(builtin.os.tag);
}

pub fn defaultSystemFontSourcesForOs(os_tag: std.Target.Os.Tag) []const Source {
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

pub fn userFontSourcesForOs(home_path: []const u8, os_tag: std.Target.Os.Tag, buffer: []Source, path_buffer: []u8) ![]const Source {
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

pub fn combinedSystemFontSourcesForOs(home_path: ?[]const u8, os_tag: std.Target.Os.Tag, buffer: []Source, path_buffer: []u8) ![]const Source {
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

fn appendUserFontSource(buffer: []Source, count: *usize, path_buffer: []u8, path_offset: *usize, home_path: []const u8, relative_path: []const u8) !void {
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
