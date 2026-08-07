const gsub = @import("gsub.zig");
const unicode = @import("unicode.zig");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .dupl;
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
