//! Platform system-font parsing smoke tests.

const std = @import("std");
const Font = @import("../../font.zig").Font;

test "macOS platform UI fonts parse for text metrics" {
    if (@import("builtin").target.os.tag != .macos) return error.SkipZigTest;
    const paths = [_][]const u8{
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    };
    var checked: usize = 0;
    for (paths) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(
            std.testing.io,
            path,
            std.testing.allocator,
            .limited(256 * 1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer std.testing.allocator.free(bytes);
        var font = try Font.parse(std.testing.allocator, bytes);
        defer font.deinit();
        try std.testing.expect(font.glyph_count > 0);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
}
