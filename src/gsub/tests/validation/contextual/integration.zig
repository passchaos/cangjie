//! Contextual validation and low-level execution integration contracts.
//!
//! These tests bind the real recursive executor while entering validators and
//! subtable executors directly. They cover the intentional boundary between
//! reference-only record preflight, complete table validation, and compatible
//! class-based shaping behavior.

const std = @import("std");
const context_execution =
    @import("../../../execution/contextual/context/root.zig");
const chaining_class =
    @import("../../../execution/contextual/chaining/class/root.zig");
const records = @import("../../../execution/contextual/records/root.zig");
const support = @import("support.zig");
const table = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "contextual record references do not recursively validate lookup payloads" {
            var bytes = [_]u8{0} ** 120;
            writeContextWithTruncatedNestedLookup(&bytes);
            const rule_records: usize = 50;
            var view = table.View{
                .data = &bytes,
                .offset = 0,
                .length = bytes.len,
                .glyph_count = 10,
            };

            // Parse-time record preflight proves only lookup identity. The
            // whole-table pass remains responsible for recursively validating
            // the referenced lookup body exactly once.
            try records.validateReferences(
                Bindings.Executor,
                view,
                rule_records,
                1,
            );
            try std.testing.expectError(
                error.BadGsub,
                Bindings.validateTable(&bytes, 0, bytes.len, 10),
            );
            view.assume_validated = true;
        }

        test "class contextual execution ignores covered classes outside set arrays" {
            const allocator = std.testing.allocator;
            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 5);

            var context_bytes = [_]u8{0} ** 32;
            writeContextClassNoRules(&context_bytes, 1);
            var view = table.View{
                .data = &context_bytes,
                .offset = 0,
                .length = context_bytes.len,
            };
            try validation.contextual.context.validate(
                Bindings.Executor,
                view,
                0,
            );
            try context_execution.subtable(
                Bindings.Executor,
                view,
                0,
                &glyphs,
                allocator,
                0,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{5},
                glyphs.items,
            );

            support.writeClassDef1(&context_bytes, 18, 5, &.{0});
            try validation.contextual.context.validate(
                Bindings.Executor,
                view,
                0,
            );

            var chaining_bytes = [_]u8{0} ** 48;
            writeChainingClassNoRules(&chaining_bytes, 1);
            view = .{
                .data = &chaining_bytes,
                .offset = 0,
                .length = chaining_bytes.len,
            };
            try validation.contextual.chaining.validate(
                Bindings.Executor,
                view,
                0,
                .strict,
            );
            try chaining_class.subtable(
                Bindings.Executor,
                view,
                0,
                &glyphs,
                allocator,
                0,
                .{},
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{5},
                glyphs.items,
            );

            support.writeClassDef1(&chaining_bytes, 30, 5, &.{0});
            try validation.contextual.chaining.validate(
                Bindings.Executor,
                view,
                0,
                .strict,
            );
        }

        test "class contextual execution distinguishes required and optional ClassDefs" {
            const allocator = std.testing.allocator;
            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 5);

            var context_bytes = [_]u8{0} ** 26;
            writeContextClassNoRules(&context_bytes, 0);
            support.writeU16(&context_bytes, 4, 0);
            var view = table.View{
                .data = &context_bytes,
                .offset = 0,
                .length = context_bytes.len,
            };
            try std.testing.expectError(
                error.BadGsub,
                validation.contextual.context.validate(
                    Bindings.Executor,
                    view,
                    0,
                ),
            );
            try std.testing.expectError(
                error.BadGsub,
                context_execution.subtable(
                    Bindings.Executor,
                    view,
                    0,
                    &glyphs,
                    allocator,
                    0,
                    .{},
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{5},
                glyphs.items,
            );

            support.writeU16(&context_bytes, 4, 18);
            try validation.contextual.context.validate(
                Bindings.Executor,
                view,
                0,
            );
            try context_execution.subtable(
                Bindings.Executor,
                view,
                0,
                &glyphs,
                allocator,
                0,
                .{},
            );

            var chaining_bytes = [_]u8{0} ** 46;
            writeChainingClassNoRules(&chaining_bytes, 0);
            view = .{
                .data = &chaining_bytes,
                .offset = 0,
                .length = chaining_bytes.len,
            };
            // Backtrack and lookahead ClassDefs are optional.
            support.writeU16(&chaining_bytes, 4, 0);
            support.writeU16(&chaining_bytes, 8, 0);
            try validation.contextual.chaining.validate(
                Bindings.Executor,
                view,
                0,
                .strict,
            );
            try chaining_class.subtable(
                Bindings.Executor,
                view,
                0,
                &glyphs,
                allocator,
                0,
                .{},
            );

            // The input ClassDef drives set selection and is always required.
            support.writeU16(&chaining_bytes, 6, 0);
            try std.testing.expectError(
                error.BadGsub,
                validation.contextual.chaining.validate(
                    Bindings.Executor,
                    view,
                    0,
                    .strict,
                ),
            );
            try std.testing.expectError(
                error.BadGsub,
                chaining_class.subtable(
                    Bindings.Executor,
                    view,
                    0,
                    &glyphs,
                    allocator,
                    0,
                    .{},
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{5},
                glyphs.items,
            );
        }
    };
}

fn writeContextWithTruncatedNestedLookup(bytes: []u8) void {
    support.writeU16(bytes, 0, 1);
    support.writeU16(bytes, 4, 10);
    support.writeU16(bytes, 6, 12);
    support.writeU16(bytes, 8, 14);
    support.writeU16(bytes, 14, 2);
    support.writeU16(bytes, 16, 6);
    support.writeU16(bytes, 18, 40);

    support.writeU16(bytes, 20, 5);
    support.writeU16(bytes, 24, 1);
    support.writeU16(bytes, 26, 8);
    const context: usize = 28;
    support.writeU16(bytes, context, 1);
    support.writeU16(bytes, context + 2, 20);
    support.writeU16(bytes, context + 4, 1);
    support.writeU16(bytes, context + 6, 14);
    support.writeCoverage1(bytes, context + 20, &.{1});
    const set = context + 14;
    support.writeU16(bytes, set, 1);
    support.writeU16(bytes, set + 2, 4);
    const rule = set + 4;
    support.writeU16(bytes, rule, 1);
    support.writeU16(bytes, rule + 2, 1);
    support.writeRecord(bytes, rule + 4, 0, 1);

    const nested_lookup: usize = 54;
    support.writeU16(bytes, nested_lookup, 2);
    support.writeU16(bytes, nested_lookup + 4, 1);
    support.writeU16(bytes, nested_lookup + 6, 8);
    const nested = nested_lookup + 8;
    support.writeU16(bytes, nested, 1);
    support.writeU16(bytes, nested + 2, 10);
    support.writeU16(bytes, nested + 4, 1);
    support.writeU16(bytes, nested + 6, 0);
    support.writeCoverage1(bytes, nested + 10, &.{1});
}

fn writeContextClassNoRules(bytes: []u8, input_class: u16) void {
    support.writeU16(bytes, 0, 2);
    support.writeU16(bytes, 2, 12);
    support.writeU16(bytes, 4, 18);
    support.writeU16(bytes, 6, 1);
    support.writeU16(bytes, 8, 0);
    support.writeCoverage1(bytes, 12, &.{5});
    support.writeClassDef1(bytes, 18, 5, &.{input_class});
}

fn writeChainingClassNoRules(bytes: []u8, input_class: u16) void {
    support.writeU16(bytes, 0, 2);
    support.writeU16(bytes, 2, 16);
    support.writeU16(bytes, 4, 22);
    support.writeU16(bytes, 6, 30);
    support.writeU16(bytes, 8, 38);
    support.writeU16(bytes, 10, 1);
    support.writeU16(bytes, 12, 0);
    support.writeCoverage1(bytes, 16, &.{5});
    support.writeClassDef1(bytes, 22, 0, &.{0});
    support.writeClassDef1(bytes, 30, 5, &.{input_class});
    support.writeClassDef1(bytes, 38, 0, &.{0});
}
