const std = @import("std");
const cangjie = @import("cangjie");

const coretext = @import("shape_bench/coretext.zig");
const options_mod = @import("shape_bench/options.zig");
const report = @import("shape_bench/report.zig");
const runner = @import("shape_bench/runner.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;

    var args_iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iterator.deinit();

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    while (args_iterator.next()) |arg| {
        try args.append(allocator, arg);
    }

    var options = options_mod.parse(args.items) catch |err| switch (err) {
        error.InvalidArguments => {
            options_mod.printUsage(args.items);
            return;
        },
        else => {
            options_mod.printUsage(args.items);
            return err;
        },
    };
    const text_bytes = if (options.text_path) |path|
        try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(64 * 1024 * 1024))
    else
        null;
    defer if (text_bytes) |bytes| allocator.free(bytes);
    if (text_bytes) |bytes| options.text = bytes;
    const text_lines = try splitTextLines(allocator, options.text);
    defer allocator.free(text_lines);
    options.text_lines = text_lines;

    const font_bytes = try runner.loadFontBytes(init.io, allocator, options);
    defer allocator.free(font_bytes);

    const result = switch (options.engine) {
        .cangjie => result: {
            var font = try cangjie.Font.parse(allocator, font_bytes);
            defer font.deinit();
            break :result try runner.runCangjie(init.io, allocator, &font, options);
        },
        .coretext => try coretext.run(init.io, allocator, font_bytes, options),
    };
    defer {
        for (result.line_summaries) |summary| allocator.free(summary.glyph_ids);
        allocator.free(result.line_summaries);
        allocator.free(result.samples);
    }
    report.print(options, result);
}

fn splitTextLines(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var lines = std.ArrayList([]const u8).empty;
    errdefer lines.deinit(allocator);

    var it = std.mem.splitScalar(u8, std.mem.trim(u8, text, "\n\r"), '\n');
    while (it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        if (line.len == 0) continue;
        try lines.append(allocator, line);
    }
    if (lines.items.len == 0 and text.len != 0) {
        try lines.append(allocator, text);
    }
    return try lines.toOwnedSlice(allocator);
}
