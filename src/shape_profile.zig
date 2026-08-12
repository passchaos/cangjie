pub const ShapeStageProfile = struct {
    pub const max_lookup_entries = 128;
    pub const lookup_window_capacity = 5;

    pub const LookupEntry = struct {
        lookup_index: u16 = 0,
        elapsed_ns: i128 = 0,
        count: usize = 0,
        glyphs_before_sum: usize = 0,
        glyphs_after_sum: usize = 0,
        last_glyph_delta: isize = 0,
        last_hash_before: u64 = 0,
        last_hash_after: u64 = 0,
        last_first_diff: usize = 0,
        window_start: usize = 0,
        window_len: usize = 0,
        glyphs_before_window: [lookup_window_capacity]u16 = [_]u16{0} ** lookup_window_capacity,
        glyphs_after_window: [lookup_window_capacity]u16 = [_]u16{0} ** lookup_window_capacity,
    };

    total_ns: i128 = 0,
    validate_ns: i128 = 0,
    options_ns: i128 = 0,
    cmap_ns: i128 = 0,
    gdef_ns: i128 = 0,
    gsub_ns: i128 = 0,
    gsub_select_ns: i128 = 0,
    gsub_apply_ns: i128 = 0,
    arabic_stage_ns: [16]i128 = [_]i128{0} ** 16,
    arabic_stage_lookup_count: [16]usize = [_]usize{0} ** 16,
    arabic_stage_count: usize = 0,
    gpos_ns: i128 = 0,
    gpos_select_ns: i128 = 0,
    gpos_apply_ns: i128 = 0,
    position_ns: i128 = 0,
    position_sort_ns: i128 = 0,
    position_loop_ns: i128 = 0,
    position_attachment_ns: i128 = 0,
    position_stch_ns: i128 = 0,
    position_tracking_ns: i128 = 0,
    position_reverse_ns: i128 = 0,
    position_output_glyphs: usize = 0,
    bidi_ns: i128 = 0,
    glyph_count: usize = 0,
    gsub_lookup_count: usize = 0,
    gsub_single_lookup_count: usize = 0,
    gsub_multiple_lookup_count: usize = 0,
    gsub_alternate_lookup_count: usize = 0,
    gsub_ligature_lookup_count: usize = 0,
    gsub_context_lookup_count: usize = 0,
    gsub_extension_lookup_count: usize = 0,
    gpos_lookup_count: usize = 0,
    gpos_single_lookup_count: usize = 0,
    gpos_pair_lookup_count: usize = 0,
    gpos_mark_lookup_count: usize = 0,
    gpos_context_lookup_count: usize = 0,
    gpos_extension_lookup_count: usize = 0,
    gsub_lookup_entries: [max_lookup_entries]LookupEntry = [_]LookupEntry{.{}} ** max_lookup_entries,
    gsub_lookup_entry_count: usize = 0,
    gpos_lookup_entries: [max_lookup_entries]LookupEntry = [_]LookupEntry{.{}} ** max_lookup_entries,
    gpos_lookup_entry_count: usize = 0,

    pub fn recordGsubLookupTime(self: *ShapeStageProfile, lookup_index: ?u16, elapsed_ns: i128) void {
        self.recordLookupTime(&self.gsub_lookup_entries, &self.gsub_lookup_entry_count, lookup_index, elapsed_ns);
    }

    pub fn recordGsubLookupGlyphs(
        self: *ShapeStageProfile,
        lookup_index: ?u16,
        before: usize,
        after: usize,
        hash_before: u64,
        hash_after: u64,
        first_diff: usize,
        window_start: usize,
        before_window: []const u16,
        after_window: []const u16,
    ) void {
        self.recordLookupGlyphs(&self.gsub_lookup_entries, self.gsub_lookup_entry_count, lookup_index, before, after, hash_before, hash_after, first_diff, window_start, before_window, after_window);
    }

    pub fn recordGposLookupTime(self: *ShapeStageProfile, lookup_index: ?u16, elapsed_ns: i128) void {
        self.recordLookupTime(&self.gpos_lookup_entries, &self.gpos_lookup_entry_count, lookup_index, elapsed_ns);
    }

    fn recordLookupTime(self: *ShapeStageProfile, entries: *[max_lookup_entries]LookupEntry, entry_count: *usize, lookup_index: ?u16, elapsed_ns: i128) void {
        _ = self;
        const index = lookup_index orelse return;
        for (entries[0..entry_count.*]) |*entry| {
            if (entry.lookup_index != index) continue;
            entry.elapsed_ns += elapsed_ns;
            entry.count += 1;
            return;
        }
        if (entry_count.* >= entries.len) return;
        entries[entry_count.*] = .{
            .lookup_index = index,
            .elapsed_ns = elapsed_ns,
            .count = 1,
        };
        entry_count.* += 1;
    }

    fn recordLookupGlyphs(
        self: *ShapeStageProfile,
        entries: *[max_lookup_entries]LookupEntry,
        entry_count: usize,
        lookup_index: ?u16,
        before: usize,
        after: usize,
        hash_before: u64,
        hash_after: u64,
        first_diff: usize,
        window_start: usize,
        before_window: []const u16,
        after_window: []const u16,
    ) void {
        _ = self;
        const index = lookup_index orelse return;
        for (entries[0..entry_count]) |*entry| {
            if (entry.lookup_index != index) continue;
            entry.glyphs_before_sum += before;
            entry.glyphs_after_sum += after;
            entry.last_glyph_delta = @as(isize, @intCast(after)) - @as(isize, @intCast(before));
            entry.last_hash_before = hash_before;
            entry.last_hash_after = hash_after;
            entry.last_first_diff = first_diff;
            entry.window_start = window_start;
            entry.window_len = @min(@min(before_window.len, after_window.len), lookup_window_capacity);
            @memset(&entry.glyphs_before_window, 0);
            @memset(&entry.glyphs_after_window, 0);
            @memcpy(entry.glyphs_before_window[0..entry.window_len], before_window[0..entry.window_len]);
            @memcpy(entry.glyphs_after_window[0..entry.window_len], after_window[0..entry.window_len]);
            return;
        }
    }
};
