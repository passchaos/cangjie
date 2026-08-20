//! Paragraph-only source itemization around non-font atoms.
//!
//! Font shaping receives only ordinary UTF-8 ranges. Inline-object markers and
//! tabs retain source byte identity but are emitted by paragraph orchestration
//! as synthetic atoms, preventing cmap/GSUB/GPOS behavior from redefining
//! their layout contract.

const std = @import("std");

const inline_object = @import("../inline_object/root.zig");

pub const TextRange = struct {
    start: usize,
    end: usize,
};

pub const Item = union(enum) {
    text: TextRange,
    object: inline_object.Object,
    tab: usize,
};

/// Forward cursor over one validated paragraph source subrange.
pub const Cursor = struct {
    text: []const u8,
    objects: []const inline_object.Object,
    byte_index: usize,
    byte_end: usize,
    object_index: usize,

    pub fn init(
        text: []const u8,
        objects: []const inline_object.Object,
        byte_start: usize,
        byte_end: usize,
    ) Cursor {
        std.debug.assert(byte_start <= byte_end);
        std.debug.assert(byte_end <= text.len);
        var object_index: usize = 0;
        while (object_index < objects.len and
            objects[object_index].byte_index < byte_start)
        {
            object_index += 1;
        }
        return .{
            .text = text,
            .objects = objects,
            .byte_index = byte_start,
            .byte_end = byte_end,
            .object_index = object_index,
        };
    }

    pub fn next(self: *Cursor) ?Item {
        if (self.byte_index >= self.byte_end) return null;
        while (self.object_index < self.objects.len and
            self.objects[self.object_index].byte_index < self.byte_index)
        {
            self.object_index += 1;
        }
        const next_object =
            if (self.object_index < self.objects.len and
            self.objects[self.object_index].byte_index < self.byte_end)
                self.objects[self.object_index].byte_index
            else
                self.byte_end;
        const next_tab =
            std.mem.indexOfScalarPos(
                u8,
                self.text,
                self.byte_index,
                '\t',
            ) orelse self.byte_end;
        const boundary = @min(next_object, @min(next_tab, self.byte_end));

        if (self.byte_index < boundary) {
            const range = TextRange{
                .start = self.byte_index,
                .end = boundary,
            };
            self.byte_index = boundary;
            return .{ .text = range };
        }
        if (boundary >= self.byte_end) return null;

        if (boundary == next_object) {
            const object = self.objects[self.object_index];
            self.object_index += 1;
            self.byte_index =
                object.byte_index + inline_object.object_replacement_utf8.len;
            return .{ .object = object };
        }

        self.byte_index = boundary + 1;
        return .{ .tab = boundary };
    }
};

test "source cursor isolates tabs and objects without losing text" {
    const marker = inline_object.object_replacement_utf8;
    const text = "A\t" ++ marker ++ "B";
    const object = inline_object.Object{
        .id = 1,
        .byte_index = 2,
        .width = 1,
        .height = 1,
    };
    var cursor = Cursor.init(text, &.{object}, 0, text.len);
    try std.testing.expectEqual(
        Item{ .text = .{ .start = 0, .end = 1 } },
        cursor.next().?,
    );
    try std.testing.expectEqual(Item{ .tab = 1 }, cursor.next().?);
    try std.testing.expectEqual(Item{ .object = object }, cursor.next().?);
    try std.testing.expectEqual(
        Item{ .text = .{ .start = 5, .end = 6 } },
        cursor.next().?,
    );
    try std.testing.expect(cursor.next() == null);
}
