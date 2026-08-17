//! Renderer-free diagnostic orchestration over a statically supplied shaper.

const std = @import("std");

const caret = @import("caret.zig");
const fallback = @import("fallback.zig");
const quality = @import("quality.zig");
const types = @import("types.zig");
const context_output = @import("../context/output.zig");
const font_fallback = @import("../fallback/font/root.zig");
const paragraph_options = @import("../../layout/paragraph/options.zig");
const paragraph_reflow = @import("../../layout/line_break/reflow/root.zig");
const shaping_plan = @import("../plan/root.zig");

pub fn clusterCaretConsistency(
    comptime Shaper: type,
    allocator: std.mem.Allocator,
    cascade: font_fallback.Cascade,
    text: []const u8,
    font_size: f32,
    options: shaping_plan.ShapeOptions,
) !types.ClusterCaretConsistencyReport {
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    _ = try Shaper.shapeUtf8CascadeWithOptions(
        cascade,
        &buffer,
        text,
        font_size,
        options,
    );
    try paragraph_reflow.build(
        &buffer,
        text,
        paragraph_options.Options{
            .max_width = std.math.inf(f32),
            .direction = options.direction,
        },
        paragraph_reflow.defaultBaselineMetrics(
            cascade.fonts[0],
            font_size,
        ),
        null,
        null,
        null,
        null,
    );
    paragraph_reflow.applyPendingJustification(&buffer);
    return try caret.analyze(
        allocator,
        text,
        buffer.paragraphLayout(),
    );
}

pub fn shapeQuality(
    comptime Shaper: type,
    allocator: std.mem.Allocator,
    cascade: font_fallback.Cascade,
    text: []const u8,
    font_size: f32,
    options: shaping_plan.ShapeOptions,
) !types.ShapeQualityReport {
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();

    const scripted = try Shaper.shapeUtf8ScriptRuns(
        cascade,
        &buffer,
        text,
        font_size,
        options,
    );
    const decisions = try fallback.analyze(allocator, cascade, text);
    defer allocator.free(decisions);
    return try quality.summarize(allocator, scripted, decisions);
}
