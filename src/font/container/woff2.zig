//! Optional runtime-backed WOFF2 reconstruction.

const std = @import("std");
const builtin = @import("builtin");

const Woff2FinalSizeFn = *const fn ([*]const u8, usize) callconv(.c) usize;
const Woff2ConvertFn = *const fn ([*]u8, usize, [*]const u8, usize) callconv(.c) bool;

const Woff2Runtime = struct {
    library: std.DynLib,
    final_size: Woff2FinalSizeFn,
    convert: Woff2ConvertFn,

    fn deinit(self: *Woff2Runtime) void {
        self.library.close();
        self.* = undefined;
    }
};

pub fn decodeAlloc(
    allocator: std.mem.Allocator,
    woff2: []const u8,
    max_decoded_size: usize,
) ![]u8 {
    var runtime = try openWoff2Runtime();
    defer runtime.deinit();

    const sfnt_len = runtime.final_size(woff2.ptr, woff2.len);
    if (sfnt_len == 0) return error.InvalidContainer;
    if (sfnt_len > max_decoded_size) return error.OutputTooLarge;
    const out = try allocator.alloc(u8, sfnt_len);
    errdefer allocator.free(out);
    if (!runtime.convert(out.ptr, out.len, woff2.ptr, woff2.len)) {
        return error.InvalidContainer;
    }
    return out;
}

fn openWoff2Runtime() !Woff2Runtime {
    if (!supportsWoff2Runtime()) return error.Woff2RuntimeUnavailable;
    const names = [_][:0]const u8{
        "libwoff2dec.so.1.0.2",
        "libwoff2dec.so",
        "libwoff2dec.dylib",
        "/lib/x86_64-linux-gnu/libwoff2dec.so.1.0.2",
        "/usr/lib/x86_64-linux-gnu/libwoff2dec.so.1.0.2",
        "/usr/local/lib/libwoff2dec.so",
        "/opt/homebrew/lib/libwoff2dec.dylib",
        "/usr/local/lib/libwoff2dec.dylib",
    };
    for (names) |name| {
        var library = std.DynLib.openZ(name.ptr) catch continue;
        const final_size = library.lookup(
            Woff2FinalSizeFn,
            "_ZN5woff221ComputeWOFF2FinalSizeEPKhm",
        ) orelse {
            library.close();
            continue;
        };
        const convert = library.lookup(
            Woff2ConvertFn,
            "_ZN5woff217ConvertWOFF2ToTTFEPhmPKhm",
        ) orelse {
            library.close();
            continue;
        };
        return .{
            .library = library,
            .final_size = final_size,
            .convert = convert,
        };
    }
    return error.Woff2RuntimeUnavailable;
}

fn supportsWoff2Runtime() bool {
    return switch (builtin.os.tag) {
        .linux,
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        .freebsd,
        .netbsd,
        .openbsd,
        .dragonfly,
        .illumos,
        => true,
        else => false,
    };
}
