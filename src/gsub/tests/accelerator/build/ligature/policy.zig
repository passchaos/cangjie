//! Ligature accelerator prefilter cost-policy contracts.

const std = @import("std");
const ligature = @import("../../../../accelerator/build/ligature/root.zig");

test "ligature second prefilter counts competing definitions" {
    try std.testing.expect(!ligature.shouldPrefilterSecond(0));
    try std.testing.expect(!ligature.shouldPrefilterSecond(
        ligature.min_competing_for_prefilter - 1,
    ));
    try std.testing.expect(ligature.shouldPrefilterSecond(
        ligature.min_competing_for_prefilter,
    ));
    try std.testing.expect(ligature.shouldBuildRequiredSecondIndex(
        ligature.min_competing_for_required_second,
        true,
    ));
    try std.testing.expect(!ligature.shouldBuildRequiredSecondIndex(
        ligature.min_competing_for_required_second - 1,
        true,
    ));
    try std.testing.expect(!ligature.shouldBuildRequiredSecondIndex(
        ligature.min_competing_for_required_second,
        false,
    ));
}

test "small exact required-second policy is cardinality bounded" {
    try std.testing.expect(ligature.shouldBuildExactRequiredSecondIndex(
        true,
        1,
    ));
    try std.testing.expect(ligature.shouldBuildExactRequiredSecondIndex(
        true,
        ligature.max_exact_required_seconds,
    ));
    try std.testing.expect(!ligature.shouldBuildExactRequiredSecondIndex(
        true,
        0,
    ));
    try std.testing.expect(!ligature.shouldBuildExactRequiredSecondIndex(
        true,
        ligature.max_exact_required_seconds + 1,
    ));
    try std.testing.expect(!ligature.shouldBuildExactRequiredSecondIndex(
        false,
        1,
    ));
}
