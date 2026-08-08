const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("glyph_bench/options.zig");
const report = @import("glyph_bench/report.zig");
const runner = @import("glyph_bench/runner.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var args_iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iterator.deinit();

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    while (args_iterator.next()) |arg| try args.append(allocator, arg);

    const options = options_mod.parse(args.items) catch |err| switch (err) {
        error.InvalidArguments => {
            options_mod.printUsage(args.items);
            return;
        },
        else => {
            options_mod.printUsage(args.items);
            return err;
        },
    };

    const font_bytes = try runner.loadFontBytes(init.io, allocator, options);
    defer allocator.free(font_bytes);
    var font = try cangjie.Font.parse(allocator, font_bytes);
    defer font.deinit();

    const result = try runner.run(init.io, allocator, &font, options);
    defer allocator.free(result.samples);
    report.print(options, result);
}
