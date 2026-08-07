const gsub = @import("gsub.zig");
const unicode = @import("unicode.zig");
const categories = @import("use/categories.zig");
const syllables = @import("use/syllables.zig");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .dupl;
}

pub const Category = categories.Category;
pub const Syllable = syllables.Syllable;
pub const SyllableType = syllables.SyllableType;

pub fn categoryForCodepoint(codepoint: u21) Category {
    return categories.forCodepoint(codepoint);
}

pub fn findSyllables(allocator: @import("std").mem.Allocator, codepoints: []const u21) ![]Syllable {
    return syllables.find(allocator, codepoints);
}

pub fn markSourceFeatures(
    allocator: @import("std").mem.Allocator,
    source_features: []u32,
    source_syllables: []u8,
    codepoints: []const u21,
) !void {
    try syllables.markSourceFeatures(allocator, source_features, source_syllables, codepoints);
}

const feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("locl") },
    .{ .tag = unicode.tag("ccmp") },
    .{ .tag = unicode.tag("nukt") },
    .{ .tag = unicode.tag("akhn"), .auto_zwj = false },
    .{ .tag = unicode.tag("rphf"), .auto_zwj = false },
    .{ .tag = unicode.tag("pref"), .auto_zwj = false },
    .{ .tag = unicode.tag("rkrf"), .auto_zwj = false },
    .{ .tag = unicode.tag("abvf"), .auto_zwj = false },
    .{ .tag = unicode.tag("blwf"), .auto_zwj = false },
    .{ .tag = unicode.tag("half"), .auto_zwj = false },
    .{ .tag = unicode.tag("pstf"), .auto_zwj = false },
    .{ .tag = unicode.tag("vatu"), .auto_zwj = false },
    .{ .tag = unicode.tag("cjct"), .auto_zwj = false },
    .{ .tag = unicode.tag("isol") },
    .{ .tag = unicode.tag("init") },
    .{ .tag = unicode.tag("medi") },
    .{ .tag = unicode.tag("fina") },
    .{ .tag = unicode.tag("abvm"), .auto_zwj = false },
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blwm"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("dist"), .auto_zwj = false },
    .{ .tag = unicode.tag("haln"), .auto_zwj = false },
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
};

pub fn featureApplications() []const gsub.FeatureApplication {
    return &feature_applications;
}

test "USE category covers Duployan sample codepoints" {
    try @import("std").testing.expectEqual(Category.base, categoryForCodepoint(0x1bc02));
    try @import("std").testing.expectEqual(Category.base, categoryForCodepoint(0x1bc5b));
    try @import("std").testing.expectEqual(Category.cg_joiner, categoryForCodepoint(0x034f));
    try @import("std").testing.expectEqual(Category.zwnj, categoryForCodepoint(0x200c));
    try @import("std").testing.expectEqual(Category.other, categoryForCodepoint(0x002e));
}

test {
    @import("std").testing.refAllDecls(@This());
}
