const std = @import("std");

pub const Reader = struct {
    data: []const u8,
    offset: usize = 0,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data };
    }

    pub fn seek(self: *Reader, offset: usize) !void {
        if (offset > self.data.len) return error.EndOfStream;
        self.offset = offset;
    }

    pub fn skip(self: *Reader, amount: usize) !void {
        try self.seek(self.offset + amount);
    }

    pub fn readU8(self: *Reader) !u8 {
        const bytes = try self.readBytes(1);
        return bytes[0];
    }

    pub fn readI8(self: *Reader) !i8 {
        return @bitCast(try self.readU8());
    }

    pub fn readU16(self: *Reader) !u16 {
        const bytes = try self.readBytes(2);
        return std.mem.readInt(u16, bytes[0..2], .big);
    }

    pub fn readI16(self: *Reader) !i16 {
        return @bitCast(try self.readU16());
    }

    pub fn readU32(self: *Reader) !u32 {
        const bytes = try self.readBytes(4);
        return std.mem.readInt(u32, bytes[0..4], .big);
    }

    pub fn readI32(self: *Reader) !i32 {
        return @bitCast(try self.readU32());
    }

    pub fn tag(self: *Reader) ![4]u8 {
        const b = try self.readBytes(4);
        return .{ b[0], b[1], b[2], b[3] };
    }

    pub fn readBytes(self: *Reader, len: usize) ![]const u8 {
        if (len > self.data.len - self.offset) return error.EndOfStream;
        const start = self.offset;
        self.offset += len;
        return self.data[start..self.offset];
    }
};

pub fn readU16At(data: []const u8, offset: usize) !u16 {
    if (offset + 2 > data.len) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

pub fn readI16At(data: []const u8, offset: usize) !i16 {
    return @bitCast(try readU16At(data, offset));
}

pub fn readU32At(data: []const u8, offset: usize) !u32 {
    if (offset + 4 > data.len) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

pub fn readI32At(data: []const u8, offset: usize) !i32 {
    return @bitCast(try readU32At(data, offset));
}

pub fn readTagAt(data: []const u8, offset: usize) ![4]u8 {
    if (offset + 4 > data.len) return error.EndOfStream;
    return .{ data[offset], data[offset + 1], data[offset + 2], data[offset + 3] };
}

pub fn tag(comptime text: []const u8) [4]u8 {
    if (text.len != 4) @compileError("SFNT tags must be four bytes");
    return .{ text[0], text[1], text[2], text[3] };
}

pub fn tagEq(a: [4]u8, comptime text: []const u8) bool {
    return std.mem.eql(u8, &a, text);
}
