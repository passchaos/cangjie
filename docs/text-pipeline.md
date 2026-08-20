# Text Analysis, Shaping, And Reflow Architecture

This document defines the target architecture for Cangjie's text stack and
records the module boundaries already implemented toward it. It is not a claim
that every stage has reached the target. Unicode line breaking and its
streaming paragraph integration were the first completed slice; shaping,
fallback, context ownership, and paragraph orchestration have since been split
into the domain modules described below.

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

## Implemented Architecture

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
- `cangjie.text.segmentation.collect.lineBreaks` is the allocating public
  counterpart. It preserves the iterator's complete opportunity stream and can
  optionally merge dictionary-tailored soft boundaries.

Paragraph wrapping consumes this iterator through a one-item lookahead. It no
longer allocates a full line-break array.

Paragraph reflow is organized under `src/layout/line_break/reflow/` rather
than embedded in the shaping implementation:

- `root.zig` is the narrow integration surface.
- `greedy.zig` owns single-line advancement, while `greedy/state.zig` owns
  persistent cursor and checkpoint records.
- `orchestration.zig` owns whole-layout greedy/balanced dispatch and probe
  storage without expanding the resumable state-machine module.
- `opportunities.zig` maps streaming or retained Unicode opportunities onto
  shaped output while enforcing `unsafe-to-break`.
- `geometry.zig` owns line struts, alignment, indentation, spacing, and run
  ranges.
- `truncation.zig` owns line limits and plain-text ellipsis materialization.

Paragraph-specific source atoms and rulers live with paragraph ownership:

- `source_items.zig` splits ordinary UTF-8 ranges from inline-object and tab
  markers before font shaping.
- `tabs.zig` owns explicit tab-ruler validation, synthetic markers, advance
  resolution, and repeating fallback intervals.

Paragraph request and ownership policy is organized under
`src/layout/paragraph/`:

- `options.zig` owns public paragraph options, validation, and the projection
  from paragraph controls to width-independent shaping controls.
- `retained.zig` owns `ShapedParagraph` and `ReflowBuffer`, including immutable
  source/shaping snapshots and repeatable reflow without another GSUB/GPOS
  pass.
- `vertical_columns.zig` owns physical RL/LR column progression;
  `vertical_wrap/` owns positive-down source-range selection and tab fields;
  focused block-metric, inline-alignment, and ellipsis modules keep those
  axis-specific transactions out of horizontal greedy reflow.
- `styled.zig` drives attributed shaping, fallback, metadata, reflow, and bidi
  over normalized style spans.
- `text_geometry/` builds an owned, platform-neutral view of final paragraph
  text runs. Its focused source, placement, and span stages keep bidi
  resolution, glyph-to-grapheme geometry, and flat output ownership separate.

The former aggregate layout compatibility façade has been removed. Public and
internal callers import result records, options, caches, diagnostics, shaping,
and paragraph operations from their owning domain modules rather than through
one aggregate implementation namespace.

Post-shaping bidi output reconstruction is similarly isolated under
`src/layout/bidi/reorder/`:

- `root.zig` selects whole-buffer, logical-normalization, or per-line policy.
- `mapping.zig` maps bidi scalars back to equal-cluster glyph output and
  applies visual mirroring through the glyph's owning cascade font.
- `runs.zig` rebuilds contiguous font runs and their output offsets after a
  glyph permutation.

Styled glyph metadata keeps its separate `styled_bidi` permutation sidecar;
ordinary shaping therefore does not pay for attributed-text state.

Public result records are separated from shaping algorithms under
`src/layout/types/`:

- `runs.zig` owns glyph runs, cascade runs, and scripted/shaped result views.
- `paragraph.zig` owns paragraph lines, metrics, hit testing, caret movement,
  and selection geometry.

The public façade groups these records under `cangjie.paragraph` and
`cangjie.shaping`, while implementation files import `layout/types/` directly.
Data-model methods therefore remain separate from OpenType shaping stages.

Ordinary shaping and paragraph entry-point orchestration live in
`src/shaping/orchestrator.zig`. This layer validates requests, selects
single-font or cascade shaping, coordinates script-run itemization and bidi
policy, and constructs retained, one-shot, styled, and measured paragraph
results. `src/shaping/text_shaper.zig` is the extended façade: it aliases the
ordinary operations and adds the uncommon UTF-8 byte-ranged GSUB feature path
without expanding every run-wide options record.

Reusable shaping-plan policy is grouped under `src/shaping/plan/`:

- `root.zig` owns `ShapeOptions`, plan identity, and plan-cache records.
- `validation.zig` validates UTF-8, sizes, feature overrides, and normalized
  variation coordinates at request boundaries.
- `resolution.zig` converts public options and inferred Unicode properties into
  homogeneous lookup options consumed by the segment pipeline.
- `bidi.zig` owns pure policy for standalone shaped-run and paragraph visual
  reordering.

Concrete context ownership is grouped under `src/shaping/context/`:

- `root.zig` exposes the source-level `Engine` owner and named request records.
- `state.zig` owns engine output and cache lifetimes and binds borrowed caches
  to each operation.
- `output.zig` owns reusable glyph, run, line, script-run, profiling, and
  scratch storage returned as borrowing views.
- `scratch.zig` owns the parallel transient arrays used by source mapping,
  GSUB, GPOS, attachment, cluster-safety, and final-output stages.
- `cache/` separates font metadata/proofs, lookup selection, glyph data,
  cascade-aware fallback, and fully owned shaped-run entries. Hashes are
  rejection filters; cache hits still compare the complete relevant identity,
  including ordered cascade pointers and shaped-run inputs.

This keeps the public owner concrete: callers hold an `Engine` value, returned
views borrow it until the next operation, and no opaque ABI handle or runtime
callback is required inside the source-level pipeline.

Portable ranges, locale identifiers, and presentation styles live in
`src/text/style/`; attributed UTF-8 ownership and standalone layout operations
live in `src/text/attributed/`. This replaces the former root-level core
aggregate, so font-independent style records and attributed orchestration have
separate module and test boundaries.

Cluster-safe fallback is grouped under `src/shaping/fallback/`:

- `font/root.zig` owns borrowed cascade identity and complete-cluster font
  selection, including variation-selector preference and default-ignorable
  coverage policy.
- `segment.zig` partitions ASCII or grapheme input into maximal same-font
  spans. It invokes a generic context's `appendSegment` method through Zig
  static dispatch, so the boundary adds neither a function pointer nor type
  erasure.
- `mark.zig` provides the separate geometric mark-fallback support used when
  portable font positioning is unavailable.

Arabic/Syriac stretch post-processing lives under
`src/shaping/features/stch/`:

- `actions.zig` records GSUB multiple-substitution provenance and maintains the
  lazy emitted-glyph action sidecar.
- `stretch.zig` measures fixed/repeating tiles in font units and expands them
  against neighboring word context.
- `root.zig` is the single positioning-stage integration surface.

Renderer-free analysis is organized under `src/shaping/diagnostics/`:

- `types.zig` owns the stable fallback, quality, and caret report records.
- `fallback.zig` traces the cluster-safe face and glyph decisions while
  preserving source spans and variation-selector semantics.
- `quality.zig` aggregates already-shaped font/script runs.
- `caret.zig` validates UTF-8 source spans and caret round trips.
- `orchestration.zig` composes shaping, paragraph geometry, and pure analysis
  through a comptime-supplied shaper type.

The public diagnostic API remains thin.
`src/api/shaping/root.zig` statically binds the ordinary shaper directly to the
diagnostic orchestrator; report storage and the diagnostic algorithms do not
depend on an aggregate layout façade or on runtime type erasure.

Optional presentation diagnostics are grouped under `src/debug/`:

- `overlays.zig` owns paragraph overlay records and geometry construction.
- `dumps.zig` formats Unicode, font coverage, shaping, paragraph, cache, and
  overlay state without owning those subsystems.
- `root.zig` is the small internal export surface, and `tests.zig` exercises
  the combined diagnostic workflow.

The first executable shaping stage is isolated under
`src/shaping/pipeline/source/`:

- `root.zig` decodes UTF-8 and establishes source/glyph cluster ownership.
- `buffer.zig` centralizes parallel source-sidecar appends.
- `support.zig` owns cmap, variation, presentation, and Arabic composition
  helpers.
- `thai_lao.zig` owns SARA AM decomposition and cluster merging.

The stage returns explicit run properties to the GSUB planner rather than
leaving cmap-local flags and temporary glyph state inside one monolithic
shaping function.

Shared GSUB infrastructure is grouped under `src/shaping/pipeline/gsub/`:

- `executor.zig` centralizes proof-aware, cached, ordered, and merged feature
  execution.
- `features.zig` normalizes public feature overrides into GSUB applications.
- `hangul.zig` owns Jamo source masks and cluster merging.
- `fraction.zig` owns source-scoped numerator/fraction/denominator masks.

Script shapers now share this small execution surface instead of duplicating
cache/proof branches inside the main segment function.

Script-specific GSUB orchestration is grouped under
`src/shaping/pipeline/gsub/shapers/`:

- `arabic/` separates Unicode joining-mask construction from Arabic, Syriac,
  Adlam, and Mongolian feature-stage ordering.
- `myanmar.zig`, `khmer.zig`, and `use.zig` own their source sidecars,
  dotted-circle insertion, stage observations, and post-GSUB reordering.
- `generic.zig` owns Hangul Jamo setup, AAT substitution selection, cached
  generic GSUB execution, and script-position features.
- `indic.zig` wraps generic execution with explicit source preparation and
  post-substitution Indic stages.

The shared executor now accepts a minimal allocator/lookup-cache context rather
than an implicit layout buffer. Script shapers therefore do not import
paragraph, line, or final-output state.

Final positioning is grouped under `src/shaping/pipeline/positioning/`:

- `collect.zig` owns GPOS option construction, cached lookup selection, table
  proof use, and the GPOS-versus-kerx engine decision.
- `engine.zig` plans AAT kerx, legacy kern, and geometric mark fallback after
  the table-level engine choice is known.
- `adjustments.zig`, `attachments.zig`, `policy.zig`, and `source_span.zig`
  own sparse adjustment lookup, attachment remapping, script/class policies,
  and public source extents respectively.
- `output/` converts font-unit adjustments into public glyph geometry, with
  separate Arabic cmap fallback, per-glyph geometry, and shared state records.

`src/shaping/pipeline/segment.zig` is the one-font execution boundary that
connects source mapping, normalization, GSUB, positioning, and final output.
It accepts resolved lookup properties and a concrete reusable output owner; it
does not choose fallback spans, paragraph lines, or bidi layout. Metric
fallback, attachment compaction, default-ignorable suppression, and glyph
construction remain delegated to the focused positioning modules above.
Shared resolved run properties live in `shaping/pipeline/types.zig`, so
pipeline stages do not import the paragraph/layout orchestrator.

After shaping, `src/shaping/itemization/script_runs.zig` maps glyph clusters
back onto Unicode script byte ranges and records stable script/language
metadata without moving that policy into the segment executor.

`WordBreakDictionary` is the optional tailoring for mainstream scripts whose
orthography normally omits spaces:

- The public value is a concrete immutable dictionary constructed for Thai, Lao,
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
- `cangjie.text.segmentation.collect.words` collects the same complete segment
  stream as the iterator; punctuation and whitespace remain present with
  `is_word = false`. Editor-only word-stop tailoring stays internal.
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
- `cangjie.text.segmentation.collect.sentences` collects the same complete
  segment stream as the iterator, including separator-only spans. Internal
  diagnostic helpers may apply their own presentation filtering.
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
- `cangjie.text.bidi.Class`, `BaseDirection`, and `Paragraph` expose the full
  UAX #9 model. The former coarse four-value classifier is no longer part of
  the public facade.
- All 770,241 paragraph-level variants compiled from Unicode 17 `BidiTest.txt`
  and all 91,707 `BidiCharacterTest.txt` rows run in the normal test suite.

`WrapMode.no_wrap` is also enforced by reflow now: width does not introduce
soft lines, but mandatory Unicode line separators still do.

Soft hyphen now follows the mainstream discretionary-break contract in both
horizontal lines and vertical columns. U+00AD remains invisible when its
opportunity is not chosen. Depending on the font's default-ignorable behavior,
shaping may retain a zero-advance atom or omit that output entirely. If reflow
selects the UAX #14 boundary, Cangjie therefore either materializes the atom or
inserts one source-owning glyph at the same UTF-8 range. U+2010 is preferred
from the owning font, with U+002D and the font's U+00AD glyph as fallbacks.
`hyphenation.character` requests an exact supported replacement independently
from automatic dictionary hyphenation.

The resolved glyph uses the current writing mode's orientation, advance, and
OpenType vertical origin. Its inline advance participates in greedy/balanced
break fitting, aligned tab fields, intrinsic sizing, alignment, selection, and
hit testing. Retained reflow restores the unselected shaping snapshot before
every width change; styled metadata, font runs, bidi order, ellipsis, and draw
output consume the same materialized result without inventing another source
range. This is explicit soft-hyphen support, not language-specific automatic
hyphenation.

The language-data layer for automatic hyphenation is implemented under
`src/text/hyphenation/`. `cangjie.text.hyphenation.Dictionary` parses the plain
Unicode Liang-pattern and exception format used by tex-hyphen/libhnj and
MuPDF's hyphen resources, copies it into an immutable scalar trie, and returns
UTF-8 byte boundaries. Left/right minimum fragments and owned one-to-one
Unicode normalization mappings are explicit construction options; no language
data, locale guess, or runtime callback is built into the library.

`ParagraphOptions.hyphenation` and
`ParagraphStyle.hyphenation` now tailor horizontal lines and vertical columns
with those boundaries. UAX #14 remains the default when its dictionary is null.
A selected automatic boundary resolves U+2010/U+002D/U+00AD through the
preceding cascade run, includes the current inline-axis advance while fitting,
and inserts one zero-source-length glyph only after all logical line/column
ranges have been chosen. The same policy can request another font-supported
Unicode scalar and cap immediately consecutive visible hyphenated lines or
columns; both settings are reflow-only and may change between layouts of one
retained paragraph.

Vertical automatic hyphens reuse explicit U+00AD's orientation, variable-font
instance, vertical-origin, tab-field, bidi, ellipsis, intrinsic-sizing, and
transactional run/metadata contracts. Greedy selection resets the consecutive
limit after an ordinary column; balanced DP carries that run length in its
state and applies the same hyphen and consecutive-hyphen penalties as
horizontal balancing. `word-break: break-all` suppresses automatic hyphen
materialization rather than drawing redundant continuation marks.
Run ownership, retained reflow, attributed metadata, bidi visual order, hit
testing, and selection therefore consume the same materialized result without
mutating the source text. Boundaries inside a shaped atom or marked unsafe to
break remain unavailable. Callers own language selection and dictionary
lifetime; Cangjie deliberately does not infer either from locale.

`TextAlign.justify` now provides portable inter-word and CJK inter-character
justification on horizontal lines and positive-down vertical columns. Reflow
first expands UAX #14 `SP` source atoms on non-terminal soft-wrapped fragments.
If no expandable space exists, it distributes the remaining inline measure
between adjacent Han/Kana/Hangul/Yi/Nushu source atoms. The conservative
CJK fallback excludes punctuation, nonstarters, combining output, and repeated
GSUB outputs for one source atom; language-specific punctuation compression and
hanging remain separate tailoring. Hard-break fragments, final paragraph
fragments, ellipsized terminal fragments, tabs, non-breaking glue, unbounded
layouts, and fragments without safe opportunities retain their natural size.
The expansion is stored in x or y glyph advances, so rendering, hit testing,
selection geometry, bidi visual reordering, and debug overlays consume one
consistent layout result. Retained reflow restores pristine advances before
every width/alignment change, preventing justification from accumulating.

`ParagraphOptions.punctuation.end_hanging_fraction` and the corresponding
`ParagraphStyle` policy optionally let East Asian closing, exclamation, and
nonstarter punctuation protrude from the logical inline-end margin on both
horizontal lines and vertical columns. Reflow uses the reduced occupied
measure for fitting, balanced badness, and alignment. After line-local bidi,
`ParagraphLine.hang_start`/`hang_end` record the physical inline side:
left/right horizontally and top/bottom vertically. Vertical positive-down
layout therefore writes line-end protrusion to `hang_end`, shortens occupied
`height`, and leaves the complete glyph/caret/selection advance below that box.
Glyph advances and source ranges remain unchanged, so rendering, TextGeometry,
retained reflow, attributed metadata, intrinsic inline sizing, tabs, ellipsis,
alignment, and paragraph metrics share one explicit optical geometry contract.
The default fraction is zero. Language-specific inter-punctuation compression
remains a separate, explicit policy.

`ParagraphOptions.punctuation.max_compression_fraction` adds a separate
CLREQ-style overfull-line stage. Eligible East Asian opening, closing,
exclamation, nonstarter, and infix punctuation contributes up to one half of
its glyph advance, scaled by the configured `0...1` limit. Compression first
uses adjacent punctuation gaps, then any remaining eligible side, and applies
only the minimum reduction needed to fit the already selected line. The
resulting advance/offset changes are explicit glyph geometry, so rendering,
caret, selection, bidi, retained reflow, attributed metadata, and ellipsis
remain synchronized. The default is zero.

The same compression policy operates on positive-down vertical inline
geometry. Capacity and fitting read `y_advance`; top-side compression raises
the glyph through shaping `y_offset`, bottom-side compression shortens only the
advance, and the final occupied `ParagraphLine.height` is recomputed after
column-local bidi. Greedy, emergency, and balanced selection plus intrinsic
inline sizing use the effective capacity without double-counting a terminal
glyph that also hangs. A selected overfull indivisible fragment is left
unchanged when its complete compression capacity cannot make it fit.

`ParagraphOptions.punctuation.convention` explicitly selects `.generic`, `.gb`,
`.cns`, or `.jis`; Cangjie does not infer it from locale or OpenType shaping
language. GB/T and JIS align comma/period/ideographic comma/colon/semicolon
blank space to the trailing side, while CNS splits that capacity across both
sides. GB additionally permits fullwidth question/exclamation compression;
CNS and JIS leave those glyphs uncompressed. East Asian brackets retain their
opening/closing edge alignment in all three regional conventions. The generic
default continues using Unicode line-break classes only.

Arabic justification now consumes the shaping surface's
`Glyph.isSafeToInsertTatweel()` evidence. Arabic-family joining nominates a
UTF-8 source boundary, and later GSUB/GPOS/kern/attachment safety clears that
nomination if insertion would interrupt shaping. On a non-terminal justified
line, Cangjie constructs a temporary copy of the visible logical source,
inserts real U+0640 scalars only at surviving boundaries, and reshapes the
complete line through its original cascade, size, features, variation
coordinates, and neighboring paragraph context. A candidate is adopted only
when it increases width without exceeding the selected measure; the remaining
space is then handled by generic space/CJK expansion.

Inserted glyphs report `Glyph.isKashida()` and remain anchored to the original
source boundary with zero source length. This keeps rendering, caret,
selection, style metadata, bidi, fallback runs, and retained reflow in one
coordinate space without changing the caller's UTF-8. Ordinary, retained, and
styled paragraph entry points share this transactional path. Hard-break,
terminal, ellipsized, inline-object, tab, and discretionary-hyphen lines retain
their existing behavior, and `ParagraphOptions.kashida` can disable or bound
the per-line insertion search. Cangjie never inserts an unshaped Tatweel glyph
into an already positioned run.

Font runs retain a range into their result owner's normalized-variation
coordinate pool. Shaped text, paragraph layouts, retained paragraphs, complete
shaped-run cache entries, attributed results, bidi-split runs, glyph draw lists,
and direct shaped-text rasterization all preserve that range. A renderer
therefore uses the same per-run fvar instance that supplied glyph selection,
GPOS, HVAR/VVAR advances, and line geometry; callers no longer have to repeat a
single paragraph-wide coordinate slice at the rendering boundary. Explicit
renderer-coordinate overrides remain available for low-level callers.

Direct grayscale, color, and hinted run rendering consume the complete
two-dimensional shaping pen. Each glyph is drawn at
`(pen.x + x_offset, pen.y - y_offset)` because OpenType/HarfBuzz offsets use
font-space positive-up Y while CPU render targets grow down; both `x_advance`
and `y_advance` then update the pen, including for non-rendering inline-object
atoms. Shaped-text rendering also applies both `CascadeRun.x_offset` and
`CascadeRun.y_offset`, so vertical fallback runs continue one column rather
than collapsing onto the first glyph.

`Glyph.orientation` records final `.horizontal`, `.upright`, or `.sideways`
geometry without increasing the compact 48-byte positioned-glyph record.
Explicit `text-orientation: upright`/`sideways` applies to every vertical
glyph; mixed orientation follows CSS Writing Modes by keeping U, Tu, and Tr
upright and rotating UAX #50 R glyphs 90 degrees clockwise. The renderer
rotates each sideways outline, color layer, or post-hinting pixel outline
around its shaping origin before advancing the unchanged two-dimensional pen,
so Latin and CJK can share one vertical run without rotating the whole column.
Vertical `x_offset`/`y_offset` also now carry HarfBuzz's actual
`-v_origin_x/-v_origin_y` values rather than renderer-specific positive
origins. Grayscale, color, and hinted renderers therefore consume the same
public offset contract, and parity tools no longer reconstruct ordinary
vertical origins out of band.

Paragraph layout now admits vertical writing through
`ParagraphOptions.writing_mode` and `text_orientation`. `max_width` is the
inline-size/column-height measure. Greedy `.word` wrapping applies global
`word_break` (`normal`, `break_all`, or `keep_all`) and `overflow_wrap`
(`normal`, `break_word`, or `anywhere`) policy to reusable UAX #14 boundaries.
An optional `WordBreakDictionary` adds language-authored boundaries for Thai,
Lao, Khmer, or Myanmar before that same policy and shaped-output safety filter.
UTF-8 `line_break_policy_ranges` and attributed-span overrides may tailor the
three wrapping properties locally; a candidate belongs to the preceding source
scalar, matching horizontal reflow. Emergency modes fall back to
extended-grapheme boundaries that also pass the shaper's `unsafe-to-break`
contract, and a local `.no_wrap` or `.normal` span defers emergency wrapping
until a later range permits it. A global `.no_wrap` keeps only hard breaks
unless a range explicitly re-enables wrapping. Dictionary analysis is retained
for repeated reflow and intrinsic inline-size measurement; greedy, balanced,
plain, and styled vertical layout consume the same opportunity stream.
`vertical_rl` places source-order columns from right to left, while
`vertical_lr` places them left to right. This block progression is independent
from HarfBuzz-style BTT, which remains an inline-direction request rather than
a CSS writing mode. Paragraph hit testing, caret/selection rectangles, owned
`TextGeometry`, debug overlays, and renderer draw lists all consume the same
y-axis pen. Public draw-list glyphs therefore retain `y_advance` and
orientation rather than flattening paragraph output back to horizontal
coordinates.

Flow-axis paragraph spacing is shared across horizontal and vertical layout.
`first_line_indent` reserves inline space before the first visual line of each
hard-break segment—physical x horizontally and positive-down y vertically.
Soft wraps do not reset it. `paragraph_spacing` appears only between explicit
hard-break segments—physical y horizontally and block-axis x vertically—and
therefore mirrors with `vertical_rl` versus `vertical_lr`. Both values affect
final layout/interaction geometry but not min/max-content intrinsic inline
sizes.

Paragraph alignment is also inline-axis aware. With top-to-bottom flow,
vertical `.start`, `.center`, and `.end` place each column at top, center, or
bottom of its post-indent `max_width` region; bottom-to-top flow mirrors
start/end to bottom/top. Every soft column resolves independently; hard-break
segments reset indentation before alignment. Overfull and unbounded columns
remain at logical start rather than moving backward. Columns containing active
absolute tab rulers are pinned to `.start`, matching horizontal tab-ruler
behavior. Physical `.left` / `.right` remain explicitly unsupported for
vertical paragraphs because they require separate block-axis semantics.
`.justify` is supported independently as inline-axis expansion along
positive-down y.

`max_lines` limits vertical output to a source-order column prefix. Glyphs,
font runs, line ranges, positioned objects, and attributed metadata are
truncated together; `max_lines = 0` produces an empty visible paragraph.
Physical RL/LR column placement is recomputed after truncation, so omitted
columns reserve no block width. Retained reflow can restore the full paragraph,
and min/max-content intrinsic widths remain independent from the visibility
limit. When `ellipsis` is enabled and a nonempty visible prefix omits later
columns, three synthetic periods are resolved through the terminal source
style's cascade, size, and variation instance, then fitted along positive-down
y. Upright dots use vertical metrics and origins; sideways dots use horizontal
advance while retaining vertical-origin placement. Terminal tab fields,
start/center/end alignment, run ownership, in-flow object block extent,
attributed metadata, and retained restoration are recomputed after fitting. An
omitted empty terminal column after a trailing hard break still counts as
truncation. `max_lines = 0` remains empty rather than emitting a standalone
ellipsis.

In-flow U+FFFC inline objects also use physical dimensions through the current
flow axes. `Object.width` is horizontal inline advance but vertical column
block extent; `Object.height` is horizontal line extent but vertical
positive-down inline advance. Vertical objects are centered inside the final
column width and positioned at the current y pen. They participate in safe
wrapping, caret/selection and owned TextGeometry, retained geometry-only
reflow, attributed metadata, and renderer object draw commands without
acquiring font-run ownership. Ordinary `.out_of_flow` objects also produce a
source-anchor fallback at the current column y pen while their marker keeps
zero inline/block occupancy; paint bounds may extend beyond paragraph metrics.
`.custom_out_of_flow` uses the same zero-occupancy fallback anchor and accepts
absolute `out_of_flow_placements` as presentation-only paint geometry.
Retained reflow and styled layout may replace those bounds without changing
column selection, paragraph metrics, or intrinsic inline sizes. The concrete
`OutOfFlowResolver` therefore supports placement-only vertical replay, and
objects removed by `max_lines` neither render nor request placement. Optional
resolver exclusions participate in vertical LR/RL reflow through the same static
rectangle pipeline as caller-authored exclusions.

This is intentionally not described as full vertical reflow. Bottom-to-top
`direction = rtl` is supported as the UAX #9 base direction and logical
inline-start/end policy while final glyphs remain in physical top-to-bottom
order. Physical left/right paragraph alignment remains rejected because it
names block-axis geometry rather than inline alignment.
Retained whole-paragraph layout and intrinsic inline-size measurement are
supported and restore the pristine vertical shaping snapshot between calls.
Returning a concrete
`UnsupportedVerticalParagraphOptions` error is part of this boundary: an
unsupported request must never fall through the horizontal x-axis machinery
and produce plausible but false geometry.

Vertical Unicode-space fallback follows the library's public positive-down
`y_advance` convention, including synthesized U+2000..U+200A/U+202F/U+205F/
U+3000 lengths. The HarfBuzz parity adapter converts those final advances back
to negative font-space output; ordinary glyphs still use their authored vmtx
oracle. This keeps wrapping, rendering, and parity from assigning opposite pen
directions to the same space glyph.

Before discrete Kashida or spacing expansion, a justified non-terminal line
may also reshape through one variable-font expansion axis. Cangjie prefers an
fvar `jstf` axis (the convention used by HarfBuzz's experimental API), then the
registered `wdth` axis; this is not an implementation of the unrelated
OpenType `JSTF` table. A bounded F2Dot14 search accepts only shapes that widen
the line without crossing its target. The selected per-run coordinates travel
with the committed line into retained/styled output and rendering, while any
remaining width proceeds through Kashida and then ordinary space/CJK
expansion. Multi-font or shaping-style-spanning lines conservatively skip the
axis stage rather than imposing one font's axis on another run.

The actual OpenType `JSTF` table is parsed and exposed independently
through `font.metadata.layout.inspect(face).justification(allocator)`.
Validation covers ordered script/language records, extender glyph bounds,
priority arrays, sorted GSUB/GPOS modification indexes cross-checked against
the corresponding LookupLists, and embedded JstfMax GPOS lookup payloads.
Inspection returns owned scripts, default/tagged language systems, priority
lists, lookup indexes, and maximum-lookup descriptors.

Paragraph justification consumes each priority's extension-side GSUB/GPOS
enable and disable lists as well as its `extensionJstfMax` positioning lookups.
Every priority starts from untouched source text. Cangjie merges enabled
lookups with generic GSUB and GPOS active plans, preserves value-aware feature
state, suppresses disabled lookups even inside contextual dispatch, and
reassembles each modified plan in LookupList order before execution. Cached
base selections remain immutable. Script-specific GSUB retains its required
feature stages and reordering; disabled indexes are guarded at every stage,
while enabled indexes not reached by those stages execute after the shaper has
established joining or syllable state. If the authored maximum geometry would
overshoot the measure, Cangjie interpolates complete positioned-glyph geometry
between natural and maximum shapes. The accepted candidate is committed
transactionally before later fvar-axis, Kashida, and generic spacing stages.

Shrinkage-side priorities participate directly in greedy line selection. When
the current source atom would overflow, Cangjie reshapes that complete
single-font/style prefix from source with the priority's shrinkage
enable/disable lists. If needed, `shrinkageJstfMax` supplies the bounded
zero-to-maximum adjustment interval. A fitting candidate replaces the
uncommitted glyph/run range transactionally and line selection continues;
otherwise the ordinary soft/emergency break remains authoritative. Retained
reflow, Engine-backed one-shot cache reuse, styled glyph metadata, and later
line/run indexes all follow the same replacement contract.

JSTF `ExtenderGlyph` sets are also consumed without synthesizing positioned
glyphs. The table supplies glyph ids but no Unicode scalar or insertion
location, so Cangjie uses only the source boundary proof currently defined for
U+0640: the font's nominal Tatweel mapping must belong to the selected script's
extender set, a retained SAFE_TO_INSERT_TATWEEL boundary must exist, and the
complete reshaped candidate must emit a zero-source-byte extender glyph. Fonts
whose extender set cannot be reached through that source contract are skipped
conservatively. A dedicated paragraph JSTF policy controls priority processing
and bounds extender attempts independently from generic Kashida fallback.

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
name resolution remains a separate `cangjie.font.database.Database`
responsibility: the unified entry consumes an already selected `font.Cascade`
and does not guess how a family name maps to loaded font bytes.

Attributed paragraph output also materializes text decorations instead of
leaving renderers to reconstruct them from logical style ranges.
`AttributedParagraphLayout.decorations` contains paragraph-space underline and
strikethrough rectangles split at every final visual line, style run, and font
run. Each segment retains line/style/font identities and the style color.
Positions and thicknesses come from the final font instance's scaled
`post`/`OS/2` decoration metrics (with existing validated fallbacks); OpenType
positions are treated as stroke centerlines when converted to fill rectangles.
Mixed bidi order, fallback fonts, font sizes, kerning, letter/word spacing,
wrapping, justification, tabs, and ellipsis are therefore already reflected in
the segment geometry. Fontless tabs borrow the nearest same-style font metrics
and remain covered, while inline objects deliberately break decoration
continuity.

The renderer bridge accepts these segments through
`BridgeOptions.decorations`, copies them into `GlyphDrawList.decorations`, and
applies the same origin as glyphs, cursors, selections, and inline objects.
Decoration geometry is optional and attributed-only; ordinary paragraph
shaping buffers do not pay for paint metadata. The bridge validates all
borrowed segment indexes and finite, nonnegative rectangles before ownership
transfer.

`TextStyle.vertical_align` places each attributed inline box within its final
line box using `.baseline`, `.top`, `.middle`, or `.bottom`. It is deliberately
an inline style rather than a paragraph-container alignment: paragraph layout
has no external block-size against which an entire paragraph could be centered
or bottom-aligned. Final placement adds a line-box offset to each glyph's
existing GPOS/kerx/fallback `y_offset`; shaping and run itemization therefore
remain unchanged even when adjacent paint spans align differently. In-flow
inline objects use the same aligned baseline, and decoration centerlines are
translated with their owning style. Renderer glyph commands retain the line
baseline plus the per-glyph final offset, so atlas, path, color, object, and
decoration output agree. The former paragraph-level `vertical_align` no-op has
been removed rather than retained as a misleading control.

`cangjie.font.database.Database.layoutAttributed` is the
integrated entry point for callers that do want that resolution. It maps each
normalized style run's family, weight, stretch, and normal/italic/oblique
request to a database face, builds a coverage-aware fallback cascade for that
run, and passes those borrowed fonts into the same unified paragraph. Runs
without an explicit family inherit the caller's default query family. An
explicit unknown family is reported as `FontFamilyNotFound` rather than
silently rendering through an unrelated fallback family. The database and all
fonts must outlive the returned layout because font runs retain borrowed face
pointers.

`ShapedParagraph` now implements the first width-independent paragraph
boundary. It owns source text plus pristine shaped glyph/run snapshots.
`ReflowBuffer` restores those snapshots before each layout, so different
widths, line limits, tabs, spacing, and ellipsis can be applied repeatedly
without another GSUB/GPOS pass and without accumulating mutations. Reflow
rejects direction, script, language, feature, or variation changes because
those options require reshaping.

`ShapedParagraph.breakLines` exposes the retained greedy breaker as a concrete
resumable owner. `Breaker.advance` commits at most one logical visual line or
vertical column and may receive an `x/y/width` region for exactly that
fragment. A caller can therefore paginate or fill containers without reshaping
accepted source. Horizontal reflow keeps its zero-copy forward state machine;
vertical retries rebuild from a breaker-owned pristine glyph/run snapshot, then
expose only the already committed column prefix. Supplying `max_height` runs
that attempted fragment transactionally: an oversized result returns
`.height_exceeded` with required physical height and source range, while the
cursor and output remain at the preceding fragment.

`Breaker.save` creates an explicitly owned checkpoint containing the logical
cursor plus the mutable reflow transaction. `restore` can then retry the same
source line at another position or measure; forward-only callers do not pay
that copy cost. The breaker rejects stale checkpoints and detects reuse of its
borrowed `ReflowBuffer`. Lines remain in logical source order while breaking.
After the cursor reaches the end, writing-mode-appropriate justification,
punctuation processing, per-fragment bidi, run offsets, and inline objects
execute once through the same final-presentation sequence used by ordinary
retained `layout`; horizontal lines additionally retain JSTF/Kashida/font-axis
expansion.

The resumable API intentionally accepts `.greedy` only. Balanced breaking
optimizes a complete hard-break segment and therefore still uses ordinary
whole-paragraph retained layout. Styled one-shot layout likewise remains on
its existing complete pipeline until it has a width-independent attributed
owner whose glyph-parallel metadata can participate in checkpoints; neither
case silently falls back to replay while claiming to be incremental.

`ParagraphOptions.line_break_strategy` independently selects greedy or
balanced soft-boundary policy. Both horizontal lines and vertical columns first
obtain the current greedy count per hard-break segment, then use bounded
dynamic programming to minimize total squared unused measure without adding
lines or columns. `.no_wrap` and unbounded layouts deliberately ignore the
strategy.

The horizontal optimizer considers reusable UAX #14, dictionary/hyphenation,
and emergency grapheme boundaries. It adds penalties for emergency breaks,
hyphenation, and consecutive hyphenated lines, and measures candidates against
final tab-field advances, optical punctuation capacity, font/inline-object line
metrics, first-line indentation, and exclusion regions. Chosen boundaries are
committed through ordinary horizontal reflow, retaining visible hyphens,
max-lines/ellipsis, justification, bidi, styled metadata, retained reflow,
decorations, and inline-object positioning.

The vertical optimizer owns a focused solver plus boundary-graph module under
`vertical_wrap/`. It considers reusable UAX #14, dictionary, ranged-policy, and
emergency boundaries, reuses positive-down tab-field and whitespace
measurement, signed spacing, first-column indentation, and shaped-output
safety, and leaves physical RL/LR placement to `vertical_columns.zig`.
Vertical exclusions use the greedy path in either LR or RL block progression;
fully blocked bands advance to the nearest physical edge in that direction. If
no complete safe path exists or
the state/edge limits are reached, the already valid greedy
columns remain authoritative.

Line-breaking policy is split along CSS Text's independent axes rather than
encoded as one ambiguous wrap enum:

- `WordBreak.normal` consumes UAX #14 plus optional dictionary and
  hyphenation boundaries. `.break_all` promotes every reusable grapheme edge
  to an ordinary soft opportunity. `.keep_all` removes UAX opportunities
  between adjacent ideographic, emoji, Japanese-starter, or Hangul word
  classes while preserving whitespace, punctuation, explicit hard breaks,
  dictionary boundaries, and explicit/automatic hyphenation.
- `OverflowWrap.normal` allows an otherwise unbreakable shaped span to exceed
  the measure. `.break_word` preserves Cangjie's historical behavior: a safe
  grapheme edge is used only after ordinary opportunities fail. `.anywhere`
  makes those safe edges ordinary opportunities, so balanced layout may
  consider them globally as well as during overflow.
- `WrapMode.no_wrap` still disables every width-induced soft break regardless
  of the other policies; explicit Unicode hard breaks remain authoritative.

`ParagraphOptions.line_break_policy_ranges` can override those three axes over
ordered, non-overlapping UTF-8 ranges. Every field is optional and inherits
the paragraph default independently. A candidate boundary is owned by the
source scalar immediately before it: a no-wrap span therefore cannot be split
at its trailing edge merely because the next span wraps, while the first safe
boundary after consuming a wrapping scalar may be selected normally. Unicode
mandatory boundaries are never removed by ranged policy.

Attributed `TextStyle` exposes the same optional `wrap_mode`, `word_break`, and
`overflow_wrap` overrides. Styled layout merges the exact style partition with
any paragraph-authored ranges into canonical intervals before line analysis;
style overrides replace only their non-null axes. These controls are
layout-only and do not split otherwise shaping-equivalent runs. Greedy,
balanced, retained and resumable reflow, min-content measurement, exclusions,
decorations, bidi, and glyph-parallel metadata all consume the same resolved
policy stream.

All arbitrary boundaries pass the same grapheme and
`unsafe-to-break-before` proof as emergency wrapping. They therefore never
split a GSUB source atom, ligature, mark attachment, kern pair, or any other
retained shaping relationship. Retained paragraphs keep policy-neutral
UAX/dictionary/hyphenation analysis and tailor it per reflow, so callers can
change these policies without reshaping.

`ParagraphOptions.white_space_collapse` controls ASCII inline whitespace
without rewriting the caller's UTF-8 source. The same source policy drives
horizontal x advances and vertical positive-down y advances:

- `.preserve` keeps authored U+0020 advances and tab-ruler behavior, retaining
  Cangjie's previous default.
- `.collapse` gives each interior U+0020/U+0009 run one ordinary blank,
  suppresses leading/trailing and soft-line-edge runs, and treats a tab in such
  a run as a source-visible collapsed blank rather than a ruler command.
- `.break_spaces` preserves every advance and makes each authored blank a soft
  boundary, including consecutive and trailing spaces.

Paragraph and attributed `letter_spacing` / `word_spacing` are signed
post-shaping advance adjustments on both axes. Vertical layout accepts negative
values while every resulting source atom retains a nonnegative positive-down
advance; exact zero is valid. A request that would reverse even one glyph or
space advance returns `InvalidParagraphOptions` rather than breaking the
monotone prefix, caret, selection, tab-ruler, and TextGeometry contracts.
Layout, intrinsic sizing, retained reflow, and styled metadata all use the same
validated advance refresh. Validation happens after white-space normalization,
so `.collapse` may safely erase an over-compressed authored blank that would
remain invalid under `.preserve` or `.break_spaces`.

Collapsed atoms stay in the glyph-parallel source/style sidecars with zero
advance. Caret, selection, bidi, attributed paint, decorations, text geometry,
and accessibility therefore keep original UTF-8 byte coordinates; retained
reflow can switch among all three policies without reshaping or losing source
atoms. Vertical columns apply the same leading/trailing and soft-edge trimming,
and `break_spaces` keeps each authored blank in the preceding visible column.
Only U+0020 and U+0009 are collapsible—NBSP and other Unicode space characters
retain their UAX #14 semantics. Vertical tab rulers use the same logical inline
distances and start/center/end/decimal field alignment as horizontal layout,
but resolve marker advances along positive-down y. The repeating `tab_width`
grid, explicit stops after first-line indentation, hard/soft column resets,
retained reflow, styled metadata, and owned interaction geometry share that
result. Collapsed tabs remain source-visible zero-advance blanks rather than
active ruler commands.

`ShapedParagraph.contentWidths` reports policy-aware intrinsic inline bounds
from width-independent paragraph content. `ContentWidths.max` is the widest
hard-break segment when no soft opportunity is taken; `ContentWidths.min` is
the widest fragment when every current policy-allowed safe soft opportunity is
taken. The calculation scans retained UAX/dictionary/hyphenation analysis
directly instead of approximating min-content with an arbitrary tiny
container. Visible discretionary-hyphen advances, aligned tab fields, in-flow
objects, paragraph/styled spacing, white-space policy, and shaping safety
therefore participate exactly. `overflow-wrap: break-word` does not reduce
min-content, while `anywhere` and `word-break: break-all` do. Container width,
alignment, line limits, exclusions, and out-of-flow placements do not affect
intrinsic widths. The operation validates retained shaping/object identities
and performs no GSUB/GPOS pass.

`ParagraphOptions.tab_stops` adds an explicit paragraph tab ruler. Each
`TabStop.position` is a finite, positive, strictly increasing advance from the
selected line fragment's logical inline start; this keeps the same ruler
meaning for LTR and RTL and composes with first-line indentation and rectangular
exclusions. Tabs move to the first explicit position ahead of the current
logical pen. After the final explicit stop, the existing `tab_width × ordinary
space advance` interval repeats from that final position. An empty ruler
therefore preserves the legacy repeating-grid behavior.

`TabStop.alignment` supports `.start`, `.center`, `.end`, and `.decimal`.
Alignment is resolved from final shaped glyph advances, including kerning,
inline-object widths, and paragraph/styled letter or word spacing. Decimal
stops use `decimal_point` (U+002E by default), and fall back to `.end` when the
field has no matching scalar. A field ends at the next tab or mandatory line
break. If centering or ending a field would move it before the current pen, the
tab clamps to zero advance rather than overlapping preceding content. When
wrapping truncates a prospective field at a soft or emergency break, Cangjie
re-resolves the tab against the actual committed prefix (and any visible
hyphen) before accepting line geometry.

A visible line containing a tab is pinned to logical paragraph start even when
paragraph alignment requests center, right, or justification; otherwise moving
the complete line after resolving the ruler would invalidate every tab column.
The line persists that resolved physical alignment so ellipsis and
optical-punctuation post-processing cannot move it again. Tabs remain
source/caret/selection atoms but the render bridge suppresses their font glyph,
and styled word spacing never shifts the following field past its selected
stop. Retained reflow may change the ruler or alignment without reshaping.

`cangjie.shaping.Engine` is the public ownership boundary for this pipeline.
It is a concrete value type that owns reusable output/scratch arrays
plus cmap, metric, fallback, GDEF, GSUB/GPOS proof/plan, and optional whole-run
caches. `Engine.Options` independently controls font-derived and whole-run
caching. Its methods accept named `cangjie.shaping.Request`,
`cangjie.shaping.TextRequest`, `cangjie.paragraph.Request`, or
`cangjie.paragraph.StyledRequest` records rather than long positional argument
lists. `shape` handles both ordinary runs and uncommon UTF-8 byte-scoped
feature ranges, avoiding a second nearly identical shaping entry point.
Cascade, script-run, retained-paragraph, one-shot layout, styled layout, and
measurement operations share the same engine and request model.
Returned run and layout slices borrow the engine and remain valid until its
next shaping/layout call. Faces must outlive the engine, or the caller must
invoke `clearCaches` before destroying them.

The package root is intentionally small and grouped by responsibility:
`cangjie.shaping.Engine`, `cangjie.font`, `cangjie.text`, `cangjie.shaping`, `cangjie.paragraph`,
`cangjie.render`, and `cangjie.debug`. Specialized font-table
records are grouped by responsibility under `font.metadata`; Unicode analysis
is similarly split under `text.bidi`, `text.segmentation`, `text.script`, and
`text.opentype`. Container and database APIs live under
`font.container` and `font.database`. This prevents unrelated low-level table
types and renderer commands from competing in one flat
namespace. The root integration suite is likewise split under
`src/tests/root/` by font, Unicode, shaping, rendering, database, bidi, and
paragraph responsibility instead of making the public root a 10,000-line test
container.

Font discovery and matching are implemented under `src/font/database/`:

- `types.zig` owns query, style, and indexed-face records.
- `manifest.zig` owns stable manifest records, TSV encoding/decoding, file
  persistence, and content identity checks.
- `sources.zig` owns platform and user font-source descriptions.
- `matching.zig` owns family/weight/stretch/style scoring and legacy metadata
  inference.
- `root.zig` owns loaded bytes and faces, directory scanning, fallback cascade
  construction, and the attributed-text bridge.

Modern SFNT, dfont, WOFF1, and WOFF2 container loading is organized under
`src/font/container/`. The root owns format dispatch and a uniform owned-byte
contract; format-specific decoders and checked binary helpers remain separate,
and fixture construction is test-only.

Renderer-facing draw-list construction lives under `src/render/bridge/`.
`root.zig` converts paragraph geometry into positioned glyph, atlas, path, and
color-paint requests with stable cache keys, while `tests.zig` owns bitmap,
SVG, COLR, variation, cursor, and selection integration coverage. Rasterization
and shaping remain dependencies of the bridge rather than peer responsibilities
inside one root-level renderer file.

CPU raster storage has focused ownership modules under `src/raster/`:
`targets.zig` owns grayscale target allocation and renderer RGBA records, while
`prepared.zig` owns reusable prepared scan geometry. The raster engine consumes
these concrete values without making target storage responsible for outline,
SVG, COLR, or scan-conversion policy.
`outline.zig` separately owns adaptive font-outline flattening, transformed
geometry, capacity bounds, and conservative small-size pixel alignment; its
focused tests do not require color or SVG rendering state.
`composite.zig` owns premultiplied source-over, Porter-Duff, separable blend,
and HSL composite math over RGBA slices. HarfBuzz-oracle and edge-invariant
tests remain beside that pure numerical boundary rather than inside the
rasterizer engine.
`bitmap.zig` owns clipped bilinear scaling of embedded straight-alpha RGBA
glyph images into premultiplied targets, including transparent-border sampling
that prevents hidden RGB from producing emoji edge fringes.

TrueType embedded hinting is staged under `src/font/hinting/`.
`Face.hintingInstance` creates concrete, allocator-owned state for one PPEM and
one normal/light/LCD/vertical-LCD/monochrome target. It revalidates borrowed
`maxp`, `cvt `, `fpgm`, and `prep` bytes, scales the CVT into signed 26.6
pixels, executes the font program before the control-value program, and
retains function/IDEF definitions, storage, CVT changes, instruction-control,
cut-in, delta, and scan state. Stack, storage, definitions, calls, backward
jumps, and total instructions are bounded by `maxp` and explicit execution
budgets; malformed or non-terminating programs fail deterministically. The
value stack follows FreeType's deployed-font compatibility bound:
`maxStackElements + max(maxStackElements / 2, 128)`, remaining fixed-size
rather than growing during execution.

Font and prep programs intentionally have no attached glyph zone: point-only
opcodes there report `UnsupportedHintInstruction` instead of becoming silent
no-ops. Glyph execution uses the separate atomic raw-point transaction below,
then reconstructs public pixel paths and raster input.
`Face.hintingInstanceAt` owns a complete, F2Dot14-quantized normalized fvar
location. It rebuilds the base CVT, applies active cvar tuples in design units,
scales the varied CVT to 26.6, and only then runs prep; GETVARIATION reads that
same owned axis-order location. `hintingInstance` delegates with an all-zero
location. Simple-glyph points/phantoms and compound component/phantom gvar
deltas use that same location.

The raw-point boundary exists for simple and compound
`glyf` glyphs as `Face.hintingPointTransaction`. It owns unscaled,
original-scaled, and mutable 26.6 point arrays; on-curve/touched/overlap flags;
contour ends; component point/contour ranges; borrowed glyph instruction
slices; the exact normalized axis-order location; and all four
horizontal/vertical phantom points. Simple gvar tuples, including per-tuple IUP
and metric phantom deltas, are applied in design space before 26.6 scaling and
glyph bytecode. Compound gvar tuples vary XY component parameters and parent
phantoms; point-matched component deltas remain ignored so varied anchors own
placement, while USE_MY_METRICS propagates the child's varied phantom owner.
Transactions reject an instance at a different location even when face, PPEM,
and render target match. Compound decoding
recursively applies exact 2.14 matrices, scaled/unscaled offsets, grid-rounded
offsets, nested point matching, and `USE_MY_METRICS` ownership. Compound
execution recursively runs each child program before component transform and
placement, resets touched/original state for top-level compound bytecode, and
shares one private CVT/storage/twilight transaction across the complete
child-to-parent lifecycle.
`Face.executeHintingTransaction` now runs core point-zone bytecode over private
working copies of the glyph and persistent PPEM twilight zones. Projection and
freedom vectors, reference points, zone pointers, loop and rounding state are
reset per glyph; MDAP/MIAP, MDRP/MIRP/MSIRP, IUP/IP, SHP/SHC/SHZ/SHPIX,
ALIGNPTS/ALIGNRP, ISECT, SDPVTL, GC/SCFS/MD, DELTAP, on-curve edits, CVT,
storage, functions, and instruction definitions share the same bounded
interpreter. Points, flags, twilight state, CVT, and storage commit together
only after a successful run; any error leaves the transaction and instance
unchanged. Installed-font gates execute representative glyph programs and a
full mnemonic scan of DejaVu Sans, Noto Sans Devanagari, and Noto Sans Arabic
shows no uncovered non-variation standard opcode.
Hinting instances select either classic v35 or minimal ClearType-compatible
v40 semantics explicitly through `HintingOptions.interpreter`; existing
target-only constructors retain classic behavior. GETINFO advertises the
selected version and its target-specific grayscale/ClearType capabilities.
The v40 state tracks IUP on both axes, honors prep or glyph INSTCTRL native
ClearType waivers, suppresses compatibility X and post-IUP movement, filters
SHPIX/DELTAP and post-IUP curve edits, preserves unrounded phantom origins
while separately grid-fitting public advances, skips X grid-rounding of
compound component offsets, reports v40 MPS point size, and falls back to
native semantics for FreeType's complete tricky-font family/signature list.
The optional
`zig build hinting-freetype-test` gate selects FreeType v35 and v40 explicitly
and requires exact contour, on-curve-tag, final 26.6-point, and
horizontal-advance parity for representative simple, compound, Arabic,
Devanagari, and variable glyphs across normal, LCD, vertical-LCD, and mono
native targets. FreeType's native light outline changed between 2.13.2 and
2.14.3 despite identical v40 bytecode traces; the same full light corpus is
therefore gated only when the linked oracle is FreeType 2.14 or newer. IP and
IUP preserve unscaled glyph-zone ratios and staged 16.16 fixed-point rounding
rather than collapsing equivalent real-number formulas that differ by a 26.6
unit.

`toPixelOutline` then reconstructs a distinct pixel-space path and applies the
possibly modified left phantom (`pp1`) as the FreeType-compatible glyph
origin. `Rasterizer.drawPixelOutline` and `preparePixelOutline` consume that
path at scale one, applying only caller x/baseline placement; they deliberately
skip the design-outline UPEM scale, small-glyph alignment, and synthetic
emboldening because the bytecode has already made pixel-grid decisions.
`Rasterizer.drawHintedGlyph` performs transaction creation, atomic VM
execution, pixel-path reconstruction, and scale-one coverage drawing with a
caller-owned PPEM instance. `drawHintedRun` applies that path to a shaped run
while preserving shaping advances/offsets and rejecting a mismatched variation
location; it does not hide PPEM-instance lifetime or cache policy.
Compound glyphs, including gvar component placement and metric phantoms, can be
decoded, executed, and reconstructed. Transactions reject an instance created
from another face, PPEM, target, interpreter, or normalized location.

The shaping integration suite is similarly rooted at
`src/tests/root/shaping/`, with focused diagnostics, fallback, font-contract,
GSUB, GPOS/AAT, attachment, pipeline-state, and vertical-layout modules. Tests
also import owning domain modules directly rather than restoring a test-only
aggregate layout namespace.

Unicode behavioral coverage is grouped beside the implementation under
`src/unicode/tests_*.zig`: baseline contracts, segmentation, RTL/joining
scripts, Indic/USE scripts, and other script families have independent test
containers. The joining state machine and its private bidirectional test oracle
live together in `src/unicode/joining.zig`; a comptime script policy supplied by
the root itemizer keeps joining-property lookup independent from script
classification without adding runtime callbacks. Only the mark-classification
test that intentionally exercises private root helpers remains in the Unicode
root implementation.
Unicode script identity and scalar classification live under
`src/unicode/script/`: `root.zig` owns the public script type, overlap-sensitive
classification order, and semantic policies such as Arabic-style joining
eligibility, while `ranges.zig` contains only scalar-range facts. The public
`unicode.Script` and `scriptForCodepoint` surface remains rooted in
`src/unicode.zig`, so shaping and application code do not depend on internal
block predicates.
Unicode mark policy is separated under `src/unicode/mark/`:
`nonspacing.zig` is the generated Unicode 17 General_Category=Mn table,
`spacing.zig` owns the supported visible dependent-sign/spacing-mark policy,
and `extender.zig` retains the established word and shaping-source boundary
tailoring. `root.zig` keeps those meanings distinct while exposing the stable
Mn, spacing-mark, and combined mark queries through `src/unicode.zig`.
UAX #50 orientation ranges and compatibility presentation-form mappings live
under `src/unicode/vertical*`. `vertical_data.zig` is generated from Unicode
17 `VerticalOrientation.txt`; its default-R table plus 189 merged U/Tu/Tr
ranges classifies all 1,114,112 code points, while `vertical.zig` keeps lookup
and the compatibility-form map independent from script itemization.

Cangjie deliberately does not own an editor or mutable text-buffer model.
Applications and UI toolkits compose the public Unicode segmentation,
paragraph, caret, selection, and hit-testing APIs with their own document,
history, IME, clipboard, and viewport state. This keeps the font/text stack
independent of any particular widget framework and avoids a second editor model
beside the application's native one.

End-to-end paragraph construction now has an explicit cross-library benchmark
boundary. `zig build paragraph-bench -Doptimize=ReleaseFast -- FONT TEXT N S`
reuses one parsed face and shaping engine while measuring complete shaping,
200-unit line breaking, and start alignment. The standalone
`tools/parley_layout_oracle` runner performs Parley's matching default-style
`RangedBuilder::build`, `break_all_lines`, and `align` sequence with one
reused `FontContext`/`LayoutContext`. Both consume the first line of the same
UTF-8 file, use the same explicit font at 16 units, verify stable glyph/line
counts and deterministic per-engine geometry checksums, and report sample
medians. Checksums intentionally are not compared byte-for-byte because the
engines expose different coordinate record shapes; equal source length, 105
glyphs, and five lines establish the comparable Roboto Latin output boundary.

On fixed CPU 30, a serial Cangjie/Parley/Parley/Cangjie run over the first
109-byte paragraph of Parley's own Latin sample, with 1,000 iterations and 31
samples per process, measured Cangjie medians of `29,706` and `29,656 ns` and
Parley medians of `47,383` and `46,798 ns`. Cangjie was about `1.59x` faster
at this newly retained default Latin paragraph boundary. This is one controlled
workload, not evidence of overall Parley superiority; Arabic, Japanese, styled,
spacing, justification, and longer paragraph matrices remain required.

The first script expansion reinforces that caution. With the same fixed-CPU-30
protocol, the first 570-byte Japanese paragraph produced 190 glyphs and seven
lines in both engines; Cangjie measured `60,642`/`60,876 ns` versus Parley's
`136,778`/`135,030 ns`, about a `2.23x` Cangjie lead. The first 200-byte Arabic
paragraph produced 144 glyphs in both engines, but Cangjie selected four lines
while Parley selected five, so it is not an output-equivalent performance row.
Its timings nevertheless expose the next optimization target: Cangjie measured
`99,972`/`100,176 ns` versus Parley's `66,594`/`67,708 ns`, about `1.50x` slower.
That row must not be used as a speed headline until line-break/metric semantics
are reconciled; it does show that Arabic paragraph construction, not the Latin
or Japanese default path, is the current Parley-relative deficit.

The benchmark CLIs now accept an optional width so this ambiguity can be
separated from the timing deficit. At 180 units both Arabic engines produce
the same 144 glyphs and five lines. The fixed-CPU-30 serial matrix measured
Cangjie at `102,885`/`103,092 ns` and Parley at `67,333`/`66,774 ns`; Cangjie
is still about `1.54x` slower on this output-count-equivalent row. Exact line
break byte ranges and positions are represented differently and are not yet a
cross-engine checksum equality claim, but the width control proves the 200-unit
4/5-line difference did not create the Arabic performance deficit.
The runners now default to the same first-strong (`auto`) paragraph direction
and also accept explicit `ltr`/`rtl`; earlier Arabic Cangjie measurements used
its explicit-LTR API default and remain only as historical harness data.

`paragraph-bench` also accepts a final `reflow` phase that prepares the
width-independent paragraph once and measures only restore, line selection,
presentation, and output reuse. On the same Arabic 180-unit row this phase is
about `17,333 ns`, versus roughly `103,000 ns` for complete construction. Thus
about 83% of Cangjie's measured cost lies before or outside repeatable reflow
(shaping, Unicode/fallback setup, and one-shot orchestration); line breaking
itself is not the primary Parley-relative bottleneck.

Single-face cascades now bypass grapheme-by-grapheme fallback segmentation:
with no overrides, every valid source cluster must resolve to font index zero,
so scanning Unicode boundaries merely to rediscover that invariant was wasted
work. The fallback and shaped-run cache contracts explicitly retain zero
fallback probes for this case. On the Arabic 180-unit row, fixed-CPU-30 medians
fell from roughly `103,000 ns` to `98,362 ns`; the same run measured Latin at
`27,754 ns` and Japanese at `56,077 ns`, both improvements over the preceding
`29,656` and `60,876 ns` retained rows. Output checksums, glyph counts, and line
counts remained identical for all three scripts.

The cross-engine timing loop validates the complete geometry checksum during
warmup, then consumes only constant-size layout summary fields inside the
measured iterations. Rehashing every glyph had previously charged Cangjie
about 4.5% of its Arabic sample while Parley's iterator exposed a differently
shaped record stream. With the symmetric constant-size consumer, the retained
Arabic 180-unit medians are approximately `93,779 ns` for Cangjie and
`66,725 ns` for Parley. Cangjie still trails by about `40.5%`, so correcting
the harness narrows but does not erase the real Arabic deficit.

Owned GDEF MarkGlyphSetsDef coverages are strictly sorted, so GSUB and GPOS
LookupFlag membership now uses binary search instead of walking every glyph in
the selected set. Noto Kufi Arabic's active sets contain up to 80 glyphs and
were a top paragraph-profile cost. Fixed-CPU-30 medians on the output-equivalent
Arabic row improved to `92,306 ns`; Latin and Japanese controls also measured
`24,038 ns` and `49,173 ns`, with unchanged checksums, glyph counts, and line
counts. The exact gains include the corrected constant-size benchmark consumer
above, while the focused membership tests retain boundary hits and misses.
After direction parity, the current fixed-CPU-30 medians are `85,092 ns` for
Cangjie versus `67,321 ns` for Parley on Arabic (about `26.4%` slower),
`23,849` versus `45,739 ns` on Latin (about `1.92x` faster), and `49,725` versus
`148,880 ns` on Japanese (about `2.99x` faster). All three rows retain equal
source length, glyph count, and line count across engines. Arabic remains the
only deficit in this default-style three-script matrix.

GPOS lookup sidecars now own both MarkMarkPos coverages, extending the existing
MarkBasePos coverage acceleration. Noto Kufi's final four active lookups are
MarkMarkPos and otherwise reparsed and searched both coverages for every
candidate glyph. The fixed-CPU-30 Arabic median moved from `85,092 ns` to
`83,744 ns` with the same checksum, 144 glyphs, and five lines. Latin and
Japanese controls remained at `24,296 ns` and `49,249 ns`, within their
preceding ranges. Cangjie still trails the same Parley Arabic row by about
`24.4%`; the other two script leads remain intact.

The common GDEF flag `UseMarkFilteringSet` (`0x0010`) now has a direct
lookup-filter path: ordinary bases are immediately visible, while marks perform
only the selected sorted-set membership test. Noto Kufi uses this exact flag on
all active filtered GSUB/GPOS lookups, so the generic high-byte/ignore-class
dispatcher was pure overhead. The Arabic fixed-CPU-30 median fell to
`76,083 ns`, about `13.0%` above Parley; Latin and Japanese controls measured
`23,931 ns` and `49,270 ns`, with all checksums and output counts unchanged.
MarkMarkPos backward search now consumes the same owned second-mark coverage
as its target lookup instead of reparsing the borrowed Coverage table for each
candidate. The Arabic median reduced further to `75,414 ns`, about `12.0%`
above the retained Parley row, with identical output checksum and counts.

The `auto` benchmark now resolves first-strong direction inside each measured
layout call, matching Parley's builder boundary rather than resolving it once
before timing. A 5,000-iteration, 31-sample CPU-30 Cangjie/Parley/Parley/
Cangjie matrix measured `75,539`/`75,551 ns` versus `68,314`/`66,560 ns`.
Direction resolution therefore leaves a stable Arabic deficit of roughly
`11--13.5%`; it is no longer hidden outside the Cangjie timing boundary.

Line-local bidi now retains its glyph/run snapshot, ownership map, cluster
index, seen bitmap, visual run indexes, L1 levels, and L2 order in the reusable
layout buffer. The glyph and run list owners are swapped for the transaction
rather than copied, with rollback restoring the original owners on every error,
and L1/L2 are derived together instead of allocating and resetting levels
twice per line. A fixed-CPU-30 B/A/A/B matrix over the locally installed
Noto Kufi Arabic and Parley sample (the first line is 200 UTF-8 bytes, 109
glyphs, five 180-unit lines on this font version) kept checksum
`14abc73c3502cccb`. Complete layout measured `37,789`/`37,872 ns` before and
`37,859`/`37,329 ns` after, within noise because shaping still dominates;
retained reflow improved from `11,167`/`11,811 ns` to `10,682`/`10,733 ns`,
about 7--9.6%. Matching Latin and Japanese one-shot controls stayed within
their preceding ranges. On this current local-font row Cangjie also measured
`36,370`/`36,352 ns` versus Parley's `48,080`/`48,124 ns`; this replaces no
historical row because both the output count and installed font build differ
from the earlier 144-glyph evidence. It is a narrow same-artifact result, not
an overall Parley claim.

The paragraph benchmark pair now also exposes a symmetric `spacing` style:
both runners apply 0.75 units of letter spacing and 2.0 units of word spacing
to the complete 16-unit paragraph before breaking at width 200. On Parley's
109-byte Latin sample both produce 105 glyphs and five lines with stable
per-engine checksums. A fixed-CPU-30 Cangjie/Parley/Parley/Cangjie 11-sample
probe initially measured Cangjie at `2.107/2.077 ms` and Parley at
`117.1/113.0 µs` per layout. Profiling showed that the styled segment bridge
discarded the engine's glyph-index and glyph-metrics caches, forcing complete
SFNT/cmap checksum validation for every glyph. Threading those existing caches
through the styled driver reduced retired instructions from about `13.76B`
to `392M` and cycles from `3.48B` to `141M` per 1,000 layouts, with the
same Cangjie checksum. A post-fix fixed-CPU-30 31-sample matrix measured
Cangjie at `118.4/128.1 µs` and Parley at `185.5/176.5 µs`: Cangjie is
about `1.45x` faster by geometric mean on this output-count-equivalent
styled/spacing boundary. This is still one Latin style workload, not an
overall Parley performance claim.

The same benchmark pair now exposes an `alternating` attributed workload. Both
runners split at the first UTF-8 boundary at or after the midpoint, keep the
first half at 16 units, and apply 18-unit text plus 0.75 letter spacing and 2.0
word spacing to the second half. A fixed-CPU-30, 1,000-iteration, 31-sample
script expansion kept cross-engine glyph and line counts equal: Roboto Latin
produced 105 glyphs/five lines at `99.94 µs` for Cangjie versus `161.93 µs`
for Parley; Noto Kufi Arabic produced 144 glyphs/six lines at `301.64 µs`
versus `242.78 µs`; and Noto Sans CJK JP produced 190 glyphs/18 lines at
`481.13 µs` versus `477.65 µs`. Per-engine geometry checksums were stable.
This adds real multi-span evidence: Latin remains a Cangjie win, Japanese is
approximately tied, and Arabic multi-style layout remains the clearest Parley
deficit. It is not an overall superiority claim.

Styled bidi no longer recomputes a second line-local UAX #9 permutation solely
for the glyph-parallel metadata sidecar. The ordinary glyph/run mapping now has
a comptime-specialized recording mode that appends the exact old glyph index at
its unique visual-output point; non-styled callers compile that path out. The
styled driver consumes the retained permutation after the existing transactional
reorder. On fixed CPU 30, five-repeat counters for Arabic alternating layout
fell from `1.0686B` to `1.0302B` instructions, `180.37M` to `173.24M` branches,
`364.1M` to `340.1M` cycles, and `1.361M` to `0.944M` branch misses per 1,000
layouts. The Arabic spacing control similarly reduced instructions by `3.8%`,
branches by `4.1%`, and cycles by `4.7%`; Latin alternating stayed neutral,
while Japanese alternating improved from `520.91/486.99 µs` to
`470.59/461.78 µs`. All target/control checksums, glyph counts, and line counts
were unchanged. A fresh 2,000-iteration Arabic Cangjie/Parley/Parley/Cangjie
matrix remained frequency-skewed (`270.38/290.93 µs` versus
`183.82/242.08 µs`), so Arabic alternating is still recorded as a Parley
deficit rather than a Cangjie win.

The same spacing protocol over the 200-byte Noto Kufi Arabic sample produces
144 glyphs and six lines in both engines. Cangjie initially measured
`377.4/321.7 µs` versus Parley's retained `233.5/174.1 µs`. Styled bidi
was heap-sorting its cluster index even when GSUB had already left the glyph
stream in monotone cluster/index order. Detecting that order before sorting
reduced Cangjie to `323.7/314.9 µs`; five-repeat counters reduced retired
instructions by `9.5%`, branches by `2.5%`, cycles by `11.0%`, and
branch misses by `15.4%`, with the output checksum unchanged. Arabic spacing
still trails Parley, so this remains an active paragraph-performance gap.

Styled bidi previously resolved the complete UAX #9 paragraph once to build
the glyph-parallel metadata permutation and then resolved the identical text
again inside the glyph/run transaction. Both consumers now share one immutable
paragraph resolution while independently applying the exact same line-local
L1/L2 mapping. On fixed CPU 30, a 1,000-iteration, 31-sample B/A/A/B run
measured the preceding Cangjie build at `307.29/305.96 µs` and the shared
resolution at `296.77/298.59 µs`, about a `3.0%` geometric-mean improvement.
The Cangjie checksum remained `fb80f404e4d69aff` with 144 glyphs and six
lines. Retired instructions fell from `1.151B` to `1.113B` and branches from
`194.2M` to `187.7M` per 1,000-layout counter run; cycles fell about `1.8%`,
while branch/cache misses remained noisy. The Latin spacing control stayed
neutral at `110.48/108.71 µs` before and `109.78/108.70 µs` after with the
same checksum and counts. Fresh matching Parley controls measured
`225.66/229.24 µs` for Arabic and `160.76/160.61 µs` for Latin. Cangjie
therefore remains about `30.5%` slower than Parley on this Arabic spacing row
while retaining about a `1.47x` Latin lead; this narrows but does not close the
active paragraph-performance gap.

Styled intrinsic sizing and final line selection previously decoded the same
text into grapheme clusters and UAX #14 opportunities independently. The
intrinsic pass now lends its width-independent analysis to reflow, which still
applies the paragraph and attributed-range wrapping policy before selecting
lines. On the fixed-CPU-30 Arabic spacing row, `perf stat -r 5` reduced retired
instructions from `1.114B` to `1.059B` and branches from `187.7M` to `179.8M`
per 1,000 layouts; cycles fell from `398.9M` to `350.1M`, although wall-clock
samples remained frequency-sensitive. An additional 2,000-iteration
Cangjie-candidate/base/base/candidate matrix measured `306.04/251.21 µs` for
the shared analysis and `324.33/366.48 µs` before it, with checksum
`fb80f404e4d69aff`, 144 glyphs, and six lines unchanged. The Latin spacing
control improved from `116.56/115.22 µs` to `100.53/106.45 µs`, preserving
checksum `024ab925eca26b11`, 105 glyphs, and five lines. A focused regression
also exercises shared analysis under `break-all` plus `anywhere` emergency
wrapping so policy tailoring cannot be bypassed.

Prepared MarkBasePos and MarkMarkPos subtables now test their owned mark
coverage before the broader LookupFlag mark-filtering set. A non-covered glyph
cannot match that subtable regardless of visibility, so the reordered tests
remove a second binary search for most glyphs while the borrowed-table path
retains its validation and error order. On fixed CPU 30, an Arabic spacing
B/A/A/B run moved from `280.85/282.27 µs` to `278.48/278.68 µs`, about a
`1.1%` geometric-mean improvement, with checksum `fb80f404e4d69aff`, 144
glyphs, and six lines unchanged. Five-repeat counters reduced instructions
from `1.0593B` to `1.0509B` and branches from `179.77M` to `177.83M`; cycles
were neutral. The Latin spacing control had identical checksum/counts and no
stable paired regression.

The styled UAX #9 pass now retains its UTF-8 scalar/input arrays and resolver
working sets in the layout buffer instead of allocating and freeing every
proportional array on each paragraph. Resolution is still recomputed from the
current bytes and base direction on every call; only capacity is reused, and
the ordinary public resolver continues returning an independently owned
snapshot. On the Arabic spacing row, five-repeat counters fell from `1.0508B`
to `1.0455B` instructions, `341.5M` to `337.0M` cycles, `177.80M` to
`177.16M` branches, and `1.032M` to `0.991M` branch misses per 1,000 layouts.
The fixed-CPU-30 wall-clock B/A/A/B sample was frequency-skewed, while its
checksums, 144 glyphs, and six lines remained identical; the matching Latin
control stayed neutral at about `100 µs` with unchanged output.

The script classifier now recognizes the disjoint primary Arabic block before
walking the long supplementary-script chain. This preserves every existing
Script value while avoiding dozens of unrelated range tests for the letters,
marks, and punctuation that dominate ordinary Arabic text. On the same Arabic
spacing row, five-repeat counters fell from `1.0457B` to `1.0224B`
instructions, `177.21M` to `174.01M` branches, `346.1M` to `337.7M` cycles,
and `1.238M` to `1.181M` branch misses per 1,000 layouts. Fixed-CPU wall-clock
samples were again frequency-skewed, but checksum `fb80f404e4d69aff`, 144
glyphs, and six lines stayed identical. The Latin spacing control retained
checksum `024ab925eca26b11`, 105 glyphs, five lines, and no stable regression.

`cangjie.paragraph.buildGeometry` and `buildStyledGeometry` provide the missing
platform-neutral accessibility bridge without introducing AccessKit or another
platform tree model. The owned result enumerates logical-order spans split by
line, final font run, resolved bidi direction, and optional style identity.
Each span carries paragraph-space bounds, UTF-8 source range, same-line
previous/next links, UAX #29 word-start indexes, and a flat range of source
graphemes with UTF-8 lengths, span-relative `inline_position`, and
`inline_size`. Those values map to x/width horizontally and y/height
vertically; consumers never have to reinterpret a field named `width` as a
vertical advance.
When one shaped glyph covers multiple source graphemes (for example a GSUB
ligature), Cangjie first reads the glyph's GDEF LigCaretList. CaretValue
formats 1, 2, and 3 are supported, including TrueType contour-point resolution
and GDEF 1.3 ItemVariationStore deltas at each final run's variation instance.
Complete, strictly increasing authored carets divide the glyph advance exactly;
missing, incomplete, unavailable, or out-of-range data falls back to equal
division rather than exposing invalid inline sizes. `GraphemeGeometry` records which
case applied through `authored_ligature_caret`, so consumers never have to infer
precision from unequal sizes. An RTL span reverses component assignment while
retaining logical grapheme order and decreasing visual positions. The builder
resolves bidi from source once rather than guessing from visual glyph order,
and its arrays remain valid after the shaping output buffer is reused. Platform
adapters can translate this stable data to AccessKit, UI Automation, AT-SPI, or
native application semantics.

The geometry owner also retains every final line independently from its spans,
including empty trailing-hard-break and empty-paragraph lines.
`TextGeometry.caret` maps an exact UTF-8 boundary plus upstream/downstream
affinity to a zero-inline-size paragraph-space rectangle; the affinity distinguishes
the two visual positions that a soft wrap or bidi transition can assign to one
logical boundary. `TextGeometry.hitTest` performs the inverse using final
grapheme partitions, including authored GDEF ligature carets, rather than the
coarser positioned-glyph midpoint API. These queries remain layout primitives:
document mutation, cursor movement policy, selection state, and IME ownership
stay in the application/editor layer.

`TextGeometry.selectionFragments` maps one strict half-open logical UTF-8 range
to allocator-owned visual fragments. Both endpoints must be grapheme
boundaries, and truncated-away or otherwise unavailable source is rejected
rather than silently approximated. Physically adjacent selected graphemes are
merged per line, while mixed-bidi visual gaps remain separate fragments. This
lets platform adapters paint accurate selections inside GDEF-authored
ligatures and across wraps without reconstructing bidi geometry themselves.

Every geometry owner also materializes `visual_caret_stops` in line then
physical inline-start-to-end order. A stop exposes `inline_position` plus
`from_start`/`from_end`, preserving bidi transitions where one physical
coordinate has two logical meanings and zero-size controls where consecutive
topology steps coincide. `nextVisualCaret`/`previousVisualCaret` traverse this
topology across soft wraps and GDEF-authored ligature boundaries without
storing mutable cursor state.

`nextLineCaret` and `previousLineCaret` extend the same topology along the block
axis. They accept a caller-retained preferred inline coordinate (physical x for
horizontal text, y for vertical text) and choose the nearest stop on the
adjacent line, naturally clamping to short or empty lines while resolving bidi
dual positions from the physical approach side. Keeping that coordinate
outside the owner preserves repeatable movement without introducing document
or cursor state into Cangjie.

GDEF's previously validation-only `AttachList` is also available through
`Face.glyphs().attachmentPoints` and
`cangjie.font.metadata.layout.inspect(face).attachmentPoints`. The
allocator-owned records expose sorted contour-point indexes for covered glyphs,
match HarfBuzz's face-level attachment-point semantics, and retain the same
borrowed-table checksum and child-grammar defenses as other public GDEF reads.

GDEF class and mark-set inspection is enumerable rather than requiring callers
to probe every glyph. `Face.glyphs().inClass` and the layout inspection view's
`glyphsInClass` return allocator-owned glyph IDs, with `.unclassified`
explicitly representing the complement of all ClassDef assignments.
`markGlyphSetCount` plus strict-indexed `markGlyphSet` exposes each
MarkGlyphSetsDef coverage independently, distinguishing an empty set from an
out-of-range request while preserving duplicate-tolerant canonical set
semantics used by production fonts.

Paragraph shaping now retains glyph atoms in logical source order and applies
bidi visual ordering only after line ranges are known. One complete UAX #9
paragraph resolution supplies levels to each final line/column, where L1/L2
produces the local visual order. Mixed LTR/RTL text, embeddings, overrides, and
isolates therefore reorder independently when a width change creates different
boundaries without losing paragraph-wide explicit state. Horizontal lines map
that order to x; vertical paragraphs map it to physical positive-down y while
RL/LR continues to select only column progression. A bottom-to-top base
therefore reverses logical ownership and start/end alignment without
introducing negative advances into wrapping, rendering, or caret geometry.
Font-run ownership, styled glyph metadata, tabs, inline objects, ellipsis,
retained reflow, hit testing, owned TextGeometry, and renderer commands follow
the same permutation.

`ParagraphOptions.exclusions` adds platform-neutral rectangular float/exclusion
geometry. Each wrapped visual line subtracts vertically intersecting rectangles
from its indented container and selects the widest remaining contiguous
fragment; equal fragments prefer physical left for LTR and physical right for
RTL. Fully blocked bands advance to the nearest rectangle bottom without
creating empty source lines. `ParagraphLine.region_x/region_width` retain the
chosen fragment so alignment, optical punctuation, compression, justification,
ellipsis, styled minimum line heights, retained reflow, caret geometry, and
rendering all consume one final measure. Multiple simultaneous fragments on a
single baseline remain outside the current one-line/one-fragment model.
Vertical-lr columns transpose the same resolver: rectangles intersecting the
column's physical x band subtract y intervals from its positive-down inline
container. The widest remaining y fragment determines wrapping/alignment; a
fully blocked band advances the block cursor to the nearest exclusion right
edge without creating an empty source column. Vertical-rl mirrors that
traversal toward the nearest exclusion left edge, then translates its local
right-to-left coordinates into final paragraph space. Explicit `line_regions`
take precedence, `.no_wrap` ignores exclusions, and out-of-flow resolver
responses replay through the same path.

Paragraph inline objects use U+FFFC OBJECT REPLACEMENT CHARACTER as their
stable UTF-8 source anchor. `cangjie.paragraph.InlineObject` supports in-flow
objects that contribute width and baseline-relative line extents, plus
out-of-flow objects that retain a positioned anchor without changing line
geometry. Object markers participate in Unicode bidi, wrapping, caret, and
selection, but never enter font fallback or generate glyph render requests.
Final `PositionedInlineObject` records are available on both paragraph layouts
and renderer draw lists. Retained paragraphs may change object dimensions and
identifiers during reflow while preserving the original marker indexes.

`InlineObjectKind.custom_out_of_flow` and
`cangjie.paragraph.OutOfFlowResolver` add the caller-controlled placement layer
without embedding an application layout callback or opaque state into
Cangjie. The resolver is a concrete replay/resume state machine. A caller
starts it with base paragraph options, lays out the returned
`OutOfFlowPass.options`, and presents that final layout to `next`. The first
visible unresolved object yields an `OutOfFlowPlacementRequest` containing its
stable object/source identity, fallback anchor, owning line box, baseline, and
selected exclusion region. The caller submits absolute paragraph-space
geometry plus an optional independent rectangular exclusion, then repeats the
pass until `next` returns `.complete`.

Requests follow UTF-8 source order even when bidi changes visual order. Objects
removed by the original line limit never yield; an object already accepted
from a visible pass may not silently disappear on a later replay. Generation
and request tokens reject stale state. Submitted absolute bounds are rendering
output only and do not enlarge paragraph metrics; only the optional exclusion
changes line selection. Static exclusions and pre-authored placements are
preserved, and `resolvedOptions` exposes the final combined slices while the
resolver owns them.

For vertical paragraphs, the same protocol currently accepts direct placements
and placement-only resolver responses. Custom markers retain zero inline/block
occupancy, and their submitted geometry remains rendering-only. A response
that also supplies an exclusion is rejected explicitly until vertical
exclusion regions support the same replay contract.

The protocol works with one-shot and styled layout, but retained
`ShapedParagraph` plus `ReflowBuffer` is the intended repeated-placement path:
Unicode analysis and whole-paragraph shaping stay immutable while each
response deterministically rebuilds only paragraph presentation. The current
generic resolver deliberately replays reflow after a response so exclusions,
dynamic line heights, ellipsis, justification, punctuation, bidi, caret
geometry, and rendering all observe one ordinary final layout. The internal
retained greedy breaker now avoids that replay when the caller can supply
regions directly through `ShapedParagraph.breakLines`; the resolver remains
the one-shot/styled-compatible protocol and its public contract is unchanged.
This follows Parley's per-line ordering model while keeping standalone shaping
APIs in their existing HarfBuzz-compatible visual buffer order.

`ParagraphOptions.line_regions` provides an explicit paragraph-space
`x/y/width` for a prefix of final visual fragments. Entry `i` owns visual
fragment `i` across hard-break segments. Horizontally, x/width remain the
contiguous line fragment while y is its block position. Vertically, x is the
column's physical block origin and y/width are its positive-down inline origin
and available height; font/object metrics still determine physical column
width. Explicit regions override natural max inline size, first-line indent,
and rectangular exclusions while preserving ordinary UAX breaking, balanced
selection, tabs, justification, bidi, objects, and output ownership. Because
physical origins are explicit, lines/columns may jump between pages or custom
containers instead of remaining block-axis monotone. `ParagraphLine` retains
both block geometry and `region_inline_start/region_inline_size`, so paragraph
and owned TextGeometry hit testing select the nearest two-dimensional region.

`cangjie.paragraph.LineRegionResolver` is the concrete replay protocol for
pagination, columns, and other caller-owned containers. `begin` snapshots base
options, `pass` exposes the currently known line-region prefix, and `next`
checks a final ordinary layout. If another visual line needs placement it
yields a tokenized request containing its natural region, height, and source
range; `submit` adds one finite positive-width region and advances the
generation. Stale passes and requests are rejected. When `next` returns
`.complete`, `resolvedOptions` contains the final resolver-owned region slice.
The protocol embeds no callback or opaque state and works with retained and
styled horizontal or vertical layout; each replay restores immutable shaping
before rebuilding final presentation.

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

Unicode 17 vertical-orientation data is generated with:

```sh
tools/unicode/vertical/generate_data.py \
  path/to/VerticalOrientation.txt \
  src/unicode/vertical_data.zig
```

The generator pins the `VerticalOrientation-17.0.0.txt` header, its 2,470
source ranges, and source SHA-256
`dcef09c3fb24d356b042569c328ec341efc5b53447700d799f2fb4834c3cd3cd`.
The normal test suite checks generated range ordering and exhaustively
classifies every Unicode code point against the generated U/R/Tu/Tr totals.

On a fixed-core mixed Latin/Arabic/Hebrew paragraph microbenchmark, the
earlier retained `BidiMap` adapter measured about `3.43 µs` versus `2.64 µs`
for the former coarse model. The exact paragraph model provides explicit controls,
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
2. Define bounded cache budgets and eviction policy for long-lived engines,
   while preserving exact cache-key comparisons, explicit lifetime rules, and
   observable hit/miss statistics.
3. Keep public and test consumers on owning domain modules; do not recreate a
   broad aggregate layout façade as new shaping or paragraph capabilities are
   added.
4. Extend the current U+0640-safe OpenType `JSTF` ExtenderGlyph source contract
   only when another Unicode extender has an equally explicit insertion-safety
   proof; never insert a raw glyph id into positioned output.
5. Add fuzz and CI matrices for stage boundaries, cache reuse, malformed font
   data, mixed-script fallback, vertical text, and retained reflow, alongside
   the existing Unicode and HarfBuzz parity gates.
6. Benchmark analysis, shaping, and reflow separately across representative
   scripts, variable/color fonts, short UI runs, and long paragraphs. A faster
   micro-iterator does not by itself establish end-to-end superiority over
   reference engines.

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
