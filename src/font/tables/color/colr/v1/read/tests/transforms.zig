//! Runtime coverage for every assigned COLR v1 transform Paint format.

const std = @import("std");

const paint = @import("../../paint/root.zig");
const support = @import("../../variation/tests/support.zig");
const transforms = @import("../transforms.zig");
const types = @import("../../types.zig");
const Context = @import("../types.zig").Context;

test "COLR v1 transform formats resolve affine matrices" {
    var bytes: [320]u8 = .{0} ** 320;
    const context = Context{ .normalized_coords = &.{}, .variation = null };
    const varied_context = Context{
        .normalized_coords = &.{1},
        .variation = .{ .store_offset = 240, .item_data_count = 1, .map = null },
    };
    const table = types.Table{ .offset = 0, .length = bytes.len };

    for (12..32) |raw_format| {
        @memset(&bytes, 0);
        support.writeItemVariationStoreWithItems(&bytes, 240, 10);
        const format: u8 = @intCast(raw_format);
        const info = paint.formatInfo(format).?;
        bytes[0] = format;
        support.writeU24(&bytes, 1, @intCast(info.min_size));
        bytes[info.min_size] = 2; // PaintSolid child.
        support.writeU16(&bytes, info.min_size + 1, 0);
        support.writeF2Dot14(&bytes, info.min_size + 3, 1);

        switch (format) {
            12, 13 => {
                support.writeU24(&bytes, 4, @intCast(info.min_size + 5));
                const matrix = info.min_size + 5;
                support.writeF16Dot16(&bytes, matrix + 0, 2);
                support.writeF16Dot16(&bytes, matrix + 4, 0);
                support.writeF16Dot16(&bytes, matrix + 8, 0);
                support.writeF16Dot16(&bytes, matrix + 12, 3);
                support.writeF16Dot16(&bytes, matrix + 16, 40);
                support.writeF16Dot16(&bytes, matrix + 20, 50);
                if (format == 13) support.writeU32(&bytes, matrix + 24, 0);
            },
            14, 15 => {
                support.writeI16(&bytes, 4, 40);
                support.writeI16(&bytes, 6, 50);
                if (format == 15) support.writeU32(&bytes, 8, 0);
            },
            16...23 => {
                support.writeF2Dot14(&bytes, 4, 0.5);
                if (format < 20) support.writeF2Dot14(&bytes, 6, 0.75);
                if (format == 18 or format == 19 or format == 22 or format == 23) {
                    const center: usize = if (format >= 20) 6 else 8;
                    support.writeI16(&bytes, center, 100);
                    support.writeI16(&bytes, center + 2, 200);
                }
                if ((format & 1) != 0) support.writeU32(&bytes, info.min_size - 4, 0);
            },
            24...27 => {
                support.writeF2Dot14(&bytes, 4, 0.5);
                if (format >= 26) {
                    support.writeI16(&bytes, 6, 100);
                    support.writeI16(&bytes, 8, 200);
                }
                if ((format & 1) != 0) support.writeU32(&bytes, info.min_size - 4, 0);
            },
            28...31 => {
                support.writeF2Dot14(&bytes, 4, 0.25);
                support.writeF2Dot14(&bytes, 6, 0);
                if (format >= 30) {
                    support.writeI16(&bytes, 8, 100);
                    support.writeI16(&bytes, 10, 200);
                }
                if ((format & 1) != 0) support.writeU32(&bytes, info.min_size - 4, 0);
            },
            else => unreachable,
        }

        const result = try transforms.transform(&bytes, table, 0, context);
        try std.testing.expectEqual(@as(usize, info.min_size), result.child.offset);
        switch (format) {
            12, 13 => {
                try std.testing.expectApproxEqAbs(@as(f32, 2), result.affine.xx, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 3), result.affine.yy, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 40), result.affine.dx, 0.0001);
            },
            14, 15 => {
                try std.testing.expectApproxEqAbs(@as(f32, 40), result.affine.dx, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 50), result.affine.dy, 0.0001);
            },
            16...23 => try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.affine.xx, 0.0001),
            24...27 => {
                try std.testing.expectApproxEqAbs(@as(f32, 0), result.affine.xx, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 1), result.affine.yx, 0.0001);
            },
            28...31 => try std.testing.expectApproxEqAbs(@as(f32, -1), result.affine.xy, 0.0001),
            else => unreachable,
        }
        if ((format & 1) != 0) {
            const varied = try transforms.transform(&bytes, table, 0, varied_context);
            try std.testing.expect(!std.meta.eql(result.affine, varied.affine));
        }
    }
}
