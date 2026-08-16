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
    var second_components = std.ArrayList(GlyphId).empty;
    defer second_components.deinit(allocator);
    var competing_count: usize = 0;
    var first_digest = GlyphDigest.empty();
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
                    try second_components.append(allocator, component);
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
        std.sort.heap(GlyphId, second_components.items, {}, lessGlyph);
        deduplicateSorted(&second_components);
        if (components.items.len <= std.math.maxInt(u32) and
            second_components.items.len <= std.math.maxInt(u16) and
            second_components.items.len <=
                std.math.maxInt(u32) - components.items.len)
        {
            required_second_start = @intCast(components.items.len);
            required_second_len = @intCast(second_components.items.len);
            try components.appendSlice(allocator, second_components.items);
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
    const start: usize = ligature.required_second_start;
    const len: usize = ligature.required_second_len;
    if (start > ligature.components.len or
        len > ligature.components.len - start)
    {
        return &.{};
    }
    return ligature.components[start .. start + len];
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

fn deduplicateSorted(glyphs: *std.ArrayList(GlyphId)) void {
    if (glyphs.items.len < 2) return;
    var write: usize = 1;
    for (glyphs.items[1..]) |glyph| {
        if (glyph == glyphs.items[write - 1]) continue;
        glyphs.items[write] = glyph;
        write += 1;
    }
    glyphs.shrinkRetainingCapacity(write);
}

fn lessGlyph(_: void, lhs: GlyphId, rhs: GlyphId) bool {
    return lhs < rhs;
}

fn lessSet(_: void, lhs: model.LigatureSet, rhs: model.LigatureSet) bool {
    return lhs.glyph < rhs.glyph;
}
