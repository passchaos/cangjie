# Text Analysis, Shaping, And Reflow Architecture

This document defines the target architecture for Cangjie's text stack. It is
not a claim that every stage has already reached the target. The first completed
slice is the Unicode line-break boundary layer and its streaming integration
with paragraph wrapping.

## Reference Designs

The design deliberately combines strengths from several implementations rather
than copying one API:

- **HarfBuzz** is the shaping-semantics reference. Its reusable shape plans,
  explicit segment properties, mutable scratch buffer, cluster invariants, and
  unsafe-to-break flags demonstrate that shaping is a bounded transformation of
  one homogeneous run—not a paragraph layout engine.
- **unicode-linebreak 0.1.5** provides the UAX #14 model used here: a
  zero-allocation forward iterator backed by a compressed Unicode property trie
  and generated pair-state table.
- **Parley** is the paragraph/reflow reference. Font-independent analysis,
  itemization, fallback, and shaping produce reusable paragraph content; line
  breaking, per-line bidi ordering, and alignment are later operations that can
  be repeated for a different width.
- **Swash** is the resource-lifetime and cluster reference. Immutable borrowed
  font data stays separate from reusable shaping/scaling contexts, caches, and
  scratch storage. Source ranges and boundary metadata survive cluster
  formation and glyph transformations.
- **FreeType and Fontations** reinforce the separation between font parsing,
  scaling/rasterization, shaping, and paragraph layout.

These references were inspected at:

- unicode-linebreak `v0.1.5` (`829adeed`)
- Parley `0cdb6d9`
- Swash `7773843`
- HarfBuzz `9f2f031`

## Required Pipeline

The long-term paragraph pipeline is:

1. **Decode and font-independent analysis**
   - Validate UTF-8 once.
   - Resolve scripts, bidi levels, grapheme/word/sentence boundaries, and
     UAX #14 line-break properties.
   - Preserve byte ranges as the stable public coordinate system.
2. **Itemization**
   - Split by bidi level, script, language, style, writing mode, and other
     shaping properties.
   - Keep common/inherited characters attached according to neighboring
     context rather than creating gratuitous runs.
3. **Font fallback**
   - Select fonts per shaping cluster, not per isolated scalar.
   - Preserve the original source range even if variation selectors,
     default-ignorables, or multiple scalars collapse into one glyph.
4. **Run shaping**
   - Shape one homogeneous item with a HarfBuzz-like cached plan and reusable
     scratch context.
   - Keep logical source metadata, cluster boundaries, and
     unsafe-to-break/unsafe-to-concatenate information through GSUB/GPOS.
5. **Width-independent paragraph**
   - Store shaped logical runs and cluster advances separately from final
     visual lines.
   - The output of this stage is reusable when only width, alignment, or line
     limits change.
6. **Reflow**
   - Consume UAX #14 opportunities and shaped cluster constraints.
   - Apply explicit breaks, wrapping policy, indentation, tabs, optional
     hyphenation, ellipsis, and justification.
   - Reorder bidi content per final line, not once for the entire paragraph.
7. **Presentation**
   - Produce line/run/glyph geometry for hit testing, selection, rendering, and
     accessibility without reparsing font tables.

The key boundary is that shaping never chooses visual lines, while line
breaking never performs OpenType substitution or positioning.

## Implemented First Slice

`src/text/line_break.zig` now owns Unicode line breaking:

- `lineBreaks(text)` validates UTF-8 and returns a zero-allocation iterator.
  Internal layout bypasses redundant validation only after its public shaping
  boundary has validated the same text.
- `lineBreakClassForCodepoint` performs a generated compressed-trie lookup.
- The pair-state table implements default UAX #14 behavior, including CRLF,
  ZWJ handling, regional indicators, East Asian punctuation, glue, and a
  mandatory end-of-text boundary.
- The generated data is Unicode 15.0.0 and records its version in the binary
  header.
- `itemizeLineBreaks` remains as an allocating compatibility collector, but new
  internal consumers should prefer the iterator.

Paragraph wrapping consumes this iterator through a one-item lookahead. It no
longer allocates a full line-break array. Grapheme clusters are still
materialized for emergency overflow fallback; replacing the project's
approximate grapheme implementation with a fully generated UAX #29 boundary
layer is a separate migration.

`WrapMode.no_wrap` is also enforced by reflow now: width does not introduce
soft lines, but mandatory Unicode line separators still do.

`ShapedParagraph` now implements the first width-independent paragraph
boundary. It owns source text plus pristine shaped glyph/run snapshots.
`ReflowBuffer` restores those snapshots before each layout, so different
widths, line limits, tabs, spacing, and ellipsis can be applied repeatedly
without another GSUB/GPOS pass and without accumulating mutations. Reflow
rejects direction, script, language, feature, or variation changes because
those options require reshaping.

## Generated Data And Reproducibility

The runtime table is generated from `unicode-linebreak 0.1.5`'s `tables.rs`:

```sh
tools/generate_line_break_data.py \
  path/to/unicode-linebreak-0.1.5/src/tables.rs \
  src/text/line_break_data.bin
```

Reference input:

- crates.io archive SHA-256:
  `3b09c83c3c29d37506a3e260c08c03743a6bb66a9cd432c6934ab501a190571f`
- `tables.rs` SHA-256:
  `1821b437dfb31164ce8180af3937ca42270f1edf963a2d2e41cbaaf999553c94`
- generated runtime blob SHA-256:
  `cac38551eb3dcbc798abeae2a675c7241f66722111d2d2081897c788bd77206b`

The conformance fixture is generated from Unicode
`LineBreakTest-15.0.0.txt`:

```sh
tools/generate_line_break_test_data.py \
  path/to/LineBreakTest.txt \
  src/text/line_break_test_data.bin
```

Reference input SHA-256:
`371bde4052aa593b108684ae292d8ea2dbb93c19990e0cdf416fa7239557aac3`.
The compact fixture SHA-256 is
`65a703330dde9d51c16b77ea5e23ac0c4965ac438c98cbf8d96d031fb1b807a5`.
It contains 6,424 default-algorithm cases. Like unicode-linebreak's upstream
runner, explicitly tailorable `[30.22]` and `[999.0]` cases are excluded.

## Invariants

Future changes must preserve these rules:

- Public offsets are UTF-8 byte offsets and always land on scalar boundaries.
- Every non-empty valid text slice emits exactly one mandatory end-of-text
  boundary; empty text has no opportunities, matching unicode-linebreak.
- CRLF is one mandatory break opportunity after LF, never a break between CR
  and LF.
- A soft line must not divide a shaped cluster marked unsafe to break.
- Emergency wrapping may split only at a grapheme/shaping-cluster boundary.
- Reflow must be repeatable without re-running GSUB/GPOS once the
  width-independent paragraph representation exists.
- Bidi visual order is a line property. Logical source order and mappings must
  remain recoverable for caret movement and selection.
- Generated Unicode data carries a version and must be updated together with
  its conformance fixture.

## Next Structural Steps

1. Extract generated UAX #29 grapheme analysis from `unicode.zig` and expose a
   streaming boundary API shared by shaping and emergency wrapping.
2. Move bidi visual reordering from whole-paragraph shaping to final lines.
3. Add explicit shaping-cluster safety flags modeled after HarfBuzz and merge
   them with UAX #14 opportunities.
4. Consolidate plan caches and transient arrays into reusable shaping/layout
   contexts, following HarfBuzz and Swash lifetime boundaries.
5. Add optional dictionary segmentation and hyphenation as tailoring layers;
   do not bake language-specific guesses into the default UAX #14 state
   machine.
6. Benchmark analysis, shaping, and reflow separately. A faster micro-iterator
   does not by itself establish end-to-end superiority over reference engines.

The standalone iterator benchmark is:

```sh
zig build line-break-bench -Doptimize=ReleaseFast -- \
  --text-file path/to/utf8.txt --iterations 1000
```

On the initial mixed-script 123-byte fixture, 100,000 iterations measured about
`2.26 ns/byte` for Cangjie's checked public constructor and about
`1.69 ns/byte` for its validated iterator-only path. An equivalent Release-mode
`unicode-linebreak 0.1.5` harness measured about `1.54–1.59 ns/byte`, with
identical break counts and checksums. Cangjie's constructor validates UTF-8,
whereas Rust's `&str` carries validity in its type; the benchmark reports both
contracts explicitly. Moving valid-scalar decoding to a branch-minimal hot path
improved the prior checked result by about 18%, but mixed-script iteration still
trails the reference slightly and must not be presented as an overall win.

Repeated reflow can be compared with the legacy shape-on-every-layout path:

```sh
zig build reflow-bench -Doptimize=ReleaseFast -- --iterations 10000
```

On the initial 39-glyph, four-width fixture, retained reflow measured about
`10.4x` faster than calling the complete shape-and-layout path for every width,
and about `3.0x` faster than the existing shaped-run cache path, with identical
glyph/line-count checksums. The retained paragraph caches both grapheme and
line-break analysis and restores directly into reusable output storage, so
repeated widths do not redo Unicode boundary work or cache lookup/copy setup.
This is an architectural workload win, not a claim that Cangjie's individual
shaping or line-breaking stages already outperform every external reference.
