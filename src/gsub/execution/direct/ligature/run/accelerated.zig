//! Accelerator-backed LigatureSubst execution and second-component prefilters.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const prefilter = @import("../../../../runtime/prefilter/root.zig");
const commit = @import("../commit.zig");
const matching = @import("../matching.zig");
const metadata = @import("../metadata.zig");
const model = @import("../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = std.mem.Allocator.Error;
const Ligature = accelerator.model.LigatureSubstitution;

pub fn apply(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return applyKind(
        false,
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn applyPrefiltered(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return applyKind(
        true,
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub noinline fn applyRequiredSecond(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    @branchHint(.cold);
    if (matching.requiredSecondUsesDigest(ligature)) {
        const second_digest = matching.requiredSecondDigest(ligature) orelse {
            // Optional accelerator metadata must never alter substitution
            // semantics. If a stale or manually assembled sidecar has an
            // invalid tagged range, use the canonical decoded rules.
            return apply(ligature, glyphs, allocator, lookup_flag, run);
        };
        const may_have_pair = if (lookup_flag == 0 and
            run.run_has_default_ignorables == false)
            hasAdjacentDigestPair(
                glyphs.items,
                ligature.first_component_digest,
                second_digest,
            )
        else
            // A conservative unfiltered scan may admit extra work, but unlike
            // physical adjacency it cannot reject a component reached after
            // LookupFlag/default-ignorable traversal.
            hasAnyDigestGlyph(glyphs.items, second_digest);
        if (!may_have_pair) return;
        return applyPrefiltered(
            ligature,
            glyphs,
            allocator,
            lookup_flag,
            run,
        );
    }
    const second_components = matching.requiredSecondComponents(ligature);
    if (second_components.len == 0) {
        return apply(ligature, glyphs, allocator, lookup_flag, run);
    }
    if (!(if (lookup_flag == 0 and
        run.run_has_default_ignorables == false)
        hasAdjacentRequiredPair(
            glyphs.items,
            ligature.first_component_digest,
            second_components,
        )
    else
        prefilter.hasAnyGlyph(glyphs.items, second_components)))
    {
        return;
    }
    return applyPrefiltered(
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

fn hasAnyDigestGlyph(
    glyphs: []const GlyphId,
    digest: @import("../../../../../glyph_digest.zig").GlyphDigest,
) bool {
    for (glyphs) |glyph| if (digest.mayHave(glyph)) return true;
    return false;
}

pub fn applyAt(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?model.Change {
    if (glyph_index >= glyphs.items.len) return null;
    const first = glyphs.items[glyph_index];
    if (!ligature.first_component_digest.mayHave(first) or
        filtering.lookupIgnoresGlyph(lookup_flag, run, first)) return null;
    const set = matching.setForGlyph(ligature, first) orelse return null;
    var component_offsets: [model.max_components]usize = undefined;
    const found = tryMatch(
        ligature,
        set,
        glyphs.items[glyph_index..],
        glyph_index,
        lookup_flag,
        run,
        &component_offsets,
    ) orelse return null;
    const info = try metadata.componentInfo(
        allocator,
        run,
        glyph_index,
        found,
    );
    metadata.mergeClusters(run, glyph_index, found);
    return commit.apply(glyphs, glyph_index, found, info, run);
}

fn tryMatch(
    ligature: Ligature,
    set: accelerator.model.LigatureSet,
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    component_offsets: *[model.max_components]usize,
) ?model.Match {
    return if (ligature.prefilter_second)
        matching.acceleratedPrefilteredMatch(
            ligature,
            set,
            glyphs,
            glyph_base,
            lookup_flag,
            run,
            component_offsets,
        )
    else
        matching.acceleratedMatch(
            ligature,
            set,
            glyphs,
            glyph_base,
            lookup_flag,
            run,
            component_offsets,
        );
}

fn hasAdjacentDigestPair(
    glyphs: []const GlyphId,
    first_digest: @import("../../../../../glyph_digest.zig").GlyphDigest,
    second_digest: @import("../../../../../glyph_digest.zig").GlyphDigest,
) bool {
    if (glyphs.len < 2) return false;
    for (glyphs[0 .. glyphs.len - 1], glyphs[1..]) |first, second| {
        if (first_digest.mayHave(first) and second_digest.mayHave(second)) {
            return true;
        }
    }
    return false;
}

fn hasAdjacentRequiredPair(
    glyphs: []const GlyphId,
    first_digest: @import("../../../../../glyph_digest.zig").GlyphDigest,
    sorted_seconds: []const GlyphId,
) bool {
    if (glyphs.len < 2) return false;
    for (glyphs[0 .. glyphs.len - 1], glyphs[1..]) |first, second| {
        if (!first_digest.mayHave(first)) continue;
        if (std.sort.binarySearch(
            GlyphId,
            sorted_seconds,
            second,
            glyphOrder,
        ) != null) return true;
    }
    return false;
}

fn glyphOrder(target: GlyphId, item: GlyphId) std.math.Order {
    return std.math.order(target, item);
}

test "adjacent required pair rejects separated candidates" {
    var first = @import("../../../../../glyph_digest.zig").GlyphDigest.empty();
    first.add(5);
    try std.testing.expect(hasAdjacentRequiredPair(&.{ 5, 7 }, first, &.{7}));
    try std.testing.expect(!hasAdjacentRequiredPair(
        &.{ 5, 9, 7 },
        first,
        &.{7},
    ));
}

test "digest required-second prefilter preserves lookup-ignored marks" {
    const definition_count = 129;
    var definitions: [definition_count]accelerator.model.LigatureDefinition = undefined;
    var components: [definition_count + 12]GlyphId = undefined;
    for (&definitions, 0..) |*definition, index| {
        definition.* = .{
            .ligature = 40,
            .component_start = index,
            .component_count = 2,
        };
        components[index] = 2;
    }
    var first_digest = @import("../../../../../glyph_digest.zig").GlyphDigest.empty();
    first_digest.add(1);
    var second_digest = @import("../../../../../glyph_digest.zig").GlyphDigest.empty();
    second_digest.add(2);
    for (second_digest.words(), 0..) |word, word_index| {
        inline for (0..4) |part| {
            components[definition_count + word_index * 4 + part] =
                @truncate(word >> (part * 16));
        }
    }
    const sets = [_]accelerator.model.LigatureSet{.{
        .glyph = 1,
        .definition_start = 0,
        .definition_len = definition_count,
    }};
    const ligature: Ligature = .{
        .sets = &sets,
        .definitions = &definitions,
        .components = &components,
        .first_component_digest = first_digest,
        .required_second_start = definition_count,
        .required_second_len = 0x800c,
    };
    var glyph_classes = [_]u16{0} ** 100;
    glyph_classes[99] = 3;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 99, 2 });

    try applyRequiredSecond(
        ligature,
        &glyphs,
        std.testing.allocator,
        0x0008,
        .{ .glyph_classes = &glyph_classes },
    );
    try std.testing.expectEqualSlices(GlyphId, &.{ 40, 99 }, glyphs.items);
}

test "invalid required-second digest falls back to decoded rules" {
    var first_digest = @import("../../../../../glyph_digest.zig").GlyphDigest.empty();
    first_digest.add(1);
    const sets = [_]accelerator.model.LigatureSet{.{
        .glyph = 1,
        .definition_start = 0,
        .definition_len = 1,
    }};
    const definitions = [_]accelerator.model.LigatureDefinition{.{
        .ligature = 40,
        .component_start = 0,
        .component_count = 2,
    }};
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2 });

    try applyRequiredSecond(.{
        .sets = &sets,
        .definitions = &definitions,
        .components = &.{2},
        .first_component_digest = first_digest,
        .required_second_start = 1,
        .required_second_len = 0x800b,
    }, &glyphs, std.testing.allocator, 0, .{});
    try std.testing.expectEqualSlices(GlyphId, &.{40}, glyphs.items);
}

fn applyKind(
    comptime prefilter_second: bool,
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    var component_offsets: [model.max_components]usize = undefined;
    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) : (glyph_index += 1) {
        const first = glyphs.items[glyph_index];
        if (!ligature.first_component_digest.mayHave(first)) continue;
        // The digest is a cheap necessary condition independent of feature
        // scope and LookupFlag visibility. Rejecting misses first avoids both
        // metadata lookups for the overwhelming non-candidate population.
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index)) continue;
        if (filtering.lookupIgnoresGlyph(lookup_flag, run, first)) continue;
        const set = matching.setForGlyph(ligature, first) orelse continue;
        const found = if (prefilter_second)
            matching.acceleratedPrefilteredMatch(
                ligature,
                set,
                glyphs.items[glyph_index..],
                glyph_index,
                lookup_flag,
                run,
                &component_offsets,
            )
        else
            matching.acceleratedMatch(
                ligature,
                set,
                glyphs.items[glyph_index..],
                glyph_index,
                lookup_flag,
                run,
                &component_offsets,
            );
        const matched = found orelse continue;
        const info = try metadata.componentInfo(
            allocator,
            run,
            glyph_index,
            matched,
        );
        metadata.mergeClusters(run, glyph_index, matched);
        _ = commit.apply(glyphs, glyph_index, matched, info, run);
    }
}
