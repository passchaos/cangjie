//! LigatureSubst accelerator construction and compact prefilter policy.

const std = @import("std");
const GlyphDigest = @import("../../../../glyph_digest.zig").GlyphDigest;
const GlyphId = @import("../../../../glyph.zig").GlyphId;
pub const index = @import("index.zig");
const model = @import("../../model.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Ligature = model.LigatureSubstitution;
pub const View = table.View;

pub const min_competing_for_prefilter = 32;
pub const min_competing_for_required_second = 128;
pub const max_exact_required_seconds = 16;
const required_second_digest_flag: u16 = 0x8000;
const required_second_digest_u16_len: u16 = 12;
const bounded_second_capacity = max_exact_required_seconds + 1;

pub fn build(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Ligature {
    if (try view.readU16(subtable_offset) != 1) return .{};
    const coverage = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const set_count = try view.readU16(subtable_offset + 4);
    const sets = try allocator.alloc(model.LigatureSet, set_count);
    errdefer allocator.free(sets);
    var definitions = std.ArrayList(model.LigatureDefinition).empty;
    errdefer definitions.deinit(allocator);
    var components = std.ArrayList(GlyphId).empty;
    errdefer components.deinit(allocator);
    var competing_count: usize = 0;
    var first_digest = GlyphDigest.empty();
    var second_digest = GlyphDigest.empty();
    var bounded_seconds: [bounded_second_capacity]GlyphId = undefined;
    var bounded_second_len: usize = 0;
    var all_require_second = true;

    for (sets, 0..) |*set, set_index| {
        const glyph = (try table.coverage.glyphAt(
            view,
            coverage,
            set_index,
        )) orelse return error.BadGsub;
        first_digest.add(glyph);
        const set_offset = table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 6 + set_index * 2),
        ) catch {
            set.* = .{
                .glyph = glyph,
                .definition_start = definitions.items.len,
                .definition_len = 0,
            };
            continue;
        };
        const ligature_count = try view.readU16(set_offset);
        const definition_start = definitions.items.len;
        for (0..ligature_count) |ligature_index| {
            const ligature_offset = table.offset.required16(
                view,
                set_offset,
                try view.readU16(set_offset + 2 + ligature_index * 2),
            ) catch continue;
            const component_count = try view.readU16(ligature_offset + 2);
            if (component_count == 0 or
                component_count > model.max_ligature_components)
            {
                // Runtime matching skips definitions that cannot fit its fixed
                // component-offset scratch. Keep cached and generic semantics.
                continue;
            }
            const component_start = components.items.len;
            all_require_second =
                all_require_second and component_count > 1;
            for (1..component_count) |component_index| {
                const component = try view.readU16(
                    ligature_offset + 4 + (component_index - 1) * 2,
                );
                try components.append(allocator, component);
                if (component_index == 1) {
                    second_digest.add(component);
                    addBoundedUniqueSecond(
                        &bounded_seconds,
                        &bounded_second_len,
                        component,
                    );
                }
            }
            try definitions.append(allocator, .{
                .ligature = try view.readU16(ligature_offset),
                .component_start = component_start,
                .component_count = component_count,
            });
        }
        set.* = .{
            .glyph = glyph,
            .definition_start = definition_start,
            .definition_len = definitions.items.len - definition_start,
        };
        competing_count +=
            (definitions.items.len - definition_start) -| 1;
    }

    std.sort.heap(model.LigatureSet, sets, {}, lessSet);
    const slots = try index.build(sets, allocator);
    errdefer allocator.free(slots);
    const prefilter_second = shouldPrefilterSecond(competing_count);
    var required_second_start: u32 = 0;
    var required_second_len: u16 = 0;
    if (shouldBuildRequiredSecondIndex(
        competing_count,
        all_require_second,
    )) {
        if (components.items.len <= std.math.maxInt(u32) and
            components.items.len <=
                @as(usize, std.math.maxInt(u32)) -
                    required_second_digest_u16_len)
        {
            required_second_start = @intCast(components.items.len);
            required_second_len = required_second_digest_flag |
                required_second_digest_u16_len;
            for (second_digest.words()) |word| {
                inline for (0..4) |part| {
                    try components.append(
                        allocator,
                        @truncate(word >> (part * 16)),
                    );
                }
            }
        }
    } else if (shouldBuildExactRequiredSecondIndex(
        all_require_second,
        bounded_second_len,
    )) {
        // Definition components occupy the prefix of this allocation. The
        // exact index is a disjoint tail, so the recorded component_start
        // values remain valid and ownership stays in one compact slice.
        std.sort.heap(
            GlyphId,
            bounded_seconds[0..bounded_second_len],
            {},
            lessGlyph,
        );
        if (components.items.len <= std.math.maxInt(u32) and
            bounded_second_len <=
                @as(usize, std.math.maxInt(u32)) - components.items.len)
        {
            required_second_start = @intCast(components.items.len);
            required_second_len = @intCast(bounded_second_len);
            try components.appendSlice(
                allocator,
                bounded_seconds[0..bounded_second_len],
            );
        }
    }

    const owned_definitions = try definitions.toOwnedSlice(allocator);
    errdefer allocator.free(owned_definitions);
    const owned_components = try components.toOwnedSlice(allocator);
    return .{
        .sets = sets,
        .set_slots = slots,
        .definitions = owned_definitions,
        .components = owned_components,
        .first_component_digest = first_digest,
        .required_second_start = required_second_start,
        .required_second_len = required_second_len,
        .prefilter_second = prefilter_second and required_second_len == 0,
    };
}

pub fn requiredSecondComponents(ligature: Ligature) []const GlyphId {
    if ((ligature.required_second_len & required_second_digest_flag) != 0) {
        return &.{};
    }
    const start: usize = ligature.required_second_start;
    const len: usize = ligature.required_second_len;
    if (len == 0 or len > max_exact_required_seconds or
        start > ligature.components.len or
        len > ligature.components.len - start)
    {
        return &.{};
    }
    const seconds = ligature.components[start .. start + len];
    // Binary search is only sound for the builder's sorted, deduplicated
    // representation. Treat malformed optional metadata as absent so runtime
    // execution falls back to the authoritative decoded definitions.
    for (seconds[1..], seconds[0 .. seconds.len - 1]) |current, previous| {
        if (current <= previous) return &.{};
    }
    return seconds;
}

pub fn requiredSecondDigest(ligature: Ligature) ?GlyphDigest {
    if ((ligature.required_second_len & required_second_digest_flag) == 0) {
        return null;
    }
    const len = ligature.required_second_len & ~required_second_digest_flag;
    if (len != required_second_digest_u16_len) return null;
    const start: usize = ligature.required_second_start;
    if (start > ligature.components.len or
        len > ligature.components.len - start)
    {
        return null;
    }
    var words_value: [3]u64 = .{ 0, 0, 0 };
    for (&words_value, 0..) |*word, word_index| {
        inline for (0..4) |part| {
            word.* |= @as(u64, ligature.components[
                start + word_index * 4 + part
            ]) << (part * 16);
        }
    }
    return GlyphDigest.fromWords(words_value);
}

pub fn requiredSecondUsesDigest(ligature: Ligature) bool {
    return (ligature.required_second_len & required_second_digest_flag) != 0;
}

pub fn shouldPrefilterSecond(competing_count: usize) bool {
    return competing_count >= min_competing_for_prefilter;
}

pub fn shouldBuildRequiredSecondIndex(
    competing_count: usize,
    all_require_second: bool,
) bool {
    return all_require_second and
        competing_count >= min_competing_for_required_second;
}

pub fn shouldBuildExactRequiredSecondIndex(
    all_require_second: bool,
    unique_second_count: usize,
) bool {
    return all_require_second and
        unique_second_count > 0 and
        unique_second_count <= max_exact_required_seconds;
}

fn addBoundedUniqueSecond(
    seconds: *[bounded_second_capacity]GlyphId,
    len: *usize,
    glyph: GlyphId,
) void {
    // Seventeen distinct values are enough to disqualify the small exact
    // representation. Retaining that overflow sentinel (rather than clamping
    // to 16) prevents the builder from indexing an incomplete required set;
    // stop doing even bounded duplicate scans after it is present.
    if (len.* == seconds.len) return;
    for (seconds[0..len.*]) |existing| {
        if (existing == glyph) return;
    }
    seconds[len.*] = glyph;
    len.* += 1;
}

fn lessGlyph(_: void, lhs: GlyphId, rhs: GlyphId) bool {
    return lhs < rhs;
}

fn lessSet(_: void, lhs: model.LigatureSet, rhs: model.LigatureSet) bool {
    return lhs.glyph < rhs.glyph;
}
