const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const Setting = struct {
    setting: u16,
    name_id: u16,
};

pub const Feature = struct {
    feature: u16,
    flags: u16,
    name_id: u16,
    settings: []Setting,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    const h = try header(data, offset, length);
    var previous_feature: ?u16 = null;
    for (0..h.count) |index| {
        const feature = try featureHeader(data, offset, length, index);
        if (previous_feature) |previous| {
            if (feature.feature <= previous) return error.BadSfnt;
        }
        previous_feature = feature.feature;
        try validateSettings(data, offset, length, feature.settings_offset, feature.setting_count);
    }
}

pub fn features(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error![]Feature {
    const h = try header(data, offset, length);
    try validate(data, offset, length);
    const out = try allocator.alloc(Feature, h.count);
    errdefer {
        for (out) |feature| allocator.free(feature.settings);
        allocator.free(out);
    }
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |feature| allocator.free(feature.settings);
    for (out, 0..) |*feature, index| {
        const fh = try featureHeader(data, offset, length, index);
        const settings = try allocator.alloc(Setting, fh.setting_count);
        errdefer allocator.free(settings);
        for (settings, 0..) |*setting, setting_index| {
            setting.* = try settingAt(data, offset + fh.settings_offset, setting_index);
        }
        feature.* = .{ .feature = fh.feature, .flags = fh.flags, .name_id = fh.name_id, .settings = settings };
        initialized += 1;
    }
    return out;
}

pub fn free(allocator: std.mem.Allocator, features_slice: []Feature) void {
    for (features_slice) |feature| allocator.free(feature.settings);
    allocator.free(features_slice);
}

const Header = struct { count: usize };
const FeatureHeader = struct {
    feature: u16,
    setting_count: usize,
    settings_offset: usize,
    flags: u16,
    name_id: u16,
};

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 12) return error.BadSfnt;
    if (try bin.readU32At(data, offset) != 0x00010000) return error.BadSfnt;
    const count: usize = @intCast(try bin.readU16At(data, offset + 4));
    if (try bin.readU16At(data, offset + 6) != 0) return error.BadSfnt;
    if (try bin.readU32At(data, offset + 8) != 0) return error.BadSfnt;
    if (count > (length - 12) / 12) return error.BadSfnt;
    return .{ .count = count };
}

fn featureHeader(data: []const u8, offset: usize, length: usize, index: usize) Error!FeatureHeader {
    const record = offset + 12 + index * 12;
    const feature = try bin.readU16At(data, record);
    const setting_count: usize = @intCast(try bin.readU16At(data, record + 2));
    const settings_offset: usize = @intCast(try bin.readU32At(data, record + 4));
    if (settings_offset < 12 or settings_offset > length) return error.BadSfnt;
    if (@as(u64, setting_count) * 4 > @as(u64, length - settings_offset)) return error.BadSfnt;
    return .{
        .feature = feature,
        .setting_count = setting_count,
        .settings_offset = settings_offset,
        .flags = try bin.readU16At(data, record + 8),
        .name_id = try bin.readU16At(data, record + 10),
    };
}

fn validateSettings(data: []const u8, table_offset: usize, table_length: usize, settings_offset: usize, setting_count: usize) Error!void {
    if (settings_offset > table_length or @as(u64, setting_count) * 4 > @as(u64, table_length - settings_offset)) return error.BadSfnt;
    var previous_setting: ?u16 = null;
    for (0..setting_count) |index| {
        const setting = try settingAt(data, table_offset + settings_offset, index);
        if (previous_setting) |previous| {
            if (setting.setting <= previous) return error.BadSfnt;
        }
        previous_setting = setting.setting;
    }
}

fn settingAt(data: []const u8, settings_start: usize, index: usize) Error!Setting {
    const record = settings_start + index * 4;
    return .{
        .setting = try bin.readU16At(data, record),
        .name_id = try bin.readU16At(data, record + 2),
    };
}
