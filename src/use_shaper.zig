const gsub = @import("gsub.zig");
const unicode = @import("unicode.zig");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .dupl;
}

pub const Category = enum(u8) {
    other = 0,
    base = 1,
    cg_joiner = 6,
    zwnj = 14,
    word_joiner = 16,
    base_other = 5,
};

pub fn categoryForCodepoint(codepoint: u21) Category {
    return switch (codepoint) {
        0x034f => .cg_joiner,
        0x200c => .zwnj,
        0x2060 => .word_joiner,
        0x1bc00...0x1bc6a => .base,
        0x1bc70...0x1bc7c => .base_other,
        else => .other,
    };
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
