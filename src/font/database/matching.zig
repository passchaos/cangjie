//! CSS-like family, weight, stretch, and style matching policy.

const std = @import("std");
const types = @import("types.zig");

pub fn familyMatches(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

pub fn matchScore(face: types.FaceInfo, query: types.Query) u32 {
    var score: u32 = 0;
    score += numericDistance(face.weight, query.weight);
    score += numericDistance(face.stretch, query.stretch) * 2;
    if (face.style != query.style) score += 1000;
    return score;
}

fn numericDistance(a: u16, b: u16) u32 {
    return if (a > b) a - b else b - a;
}

pub fn widthClassToStretch(width_class: u16) u16 {
    return switch (width_class) {
        1 => 50,
        2 => 62,
        3 => 75,
        4 => 87,
        5 => 100,
        6 => 112,
        7 => 125,
        8 => 150,
        9 => 200,
        else => 100,
    };
}

pub fn inferWeight(subfamily: []const u8) u16 {
    if (containsIgnoreCase(subfamily, "Thin")) return 100;
    if (containsIgnoreCase(subfamily, "ExtraLight") or containsIgnoreCase(subfamily, "UltraLight")) return 200;
    if (containsIgnoreCase(subfamily, "Light")) return 300;
    if (containsIgnoreCase(subfamily, "Medium")) return 500;
    if (containsIgnoreCase(subfamily, "SemiBold") or containsIgnoreCase(subfamily, "DemiBold")) return 600;
    if (containsIgnoreCase(subfamily, "Bold")) return 700;
    if (containsIgnoreCase(subfamily, "ExtraBold") or containsIgnoreCase(subfamily, "UltraBold")) return 800;
    if (containsIgnoreCase(subfamily, "Black") or containsIgnoreCase(subfamily, "Heavy")) return 900;
    return 400;
}

pub fn inferStyle(subfamily: []const u8) types.Style {
    if (containsIgnoreCase(subfamily, "Italic")) return .italic;
    if (containsIgnoreCase(subfamily, "Oblique")) return .oblique;
    return .normal;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}
