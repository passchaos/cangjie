//! Native xAdvance-only PairPos accelerator execution.

const std = @import("std");
const accelerator_model = @import("../../../accelerator/model.zig");
const glyph_groups = @import("../../../accelerator/glyph_groups.zig");
const generic = @import("generic.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const output = @import("../../output/root.zig");
const positioning = @import("../../../positioning/root.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error = table.view.Error || error{UnsupportedGpos};
pub const Lookup = accelerator_model.Lookup;
pub const Options = options.Options;
pub const PairClassEntry = accelerator_model.PairClassEntry;
pub const PairRecord = accelerator_model.PairPositionRecord;
pub const Subtable = accelerator_model.PairPositionSubtable;
pub const View = table.View;

pub fn hasNativeData(subtables: []const Subtable) bool {
    for (subtables) |subtable| {
        if (subtable.kind != .generic) return true;
    }
    return false;
}

pub fn collectLookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    accelerator: *const Lookup,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (lookup_flag == 0 and run.run_has_default_ignorables == false) {
        return collectLookupImpl(
            true,
            view,
            lookup_offset,
            subtable_count,
            accelerator,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        );
    }
    return collectLookupImpl(
        false,
        view,
        lookup_offset,
        subtable_count,
        accelerator,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}

fn collectLookupImpl(
    comptime adjacent_pairs: bool,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    accelerator: *const Lookup,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;
    const append_pairs_directly = adjustments.items.len == 0;
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) {
        if (!adjacent_pairs and matching.lookupIgnoresGlyph(
            lookup_flag,
            run,
            glyphs[first_index],
        )) {
            first_index += 1;
            continue;
        }
        const second_index = if (adjacent_pairs)
            first_index + 1
        else
            generic.nextParticipatingGlyph(
                glyphs,
                first_index + 1,
                lookup_flag,
                run,
            ) orelse {
                first_index += 1;
                continue;
            };
        const candidates = glyph_groups.findDirect(
            accelerator.coverage_groups,
            accelerator.coverage_group_slots,
            accelerator.coverage_group_direct,
            glyphs[first_index],
        ) orelse {
            first_index += 1;
            continue;
        };

        var matched_value_2 = false;
        for (candidates) |subtable_index| {
            const index: usize = subtable_index;
            if (index >= subtable_count or
                index >= accelerator.pair_pos_subtables.len)
            {
                return error.BadGpos;
            }
            const sidecar = accelerator.pair_pos_subtables[index];
            const x_advance = switch (sidecar.kind) {
                .format_1_x_advance => value: {
                    const record = findSparseRecord(
                        accelerator.pair_pos_records,
                        sidecar,
                        glyphs[first_index],
                        glyphs[second_index],
                    ) orelse continue;
                    break :value record.x_advance;
                },
                .format_2_x_advance => classAdvance(
                    accelerator,
                    sidecar,
                    glyphs[first_index],
                    glyphs[second_index],
                ) orelse continue,
                .format_2_dense_x_advance => denseClassAdvance(
                    accelerator,
                    sidecar,
                    glyphs[first_index],
                    glyphs[second_index],
                ) orelse continue,
                .generic => generic: {
                    const lookup_subtable = try table.offset.required16(
                        view,
                        lookup_offset,
                        try view.readU16(lookup_offset + 6 + index * 2),
                    );
                    const pair_subtable =
                        if (accelerator.pair_pos_extension)
                            try positioning.lookup.dispatch.extensionPayload(
                                view,
                                lookup_subtable,
                                2,
                            )
                        else
                            lookup_subtable;
                    const parsed = try positioning.lookup.pair.parse(
                        view,
                        pair_subtable,
                    );
                    if (try generic.collectAtParsed(
                        view,
                        parsed,
                        glyphs,
                        first_index,
                        adjustments,
                        allocator,
                        lookup_flag,
                        run,
                    )) {
                        matched_value_2 = parsed.value_format_2 != 0;
                        break :generic null;
                    }
                    continue;
                },
            };
            if (x_advance) |amount| {
                if (!run.vertical and amount != 0) {
                    try output.safety.markPair(
                        allocator,
                        &run,
                        first_index,
                        second_index,
                    );
                }
                try appendXAdvance(
                    adjustments,
                    allocator,
                    first_index,
                    amount,
                    append_pairs_directly,
                );
            }
            break;
        }
        first_index = generic.advanceAfterPair(
            glyphs,
            first_index,
            lookup_flag,
            run,
            matched_value_2,
        );
    }
}

pub fn denseClassAdvance(
    accelerator: *const Lookup,
    subtable: Subtable,
    first: GlyphId,
    second: GlyphId,
) ?i16 {
    const first_index: usize = first;
    if (first_index < subtable.record_start or
        first_index - subtable.record_start >= subtable.coverage_len)
    {
        return null;
    }
    const coverage_entry = accelerator.pair_pos_coverage_classes[
        subtable.coverage_start + first_index - subtable.record_start
    ];
    if (coverage_entry.class == std.math.maxInt(u16)) return null;
    const class_1 = coverage_entry.class;

    const second_index: usize = second;
    const class_2 =
        if (second_index >= subtable.record_len and
        second_index - subtable.record_len < subtable.class_2_len)
            accelerator.pair_pos_class_entries[
                subtable.class_2_start + second_index - subtable.record_len
            ].class
        else
            0;
    if (class_1 >= subtable.class_1_count or
        class_2 >= subtable.class_2_count)
    {
        return null;
    }
    return accelerator.pair_pos_class_matrix[
        subtable.matrix_start +
            @as(usize, class_1) * subtable.class_2_count +
            class_2
    ];
}

fn findSparseRecord(
    records: []const PairRecord,
    subtable: Subtable,
    first: GlyphId,
    second: GlyphId,
) ?PairRecord {
    const slice =
        records[subtable.record_start .. subtable.record_start + subtable.record_len];
    var low: usize = 0;
    var high: usize = slice.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const record = slice[middle];
        if (first < record.first or
            (first == record.first and second < record.second))
        {
            high = middle;
        } else if (first > record.first or
            (first == record.first and second > record.second))
        {
            low = middle + 1;
        } else {
            return record;
        }
    }
    return null;
}

fn classAdvance(
    accelerator: *const Lookup,
    subtable: Subtable,
    first: GlyphId,
    second: GlyphId,
) ?i16 {
    const class_1 = coveredClass(
        accelerator.pair_pos_coverage_classes[subtable.coverage_start .. subtable.coverage_start + subtable.coverage_len],
        first,
    ) orelse return null;
    const class_2 = classForGlyph(
        accelerator.pair_pos_class_entries[subtable.class_2_start .. subtable.class_2_start + subtable.class_2_len],
        second,
    );
    if (class_1 >= subtable.class_1_count or
        class_2 >= subtable.class_2_count)
    {
        return null;
    }
    return accelerator.pair_pos_class_matrix[
        subtable.matrix_start +
            @as(usize, class_1) * subtable.class_2_count +
            class_2
    ];
}

fn coveredClass(entries: []const PairClassEntry, glyph: GlyphId) ?u16 {
    var low: usize = 0;
    var high = entries.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (glyph < entries[middle].glyph) {
            high = middle;
        } else if (glyph > entries[middle].glyph) {
            low = middle + 1;
        } else {
            return entries[middle].class;
        }
    }
    return null;
}

fn classForGlyph(entries: []const PairClassEntry, glyph: GlyphId) u16 {
    return coveredClass(entries, glyph) orelse 0;
}

fn appendXAdvance(
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    first_index: usize,
    x_advance: i16,
    append_directly: bool,
) std.mem.Allocator.Error!void {
    if (append_directly) {
        try adjustments.append(allocator, .{
            .index = first_index,
            .x_advance = x_advance,
            .pair_positioned = true,
        });
        return;
    }
    try output.adjustments.append(
        adjustments,
        allocator,
        first_index,
        .{ .index = first_index, .x_advance = x_advance },
        true,
    );
}
