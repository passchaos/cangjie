//! FreeType v40 backward-compatibility state and movement policy.
//!
//! Bit 2 enables compatibility; bits 0 and 1 record IUP[Y] and IUP[X].
//! The value therefore reaches `0b111` after both axes have been
//! interpolated. FreeType uses that exact post-IUP state to suppress later
//! pattern-fixing instructions while still updating touched flags.

const state = @import("state.zig");
const types = @import("../types.zig");

pub const State = struct {
    bits: u3 = 0,
    is_compound: bool = false,

    pub fn init(
        interpreter: types.Interpreter,
        target: types.Target,
        instruct_control: u8,
        tricky: bool,
    ) State {
        const enabled =
            interpreter == .cleartype and
            target != .mono and
            !tricky and
            (instruct_control & 4) == 0;
        return .{ .bits = if (enabled) 4 else 0 };
    }

    pub fn beginGlyph(self: *State, is_compound: bool) void {
        self.bits &= 4;
        self.is_compound = is_compound;
    }

    pub fn active(self: State) bool {
        return self.bits != 0;
    }

    pub fn postIup(self: State) bool {
        return self.bits == 7;
    }

    /// Record one IUP axis and report whether this invocation executes.
    pub fn beginIup(self: *State, x_axis: bool) bool {
        if (self.postIup()) return false;
        if (self.active()) {
            self.bits |= @as(u3, 1) << @intFromBool(x_axis);
        }
        return true;
    }

    /// Glyph INSTCTRL selector 3 may temporarily toggle native ClearType.
    pub fn setGlyphInstructionControl(
        self: *State,
        interpreter: types.Interpreter,
        value: u8,
    ) void {
        if (interpreter != .cleartype) return;
        self.bits = @truncate((value & 4) ^ 4);
    }

    pub fn directAxes(
        self: State,
        freedom: state.Vector,
    ) Axes {
        return .{
            .x = freedom.x != 0 and !self.active(),
            .y = freedom.y != 0 and !self.postIup(),
        };
    }

    pub fn allowPatternMove(
        self: State,
        freedom: state.Vector,
        touched_y: bool,
    ) bool {
        if (!self.active()) return true;
        return !self.postIup() and
            ((self.is_compound and freedom.y != 0) or touched_y);
    }

    pub fn allowShiftPixel(
        self: State,
        graphics: state.GraphicsState,
        touched_y: bool,
    ) bool {
        if (!self.active()) return true;
        const uses_twilight =
            graphics.zp0 == 0 or
            graphics.zp1 == 0 or
            graphics.zp2 == 0;
        return uses_twilight or self.allowPatternMove(
            graphics.freedom,
            touched_y,
        );
    }
};

pub const Axes = struct {
    x: bool,
    y: bool,
};

test "v40 compatibility tracks IUP and native ClearType waiver" {
    const std = @import("std");

    var value = State.init(.cleartype, .normal, 0, false);
    try std.testing.expectEqual(@as(u3, 4), value.bits);
    try std.testing.expect(value.beginIup(false));
    try std.testing.expectEqual(@as(u3, 5), value.bits);
    try std.testing.expect(value.beginIup(true));
    try std.testing.expect(value.postIup());
    try std.testing.expect(!value.beginIup(false));

    value.setGlyphInstructionControl(.cleartype, 4);
    try std.testing.expectEqual(@as(u3, 0), value.bits);
    value.beginGlyph(true);
    try std.testing.expectEqual(@as(u3, 0), value.bits);
    value.setGlyphInstructionControl(.cleartype, 0);
    try std.testing.expectEqual(@as(u3, 4), value.bits);

    try std.testing.expect(
        !State.init(.cleartype, .normal, 0, true).active(),
    );
    try std.testing.expect(
        !State.init(.cleartype, .mono, 0, false).active(),
    );
}
