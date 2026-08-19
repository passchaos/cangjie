//! Optional runtime shared-Brotli decoder used by IFT table patches.

const std = @import("std");
const builtin = @import("builtin");

pub const Error = error{
    BrotliRuntimeUnavailable,
    InvalidBrotliStream,
    InvalidBrotliDictionary,
    BrotliOutputTooLarge,
} || std.mem.Allocator.Error;

const State = opaque {};
const AllocFn = ?*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque;
const FreeFn = ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;
const CreateFn = *const fn (AllocFn, FreeFn, ?*anyopaque) callconv(.c) ?*State;
const DestroyFn = *const fn (?*State) callconv(.c) void;
const AttachFn = *const fn (*State, c_int, usize, [*]const u8) callconv(.c) c_int;
const StreamFn = *const fn (*State, *usize, *[*]const u8, *usize, *[*]u8, *usize) callconv(.c) c_int;

const Runtime = struct {
    library: std.DynLib,
    create: CreateFn,
    destroy: DestroyFn,
    attach: AttachFn,
    stream: StreamFn,

    fn deinit(self: *Runtime) void {
        self.library.close();
        self.* = undefined;
    }
};

pub fn decodeAlloc(
    allocator: std.mem.Allocator,
    encoded: []const u8,
    dictionary: ?[]const u8,
    max_output_size: usize,
) Error![]u8 {
    var runtime = try openRuntime();
    defer runtime.deinit();
    const state = runtime.create(null, null, null) orelse
        return error.InvalidBrotliStream;
    defer runtime.destroy(state);
    if (dictionary) |bytes| {
        if (bytes.len == 0 or runtime.attach(state, 0, bytes.len, bytes.ptr) == 0) {
            return error.InvalidBrotliDictionary;
        }
    }
    const output = try allocator.alloc(u8, max_output_size);
    errdefer allocator.free(output);
    var available_input = encoded.len;
    var next_input: [*]const u8 = encoded.ptr;
    var available_output = output.len;
    var next_output: [*]u8 = output.ptr;
    var total_output: usize = 0;
    while (true) {
        const result = runtime.stream(
            state,
            &available_input,
            &next_input,
            &available_output,
            &next_output,
            &total_output,
        );
        switch (result) {
            1 => break,
            2 => if (available_input == 0) return error.InvalidBrotliStream,
            3 => if (available_output == 0) return error.BrotliOutputTooLarge,
            else => return error.InvalidBrotliStream,
        }
    }
    if (available_input != 0) return error.InvalidBrotliStream;
    if (total_output > output.len) return error.BrotliOutputTooLarge;
    return allocator.realloc(output, total_output);
}

fn openRuntime() Error!Runtime {
    if (!supported()) return error.BrotliRuntimeUnavailable;
    const names = [_][:0]const u8{
        "libbrotlidec.so.1",
        "libbrotlidec.so",
        "libbrotlidec.dylib",
        "/lib/x86_64-linux-gnu/libbrotlidec.so.1",
        "/usr/lib/x86_64-linux-gnu/libbrotlidec.so.1",
        "/opt/homebrew/lib/libbrotlidec.dylib",
    };
    for (names) |name| {
        var library = std.DynLib.openZ(name.ptr) catch continue;
        const create = library.lookup(CreateFn, "BrotliDecoderCreateInstance") orelse {
            library.close();
            continue;
        };
        const destroy = library.lookup(DestroyFn, "BrotliDecoderDestroyInstance") orelse {
            library.close();
            continue;
        };
        const attach = library.lookup(AttachFn, "BrotliDecoderAttachDictionary") orelse {
            library.close();
            continue;
        };
        const stream = library.lookup(StreamFn, "BrotliDecoderDecompressStream") orelse {
            library.close();
            continue;
        };
        return .{
            .library = library,
            .create = create,
            .destroy = destroy,
            .attach = attach,
            .stream = stream,
        };
    }
    return error.BrotliRuntimeUnavailable;
}

fn supported() bool {
    return switch (builtin.os.tag) {
        .linux,
        .freebsd,
        .netbsd,
        .openbsd,
        .dragonfly,
        .illumos,
        .macos,
        .ios,
        .tvos,
        .watchos,
        .visionos,
        .maccatalyst,
        .driverkit,
        => true,
        else => false,
    };
}

test "shared Brotli runtime decodes reference vectors when installed" {
    const target = "hijkabcdeflmnohijkabcdeflmno\n";
    const dictionary = "abcdef\n";
    const encoded = [_]u8{
        0xa1, 0xe0, 0x00, 0xc0, 0x2f, 0x3a, 0x38, 0xf4,
        0x01, 0xd1, 0xaf, 0x54, 0x84, 0x14, 0x71, 0x2a,
        0x80, 0x04, 0xa2, 0x1c, 0xd3, 0xdd, 0x07,
    };
    const decoded = decodeAlloc(
        std.testing.allocator,
        &encoded,
        dictionary,
        target.len,
    ) catch |err| switch (err) {
        error.BrotliRuntimeUnavailable => return,
        else => return err,
    };
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings(target, decoded);
}
