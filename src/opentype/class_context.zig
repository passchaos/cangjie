const GlyphId = @import("../glyph.zig").GlyphId;

/// Class definition role for an OpenType chaining-context match region.
pub const ClassRole = enum {
    backtrack,
    input,
    lookahead,
};

/// Compact representation of a chaining class rule whose backtrack/input shape
/// has already been proven by the table-specific builder. `classes_start` and
/// `lookahead_count` select the expected lookahead class sequence from a
/// side-car class array.
pub const Rule = struct {
    class_set: u16,
    input_count: u16,
    lookahead_count: u16,
    hash: u64,
    order: u32,
    lookup_index: u16,
    classes_start: u32,
    subst_count: u16 = 1,
    /// Number of preceding glyphs in a chaining rule. Context rules leave it
    /// at zero. Keeping this independent from `records_offset` avoids
    /// overloading a table cursor with match geometry.
    backtrack_count: u16 = 0,
    /// False denotes the compact one-record/sequence-zero action stored in
    /// `lookup_index`; true denotes an authored record list at
    /// `records_offset`.
    record_list: bool = false,
    /// Table-relative offset of the first authored SequenceLookupRecord. This
    /// is meaningful only when `record_list` is true (or for context rules,
    /// which always execute authored lists).
    records_offset: u32 = 0,
};

pub const RuleGroup = struct {
    class_set: u16,
    start: usize,
    len: usize,
    max_input_count: u16,
    max_lookahead_count: u16,
    /// Rules in this group have identical region lengths and are ordered by
    /// `Rule.hash`, then authored order.
    hash_sorted: bool = false,
};

pub fn sequenceHashEmpty() u64 {
    return 0xcbf29ce484222325;
}

pub fn sequenceHash(classes: []const u16) u64 {
    var hash = sequenceHashEmpty();
    for (classes) |class| hash = sequenceHashAppend(hash, class);
    return hash;
}

pub fn sequenceHashAppend(hash: u64, class: u16) u64 {
    return (hash ^ @as(u64, class)) *% 0x100000001b3;
}

pub fn ruleLessThan(_: void, lhs: Rule, rhs: Rule) bool {
    if (lhs.class_set != rhs.class_set) return lhs.class_set < rhs.class_set;
    return lhs.order < rhs.order;
}

pub fn ruleHashLessThan(_: void, lhs: Rule, rhs: Rule) bool {
    if (lhs.class_set != rhs.class_set) return lhs.class_set < rhs.class_set;
    if (lhs.hash != rhs.hash) return lhs.hash < rhs.hash;
    return lhs.order < rhs.order;
}

pub fn groupForClass(groups: []const RuleGroup, class_set: u16) ?RuleGroup {
    const index = groupIndexForClass(groups, class_set) orelse return null;
    return groups[index];
}

pub fn groupIndexForClass(
    groups: []const RuleGroup,
    class_set: u16,
) ?usize {
    var lo: usize = 0;
    var hi: usize = groups.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const candidate = groups[mid].class_set;
        if (class_set < candidate) {
            hi = mid;
        } else if (class_set > candidate) {
            lo = mid + 1;
        } else {
            return mid;
        }
    }
    return null;
}

/// Builds a small, stack-backed cache for OpenType chaining class-context
/// matching. Format-2 chaining subtables frequently contain many candidate
/// rules for the same first glyph; those rules share the same backtrack/input/
/// lookahead glyph window while differing only in expected class vectors.
///
/// The caller supplies table-specific class lookup and ignore predicates so
/// the cache can be shared by layout engines without owning parser state.
pub fn MatchWindow(
    comptime Context: type,
    comptime LookupError: type,
    comptime unsupported_context_error: LookupError,
    comptime max_region_glyphs: usize,
    comptime classValueFn: fn (*Context, ClassRole, GlyphId) LookupError!u16,
    comptime skipsGlyphFn: fn (*Context, []const GlyphId, usize) bool,
) type {
    return struct {
        const Self = @This();
        pub const max_forward_glyphs = max_region_glyphs * 2;

        context: *Context,
        glyphs: []const GlyphId,

        forward_indices: [max_forward_glyphs]usize = undefined,
        forward_input_classes: [max_forward_glyphs]u16 = undefined,
        forward_input_class_valid: [max_forward_glyphs]bool = [_]bool{false} ** max_forward_glyphs,
        forward_lookahead_classes: [max_forward_glyphs]u16 = undefined,
        forward_lookahead_class_valid: [max_forward_glyphs]bool = [_]bool{false} ** max_forward_glyphs,
        forward_len: usize = 0,
        forward_scan: usize,
        forward_exhausted: bool = false,

        backtrack_indices: [max_region_glyphs]usize = undefined,
        backtrack_classes: [max_region_glyphs]u16 = undefined,
        backtrack_class_valid: [max_region_glyphs]bool = [_]bool{false} ** max_region_glyphs,
        backtrack_len: usize = 0,
        backtrack_scan: usize,
        backtrack_exhausted: bool = false,

        pub fn init(context: *Context, glyphs: []const GlyphId, pos: usize) Self {
            return .{
                .context = context,
                .glyphs = glyphs,
                .forward_scan = pos,
                .backtrack_scan = pos,
            };
        }

        pub fn inputIndices(self: *Self, count: usize) LookupError!?[]const usize {
            if (count > max_region_glyphs) return unsupported_context_error;
            if (!try self.ensureForwardCount(count)) return null;
            return self.forward_indices[0..count];
        }

        pub fn inputClassAt(self: *Self, forward_index: usize) LookupError!?u16 {
            if (forward_index >= max_region_glyphs) return unsupported_context_error;
            if (!try self.ensureForwardCount(forward_index + 1)) return null;
            if (!self.forward_input_class_valid[forward_index]) {
                self.forward_input_classes[forward_index] = try classValueFn(self.context, .input, self.glyphs[self.forward_indices[forward_index]]);
                self.forward_input_class_valid[forward_index] = true;
            }
            return self.forward_input_classes[forward_index];
        }

        pub fn lookaheadClassAt(self: *Self, forward_index: usize) LookupError!?u16 {
            if (forward_index >= max_forward_glyphs) return unsupported_context_error;
            if (!try self.ensureForwardCount(forward_index + 1)) return null;
            if (!self.forward_lookahead_class_valid[forward_index]) {
                self.forward_lookahead_classes[forward_index] = try classValueFn(self.context, .lookahead, self.glyphs[self.forward_indices[forward_index]]);
                self.forward_lookahead_class_valid[forward_index] = true;
            }
            return self.forward_lookahead_classes[forward_index];
        }

        pub fn backtrackClassAt(self: *Self, backtrack_index: usize) LookupError!?u16 {
            if (backtrack_index >= max_region_glyphs) return unsupported_context_error;
            if (!try self.ensureBacktrackCount(backtrack_index + 1)) return null;
            if (!self.backtrack_class_valid[backtrack_index]) {
                self.backtrack_classes[backtrack_index] = try classValueFn(self.context, .backtrack, self.glyphs[self.backtrack_indices[backtrack_index]]);
                self.backtrack_class_valid[backtrack_index] = true;
            }
            return self.backtrack_classes[backtrack_index];
        }

        pub fn ensureForwardCount(self: *Self, count: usize) LookupError!bool {
            if (count > max_forward_glyphs) return unsupported_context_error;
            while (self.forward_len < count) {
                if (self.forward_exhausted) return false;
                var found = false;
                while (self.forward_scan < self.glyphs.len) {
                    const glyph_index = self.forward_scan;
                    self.forward_scan += 1;
                    if (skipsGlyphFn(self.context, self.glyphs, glyph_index)) continue;
                    self.forward_indices[self.forward_len] = glyph_index;
                    self.forward_len += 1;
                    found = true;
                    break;
                }
                if (!found) {
                    self.forward_exhausted = true;
                    return false;
                }
            }
            return true;
        }

        fn ensureBacktrackCount(self: *Self, count: usize) LookupError!bool {
            if (count > max_region_glyphs) return unsupported_context_error;
            while (self.backtrack_len < count) {
                if (self.backtrack_exhausted) return false;
                var found = false;
                while (self.backtrack_scan > 0) {
                    self.backtrack_scan -= 1;
                    if (skipsGlyphFn(self.context, self.glyphs, self.backtrack_scan)) continue;
                    self.backtrack_indices[self.backtrack_len] = self.backtrack_scan;
                    self.backtrack_len += 1;
                    found = true;
                    break;
                }
                if (!found) {
                    self.backtrack_exhausted = true;
                    return false;
                }
            }
            return true;
        }
    };
}
