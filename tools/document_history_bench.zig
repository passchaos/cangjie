//! Million-line incremental document history benchmark and semantic gate.

const std = @import("std");
const builtin = @import("builtin");
const cangjie = @import("cangjie");

const line_text = "0123456789abcdef chunked document line\n";
const replacement = "Z";
const fnv_offset: u64 = 0xcbf2_9ce4_8422_2325;
const fnv_prime: u64 = 0x0000_0100_0000_01b3;

const Options = struct {
    lines: usize = 1_000_000,
    transactions: usize = 1_024,
    json_path: ?[]const u8 = null,
    max_record_ns_per_op: u64 = 100_000,
    max_undo_ns_per_op: u64 = 100_000,
    max_redo_ns_per_op: u64 = 100_000,
    max_history_bytes: usize = 1024 * 1024,
    max_total_owned_bytes: usize = 52 * 1024 * 1024,
    max_rss_kib: usize = 196 * 1024,
    expect_checksum: ?u64 = null,
};

const Report = struct {
    lines: usize,
    source_bytes: usize,
    transactions: usize,
    record_ns_per_op: f64,
    undo_ns_per_op: f64,
    redo_ns_per_op: f64,
    history_entries: usize,
    history_payload_bytes: usize,
    history_retained_bytes: usize,
    total_owned_bytes: usize,
    peak_rss_kib: usize,
    checksum: u64,
    expected_checksum: ?u64,
    semantic_passed: bool,
    performance_passed: bool,
    memory_passed: bool,
    signature_passed: bool,
    passed: bool,
};

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !Report {
    const source_len = try std.math.mul(usize, options.lines, line_text.len);
    const source = try allocator.alloc(u8, source_len);
    defer allocator.free(source);
    for (0..options.lines) |line| {
        const start = line * line_text.len;
        @memcpy(source[start..][0..line_text.len], line_text);
    }
    var document = try cangjie.text.document.Document.init(allocator, source);
    defer document.deinit();
    var history = cangjie.text.document.History.init(allocator, options.transactions, options.max_history_bytes);
    defer history.deinit();

    var checksum = fnv_offset;
    var random: u64 = 0x6869_7374_6f72_7921;
    const record_started = std.Io.Clock.awake.now(io);
    for (0..options.transactions) |_| {
        random = nextRandom(random);
        const line = @as(usize, @intCast(random % options.lines));
        const start = (try document.lineStart(line)) + 8;
        const result = (try history.replaceRange(&document, start, start + 1, replacement, .{
            .before_selection = .{ .anchor = start, .cursor = start + 1 },
            .after_selection = .{ .anchor = start + 1, .cursor = start + 1 },
            .action_name = "Replace",
        })) orelse return error.MissingRecordedEdit;
        mix(&checksum, result.edit.start);
        mix(&checksum, result.edit.revision);
    }
    const record_ns = elapsedNs(record_started, io);
    const edited_checksum = try hashDocument(&document, checksum);

    const undo_started = std.Io.Clock.awake.now(io);
    for (0..options.transactions) |_| _ = (try history.undo(&document)) orelse return error.MissingUndo;
    const undo_ns = elapsedNs(undo_started, io);
    const restored = try document.materialize(allocator);
    defer allocator.free(restored);
    const restored_original = std.mem.eql(u8, restored, source);

    const redo_started = std.Io.Clock.awake.now(io);
    for (0..options.transactions) |_| _ = (try history.redo(&document)) orelse return error.MissingRedo;
    const redo_ns = elapsedNs(redo_started, io);
    const final_checksum = try hashDocument(&document, edited_checksum);
    const diagnostics = history.diagnostics();
    const document_diagnostics = document.diagnostics();
    const total_owned_bytes = diagnostics.retained_bytes + document_diagnostics.owned_bytes;
    const peak_rss_kib = processPeakRssKib();
    const semantic = restored_original and diagnostics.undo_entries == options.transactions and diagnostics.redo_entries == 0 and
        diagnostics.recorded_count == options.transactions and diagnostics.undo_count == options.transactions and
        diagnostics.redo_count == options.transactions and diagnostics.failure_count == 0;
    const performance = record_ns <= options.max_record_ns_per_op * options.transactions and
        undo_ns <= options.max_undo_ns_per_op * options.transactions and
        redo_ns <= options.max_redo_ns_per_op * options.transactions;
    const memory = diagnostics.retained_bytes <= options.max_history_bytes and total_owned_bytes <= options.max_total_owned_bytes and
        (peak_rss_kib == 0 or peak_rss_kib <= options.max_rss_kib);
    const signature = options.expect_checksum == null or options.expect_checksum.? == final_checksum;
    return .{
        .lines = options.lines,
        .source_bytes = source_len,
        .transactions = options.transactions,
        .record_ns_per_op = ratio(record_ns, options.transactions),
        .undo_ns_per_op = ratio(undo_ns, options.transactions),
        .redo_ns_per_op = ratio(redo_ns, options.transactions),
        .history_entries = diagnostics.undo_entries,
        .history_payload_bytes = diagnostics.payload_bytes,
        .history_retained_bytes = diagnostics.retained_bytes,
        .total_owned_bytes = total_owned_bytes,
        .peak_rss_kib = peak_rss_kib,
        .checksum = final_checksum,
        .expected_checksum = options.expect_checksum,
        .semantic_passed = semantic,
        .performance_passed = performance,
        .memory_passed = memory,
        .signature_passed = signature,
        .passed = semantic and performance and memory and signature,
    };
}

fn hashDocument(document: *const cangjie.text.document.Document, seed: u64) !u64 {
    var hash = seed;
    var chunks = try document.chunks(.{ .start = 0, .end = document.byteLen() });
    while (chunks.next()) |chunk| for (chunk.bytes) |byte| mix(&hash, byte);
    return hash;
}

fn nextRandom(value: u64) u64 {
    return value *% 6364136223846793005 +% 1442695040888963407;
}

fn mix(hash: *u64, value: anytype) void {
    hash.* = (hash.* ^ @as(u64, @intCast(value))) *% fnv_prime;
}

fn ratio(elapsed: u64, count: usize) f64 {
    return @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(count));
}

fn elapsedNs(started: std.Io.Timestamp, io: std.Io) u64 {
    return @intCast(started.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
}

fn processPeakRssKib() usize {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return 0;
    const usage = std.posix.getrusage(0);
    const raw: usize = @intCast(@max(@as(isize, 0), usage.maxrss));
    return switch (builtin.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos => raw / 1024,
        else => raw,
    };
}

fn parse(args: []const []const u8) !Options {
    var out = Options{};
    var index: usize = if (args.len > 0 and !std.mem.startsWith(u8, args[0], "--")) 1 else 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.startsWith(u8, arg, "--lines=")) out.lines = try std.fmt.parseInt(usize, arg["--lines=".len..], 10) else if (std.mem.startsWith(u8, arg, "--transactions=")) out.transactions = try std.fmt.parseInt(usize, arg["--transactions=".len..], 10) else if (std.mem.startsWith(u8, arg, "--json=")) out.json_path = arg["--json=".len..] else if (std.mem.startsWith(u8, arg, "--max-record-ns-per-op=")) out.max_record_ns_per_op = try std.fmt.parseInt(u64, arg["--max-record-ns-per-op=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-undo-ns-per-op=")) out.max_undo_ns_per_op = try std.fmt.parseInt(u64, arg["--max-undo-ns-per-op=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-redo-ns-per-op=")) out.max_redo_ns_per_op = try std.fmt.parseInt(u64, arg["--max-redo-ns-per-op=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-history-bytes=")) out.max_history_bytes = try std.fmt.parseInt(usize, arg["--max-history-bytes=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-total-owned-bytes=")) out.max_total_owned_bytes = try std.fmt.parseInt(usize, arg["--max-total-owned-bytes=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-rss-kib=")) out.max_rss_kib = try std.fmt.parseInt(usize, arg["--max-rss-kib=".len..], 10) else if (std.mem.startsWith(u8, arg, "--expect-checksum=")) out.expect_checksum = try std.fmt.parseInt(u64, arg["--expect-checksum=".len..], 10) else return error.InvalidArgument;
    }
    if (out.lines < 256 or out.transactions == 0) return error.InvalidArguments;
    return out;
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
    std.debug.print(
        "document history: lines={d} bytes={d} txns={d} record={d:.1}ns/op undo={d:.1}ns/op redo={d:.1}ns/op payload={d}B retained={d}B total={d:.2}MiB rss={d:.2}MiB checksum={d} passed={}\n",
        .{ report.lines, report.source_bytes, report.transactions, report.record_ns_per_op, report.undo_ns_per_op, report.redo_ns_per_op, report.history_payload_bytes, report.history_retained_bytes, @as(f64, @floatFromInt(report.total_owned_bytes)) / (1024.0 * 1024.0), @as(f64, @floatFromInt(report.peak_rss_kib)) / 1024.0, report.checksum, report.passed },
    );
    if (options.json_path) |path| try writeReport(init.io, init.gpa, path, report);
    if (!report.passed) return error.DocumentHistoryGateFailed;
}

test "document history benchmark scales down" {
    const report = try run(std.testing.allocator, std.testing.io, .{
        .lines = 4096,
        .transactions = 32,
        .max_rss_kib = std.math.maxInt(usize),
    });
    try std.testing.expect(report.semantic_passed);
    try std.testing.expect(report.memory_passed);
}
