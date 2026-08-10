const std = @import("std");

const Font = @import("font.zig").Font;
const GdefLookupMetadata = @import("font.zig").GdefLookupMetadata;
const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const gsub = @import("gsub.zig");
const unicode = @import("unicode.zig");

pub const GlyphMetrics = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

pub const VerticalGlyphMetrics = struct {
    advance_height: u16,
    top_side_bearing: i16,
};

const GdefMetadataCacheKey = struct {
    font_addr: usize,
};

pub const GdefMetadataCache = struct {
    const Entry = struct {
        key: GdefMetadataCacheKey,
        metadata: GdefLookupMetadata,
    };

    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GdefMetadataCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *GdefMetadataCache) void {
        self.clear();
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *GdefMetadataCache) void {
        for (self.entries.items) |*entry| {
            entry.metadata.deinit(self.allocator);
        }
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn metadata(self: *GdefMetadataCache, font: *const Font) !*const GdefLookupMetadata {
        const key = GdefMetadataCacheKey{ .font_addr = @intFromPtr(font) };
        for (self.entries.items) |*entry| {
            if (entry.key.font_addr == key.font_addr) {
                self.hits += 1;
                return &entry.metadata;
            }
        }

        self.misses += 1;
        var metadata_value = try font.gdefLookupMetadataForShaping(self.allocator);
        errdefer metadata_value.deinit(self.allocator);
        try self.entries.append(self.allocator, .{
            .key = key,
            .metadata = metadata_value,
        });
        return &self.entries.items[self.entries.items.len - 1].metadata;
    }
};

const TableProofCacheKey = struct {
    font_addr: usize,
};

pub const GsubTableProofCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(TableProofCacheKey, void),
    last_font_addr: ?usize = null,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GsubTableProofCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(TableProofCacheKey, void).init(allocator),
        };
    }

    pub fn deinit(self: *GsubTableProofCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GsubTableProofCache) void {
        self.entries.clearRetainingCapacity();
        self.last_font_addr = null;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn prove(self: *GsubTableProofCache, font: *const Font) !void {
        const font_addr = @intFromPtr(font);
        // Consecutive runs overwhelmingly use the same face. Keep the hash
        // set for arbitrary fallback cascades, but let the normal path prove
        // membership with one pointer comparison instead of finalizing a hash
        // for every shaped word.
        if (self.last_font_addr == font_addr) {
            self.hits += 1;
            return;
        }
        const key = TableProofCacheKey{ .font_addr = font_addr };
        if (self.entries.contains(key)) {
            self.last_font_addr = font_addr;
            self.hits += 1;
            return;
        }
        self.misses += 1;
        try font.proveGsubTableForShaping();
        try self.entries.put(key, {});
        self.last_font_addr = font_addr;
    }
};

pub const GposTableProofCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(TableProofCacheKey, void),
    last_font_addr: ?usize = null,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GposTableProofCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(TableProofCacheKey, void).init(allocator),
        };
    }

    pub fn deinit(self: *GposTableProofCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GposTableProofCache) void {
        self.entries.clearRetainingCapacity();
        self.last_font_addr = null;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn prove(self: *GposTableProofCache, font: *const Font) !void {
        const font_addr = @intFromPtr(font);
        if (self.last_font_addr == font_addr) {
            self.hits += 1;
            return;
        }
        const key = TableProofCacheKey{ .font_addr = font_addr };
        if (self.entries.contains(key)) {
            self.last_font_addr = font_addr;
            self.hits += 1;
            return;
        }
        self.misses += 1;
        try font.proveGposTableForShaping();
        try self.entries.put(key, {});
        self.last_font_addr = font_addr;
    }
};

test "table proof caches fast-path consecutive fonts and reset locality" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildScriptFeatureGsubTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var font_a = try Font.parse(std.testing.allocator, bytes);
    defer font_a.deinit();
    var font_b = try Font.parse(std.testing.allocator, bytes);
    defer font_b.deinit();

    var gsub_cache = GsubTableProofCache.init(std.testing.allocator);
    defer gsub_cache.deinit();
    try gsub_cache.prove(&font_a);
    try gsub_cache.prove(&font_a);
    try gsub_cache.prove(&font_b);
    try gsub_cache.prove(&font_a); // Hash-set hit after switching faces.
    try std.testing.expectEqual(@as(usize, 2), gsub_cache.hits);
    try std.testing.expectEqual(@as(usize, 2), gsub_cache.misses);
    try std.testing.expectEqual(@as(?usize, @intFromPtr(&font_a)), gsub_cache.last_font_addr);

    var gpos_cache = GposTableProofCache.init(std.testing.allocator);
    defer gpos_cache.deinit();
    try gpos_cache.prove(&font_a);
    try gpos_cache.prove(&font_a);
    try std.testing.expectEqual(@as(usize, 1), gpos_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), gpos_cache.misses);

    gsub_cache.clear();
    try std.testing.expectEqual(@as(?usize, null), gsub_cache.last_font_addr);
    try std.testing.expectEqual(@as(usize, 0), gsub_cache.hits);
    try std.testing.expectEqual(@as(usize, 0), gsub_cache.misses);
}

const LookupTableKind = enum {
    gsub,
    gpos,
};

const LookupSelectionKey = struct {
    font_addr: usize,
    table: LookupTableKind,
    script_tag: unicode.OpenTypeScriptTag,
    language_tag: unicode.OpenTypeLanguageTag,
    feature_hash: u64,
    vertical: bool,
    run_has_gdef_marks: ?bool,
};

pub const LayoutScriptSelections = struct {
    gsub: Font.LayoutScriptSelection,
    gpos: Font.LayoutScriptSelection,
};

pub const LookupSelectionCache = struct {
    const Entry = struct {
        key: LookupSelectionKey,
        features: []unicode.FeatureOverride,
        lookups: []u16,
    };
    const GsubAcceleratorEntry = struct {
        font_addr: usize,
        accelerators: []gsub.LookupAccelerator,
    };
    const GposAcceleratorEntry = struct {
        font_addr: usize,
        accelerators: []gpos.LookupAccelerator,
    };
    const ScriptSelectionEntry = struct {
        font_addr: usize,
        script: unicode.Script,
        explicit_tag: ?unicode.OpenTypeScriptTag,
        gsub: Font.LayoutScriptSelection,
        gpos: Font.LayoutScriptSelection,
    };
    const FeaturePlanEntry = struct {
        key: LookupSelectionKey,
        features: []unicode.FeatureOverride,
        applications: []gsub.FeatureApplication,
        plan: gsub.FeatureLookupPlan,
    };

    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    gsub_accelerator_entries: std.ArrayList(GsubAcceleratorEntry) = .empty,
    gpos_accelerator_entries: std.ArrayList(GposAcceleratorEntry) = .empty,
    script_selection_entries: std.ArrayList(ScriptSelectionEntry) = .empty,
    gsub_feature_plan_entries: std.ArrayList(FeaturePlanEntry) = .empty,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) LookupSelectionCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LookupSelectionCache) void {
        self.clear();
        self.script_selection_entries.deinit(self.allocator);
        self.gsub_feature_plan_entries.deinit(self.allocator);
        self.gpos_accelerator_entries.deinit(self.allocator);
        self.gsub_accelerator_entries.deinit(self.allocator);
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *LookupSelectionCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.features);
            self.allocator.free(entry.lookups);
        }
        self.entries.clearRetainingCapacity();
        for (self.gsub_accelerator_entries.items) |entry| {
            gsub.deinitLookupAccelerators(self.allocator, entry.accelerators);
        }
        self.gsub_accelerator_entries.clearRetainingCapacity();
        for (self.gpos_accelerator_entries.items) |entry| {
            gpos.deinitLookupAccelerators(self.allocator, entry.accelerators);
        }
        self.gpos_accelerator_entries.clearRetainingCapacity();
        self.script_selection_entries.clearRetainingCapacity();
        for (self.gsub_feature_plan_entries.items) |*entry| {
            self.allocator.free(entry.features);
            self.allocator.free(entry.applications);
            entry.plan.deinit(self.allocator);
        }
        self.gsub_feature_plan_entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn gsubLookups(self: *LookupSelectionCache, font: *const Font, options: gsub.LookupOptions, gdef_metadata: GdefLookupMetadata) ![]const u16 {
        const key = lookupSelectionKey(font, .gsub, options.script_tag, options.language_tag, options.features, options.vertical, null);
        if (self.lookup(key, options.features)) |lookups| return lookups;

        self.misses += 1;
        const lookups = try font.selectGsubLookupsForShaping(self.allocator, options, gdef_metadata);
        errdefer self.allocator.free(lookups);
        const features = try self.allocator.dupe(unicode.FeatureOverride, options.features);
        errdefer self.allocator.free(features);
        try self.entries.append(self.allocator, .{ .key = key, .features = features, .lookups = lookups });
        return self.entries.items[self.entries.items.len - 1].lookups;
    }

    pub fn gsubLookupAccelerators(self: *LookupSelectionCache, font: *const Font) ![]const gsub.LookupAccelerator {
        const font_addr = @intFromPtr(font);
        for (self.gsub_accelerator_entries.items) |entry| {
            if (entry.font_addr != font_addr) continue;
            self.hits += 1;
            return entry.accelerators;
        }

        self.misses += 1;
        const accelerators = try font.gsubLookupAcceleratorsForShaping(self.allocator);
        errdefer self.allocator.free(accelerators);
        try self.gsub_accelerator_entries.append(self.allocator, .{
            .font_addr = font_addr,
            .accelerators = accelerators,
        });
        return self.gsub_accelerator_entries.items[self.gsub_accelerator_entries.items.len - 1].accelerators;
    }

    pub fn gsubFeatureLookupPlan(self: *LookupSelectionCache, font: *const Font, applications: []const gsub.FeatureApplication, options: gsub.LookupOptions, gdef_metadata: GdefLookupMetadata) !gsub.FeatureLookupPlan {
        const key = lookupSelectionKey(font, .gsub, options.script_tag, options.language_tag, options.features, options.vertical, null);
        for (self.gsub_feature_plan_entries.items) |entry| {
            if (!lookupSelectionKeysEqual(entry.key, key)) continue;
            if (!featureOverridesEqual(entry.features, options.features)) continue;
            if (!featureApplicationsEqual(entry.applications, applications)) continue;
            self.hits += 1;
            return entry.plan;
        }

        self.misses += 1;
        const plan = try font.gsubFeatureLookupPlanForShaping(self.allocator, applications, options, gdef_metadata);
        errdefer {
            var mutable_plan = plan;
            mutable_plan.deinit(self.allocator);
        }
        const features = try self.allocator.dupe(unicode.FeatureOverride, options.features);
        errdefer self.allocator.free(features);
        const applications_copy = try self.allocator.dupe(gsub.FeatureApplication, applications);
        errdefer self.allocator.free(applications_copy);
        try self.gsub_feature_plan_entries.append(self.allocator, .{
            .key = key,
            .features = features,
            .applications = applications_copy,
            .plan = plan,
        });
        return self.gsub_feature_plan_entries.items[self.gsub_feature_plan_entries.items.len - 1].plan;
    }

    pub fn gposLookupAccelerators(self: *LookupSelectionCache, font: *const Font) ![]const gpos.LookupAccelerator {
        const font_addr = @intFromPtr(font);
        for (self.gpos_accelerator_entries.items) |entry| {
            if (entry.font_addr != font_addr) continue;
            self.hits += 1;
            return entry.accelerators;
        }

        self.misses += 1;
        const accelerators = try font.gposLookupAcceleratorsForShaping(self.allocator);
        errdefer self.allocator.free(accelerators);
        try self.gpos_accelerator_entries.append(self.allocator, .{
            .font_addr = font_addr,
            .accelerators = accelerators,
        });
        return self.gpos_accelerator_entries.items[self.gpos_accelerator_entries.items.len - 1].accelerators;
    }

    pub fn gposLookups(self: *LookupSelectionCache, font: *const Font, options: gpos.LookupOptions, gdef_metadata: GdefLookupMetadata) ![]const u16 {
        const key = lookupSelectionKey(font, .gpos, options.script_tag, options.language_tag, options.features, false, options.run_has_gdef_marks);
        if (self.lookup(key, options.features)) |lookups| return lookups;

        self.misses += 1;
        const lookups = try font.selectGposLookupsForShaping(self.allocator, options, gdef_metadata);
        errdefer self.allocator.free(lookups);
        const features = try self.allocator.dupe(unicode.FeatureOverride, options.features);
        errdefer self.allocator.free(features);
        try self.entries.append(self.allocator, .{ .key = key, .features = features, .lookups = lookups });
        return self.entries.items[self.entries.items.len - 1].lookups;
    }

    pub fn layoutScripts(
        self: *LookupSelectionCache,
        font: *const Font,
        script: unicode.Script,
        explicit_tag: ?unicode.OpenTypeScriptTag,
    ) !LayoutScriptSelections {
        const font_addr = @intFromPtr(font);
        for (self.script_selection_entries.items) |entry| {
            if (entry.font_addr == font_addr and entry.script == script and entry.explicit_tag == explicit_tag) {
                return .{ .gsub = entry.gsub, .gpos = entry.gpos };
            }
        }
        const entry = ScriptSelectionEntry{
            .font_addr = font_addr,
            .script = script,
            .explicit_tag = explicit_tag,
            .gsub = try font.selectGsubScriptForShaping(script, explicit_tag),
            .gpos = try font.selectGposScriptForShaping(script, explicit_tag),
        };
        try self.script_selection_entries.append(self.allocator, entry);
        return .{ .gsub = entry.gsub, .gpos = entry.gpos };
    }

    fn lookup(self: *LookupSelectionCache, key: LookupSelectionKey, features: []const unicode.FeatureOverride) ?[]const u16 {
        for (self.entries.items) |entry| {
            if (!lookupSelectionKeysEqual(entry.key, key)) continue;
            if (!featureOverridesEqual(entry.features, features)) continue;
            self.hits += 1;
            return entry.lookups;
        }
        return null;
    }
};

fn lookupSelectionKey(font: *const Font, table: LookupTableKind, script_tag: unicode.OpenTypeScriptTag, language_tag: unicode.OpenTypeLanguageTag, features: []const unicode.FeatureOverride, vertical: bool, run_has_gdef_marks: ?bool) LookupSelectionKey {
    return .{
        .font_addr = @intFromPtr(font),
        .table = table,
        .script_tag = script_tag,
        .language_tag = language_tag,
        .feature_hash = featureOverridesHash(features),
        .vertical = vertical,
        .run_has_gdef_marks = run_has_gdef_marks,
    };
}

fn lookupSelectionKeysEqual(a: LookupSelectionKey, b: LookupSelectionKey) bool {
    return a.font_addr == b.font_addr and
        a.table == b.table and
        a.script_tag == b.script_tag and
        a.language_tag == b.language_tag and
        a.feature_hash == b.feature_hash and
        a.vertical == b.vertical and
        a.run_has_gdef_marks == b.run_has_gdef_marks;
}

fn featureOverridesHash(features: []const unicode.FeatureOverride) u64 {
    // Empty overrides are the normal shaping case. Zero is a stable sentinel
    // because cache hits still compare the complete override slices after the
    // hash key matches, so a rare collision cannot alias different plans.
    if (features.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    for (features) |feature| {
        hasher.update(std.mem.asBytes(&feature.tag));
        const enabled: u8 = @intFromBool(feature.enabled);
        hasher.update(std.mem.asBytes(&enabled));
    }
    return hasher.final();
}

test "lookup selection reserves zero feature hash for defaults" {
    try std.testing.expectEqual(@as(u64, 0), featureOverridesHash(&.{}));
    try std.testing.expect(featureOverridesHash(&.{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    }) != 0);
}

fn featureOverridesEqual(a: []const unicode.FeatureOverride, b: []const unicode.FeatureOverride) bool {
    if (a.len != b.len) return false;
    for (a, b) |a_feature, b_feature| {
        if (a_feature.tag != b_feature.tag or a_feature.enabled != b_feature.enabled) return false;
    }
    return true;
}

fn featureApplicationsEqual(a: []const gsub.FeatureApplication, b: []const gsub.FeatureApplication) bool {
    if (a.len != b.len) return false;
    for (a, b) |a_application, b_application| {
        if (a_application.tag != b_application.tag or
            a_application.source_scoped != b_application.source_scoped or
            a_application.auto_zwnj != b_application.auto_zwnj or
            a_application.auto_zwj != b_application.auto_zwj or
            a_application.match_source_syllable != b_application.match_source_syllable) return false;
    }
    return true;
}

test "feature plan cache distinguishes syllable-scoped applications" {
    const global = [_]gsub.FeatureApplication{
        .{ .tag = unicode.tag("rphf"), .source_scoped = true },
    };
    const syllable_scoped = [_]gsub.FeatureApplication{
        .{
            .tag = unicode.tag("rphf"),
            .source_scoped = true,
            .match_source_syllable = true,
        },
    };

    try std.testing.expect(featureApplicationsEqual(&global, &global));
    try std.testing.expect(!featureApplicationsEqual(&global, &syllable_scoped));
}

const GlyphMetricsKey = struct {
    font_addr: usize,
    glyph_id: GlyphId,
    variation_hash: u64 = 0,
};

pub const GlyphMetricsCache = struct {
    const direct_capacity = 512;
    const HorizontalDirectEntry = struct {
        key: GlyphMetricsKey = .{ .font_addr = 0, .glyph_id = 0 },
        metrics: GlyphMetrics = .{ .advance_width = 0, .left_side_bearing = 0 },
        valid: bool = false,
    };
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphMetricsKey, GlyphMetrics),
    vertical_entries: std.AutoHashMap(GlyphMetricsKey, ?VerticalGlyphMetrics),
    direct_entries: [direct_capacity]HorizontalDirectEntry = [_]HorizontalDirectEntry{.{}} ** direct_capacity,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GlyphMetricsCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(GlyphMetricsKey, GlyphMetrics).init(allocator),
            .vertical_entries = std.AutoHashMap(GlyphMetricsKey, ?VerticalGlyphMetrics).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphMetricsCache) void {
        self.vertical_entries.deinit();
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GlyphMetricsCache) void {
        self.entries.clearRetainingCapacity();
        self.vertical_entries.clearRetainingCapacity();
        self.direct_entries = [_]HorizontalDirectEntry{.{}} ** direct_capacity;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn horizontalMetrics(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId) !GlyphMetrics {
        return try self.horizontalMetricsAtCoords(font, glyph_id, &.{});
    }

    pub fn horizontalMetricsAtCoords(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId, normalized_variation_coords: []const f32) !GlyphMetrics {
        const key = glyphMetricsKey(font, glyph_id, normalized_variation_coords);
        const direct = &self.direct_entries[directMetricsIndex(key)];
        if (direct.valid and glyphMetricsKeysEqual(direct.key, key)) {
            self.hits += 1;
            return direct.metrics;
        }
        if (self.entries.get(key)) |metrics| {
            direct.* = .{ .key = key, .metrics = metrics, .valid = true };
            self.hits += 1;
            return metrics;
        }
        self.misses += 1;
        const raw = if (normalized_variation_coords.len == 0)
            try font.horizontalMetrics(glyph_id)
        else
            try font.horizontalMetricsAtCoords(glyph_id, normalized_variation_coords);
        const metrics = GlyphMetrics{
            .advance_width = raw.advance_width,
            .left_side_bearing = raw.left_side_bearing,
        };
        try self.entries.put(key, metrics);
        direct.* = .{ .key = key, .metrics = metrics, .valid = true };
        return metrics;
    }

    pub fn verticalMetrics(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId) !?VerticalGlyphMetrics {
        return try self.verticalMetricsAtCoords(font, glyph_id, &.{});
    }

    pub fn verticalMetricsAtCoords(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId, normalized_variation_coords: []const f32) !?VerticalGlyphMetrics {
        const key = glyphMetricsKey(font, glyph_id, normalized_variation_coords);
        if (self.vertical_entries.get(key)) |metrics| {
            self.hits += 1;
            return metrics;
        }
        self.misses += 1;
        const raw = if (normalized_variation_coords.len == 0)
            try font.verticalMetrics(glyph_id)
        else
            try font.verticalMetricsAtCoords(glyph_id, normalized_variation_coords);
        const metrics: ?VerticalGlyphMetrics = if (raw) |value| .{
            .advance_height = value.advance_height,
            .top_side_bearing = value.top_side_bearing,
        } else null;
        try self.vertical_entries.put(key, metrics);
        return metrics;
    }
};

fn directMetricsIndex(key: GlyphMetricsKey) usize {
    // Glyph id is the strongest locality signal: shaping repeatedly requests
    // the same small alphabet from one face and variation instance. Mix the
    // complete identity so fallback fonts and variable instances can coexist;
    // exact key comparison still resolves all collisions before returning.
    var mixed: u64 = @intCast(key.font_addr);
    mixed = (mixed >> 4) ^ key.variation_hash;
    mixed ^= @as(u64, key.glyph_id) *% 0x9e37_79b9_7f4a_7c15;
    mixed ^= mixed >> 32;
    return @intCast(mixed & (GlyphMetricsCache.direct_capacity - 1));
}

fn glyphMetricsKeysEqual(a: GlyphMetricsKey, b: GlyphMetricsKey) bool {
    return a.font_addr == b.font_addr and
        a.glyph_id == b.glyph_id and
        a.variation_hash == b.variation_hash;
}

test "glyph metrics direct cache is exact and cleared with the backing map" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var cache = GlyphMetricsCache.init(std.testing.allocator);
    defer cache.deinit();

    const expected = try cache.horizontalMetrics(&font, 1);
    const key = glyphMetricsKey(&font, 1, &.{});
    const slot = directMetricsIndex(key);
    try std.testing.expect(cache.direct_entries[slot].valid);
    try std.testing.expect(glyphMetricsKeysEqual(key, cache.direct_entries[slot].key));

    // Remove the authoritative map entry so this repeat can succeed only via
    // the exact direct slot, not by falling through to the old cache path.
    try std.testing.expect(cache.entries.remove(key));
    const from_direct = try cache.horizontalMetrics(&font, 1);
    try std.testing.expectEqual(expected, from_direct);
    try std.testing.expectEqual(@as(usize, 1), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    // Glyph ids separated by the power-of-two slot count collide. A foreign
    // complete key must miss the slot and fall back to the authoritative map.
    try cache.entries.put(key, expected);
    cache.direct_entries[slot].key.glyph_id +%= GlyphMetricsCache.direct_capacity;
    const after_collision = try cache.horizontalMetrics(&font, 1);
    try std.testing.expectEqual(expected, after_collision);
    try std.testing.expect(glyphMetricsKeysEqual(key, cache.direct_entries[slot].key));
    try std.testing.expectEqual(@as(usize, 2), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    cache.clear();
    try std.testing.expect(!cache.direct_entries[slot].valid);
    try std.testing.expectEqual(@as(usize, 0), cache.hits);
    try std.testing.expectEqual(@as(usize, 0), cache.misses);
}

const GlyphIndexKey = struct {
    font_addr: usize,
    codepoint: u21,
};

pub const GlyphIndexCache = struct {
    const ascii_capacity = 128;
    const direct_capacity = 512;
    const AsciiEntry = struct {
        font_addr: usize = 0,
        glyph_id: GlyphId = 0,
        valid: bool = false,
    };
    const DirectEntry = struct {
        font_addr: usize = 0,
        codepoint: u21 = 0,
        glyph_id: GlyphId = 0,
        valid: bool = false,
    };

    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphIndexKey, GlyphId),
    ascii_entries: [ascii_capacity]AsciiEntry = [_]AsciiEntry{.{}} ** ascii_capacity,
    direct_entries: [direct_capacity]DirectEntry = [_]DirectEntry{.{}} ** direct_capacity,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GlyphIndexCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(GlyphIndexKey, GlyphId).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphIndexCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GlyphIndexCache) void {
        self.entries.clearRetainingCapacity();
        self.ascii_entries = [_]AsciiEntry{.{}} ** ascii_capacity;
        self.direct_entries = [_]DirectEntry{.{}} ** direct_capacity;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn glyphIndex(self: *GlyphIndexCache, font: *const Font, codepoint: u21) !GlyphId {
        const font_addr = @intFromPtr(font);
        if (codepoint < ascii_capacity) {
            const ascii = &self.ascii_entries[@intCast(codepoint)];
            if (ascii.valid and ascii.font_addr == font_addr) {
                self.hits += 1;
                return ascii.glyph_id;
            }
        }

        const key = GlyphIndexKey{ .font_addr = font_addr, .codepoint = codepoint };
        const direct = &self.direct_entries[directGlyphIndex(key)];
        if (direct.valid and direct.font_addr == font_addr and direct.codepoint == codepoint) {
            self.hits += 1;
            return direct.glyph_id;
        }
        if (self.entries.get(key)) |glyph_id| {
            direct.* = .{
                .font_addr = font_addr,
                .codepoint = codepoint,
                .glyph_id = glyph_id,
                .valid = true,
            };
            self.hits += 1;
            if (codepoint < ascii_capacity) {
                self.ascii_entries[@intCast(codepoint)] = .{
                    .font_addr = font_addr,
                    .glyph_id = glyph_id,
                    .valid = true,
                };
            }
            return glyph_id;
        }
        self.misses += 1;
        const glyph_id = try font.glyphIndex(codepoint);
        try self.entries.put(key, glyph_id);
        direct.* = .{
            .font_addr = font_addr,
            .codepoint = codepoint,
            .glyph_id = glyph_id,
            .valid = true,
        };
        if (codepoint < ascii_capacity) {
            self.ascii_entries[@intCast(codepoint)] = .{
                .font_addr = font_addr,
                .glyph_id = glyph_id,
                .valid = true,
            };
        }
        return glyph_id;
    }
};

fn directGlyphIndex(key: GlyphIndexKey) usize {
    // Non-ASCII shaping repeatedly maps a small script alphabet. Mix the full
    // font/codepoint identity with integer operations only; exact key checks
    // make direct-map collisions fall through to the authoritative hash map.
    var mixed: u64 = @intCast(key.font_addr >> 4);
    mixed ^= @as(u64, key.codepoint) *% 0x9e37_79b9_7f4a_7c15;
    mixed ^= mixed >> 32;
    return @intCast(mixed & (GlyphIndexCache.direct_capacity - 1));
}

test "glyph index direct cache is exact for non-ASCII mappings" {
    const test_font = @import("test_font.zig");
    const bytes = try test_font.buildSingleCodepointTtf(std.testing.allocator, 0x0915);
    defer std.testing.allocator.free(bytes);

    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var cache = GlyphIndexCache.init(std.testing.allocator);
    defer cache.deinit();

    const codepoint: u21 = 0x0915;
    const expected = try cache.glyphIndex(&font, codepoint);
    const key = GlyphIndexKey{
        .font_addr = @intFromPtr(&font),
        .codepoint = codepoint,
    };
    const slot = directGlyphIndex(key);
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(GlyphIndexCache.DirectEntry));
    try std.testing.expect(cache.direct_entries[slot].valid);
    try std.testing.expectEqual(key.font_addr, cache.direct_entries[slot].font_addr);
    try std.testing.expectEqual(key.codepoint, cache.direct_entries[slot].codepoint);

    // Remove the backing entry: an exact repeat can now succeed only from the
    // direct slot, not through AutoHashMap's Wyhash path.
    try std.testing.expect(cache.entries.remove(key));
    try std.testing.expectEqual(expected, try cache.glyphIndex(&font, codepoint));
    try std.testing.expectEqual(@as(usize, 1), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    // Codepoints separated by the power-of-two slot count collide in the low
    // index bits. A mismatching complete key must fall through and refill from
    // the authoritative map rather than returning the foreign glyph.
    try cache.entries.put(key, expected);
    cache.direct_entries[slot].codepoint +%= GlyphIndexCache.direct_capacity;
    cache.direct_entries[slot].glyph_id = 0;
    try std.testing.expectEqual(expected, try cache.glyphIndex(&font, codepoint));
    try std.testing.expectEqual(key.font_addr, cache.direct_entries[slot].font_addr);
    try std.testing.expectEqual(key.codepoint, cache.direct_entries[slot].codepoint);
    try std.testing.expectEqual(@as(usize, 2), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    cache.clear();
    try std.testing.expect(!cache.direct_entries[slot].valid);
}

fn glyphMetricsKey(font: *const Font, glyph_id: GlyphId, normalized_variation_coords: []const f32) GlyphMetricsKey {
    return .{
        .font_addr = @intFromPtr(font),
        .glyph_id = glyph_id,
        .variation_hash = variationCoordsHash(normalized_variation_coords),
    };
}

fn variationCoordsHash(coords: []const f32) u64 {
    if (coords.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&coords.len));
    for (coords) |coord| {
        const bits: u32 = @bitCast(coord);
        hasher.update(std.mem.asBytes(&bits));
    }
    return hasher.final();
}
