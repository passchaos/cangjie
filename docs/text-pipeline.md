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

- `root.zig` owns the greedy line-selection state machine.
- `opportunities.zig` maps streaming or retained Unicode opportunities onto
  shaped output while enforcing `unsafe-to-break`.
- `geometry.zig` owns line struts, alignment, indentation, tabs, spacing, and
  run ranges.
- `truncation.zig` owns line limits and plain-text ellipsis materialization.

Paragraph request and ownership policy is organized under
`src/layout/paragraph/`:

- `options.zig` owns public paragraph options, validation, and the projection
  from paragraph controls to width-independent shaping controls.
- `retained.zig` owns `ShapedParagraph` and `ReflowBuffer`, including immutable
  source/shaping snapshots and repeatable reflow without another GSUB/GPOS
  pass.
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

The language-data layer for automatic hyphenation is implemented under
`src/text/hyphenation/`. `cangjie.text.hyphenation.Dictionary` parses the plain
Unicode Liang-pattern and exception format used by tex-hyphen/libhnj and
MuPDF's hyphen resources, copies it into an immutable scalar trie, and returns
UTF-8 byte boundaries. Left/right minimum fragments and owned one-to-one
Unicode normalization mappings are explicit construction options; no language
data, locale guess, or runtime callback is built into the library.

`ParagraphOptions.hyphenation` and
`ParagraphStyle.hyphenation` now tailor paragraph reflow with those
boundaries. UAX #14 remains the default when its dictionary is null. A selected
automatic boundary resolves U+2010/U+002D/U+00AD through the preceding
cascade run, includes that advance while fitting the line, and inserts one
zero-source-length glyph only after all logical line ranges have been chosen.
The same policy can request another font-supported Unicode scalar and cap
immediately consecutive visible hyphenated lines; both settings are reflow-only
and may change between layouts of one retained paragraph.
Run ownership, retained reflow, attributed metadata, bidi visual order, hit
testing, and selection therefore consume the same materialized result without
mutating the source text. Boundaries inside a shaped atom or marked unsafe to
break remain unavailable. Callers own language selection and dictionary
lifetime; Cangjie deliberately does not infer either from locale.

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

`ParagraphOptions.punctuation.end_hanging_fraction` and the corresponding
`ParagraphStyle` policy optionally let East Asian closing, exclamation, and
nonstarter punctuation protrude from the logical inline-end margin. Reflow
uses the reduced occupied measure for fitting and justification, while
`ParagraphLine.hang_start`/`hang_end` record the final physical side after bidi.
Glyph advances and source ranges remain unchanged, so rendering, selection,
caret, retained reflow, attributed metadata, alignment, and paragraph metrics
share one explicit optical geometry contract. The default fraction is zero.
Language-specific inter-punctuation compression remains separate from this
portable line-edge feature.

`ParagraphOptions.punctuation.max_compression_fraction` adds a separate
CLREQ-style overfull-line stage. Eligible East Asian opening, closing,
exclamation, nonstarter, and infix punctuation contributes up to one half of
its glyph advance, scaled by the configured `0...1` limit. Compression first
uses adjacent punctuation gaps, then any remaining eligible side, and applies
only the minimum reduction needed to fit the already selected line. The
resulting advance/offset changes are explicit glyph geometry, so rendering,
caret, selection, bidi, retained reflow, attributed metadata, and ellipsis
remain synchronized. The default is zero.

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
in `src/unicode/vertical.zig`; the root Unicode API supplies only the resolved
script-family proof needed by that independent policy.

Cangjie deliberately does not own an editor or mutable text-buffer model.
Applications and UI toolkits compose the public Unicode segmentation,
paragraph, caret, selection, and hit-testing APIs with their own document,
history, IME, clipboard, and viewport state. This keeps the font/text stack
independent of any particular widget framework and avoids a second editor model
beside the application's native one.

`cangjie.paragraph.buildGeometry` and `buildStyledGeometry` provide the missing
platform-neutral accessibility bridge without introducing AccessKit or another
platform tree model. The owned result enumerates logical-order spans split by
line, final font run, resolved bidi direction, and optional style identity.
Each span carries paragraph-space bounds, UTF-8 source range, same-line
previous/next links, UAX #29 word-start indexes, and a flat range of source
graphemes with UTF-8 lengths, span-relative inline positions, and widths.
When one shaped glyph covers multiple source graphemes (for example a GSUB
ligature), Cangjie first reads the glyph's GDEF LigCaretList. CaretValue
formats 1, 2, and 3 are supported, including TrueType contour-point resolution
and GDEF 1.3 ItemVariationStore deltas at each final run's variation instance.
Complete, strictly increasing authored carets divide the glyph advance exactly;
missing, incomplete, unavailable, or out-of-range data falls back to equal
division rather than exposing invalid widths. `GraphemeGeometry` records which
case applied through `authored_ligature_caret`, so consumers never have to infer
precision from unequal widths. An RTL span reverses component assignment while
retaining logical grapheme order and decreasing visual positions. The builder
resolves bidi from source once rather than guessing from visual glyph order,
and its arrays remain valid after the shaping output buffer is reused. Platform
adapters can translate this stable data to AccessKit, UI Automation, AT-SPI, or
native application semantics.

The geometry owner also retains every final line independently from its spans,
including empty trailing-hard-break and empty-paragraph lines.
`TextGeometry.caret` maps an exact UTF-8 boundary plus upstream/downstream
affinity to a zero-width paragraph-space rectangle; the affinity distinguishes
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
physical-left-to-right order. A stop records the logical position selected when
arriving from either physical side, preserving bidi transitions where one x
coordinate has two logical meanings and zero-width controls where consecutive
topology steps share x. `nextVisualCaret`/`previousVisualCaret` traverse this
topology across soft wraps and GDEF-authored ligature boundaries without
storing mutable cursor state.

`nextLineCaret` and `previousLineCaret` extend the same topology vertically.
They accept a caller-retained preferred x and choose the nearest stop on the
adjacent line, naturally clamping to short or empty lines while resolving bidi
dual positions from the physical approach side. Keeping preferred x outside
the owner preserves repeatable vertical movement without introducing document
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
bidi visual ordering only after line ranges are known. Each line builds its own
bidi map from `ParagraphLine.byte_start/byte_len`; mixed LTR/RTL text therefore
reorders independently when a width change creates different line boundaries.

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

The protocol works with one-shot and styled layout, but retained
`ShapedParagraph` plus `ReflowBuffer` is the intended repeated-placement path:
Unicode analysis and whole-paragraph shaping stay immutable while each
response deterministically rebuilds only paragraph presentation. The current
implementation deliberately replays reflow after a response so exclusions,
dynamic line heights, ellipsis, justification, punctuation, bidi, caret
geometry, and rendering all observe one ordinary final layout. The internal
breaker can later retain an incremental checkpoint without changing this
public concrete protocol.
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
