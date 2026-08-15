# Cangjie

Cangjie is a modern, cross-platform font and text processing stack for Zig
0.16. It combines SFNT font parsing, OpenType shaping, Unicode analysis,
paragraph layout, and CPU rasterization behind domain-oriented APIs:

- `cangjie.font` — font faces, outlines, containers, metadata, and databases
- `cangjie.text` — Unicode boundaries, bidi, scripts, styles, and OpenType tags
- `cangjie.shaping` — reusable shaping context, requests, results, and fallback
- `cangjie.paragraph` — retained paragraphs, reflow, lines, and hit-test records
- `cangjie.render` — grayscale/color targets, rasterization, and draw lists
- `cangjie.editor` — text buffers and editor-oriented helpers
- `cangjie.debug` — optional dumps and diagnostic overlays

## Shape and rasterize

```zig
const cangjie = @import("cangjie");

var font = try cangjie.font.Font.parse(allocator, font_bytes);
defer font.deinit();

const context = try cangjie.shaping.Context.init(allocator, .{});
defer context.deinit();

const run = try context.shape(&font, .{
    .text = "Hello, 世界",
    .font_size = 32,
});

var target = try cangjie.render.GrayTarget.init(allocator, 640, 96);
defer target.deinit();

var rasterizer = cangjie.render.Rasterizer.init(allocator);
try rasterizer.renderRun(&target, run, 16, 64);
```

Returned shaping and one-shot layout views borrow `Context` storage and remain
valid until its next shaping or layout call. Parsed fonts borrow their source
bytes. Fonts and bytes must therefore outlive the context, or the context's
font-derived caches must be cleared before a font is destroyed.

See `docs/text-pipeline.md` for the shaping/reflow architecture and
`docs/font-containers.md` for owned web-font container loading.
