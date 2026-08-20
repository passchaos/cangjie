//! Public shaping requests and the reusable plan identity derived from them.
//!
//! A plan deliberately captures only lookup-selection inputs. Font identity,
//! source bytes, and output storage belong to higher-level shaped-run caches,
//! so this module remains independent of the layout orchestrator.

const std = @import("std");
const pipeline_types = @import("../pipeline/types.zig");
const unicode = @import("../../unicode.zig");

pub const ClusterLevel = pipeline_types.ClusterLevel;
pub const ScriptPosition = pipeline_types.ScriptPosition;
pub const TextDirection = pipeline_types.TextDirection;
pub const TextOrientation = pipeline_types.TextOrientation;
pub const WritingMode = pipeline_types.WritingMode;

pub const ShapeOptions = struct {
    direction: TextDirection = .ltr,
    /// Reorder the logical UTF-8 input into bidi visual order after shaping.
    ///
    /// Callers that already materialized visual text (for example, a retained
    /// document engine implementing its own unicode-bidi run boundaries) can
    /// disable this while retaining all other GSUB/GPOS and fallback behavior.
    reorder_bidi: bool = true,
    /// Shape through the OpenType native-direction buffer order even when final
    /// bidi reordering is disabled. This is mainly for parity tools that need
    /// HarfBuzz buffer order without Cangjie's paragraph-level bidi pass.
    native_direction_shaping: bool = false,
    writing_mode: WritingMode = .horizontal_tb,
    text_orientation: TextOrientation = .mixed,
    script_tag: ?unicode.OpenTypeScriptTag = null,
    language_tag: ?unicode.OpenTypeLanguageTag = null,
    script_position: ScriptPosition = .normal,
    features: []const unicode.FeatureOverride = &.{},
    /// Normalized variation-space coordinates in fvar axis order after avar
    /// mapping. The default empty slice preserves legacy/default-instance
    /// shaping and lets glyph metric caches stay keyed only by glyph id.
    normalized_variation_coords: []const f32 = &.{},
    /// Optional HarfBuzz-compatible synthetic glyph id for unsupported
    /// variation selectors. This is a diagnostics/parity switch: it keeps the
    /// unsupported selector visible to GSUB/GPOS matching and reports this glyph
    /// id with zero advance, without changing the real font glyph id.
    not_found_variation_selector_glyph: ?u32 = null,
    /// Delete untouched default-ignorables after substitution and positioning.
    ///
    /// The default behavior mirrors HarfBuzz by replacing them with the font's
    /// space glyph at zero advance when one exists. This explicit mode forces
    /// deletion even in that case, while substituted controls and a requested
    /// not-found variation-selector glyph remain visible.
    remove_default_ignorables: bool = false,
    /// Optional item context used for HarfBuzz-style shaping of a substring.
    ///
    /// The context is not emitted. It only influences joining decisions at the
    /// item boundaries, matching the common use of hb_buffer pre/post context.
    context_before: []const u8 = &.{},
    context_after: []const u8 = &.{},
    beginning_of_text: bool = false,
    end_of_text: bool = false,
    cluster_level: ?ClusterLevel = null,
};

/// Coarse shaping plan identity. It intentionally excludes the concrete font
/// and text bytes; those live in the higher-level shaped-run cache key. This
/// part captures the OpenType selection knobs that change active lookups.
pub const ShapePlanKey = struct {
    direction: TextDirection = .ltr,
    reorder_bidi: bool = true,
    native_direction_shaping: bool = false,
    writing_mode: WritingMode = .horizontal_tb,
    text_orientation: TextOrientation = .mixed,
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    script_position: ScriptPosition = .normal,
    feature_hash: u64 = 0,
    variation_hash: u64 = 0,
    context_hash: u64 = 0,
    beginning_of_text: bool = false,
    end_of_text: bool = false,
    not_found_variation_selector_glyph: ?u32 = null,
    remove_default_ignorables: bool = false,
    cluster_level: ?ClusterLevel = null,

    pub fn fromText(text: []const u8, options: ShapeOptions) ShapePlanKey {
        const infer_both =
            options.script_tag == null and options.language_tag == null;
        const inferred = if (infer_both)
            unicode.inferOpenTypeProperties(text)
        else
            undefined;
        return .{
            .direction = options.direction,
            .reorder_bidi = options.reorder_bidi,
            .native_direction_shaping = options.native_direction_shaping,
            .writing_mode = options.writing_mode,
            .text_orientation = options.text_orientation,
            .script_tag = options.script_tag orelse unicode.openTypeScriptTag(
                if (infer_both)
                    inferred.script
                else
                    unicode.inferOpenTypeScript(text),
            ),
            .language_tag = options.language_tag orelse if (infer_both)
                inferred.language
            else
                unicode.inferOpenTypeLanguageTag(text),
            .script_position = options.script_position,
            .feature_hash = featureOverridesHash(options.features),
            .variation_hash = normalizedVariationCoordsHash(
                options.normalized_variation_coords,
            ),
            .context_hash = contextHash(
                options.context_before,
                options.context_after,
            ),
            .beginning_of_text = options.beginning_of_text,
            .end_of_text = options.end_of_text,
            .not_found_variation_selector_glyph = options.not_found_variation_selector_glyph,
            .remove_default_ignorables = options.remove_default_ignorables,
            .cluster_level = options.cluster_level,
        };
    }

    pub fn eql(a: ShapePlanKey, b: ShapePlanKey) bool {
        return a.direction == b.direction and
            a.reorder_bidi == b.reorder_bidi and
            a.native_direction_shaping == b.native_direction_shaping and
            a.writing_mode == b.writing_mode and
            a.text_orientation == b.text_orientation and
            a.script_tag == b.script_tag and
            a.language_tag == b.language_tag and
            a.script_position == b.script_position and
            a.feature_hash == b.feature_hash and
            a.variation_hash == b.variation_hash and
            a.context_hash == b.context_hash and
            a.beginning_of_text == b.beginning_of_text and
            a.end_of_text == b.end_of_text and
            a.not_found_variation_selector_glyph ==
                b.not_found_variation_selector_glyph and
            a.remove_default_ignorables == b.remove_default_ignorables and
            a.cluster_level == b.cluster_level;
    }
};

pub const ShapePlan = struct {
    key: ShapePlanKey,
    hits: usize = 0,
};

pub const ShapePlanCache = struct {
    allocator: std.mem.Allocator,
    plans: std.ArrayList(ShapePlan) = .empty,

    pub fn init(allocator: std.mem.Allocator) ShapePlanCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ShapePlanCache) void {
        self.plans.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn getOrPut(self: *ShapePlanCache, key: ShapePlanKey) !*ShapePlan {
        for (self.plans.items) |*plan| {
            if (plan.key.eql(key)) {
                plan.hits += 1;
                return plan;
            }
        }
        try self.plans.append(self.allocator, .{ .key = key, .hits = 1 });
        return &self.plans.items[self.plans.items.len - 1];
    }
};

fn featureOverridesHash(features: []const unicode.FeatureOverride) u64 {
    // Reserve zero for the overwhelmingly common no-override plan and avoid
    // constructing/finalizing Wyhash per run. Non-empty plans retain their
    // established hash representation for cache compatibility.
    if (features.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    for (features) |feature| {
        hasher.update(std.mem.asBytes(&feature.tag));
        const value = feature.effectiveValue();
        hasher.update(std.mem.asBytes(&value));
    }
    return hasher.final();
}

fn normalizedVariationCoordsHash(coords: []const f32) u64 {
    // Match GlyphMetricsCache's established default-instance key. No axis
    // coordinates means there are no bytes to distinguish, so hashing the
    // empty length only adds work to every default shaping plan.
    if (coords.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&coords.len));
    for (coords) |coord| {
        const bits: u32 = @bitCast(coord);
        hasher.update(std.mem.asBytes(&bits));
    }
    return hasher.final();
}

fn contextHash(before: []const u8, after: []const u8) u64 {
    if (before.len == 0 and after.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&before.len));
    hasher.update(before);
    hasher.update(std.mem.asBytes(&after.len));
    hasher.update(after);
    return hasher.final();
}

test "default shape-plan inputs use zero hashes" {
    try std.testing.expectEqual(@as(u64, 0), featureOverridesHash(&.{}));
    try std.testing.expectEqual(
        @as(u64, 0),
        normalizedVariationCoordsHash(&.{}),
    );
    try std.testing.expectEqual(@as(u64, 0), contextHash("", ""));

    // Non-empty values must still take the payload-sensitive hash path.
    try std.testing.expect(featureOverridesHash(&.{
        .{ .tag = unicode.tag("liga"), .enabled = false },
    }) != 0);
    try std.testing.expect(normalizedVariationCoordsHash(&.{0.25}) != 0);
    try std.testing.expect(contextHash("a", "") != 0);
}
