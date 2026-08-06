const std = @import("std");
const cangjie = @import("cangjie");

const coretext = @import("shape_bench/coretext.zig");
const options_mod = @import("shape_bench/options.zig");
const report = @import("shape_bench/report.zig");
const runner = @import("shape_bench/runner.zig");

pub fn main(init: std.process.Init) !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var args_iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args_iterator.deinit();

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    while (args_iterator.next()) |arg| {
        try args.append(allocator, arg);
    }

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

    const result = switch (options.engine) {
        .cangjie => result: {
            var font = try cangjie.Font.parse(allocator, font_bytes);
            defer font.deinit();
            break :result try runner.runCangjie(init.io, allocator, &font, options);
        },
        .coretext => try coretext.run(init.io, allocator, font_bytes, options),
    };
    report.print(options, result);
}
