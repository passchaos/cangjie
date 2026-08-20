//! Whole-table Script/LangSys feature-selection integration contracts.
//!
//! `Bindings` is supplied by `gsub.zig` at comptime so this suite covers the
//! root validation and selection surfaces without exporting test-only hooks.

const std = @import("std");
const fixture = @import("fixture.zig");
const unicode = @import("../../../../unicode.zig");

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB whole-table selection honors script language and fallback" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 160;
            fixture.writeScriptLanguageSelection(&bytes);

            const latin = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .latn },
            );
            defer allocator.free(latin);
            try std.testing.expectEqualSlices(u16, &.{0}, latin);

            const han_default = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .hani },
            );
            defer allocator.free(han_default);
            try std.testing.expectEqualSlices(u16, &.{1}, han_default);

            const han_japanese = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .hani, .language_tag = .jan },
            );
            defer allocator.free(han_japanese);
            try std.testing.expectEqualSlices(u16, &.{2}, han_japanese);

            const fallback = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .arab },
            );
            defer allocator.free(fallback);
            try std.testing.expectEqualSlices(u16, &.{3}, fallback);
        }

        test "vertical GSUB globally selects vert outside the active LangSys" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 84;
            fixture.writeGlobalVerticalSelection(&bytes);

            const horizontal = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .dflt },
            );
            defer allocator.free(horizontal);
            try std.testing.expectEqual(@as(usize, 0), horizontal.len);

            const vertical = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .dflt, .vertical = true },
            );
            defer allocator.free(vertical);
            try std.testing.expectEqualSlices(u16, &.{0}, vertical);

            const disabled = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{
                    .script_tag = .dflt,
                    .vertical = true,
                    .features = &.{
                        .{
                            .tag = unicode.tag("vert"),
                            .enabled = false,
                        },
                    },
                },
            );
            defer allocator.free(disabled);
            try std.testing.expectEqual(@as(usize, 0), disabled.len);
        }

        test "GSUB whole-table selection validates layout tag ordering" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 92;
            fixture.writeLayoutTagOrdering(&bytes);

            try Bindings.validate(&bytes, 0, bytes.len, 4);
            const selected = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .dflt },
            );
            defer allocator.free(selected);
            try std.testing.expectEqual(@as(usize, 0), selected.len);

            // Duplicate ScriptRecords preserve the first record rather than
            // changing the active script selection.
            fixture.writeU32(
                &bytes,
                18,
                @intFromEnum(unicode.OpenTypeScriptTag.dflt),
            );
            try Bindings.validate(&bytes, 0, bytes.len, 4);
            const duplicate = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .dflt },
            );
            defer allocator.free(duplicate);
            try std.testing.expectEqual(@as(usize, 0), duplicate.len);

            fixture.writeU32(&bytes, 18, unicode.tag("AAAA"));
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(&bytes, 0, bytes.len, 4),
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.selectedLookups(
                    &bytes,
                    0,
                    bytes.len,
                    allocator,
                    .{ .script_tag = .dflt },
                ),
            );
            fixture.writeU32(
                &bytes,
                18,
                @intFromEnum(unicode.OpenTypeScriptTag.hani),
            );

            fixture.writeU32(
                &bytes,
                34,
                @intFromEnum(unicode.OpenTypeLanguageTag.ara),
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validate(&bytes, 0, bytes.len, 4),
            );
            fixture.writeU32(
                &bytes,
                34,
                @intFromEnum(unicode.OpenTypeLanguageTag.kor),
            );

            // Font-load validation walks every FeatureRecord by index and
            // deliberately does not require tag ordering. Defensive runtime
            // selection validates that stronger lookup-oriented contract.
            fixture.writeU32(&bytes, 76, unicode.tag("aalt"));
            try Bindings.validate(&bytes, 0, bytes.len, 4);
        }

        test "GSUB required feature ignores optional disable overrides" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 72;
            fixture.writeRequiredFeatureSelection(
                &bytes,
                unicode.tag("ordn"),
                unicode.tag("liga"),
            );

            const lookups = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{
                    .script_tag = .dflt,
                    // ReqFeatureIndex remains mandatory. Overrides only disable
                    // optional FeatureIndex entries with the same tags.
                    .features = &.{
                        .{
                            .tag = unicode.tag("ordn"),
                            .enabled = false,
                        },
                        .{
                            .tag = unicode.tag("liga"),
                            .enabled = false,
                        },
                    },
                },
            );
            defer allocator.free(lookups);
            try std.testing.expectEqualSlices(u16, &.{0}, lookups);
        }

        test "GSUB whole-table selection canonicalizes repeated lookups" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 78;
            fixture.writeRepeatedLookupSelection(
                &bytes,
                unicode.tag("liga"),
            );

            const lookups = try Bindings.selectedLookups(
                &bytes,
                0,
                bytes.len,
                allocator,
                .{ .script_tag = .dflt },
            );
            defer allocator.free(lookups);
            try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, lookups);
        }
    };
}
