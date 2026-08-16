//! Whole-GSUB table construction and lightweight topology queries.

const table = @import("root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

pub fn view(
    data: []const u8,
    offset: usize,
    length: usize,
    assume_validated: bool,
) Error!View {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const result = View{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = assume_validated,
    };
    try requireVersion(result);
    return result;
}

pub fn requireVersion(table_view: View) Error!void {
    if (try read(table_view, 0) != 1) return error.UnsupportedGsub;
}

pub fn isEmpty(table_view: View) Error!bool {
    return try read(table_view, 4) == 0 and
        try read(table_view, 6) == 0 and
        try read(table_view, 8) == 0;
}

pub fn hasFeature(table_view: View, feature_tag: u32) Error!bool {
    if (try isEmpty(table_view)) return false;
    const feature_list = try requiredTopLevel(table_view, 6);
    const feature_count = try read(table_view, feature_list);
    for (0..feature_count) |feature_index| {
        if (try readU32(
            table_view,
            feature_list + 2 + feature_index * 6,
        ) == feature_tag) return true;
    }
    return false;
}

pub fn requiredScriptList(table_view: View) Error!usize {
    return requiredTopLevel(table_view, 4);
}

pub fn requiredFeatureList(table_view: View) Error!usize {
    return requiredTopLevel(table_view, 6);
}

pub fn requiredLookupList(table_view: View) Error!usize {
    return requiredTopLevel(table_view, 8);
}

pub fn requiredLookup(
    table_view: View,
    lookup_list: usize,
    relative: u16,
) Error!usize {
    return table.offset.required16(table_view, lookup_list, relative);
}

pub fn read(table_view: View, offset: usize) Error!u16 {
    return table_view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}

pub fn readU32(table_view: View, offset: usize) Error!u32 {
    return table_view.readU32(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}

fn requiredTopLevel(table_view: View, field: usize) Error!usize {
    return table.offset.required16(
        table_view,
        0,
        try read(table_view, field),
    );
}
