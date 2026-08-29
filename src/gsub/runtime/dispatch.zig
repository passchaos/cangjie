//! GSUB lookup header dispatch and accelerator capability selection.
//!
//! Cached fields are trusted only for an exact validated lookup identity.
//! Concrete capability helpers keep sidecar-selection policy out of the
//! substitution executor without introducing callbacks or erased contexts.

const accelerator = @import("../accelerator/root.zig");
const options = @import("options.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error;
pub const Lookup = accelerator.Lookup;
pub const MultipleSubstitution = accelerator.model.MultipleSubstitution;
pub const LigatureSubstitution = accelerator.model.LigatureSubstitution;
pub const Options = options.Options;
pub const SingleEntry = accelerator.model.SingleEntry;
pub const View = table.View;

pub const Header = struct {
    lookup_type: u16,
    lookup_flag: u16,
    subtable_count: u16,
    mark_filtering_set: ?u16,
};

/// Resolve one Lookup header after its fixed storage has been validated.
pub fn header(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    run: Options,
) Error!Header {
    if (exact(view, lookup_offset, lookup_index, run)) |cached| {
        return .{
            .lookup_type = cached.lookup_type,
            .lookup_flag = cached.lookup_flag,
            .subtable_count = cached.subtable_count,
            .mark_filtering_set = cached.mark_filtering_set,
        };
    }

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

/// Return the sidecar only when the caller owns a validated table view and the
/// cached lookup identity matches that exact table position. Capability-specific
/// dispatchers may still decline its payload, but can reuse the header proof.
pub inline fn exact(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    if (!view.assume_validated) return null;
    const cached = any(lookup_index, run) orelse return null;
    if (cached.lookup_offset != lookup_offset or cached.lookup_type == 0) {
        return null;
    }
    return cached;
}

pub fn any(lookup_index: ?u16, run: Options) ?*const Lookup {
    const accelerators = run.lookup_accelerators orelse return null;
    const index = lookup_index orelse return null;
    if (index >= accelerators.len) return null;
    return &accelerators[index];
}

pub fn chainingCoverage(
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    const cached = any(lookup_index, run) orelse return null;
    if (!cached.chaining_coverage_only) return null;
    return cached;
}

pub fn reverseChaining(
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.reverse_chaining_subtables.len == 0 or
        cached.reverse_chaining_groups.len == 0)
    {
        return null;
    }
    return cached;
}

pub fn multiple(
    lookup_index: ?u16,
    run: Options,
) ?*const MultipleSubstitution {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.multiple_subst.entries.len == 0) return null;
    return &cached.multiple_subst;
}

pub fn singleEntries(
    lookup_index: ?u16,
    run: Options,
) ?[]const SingleEntry {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.single_subst_entries.len == 0) return null;
    return cached.single_subst_entries;
}

pub fn ligature(
    lookup_index: ?u16,
    run: Options,
) ?*const LigatureSubstitution {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.ligature_subst.sets.len == 0) return null;
    return &cached.ligature_subst;
}

pub fn contextClass(
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.context_class_subtables.len == 0) return null;
    return cached;
}

pub fn contextCoverage(
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.context_coverage_subtables.len == 0) return null;
    return cached;
}

pub fn chainingClass(
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.chaining_class_subtables.len == 0) return null;
    return cached;
}

pub fn extensionType(
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    const cached = any(lookup_index, run) orelse return null;
    if (cached.extension_lookup_type == null) return null;
    return cached;
}

pub fn tableUsesRunDigestCache(lookups: ?[]const Lookup) bool {
    const items = lookups orelse return false;
    return items.len != 0 and items[0].table_uses_run_digest_cache;
}

pub fn matchesSourceSyllable(
    lookup_index: ?u16,
    run: Options,
) bool {
    if (run.match_source_syllable) return true;
    const lookups = run.match_source_syllable_lookups orelse return false;
    const index = lookup_index orelse return false;
    for (lookups) |candidate| {
        if (candidate == index) return true;
    }
    return false;
}

pub fn needsCustomizedOptions(
    lookup_flag: u16,
    scoped_syllable: bool,
    run: Options,
) bool {
    return (lookup_flag & 0x0010) != 0 or
        scoped_syllable != run.match_source_syllable;
}
