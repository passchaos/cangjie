//! Construction of the ordinary GSUB feature set for a ranged request.

const std = @import("std");

const ranges_mod = @import("ranges.zig");
const unicode = @import("../../../unicode.zig");

pub fn buildOrdinary(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(unicode.FeatureOverride),
    overrides: []const unicode.FeatureOverride,
    ranges: []const ranges_mod.Range,
) !void {
    out.clearRetainingCapacity();
    try out.ensureUnusedCapacity(allocator, overrides.len + ranges.len);

    for (overrides) |override| {
        if (!ranges_mod.hasTag(ranges, override.tag)) {
            out.appendAssumeCapacity(override);
        }
    }

    // A ranged declaration turns a normally global feature into a source-mask
    // feature. Disable it during the ordinary pass; otherwise a default-on
    // substitution such as `liga` would be irreversible before disabled spans
    // are considered.
    for (ranges) |range| {
        if (ranges_mod.defaultValue(range.tag) == 0 or
            containsTag(out.items, range.tag))
        {
            continue;
        }
        out.appendAssumeCapacity(.{ .tag = range.tag, .enabled = false });
    }
}

fn containsTag(
    overrides: []const unicode.FeatureOverride,
    tag: u32,
) bool {
    for (overrides) |override| {
        if (override.tag == tag) return true;
    }
    return false;
}
