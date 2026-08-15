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
- **UAX #14 Unicode 17.0** provides the line-breaking model used here: a
  zero-allocation forward iterator backed by generated Unicode properties and
  bounded context state for numeric, quote, emoji, and Brahmic rules.
- **UAX #9 Unicode 17.0** provides exact paragraph embedding levels, isolate
  handling, weak/neutral resolution, paired-bracket behavior, mirroring, and
  per-line visual ordering.
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

- unicode-linebreak `v0.1.5` (`829adeed`), as the original compact iterator
  and state-table reference before the Unicode 17 rule upgrade
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

`src/unicode/line_break/iterator.zig` now owns Unicode line breaking:

- `lineBreaks(text)` validates UTF-8 and returns a zero-allocation iterator.
  Internal layout bypasses redundant validation only after its public shaping
  boundary has validated the same text.
- `lineBreakClassForCodepoint` performs a generated deduplicated-page lookup.
- The Unicode 17 state machine implements LB1 through LB31, including CRLF,
  ZWJ handling, regional indicators, East Asian quotation/parenthesis
  behavior, numeric expressions, emoji modifiers, Brahmic orthographic
  syllables, glue, and a mandatory end-of-text boundary.
- Generated property words combine `Line_Break`, the General_Category subset
  needed by contextual rules, `$EastAsian`, and `Extended_Pictographic`.
- All 19,338 official Unicode 17 `LineBreakTest.txt` cases run in the normal
  test suite; no tailorable or fallback rows are excluded.
- `itemizeLineBreaks` remains as an allocating compatibility collector, but new
  internal consumers should prefer the iterator.

Paragraph wrapping consumes this iterator through a one-item lookahead. It no
longer allocates a full line-break array.

Paragraph reflow is organized under `src/layout/line_break/reflow/` rather
than embedded in the shaping implementation:

- `root.zig` owns the greedy line-selection state machine.
- `opportunities.zig` maps streaming or retained Unicode opportunities onto
  shaped output while enforcing `unsafe-to-break`.
- `geometry.zig` owns line struts, alignment, indentation, tabs, spacing, and
  run ranges.
- `truncation.zig` owns line limits and plain-text ellipsis materialization.

`src/layout.zig` retains the public paragraph types and orchestration entry
points only. This keeps shaping, boundary selection, geometry, and truncation
independently testable without changing the `TextContext` surface.

`WordBreakDictionary` is the optional tailoring for mainstream scripts whose
orthography normally omits spaces:

- The public value is an opaque immutable handle constructed for Thai, Lao,
  Khmer, or Myanmar. Construction copies and validates UTF-8 words, rejects
  mixed-script and duplicate entries, and stores a Unicode-scalar trie.
- Dictionary segmentation uses dynamic programming over each matching script
  run. It first minimizes unknown grapheme clusters and then minimizes word
  count, preferring longer known words when coverage is equal.
- The resulting UTF-8 byte boundaries are merged with, rather than substituted
  for, UAX #14 opportunities. Unknown-only regions are not arbitrarily split
  into dictionary words.
- One-shot, retained, and styled paragraphs all consume the same
  `ParagraphOptions.word_break_dictionary`. Every candidate still passes
  grapheme and shaped `unsafe-to-break` checks before line wrapping.
- The dictionary is borrowed by `ParagraphOptions` and `ShapedParagraph`; it
  must outlive the layout call or retained paragraph. A retained paragraph
  rejects reflow with a different dictionary because its analyzed boundary
  set is width-independent retained state.

`src/unicode/grapheme/iterator.zig` now owns Unicode 17.0 extended grapheme
boundaries:

- `graphemeClusters(text)` validates UTF-8 and returns a zero-allocation
  iterator; already-validated internal paths use the matching assume-valid
  entry point.
- A generated, page-deduplicated property blob supplies
  `Grapheme_Cluster_Break`, `Indic_Conjunct_Break`, and
  `Extended_Pictographic` for all Unicode scalars.
- The state machine implements GB3 through GB13, including Hangul, GB9c Indic
  conjuncts, emoji ZWJ sequences, and regional-indicator pairing.
- The complete Unicode 17 `GraphemeBreakTest.txt` suite is embedded as a compact
  fixture and runs as part of `zig build test`.

OpenType source ownership is deliberately separate in
`src/unicode/grapheme/shaping_cluster.zig`. HarfBuzz's
`monotone_graphemes` behavior includes shaper-specific tailoring and is not a
caret-boundary API. USE shaping and parity normalization share this internal
layer, so upgrading public UAX #29 data does not silently change GSUB cluster
provenance.

`src/unicode/word/iterator.zig` independently implements Unicode 17.0 default
word boundaries:

- `wordSegments(text)` validates UTF-8 and streams every UAX #29 segment
  without allocation. Each result carries an `is_word` classification so
  punctuation and whitespace remain observable without becoming editor word
  stops.
- The generated property byte combines `Word_Break`,
  `Extended_Pictographic`, and a Unicode General_Category-based letter/number
  anchor. Dictionary-segmented scripts with `WB=Other` therefore remain
  identifiable as text without changing their default boundaries.
- The state machine covers WB3 through WB16, including ignored Format/Extend
  replacement, Hebrew quotes, decimal punctuation, Katakana, connectors,
  emoji ZWJ sequences, and regional-indicator pairing.
- `itemizeWordSegments` remains an explicitly documented compatibility
  tailoring for existing editor movement. It emits only selectable words and
  preserves established script-specific number/symbol grouping; standards
  consumers use the streaming API instead.
- All 1,944 cases from Unicode 17 `WordBreakTest.txt` run in the normal test
  suite.

`src/unicode/sentence/iterator.zig` completes the Unicode 17 default
segmentation layer:

- `sentenceSegments(text)` streams every UAX #29 sentence segment without
  allocation and validates UTF-8 at the public boundary.
- Generated `Sentence_Break` data drives SB3 through SB11, including CRLF and
  paragraph separators, Format/Extend replacement, decimal periods,
  uppercase abbreviation contexts, lowercase continuations, Unicode sentence
  terminators, closing punctuation, and trailing spaces.
- `itemizeSentenceSegments` remains the compatibility collector used by
  existing editor/debug APIs; it filters pure ASCII whitespace segments but
  otherwise preserves the standard boundaries.
- All 512 cases from Unicode 17 `SentenceBreakTest.txt` run in the normal test
  suite. Language-specific abbreviation dictionaries remain an explicit
  future tailoring rather than being guessed by the default iterator.

`src/unicode/bidi/` now owns the Unicode 17 bidirectional algorithm:

- `resolveBidiParagraph` decodes valid UTF-8 once and returns exact scalar
  `Bidi_Class` values, resolved embedding levels, source byte coordinates, and
  reusable per-line L1/L2 visual ordering.
- The resolver implements P2/P3, explicit embeddings/overrides and isolates
  (X1–X10), weak types (W1–W7), paired brackets and neutral types (N0–N2),
  implicit levels (I1/I2), line resets/reordering (L1/L2), and generated
  mirroring data (L4).
- Paragraph reflow resolves levels once for the complete logical paragraph,
  then applies line-local resets and visual order after wrapping. Explicit
  controls and isolates therefore keep paragraph context across line breaks.
- The former four-value `BidiClass` remains as a compatibility view for old
  callers. New analysis uses `ExactBidiClass`, `BidiBaseDirection`, and
  `BidiParagraph`.
- All 770,241 paragraph-level variants compiled from Unicode 17 `BidiTest.txt`
  and all 91,707 `BidiCharacterTest.txt` rows run in the normal test suite.

`WrapMode.no_wrap` is also enforced by reflow now: width does not introduce
soft lines, but mandatory Unicode line separators still do.

Soft hyphen now follows the mainstream discretionary-break contract. U+00AD is
kept as a zero-advance, invisible shaping atom when its opportunity is not
chosen. If reflow selects that UAX #14 boundary, the same source atom is
materialized with U+2010 from its owning font, falling back to U+002D and then
the font's U+00AD glyph. Its advance participates in break fitting, alignment,
justification, selection, and hit testing. Retained reflow restores the
invisible atom before every width change, and paragraph bidi preserves a
materialized X9 atom at the visual line end without inventing a new source
range. This is explicit soft-hyphen support, not language-specific automatic
hyphenation.

`TextAlign.justify` now provides portable inter-word and CJK inter-character
justification. Reflow first expands UAX #14 `SP` source atoms on non-terminal
soft-wrapped lines. If no expandable space exists, it distributes the remaining
width between adjacent Han/Kana/Hangul/Yi/Nushu source atoms. The conservative
CJK fallback excludes punctuation, nonstarters, combining output, and repeated
GSUB outputs for one source atom; language-specific punctuation compression and
hanging remain separate tailoring. Hard-break lines, final paragraph lines,
ellipsized terminal lines, tabs, non-breaking glue, unbounded layouts, and
lines without safe opportunities retain their natural width.
The expansion is stored in glyph advances, so rendering, hit testing,
selection geometry, bidi visual reordering, and debug overlays consume one
consistent layout result. Retained reflow restores pristine advances before
every width/alignment change, preventing justification from accumulating.
Arabic kashida insertion remains a separate future tailoring rather than being
guessed by the generic path.

Paragraph alignment distinguishes logical and physical edges:
`TextAlign.start`/`end` resolve through the paragraph direction, while
`left`/`right` always name physical edges. `start` is the default, preserving
the expected left edge for LTR and right edge for RTL without making it
impossible for a caller to request physical-left RTL text.

Automatic line metrics now aggregate the fonts and sizes that actually overlap
each line. The cascade's primary font remains a minimum line strut for empty
and fallback-only lines, while taller fallback ascenders, deeper descenders,
and larger line gaps expand only the visual lines that contain them. Soft and
hard line progression uses each preceding line's resolved height, so fallback
glyphs cannot overlap the next line or be clipped by primary-font-only
geometry. An explicit `line_height` remains a minimum line box rather than a
request to crop larger font metrics.

Attributed text now has a unified paragraph entry point instead of requiring
each style run to be laid out as an independent horizontal fragment. Normalized
style spans are intersected with script items, shaped through one font cascade,
and then share line breaking, per-line bidi ordering, alignment,
justification, hit testing, and selection geometry. Font size, language/script
tags, OpenType features, normalized variation coordinates, letter/word
spacing, and minimum line height are applied per span; visual style fragments
retain color, background, and decoration metadata for renderers. Font-family
name resolution remains a separate `FontDatabase` responsibility: the unified
entry consumes an already selected `FontCascade` and does not guess how a
family name maps to loaded font bytes.

`FontDatabase.layoutAttributedParagraphUtf8` is the integrated entry point for
callers that do want that resolution. It maps each normalized style run's
family, weight, stretch, and normal/italic/oblique request to a database face,
builds a coverage-aware fallback cascade for that run, and passes those
borrowed fonts into the same unified paragraph. Runs without an explicit
family inherit the caller's default query family. An explicit unknown family
is reported as `FontFamilyNotFound` rather than silently rendering through an
unrelated fallback family. The database and all fonts must outlive the returned
layout because font runs retain borrowed face pointers.

`ShapedParagraph` now implements the first width-independent paragraph
boundary. It owns source text plus pristine shaped glyph/run snapshots.
`ReflowBuffer` restores those snapshots before each layout, so different
widths, line limits, tabs, spacing, and ellipsis can be applied repeatedly
without another GSUB/GPOS pass and without accumulating mutations. Reflow
rejects direction, script, language, feature, or variation changes because
those options require reshaping.

`TextContext` is the public ownership boundary for this pipeline. It is an
opaque, heap-backed handle that owns reusable output/scratch arrays plus cmap,
metric, fallback, GDEF, GSUB/GPOS proof/plan, and optional whole-run caches.
`TextContext.Options` independently controls font-derived and whole-run
caching. Its concise
`shape`, `shapeWithFeatureRanges`, `shapeCascade`, `shapeScriptRuns`,
`shapeParagraph`, `layoutParagraph`, `layoutStyledParagraph`, and
`measureParagraph` methods replace public APIs that required callers to
construct several independent caches and write internal buffer pointers.
Returned run and layout slices borrow the context and remain valid until its
next shaping/layout call. Fonts must outlive the context, or the caller must
invoke `clearCaches` before destroying them.

Paragraph shaping now retains glyph atoms in logical source order and applies
bidi visual ordering only after line ranges are known. Each line builds its own
bidi map from `ParagraphLine.byte_start/byte_len`; mixed LTR/RTL text therefore
reorders independently when a width change creates different line boundaries.
This follows Parley's per-line ordering model while keeping standalone shaping
APIs in their existing HarfBuzz-compatible visual buffer order.

Font fallback is selected per extended grapheme/shaping cluster rather than per
scalar. The first cascade font covering every visible scalar owns the complete
cluster; variation-selector mappings are preferred explicitly, while join
controls and other default-ignorables do not require nominal cmap entries. If
no font fully covers the cluster, the base scalar's font retains the whole
sequence and missing continuation glyphs remain visible to diagnostics instead
of splitting marks or ZWJ sequences into unrelated font runs. A zero-allocation
grapheme iterator feeds this path; the common ASCII path keeps its direct
per-byte fallback/cache loop.

## Generated Data And Reproducibility

The Unicode 17 line-break property blob is generated with:

```sh
tools/unicode/line_break/generate_data.py \
  path/to/LineBreak.txt \
  path/to/UnicodeData.txt \
  path/to/EastAsianWidth.txt \
  path/to/emoji-data.txt \
  src/unicode/line_break/data.bin
```

The conformance fixture is generated separately:

```sh
tools/unicode/line_break/generate_conformance.py \
  path/to/LineBreakTest.txt \
  src/unicode/line_break/conformance.bin
```

Reference input SHA-256:

- `LineBreak.txt`:
  `e6a18fa91f8f6a6f8e534b1d3f128c21ada45bfe152eb6b1bcc5e15fd8ac92e6`
- `LineBreakTest.txt`:
  `e69884e0dde6a8724873f885d68c52dc14518abf9ae4ca9e2283b8773db3b752`
- `UnicodeData.txt`:
  `2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c`
- `EastAsianWidth.txt`:
  `ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33`
- `emoji-data.txt`:
  `2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b`

The generated property blob SHA-256 is
`0fef55798282a97581de58698c3617ee0990a52ff40342230fd083f6f881fa92`;
the 19,338-case conformance fixture SHA-256 is
`28e470fb325428ef1cb18b027b8889add6a18f7bf8046e34a986626b687a8ab9`.

The grapheme property blob is generated from Unicode 17.0.0:

```sh
tools/unicode/grapheme/generate_data.py \
  path/to/GraphemeBreakProperty.txt \
  path/to/emoji-data.txt \
  path/to/DerivedCoreProperties.txt \
  src/unicode/grapheme/data.bin
```

Reference input SHA-256:

- `GraphemeBreakProperty.txt`:
  `d6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89`
- `emoji-data.txt`:
  `2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b`
- `DerivedCoreProperties.txt`:
  `24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08`

The generated `data.bin` SHA-256 is
`a1530b138635e021e10089c713716b4c8135b9b9a159e8b8433381c70c744449`.
Each scalar uses one property byte before 256-byte pages are deduplicated.

The conformance fixture is generated separately:

```sh
tools/unicode/grapheme/generate_conformance.py \
  path/to/GraphemeBreakTest.txt \
  src/unicode/grapheme/conformance.bin
```

`GraphemeBreakTest.txt` SHA-256 is
`e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec`.
The resulting 766-case fixture SHA-256 is
`07053949345b67792108362e7b5146ae2d5467fef9de7fa5e7aa1dd3ddffbd56`.

The public state machine has one explicit Cangjie tailoring: U+0A4D, U+0CCD,
U+11046, U+110B9, and U+11442 remain InCB linkers to preserve established
cross-script caret atoms. This is intentionally documented and tested as a
tailoring rather than presented as Unicode 17's default property assignment.

The word-boundary data and fixture are generated separately:

```sh
tools/unicode/word/generate_data.py \
  path/to/WordBreakProperty.txt \
  path/to/emoji-data.txt \
  path/to/UnicodeData.txt \
  src/unicode/word/data.bin

tools/unicode/word/generate_conformance.py \
  path/to/WordBreakTest.txt \
  src/unicode/word/conformance.bin
```

Reference input SHA-256:

- `WordBreakProperty.txt`:
  `72274cac1e6b919507db35655c3e175aa27274668a1ece95c28d2069f2ad9852`
- `WordBreakTest.txt`:
  `1de23a75f37904abc7d206239ee8d34f8fdf0fb4ab32a7174dfbabbde25419b2`
- `emoji-data.txt`:
  `2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b`
- `UnicodeData.txt`:
  `2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c`

The generated word property blob SHA-256 is
`81c4e27d01e49c1aaf3f57b17bcc6e0576ecb1a9717f3f46ada32bc7481f3540`;
the 1,944-case conformance fixture SHA-256 is
`e390fd977570cd63aef4a1c657d4afefa188bfff5e8cc39e60942444feb5b674`.

Sentence-boundary data is generated with:

```sh
tools/unicode/sentence/generate_data.py \
  path/to/SentenceBreakProperty.txt \
  src/unicode/sentence/data.bin

tools/unicode/sentence/generate_conformance.py \
  path/to/SentenceBreakTest.txt \
  src/unicode/sentence/conformance.bin
```

Reference input SHA-256:

- `SentenceBreakProperty.txt`:
  `871c0c985ad95125e25b302414065a10839d068970bceb383ecec138f22a0a18`
- `SentenceBreakTest.txt`:
  `12cb47d028ded0c1cb8a28558f95479cbcd24559c46977015c82f3b50a1cc6e4`

The generated sentence property blob SHA-256 is
`c163eb450ba6df51a31fe2ac4a74e3c1d9d154c37ec9124af46dffce6a5844e8`;
the 512-case conformance fixture SHA-256 is
`ad12cc4dc33a16ffe0da235ac34cb8f0ddfc3c9e85a62c657ee88bb3beeba5cc`.

Unicode 17 bidi data and both official conformance suites are generated with:

```sh
tools/unicode/bidi/generate_data.py \
  path/to/DerivedBidiClass.txt \
  path/to/BidiBrackets.txt \
  path/to/BidiMirroring.txt \
  src/unicode/bidi/data.bin

tools/unicode/bidi/generate_conformance.py \
  path/to/BidiTest.txt \
  path/to/BidiCharacterTest.txt \
  src/unicode/bidi/conformance.bin
```

Reference input SHA-256:

- `DerivedBidiClass.txt`:
  `4867b4b7f0731ed1bfcd34cc6251211ff1542541fce0734b6fbda139ee80b3a4`
- `BidiBrackets.txt`:
  `dadbaf38a0d0246e5b805bf8725cb81b7c621f93d030595635f5ba2c2f179428`
- `BidiMirroring.txt`:
  `a2f16fb873ab4fcdf3221cb1a8a85a134ddd6ed03603181823ff5206af3741ce`
- `BidiTest.txt`:
  `888bdfc8090652272d1f859cdb00ae659e2dc6c26740be61ef1d03998a687620`
- `BidiCharacterTest.txt`:
  `a3e6e905ab5afbe318a96df5401d0372a04cd73ef139ab5e3cf0ae241c255488`

The generated property/bracket/mirror blob SHA-256 is
`9e9f9937100d6019f7308743916c3606bdb31c9cc4f142eb605becf45a210c3f`;
the 861,948-case fixture SHA-256 is
`40d4b9145779f8aad815e1f5ea5201ccd9cc5daeb73c8bf73b06c6f1c76d9a26`.

On a fixed-core mixed Latin/Arabic/Hebrew paragraph microbenchmark, the
compatibility `BidiMap` measured about `3.43 µs` versus `2.64 µs` for the
former coarse model. The additional work provides exact explicit controls,
isolates, weak/neutral resolution, bracket pairing, and levels rather than the
old run-direction approximation. Ordinary Persian shaping keeps its pure-RTL
non-allocating path; an unprofiled Amiri long-text run remained about
`796 ns/glyph` after the upgrade. Bidi analysis remains reusable paragraph
state so retained reflow does not resolve it once per visual line.

## Invariants

Future changes must preserve these rules:

- Public offsets are UTF-8 byte offsets and always land on scalar boundaries.
- Every non-empty valid text slice emits exactly one mandatory end-of-text
  boundary; empty text has no opportunities, matching unicode-linebreak.
- CRLF is one mandatory break opportunity after LF, never a break between CR
  and LF.
- Neither a UAX #14 opportunity nor an emergency wrap may divide a shaped
  boundary marked unsafe to break. The flag covers contextual substitutions
  and positioning relationships, including GPOS, legacy `kern`, and geometric
  fallback mark attachment.
- Emergency wrapping may split only at a grapheme/shaping-cluster boundary
  that is also safe for reuse of the retained shaped run.
- Reflow must be repeatable without re-running GSUB/GPOS once the
  width-independent paragraph representation exists.
- Bidi visual order is a line property. Logical source order and mappings must
  remain recoverable for caret movement and selection.
- Generated Unicode data carries a version and must be updated together with
  its conformance fixture.

## Next Structural Steps

1. Extend the existing HarfBuzz-compatible shaping-boundary flags only when a
   new portable shaping relationship can change retained-run reuse semantics.
2. Continue moving internal cache and scratch implementations under the
   `shaping/context` module boundary now that `TextContext` owns their public
   lifetime.
3. Add language-aware hyphenation as the next optional tailoring layer; keep
   dictionary segmentation and hyphenation outside the default UAX #14 state
   machine.
4. Add Arabic kashida and language-specific CJK punctuation
   compression/hanging where portable references exist, without changing the
   generic inter-word and inter-character contracts.
5. Benchmark analysis, shaping, and reflow separately. A faster micro-iterator
   does not by itself establish end-to-end superiority over reference engines.

The standalone iterator benchmark is:

```sh
zig build line-break-bench -Doptimize=ReleaseFast -- \
  --text-file path/to/utf8.txt --iterations 1000
```

The Unicode 17 implementation deliberately prioritizes current conformance over
the smaller Unicode 15 pair table it replaced. Fixed-core ReleaseFast A/B runs
against that previous implementation retained identical output on the measured
corpora but remained slower: about `5.1` versus `3.8 ns/byte` on the HarfBuzz
English word list, `6.4` versus `3.9 ns/byte` on punctuation-heavy English, and
`3.7` versus `1.2 ns/byte` on the HarfBuzz Hindi word list. A bounded
AL/HL/NU/CM run scanner removed most of the initial complex-script regression.
The remaining difference is a known cost of this implementation and a future
optimization target; it is not evidence that full Unicode 17 semantics require
that overhead. These figures are micro-iterator measurements, not claims about
paragraph or end-to-end layout performance.

Cangjie's constructor validates UTF-8, whereas references whose input type
already guarantees valid UTF-8 do not repeat that work. The benchmark therefore
reports checked and prevalidated iterator contracts separately.

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
