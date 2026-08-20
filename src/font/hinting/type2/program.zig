//! Parsed Type2 stem and mask program shared by CFF and CFF2 hinting.
//!
//! Geometry remains in the ordinary charstring interpreter; these records
//! capture the state changes needed by a size-specific PostScript hint map.

const std = @import("std");
const params_mod = @import("params.zig");

pub const Axis = enum { horizontal, vertical };
pub const MaskKind = enum { hint, counter };

pub const Stem = struct {
    axis: Axis,
    min: f32,
    max: f32,
};

pub const Mask = struct {
    kind: MaskKind,
    path_command_index: usize,
    byte_start: usize,
    byte_len: u8,
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    stems: std.ArrayList(Stem) = .empty,
    masks: std.ArrayList(Mask) = .empty,
    mask_bytes: std.ArrayList(u8) = .empty,
    hint_params: params_mod.Params = .{},

    pub fn init(allocator: std.mem.Allocator) Program {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Program) void {
        self.mask_bytes.deinit(self.allocator);
        self.masks.deinit(self.allocator);
        self.stems.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn appendStems(
        self: *Program,
        axis: Axis,
        operands: []const f32,
    ) !void {
        if ((operands.len & 1) != 0) return error.InvalidHintOperands;
        var origin: f32 = 0;
        var index: usize = 0;
        while (index < operands.len) : (index += 2) {
            const delta = operands[index];
            const width = operands[index + 1];
            if (!std.math.isFinite(delta) or !std.math.isFinite(width)) {
                return error.InvalidHintOperands;
            }
            origin += delta;
            try self.stems.append(self.allocator, .{
                .axis = axis,
                .min = origin,
                .max = origin + width,
            });
            origin += width;
        }
    }

    pub fn appendMask(
        self: *Program,
        kind: MaskKind,
        path_command_index: usize,
        bytes: []const u8,
    ) !void {
        if (bytes.len > std.math.maxInt(u8)) return error.InvalidHintMask;
        const start = self.mask_bytes.items.len;
        try self.mask_bytes.appendSlice(self.allocator, bytes);
        errdefer self.mask_bytes.shrinkRetainingCapacity(start);
        try self.masks.append(self.allocator, .{
            .kind = kind,
            .path_command_index = path_command_index,
            .byte_start = start,
            .byte_len = @intCast(bytes.len),
        });
    }

    pub fn maskBytes(self: *const Program, mask: Mask) []const u8 {
        const end = mask.byte_start + mask.byte_len;
        std.debug.assert(end <= self.mask_bytes.items.len);
        return self.mask_bytes.items[mask.byte_start..end];
    }
};

test "Type2 program decodes relative stems and retains masks" {
    var program = Program.init(std.testing.allocator);
    defer program.deinit();
    try program.appendStems(.horizontal, &.{ 10, 20, 5, -4 });
    try std.testing.expectEqualSlices(Stem, &.{
        .{ .axis = .horizontal, .min = 10, .max = 30 },
        .{ .axis = .horizontal, .min = 35, .max = 31 },
    }, program.stems.items);
    try program.appendMask(.hint, 7, &.{0xa0});
    try std.testing.expectEqualSlices(
        u8,
        &.{0xa0},
        program.maskBytes(program.masks.items[0]),
    );
}
