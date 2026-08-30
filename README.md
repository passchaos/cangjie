# Cangjie

Cangjie is a modern, cross-platform font and text processing stack for Zig
0.16. It combines SFNT font parsing, OpenType shaping, Unicode analysis,
paragraph layout, and CPU rasterization behind domain-oriented APIs:

- `cangjie.font` — font faces, outlines, containers, metadata, and databases
- `cangjie.text` — Unicode boundaries, bidi, scripts, styles, and OpenType tags
- `cangjie.shaping.Engine` — reusable shaping/layout state and font-derived caches
- `cangjie.shaping` — shaping requests, options, results, and diagnostics
- `cangjie.paragraph` — retained paragraphs, reflow, lines, and hit-test records
- `cangjie.render` — grayscale/color targets, rasterization, and draw lists
- `cangjie.debug` — optional dumps and diagnostic overlays

## Shape and rasterize

```zig
const cangjie = @import("cangjie");

var face = try cangjie.font.Face.parse(allocator, font_bytes);
defer face.deinit();

var engine = cangjie.shaping.Engine.init(allocator, .{});
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

## Retained styled paragraphs

Prepare styled text once when the same content will be laid out at more than
one width. The retained owner keeps independent text, span, shaping, and
glyph-metadata snapshots, while each layout view borrows its reflow buffer:

```zig
const text = "Hello, 世界";
const spans = [_]cangjie.paragraph.StyledSpan{
    .{
        .byte_start = 0,
        .byte_len = "Hello, ".len,
        .style_index = 0,
        .font_size = 24,
    },
    .{
        .byte_start = "Hello, ".len,
        .byte_len = "世界".len,
        .style_index = 1,
        .font_size = 32,
        .letter_spacing = 0.5,
    },
};

var paragraph = try engine.prepareStyledParagraph(cascade, .{
    .text = text,
    .default_font_size = 24,
    .spans = &spans,
    .options = .{ .max_width = 320 },
});
defer paragraph.deinit();

var reflow = cangjie.paragraph.StyledReflowBuffer.init(allocator);
defer reflow.deinit();

const narrow = try paragraph.layout(&reflow, .{ .max_width = 160 });
std.debug.assert(
    narrow.layout.glyphs.len == narrow.glyph_metadata.len,
);
// Copy either view before reusing `reflow`.
const intrinsic = try paragraph.contentWidths(.{ .max_width = 160 });
std.debug.assert(intrinsic.min <= intrinsic.max);
```

The retained paragraph deep-copies the source, span records, and the nested
face-pointer, feature, and variation-coordinate slices in each span. The faces
themselves and optional segmentation or hyphenation dictionaries remain
borrowed and must outlive the paragraph. Reflow may change geometry and line
policy, but shaping-affecting changes require preparing another paragraph.

See `docs/text-pipeline.md` for the shaping/reflow architecture and
`docs/font-containers.md` for owned web-font container loading.

Variable-font clients can bind one normalized location once and reuse it
across the common glyph views:

```zig
const instance = face.at(normalized_coords);
const bounds = try instance.glyphs().bounds(glyph_id);
const metrics = try instance.metrics().horizontal(glyph_id);
var outline = try instance.glyphs().outline(allocator, glyph_id);
defer outline.deinit();
```

The instance borrows both the face and coordinate slice. Raw `Face` views stay
available when an application intentionally changes location per query.

Generated canonical font bytes can move into the same owner without another
copy. For example, `subset.Result.intoOwnedFace()` transfers the subset program
into `font.container.OwnedFace`; `OwnedFace.adoptSfnt` provides the general
already-owned SFNT/TTC boundary. On parse failure the caller keeps ownership of
the original byte slice.

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
