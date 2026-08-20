//! GSUB run-prefilter necessary-condition and cache contracts.

const std = @import("std");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const prefilter = @import("../../../runtime/prefilter/root.zig");

test "run digest cache reuses summaries and invalidates on mutation epoch" {
    var glyphs = [_]GlyphId{ 1, 2 };
    var generation: usize = 0;
    const run = prefilter.Options{
        .glyph_mutation_generation = &generation,
    };
    var cache = prefilter.Cache.init();

    const initial = cache.digestForRun(&glyphs, 0, run);
    try std.testing.expect(initial.mayHave(1));
    try std.testing.expect(initial.mayHave(2));

    // Reusing a summary within one epoch is intentional. GSUB mutation helpers
    // advance the shared epoch before a later lookup consults the cache.
    glyphs[0] = 7;
    const stale_same_epoch = cache.digestForRun(&glyphs, 0, run);
    try std.testing.expect(stale_same_epoch.mayHave(1));
    try std.testing.expect(!stale_same_epoch.mayHave(7));

    generation += 1;
    const refreshed = cache.digestForRun(&glyphs, 0, run);
    try std.testing.expect(refreshed.mayHave(7));
    try std.testing.expect(!refreshed.mayHave(1));
    try std.testing.expectEqual(generation, cache.generation);
}

test "run digest cache keys source scope and lookup visibility" {
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });

    const glyphs = [_]GlyphId{ 3, 5 };
    const source_features = [_]u32{ 0x6c696761, 0x63616c74 };
    var glyph_classes = [_]u16{0} ** 6;
    glyph_classes[5] = 3;
    var cache = prefilter.Cache.init();

    const liga = cache.digestForRun(&glyphs, 0, .{
        .glyph_source_indices = &sources,
        .source_features = &source_features,
        .active_source_feature = source_features[0],
    });
    try std.testing.expect(liga.mayHave(3));
    try std.testing.expect(liga.mayHave(5));

    const calt = cache.digestForRun(&glyphs, 0, .{
        .glyph_source_indices = &sources,
        .source_features = &source_features,
        .active_source_feature = source_features[1],
    });
    // Cached prefilters are conservative supersets: feature and lookup
    // filtering may leave false positives, but never hide an exact match.
    try std.testing.expect(calt.mayHave(3));
    try std.testing.expect(calt.mayHave(5));

    const ignore_marks = cache.digestForRun(&glyphs, 0x0008, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expect(ignore_marks.mayHave(3));
    try std.testing.expect(ignore_marks.mayHave(5));
}

test "coverage prefilter preserves short exact and long digest paths" {
    var bytes = [_]u8{0} ** 26;
    writeU16(&bytes, 0, 6); // ChainContextSubst lookup.
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 3); // ChainContextSubst format 3.
    writeU16(&bytes, 10, 0); // Backtrack count.
    writeU16(&bytes, 12, 1); // Input count.
    writeU16(&bytes, 14, 12); // First input Coverage at 20.
    writeU16(&bytes, 16, 0); // Lookahead count.
    writeU16(&bytes, 18, 0); // Substitution count.
    writeCoverage1(&bytes, 20, 5);
    const view = prefilter.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expect(try prefilter.chainingCoverageLookupMayMatch(
        view,
        0,
        1,
        &.{ 4, 5 },
        0,
        .{},
    ));
    try std.testing.expect(!try prefilter.chainingCoverageLookupMayMatch(
        view,
        0,
        1,
        &.{ 4, 6 },
        0,
        .{},
    ));

    var long_run = [_]GlyphId{6} ** 64;
    try std.testing.expect(!try prefilter.chainingCoverageLookupMayMatch(
        view,
        0,
        1,
        &long_run,
        0,
        .{},
    ));
    long_run[63] = 5;
    try std.testing.expect(try prefilter.chainingCoverageLookupMayMatch(
        view,
        0,
        1,
        &long_run,
        0,
        .{},
    ));

    var glyph_classes = [_]u16{0} ** 6;
    glyph_classes[5] = 3;
    try std.testing.expect(!try prefilter.chainingCoverageLookupMayMatch(
        view,
        0,
        1,
        &.{5},
        0x0008,
        .{ .glyph_classes = &glyph_classes },
    ));
}

test "exact candidate prefilter handles hits boundaries and empty sets" {
    const candidates = [_]GlyphId{ 2, 7, 11 };
    try std.testing.expect(prefilter.hasAnyGlyph(&.{ 1, 7 }, &candidates));
    try std.testing.expect(prefilter.hasAnyGlyph(&.{11}, &candidates));
    try std.testing.expect(!prefilter.hasAnyGlyph(&.{ 1, 8 }, &candidates));
    try std.testing.expect(!prefilter.hasAnyGlyph(&.{ 2, 7 }, &.{}));
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
