//! FreeType-derived CFF horizontal-stem hint map.
//!
//! CFF raster hinting deliberately transforms only Y. Vertical stem hints are
//! retained in the program because masks count both axes, but FreeType's native
//! CFF hinter leaves X under the uniform outline scale.

const std = @import("std");
const fixed_mod = @import("fixed.zig");
const params_mod = @import("params.zig");
const program = @import("program.zig");

const Fixed = fixed_mod.Fixed;
pub const max_hints = 96;
pub const hint_mask_size = (max_hints + 7) / 8;
const max_blue_zones = 12;
const min_counter = Fixed.fromBits(0x8000);
const epsilon = Fixed.fromBits(1);
const icf_top = Fixed.fromInt(880);
const icf_bottom = Fixed.fromInt(-120);

const ghost_bottom: u8 = 0x01;
const ghost_top: u8 = 0x02;
const pair_bottom: u8 = 0x04;
const pair_top: u8 = 0x08;
const locked: u8 = 0x10;
const synthetic: u8 = 0x20;

pub const Mask = struct {
    bytes: [hint_mask_size]u8 = [_]u8{0xff} ** hint_mask_size,
    valid: bool = true,

    pub fn all() Mask {
        return .{};
    }

    pub fn fromBytes(bytes: []const u8) Mask {
        if (bytes.len > hint_mask_size) return .{};
        var result = Mask{ .bytes = [_]u8{0} ** hint_mask_size };
        @memcpy(result.bytes[0..bytes.len], bytes);
        return result;
    }

    fn get(self: Mask, index: usize) bool {
        return index < max_hints and
            (self.bytes[index >> 3] & (@as(u8, 1) << @intCast(7 - (index & 7)))) != 0;
    }

    fn clear(self: *Mask, index: usize) void {
        self.bytes[index >> 3] &= ~(@as(u8, 1) << @intCast(7 - (index & 7)));
    }
};

pub const StemHint = struct {
    used: bool = false,
    /// Bit position in the original Type2 mask. Vertical hints consume mask
    /// bits even though the native CFF hinter transforms only Y.
    mask_index: u8 = 0,
    min: Fixed = .zero,
    max: Fixed = .zero,
    ds_min: Fixed = .zero,
    ds_max: Fixed = .zero,
};

const Zone = struct {
    bottom: bool = false,
    cs_bottom: Fixed = .zero,
    cs_top: Fixed = .zero,
    cs_flat: Fixed = .zero,
    ds_flat: Fixed = .zero,
};

pub const State = struct {
    scale: Fixed,
    blue_scale: Fixed,
    blue_shift: Fixed,
    blue_fuzz: Fixed,
    language_group: i32,
    suppress_overshoot: bool = false,
    em_box_hints: bool = false,
    boost: Fixed = .zero,
    zones: [max_blue_zones]Zone = [_]Zone{.{}} ** max_blue_zones,
    zone_count: usize = 0,

    pub fn init(params: params_mod.Params, scale: Fixed) State {
        var state = State{
            .scale = scale,
            .blue_scale = params.blue_scale,
            .blue_shift = params.blue_shift,
            .blue_fuzz = params.blue_fuzz,
            .language_group = params.language_group,
        };
        state.buildZones(params);
        return state;
    }

    fn buildZones(self: *State, params: params_mod.Params) void {
        if (self.language_group == 1) {
            const blues = params.blues.slice();
            if (blues.len == 0 or
                (blues.len == 2 and
                    blues[0][0].lessThan(icf_bottom) and
                    blues[0][1].lessThan(icf_bottom) and
                    icf_top.lessThan(blues[1][0]) and
                    icf_top.lessThan(blues[1][1])))
            {
                self.em_box_hints = true;
                return;
            }
        }
        var max_height = Fixed.zero;
        for (params.blues.slice(), 0..) |pair, index| {
            if (self.zone_count == self.zones.len) break;
            const height = pair[1].sub(pair[0]);
            if (height.bits < 0) continue;
            max_height = max_height.maxValue(height);
            const zone = Zone{
                .bottom = index == 0,
                .cs_bottom = pair[0],
                .cs_top = pair[1],
                .cs_flat = if (index == 0) pair[1] else pair[0],
            };
            self.zones[self.zone_count] = zone;
            self.zone_count += 1;
        }
        for (params.other_blues.slice()) |pair| {
            if (self.zone_count == self.zones.len) break;
            const height = pair[1].sub(pair[0]);
            if (height.bits < 0) continue;
            max_height = max_height.maxValue(height);
            self.zones[self.zone_count] = .{
                .bottom = true,
                .cs_bottom = pair[0],
                .cs_top = pair[1],
                .cs_flat = pair[1],
            };
            self.zone_count += 1;
        }

        // Prefer a matching family flat edge when it is within one device
        // pixel. The original zone edges remain the capture range.
        const units_per_pixel = Fixed.one.div(self.scale);
        for (self.zones[0..self.zone_count]) |*zone| {
            const original = zone.cs_flat;
            var best = Fixed.max;
            if (zone.bottom) {
                for (params.family_other_blues.slice()) |pair| {
                    const diff = original.sub(pair[1]).abs();
                    if (diff.lessThan(best) and diff.lessThan(units_per_pixel)) {
                        zone.cs_flat = pair[1];
                        best = diff;
                    }
                }
                const family = params.family_blues.slice();
                if (family.len != 0) {
                    const diff = original.sub(family[0][1]).abs();
                    if (diff.lessThan(best) and diff.lessThan(units_per_pixel)) {
                        zone.cs_flat = family[0][1];
                    }
                }
            } else {
                for (params.family_blues.slice()[@min(1, params.family_blues.slice().len)..]) |pair| {
                    const diff = original.sub(pair[0]).abs();
                    if (diff.lessThan(best) and diff.lessThan(units_per_pixel)) {
                        zone.cs_flat = pair[0];
                        best = diff;
                    }
                }
            }
        }
        if (max_height.bits > 0) {
            const maximum_scale = Fixed.one.div(max_height);
            if (maximum_scale.lessThan(self.blue_scale)) self.blue_scale = maximum_scale;
        }
        if (self.scale.lessThan(self.blue_scale)) {
            self.suppress_overshoot = true;
            const six_tenths = Fixed.fromF32(0.6);
            self.boost = six_tenths.sub(six_tenths.mulDiv(self.scale, self.blue_scale));
            self.boost = self.boost.minValue(Fixed.fromBits(0x7fff));
        }
        for (self.zones[0..self.zone_count]) |*zone| {
            const boost = if (zone.bottom) self.boost.neg() else self.boost;
            zone.ds_flat = zone.cs_flat.mul(self.scale).add(boost).round();
        }
    }

    fn capture(self: *const State, bottom: *Hint, top: *Hint) bool {
        var adjustment = Fixed.zero;
        var found = false;
        for (self.zones[0..self.zone_count]) |zone| {
            if (zone.bottom and bottom.isBottom() and
                zone.cs_bottom.sub(self.blue_fuzz).lessOrEqual(bottom.cs) and
                bottom.cs.lessOrEqual(zone.cs_top.add(self.blue_fuzz)))
            {
                const target = if (self.suppress_overshoot)
                    zone.ds_flat
                else if (self.blue_shift.lessOrEqual(zone.cs_top.sub(bottom.cs)))
                    bottom.ds.round().minValue(zone.ds_flat.sub(Fixed.one))
                else
                    bottom.ds.round();
                adjustment = target.sub(bottom.ds);
                found = true;
                break;
            }
            if (!zone.bottom and top.isTop() and
                zone.cs_bottom.sub(self.blue_fuzz).lessOrEqual(top.cs) and
                top.cs.lessOrEqual(zone.cs_top.add(self.blue_fuzz)))
            {
                const target = if (self.suppress_overshoot)
                    zone.ds_flat
                else if (self.blue_shift.lessOrEqual(top.cs.sub(zone.cs_bottom)))
                    top.ds.round().maxValue(zone.ds_flat.add(Fixed.one))
                else
                    top.ds.round();
                adjustment = target.sub(top.ds);
                found = true;
                break;
            }
        }
        if (found) {
            if (bottom.valid()) {
                bottom.ds = bottom.ds.add(adjustment);
                bottom.flags |= locked;
            }
            if (top.valid()) {
                top.ds = top.ds.add(adjustment);
                top.flags |= locked;
            }
        }
        return found;
    }
};

const Hint = struct {
    flags: u8 = 0,
    index: u8 = 0,
    cs: Fixed = .zero,
    ds: Fixed = .zero,
    scale: Fixed = .zero,

    fn setup(stem: StemHint, index: u8, origin: Fixed, scale: Fixed, is_bottom: bool) Hint {
        const width = stem.max.sub(stem.min);
        var result = Hint{ .index = index, .scale = scale };
        if (width.bits == Fixed.fromInt(-21).bits) {
            if (is_bottom) {
                result.cs = stem.max;
                result.flags = ghost_bottom;
            }
        } else if (width.bits == Fixed.fromInt(-20).bits) {
            if (!is_bottom) {
                result.cs = stem.min;
                result.flags = ghost_top;
            }
        } else if (width.bits < 0) {
            result.cs = if (is_bottom) stem.max else stem.min;
            result.flags = if (is_bottom) pair_bottom else pair_top;
        } else {
            result.cs = if (is_bottom) stem.min else stem.max;
            result.flags = if (is_bottom) pair_bottom else pair_top;
        }
        result.cs = result.cs.add(origin);
        if (result.valid() and stem.used) {
            result.ds = if (result.isTop()) stem.ds_max else stem.ds_min;
            result.flags |= locked;
        } else {
            result.ds = result.cs.mul(scale);
        }
        return result;
    }

    fn valid(self: Hint) bool {
        return self.flags != 0;
    }
    fn isBottom(self: Hint) bool {
        return (self.flags & (ghost_bottom | pair_bottom)) != 0;
    }
    fn isTop(self: Hint) bool {
        return (self.flags & (ghost_top | pair_top)) != 0;
    }
    fn isPair(self: Hint) bool {
        return (self.flags & (pair_bottom | pair_top)) != 0;
    }
    fn pairTop(self: Hint) bool {
        return (self.flags & pair_top) != 0;
    }
    fn isLocked(self: Hint) bool {
        return (self.flags & locked) != 0;
    }
    fn isSynthetic(self: Hint) bool {
        return (self.flags & synthetic) != 0;
    }
};

pub const HintMap = struct {
    edges: [max_hints]Hint = [_]Hint{.{}} ** max_hints,
    len: usize = 0,
    valid: bool = false,
    scale: Fixed,

    pub fn init(scale: Fixed) HintMap {
        return .{ .scale = scale };
    }

    pub fn transform(self: *const HintMap, coordinate: Fixed) Fixed {
        if (self.len == 0) return coordinate.mul(self.scale);
        var index: usize = 0;
        while (index + 1 < self.len and
            !coordinate.lessThan(self.edges[index + 1].cs)) : (index += 1)
        {}
        while (index > 0 and coordinate.lessThan(self.edges[index].cs)) : (index -= 1) {}
        const edge = if (index == 0 and coordinate.lessThan(self.edges[0].cs))
            Hint{ .cs = self.edges[0].cs, .ds = self.edges[0].ds, .scale = self.scale }
        else
            self.edges[index];
        return coordinate.sub(edge.cs).mul(edge.scale).add(edge.ds);
    }

    fn insert(self: *HintMap, bottom: Hint, top: Hint, initial: ?*const HintMap) void {
        const pair = bottom.valid() and top.valid();
        var first = if (bottom.valid()) bottom else top;
        var second = top;
        if (pair and second.cs.lessThan(first.cs)) return;
        const count: usize = if (pair) 2 else 1;
        if (self.len + count > self.edges.len or !first.valid()) return;
        var at: usize = 0;
        while (at < self.len and self.edges[at].cs.lessThan(first.cs)) : (at += 1) {}
        if (at < self.len) {
            const current = self.edges[at];
            if (current.cs.bits == first.cs.bits or
                (pair and !second.cs.lessThan(current.cs)) or current.pairTop()) return;
        }
        if (!first.isLocked()) {
            if (initial) |map| {
                if (pair) {
                    const middle = map.transform(midpoint(first.cs, second.cs));
                    const half_width = half(second.cs.sub(first.cs)).mul(self.scale);
                    first.ds = middle.sub(half_width);
                    second.ds = middle.add(half_width);
                } else {
                    first.ds = map.transform(first.cs);
                }
            }
        }
        if (at > 0 and first.ds.lessThan(self.edges[at - 1].ds)) return;
        if (at < self.len and
            ((pair and self.edges[at].ds.lessThan(second.ds)) or
                self.edges[at].ds.lessThan(first.ds))) return;
        std.mem.copyBackwards(Hint, self.edges[at + count .. self.len + count], self.edges[at..self.len]);
        self.edges[at] = first;
        if (pair) self.edges[at + 1] = second;
        self.len += count;
    }

    fn adjust(self: *HintMap) void {
        var saved: [max_hints]struct { index: usize = 0, adjustment: Fixed = .zero } = undefined;
        var saved_len: usize = 0;
        var index: usize = 0;
        while (index < self.len) : (index += 1) {
            const pair = self.edges[index].isPair();
            const upper = if (pair) index + 1 else index;
            if (!self.edges[index].isLocked()) {
                const frac_down = self.edges[index].ds.fract();
                const frac_up = self.edges[upper].ds.fract();
                const down_down = frac_down.neg();
                const up_down = frac_up.neg();
                const down_up = if (frac_down.bits == 0) Fixed.zero else Fixed.one.sub(frac_down);
                const up_up = if (frac_up.bits == 0) Fixed.zero else Fixed.one.sub(frac_up);
                const move_up = down_up.minValue(up_up);
                const move_down = down_down.maxValue(up_down);
                var adjustment = Fixed.zero;
                var save = false;
                const room_up = upper >= self.len - 1 or
                    !self.edges[upper + 1].ds.lessThan(self.edges[upper].ds.add(move_up).add(min_counter));
                const room_down = index == 0 or
                    !self.edges[index].ds.add(move_down).sub(min_counter).lessThan(self.edges[index - 1].ds);
                if (room_up) {
                    adjustment = if (room_down and move_up.lessThan(move_down.neg())) move_up else if (room_down) move_down else move_up;
                } else if (room_down) {
                    adjustment = move_down;
                    save = move_down.neg().lessThan(move_up);
                } else {
                    save = true;
                }
                if (save and upper + 1 < self.len and !self.edges[upper + 1].isLocked()) {
                    saved[saved_len] = .{ .index = upper, .adjustment = move_up.sub(adjustment) };
                    saved_len += 1;
                }
                self.edges[index].ds = self.edges[index].ds.add(adjustment);
                if (pair) self.edges[upper].ds = self.edges[upper].ds.add(adjustment);
            }
            if (index > 0 and self.edges[index].cs.bits != self.edges[index - 1].cs.bits) {
                self.edges[index - 1].scale = self.edges[index].ds.sub(self.edges[index - 1].ds)
                    .div(self.edges[index].cs.sub(self.edges[index - 1].cs));
            }
            if (pair) {
                if (self.edges[upper].cs.bits != self.edges[upper - 1].cs.bits) {
                    self.edges[upper - 1].scale = self.edges[upper].ds.sub(self.edges[upper - 1].ds)
                        .div(self.edges[upper].cs.sub(self.edges[upper - 1].cs));
                }
                index += 1;
            }
        }
        var saved_index = saved_len;
        while (saved_index != 0) {
            saved_index -= 1;
            const entry = saved[saved_index];
            const upper = entry.index + 1;
            if (!self.edges[upper].ds.lessThan(self.edges[entry.index].ds.add(entry.adjustment).add(min_counter))) {
                self.edges[entry.index].ds = self.edges[entry.index].ds.add(entry.adjustment);
                if (self.edges[entry.index].isPair()) {
                    self.edges[entry.index - 1].ds = self.edges[entry.index - 1].ds.add(entry.adjustment);
                }
            }
        }
    }

    pub fn build(
        self: *HintMap,
        state: *const State,
        incoming_mask: ?Mask,
        initial: ?*HintMap,
        stems: []StemHint,
        origin: Fixed,
        is_initial: bool,
    ) void {
        if (!is_initial) if (initial) |initial_map| {
            if (!initial_map.valid) initial_map.build(state, Mask.all(), null, stems, origin, true);
        };
        self.len = 0;
        self.valid = false;
        var mask = incoming_mask orelse Mask.all();
        if (!mask.valid) mask = Mask.all();
        const initial_const: ?*const HintMap = if (is_initial) null else if (initial) |value| value else null;
        if (state.em_box_hints) {
            const invalid = Hint{};
            self.insert(.{
                .cs = icf_bottom.sub(epsilon),
                .ds = icf_bottom.sub(epsilon).mul(state.scale).round().sub(min_counter),
                .scale = state.scale,
                .flags = ghost_bottom | locked | synthetic,
            }, invalid, initial_const);
            self.insert(invalid, .{
                .cs = icf_top.add(epsilon),
                .ds = icf_top.add(epsilon).mul(state.scale).round().add(min_counter),
                .scale = state.scale,
                .flags = ghost_top | locked | synthetic,
            }, initial_const);
        }
        var remaining = mask;
        for (stems, 0..) |stem, stem_index| {
            if (!remaining.get(stem.mask_index)) continue;
            var bottom = Hint.setup(stem, @intCast(stem_index), origin, state.scale, true);
            var top = Hint.setup(stem, @intCast(stem_index), origin, state.scale, false);
            if (bottom.isLocked() or top.isLocked() or state.capture(&bottom, &top)) {
                self.insert(bottom, top, if (is_initial) null else initial_const);
                remaining.clear(stem.mask_index);
            }
        }
        if (is_initial) {
            if (self.len == 0 or self.edges[0].cs.bits > 0 or self.edges[self.len - 1].cs.bits < 0) {
                self.insert(.{ .flags = ghost_bottom | locked | synthetic, .scale = state.scale }, .{}, null);
            }
        } else {
            for (stems, 0..) |stem, stem_index| {
                if (!remaining.get(stem.mask_index)) continue;
                self.insert(
                    Hint.setup(stem, @intCast(stem_index), origin, state.scale, true),
                    Hint.setup(stem, @intCast(stem_index), origin, state.scale, false),
                    initial_const,
                );
            }
        }
        self.adjust();
        if (!is_initial) for (self.edges[0..self.len]) |edge| {
            if (edge.isSynthetic()) continue;
            if (edge.isTop()) stems[edge.index].ds_max = edge.ds else stems[edge.index].ds_min = edge.ds;
            stems[edge.index].used = true;
        };
        self.valid = true;
    }
};

pub fn horizontalStems(program_value: *const program.Program, out: *[max_hints]StemHint) usize {
    var count: usize = 0;
    for (program_value.stems.items, 0..) |stem, mask_index| {
        if (stem.axis != .horizontal) continue;
        if (count == out.len or mask_index >= max_hints) break;
        out[count] = .{
            .mask_index = @intCast(mask_index),
            .min = Fixed.fromF32(stem.min),
            .max = Fixed.fromF32(stem.max),
        };
        count += 1;
    }
    return count;
}

fn half(value: Fixed) Fixed {
    return Fixed.fromBits(@divTrunc(value.bits, 2));
}
fn midpoint(a: Fixed, b: Fixed) Fixed {
    return a.add(half(b.sub(a)));
}
