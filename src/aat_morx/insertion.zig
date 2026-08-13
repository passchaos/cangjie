const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;
const gsub = @import("../gsub.zig");
const ligature_provenance = @import("../ligature_provenance.zig");
const state_table = @import("state_table.zig");

pub const Error = state_table.Error || std.mem.Allocator.Error;

const set_mark: u16 = 0x8000;
const current_insert_before: u16 = 0x0800;
const marked_insert_before: u16 = 0x0400;
const current_insert_count: u16 = 0x03e0;
const marked_insert_count: u16 = 0x001f;
const no_insertion: u16 = 0xffff;

pub fn apply(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    operations_left: *usize,
) Error!void {
    if (length < 20) return error.BadSfnt;
    const class_count: usize = @intCast(try state_table.readU32(data, offset));
    const class_table_offset: usize = @intCast(try state_table.readU32(data, offset + 4));
    const state_array_offset: usize = @intCast(try state_table.readU32(data, offset + 8));
    const entry_table_offset: usize = @intCast(try state_table.readU32(data, offset + 12));
    const insertion_offset: usize = @intCast(try state_table.readU32(data, offset + 16));
    if (class_count < 4 or
        class_table_offset > length or
        state_array_offset > length or
        entry_table_offset > length or
        insertion_offset > length)
    {
        return error.BadSfnt;
    }

    var run = try WorkingRun.init(allocator, glyphs, options);
    defer run.deinit(allocator);

    var state: usize = 0;
    var cursor: usize = 0;
    var mark: usize = 0;

    while (true) {
        if (operations_left.* == 0) return error.BadSfnt;
        operations_left.* -= 1;

        const class = if (cursor < run.glyphs.items.len)
            try state_table.classForGlyph(data, offset, length, class_table_offset, run.glyphs.items[cursor])
        else
            state_table.class_end_of_text;
        const current_entry = try state_table.entry(
            data,
            offset,
            length,
            state_array_offset,
            entry_table_offset,
            class_count,
            state,
            class,
            8,
        );
        const flags = current_entry.flags;
        const mark_location = cursor;

        if (current_entry.payload_2 != no_insertion) {
            const count: usize = flags & marked_insert_count;
            try consumeInsertionBudget(operations_left, count);
            const end = cursor;
            if (mark > run.glyphs.items.len) return error.BadSfnt;
            cursor = mark;
            const before = flags & marked_insert_before != 0;
            if (cursor < run.glyphs.items.len and !before) {
                try run.copyCurrent(allocator, &cursor);
            }
            try outputInsertionGlyphs(
                allocator,
                data,
                offset,
                length,
                insertion_offset,
                current_entry.payload_2,
                count,
                glyph_count,
                &run,
                &cursor,
            );
            if (cursor < run.glyphs.items.len and !before) run.skipCurrent(cursor);
            cursor = std.math.add(usize, end, count) catch return error.BadSfnt;
            if (cursor > run.glyphs.items.len) return error.BadSfnt;
        }

        if (flags & set_mark != 0) mark = mark_location;

        if (current_entry.payload != no_insertion) {
            const count: usize = (flags & current_insert_count) >> 5;
            try consumeInsertionBudget(operations_left, count);
            const end = cursor;
            const before = flags & current_insert_before != 0;
            if (cursor < run.glyphs.items.len and !before) {
                try run.copyCurrent(allocator, &cursor);
            }
            try outputInsertionGlyphs(
                allocator,
                data,
                offset,
                length,
                insertion_offset,
                current_entry.payload,
                count,
                glyph_count,
                &run,
                &cursor,
            );
            if (cursor < run.glyphs.items.len and !before) run.skipCurrent(cursor);

            // With DontAdvance, downstream insertions become visible to the
            // next transition. Otherwise leave the boundary after all inserted
            // glyphs and let the shared driver consume the original current
            // glyph below.
            cursor = if (flags & state_table.dont_advance != 0)
                end
            else
                std.math.add(usize, end, count) catch return error.BadSfnt;
            if (cursor > run.glyphs.items.len) return error.BadSfnt;
        }

        state = current_entry.new_state;
        if (cursor >= run.glyphs.items.len) break;
        if (flags & state_table.dont_advance == 0) cursor += 1;
    }

    try run.commit(allocator, glyphs, options);
}

fn consumeInsertionBudget(operations_left: *usize, count: usize) Error!void {
    if (count >= operations_left.*) return error.BadSfnt;
    operations_left.* -= count;
}

fn outputInsertionGlyphs(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    insertion_offset: usize,
    insertion_index: u16,
    count: usize,
    glyph_count: usize,
    run: *WorkingRun,
    cursor: *usize,
) Error!void {
    const first_delta = std.math.mul(usize, insertion_index, 2) catch return error.BadSfnt;
    const first = std.math.add(usize, insertion_offset, first_delta) catch return error.BadSfnt;
    const byte_count = std.math.mul(usize, count, 2) catch return error.BadSfnt;
    if (first > length or byte_count > length - first) return error.BadSfnt;

    for (0..count) |index| {
        const glyph = try state_table.readU16(data, offset + first + index * 2);
        if (glyph >= glyph_count) return error.BadSfnt;
        try run.outputGlyph(allocator, cursor, glyph);
    }
}

/// Mutable concatenation of the AAT output prefix and unconsumed input suffix.
///
/// `cursor` is the boundary between those two regions. Inserting a duplicate
/// at the boundary models `copy_glyph`; deleting the original models
/// `skip_glyph`; assigning the boundary directly models `move_to`. This keeps
/// the state-machine semantics exact without exposing HarfBuzz's dual-buffer
/// storage strategy to the rest of the shaper.
const WorkingRun = struct {
    glyphs: std.ArrayList(GlyphId) = .empty,
    sources: std.ArrayList(usize) = .empty,
    clusters: std.ArrayList(usize) = .empty,
    substituted: std.ArrayList(bool) = .empty,
    stage_substituted: std.ArrayList(bool) = .empty,
    ligatures: std.ArrayList(ligature_provenance.Info) = .empty,
    has_sources: bool = false,
    has_clusters: bool = false,
    has_substituted: bool = false,
    has_stage_substituted: bool = false,
    has_ligatures: bool = false,

    fn init(
        allocator: std.mem.Allocator,
        glyphs: *const std.ArrayList(GlyphId),
        options: gsub.LookupOptions,
    ) Error!WorkingRun {
        var run = WorkingRun{};
        errdefer run.deinit(allocator);
        try run.glyphs.appendSlice(allocator, glyphs.items);
        if (options.glyph_source_indices) |values| {
            run.has_sources = true;
            try run.sources.appendSlice(allocator, values.items);
        }
        if (options.glyph_cluster_indices) |values| {
            run.has_clusters = true;
            try run.clusters.appendSlice(allocator, values.items);
        }
        if (options.glyph_substituted) |values| {
            run.has_substituted = true;
            try run.substituted.appendSlice(allocator, values.items);
        }
        if (options.glyph_stage_substituted) |values| {
            run.has_stage_substituted = true;
            try run.stage_substituted.appendSlice(allocator, values.items);
        }
        if (options.ligature_components) |store| {
            run.has_ligatures = true;
            try run.ligatures.appendSlice(allocator, store.infos.items);
        }
        return run;
    }

    fn deinit(run: *WorkingRun, allocator: std.mem.Allocator) void {
        run.ligatures.deinit(allocator);
        run.stage_substituted.deinit(allocator);
        run.substituted.deinit(allocator);
        run.clusters.deinit(allocator);
        run.sources.deinit(allocator);
        run.glyphs.deinit(allocator);
        run.* = .{};
    }

    fn copyCurrent(run: *WorkingRun, allocator: std.mem.Allocator, cursor: *usize) Error!void {
        if (cursor.* >= run.glyphs.items.len) return;
        const metadata = run.metadataAt(cursor.*);
        try run.insertMetadata(allocator, cursor.*, run.glyphs.items[cursor.*], metadata, false);
        cursor.* += 1;
    }

    fn outputGlyph(run: *WorkingRun, allocator: std.mem.Allocator, cursor: *usize, glyph: GlyphId) Error!void {
        if (run.glyphs.items.len == 0) return;
        const template = if (cursor.* < run.glyphs.items.len) cursor.* else cursor.* - 1;
        const metadata = run.metadataAt(template);
        try run.insertMetadata(allocator, cursor.*, glyph, metadata, true);
        cursor.* += 1;
    }

    const Metadata = struct {
        source: usize = 0,
        cluster: usize = 0,
        substituted: bool = false,
        stage_substituted: bool = false,
        ligature: ligature_provenance.Info = .{},
    };

    fn metadataAt(run: *const WorkingRun, index: usize) Metadata {
        return .{
            .source = if (run.has_sources) run.sources.items[index] else 0,
            .cluster = if (run.has_clusters) run.clusters.items[index] else 0,
            .substituted = if (run.has_substituted) run.substituted.items[index] else false,
            .stage_substituted = if (run.has_stage_substituted) run.stage_substituted.items[index] else false,
            .ligature = if (run.has_ligatures) run.ligatures.items[index] else .{},
        };
    }

    fn insertMetadata(
        run: *WorkingRun,
        allocator: std.mem.Allocator,
        index: usize,
        glyph: GlyphId,
        metadata: Metadata,
        mark_substituted: bool,
    ) Error!void {
        try run.glyphs.replaceRange(allocator, index, 0, &.{glyph});
        errdefer _ = run.glyphs.orderedRemove(index);
        if (run.has_sources) try insertValue(usize, allocator, &run.sources, index, metadata.source);
        if (run.has_clusters) try insertValue(usize, allocator, &run.clusters, index, metadata.cluster);
        if (run.has_substituted) try insertValue(bool, allocator, &run.substituted, index, metadata.substituted or mark_substituted);
        if (run.has_stage_substituted) try insertValue(bool, allocator, &run.stage_substituted, index, metadata.stage_substituted or mark_substituted);
        if (run.has_ligatures) try insertValue(ligature_provenance.Info, allocator, &run.ligatures, index, metadata.ligature);
    }

    fn skipCurrent(run: *WorkingRun, index: usize) void {
        _ = run.glyphs.orderedRemove(index);
        if (run.has_sources) _ = run.sources.orderedRemove(index);
        if (run.has_clusters) _ = run.clusters.orderedRemove(index);
        if (run.has_substituted) _ = run.substituted.orderedRemove(index);
        if (run.has_stage_substituted) _ = run.stage_substituted.orderedRemove(index);
        if (run.has_ligatures) _ = run.ligatures.orderedRemove(index);
    }

    fn commit(
        run: *WorkingRun,
        allocator: std.mem.Allocator,
        glyphs: *std.ArrayList(GlyphId),
        options: gsub.LookupOptions,
    ) Error!void {
        const len = run.glyphs.items.len;
        try glyphs.ensureTotalCapacity(allocator, len);
        if (options.glyph_source_indices) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.glyph_cluster_indices) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.glyph_substituted) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.glyph_stage_substituted) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.ligature_components) |store| try store.infos.ensureTotalCapacity(allocator, len);

        try glyphs.replaceRange(allocator, 0, glyphs.items.len, run.glyphs.items);
        if (options.glyph_source_indices) |values| try values.replaceRange(allocator, 0, values.items.len, run.sources.items);
        if (options.glyph_cluster_indices) |values| try values.replaceRange(allocator, 0, values.items.len, run.clusters.items);
        if (options.glyph_substituted) |values| try values.replaceRange(allocator, 0, values.items.len, run.substituted.items);
        if (options.glyph_stage_substituted) |values| try values.replaceRange(allocator, 0, values.items.len, run.stage_substituted.items);
        if (options.ligature_components) |store| try store.infos.replaceRange(allocator, 0, store.infos.items.len, run.ligatures.items);
    }
};

fn insertValue(
    comptime T: type,
    allocator: std.mem.Allocator,
    values: *std.ArrayList(T),
    index: usize,
    value: T,
) Error!void {
    try values.replaceRange(allocator, index, 0, &.{value});
}

test "inserted glyphs clone every parallel metadata sidecar" {
    const allocator = std.testing.allocator;

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 2, 3 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 7, 8 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 10, 20 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, true });

    var stage_substituted = std.ArrayList(bool).empty;
    defer stage_substituted.deinit(allocator);
    try stage_substituted.appendSlice(allocator, &.{ false, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(allocator);
    try ligatures.infos.resize(allocator, 2);
    @memset(ligatures.infos.items, .{});
    ligatures.infos.items[0].flags.synthetic_base = true;

    const options = gsub.LookupOptions{
        .glyph_source_indices = &sources,
        .glyph_cluster_indices = &clusters,
        .glyph_substituted = &substituted,
        .glyph_stage_substituted = &stage_substituted,
        .ligature_components = &ligatures,
    };
    var run = try WorkingRun.init(allocator, &glyphs, options);
    defer run.deinit(allocator);

    var cursor: usize = 0;
    try run.copyCurrent(allocator, &cursor);
    try run.outputGlyph(allocator, &cursor, 4);
    run.skipCurrent(cursor);
    try run.commit(allocator, &glyphs, options);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 4, 3 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 7, 7, 8 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 10, 10, 20 }, clusters.items);
    try std.testing.expectEqualSlices(bool, &.{ false, true, true }, substituted.items);
    try std.testing.expectEqualSlices(bool, &.{ false, true, false }, stage_substituted.items);
    try std.testing.expect(ligatures.infos.items[0].flags.synthetic_base);
    try std.testing.expect(ligatures.infos.items[1].flags.synthetic_base);
}
