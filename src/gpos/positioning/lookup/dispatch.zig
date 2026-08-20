//! GPOS Lookup header and ExtensionPos navigation.

const table = @import("../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub const Header = struct {
    lookup_type: u16,
    lookup_flag: u16,
    subtable_count: u16,
    mark_filtering_set: ?u16,
};

pub const Extension = struct {
    lookup_type: u16,
    payload_offset: usize,
};

pub fn header(view: View, lookup_offset: usize) Error!Header {
    try validateHeader(view, lookup_offset);
    const lookup_flag = try view.readU16(lookup_offset + 2);
    const subtable_count = try view.readU16(lookup_offset + 4);
    return .{
        .lookup_type = try view.readU16(lookup_offset),
        .lookup_flag = lookup_flag,
        .subtable_count = subtable_count,
        .mark_filtering_set = if ((lookup_flag & 0x0010) != 0)
            try view.readU16(
                lookup_offset + 6 + @as(usize, subtable_count) * 2,
            )
        else
            null,
    };
}

pub fn validateHeader(view: View, lookup_offset: usize) Error!void {
    if (lookup_offset > view.length or view.length - lookup_offset < 6) {
        return error.BadGpos;
    }
    const lookup_flag = try readU16ForValidation(view, lookup_offset + 2);
    const subtable_count =
        try readU16ForValidation(view, lookup_offset + 4);
    try validateLookupFlag(lookup_flag);
    const offsets_pos = lookup_offset + 6;
    const offsets_len = @as(usize, subtable_count) * 2;
    try view.ensure(offsets_pos, offsets_len);
    if ((lookup_flag & 0x0010) != 0) {
        try view.ensure(offsets_pos + offsets_len, 2);
    }
}

pub fn validateLookupFlag(lookup_flag: u16) Error!void {
    // Bits 5..7 are currently reserved. The high byte is the independent
    // MarkAttachmentType field and remains valid.
    if ((lookup_flag & 0x00e0) != 0) return error.BadGpos;
}

/// Return a common wrapped lookup type, or null for mixed/malformed wrappers.
pub fn commonExtensionType(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
) Error!?u16 {
    var common: ?u16 = null;
    for (0..subtable_count) |subtable_index| {
        const wrapper = try requiredSubtable(
            view,
            lookup_offset,
            subtable_index,
        );
        if (try view.readU16(wrapper) != 1) return null;
        const wrapped_type = try view.readU16(wrapper + 2);
        if (wrapped_type == 9) return error.UnsupportedGpos;
        if (common) |existing| {
            if (existing != wrapped_type) return null;
        } else {
            common = wrapped_type;
        }
    }
    return common;
}

pub fn extensionPayload(
    view: View,
    wrapper_offset: usize,
    expected_lookup_type: u16,
) Error!usize {
    const parsed = try extension(view, wrapper_offset);
    if (parsed.lookup_type != expected_lookup_type) {
        return error.UnsupportedGpos;
    }
    return parsed.payload_offset;
}

pub fn extension(view: View, wrapper_offset: usize) Error!Extension {
    if (try view.readU16(wrapper_offset) != 1) {
        return error.UnsupportedGpos;
    }
    const wrapped_type = try view.readU16(wrapper_offset + 2);
    if (wrapped_type == 9) return error.UnsupportedGpos;
    return .{
        .lookup_type = wrapped_type,
        .payload_offset = try table.offset.extensionPayload(
            view,
            wrapper_offset,
            try view.readU32(wrapper_offset + 4),
        ),
    };
}

fn extensionForValidation(
    view: View,
    wrapper_offset: usize,
) Error!Extension {
    try view.ensure(wrapper_offset, 8);
    if (try readU16ForValidation(view, wrapper_offset) != 1) {
        return error.UnsupportedGpos;
    }
    const wrapped_type = try readU16ForValidation(view, wrapper_offset + 2);
    if (wrapped_type == 9) return error.UnsupportedGpos;
    return .{
        .lookup_type = wrapped_type,
        .payload_offset = try table.offset.extensionPayload(
            view,
            wrapper_offset,
            try readU32ForValidation(view, wrapper_offset + 4),
        ),
    };
}

pub fn extensionWrapperOffset(
    view: View,
    lookup_offset: usize,
    subtable_index: usize,
) Error!usize {
    return requiredSubtable(
        view,
        lookup_offset,
        subtable_index,
    );
}

pub fn validateExtensionWrappers(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
) Error!void {
    for (0..subtable_count) |subtable_index| {
        const wrapper = try requiredSubtable(
            view,
            lookup_offset,
            subtable_index,
        );
        try validateExtensionWrapper(view, wrapper);
    }
}

pub fn validateExtensionWrapper(view: View, wrapper_offset: usize) Error!void {
    const parsed = try extensionForValidation(view, wrapper_offset);
    try validateSubtableFixedHeader(
        view,
        parsed.payload_offset,
        parsed.lookup_type,
    );
}

pub fn validateSubtableFixedHeader(
    view: View,
    subtable_offset: usize,
    lookup_type: u16,
) Error!void {
    if (subtable_offset > view.length or view.length - subtable_offset < 2) {
        return error.BadGpos;
    }
    const pos_format = try readU16ForValidation(view, subtable_offset);
    const minimum: usize = switch (lookup_type) {
        1 => 6,
        2 => 8,
        3 => 6,
        4, 5, 6 => 12,
        7 => switch (pos_format) {
            1, 3 => 6,
            2 => 8,
            else => return error.UnsupportedGpos,
        },
        8 => switch (pos_format) {
            1 => 6,
            2 => 12,
            3 => 4,
            else => return error.UnsupportedGpos,
        },
        else => return,
    };
    if (view.length - subtable_offset < minimum) return error.BadGpos;
}

fn requiredSubtable(
    view: View,
    lookup_offset: usize,
    subtable_index: usize,
) Error!usize {
    return table.offset.required16(
        view,
        lookup_offset,
        try view.readU16(lookup_offset + 6 + subtable_index * 2),
    );
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

fn readU32ForValidation(view: View, relative: usize) Error!u32 {
    return view.readU32(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
