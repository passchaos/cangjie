# Cangjie

Cangjie is a modern, cross-platform font and text processing stack for Zig
0.16. It combines SFNT font parsing, OpenType shaping, Unicode analysis,
paragraph layout, and CPU rasterization behind domain-oriented APIs:

- `cangjie.font` — font faces, outlines, containers, metadata, and databases
- `cangjie.text` — Unicode boundaries, bidi, scripts, styles, and OpenType tags
- `cangjie.Engine` — reusable shaping/layout state and font-derived caches
- `cangjie.shaping` — shaping requests, options, results, and diagnostics
- `cangjie.paragraph` — retained paragraphs, reflow, lines, and hit-test records
- `cangjie.render` — grayscale/color targets, rasterization, and draw lists
- `cangjie.editor` — text buffers and editor-oriented helpers
- `cangjie.debug` — optional dumps and diagnostic overlays

## Shape and rasterize

```zig
const cangjie = @import("cangjie");

var face = try cangjie.font.Face.parse(allocator, font_bytes);
defer face.deinit();

var engine = cangjie.Engine.init(allocator, .{});
defer engine.deinit();

const run = try engine.shape(&face, .{
    .text = "Hello, 世界",
    .font_size = 32,
});

var target = try cangjie.render.GrayTarget.init(allocator, 640, 96);
defer target.deinit();

var rasterizer = cangjie.render.Rasterizer.init(allocator);
defer rasterizer.deinit();
try rasterizer.drawRun(&target, run, 16, 64);
```

Returned shaping and one-shot layout views borrow `Engine` storage and remain
valid until its next shaping or layout call. Parsed faces borrow their source
bytes. Faces and bytes must therefore outlive the engine, or the engine's
font-derived caches must be cleared before a face is destroyed.

See `docs/text-pipeline.md` for the shaping/reflow architecture and
`docs/font-containers.md` for owned web-font container loading.

## API organization

The facade intentionally has no deprecated aliases. Unicode APIs are grouped
under `text.bidi`, `text.segmentation`, `text.script`, `text.opentype`,
`text.style`, and `text.attributed`. Font inspection records are grouped under
`font.metadata.core`, `metrics`, `variations`, `color`, `layout`, `math`, and
`incremental`; AAT-specific records live one level deeper at
`font.metadata.layout.aat`.

Cangjie is a Zig source library, not a stable binary ABI. Public owners such as
`font.Face`, `Engine`, `font.database.Database`, and `render.Rasterizer` are
concrete value types. Their documented methods and records form the supported
source API; internal storage layout may evolve between versions. Pointers in
the API express borrowing and lifetime relationships, not opaque ABI handles.
