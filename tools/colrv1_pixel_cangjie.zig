const std = @import("std");
const cangjie = @import("cangjie");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const path = args.next() orelse return error.InvalidArguments;
    const gid = try number(u16, args.next());
    const size = try number(f32, args.next());
    const width = try number(u32, args.next());
    const height = try number(u32, args.next());
    const x = try number(f32, args.next());
    const y = try number(f32, args.next());
    const palette = try number(u16, args.next());
    const raw_coords = args.next() orelse return error.InvalidArguments;
    const iterations = try number(usize, args.next());
    const samples = try number(usize, args.next());
    const output = args.next();
    if (args.next() != null or width == 0 or height == 0 or iterations == 0 or samples == 0)
        return error.InvalidArguments;

    var coord_storage: [64]f32 = undefined;
    const coords = try parseCoords(raw_coords, &coord_storage);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    var face = try cangjie.font.Face.parse(allocator, bytes);
    defer face.deinit();
    var rasterizer = cangjie.render.Rasterizer.init(allocator);
    defer rasterizer.deinit();
    rasterizer.setSampling(4);
    var target = try cangjie.render.ColorTarget.init(allocator, width, height);
    defer target.deinit();
    var times = try std.ArrayList(i128).initCapacity(allocator, samples);
    defer times.deinit(allocator);
    for (0..samples) |_| {
        const start = std.Io.Clock.now(.awake, init.io).nanoseconds;
        for (0..iterations) |_| {
            target.clear(.{ .r = 0, .g = 0, .b = 0, .a = 0 });
            try rasterizer.drawColorGlyphAt(&target, &face, gid, size, x, y, palette, coords);
            std.mem.doNotOptimizeAway(pixelHash(target.pixels));
        }
        try times.append(allocator, std.Io.Clock.now(.awake, init.io).nanoseconds - start);
    }
    std.mem.sort(i128, times.items, {}, std.sort.asc(i128));
    if (output) |out| {
        const raw: []const u8 = @ptrCast(target.pixels);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out, .data = raw });
    }
    const b = nonzeroBounds(&target);
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.print("engine=cangjie\tformat=premul-rgba8\twidth={d}\theight={d}\tleft={d}\ttop={d}\tright={d}\tbottom={d}\tchecksum={x:0>16}\tmedian_ns_per_iter={d:.3}\n", .{ width, height, b.left, b.top, b.right, b.bottom, pixelHash(target.pixels), @as(f64, @floatFromInt(times.items[times.items.len / 2])) / @as(f64, @floatFromInt(iterations)) });
    try std.Io.File.stdout().writeStreamingAll(init.io, writer.buffered());
}

fn number(comptime T: type, raw: ?[]const u8) !T {
    const value = raw orelse return error.InvalidArguments;
    return switch (@typeInfo(T)) {
        .int => std.fmt.parseInt(T, value, 10),
        .float => std.fmt.parseFloat(T, value),
        else => @compileError("unsupported option type"),
    };
}

fn parseCoords(raw: []const u8, storage: *[64]f32) ![]const f32 {
    if (std.mem.eql(u8, raw, "-")) return &.{};
    var count: usize = 0;
    var values = std.mem.splitScalar(u8, raw, ',');
    while (values.next()) |text| {
        if (count == storage.len or text.len == 0) return error.InvalidArguments;
        const value = try std.fmt.parseFloat(f32, text);
        if (!std.math.isFinite(value) or value < -1 or value > 1) return error.InvalidArguments;
        storage[count] = value;
        count += 1;
    }
    return storage[0..count];
}

fn pixelHash(pixels: []const cangjie.render.Rgba) u64 {
    const bytes: []const u8 = @ptrCast(pixels);
    var result: u64 = 0xcbf29ce484222325;
    for (bytes) |byte| result = (result ^ byte) *% 0x100000001b3;
    return result;
}

const Bounds = struct { left: u32 = 0, top: u32 = 0, right: u32 = 0, bottom: u32 = 0 };
fn nonzeroBounds(target: *const cangjie.render.ColorTarget) Bounds {
    var result = Bounds{ .left = target.width, .top = target.height };
    var found = false;
    for (0..target.height) |y| for (0..target.width) |x| {
        if (target.at(@intCast(x), @intCast(y)).a == 0) continue;
        found = true;
        result.left = @min(result.left, @as(u32, @intCast(x)));
        result.top = @min(result.top, @as(u32, @intCast(y)));
        result.right = @max(result.right, @as(u32, @intCast(x + 1)));
        result.bottom = @max(result.bottom, @as(u32, @intCast(y + 1)));
    };
    return if (found) result else .{};
}

test "normalized coordinates are bounded" {
    var storage: [64]f32 = undefined;
    try std.testing.expectEqualSlices(f32, &.{ 0.5, -1 }, try parseCoords("0.5,-1", &storage));
    try std.testing.expectError(error.InvalidArguments, parseCoords("1.1", &storage));
}
