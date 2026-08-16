const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;
const gsub = @import("../gsub.zig");
const ligature_provenance = @import("../ligature_provenance.zig");
const shaping_metadata = @import("../shaping_metadata.zig");
const state_table = @import("state_table.zig");

pub const Error = error{ BadSfnt, InvalidShapingInput } || std.mem.Allocator.Error || error{EndOfStream};

const set_component: u16 = 0x8000;
const perform_action: u16 = 0x2000;
const obsolete_action_offset: u16 = 0x3fff;

const lig_action_last: u32 = 0x8000_0000;
const lig_action_store: u32 = 0x4000_0000;
const lig_action_offset: u32 = 0x3fff_ffff;
const lig_action_sign_bit: u32 = 0x2000_0000;

const max_ligature_matches = ligature_provenance.max_components;

const Addressing = enum {
    /// `morx` entry payloads and component/ligature values are table indexes.
    extended_indexes,
    /// `mort` actions use subtable-relative byte/word offsets.
    obsolete_offsets,
};

/// Execute a modern `morx` type-2 ligature state machine.
pub fn applyExtended(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    operations_left: *usize,
) Error!void {
    if (length < 28) return error.BadSfnt;
    const class_count: usize = @intCast(try state_table.readU32(data, offset));
    const class_table_offset: usize = @intCast(try state_table.readU32(data, offset + 4));
    const state_array_offset: usize = @intCast(try state_table.readU32(data, offset + 8));
    const entry_table_offset: usize = @intCast(try state_table.readU32(data, offset + 12));
    const lig_action_offset_abs: usize = @intCast(try state_table.readU32(data, offset + 16));
    const component_offset: usize = @intCast(try state_table.readU32(data, offset + 20));
    const ligature_offset: usize = @intCast(try state_table.readU32(data, offset + 24));
    if (class_count == 0) return;
    if (class_table_offset > length or
        state_array_offset > length or
        entry_table_offset > length or
        lig_action_offset_abs > length or
        component_offset > length or
        ligature_offset > length)
    {
        return error.BadSfnt;
    }

    var output = try OutputRun.init(allocator, options);
    defer output.deinit(allocator);
    var state: usize = 0;
    var index: usize = 0;
    var match_len: usize = 0;
    var match_positions: [max_ligature_matches]usize = undefined;

    while (true) {
        try consumeTransition(operations_left);
        const class = if (index < glyphs.items.len)
            try extendedClassForGlyph(data, offset, length, class_table_offset, glyphs.items[index])
        else
            state_table.class_end_of_text;
        const entry = try state_table.entry(
            data,
            offset,
            length,
            state_array_offset,
            entry_table_offset,
            class_count,
            state,
            class,
            6,
        );
        if (entry.flags & set_component != 0 and index < glyphs.items.len) {
            pushComponent(&match_len, &match_positions, output.glyphs.items.len);
        }
        if (index < glyphs.items.len) {
            try output.appendInput(allocator, glyphs, options, index);
            if (entry.flags & perform_action != 0) {
                const action_delta = std.math.mul(usize, entry.payload, 4) catch return error.BadSfnt;
                const action_start = std.math.add(usize, lig_action_offset_abs, action_delta) catch return error.BadSfnt;
                try performLigatureAction(
                    allocator,
                    data,
                    offset,
                    length,
                    glyph_count,
                    .extended_indexes,
                    action_start,
                    component_offset,
                    ligature_offset,
                    &output,
                    &match_len,
                    &match_positions,
                );
            }
        }

        state = entry.new_state;
        if (index >= glyphs.items.len) break;
        if (entry.flags & state_table.dont_advance == 0) index += 1;
    }

    try output.commit(allocator, glyphs, options);
}

/// Validate the table topology and all statically reachable action streams of
/// an obsolete `mort` type-2 subtable. Component and ligature addresses depend
/// on the run-time glyphs and are checked by `applyObsolete`.
pub fn validateObsolete(
    data: []const u8,
    offset: usize,
    length: usize,
) Error!void {
    const header = try readObsoleteHeader(data, offset, length);
    const class_glyph_count: usize = try state_table.readU16(data, offset + header.class_table_offset + 2);
    if (class_glyph_count > length - header.class_table_offset - 4) return error.BadSfnt;
    if ((header.entry_table_offset - header.state_array_offset) % header.class_count != 0) return error.BadSfnt;

    for (data[offset + header.state_array_offset .. offset + header.entry_table_offset]) |entry_index| {
        const entry_delta = std.math.mul(usize, entry_index, 4) catch return error.BadSfnt;
        const entry_relative = std.math.add(usize, header.entry_table_offset, entry_delta) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 4) return error.BadSfnt;
        const new_state_offset: usize = try state_table.readU16(data, offset + entry_relative);
        const flags = try state_table.readU16(data, offset + entry_relative + 2);
        if (new_state_offset < header.state_array_offset or new_state_offset >= header.entry_table_offset) return error.BadSfnt;
        if ((new_state_offset - header.state_array_offset) % header.class_count != 0) return error.BadSfnt;

        const action_start: usize = flags & obsolete_action_offset;
        if (action_start == 0) continue;
        const resolved_action = resolveByteOffset(
            header.lig_action_offset,
            action_start,
            4,
        ) catch return error.BadSfnt;
        try validateActionStream(data, offset, length, resolved_action);
    }
}

/// Execute a legacy `mort` type-2 ligature state machine.
///
/// The obsolete format reuses the modern action arithmetic but not its
/// addressing. Entry flag bits select a byte offset from the state-subtable
/// base. Each signed action delta turns `glyph + delta` into a word offset to
/// the component value, and the accumulated component value is a byte offset
/// to the resulting ligature glyph.
pub fn applyObsolete(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
) Error!void {
    const header = try readObsoleteHeader(data, offset, length);
    const class_first: usize = try state_table.readU16(data, offset + header.class_table_offset);
    const class_glyph_count: usize = try state_table.readU16(data, offset + header.class_table_offset + 2);

    var output = try OutputRun.init(allocator, options);
    defer output.deinit(allocator);
    var operations_left = try state_table.operationBudget(glyphs.items.len);
    var state_offset = header.state_array_offset;
    var index: usize = 0;
    var match_len: usize = 0;
    var match_positions: [max_ligature_matches]usize = undefined;

    while (true) {
        try consumeTransition(&operations_left);
        const class: usize = if (index >= glyphs.items.len)
            state_table.class_end_of_text
        else class: {
            const glyph: usize = glyphs.items[index];
            if (glyph < class_first or glyph >= class_first + class_glyph_count) {
                break :class state_table.class_out_of_bounds;
            }
            break :class data[offset + header.class_table_offset + 4 + glyph - class_first];
        };
        const bounded_class = if (class < header.class_count) class else state_table.class_out_of_bounds;
        const state_cell = std.math.add(usize, state_offset, bounded_class) catch return error.BadSfnt;
        if (state_cell >= length) return error.BadSfnt;
        const entry_delta = std.math.mul(usize, data[offset + state_cell], 4) catch return error.BadSfnt;
        const entry_relative = std.math.add(usize, header.entry_table_offset, entry_delta) catch return error.BadSfnt;
        if (entry_relative > length or length - entry_relative < 4) return error.BadSfnt;
        const new_state_offset: usize = try state_table.readU16(data, offset + entry_relative);
        const flags = try state_table.readU16(data, offset + entry_relative + 2);

        if (flags & set_component != 0 and index < glyphs.items.len) {
            pushComponent(&match_len, &match_positions, output.glyphs.items.len);
        }
        if (index < glyphs.items.len) {
            try output.appendInput(allocator, glyphs, options, index);
            const action_start: usize = flags & obsolete_action_offset;
            if (action_start != 0) {
                const resolved_action = resolveByteOffset(
                    header.lig_action_offset,
                    action_start,
                    4,
                ) catch return error.BadSfnt;
                try performLigatureAction(
                    allocator,
                    data,
                    offset,
                    length,
                    glyph_count,
                    .obsolete_offsets,
                    resolved_action,
                    header.component_offset,
                    header.ligature_offset,
                    &output,
                    &match_len,
                    &match_positions,
                );
            }
        }

        state_offset = new_state_offset;
        if (index >= glyphs.items.len) break;
        if (flags & state_table.dont_advance == 0) index += 1;
    }

    try output.commit(allocator, glyphs, options);
}

const ObsoleteHeader = struct {
    class_count: usize,
    class_table_offset: usize,
    state_array_offset: usize,
    entry_table_offset: usize,
    lig_action_offset: usize,
    component_offset: usize,
    ligature_offset: usize,
};

fn readObsoleteHeader(data: []const u8, offset: usize, length: usize) Error!ObsoleteHeader {
    if (length < 14) return error.BadSfnt;
    const header = ObsoleteHeader{
        .class_count = try state_table.readU16(data, offset),
        .class_table_offset = try state_table.readU16(data, offset + 2),
        .state_array_offset = try state_table.readU16(data, offset + 4),
        .entry_table_offset = try state_table.readU16(data, offset + 6),
        .lig_action_offset = try state_table.readU16(data, offset + 8),
        .component_offset = try state_table.readU16(data, offset + 10),
        .ligature_offset = try state_table.readU16(data, offset + 12),
    };
    if (header.class_count < 4 or
        header.class_table_offset < 14 or
        header.state_array_offset < 14 or
        header.entry_table_offset < 14 or
        header.lig_action_offset < 14 or
        header.component_offset < 14 or
        header.ligature_offset < 14 or
        header.class_table_offset >= length or
        header.state_array_offset >= header.entry_table_offset or
        header.entry_table_offset >= length or
        header.lig_action_offset >= length or
        header.component_offset >= length or
        header.ligature_offset >= length)
    {
        return error.BadSfnt;
    }
    return header;
}

fn validateActionStream(data: []const u8, offset: usize, length: usize, first: usize) Error!void {
    var relative = first;
    while (true) {
        if (relative > length or length - relative < 4) return error.BadSfnt;
        const action = try state_table.readU32(data, offset + relative);
        if (action & lig_action_last != 0) return;
        relative = std.math.add(usize, relative, 4) catch return error.BadSfnt;
    }
}

fn extendedClassForGlyph(
    data: []const u8,
    offset: usize,
    length: usize,
    class_table_offset: usize,
    glyph: GlyphId,
) Error!u16 {
    if (glyph == 0xffff) return state_table.class_deleted_glyph;
    if (class_table_offset > length) return error.BadSfnt;
    const lookup = offset + class_table_offset;

    // The out-buffer executor is validated for trimmed format-8 class tables.
    // Sparse format-6 machines can take epsilon transitions after mutating the
    // current glyph, which requires an in-place driver; retaining the existing
    // out-of-bounds fallback avoids duplicating a glyph on DontAdvance.
    if (try state_table.readU16(data, lookup) != 8) return state_table.class_out_of_bounds;
    return (try state_table.lookupGlyphValue(data, lookup, length - class_table_offset, glyph)) orelse state_table.class_out_of_bounds;
}

fn consumeTransition(operations_left: *usize) Error!void {
    if (operations_left.* == 0) return error.BadSfnt;
    operations_left.* -= 1;
}

fn pushComponent(
    match_len: *usize,
    match_positions: *[max_ligature_matches]usize,
    position: usize,
) void {
    // DontAdvance may revisit the same output boundary. HarfBuzz removes the
    // duplicate mark before pushing it again so one input glyph cannot consume
    // two stack slots merely because the state machine epsilon-transitions.
    if (match_len.* != 0 and match_positions.*[(match_len.* - 1) % max_ligature_matches] == position) {
        match_len.* -= 1;
    }
    match_positions.*[match_len.* % max_ligature_matches] = position;
    match_len.* += 1;
}

fn performLigatureAction(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    addressing: Addressing,
    action_start: usize,
    component_offset: usize,
    ligature_offset: usize,
    output: *OutputRun,
    match_len: *usize,
    match_positions: *[max_ligature_matches]usize,
) Error!void {
    if (match_len.* == 0) return;
    var cursor = match_len.*;
    var action_relative = action_start;
    var ligature_index: usize = 0;
    var store_position: ?usize = null;

    while (true) {
        if (cursor == 0) {
            match_len.* = 0;
            return;
        }
        cursor -= 1;
        const position = match_positions.*[cursor % max_ligature_matches];
        if (position >= output.glyphs.items.len) return error.BadSfnt;
        if (action_relative > length or length - action_relative < 4) return error.BadSfnt;
        const action = try state_table.readU32(data, offset + action_relative);
        var unsigned_delta = action & lig_action_offset;
        if (unsigned_delta & lig_action_sign_bit != 0) unsigned_delta |= 0xc000_0000;
        const delta: i32 = @bitCast(unsigned_delta);
        const component_key = @as(i64, output.glyphs.items[position]) + @as(i64, delta);
        if (component_key < 0) return error.BadSfnt;

        const component_relative = switch (addressing) {
            .extended_indexes => relativeIndexed(component_offset, @intCast(component_key), 2) catch return error.BadSfnt,
            .obsolete_offsets => resolveWordOffset(component_offset, @intCast(component_key), 2) catch return error.BadSfnt,
        };
        if (component_relative > length or length - component_relative < 2) return error.BadSfnt;
        ligature_index = std.math.add(
            usize,
            ligature_index,
            try state_table.readU16(data, offset + component_relative),
        ) catch return error.BadSfnt;

        if (action & (lig_action_store | lig_action_last) != 0) {
            const ligature_relative = switch (addressing) {
                .extended_indexes => relativeIndexed(ligature_offset, ligature_index, 2) catch return error.BadSfnt,
                .obsolete_offsets => resolveByteOffset(ligature_offset, ligature_index, 2) catch return error.BadSfnt,
            };
            if (ligature_relative > length or length - ligature_relative < 2) return error.BadSfnt;
            const ligature_glyph = try state_table.readU16(data, offset + ligature_relative);
            if (ligature_glyph >= glyph_count) return error.BadSfnt;
            output.glyphs.items[position] = ligature_glyph;
            if (output.has_substituted) output.substituted.items[position] = true;
            if (output.has_stage_substituted) output.stage_substituted.items[position] = true;
            store_position = position;
        }
        action_relative = std.math.add(usize, action_relative, 4) catch return error.BadSfnt;
        if (action & lig_action_last != 0) break;
    }

    const first = match_positions.*[cursor % max_ligature_matches];
    const last = match_positions.*[(match_len.* - 1) % max_ligature_matches];
    const ligature_pos = store_position orelse first;
    if (first >= output.glyphs.items.len or
        last >= output.glyphs.items.len or
        first > last or
        ligature_pos > last)
    {
        return error.BadSfnt;
    }
    if (output.has_clusters) {
        shaping_metadata.mergeMonotoneClusters(output.clusters.items, first, last + 1);
    }
    if (output.has_ligatures and output.has_sources) {
        var component_sources: [max_ligature_matches]usize = undefined;
        const count = last - first + 1;
        if (count > component_sources.len) return error.BadSfnt;
        for (0..count) |i| component_sources[i] = output.sources.items[first + i];
        output.ligatures.infos.items[ligature_pos] = try output.ligatures.addLigature(
            allocator,
            component_sources[0..count],
        );
    }

    var remove_cursor = match_len.*;
    while (remove_cursor > cursor) {
        remove_cursor -= 1;
        const remove_index = match_positions.*[remove_cursor % max_ligature_matches];
        if (remove_index == ligature_pos) continue;
        output.remove(remove_index);
    }
    // The stored ligature remains the oldest live stack component, matching
    // HarfBuzz's post-action stack length rather than an output-array index.
    match_len.* = cursor + 1;
}

fn relativeIndexed(base: usize, index: usize, stride: usize) !usize {
    const delta = try std.math.mul(usize, index, stride);
    return std.math.add(usize, base, delta);
}

fn resolveWordOffset(array_base: usize, word_offset: usize, stride: usize) !usize {
    const byte_offset = try std.math.mul(usize, word_offset, 2);
    return resolveByteOffset(array_base, byte_offset, stride);
}

fn resolveByteOffset(array_base: usize, byte_offset: usize, stride: usize) !usize {
    if (stride == 0 or byte_offset < array_base) return error.Overflow;
    // HarfBuzz's ObsoleteTypes::offsetToIndex converts through the target
    // array base and floors a malformed non-aligned delta. Resolve back to the
    // same element address instead of imposing a stricter validator policy.
    const index = (byte_offset - array_base) / stride;
    return relativeIndexed(array_base, index, stride);
}

const OutputRun = struct {
    glyphs: std.ArrayList(GlyphId) = .empty,
    sources: std.ArrayList(usize) = .empty,
    clusters: std.ArrayList(usize) = .empty,
    substituted: std.ArrayList(bool) = .empty,
    stage_substituted: std.ArrayList(bool) = .empty,
    ligatures: ligature_provenance.Store = .{},
    has_sources: bool = false,
    has_clusters: bool = false,
    has_substituted: bool = false,
    has_stage_substituted: bool = false,
    has_ligatures: bool = false,

    fn init(allocator: std.mem.Allocator, options: gsub.runtime.Options) Error!OutputRun {
        var output = OutputRun{};
        errdefer output.deinit(allocator);
        output.has_sources = options.glyph_source_indices != null;
        output.has_clusters = options.glyph_cluster_indices != null;
        output.has_substituted = options.glyph_substituted != null;
        output.has_stage_substituted = options.glyph_stage_substituted != null;
        if (options.ligature_components) |store| {
            output.has_ligatures = true;
            // Existing handles refer into this immutable prefix. New AAT
            // ligature records append to it, so copied handles remain valid.
            try output.ligatures.sources.appendSlice(allocator, store.sources.items);
        }
        return output;
    }

    fn deinit(output: *OutputRun, allocator: std.mem.Allocator) void {
        output.ligatures.deinit(allocator);
        output.stage_substituted.deinit(allocator);
        output.substituted.deinit(allocator);
        output.clusters.deinit(allocator);
        output.sources.deinit(allocator);
        output.glyphs.deinit(allocator);
        output.* = .{};
    }

    fn appendInput(
        output: *OutputRun,
        allocator: std.mem.Allocator,
        glyphs: *const std.ArrayList(GlyphId),
        options: gsub.runtime.Options,
        index: usize,
    ) Error!void {
        try output.glyphs.append(allocator, glyphs.items[index]);
        if (options.glyph_source_indices) |values| try output.sources.append(allocator, values.items[index]);
        if (options.glyph_cluster_indices) |values| try output.clusters.append(allocator, values.items[index]);
        if (options.glyph_substituted) |values| try output.substituted.append(allocator, values.items[index]);
        if (options.glyph_stage_substituted) |values| try output.stage_substituted.append(allocator, values.items[index]);
        if (options.ligature_components) |store| try output.ligatures.infos.append(allocator, store.infos.items[index]);
    }

    fn remove(output: *OutputRun, index: usize) void {
        _ = output.glyphs.orderedRemove(index);
        if (output.has_sources) _ = output.sources.orderedRemove(index);
        if (output.has_clusters) _ = output.clusters.orderedRemove(index);
        if (output.has_substituted) _ = output.substituted.orderedRemove(index);
        if (output.has_stage_substituted) _ = output.stage_substituted.orderedRemove(index);
        if (output.has_ligatures) _ = output.ligatures.infos.orderedRemove(index);
    }

    fn commit(
        output: *OutputRun,
        allocator: std.mem.Allocator,
        glyphs: *std.ArrayList(GlyphId),
        options: gsub.runtime.Options,
    ) Error!void {
        const len = output.glyphs.items.len;
        try glyphs.ensureTotalCapacity(allocator, len);
        if (options.glyph_source_indices) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.glyph_cluster_indices) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.glyph_substituted) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.glyph_stage_substituted) |values| try values.ensureTotalCapacity(allocator, len);
        if (options.ligature_components) |store| {
            try store.infos.ensureTotalCapacity(allocator, len);
            try store.sources.ensureTotalCapacity(allocator, output.ligatures.sources.items.len);
        }

        try glyphs.replaceRange(allocator, 0, glyphs.items.len, output.glyphs.items);
        if (options.glyph_source_indices) |values| try values.replaceRange(allocator, 0, values.items.len, output.sources.items);
        if (options.glyph_cluster_indices) |values| try values.replaceRange(allocator, 0, values.items.len, output.clusters.items);
        if (options.glyph_substituted) |values| try values.replaceRange(allocator, 0, values.items.len, output.substituted.items);
        if (options.glyph_stage_substituted) |values| try values.replaceRange(allocator, 0, values.items.len, output.stage_substituted.items);
        if (options.ligature_components) |store| {
            store.clear();
            try store.sources.appendSlice(allocator, output.ligatures.sources.items);
            try store.infos.appendSlice(allocator, output.ligatures.infos.items);
        }
    }
};

test "obsolete ligature offsets merge glyphs and parallel metadata" {
    var bytes = [_]u8{0} ** 62;
    std.mem.writeInt(u16, bytes[0..2], 6, .big);
    std.mem.writeInt(u16, bytes[2..4], 14, .big);
    std.mem.writeInt(u16, bytes[4..6], 20, .big);
    std.mem.writeInt(u16, bytes[6..8], 32, .big);
    std.mem.writeInt(u16, bytes[8..10], 44, .big);
    std.mem.writeInt(u16, bytes[10..12], 52, .big);
    std.mem.writeInt(u16, bytes[12..14], 60, .big);
    std.mem.writeInt(u16, bytes[14..16], 1, .big);
    std.mem.writeInt(u16, bytes[16..18], 2, .big);
    bytes[18] = 4;
    bytes[19] = 5;
    bytes[20 + 4] = 1;
    bytes[26 + 5] = 2;
    std.mem.writeInt(u16, bytes[32..34], 20, .big);
    std.mem.writeInt(u16, bytes[36..38], 26, .big);
    std.mem.writeInt(u16, bytes[38..40], set_component, .big);
    std.mem.writeInt(u16, bytes[40..42], 20, .big);
    std.mem.writeInt(u16, bytes[42..44], set_component | 44, .big);

    // The first action addresses glyph 2 at absolute component word offset
    // 26; the final action addresses glyph 1 at word offset 27 and contributes
    // absolute byte offset 60 into the ligature table.
    std.mem.writeInt(u32, bytes[44..48], 24, .big);
    std.mem.writeInt(u32, bytes[48..52], lig_action_last | 26, .big);
    std.mem.writeInt(u16, bytes[52..54], 0, .big);
    std.mem.writeInt(u16, bytes[54..56], 60, .big);
    std.mem.writeInt(u16, bytes[60..62], 3, .big);

    try validateObsolete(&bytes, 0, bytes.len);

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 7, 8 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 10, 20 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, false });
    var stage_substituted = std.ArrayList(bool).empty;
    defer stage_substituted.deinit(std.testing.allocator);
    try stage_substituted.appendSlice(std.testing.allocator, &.{ false, false });
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.resize(std.testing.allocator, 2);
    @memset(ligatures.infos.items, .{});

    try applyObsolete(std.testing.allocator, &bytes, 0, bytes.len, 4, &glyphs, .{
        .glyph_source_indices = &sources,
        .glyph_cluster_indices = &clusters,
        .glyph_substituted = &substituted,
        .glyph_stage_substituted = &stage_substituted,
        .ligature_components = &ligatures,
    });

    try std.testing.expectEqualSlices(GlyphId, &.{3}, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{7}, sources.items);
    try std.testing.expectEqualSlices(usize, &.{10}, clusters.items);
    try std.testing.expectEqualSlices(bool, &.{true}, substituted.items);
    try std.testing.expectEqualSlices(bool, &.{true}, stage_substituted.items);
    try std.testing.expectEqualSlices(usize, &.{ 7, 8 }, ligatures.componentSources(ligatures.infos.items[0]).?);
}
