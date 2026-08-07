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
    .{ .tag = unicode.tag("locl"), .match_source_syllable = true },
    .{ .tag = unicode.tag("ccmp"), .match_source_syllable = true },
    .{ .tag = unicode.tag("nukt"), .match_source_syllable = true },
    .{ .tag = unicode.tag("akhn"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("rphf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pref"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("rkrf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("abvf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("blwf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("half"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pstf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("vatu"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("cjct"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("isol"), .source_scoped = true },
    .{ .tag = unicode.tag("init"), .source_scoped = true },
    .{ .tag = unicode.tag("medi"), .source_scoped = true },
    .{ .tag = unicode.tag("fina"), .source_scoped = true },
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("haln"), .auto_zwj = false },
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
    .{ .tag = unicode.tag("abvm") },
    .{ .tag = unicode.tag("blwm") },
    .{ .tag = unicode.tag("rlig") },
    .{ .tag = unicode.tag("calt") },
    .{ .tag = unicode.tag("clig") },
    .{ .tag = unicode.tag("dist") },
    .{ .tag = unicode.tag("liga") },
    .{ .tag = unicode.tag("rclt") },
};

const default_preprocessing_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("locl"), .match_source_syllable = true },
    .{ .tag = unicode.tag("ccmp"), .match_source_syllable = true },
    .{ .tag = unicode.tag("nukt"), .match_source_syllable = true },
    .{ .tag = unicode.tag("akhn"), .match_source_syllable = true, .auto_zwj = false },
};

const rphf_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rphf"), .source_scoped = true, .match_source_syllable = true, .auto_zwj = false },
};

const pref_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pref"), .match_source_syllable = true, .auto_zwj = false },
};

const basic_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rkrf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("abvf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("blwf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("half"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("pstf"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("vatu"), .match_source_syllable = true, .auto_zwj = false },
    .{ .tag = unicode.tag("cjct"), .match_source_syllable = true, .auto_zwj = false },
};

const topographical_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("isol"), .source_scoped = true },
    .{ .tag = unicode.tag("init"), .source_scoped = true },
    .{ .tag = unicode.tag("medi"), .source_scoped = true },
    .{ .tag = unicode.tag("fina"), .source_scoped = true },
};

const final_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("abvs"), .auto_zwj = false },
    .{ .tag = unicode.tag("blws"), .auto_zwj = false },
    .{ .tag = unicode.tag("haln"), .auto_zwj = false },
    .{ .tag = unicode.tag("pres"), .auto_zwj = false },
    .{ .tag = unicode.tag("psts"), .auto_zwj = false },
};

const typographic_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("abvm") },
    .{ .tag = unicode.tag("blwm") },
    .{ .tag = unicode.tag("rlig") },
    .{ .tag = unicode.tag("calt") },
    .{ .tag = unicode.tag("clig") },
    .{ .tag = unicode.tag("dist") },
    .{ .tag = unicode.tag("liga") },
    .{ .tag = unicode.tag("rclt") },
};

pub fn featureApplications() []const gsub.FeatureApplication {
    return &feature_applications;
}

pub fn defaultPreprocessingFeatureApplications() []const gsub.FeatureApplication {
    return &default_preprocessing_applications;
}

pub fn rphfFeatureApplications() []const gsub.FeatureApplication {
    return &rphf_applications;
}

pub fn prefFeatureApplications() []const gsub.FeatureApplication {
    return &pref_applications;
}

pub fn basicFeatureApplications() []const gsub.FeatureApplication {
    return &basic_applications;
}

pub fn topographicalFeatureApplications() []const gsub.FeatureApplication {
    return &topographical_applications;
}

pub fn finalFeatureApplications() []const gsub.FeatureApplication {
    return &final_applications;
}

pub fn typographicFeatureApplications() []const gsub.FeatureApplication {
    return &typographic_applications;
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
