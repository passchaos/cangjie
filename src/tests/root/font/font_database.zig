//! Integration coverage migrated from the former package root.

const std = @import("std");
const face_mod = @import("../../../font/face/root.zig");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const FontDatabase = support.FontDatabase;
const FontManifestEntry = support.FontManifestEntry;
const FontSource = support.FontSource;
const FontStyle = support.FontStyle;
const combinedSystemFontSourcesForOs = support.combinedSystemFontSourcesForOs;
const defaultSystemFontSourcesForOs = support.defaultSystemFontSourcesForOs;
const manifestEntryMatchesBytes = support.manifestEntryMatchesBytes;
const parseManifest = support.parseManifest;
const readManifestFile = support.readManifestFile;
const serializeManifest = support.serializeManifest;
const userFontSourcesForOs = support.userFontSourcesForOs;
const writeManifestFile = support.writeManifestFile;
const Font = support.Font;
const FontCascade = support.FontCascade;
const testing = support.testing;

test "matches font database faces by family weight and style" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const regular_bytes = try test_font.buildNamedTtfWithNames(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular");
    defer allocator.free(regular_bytes);
    const bold_italic_bytes = try test_font.buildNamedTtfWithNames(allocator, "Cangjie Sans", "Bold Italic", "Cangjie Sans Bold Italic");
    defer allocator.free(bold_italic_bytes);

    var regular = try Font.parse(allocator, regular_bytes);
    defer regular.deinit();
    var bold_italic = try Font.parse(allocator, bold_italic_bytes);
    defer bold_italic.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&regular);
    _ = try database.addFont(&bold_italic);

    try std.testing.expectEqual(@as(usize, 1), database.familyCount());

    const regular_match = database.match(.{ .family = "cangjie sans", .weight = 400, .style = .normal }).?;
    try std.testing.expectEqual(
        face_mod.backend.face(&regular),
        regular_match.face,
    );
    try std.testing.expectEqual(@as(u16, 400), regular_match.weight);
    try std.testing.expectEqual(FontStyle.normal, regular_match.style);

    const bold_match = database.match(.{ .family = "Cangjie Sans", .weight = 700, .style = .italic }).?;
    try std.testing.expectEqual(
        face_mod.backend.face(&bold_italic),
        bold_match.face,
    );
    try std.testing.expectEqual(@as(u16, 700), bold_match.weight);
    try std.testing.expectEqual(FontStyle.italic, bold_match.style);

    try std.testing.expect(database.match(.{ .family = "Missing Sans" }) == null);
}

test "enumerates font database families and faces" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const regular_bytes = try test_font.buildNamedTtfWithNames(allocator, "Enum Sans", "Regular", "Enum Sans Regular");
    defer allocator.free(regular_bytes);
    const bold_bytes = try test_font.buildNamedTtfWithNames(allocator, "Enum Sans", "Bold", "Enum Sans Bold");
    defer allocator.free(bold_bytes);
    const serif_bytes = try test_font.buildNamedTtfWithNames(allocator, "Enum Serif", "Regular", "Enum Serif Regular");
    defer allocator.free(serif_bytes);

    var regular = try Font.parse(allocator, regular_bytes);
    defer regular.deinit();
    var bold = try Font.parse(allocator, bold_bytes);
    defer bold.deinit();
    var serif = try Font.parse(allocator, serif_bytes);
    defer serif.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&regular);
    _ = try database.addFont(&bold);
    _ = try database.addFont(&serif);

    const families = try database.familyNames(allocator);
    defer allocator.free(families);
    try std.testing.expectEqual(@as(usize, 2), families.len);
    try std.testing.expectEqualStrings("Enum Sans", families[0]);
    try std.testing.expectEqualStrings("Enum Serif", families[1]);

    const sans_indices = try database.faceIndicesForFamily(allocator, "enum sans");
    defer allocator.free(sans_indices);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sans_indices);
    const missing_indices = try database.faceIndicesForFamily(allocator, "Missing");
    defer allocator.free(missing_indices);
    try std.testing.expectEqual(@as(usize, 0), missing_indices.len);

    const manifest = try database.manifest(allocator);
    defer FontDatabase.freeManifest(allocator, manifest);
    try std.testing.expectEqual(@as(usize, 3), manifest.len);
    try std.testing.expectEqualStrings("Enum Sans", manifest[0].family);
    try std.testing.expectEqualStrings("Regular", manifest[0].subfamily);
    try std.testing.expectEqualStrings("Enum Sans Regular", manifest[0].full_name);
    try std.testing.expectEqualStrings("EnumSans-Regular", manifest[0].postscript_name);
    try std.testing.expectEqual(@as(u16, 400), manifest[0].weight);
    try std.testing.expectEqual(@as(u16, 100), manifest[0].stretch);
    try std.testing.expectEqual(FontStyle.normal, manifest[0].style);
}

test "serializes font manifest entries with escaping" {
    const allocator = std.testing.allocator;
    const entries = [_]FontManifestEntry{
        .{
            .family = "Family\tOne",
            .subfamily = "Regular",
            .full_name = "Family\\One Regular",
            .postscript_name = "FamilyOne\nRegular",
            .weight = 400,
            .stretch = 100,
            .style = .normal,
        },
        .{
            .family = "Family Two",
            .subfamily = "Italic",
            .full_name = "Family Two Italic",
            .postscript_name = "FamilyTwo-Italic",
            .weight = 700,
            .stretch = 75,
            .style = .italic,
        },
    };
    const text = try serializeManifest(allocator, &entries);
    defer allocator.free(text);
    try std.testing.expectEqualStrings(
        "cangjie-font-manifest-v3\n" ++
            "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle\n" ++
            "Family\\tOne\tRegular\tFamily\\\\One Regular\tFamilyOne\\nRegular\t0\t0\t400\t100\tnormal\n" ++
            "Family Two\tItalic\tFamily Two Italic\tFamilyTwo-Italic\t0\t0\t700\t75\titalic\n",
        text,
    );

    const parsed = try parseManifest(allocator, text);
    defer FontDatabase.freeManifest(allocator, parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.len);
    try std.testing.expectEqualStrings("Family\tOne", parsed[0].family);
    try std.testing.expectEqualStrings("Family\\One Regular", parsed[0].full_name);
    try std.testing.expectEqualStrings("FamilyOne\nRegular", parsed[0].postscript_name);
    try std.testing.expectEqual(@as(u64, 0), parsed[0].content_hash);
    try std.testing.expectEqual(@as(u64, 0), parsed[0].content_size);
    try std.testing.expectEqual(@as(u16, 700), parsed[1].weight);
    try std.testing.expectEqual(@as(u16, 75), parsed[1].stretch);
    try std.testing.expectEqual(FontStyle.italic, parsed[1].style);

    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, "bad\n"));
}

test "font database manifest frees partial entries on allocation failure" {
    const allocator = std.testing.allocator;
    const bytes = try @import("../../../test_font.zig").buildNamedTtfWithNames(allocator, "OOM Manifest", "Regular", "OOM Manifest Regular");
    defer allocator.free(bytes);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontBytes(bytes);

    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 2 });
    try std.testing.expectError(error.OutOfMemory, database.manifest(failing.allocator()));
}

test "font manifest parser accepts CRLF line endings" {
    const allocator = std.testing.allocator;
    const text =
        "cangjie-font-manifest-v3\r\n" ++
        "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle\r\n" ++
        "CRLF Sans\tRegular\tCRLF Sans Regular\tCRLFSans-Regular\t0\t0\t400\t100\tnormal\r\n";
    const parsed = try parseManifest(allocator, text);
    defer FontDatabase.freeManifest(allocator, parsed);

    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqualStrings("CRLF Sans", parsed[0].family);
    try std.testing.expectEqual(FontStyle.normal, parsed[0].style);
}

test "font manifest parse errors free decoded fields" {
    const allocator = std.testing.allocator;
    const prefix =
        "cangjie-font-manifest-v3\n" ++
        "family\tsubfamily\tfull_name\tpostscript_name\tcontent_hash\tcontent_size\tweight\tstretch\tstyle\n";

    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\tnot-hex\t0\t400\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky\\x-Regular\t0\t0\t400\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t400\t100\tslant\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t0\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t1001\t100\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t400\t0\tnormal\n"));
    try std.testing.expectError(error.InvalidManifest, parseManifest(allocator, prefix ++
        "Leaky\tRegular\tLeaky Regular\tLeaky-Regular\t0\t0\t400\t1001\tnormal\n"));
}

test "writes and reads font manifest files" {
    const allocator = std.testing.allocator;
    const entries = [_]FontManifestEntry{.{
        .family = "Disk Family",
        .subfamily = "Regular",
        .full_name = "Disk Family Regular",
        .postscript_name = "DiskFamily-Regular",
        .content_hash = 0x1234,
        .content_size = 4096,
        .weight = 500,
        .stretch = 100,
        .style = .normal,
    }};

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try writeManifestFile(allocator, std.testing.io, tmp_dir.dir, "manifest.tsv", &entries);
    const parsed = try readManifestFile(allocator, std.testing.io, tmp_dir.dir, "manifest.tsv", .limited(1024 * 1024));
    defer FontDatabase.freeManifest(allocator, parsed);
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqualStrings("Disk Family", parsed[0].family);
    try std.testing.expectEqualStrings("DiskFamily-Regular", parsed[0].postscript_name);
    try std.testing.expectEqual(@as(u64, 0x1234), parsed[0].content_hash);
    try std.testing.expectEqual(@as(u64, 4096), parsed[0].content_size);
    try std.testing.expectEqual(@as(u16, 500), parsed[0].weight);
}

test "font database owns parsed font bytes and builds fallback cascades" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Owned Primary", "Regular", "Owned Primary Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Owned Fallback", "Regular", "Owned Fallback Regular");
    defer allocator.free(fallback_bytes);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontBytes(primary_bytes);
    _ = try database.addFontBytes(fallback_bytes);

    const primary = database.match(.{ .family = "Owned Primary" }).?;
    try std.testing.expectEqualStrings("Owned Primary", primary.family);

    const cascade_fonts = try database.buildCascadeForText(allocator, .{ .family = "Owned Primary" }, "ABA");
    defer allocator.free(cascade_fonts);
    try std.testing.expectEqual(@as(usize, 2), cascade_fonts.len);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(cascade_fonts), &layout_buffer, "ABA", 20);
    try std.testing.expectEqual(@as(usize, 3), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[2].font_index);
}

test "font database cascade construction rejects malformed UTF-8" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedTtfWithNames(allocator, "UTF8 Sans", "Regular", "UTF8 Sans Regular");
    defer allocator.free(bytes);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontBytes(bytes);

    const face_count = database.faces.items.len;
    // buildCascadeForText feeds text into Utf8Iterator for fallback discovery.
    // Reject malformed bytes rather than returning a truncated primary-only
    // cascade for the prefix before the invalid sequence.
    try std.testing.expectError(error.InvalidUtf8, database.buildCascadeForText(allocator, .{ .family = "UTF8 Sans" }, "A\xc3("));
    try std.testing.expectEqual(face_count, database.faces.items.len);

    try std.testing.expectError(error.InvalidUtf8, database.cascadeForText(allocator, .{ .family = "UTF8 Sans" }, "\xf0\x28\x8c\x28"));
}

test "font database deduplicates equivalent faces" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedTtfWithNames(allocator, "Dedupe Sans", "Regular", "Dedupe Sans Regular");
    defer allocator.free(bytes);

    var borrowed_a = try Font.parse(allocator, bytes);
    defer borrowed_a.deinit();
    var borrowed_b = try Font.parse(allocator, bytes);
    defer borrowed_b.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&borrowed_a));
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&borrowed_b));
    try std.testing.expectEqual(@as(usize, 1), database.faces.items.len);

    try std.testing.expectEqual(@as(usize, 0), try database.addFontBytes(bytes));
    try std.testing.expectEqual(@as(usize, 1), database.faces.items.len);
    try std.testing.expectEqual(@as(usize, 1), database.familyCount());

    var owned_database = FontDatabase.init(allocator);
    defer owned_database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try owned_database.addFontBytes(bytes));
    try std.testing.expectEqual(@as(usize, 0), try owned_database.addFontBytes(bytes));
    try std.testing.expectEqual(@as(usize, 1), owned_database.faces.items.len);
    try std.testing.expectEqual(@as(usize, 1), owned_database.familyCount());
    const owned_manifest = try owned_database.manifest(allocator);
    defer FontDatabase.freeManifest(allocator, owned_manifest);
    try std.testing.expect(owned_manifest[0].content_hash != 0);
    try std.testing.expectEqual(@as(u64, @intCast(bytes.len)), owned_manifest[0].content_size);
    try std.testing.expect(manifestEntryMatchesBytes(owned_manifest[0], bytes));
    try std.testing.expect(!manifestEntryMatchesBytes(owned_manifest[0], bytes[0 .. bytes.len - 1]));
}

test "font database uses PostScript names as stable duplicate ids" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const first_bytes = try test_font.buildNamedTtfWithPostScript(allocator, "PS Family A", "Regular", "PS Family A Regular", "SharedPS-Regular");
    defer allocator.free(first_bytes);
    const second_bytes = try test_font.buildNamedTtfWithPostScript(allocator, "PS Family B", "Regular", "PS Family B Regular", "SharedPS-Regular");
    defer allocator.free(second_bytes);

    var first_font = try Font.parse(allocator, first_bytes);
    defer first_font.deinit();
    var second_font = try Font.parse(allocator, second_bytes);
    defer second_font.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&first_font));
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&second_font));
    try std.testing.expectEqual(@as(usize, 1), database.faces.items.len);
    try std.testing.expectEqualStrings("SharedPS-Regular", database.faces.items[0].postscript_name);

    const matched = database.match(.{ .family = "", .postscript_name = "sharedps-regular" }).?;
    try std.testing.expectEqualStrings("PS Family A", matched.family);
    try std.testing.expect(database.match(.{ .family = "", .postscript_name = "MissingPS-Regular" }) == null);
}

test "font database ignores invalid PostScript names" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Invalid PS", "Regular", "Invalid PS Regular", "Bad Name");
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 0), try database.addFont(&font));
    try std.testing.expectEqual(@as(usize, 1), database.faces.items.len);
    try std.testing.expectEqualStrings("", database.faces.items[0].postscript_name);

    try std.testing.expect(database.match(.{ .family = "", .postscript_name = "Bad Name" }) == null);
    const matched = database.match(.{ .family = "Invalid PS" }).?;
    try std.testing.expectEqualStrings("Invalid PS", matched.family);
}

test "font database ingests all faces from a TTC collection" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildNamedTtc(allocator);
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(usize, 2), try Font.faceCount(bytes));

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 2), try database.addFontCollectionBytes(bytes));
    try std.testing.expectEqual(@as(usize, 0), try database.addFontCollectionBytes(bytes));
    try std.testing.expectEqual(@as(usize, 2), database.familyCount());

    const first = database.match(.{ .family = "Collection One" }).?;
    try std.testing.expectEqualStrings("Collection One", first.family);
    const second = database.match(.{ .family = "Collection Two" }).?;
    try std.testing.expectEqualStrings("Collection Two", second.family);
}

test "font database ingests font files from an Io directory" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const font_bytes = try test_font.buildNamedTtfWithNames(allocator, "File Sans", "Regular", "File Sans Regular");
    defer allocator.free(font_bytes);
    const collection_bytes = try test_font.buildNamedTtc(allocator);
    defer allocator.free(collection_bytes);

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "file.ttf", .data = font_bytes });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "collection.ttc", .data = collection_bytes });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFontFile(std.testing.io, tmp_dir.dir, "file.ttf", .limited(1024 * 1024));
    try std.testing.expectEqual(@as(usize, 2), try database.addFontCollectionFile(std.testing.io, tmp_dir.dir, "collection.ttc", .limited(1024 * 1024)));
    try std.testing.expectEqual(@as(usize, 3), database.familyCount());
    try std.testing.expect(database.match(.{ .family = "File Sans" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection One" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection Two" }) != null);
}

test "font database scans supported font files in a directory" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const font_bytes = try test_font.buildNamedTtfWithNames(allocator, "Scan Sans", "Regular", "Scan Sans Regular");
    defer allocator.free(font_bytes);
    const collection_bytes = try test_font.buildNamedTtc(allocator);
    defer allocator.free(collection_bytes);

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "scan.ttf", .data = font_bytes });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "collection.TTC", .data = collection_bytes });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "ignore.txt", .data = font_bytes });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 3), try database.scanFontDir(std.testing.io, tmp_dir.dir, .limited(1024 * 1024)));
    try std.testing.expectEqual(@as(usize, 3), database.familyCount());
    try std.testing.expect(database.match(.{ .family = "Scan Sans" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection One" }) != null);
    try std.testing.expect(database.match(.{ .family = "Collection Two" }) != null);
}

test "font database recursively scans supported font files" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const root_font = try test_font.buildNamedTtfWithNames(allocator, "Root Scan", "Regular", "Root Scan Regular");
    defer allocator.free(root_font);
    const nested_font = try test_font.buildNamedTtfWithNames(allocator, "Nested Scan", "Regular", "Nested Scan Regular");
    defer allocator.free(nested_font);

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.createDirPath(std.testing.io, "nested/deeper");
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "root.ttf", .data = root_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "nested/deeper/nested.OTF", .data = nested_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "nested/deeper/ignore.md", .data = nested_font });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    try std.testing.expectEqual(@as(usize, 2), try database.scanFontTree(std.testing.io, tmp_dir.dir, .limited(1024 * 1024)));
    try std.testing.expectEqual(@as(usize, 2), database.familyCount());
    try std.testing.expect(database.match(.{ .family = "Root Scan" }) != null);
    try std.testing.expect(database.match(.{ .family = "Nested Scan" }) != null);
}

test "font database scans configured font sources" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const flat_font = try test_font.buildNamedTtfWithNames(allocator, "Flat Source", "Regular", "Flat Source Regular");
    defer allocator.free(flat_font);
    const recursive_font = try test_font.buildNamedTtfWithNames(allocator, "Recursive Source", "Regular", "Recursive Source Regular");
    defer allocator.free(recursive_font);
    const file_font = try test_font.buildNamedTtfWithNames(allocator, "File Source", "Regular", "File Source Regular");
    defer allocator.free(file_font);

    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();
    try tmp_dir.dir.createDirPath(std.testing.io, "flat");
    try tmp_dir.dir.createDirPath(std.testing.io, "tree/deep");
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "flat/flat.ttf", .data = flat_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "tree/deep/recursive.ttf", .data = recursive_font });
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "direct.otf", .data = file_font });

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    const sources = [_]FontSource{
        .{ .directory = .{ .path = "flat", .recursive = false } },
        .{ .directory = .{ .path = "tree", .recursive = true } },
        .{ .file = .{ .path = "direct.otf" } },
        .{ .file = .{ .path = "missing.ttf", .ignore_missing = true } },
        .{ .directory = .{ .path = "missing", .recursive = true, .ignore_missing = true } },
    };
    try std.testing.expectEqual(@as(usize, 3), try database.scanFontSources(std.testing.io, tmp_dir.dir, &sources, .limited(1024 * 1024)));
    try std.testing.expect(database.match(.{ .family = "Flat Source" }) != null);
    try std.testing.expect(database.match(.{ .family = "Recursive Source" }) != null);
    try std.testing.expect(database.match(.{ .family = "File Source" }) != null);

    const ignored_unsupported = [_]FontSource{.{ .file = .{ .path = "notes.txt", .ignore_missing = true } }};
    try std.testing.expectEqual(@as(usize, 0), try database.scanFontSources(std.testing.io, tmp_dir.dir, &ignored_unsupported, .limited(1024 * 1024)));
    const strict_unsupported = [_]FontSource{.{ .file = .{ .path = "notes.txt", .ignore_missing = false } }};
    try std.testing.expectError(error.UnsupportedFontSource, database.scanFontSources(std.testing.io, tmp_dir.dir, &strict_unsupported, .limited(1024 * 1024)));
}

test "builds conservative default system font source lists" {
    const macos_sources = defaultSystemFontSourcesForOs(.macos);
    try std.testing.expectEqual(@as(usize, 2), macos_sources.len);
    try std.testing.expectEqualStrings("/System/Library/Fonts", macos_sources[0].directory.path);
    try std.testing.expect(macos_sources[0].directory.recursive);
    try std.testing.expect(macos_sources[0].directory.ignore_missing);
    try std.testing.expectEqualStrings("/Library/Fonts", macos_sources[1].directory.path);

    const linux_sources = defaultSystemFontSourcesForOs(.linux);
    try std.testing.expectEqual(@as(usize, 2), linux_sources.len);
    try std.testing.expectEqualStrings("/usr/share/fonts", linux_sources[0].directory.path);
    try std.testing.expectEqualStrings("/usr/local/share/fonts", linux_sources[1].directory.path);

    const windows_sources = defaultSystemFontSourcesForOs(.windows);
    try std.testing.expectEqual(@as(usize, 1), windows_sources.len);
    try std.testing.expectEqualStrings("C:\\Windows\\Fonts", windows_sources[0].directory.path);

    const unknown_sources = defaultSystemFontSourcesForOs(.freestanding);
    try std.testing.expectEqual(@as(usize, 0), unknown_sources.len);
}

test "builds user font source lists from a home path" {
    var source_buffer: [4]FontSource = undefined;
    var path_buffer: [256]u8 = undefined;

    const macos_sources = try userFontSourcesForOs("/Users/example", .macos, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 1), macos_sources.len);
    try std.testing.expectEqualStrings("/Users/example/Library/Fonts", macos_sources[0].directory.path);
    try std.testing.expect(macos_sources[0].directory.recursive);
    try std.testing.expect(macos_sources[0].directory.ignore_missing);

    const linux_sources = try userFontSourcesForOs("/home/example/", .linux, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 2), linux_sources.len);
    try std.testing.expectEqualStrings("/home/example/.local/share/fonts", linux_sources[0].directory.path);
    try std.testing.expectEqualStrings("/home/example/.fonts", linux_sources[1].directory.path);

    const windows_sources = try userFontSourcesForOs("C:\\Users\\example", .windows, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 0), windows_sources.len);
}

test "builds combined system and user font source lists" {
    var source_buffer: [8]FontSource = undefined;
    var path_buffer: [256]u8 = undefined;

    const macos_sources = try combinedSystemFontSourcesForOs("/Users/example", .macos, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 3), macos_sources.len);
    try std.testing.expectEqualStrings("/System/Library/Fonts", macos_sources[0].directory.path);
    try std.testing.expectEqualStrings("/Library/Fonts", macos_sources[1].directory.path);
    try std.testing.expectEqualStrings("/Users/example/Library/Fonts", macos_sources[2].directory.path);

    const linux_sources = try combinedSystemFontSourcesForOs("/home/example", .linux, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 4), linux_sources.len);
    try std.testing.expectEqualStrings("/usr/share/fonts", linux_sources[0].directory.path);
    try std.testing.expectEqualStrings("/usr/local/share/fonts", linux_sources[1].directory.path);
    try std.testing.expectEqualStrings("/home/example/.local/share/fonts", linux_sources[2].directory.path);
    try std.testing.expectEqualStrings("/home/example/.fonts", linux_sources[3].directory.path);

    const no_home_sources = try combinedSystemFontSourcesForOs(null, .linux, &source_buffer, &path_buffer);
    try std.testing.expectEqual(@as(usize, 2), no_home_sources.len);
}

test "uses OS/2 style attributes for database matching" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const regular_bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
    defer allocator.free(regular_bytes);
    const narrow_italic_bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 650, 3, true, false);
    defer allocator.free(narrow_italic_bytes);

    var regular = try Font.parse(allocator, regular_bytes);
    defer regular.deinit();
    var narrow_italic = try Font.parse(allocator, narrow_italic_bytes);
    defer narrow_italic.deinit();

    const attributes = try narrow_italic.styleAttributes();
    try std.testing.expectEqual(@as(u16, 650), attributes.weight);
    try std.testing.expectEqual(@as(u16, 3), attributes.width);
    try std.testing.expect(attributes.italic);
    try std.testing.expect(!attributes.bold);

    const os2 = (try narrow_italic.os2Info()).?;
    try std.testing.expectEqual(@as(u16, 4), os2.version);
    try std.testing.expectEqual(@as(u16, 650), os2.weight_class);
    try std.testing.expectEqual(@as(u16, 3), os2.width_class);
    try std.testing.expectEqual(@as(u16, 0x0001), os2.selection);
    try std.testing.expectEqual(@as(i16, 650), os2.subscript_x_size);
    try std.testing.expectEqual(@as(i16, 120), os2.subscript_y_offset);
    try std.testing.expectEqual(@as(i16, 0), os2.typo_ascender);
    try std.testing.expect(os2.code_page_ranges != null);
    try std.testing.expect(os2.x_height != null);
    try std.testing.expect(os2.lower_optical_point_size == null);

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&regular);
    _ = try database.addFont(&narrow_italic);

    const matched = database.match(.{ .family = "Metric Sans", .weight = 650, .stretch = 75, .style = .italic }).?;
    try std.testing.expectEqual(
        face_mod.backend.face(&narrow_italic),
        matched.face,
    );
    try std.testing.expectEqual(@as(u16, 650), matched.weight);
    try std.testing.expectEqual(@as(u16, 75), matched.stretch);
    try std.testing.expectEqual(FontStyle.italic, matched.style);
}

test "OS/2 info handles missing and borrowed mutated tables" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.os2Info()) == null);

    const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expect((try font.os2Info()) != null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var os2_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "OS/2")) os2_offset = table.offset;
    }
    bytes[os2_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.os2Info());
}

test "builds coverage-aware fallback cascades from the font database" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const primary_bytes = try test_font.buildNamedTtfWithNames(allocator, "Primary Sans", "Regular", "Primary Sans Regular");
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(allocator, 'B', "Fallback Sans", "Regular", "Fallback Sans Regular");
    defer allocator.free(fallback_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();

    var database = FontDatabase.init(allocator);
    defer database.deinit();
    _ = try database.addFont(&primary);
    _ = try database.addFont(&fallback);

    const cascade_fonts = try database.buildCascadeForText(allocator, .{ .family = "Primary Sans" }, "ABA");
    defer allocator.free(cascade_fonts);
    try std.testing.expectEqual(@as(usize, 2), cascade_fonts.len);
    try std.testing.expectEqual(@as(*const Font, &primary), cascade_fonts[0]);
    try std.testing.expectEqual(@as(*const Font, &fallback), cascade_fonts[1]);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const shaped = try TextShaper.shapeUtf8Cascade(FontCascade.init(cascade_fonts), &layout_buffer, "ABA", 20);
    try std.testing.expectEqual(@as(usize, 3), shaped.runs.len);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), shaped.runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 0), shaped.runs[2].font_index);
}
