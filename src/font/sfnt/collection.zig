//! TrueType/OpenType Collection header and face-offset validation.

const bin = @import("../../binary.zig");
const record_mod = @import("record.zig");

pub const Error = record_mod.Error || error{EndOfStream};

pub const Header = struct {
    face_count: usize,
    header_length: usize,
    dsig_range: ?record_mod.Range = null,
};

pub fn parse(data: []const u8) Error!?Header {
    const tag = try bin.readU32At(data, 0);
    if (tag != 0x74746366) return null; // "ttcf"

    const version = try bin.readU32At(data, 4);
    const major = version >> 16;
    if (major != 1 and major != 2) return error.BadSfnt;

    const face_count: usize = @intCast(try bin.readU32At(data, 8));
    if (face_count == 0) return error.BadSfnt;
    if (data.len < 12 or face_count > (data.len - 12) / 4) {
        return error.BadSfnt;
    }

    // Face offsets immediately follow the fixed header. Version 2 appends one
    // collection-level DSIG descriptor; the complete metadata prefix is
    // reserved from every embedded SFNT face and table payload.
    var header_length = 12 + face_count * 4;
    var dsig_range: ?record_mod.Range = null;
    if (major == 2) {
        if (header_length > data.len or 12 > data.len - header_length) {
            return error.BadSfnt;
        }
        const dsig_tag = try bin.readU32At(data, header_length);
        const dsig_length = try bin.readU32At(data, header_length + 4);
        const dsig_offset = try bin.readU32At(data, header_length + 8);
        header_length += 12;

        if (dsig_tag == 0 and dsig_length == 0 and dsig_offset == 0) {
            // No collection signature.
        } else {
            if (dsig_tag != 0x44534947 or dsig_length == 0) {
                return error.BadSfnt;
            }
            const dsig_start: usize = @intCast(dsig_offset);
            const length: usize = @intCast(dsig_length);
            if (dsig_start < header_length or
                dsig_start > data.len or length > data.len - dsig_start)
            {
                return error.BadSfnt;
            }
            dsig_range = .{
                .start = dsig_start,
                .end = dsig_start + length,
            };
        }
    }

    for (0..face_count) |face_index| {
        const face_offset: usize = @intCast(try bin.readU32At(
            data,
            12 + face_index * 4,
        ));
        try validateFaceOffset(data.len, face_offset, header_length, dsig_range);
    }

    return .{
        .face_count = face_count,
        .header_length = header_length,
        .dsig_range = dsig_range,
    };
}

pub fn faceOffset(
    data: []const u8,
    header: Header,
    face_index: usize,
) Error!usize {
    if (face_index >= header.face_count) return error.BadSfnt;
    const offset: usize = @intCast(try bin.readU32At(
        data,
        12 + face_index * 4,
    ));
    try validateFaceOffset(
        data.len,
        offset,
        header.header_length,
        header.dsig_range,
    );
    return offset;
}

fn validateFaceOffset(
    data_len: usize,
    face_offset: usize,
    header_length: usize,
    dsig_range: ?record_mod.Range,
) Error!void {
    // An embedded face begins with a 12-byte SFNT offset table.
    if ((face_offset & 3) != 0 or face_offset < header_length) {
        return error.BadSfnt;
    }
    if (face_offset > data_len or 12 > data_len - face_offset) {
        return error.BadSfnt;
    }
    if (dsig_range) |dsig| {
        if (record_mod.overlaps(
            .{ .start = face_offset, .end = face_offset + 12 },
            dsig,
        )) {
            return error.BadSfnt;
        }
    }
}
