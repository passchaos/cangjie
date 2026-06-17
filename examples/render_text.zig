const std = @import("std");
const cangjie = @import("cangjie");

const Options = struct {
    font_path: []const u8,
    text: []const u8,
    output_path: []const u8 = "zig-out/text.pgm",
    width: u32 = 800,
    height: u32 = 200,
    size: f32 = 64,
    x: f32 = 24,
    baseline: f32 = 120,
};

pub fn main(init: std.process.Init) !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var args_iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iterator.deinit();

    var args_list = std.ArrayList([]const u8).empty;
    defer args_list.deinit(allocator);
    while (args_iterator.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    const options = parseArgs(args_list.items) catch |err| switch (err) {
        error.InvalidArguments => {
            try printUsage(args_list.items);
            return;
        },
        else => {
            try printUsage(args_list.items);
            return err;
        },
    };

    const font_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, options.font_path, allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(font_bytes);

    var font = try cangjie.Font.parse(allocator, font_bytes);
    defer font.deinit();

    var layout_buffer = cangjie.LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try cangjie.TextShaper.shapeUtf8(&font, &layout_buffer, options.text, options.size);

    var target = try cangjie.RenderTarget.init(allocator, options.width, options.height);
    defer target.deinit();

    var rasterizer = cangjie.Rasterizer.init(allocator);
    try rasterizer.renderRun(&target, run, options.x, options.baseline);

    try writePgm(init.io, options.output_path, &target);
    std.debug.print("wrote {s} ({d}x{d})\n", .{ options.output_path, options.width, options.height });
}

fn parseArgs(args: []const []const u8) !Options {
    if (args.len < 3) return error.InvalidArguments;
    var options = Options{
        .font_path = args[1],
        .text = args[2],
    };

    var i: usize = 3;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--out")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--width")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.width = try parseU32(args[i]);
        } else if (std.mem.eql(u8, arg, "--height")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.height = try parseU32(args[i]);
        } else if (std.mem.eql(u8, arg, "--size")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.size = try parseF32(args[i]);
        } else if (std.mem.eql(u8, arg, "--x")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.x = try parseF32(args[i]);
        } else if (std.mem.eql(u8, arg, "--baseline")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.baseline = try parseF32(args[i]);
        } else {
            return error.InvalidArguments;
        }
        i += 1;
    }

    return options;
}

fn parseU32(text: []const u8) !u32 {
    return std.fmt.parseInt(u32, text, 10);
}

fn parseF32(text: []const u8) !f32 {
    return std.fmt.parseFloat(f32, text);
}

fn writePgm(io: std.Io, path: []const u8, target: *const cangjie.RenderTarget) !void {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| {
        if (slash > 0) {
            try std.Io.Dir.cwd().createDirPath(io, path[0..slash]);
        }
    }

    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    const out = &writer.interface;
    try out.print("P5\n{d} {d}\n255\n", .{ target.width, target.height });
    try out.writeAll(target.pixels);
    try writer.flush();
}

fn printUsage(args: []const []const u8) !void {
    const exe = if (args.len > 0) args[0] else "render-text";
    std.debug.print(
        \\usage: {s} <font.ttf|font.otf> <text> [--out text.pgm] [--width 800] [--height 200] [--size 64] [--x 24] [--baseline 120]
        \\
        \\example:
        \\  zig build render-text -- /System/Library/Fonts/Supplemental/Arial.ttf "Hello" --out zig-out/hello.pgm
        \\
    , .{exe});
}
