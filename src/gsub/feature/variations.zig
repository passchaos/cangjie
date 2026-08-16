//! GSUB FeatureVariations condition matching and feature substitution lookup.
//!
//! The returned offsets are relative to the containing GSUB table view. This
//! module only resolves the active variation record and its replacement
//! Feature table; feature lookup-list validation remains the executor's job.

const std = @import("std");
const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGsub};
pub const View = table.View;

/// Return the first FeatureVariationRecord whose ConditionSet matches.
///
/// OpenType defines record order as priority order. A zero ConditionSet offset
/// is therefore an unconditional match, not an absent record. Missing
/// coordinates use the normalized default value zero, as required by the
/// FeatureVariations condition model.
pub fn matchingRecord(
    view: View,
    normalized_coords: []const f32,
) Error!?usize {
    if (normalized_coords.len == 0) return null;
    if (try view.readU16(0) != 1) return null;
    if (try view.readU16(2) < 1) return null;

    // Widen authored offsets before any arithmetic. A valid table view may be
    // larger than 4 GiB on 64-bit hosts, and `Offset32 + header_size` must not
    // wrap in the serialized u32 domain before bounds validation.
    const variations_offset: usize = try view.readU32(10);
    if (variations_offset == 0) return null;
    try view.ensure(variations_offset, 8);
    if (try view.readU16(variations_offset) != 1) {
        return error.UnsupportedGsub;
    }

    const record_count = try view.readU32(variations_offset + 4);
    const records_offset = variations_offset + 8;
    try ensureRecordArray(view, records_offset, record_count, 8);
    for (0..record_count) |record_index| {
        const record_offset = records_offset + record_index * 8;
        const condition_relative = try view.readU32(record_offset);
        if (condition_relative == 0) return record_index;
        const condition_set = try table.offset.required32(
            view,
            variations_offset,
            condition_relative,
        );
        if (try conditionSetMatches(
            view,
            condition_set,
            normalized_coords,
        )) {
            return record_index;
        }
    }
    return null;
}

/// Resolve the replacement Feature table for one matched variation record.
///
/// `null` means either that the record has no FeatureTableSubstitution table
/// or that it does not replace `feature_index`.
pub fn substitutedFeatureOffset(
    view: View,
    variation_record_index: usize,
    feature_index: u16,
) Error!?usize {
    const variations_offset: usize = try view.readU32(10);
    if (variations_offset == 0) return null;
    try view.ensure(variations_offset, 8);

    const record_count = try view.readU32(variations_offset + 4);
    if (variation_record_index >= record_count) return error.BadGsub;
    const records_offset = variations_offset + 8;
    try ensureRecordArray(view, records_offset, record_count, 8);

    const record_offset = records_offset + variation_record_index * 8;
    const substitution_relative = try view.readU32(record_offset + 4);
    if (substitution_relative == 0) return null;
    const substitution = try table.offset.required32(
        view,
        variations_offset,
        substitution_relative,
    );
    try view.ensure(substitution, 6);
    if (try view.readU16(substitution) != 1) {
        return error.UnsupportedGsub;
    }

    const substitution_count = try view.readU16(substitution + 4);
    const substitution_records = substitution + 6;
    try ensureRecordArray(view, substitution_records, substitution_count, 6);
    for (0..substitution_count) |record_index| {
        const record = substitution_records + record_index * 6;
        if (try view.readU16(record) != feature_index) continue;
        return try table.offset.required32(
            view,
            substitution,
            try view.readU32(record + 2),
        );
    }
    return null;
}

fn conditionSetMatches(
    view: View,
    condition_set: usize,
    normalized_coords: []const f32,
) Error!bool {
    try view.ensure(condition_set, 2);
    const condition_count = try view.readU16(condition_set);
    const condition_offsets = condition_set + 2;
    try ensureRecordArray(view, condition_offsets, condition_count, 4);
    for (0..condition_count) |condition_index| {
        const condition = try table.offset.required32(
            view,
            condition_set,
            try view.readU32(condition_offsets + condition_index * 4),
        );
        if (!try conditionMatches(view, condition, normalized_coords)) {
            return false;
        }
    }
    return true;
}

fn conditionMatches(
    view: View,
    condition: usize,
    normalized_coords: []const f32,
) Error!bool {
    try view.ensure(condition, 8);
    if (try view.readU16(condition) != 1) return false;

    const axis_index = try view.readU16(condition + 2);
    const min_value = try view.readF2Dot14(condition + 4);
    const max_value = try view.readF2Dot14(condition + 6);
    const coordinate = if (axis_index < normalized_coords.len)
        normalized_coords[axis_index]
    else
        0;
    return coordinate >= min_value and coordinate <= max_value;
}

fn ensureRecordArray(
    view: View,
    records_offset: usize,
    record_count: anytype,
    record_size: usize,
) Error!void {
    // Counts are authored as both u16 and u32 in the surrounding formats.
    // Reject values that cannot be represented by the target instead of
    // trapping on 32-bit builds before the table-bounds check can run.
    const count = std.math.cast(usize, record_count) orelse
        return error.BadGsub;
    if (count > view.length / record_size) return error.BadGsub;
    try view.ensure(records_offset, count * record_size);
}
