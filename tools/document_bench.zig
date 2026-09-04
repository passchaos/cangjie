//! Million-line chunked UTF-8 document benchmark and semantic gate.

const std = @import("std");
const builtin = @import("builtin");
const cangjie = @import("cangjie");

const default_lines: usize = 1_000_000;
const default_queries: usize = 10_000;
const default_edit_pairs: usize = 2_048;
const line_text = "0123456789abcdef chunked document line\n";
const inserted_text = "INSERTED-中\nexpanded";
const fnv_offset: u64 = 0xcbf2_9ce4_8422_2325;
const fnv_prime: u64 = 0x0000_0100_0000_01b3;

const Options = struct {
    lines: usize = default_lines,
    queries: usize = default_queries,
    edit_pairs: usize = default_edit_pairs,
    json_path: ?[]const u8 = null,
    max_source_build_ns: u64 = 100_000_000,
    max_init_ns: u64 = 150_000_000,
    max_grow_ns: u64 = 1_000_000,
    max_shrink_ns: u64 = 1_000_000,
    max_delete_ns: u64 = 1_000_000,
    max_churn_ns_per_edit: u64 = 100_000,
    min_contiguous_speedup: f64 = 5.0,
    max_query_ns_per_op: u64 = 10_000,
    max_chunk_scan_ns: u64 = 500_000,
    max_materialize_ns: u64 = 250_000_000,
    max_snapshot_ns: u64 = 20_000_000,
    max_snapshot_owned_bytes: usize = 2 * 1024 * 1024,
    max_owned_bytes: usize = 48 * 1024 * 1024,
    max_rss_kib: usize = 192 * 1024,
    max_tree_depth: usize = 64,
    expect_checksum: ?u64 = null,
};

const Report = struct {
    lines: usize,
    initial_bytes: usize,
    final_bytes: usize,
    source_build_ns: u64,
    init_ns: u64,
    grow_insert_ns: u64,
    shrink_replace_ns: u64,
    inserted_delete_ns: u64,
    contiguous_grow_insert_ns: u64,
    contiguous_shrink_replace_ns: u64,
    contiguous_inserted_delete_ns: u64,
    grow_speedup: f64,
    shrink_speedup: f64,
    delete_speedup: f64,
    min_contiguous_speedup: f64,
    edit_pairs: usize,
    churn_edit_operations: usize,
    churn_edit_ns: u64,
    churn_edit_ns_per_op: f64,
    query_operations: usize,
    query_ns: u64,
    query_ns_per_op: f64,
    chunk_scan_ns: u64,
    chunk_scan_bytes: usize,
    materialize_ns: u64,
    snapshot_ns: u64,
    snapshot_pieces: usize,
    snapshot_owned_bytes: usize,
    snapshot_shared_original_bytes: usize,
    snapshot_shared_addition_bytes: usize,
    initial_pieces: usize,
    pieces: usize,
    node_slots: usize,
    tree_depth: usize,
    original_bytes: usize,
    addition_bytes: usize,
    owned_bytes: usize,
    peak_rss_kib: usize,
    revision: u64,
    checksum: u64,
    expected_checksum: ?u64,
    semantic_passed: bool,
    performance_passed: bool,
    memory_passed: bool,
    signature_passed: bool,
    passed: bool,
};

fn run(allocator: std.mem.Allocator, io: std.Io, options: Options) !Report {
    const initial_len = try std.math.mul(usize, options.lines, line_text.len);
    const source_started = std.Io.Clock.awake.now(io);
    const source = try allocator.alloc(u8, initial_len);
    defer allocator.free(source);
    for (0..options.lines) |line| {
        const start = line * line_text.len;
        @memcpy(source[start..][0..line_text.len], line_text);
    }
    const source_build_ns = elapsedNs(source_started, io);

    const init_started = std.Io.Clock.awake.now(io);
    var document = try cangjie.text.document.Document.init(allocator, source);
    defer document.deinit();
    const init_ns = elapsedNs(init_started, io);
    const initial_pieces = document.pieceCount();

    const middle_line = options.lines / 2;
    const middle = (try document.lineStart(middle_line)) + 8;
    const before_grow_revision = document.revision();
    const grow_started = std.Io.Clock.awake.now(io);
    const grow = (try document.replaceRange(middle, middle, inserted_text)) orelse return error.MissingGrowEdit;
    const grow_insert_ns = elapsedNs(grow_started, io);
    const grow_summary = document.editSince(before_grow_revision) orelse return error.MissingGrowSummary;

    const shrink_line = (options.lines * 3) / 4;
    const shrink_start = (try document.lineStart(shrink_line)) + 4;
    const before_shrink_revision = document.revision();
    const shrink_started = std.Io.Clock.awake.now(io);
    const shrink = (try document.replaceRange(shrink_start, shrink_start + 10, "Q")) orelse return error.MissingShrinkEdit;
    const shrink_replace_ns = elapsedNs(shrink_started, io);
    const shrink_summary = document.editSince(before_shrink_revision) orelse return error.MissingShrinkSummary;

    const before_delete_revision = document.revision();
    const delete_started = std.Io.Clock.awake.now(io);
    const deleted = (try document.replaceRange(middle, middle + inserted_text.len, "")) orelse return error.MissingDeleteEdit;
    const inserted_delete_ns = elapsedNs(delete_started, io);
    const delete_summary = document.editSince(before_delete_revision) orelse return error.MissingDeleteSummary;

    var contiguous = std.ArrayList(u8).empty;
    defer contiguous.deinit(allocator);
    try contiguous.ensureTotalCapacity(allocator, initial_len + inserted_text.len);
    contiguous.appendSliceAssumeCapacity(source);
    const contiguous_grow_started = std.Io.Clock.awake.now(io);
    try contiguous.replaceRange(allocator, middle, 0, inserted_text);
    const contiguous_grow_insert_ns = elapsedNs(contiguous_grow_started, io);
    const contiguous_shrink_started = std.Io.Clock.awake.now(io);
    try contiguous.replaceRange(allocator, shrink_start, 10, "Q");
    const contiguous_shrink_replace_ns = elapsedNs(contiguous_shrink_started, io);
    const contiguous_delete_started = std.Io.Clock.awake.now(io);
    try contiguous.replaceRange(allocator, middle, inserted_text.len, "");
    const contiguous_inserted_delete_ns = elapsedNs(contiguous_delete_started, io);

    var churn_random: u64 = 0x7069_6563_652d_7472;
    const churn_started = std.Io.Clock.awake.now(io);
    for (0..options.edit_pairs) |_| {
        churn_random = churn_random *% 6364136223846793005 +% 1442695040888963407;
        const line = 1 + @as(usize, @intCast(churn_random % (document.lineCount() - 2)));
        const edit_at = (try document.lineStart(line)) + 8;
        _ = (try document.replaceRange(edit_at, edit_at, "z\n")) orelse return error.MissingChurnInsert;
        if (document.lineCount() != options.lines + 2) return error.ChurnLineInsertFailed;
        _ = (try document.replaceRange(edit_at, edit_at + 2, "")) orelse return error.MissingChurnDelete;
        if (document.lineCount() != options.lines + 1) return error.ChurnLineDeleteFailed;
    }
    const churn_edit_ns = elapsedNs(churn_started, io);
    const churn_edit_operations = options.edit_pairs * 2;

    var checksum = fnv_offset;
    var random: u64 = 0x6361_6e67_6a69_652d;
    const query_started = std.Io.Clock.awake.now(io);
    for (0..options.queries) |_| {
        random = random *% 6364136223846793005 +% 1442695040888963407;
        const line = @as(usize, @intCast(random % document.lineCount()));
        const range = try document.lineRange(line);
        const column = @min(@as(usize, 7), range.len());
        const point = cangjie.text.document.Point{ .line = line, .column = column };
        const byte = try document.byteForPoint(point);
        const roundtrip = try document.pointForByte(byte);
        mix(&checksum, line);
        mix(&checksum, range.start);
        mix(&checksum, range.end);
        mix(&checksum, byte);
        mix(&checksum, roundtrip.line);
        mix(&checksum, roundtrip.column);
    }
    const query_ns = elapsedNs(query_started, io);

    const window_start = try document.lineStart(middle_line - 32);
    const window_end = try document.lineStart(middle_line + 32);
    const chunk_started = std.Io.Clock.awake.now(io);
    var iterator = try document.chunks(.{ .start = window_start, .end = window_end });
    var chunk_scan_bytes: usize = 0;
    while (iterator.next()) |chunk| {
        chunk_scan_bytes += chunk.bytes.len;
        for (chunk.bytes) |byte| mix(&checksum, byte);
    }
    const chunk_scan_ns = elapsedNs(chunk_started, io);

    const materialize_started = std.Io.Clock.awake.now(io);
    const bytes = try document.materialize(allocator);
    defer allocator.free(bytes);
    for (bytes) |byte| mix(&checksum, byte);
    const materialize_ns = elapsedNs(materialize_started, io);

    const snapshot_started = std.Io.Clock.awake.now(io);
    var snapshot = try document.snapshot(allocator);
    defer snapshot.deinit();
    const snapshot_ns = elapsedNs(snapshot_started, io);
    const snapshot_diagnostics = snapshot.diagnostics();
    const snapshot_probe_line = options.lines / 3;
    const snapshot_probe_range = try snapshot.lineRange(snapshot_probe_line);
    const snapshot_probe_point = try snapshot.pointForByte(snapshot_probe_range.start);

    const diagnostics = document.diagnostics();
    mix(&checksum, diagnostics.pieces);
    mix(&checksum, diagnostics.node_slots);
    mix(&checksum, diagnostics.tree_depth);
    mix(&checksum, diagnostics.addition_bytes);
    mix(&checksum, document.revision());
    const expected_final_len = initial_len - 9;
    const semantic = document.lineCount() == options.lines + 1 and
        document.byteLen() == expected_final_len and bytes.len == expected_final_len and
        grow.old_bytes == 0 and grow.new_bytes == inserted_text.len and grow.new_newlines == 1 and
        grow_summary.revision == grow.revision and shrink.old_bytes == 10 and shrink.new_bytes == 1 and
        shrink.old_newlines == 0 and shrink.new_newlines == 0 and shrink_summary.revision == shrink.revision and
        deleted.old_bytes == inserted_text.len and deleted.new_bytes == 0 and deleted.old_newlines == 1 and
        delete_summary.revision == deleted.revision and chunk_scan_bytes == window_end - window_start and
        document.revision() == 3 + churn_edit_operations and std.mem.eql(u8, bytes, contiguous.items) and
        diagnostics.pieces >= initial_pieces and diagnostics.pieces <= initial_pieces + 8 and
        snapshot.identity() == document.identity() and snapshot.revision() == document.revision() and
        snapshot.byteLen() == document.byteLen() and snapshot.lineCount() == document.lineCount() and
        snapshot.pieceCount() == diagnostics.pieces and snapshot_probe_point.line == snapshot_probe_line and
        snapshot_probe_point.column == 0 and snapshot_diagnostics.shared_original_bytes == diagnostics.original_bytes and
        snapshot_diagnostics.shared_addition_bytes == diagnostics.addition_bytes and
        snapshot_diagnostics.owned_bytes == snapshot_diagnostics.metadata_bytes;
    const performance = source_build_ns <= options.max_source_build_ns and init_ns <= options.max_init_ns and
        grow_insert_ns <= options.max_grow_ns and shrink_replace_ns <= options.max_shrink_ns and
        inserted_delete_ns <= options.max_delete_ns and
        ratio(contiguous_grow_insert_ns, grow_insert_ns) >= options.min_contiguous_speedup and
        ratio(contiguous_shrink_replace_ns, shrink_replace_ns) >= options.min_contiguous_speedup and
        ratio(contiguous_inserted_delete_ns, inserted_delete_ns) >= options.min_contiguous_speedup and
        churn_edit_ns <= options.max_churn_ns_per_edit * churn_edit_operations and
        query_ns <= options.max_query_ns_per_op * options.queries and chunk_scan_ns <= options.max_chunk_scan_ns and
        materialize_ns <= options.max_materialize_ns and snapshot_ns <= options.max_snapshot_ns;
    const peak_rss_kib = processPeakRssKib();
    const memory = diagnostics.owned_bytes <= options.max_owned_bytes and
        snapshot_diagnostics.owned_bytes <= options.max_snapshot_owned_bytes and diagnostics.tree_depth <= options.max_tree_depth and
        (peak_rss_kib == 0 or peak_rss_kib <= options.max_rss_kib);
    const signature = options.expect_checksum == null or options.expect_checksum.? == checksum;

    return .{
        .lines = options.lines,
        .initial_bytes = initial_len,
        .final_bytes = document.byteLen(),
        .source_build_ns = source_build_ns,
        .init_ns = init_ns,
        .grow_insert_ns = grow_insert_ns,
        .shrink_replace_ns = shrink_replace_ns,
        .inserted_delete_ns = inserted_delete_ns,
        .contiguous_grow_insert_ns = contiguous_grow_insert_ns,
        .contiguous_shrink_replace_ns = contiguous_shrink_replace_ns,
        .contiguous_inserted_delete_ns = contiguous_inserted_delete_ns,
        .grow_speedup = ratio(contiguous_grow_insert_ns, grow_insert_ns),
        .shrink_speedup = ratio(contiguous_shrink_replace_ns, shrink_replace_ns),
        .delete_speedup = ratio(contiguous_inserted_delete_ns, inserted_delete_ns),
        .min_contiguous_speedup = options.min_contiguous_speedup,
        .edit_pairs = options.edit_pairs,
        .churn_edit_operations = churn_edit_operations,
        .churn_edit_ns = churn_edit_ns,
        .churn_edit_ns_per_op = @as(f64, @floatFromInt(churn_edit_ns)) / @as(f64, @floatFromInt(churn_edit_operations)),
        .query_operations = options.queries,
        .query_ns = query_ns,
        .query_ns_per_op = @as(f64, @floatFromInt(query_ns)) / @as(f64, @floatFromInt(options.queries)),
        .chunk_scan_ns = chunk_scan_ns,
        .chunk_scan_bytes = chunk_scan_bytes,
        .materialize_ns = materialize_ns,
        .snapshot_ns = snapshot_ns,
        .snapshot_pieces = snapshot_diagnostics.pieces,
        .snapshot_owned_bytes = snapshot_diagnostics.owned_bytes,
        .snapshot_shared_original_bytes = snapshot_diagnostics.shared_original_bytes,
        .snapshot_shared_addition_bytes = snapshot_diagnostics.shared_addition_bytes,
        .initial_pieces = initial_pieces,
        .pieces = diagnostics.pieces,
        .node_slots = diagnostics.node_slots,
        .tree_depth = diagnostics.tree_depth,
        .original_bytes = diagnostics.original_bytes,
        .addition_bytes = diagnostics.addition_bytes,
        .owned_bytes = diagnostics.owned_bytes,
        .peak_rss_kib = peak_rss_kib,
        .revision = document.revision(),
        .checksum = checksum,
        .expected_checksum = options.expect_checksum,
        .semantic_passed = semantic,
        .performance_passed = performance,
        .memory_passed = memory,
        .signature_passed = signature,
        .passed = semantic and performance and memory and signature,
    };
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

fn mix(hash: *u64, value: anytype) void {
    hash.* = (hash.* ^ @as(u64, @intCast(value))) *% fnv_prime;
}

fn ratio(baseline: u64, candidate: u64) f64 {
    if (candidate == 0) return 0;
    return @as(f64, @floatFromInt(baseline)) / @as(f64, @floatFromInt(candidate));
}

fn parse(args: []const []const u8) !Options {
    var out = Options{};
    var index: usize = if (args.len > 0 and !std.mem.startsWith(u8, args[0], "--")) 1 else 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.startsWith(u8, arg, "--lines=")) out.lines = try std.fmt.parseInt(usize, arg["--lines=".len..], 10) else if (std.mem.startsWith(u8, arg, "--queries=")) out.queries = try std.fmt.parseInt(usize, arg["--queries=".len..], 10) else if (std.mem.startsWith(u8, arg, "--edit-pairs=")) out.edit_pairs = try std.fmt.parseInt(usize, arg["--edit-pairs=".len..], 10) else if (std.mem.startsWith(u8, arg, "--json=")) out.json_path = arg["--json=".len..] else if (std.mem.startsWith(u8, arg, "--max-source-build-ns=")) out.max_source_build_ns = try std.fmt.parseInt(u64, arg["--max-source-build-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-init-ns=")) out.max_init_ns = try std.fmt.parseInt(u64, arg["--max-init-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-grow-ns=")) out.max_grow_ns = try std.fmt.parseInt(u64, arg["--max-grow-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-shrink-ns=")) out.max_shrink_ns = try std.fmt.parseInt(u64, arg["--max-shrink-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-delete-ns=")) out.max_delete_ns = try std.fmt.parseInt(u64, arg["--max-delete-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-churn-ns-per-edit=")) out.max_churn_ns_per_edit = try std.fmt.parseInt(u64, arg["--max-churn-ns-per-edit=".len..], 10) else if (std.mem.startsWith(u8, arg, "--min-contiguous-speedup=")) out.min_contiguous_speedup = try std.fmt.parseFloat(f64, arg["--min-contiguous-speedup=".len..]) else if (std.mem.startsWith(u8, arg, "--max-query-ns-per-op=")) out.max_query_ns_per_op = try std.fmt.parseInt(u64, arg["--max-query-ns-per-op=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-chunk-scan-ns=")) out.max_chunk_scan_ns = try std.fmt.parseInt(u64, arg["--max-chunk-scan-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-materialize-ns=")) out.max_materialize_ns = try std.fmt.parseInt(u64, arg["--max-materialize-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-snapshot-ns=")) out.max_snapshot_ns = try std.fmt.parseInt(u64, arg["--max-snapshot-ns=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-snapshot-owned-bytes=")) out.max_snapshot_owned_bytes = try std.fmt.parseInt(usize, arg["--max-snapshot-owned-bytes=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-owned-bytes=")) out.max_owned_bytes = try std.fmt.parseInt(usize, arg["--max-owned-bytes=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-rss-kib=")) out.max_rss_kib = try std.fmt.parseInt(usize, arg["--max-rss-kib=".len..], 10) else if (std.mem.startsWith(u8, arg, "--max-tree-depth=")) out.max_tree_depth = try std.fmt.parseInt(usize, arg["--max-tree-depth=".len..], 10) else if (std.mem.startsWith(u8, arg, "--expect-checksum=")) out.expect_checksum = try std.fmt.parseInt(u64, arg["--expect-checksum=".len..], 10) else return error.InvalidArgument;
    }
    if (out.lines < 64 or out.queries == 0 or out.edit_pairs == 0) return error.InvalidArguments;
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
        "document: lines={d} bytes={d}->{d} init={d:.2}ms grow={d:.3}ms/{d:.1}x shrink={d:.3}ms/{d:.1}x delete={d:.3}ms/{d:.1}x churn={d:.1}ns/edit query={d:.1}ns/op chunk={d:.3}ms materialize={d:.2}ms snapshot={d:.3}ms/{d:.2}MiB pieces={d} depth={d} owned={d:.2}MiB rss={d:.2}MiB checksum={d} passed={}\n",
        .{ report.lines, report.initial_bytes, report.final_bytes, @as(f64, @floatFromInt(report.init_ns)) / 1_000_000.0, @as(f64, @floatFromInt(report.grow_insert_ns)) / 1_000_000.0, report.grow_speedup, @as(f64, @floatFromInt(report.shrink_replace_ns)) / 1_000_000.0, report.shrink_speedup, @as(f64, @floatFromInt(report.inserted_delete_ns)) / 1_000_000.0, report.delete_speedup, report.churn_edit_ns_per_op, report.query_ns_per_op, @as(f64, @floatFromInt(report.chunk_scan_ns)) / 1_000_000.0, @as(f64, @floatFromInt(report.materialize_ns)) / 1_000_000.0, @as(f64, @floatFromInt(report.snapshot_ns)) / 1_000_000.0, @as(f64, @floatFromInt(report.snapshot_owned_bytes)) / (1024.0 * 1024.0), report.pieces, report.tree_depth, @as(f64, @floatFromInt(report.owned_bytes)) / (1024.0 * 1024.0), @as(f64, @floatFromInt(report.peak_rss_kib)) / 1024.0, report.checksum, report.passed },
    );
    if (options.json_path) |path| try writeReport(init.io, init.gpa, path, report);
    if (!report.passed) return error.DocumentBenchmarkFailed;
}

test "document benchmark contract scales down" {
    const report = try run(std.testing.allocator, std.testing.io, .{
        .lines = 4096,
        .queries = 128,
        .edit_pairs = 32,
        .min_contiguous_speedup = 0,
        .max_rss_kib = std.math.maxInt(usize),
    });
    try std.testing.expect(report.semantic_passed);
    try std.testing.expect(report.memory_passed);
}
