//! Common GSUB feature override and application planning.

const font_shaping = @import("../../../font.zig").shaping;
const Font = @import("../../../font.zig").Font;
const gsub = @import("../../../gsub.zig");
const unicode = @import("../../../unicode.zig");

pub fn enabled(
    feature: u32,
    overrides: []const unicode.FeatureOverride,
    default_enabled: bool,
) bool {
    for (overrides) |override| {
        if (override.tag == feature) return override.enabled;
    }
    return default_enabled;
}

pub fn randomApplication(
    overrides: []const unicode.FeatureOverride,
) ?gsub.FeatureApplication {
    for (overrides) |override| {
        if (override.tag != unicode.tag("rand")) continue;
        if (!override.enabled) return null;
        return .{
            .tag = override.tag,
            .value = override.effectiveValue(),
        };
    }
    return .{
        .tag = unicode.tag("rand"),
        .value = gsub.random_feature_value,
    };
}

pub fn withDefaultDisabledCalt(
    out: []unicode.FeatureOverride,
    overrides: []const unicode.FeatureOverride,
) ?[]const unicode.FeatureOverride {
    if (out.len < overrides.len + 1) return null;
    var count: usize = 0;
    for (overrides) |override| {
        if (override.tag == unicode.tag("calt")) return overrides;
        out[count] = override;
        count += 1;
    }
    out[count] = .{ .tag = unicode.tag("calt"), .enabled = false };
    return out[0 .. count + 1];
}

pub fn appendExplicitOptional(
    out: []gsub.FeatureApplication,
    overrides: []const unicode.FeatureOverride,
) usize {
    var count: usize = 0;
    for (overrides) |override| {
        if (!override.enabled or !optionalShouldRun(override.tag)) continue;
        if (count >= out.len) break;
        out[count] = .{
            .tag = override.tag,
            .auto_zwj = false,
            .value = override.value,
        };
        count += 1;
    }
    return count;
}

pub fn needsValueAwareSelection(
    font: *const Font,
    overrides: []const unicode.FeatureOverride,
    lookup_accelerators: ?[]const gsub.LookupAccelerator,
    table_proved: bool,
) bool {
    var rand_disabled = false;
    for (overrides) |feature| {
        if (feature.effectiveValue() > 1) return true;
        if (feature.tag == unicode.tag("rand") and !feature.enabled) {
            rand_disabled = true;
        }
    }
    if (rand_disabled) return false;
    if (table_proved) {
        if (lookup_accelerators) |accelerators| {
            if (font_shaping.hasGsubRandomFeatureWithAcceleratorsForShaping(
                font,
                accelerators,
            )) |has_random| {
                return has_random;
            }
        }
    }
    return font_shaping.hasGsubFeatureForShaping(font, unicode.tag("rand")) catch false;
}

pub fn scriptPositionApplication(
    position: anytype,
) ?gsub.FeatureApplication {
    return switch (position) {
        .normal => null,
        .superscript => .{ .tag = unicode.tag("sups") },
        .subscript => .{ .tag = unicode.tag("subs") },
    };
}

fn optionalShouldRun(feature: u32) bool {
    return feature != unicode.tag("rand") and
        feature != unicode.tag("stch") and
        feature != unicode.tag("ccmp") and
        feature != unicode.tag("locl") and
        feature != unicode.tag("isol") and
        feature != unicode.tag("fina") and
        feature != unicode.tag("fin2") and
        feature != unicode.tag("fin3") and
        feature != unicode.tag("medi") and
        feature != unicode.tag("med2") and
        feature != unicode.tag("init") and
        feature != unicode.tag("rlig") and
        feature != unicode.tag("calt") and
        feature != unicode.tag("rclt") and
        feature != unicode.tag("liga") and
        feature != unicode.tag("clig") and
        feature != unicode.tag("sups") and
        feature != unicode.tag("subs");
}
