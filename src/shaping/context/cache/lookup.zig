const std = @import("std");
const font_shaping = @import("../../../font.zig").shaping;

const font_mod = @import("../../../font.zig");
const Font = font_mod.Font;
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;
const gpos = @import("../../../gpos.zig");
const gsub = @import("../../../gsub.zig");
const unicode = @import("../../../unicode.zig");

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
    run_may_have_mark_attachments: ?bool,
};

pub const LayoutScriptSelections = struct {
    gsub: font_mod.LayoutScriptSelection,
    gpos: font_mod.LayoutScriptSelection,
};

pub const LookupSelectionCache = struct {
    const Entry = struct {
        key: LookupSelectionKey,
        features: []unicode.FeatureOverride,
        lookups: []u16,
    };
    const GsubAcceleratorEntry = struct {
        font_addr: usize,
        accelerators: []gsub.acceleration.Lookup,
    };
    const GposAcceleratorEntry = struct {
        font_addr: usize,
        accelerators: []gpos.LookupAccelerator,
    };
    const ScriptSelectionEntry = struct {
        font_addr: usize,
        script: unicode.Script,
        explicit_tag: ?unicode.OpenTypeScriptTag,
        gsub: font_mod.LayoutScriptSelection,
        gpos: font_mod.LayoutScriptSelection,
    };
    const FeaturePlanEntry = struct {
        key: LookupSelectionKey,
        features: []unicode.FeatureOverride,
        applications: []gsub.feature.Application,
        plan: gsub.feature.LookupPlan,
    };
    const MergedFeaturePlanEntry = struct {
        key: LookupSelectionKey,
        features: []unicode.FeatureOverride,
        applications: []gsub.feature.Application,
        plan: gsub.feature.MergedLookupPlan,
    };

    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    gsub_accelerator_entries: std.ArrayList(GsubAcceleratorEntry) = .empty,
    gpos_accelerator_entries: std.ArrayList(GposAcceleratorEntry) = .empty,
    script_selection_entries: std.ArrayList(ScriptSelectionEntry) = .empty,
    gsub_feature_plan_entries: std.ArrayList(FeaturePlanEntry) = .empty,
    gsub_merged_feature_plan_entries: std.ArrayList(MergedFeaturePlanEntry) = .empty,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) LookupSelectionCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *LookupSelectionCache) void {
        self.clear();
        self.gsub_merged_feature_plan_entries.deinit(self.allocator);
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
            gsub.acceleration.deinit(self.allocator, entry.accelerators);
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
        for (self.gsub_merged_feature_plan_entries.items) |*entry| {
            self.allocator.free(entry.features);
            self.allocator.free(entry.applications);
            entry.plan.deinit(self.allocator);
        }
        self.gsub_merged_feature_plan_entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn gsubLookups(self: *LookupSelectionCache, font: *const Font, options: gsub.runtime.Options, gdef_metadata: GdefLookupMetadata) ![]const u16 {
        const key = lookupSelectionKey(font, .gsub, options.script_tag, options.language_tag, options.features, options.vertical, null);
        if (self.lookup(key, options.features)) |lookups| return lookups;

        self.misses += 1;
        const lookups = try font_shaping.selectGsubLookupsForShaping(font, self.allocator, options, gdef_metadata);
        errdefer self.allocator.free(lookups);
        const features = try self.allocator.dupe(unicode.FeatureOverride, options.features);
        errdefer self.allocator.free(features);
        try self.entries.append(self.allocator, .{ .key = key, .features = features, .lookups = lookups });
        return self.entries.items[self.entries.items.len - 1].lookups;
    }

    pub fn gsubLookupAccelerators(self: *LookupSelectionCache, font: *const Font) ![]const gsub.acceleration.Lookup {
        const font_addr = @intFromPtr(font);
        for (self.gsub_accelerator_entries.items) |entry| {
            if (entry.font_addr != font_addr) continue;
            self.hits += 1;
            return entry.accelerators;
        }

        self.misses += 1;
        const accelerators = try font_shaping.gsubLookupAcceleratorsForShaping(font, self.allocator);
        // Lookup accelerators own nested feature indexes and substitution
        // sidecars. If retaining the top-level cache entry fails, freeing only
        // its outer slice leaks those nested allocations under allocator
        // failure injection.
        errdefer gsub.acceleration.deinit(self.allocator, accelerators);
        try self.gsub_accelerator_entries.append(self.allocator, .{
            .font_addr = font_addr,
            .accelerators = accelerators,
        });
        return self.gsub_accelerator_entries.items[self.gsub_accelerator_entries.items.len - 1].accelerators;
    }

    pub fn gsubFeatureLookupPlan(self: *LookupSelectionCache, font: *const Font, applications: []const gsub.feature.Application, options: gsub.runtime.Options, gdef_metadata: GdefLookupMetadata) !gsub.feature.LookupPlan {
        const key = lookupSelectionKey(font, .gsub, options.script_tag, options.language_tag, options.features, options.vertical, null);
        for (self.gsub_feature_plan_entries.items) |entry| {
            if (!lookupSelectionKeysEqual(entry.key, key)) continue;
            if (!featureOverridesEqual(entry.features, options.features)) continue;
            if (!featureApplicationsEqual(entry.applications, applications)) continue;
            self.hits += 1;
            return entry.plan;
        }

        self.misses += 1;
        const plan = try font_shaping.gsubFeatureLookupPlanForShaping(font, self.allocator, applications, options, gdef_metadata);
        errdefer {
            var mutable_plan = plan;
            mutable_plan.deinit(self.allocator);
        }
        const features = try self.allocator.dupe(unicode.FeatureOverride, options.features);
        errdefer self.allocator.free(features);
        const applications_copy = try self.allocator.dupe(gsub.feature.Application, applications);
        errdefer self.allocator.free(applications_copy);
        try self.gsub_feature_plan_entries.append(self.allocator, .{
            .key = key,
            .features = features,
            .applications = applications_copy,
            .plan = plan,
        });
        return self.gsub_feature_plan_entries.items[self.gsub_feature_plan_entries.items.len - 1].plan;
    }

    /// Resolve several script stages in one pass over the feature-plan cache.
    ///
    /// Multi-stage shapers revisit the same small cache for every source run.
    /// Matching all requested application sequences together preserves the
    /// exact keys while avoiding one full cache walk per stage.
    pub fn gsubFeatureLookupPlans(
        self: *LookupSelectionCache,
        font: *const Font,
        application_sets: []const []const gsub.feature.Application,
        options: gsub.runtime.Options,
        gdef_metadata: GdefLookupMetadata,
        output: []gsub.feature.LookupPlan,
    ) !void {
        if (output.len != application_sets.len) {
            return error.InvalidShapingInput;
        }
        const key = lookupSelectionKey(
            font,
            .gsub,
            options.script_tag,
            options.language_tag,
            options.features,
            options.vertical,
            null,
        );
        var found: [16]bool = [_]bool{false} ** 16;
        if (application_sets.len > found.len) return error.InvalidShapingInput;
        var remaining = application_sets.len;
        for (self.gsub_feature_plan_entries.items) |entry| {
            if (!lookupSelectionKeysEqual(entry.key, key)) continue;
            if (!featureOverridesEqual(entry.features, options.features)) continue;
            for (application_sets, 0..) |applications, index| {
                if (found[index] or
                    !featureApplicationsEqual(entry.applications, applications))
                {
                    continue;
                }
                output[index] = entry.plan;
                found[index] = true;
                remaining -= 1;
                self.hits += 1;
                break;
            }
            if (remaining == 0) return;
        }
        for (application_sets, 0..) |applications, index| {
            if (found[index]) continue;
            output[index] = try self.gsubFeatureLookupPlan(
                font,
                applications,
                options,
                gdef_metadata,
            );
        }
    }

    pub fn gsubMergedFeatureLookupPlan(self: *LookupSelectionCache, font: *const Font, applications: []const gsub.feature.Application, options: gsub.runtime.Options, gdef_metadata: GdefLookupMetadata) !gsub.feature.MergedLookupPlan {
        const key = lookupSelectionKey(font, .gsub, options.script_tag, options.language_tag, options.features, options.vertical, null);
        for (self.gsub_merged_feature_plan_entries.items) |entry| {
            if (!lookupSelectionKeysEqual(entry.key, key)) continue;
            if (!featureOverridesEqual(entry.features, options.features)) continue;
            if (!featureApplicationsEqual(entry.applications, applications)) continue;
            self.hits += 1;
            return entry.plan;
        }

        self.misses += 1;
        const plan = try font_shaping.gsubMergedFeatureLookupPlanForShaping(font, self.allocator, applications, options, gdef_metadata);
        errdefer {
            var mutable_plan = plan;
            mutable_plan.deinit(self.allocator);
        }
        const features = try self.allocator.dupe(unicode.FeatureOverride, options.features);
        errdefer self.allocator.free(features);
        const applications_copy = try self.allocator.dupe(gsub.feature.Application, applications);
        errdefer self.allocator.free(applications_copy);
        try self.gsub_merged_feature_plan_entries.append(self.allocator, .{
            .key = key,
            .features = features,
            .applications = applications_copy,
            .plan = plan,
        });
        return self.gsub_merged_feature_plan_entries.items[self.gsub_merged_feature_plan_entries.items.len - 1].plan;
    }

    pub fn gposLookupAccelerators(self: *LookupSelectionCache, font: *const Font) ![]const gpos.LookupAccelerator {
        const font_addr = @intFromPtr(font);
        for (self.gpos_accelerator_entries.items) |entry| {
            if (entry.font_addr != font_addr) continue;
            self.hits += 1;
            return entry.accelerators;
        }

        self.misses += 1;
        const accelerators = try font_shaping.gposLookupAcceleratorsForShaping(font, self.allocator);
        errdefer self.allocator.free(accelerators);
        try self.gpos_accelerator_entries.append(self.allocator, .{
            .font_addr = font_addr,
            .accelerators = accelerators,
        });
        return self.gpos_accelerator_entries.items[self.gpos_accelerator_entries.items.len - 1].accelerators;
    }

    pub fn gposLookups(self: *LookupSelectionCache, font: *const Font, options: gpos.LookupOptions, gdef_metadata: GdefLookupMetadata) ![]const u16 {
        const key = lookupSelectionKey(font, .gpos, options.script_tag, options.language_tag, options.features, false, options.run_may_have_mark_attachments);
        if (self.lookup(key, options.features)) |lookups| return lookups;

        self.misses += 1;
        const lookups = try font_shaping.selectGposLookupsForShaping(font, self.allocator, options, gdef_metadata);
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
            .gsub = try font_shaping.selectGsubScriptForShaping(font, script, explicit_tag),
            .gpos = try font_shaping.selectGposScriptForShaping(font, script, explicit_tag),
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

fn lookupSelectionKey(font: *const Font, table: LookupTableKind, script_tag: unicode.OpenTypeScriptTag, language_tag: unicode.OpenTypeLanguageTag, features: []const unicode.FeatureOverride, vertical: bool, run_may_have_mark_attachments: ?bool) LookupSelectionKey {
    return .{
        .font_addr = @intFromPtr(font),
        .table = table,
        .script_tag = script_tag,
        .language_tag = language_tag,
        .feature_hash = featureOverridesHash(features),
        .vertical = vertical,
        .run_may_have_mark_attachments = run_may_have_mark_attachments,
    };
}

fn lookupSelectionKeysEqual(a: LookupSelectionKey, b: LookupSelectionKey) bool {
    return a.font_addr == b.font_addr and
        a.table == b.table and
        a.script_tag == b.script_tag and
        a.language_tag == b.language_tag and
        a.feature_hash == b.feature_hash and
        a.vertical == b.vertical and
        a.run_may_have_mark_attachments == b.run_may_have_mark_attachments;
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
        if (a_feature.tag != b_feature.tag or
            a_feature.effectiveValue() != b_feature.effectiveValue()) return false;
    }
    return true;
}

fn featureApplicationsEqual(a: []const gsub.feature.Application, b: []const gsub.feature.Application) bool {
    if (a.len != b.len) return false;
    for (a, b) |a_application, b_application| {
        if (a_application.tag != b_application.tag or
            a_application.source_scoped != b_application.source_scoped or
            a_application.auto_zwnj != b_application.auto_zwnj or
            a_application.auto_zwj != b_application.auto_zwj or
            a_application.match_source_syllable != b_application.match_source_syllable or
            a_application.value != b_application.value) return false;
    }
    return true;
}

test "feature plan cache distinguishes syllable-scoped applications" {
    const global = [_]gsub.feature.Application{
        .{ .tag = unicode.tag("rphf"), .source_scoped = true },
    };
    const syllable_scoped = [_]gsub.feature.Application{
        .{
            .tag = unicode.tag("rphf"),
            .source_scoped = true,
            .match_source_syllable = true,
        },
    };

    try std.testing.expect(featureApplicationsEqual(&global, &global));
    try std.testing.expect(!featureApplicationsEqual(&global, &syllable_scoped));
}

test "feature plan cache distinguishes feature application values" {
    const salt_one = [_]gsub.feature.Application{
        .{ .tag = unicode.tag("salt"), .value = 1 },
    };
    const salt_two = [_]gsub.feature.Application{
        .{ .tag = unicode.tag("salt"), .value = 2 },
    };
    const override_one = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("salt"), .enabled = true, .value = 1 },
    };
    const override_two = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("salt"), .enabled = true, .value = 2 },
    };

    try std.testing.expect(!featureApplicationsEqual(&salt_one, &salt_two));
    try std.testing.expect(!featureOverridesEqual(&override_one, &override_two));
}
