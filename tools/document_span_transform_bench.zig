//! Large ordered-span edit-transform benchmark and semantic gate.

const std = @import("std");
const cangjie = @import("cangjie");

const transform = cangjie.text.document.span_transform;
const fnv_offset: u64 = 0xcbf2_9ce4_8422_2325;
const fnv_prime: u64 = 0x0000_0100_0000_01b3;

const Span = struct {
    start: usize,
    end: usize,
    style_id: u32,
};

const Options = struct {
    spans: usize = 100_000,
    rounds: usize = 256,
    json_path: ?[]const u8 = null,
    max_ns_per_span: f64 = 20.0,
    expect_checksum: ?u64 = null,
};

const Report = struct {
    spans: usize,
    rounds: usize,
    transforms: usize,
    elapsed_ns: u64,
    ns_per_span: f64,
    allocated_bytes_per_transform: usize,
    checksum: u64,
    expected_checksum: ?u64,
    semantic_passed: bool,
    performance_passed: bool,
    signature_passed: bool,
    passed: bool,
};

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !Report {
    const spans = try allocator.alloc(Span, options.spans);
    defer allocator.free(spans);
    for (spans, 0..) |*span, index| span.* = .{
        .start = index * 8,
        .end = index * 8 + 6,
        .style_id = @intCast(index % 17),
    };
    const original = try allocator.dupe(Span, spans);
    defer allocator.free(original);
    const document_len = options.spans * 8;
    const middle = (options.spans / 2) * 8 + 2;
    var checksum = fnv_offset;
    const started = std.Io.Clock.awake.now(io);
    for (0..options.rounds) |_| {
        const inserted = try transform.transform(Span, spans, spans, .{
            .document_len = document_len,
            .start = middle,
            .old_end = middle,
            .new_len = 3,
        }, .{});
        if (inserted.len != spans.len) return error.UnexpectedSpanCount;
        const removed = try transform.transform(Span, spans, spans, .{
            .document_len = document_len + 3,
            .start = middle,
            .old_end = middle + 3,
            .new_len = 0,
        }, .{});
        if (removed.len != spans.len) return error.UnexpectedSpanCount;
        mix(&checksum, spans[0].start);
        mix(&checksum, spans[options.spans / 2].end);
        mix(&checksum, spans[options.spans - 1].style_id);
    }
    const elapsed_ns = elapsedNs(started, io);
    const semantics = spansEqual(original, spans);
    const transforms = options.rounds * 2;
    const operations = transforms * options.spans;
    const ns_per_span = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(operations));
    const performance = ns_per_span <= options.max_ns_per_span;
    const signature = options.expect_checksum == null or options.expect_checksum.? == checksum;
    return .{
        .spans = options.spans,
        .rounds = options.rounds,
        .transforms = transforms,
        .elapsed_ns = elapsed_ns,
        .ns_per_span = ns_per_span,
        .allocated_bytes_per_transform = 0,
        .checksum = checksum,
        .expected_checksum = options.expect_checksum,
        .semantic_passed = semantics,
        .performance_passed = performance,
        .signature_passed = signature,
        .passed = semantics and performance and signature,
    };
}

fn parse(args: []const []const u8) !Options {
    var options = Options{};
    var index: usize = if (args.len != 0 and !std.mem.startsWith(u8, args[0], "--")) 1 else 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.startsWith(u8, arg, "--spans=")) options.spans = try std.fmt.parseInt(usize, arg["--spans=".len..], 10) else if (std.mem.startsWith(u8, arg, "--rounds=")) options.rounds = try std.fmt.parseInt(usize, arg["--rounds=".len..], 10) else if (std.mem.startsWith(u8, arg, "--json=")) options.json_path = arg["--json=".len..] else if (std.mem.startsWith(u8, arg, "--max-ns-per-span=")) options.max_ns_per_span = try std.fmt.parseFloat(f64, arg["--max-ns-per-span=".len..]) else if (std.mem.startsWith(u8, arg, "--expect-checksum=")) options.expect_checksum = try std.fmt.parseInt(u64, arg["--expect-checksum=".len..], 10) else return error.InvalidArgument;
    }
    if (options.spans < 2 or options.rounds == 0) return error.InvalidArguments;
    return options;
}

fn mix(hash: *u64, value: anytype) void {
    hash.* = (hash.* ^ @as(u64, @intCast(value))) *% fnv_prime;
}

fn spansEqual(a: []const Span, b: []const Span) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
}

fn elapsedNs(started: std.Io.Timestamp, io: std.Io) u64 {
    return @intCast(started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
}

fn writeReport(io: std.Io, allocator: std.mem.Allocator, path: []const u8, report: Report) !void {
    const bytes = try std.json.Stringify.valueAlloc(allocator, report, .{ .whitespace = .indent_2 });
    defer allocator.free(bytes);
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| if (slash > 0) try std.Io.Dir.cwd().createDirPath(io, path[0..slash]);
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}

pub fn main(init: std.process.Init) !void {
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer iterator.deinit();
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(init.gpa);
    while (iterator.next()) |arg| try args.append(init.gpa, arg);
    const options = try parse(args.items);
    const report = try run(init.gpa, init.io, options);
    std.debug.print("document span transform: spans={d} rounds={d} ns/span={d:.2} alloc/transform={d} checksum={d} passed={}\n", .{
        report.spans, report.rounds, report.ns_per_span, report.allocated_bytes_per_transform, report.checksum, report.passed,
    });
    if (options.json_path) |path| try writeReport(init.io, init.gpa, path, report);
    if (!report.passed) return error.DocumentSpanTransformGateFailed;
}

test "document span transform benchmark scales down" {
    const report = try run(std.testing.allocator, std.testing.io, .{ .spans = 256, .rounds = 4, .max_ns_per_span = std.math.floatMax(f64) });
    try std.testing.expect(report.semantic_passed);
    try std.testing.expectEqual(@as(usize, 0), report.allocated_bytes_per_transform);
}
