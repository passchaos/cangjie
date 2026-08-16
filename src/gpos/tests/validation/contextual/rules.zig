//! ContextPos and ChainContextPos rule-child validation contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const table_core = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");

const Table = table_core.View;
const ensurePositionRuleSetWithin = validation.lookup.contextRuleSet;
const ensureChainingPositionRuleSetWithin = validation.lookup.chainingRuleSet;
const writeU16Test = fixture.writeU16;

test "GPOS ContextPos rejects null required rule offsets" {
    var bytes = [_]u8{0} ** 36;
    writeU16Test(&bytes, 8, 12); // LookupList offset for record preflight.
    writeU16Test(&bytes, 12, 0); // Empty LookupList; the repaired rule has no records.

    const rule_set = 20;
    writeU16Test(&bytes, rule_set + 0, 1); // One PosRule offset follows.
    writeU16Test(&bytes, rule_set + 2, 0); // Invalid: PosRule offsets are not nullable.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, ensurePositionRuleSetWithin(table, rule_set, 0));

    // A real rule may still be empty of positioning records; only the child
    // pointer itself must be non-null so the parser reads an actual PosRule.
    const rule = rule_set + 4;
    writeU16Test(&bytes, rule_set + 2, 4);
    writeU16Test(&bytes, rule + 0, 1); // GlyphCount includes the first covered glyph.
    writeU16Test(&bytes, rule + 2, 0); // PosCount.
    try ensurePositionRuleSetWithin(table, rule_set, 0);
}
test "GPOS ChainingContextPos rejects null required rule offsets" {
    var bytes = [_]u8{0} ** 40;
    writeU16Test(&bytes, 8, 12); // LookupList offset for record preflight.
    writeU16Test(&bytes, 12, 0); // Empty LookupList; the repaired rule has no records.

    const rule_set = 20;
    writeU16Test(&bytes, rule_set + 0, 1); // One ChainPosRule offset follows.
    writeU16Test(&bytes, rule_set + 2, 0); // Invalid: ChainPosRule offsets are not nullable.

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadGpos, ensureChainingPositionRuleSetWithin(table, rule_set, 0));

    // Minimal valid ChainPosRule: no backtrack, one input glyph (the covered
    // glyph), no lookahead, and no positioning records.
    const rule = rule_set + 4;
    writeU16Test(&bytes, rule_set + 2, 4);
    writeU16Test(&bytes, rule + 0, 0); // BacktrackGlyphCount.
    writeU16Test(&bytes, rule + 2, 1); // InputGlyphCount.
    writeU16Test(&bytes, rule + 4, 0); // LookaheadGlyphCount.
    writeU16Test(&bytes, rule + 6, 0); // PosCount.
    try ensureChainingPositionRuleSetWithin(table, rule_set, 0);
}
