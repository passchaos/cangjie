//! OpenType SVG cleartext/gzip document envelope validation.

const std = @import("std");
const vort = @import("vort");

const document = @import("../document.zig");

test "gzip SVG payload validation checks stream integrity and decoded XML" {
    const valid = try vort.encodeGzipFixedAlloc(std.testing.allocator, "<svg><g/></svg>");
    defer std.testing.allocator.free(valid);
    try document.validate(std.testing.allocator, valid);

    const wrong_root = try vort.encodeGzipFixedAlloc(std.testing.allocator, "<g/>");
    defer std.testing.allocator.free(wrong_root);
    try std.testing.expectError(error.BadSfnt, document.validate(std.testing.allocator, wrong_root));

    const bad_crc = try std.testing.allocator.dupe(u8, valid);
    defer std.testing.allocator.free(bad_crc);
    bad_crc[bad_crc.len - 8] ^= 1;
    try std.testing.expectError(error.BadSfnt, document.validate(std.testing.allocator, bad_crc));

    const bad_isize = try std.testing.allocator.dupe(u8, valid);
    defer std.testing.allocator.free(bad_isize);
    bad_isize[bad_isize.len - 4] +%= 1;
    try std.testing.expectError(error.BadSfnt, document.validate(std.testing.allocator, bad_isize));

    try std.testing.expectError(error.BadSfnt, document.validate(std.testing.allocator, &.{ 0x1f, 0x8b, 0x08 }));

    // Vort consults ISIZE before allocation, so an advertised gzip bomb is
    // rejected by the 16 MiB SVG limit without attempting that allocation.
    const oversized = try std.testing.allocator.dupe(u8, valid);
    defer std.testing.allocator.free(oversized);
    std.mem.writeInt(u32, oversized[oversized.len - 4 ..][0..4], @intCast(document.max_document_size + 1), .little);
    try std.testing.expectError(error.BadSfnt, document.validate(std.testing.allocator, oversized));
}
