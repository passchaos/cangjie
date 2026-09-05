//! Stable font descriptor codec and worst-position resolver benchmark.

const std = @import("std");
const cangjie = @import("cangjie");
const database = cangjie.font.database;

const Options = struct {
    faces: usize = 4096,
    iterations: usize = 20_000,
    max_exact_ns_per_query: f64 = 100_000,
    max_portable_ns_per_query: f64 = 100_000,
    max_codec_ns_per_roundtrip: f64 = 10_000,
    max_instance_codec_ns_per_roundtrip: f64 = 10_000,
    expect_checksum: ?u64 = null,
    json_path: ?[]const u8 = null,
};

const Report = struct {
    faces: usize,
    iterations: usize,
    exact_ns_per_query: f64,
    portable_ns_per_query: f64,
    codec_ns_per_roundtrip: f64,
    instance_codec_ns_per_roundtrip: f64,
    descriptor_bytes: usize,
    instance_descriptor_bytes: usize,
    checksum: u64,
    expected_checksum: ?u64,
    semantic_passed: bool,
    performance_passed: bool,
    signature_passed: bool,
    passed: bool,
};

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !Report {
    const candidates = try allocator.alloc(database.DescriptorCandidate, options.faces);
    defer allocator.free(candidates);
    const names = try allocator.alloc([48]u8, options.faces);
    defer allocator.free(names);
    const name_lengths = try allocator.alloc(usize, options.faces);
    defer allocator.free(name_lengths);

    for (candidates, 0..) |*candidate, index| {
        const name = try std.fmt.bufPrint(&names[index], "BenchFace-{d:0>5}", .{index});
        name_lengths[index] = name.len;
        var digest: database.DescriptorDigest = undefined;
        @memset(&digest, @intCast(index & 0xff));
        candidate.* = .{
            .family = "Benchmark Sans",
            .subfamily = "Regular",
            .postscript_name = names[index][0..name.len],
            .weight = 400,
            .stretch = 100,
            .style = .normal,
            .source_digest = digest,
            .source_size = 100_000 + index,
            .face_index = @intCast(index),
        };
    }
    const target = candidates[options.faces - 1];
    const exact = try database.Descriptor.init(.{
        .family = target.family,
        .subfamily = target.subfamily,
        .postscript_name = target.postscript_name,
        .source_digest = target.source_digest,
        .source_size = target.source_size,
        .face_index = target.face_index,
    });
    const portable = try database.Descriptor.init(.{
        .family = "ignored",
        .subfamily = target.subfamily,
        .postscript_name = target.postscript_name,
    });

    var checksum: u64 = 0xcbf2_9ce4_8422_2325;
    const exact_started = std.Io.Clock.awake.now(io);
    for (0..options.iterations) |_| {
        const resolved = database.resolveDescriptorCandidates(candidates, exact, .exact);
        if (resolved.status != .exact_content or resolved.face_index != options.faces - 1) return error.ExactResolutionFailed;
        mix(&checksum, resolved.face_index.?);
    }
    const exact_ns = elapsedNs(exact_started, io);

    const portable_started = std.Io.Clock.awake.now(io);
    for (0..options.iterations) |_| {
        const resolved = database.resolveDescriptorCandidates(candidates, portable, .portable);
        if (resolved.status != .postscript or resolved.face_index != options.faces - 1) return error.PortableResolutionFailed;
        mix(&checksum, resolved.face_index.?);
    }
    const portable_ns = elapsedNs(portable_started, io);

    var wire: [database.descriptor_wire_size]u8 = undefined;
    const codec_started = std.Io.Clock.awake.now(io);
    for (0..options.iterations) |_| {
        const encoded = try database.encodeDescriptor(exact, &wire);
        const decoded = try database.decodeDescriptor(encoded);
        mix(&checksum, decoded.fingerprint());
    }
    const codec_ns = elapsedNs(codec_started, io);

    const instance = try database.InstanceDescriptor.init(exact, &.{0.5});
    var instance_wire: [database.instance_descriptor_wire_size]u8 = undefined;
    const instance_codec_started = std.Io.Clock.awake.now(io);
    for (0..options.iterations) |_| {
        const encoded = try database.encodeInstanceDescriptor(
            instance,
            &instance_wire,
        );
        const decoded = try database.decodeInstanceDescriptor(encoded);
        mix(&checksum, decoded.fingerprint());
    }
    const instance_codec_ns = elapsedNs(instance_codec_started, io);

    const exact_per = perOperation(exact_ns, options.iterations);
    const portable_per = perOperation(portable_ns, options.iterations);
    const codec_per = perOperation(codec_ns, options.iterations);
    const instance_codec_per = perOperation(instance_codec_ns, options.iterations);
    const semantic = exact.valid() and portable.valid() and instance.valid() and
        database.descriptor_wire_size == 644 and
        database.instance_descriptor_wire_size == 716;
    const performance = exact_per <= options.max_exact_ns_per_query and portable_per <= options.max_portable_ns_per_query and
        codec_per <= options.max_codec_ns_per_roundtrip and
        instance_codec_per <= options.max_instance_codec_ns_per_roundtrip;
    const signature = options.expect_checksum == null or options.expect_checksum.? == checksum;
    return .{
        .faces = options.faces,
        .iterations = options.iterations,
        .exact_ns_per_query = exact_per,
        .portable_ns_per_query = portable_per,
        .codec_ns_per_roundtrip = codec_per,
        .instance_codec_ns_per_roundtrip = instance_codec_per,
        .descriptor_bytes = database.descriptor_wire_size,
        .instance_descriptor_bytes = database.instance_descriptor_wire_size,
        .checksum = checksum,
        .expected_checksum = options.expect_checksum,
        .semantic_passed = semantic,
        .performance_passed = performance,
        .signature_passed = signature,
        .passed = semantic and performance and signature,
    };
}

fn parse(args: []const []const u8) !Options {
    var out = Options{};
    var index: usize = if (args.len != 0 and !std.mem.startsWith(u8, args[0], "--")) 1 else 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.startsWith(u8, arg, "--faces=")) out.faces = try std.fmt.parseInt(usize, arg["--faces=".len..], 10) else if (std.mem.startsWith(u8, arg, "--iterations=")) out.iterations = try std.fmt.parseInt(usize, arg["--iterations=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-exact-ns-per-query=")) out.max_exact_ns_per_query = try std.fmt.parseFloat(f64, arg["--max-exact-ns-per-query=".len..]) else if (std.mem.startsWith(u8, arg, "--max-portable-ns-per-query=")) out.max_portable_ns_per_query = try std.fmt.parseFloat(f64, arg["--max-portable-ns-per-query=".len..]) else if (std.mem.startsWith(u8, arg, "--max-codec-ns-per-roundtrip=")) out.max_codec_ns_per_roundtrip = try std.fmt.parseFloat(f64, arg["--max-codec-ns-per-roundtrip=".len..]) else if (std.mem.startsWith(u8, arg, "--max-instance-codec-ns-per-roundtrip=")) out.max_instance_codec_ns_per_roundtrip = try std.fmt.parseFloat(f64, arg["--max-instance-codec-ns-per-roundtrip=".len..]) else if (std.mem.startsWith(u8, arg, "--expect-checksum=")) out.expect_checksum = try std.fmt.parseInt(u64, arg["--expect-checksum=".len..], 10) else if (std.mem.startsWith(u8, arg, "--json=")) out.json_path = arg["--json=".len..] else return error.InvalidArgument;
    }
    if (out.faces == 0 or out.iterations == 0) return error.InvalidArguments;
    return out;
}

fn perOperation(elapsed: u64, count: usize) f64 {
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}

fn elapsedNs(started: std.Io.Timestamp, io: std.Io) u64 {
    return @intCast(started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
}

fn mix(hash: *u64, value: anytype) void {
    hash.* = (hash.* ^ @as(u64, @intCast(value))) *% 0x0000_0100_0000_01b3;
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
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(init.gpa);
    while (iterator.next()) |arg| try args.append(init.gpa, arg);
    const options = try parse(args.items);
    const report = try run(init.gpa, init.io, options);
    std.debug.print("font descriptor: faces={d} iterations={d} exact={d:.1}ns portable={d:.1}ns face-codec={d:.1}ns/{d}B instance-codec={d:.1}ns/{d}B checksum={d} passed={}\n", .{ report.faces, report.iterations, report.exact_ns_per_query, report.portable_ns_per_query, report.codec_ns_per_roundtrip, report.descriptor_bytes, report.instance_codec_ns_per_roundtrip, report.instance_descriptor_bytes, report.checksum, report.passed });
    if (options.json_path) |path| try writeReport(init.io, init.gpa, path, report);
    if (!report.passed) return error.FontDescriptorGateFailed;
}

test "font descriptor benchmark scales down" {
    const report = try run(std.testing.allocator, std.testing.io, .{
        .faces = 64,
        .iterations = 64,
        .max_exact_ns_per_query = std.math.inf(f64),
        .max_portable_ns_per_query = std.math.inf(f64),
        .max_codec_ns_per_roundtrip = std.math.inf(f64),
        .max_instance_codec_ns_per_roundtrip = std.math.inf(f64),
    });
    try std.testing.expect(report.semantic_passed);
}
