const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("glyph_bench/options.zig");
const freetype = @import("glyph_bench/freetype.zig");
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
    if (options.engine == .freetype) {
        const result = try freetype.run(init.io, allocator, font_bytes, options);
        defer allocator.free(result.samples);
        report.print(options, result);
        return;
    }
    var font = try cangjie.Font.parse(allocator, font_bytes);
    defer font.deinit();

    if (options.engine == .compare_freetype) {
        var cangjie_options = options;
        cangjie_options.engine = .cangjie;
        const cangjie_result = try runner.run(init.io, allocator, &font, cangjie_options);
        defer allocator.free(cangjie_result.samples);
        report.print(cangjie_options, cangjie_result);

        var freetype_options = options;
        freetype_options.engine = .freetype;
        const freetype_result = try freetype.run(init.io, allocator, font_bytes, freetype_options);
        defer allocator.free(freetype_result.samples);
        report.print(freetype_options, freetype_result);
        return;
    }

    const result = try runner.run(init.io, allocator, &font, options);
    defer allocator.free(result.samples);
    report.print(options, result);
}
