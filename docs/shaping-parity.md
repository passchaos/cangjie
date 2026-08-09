# Shaping Parity And Performance Targets

Cangjie should not be described as exceeding industry implementations until the
claim is backed by both correctness and performance evidence. This document is
the working checklist for that bar.

## Reference Implementations

Local references to inspect before non-trivial shaping changes:

- `~/Work/harfbuzz`
- `~/Work/harfrust`
- `~/Work/fontations`
- `~/Work/freetype`

Use HarfBuzz as the primary shaping semantics reference. Use fontations for
modern table parsing structure, harfrust for the benchmark corpus and Rust
porting choices, and FreeType for font loading, legacy `kern`, and raster/font
infrastructure boundaries.

## Completion Bar

The goal is not complete until all of these are true:

- Correctness: Cangjie matches the reference output, or every intentional
  difference is documented, for the benchmark corpus and a broader script/font
  fixture set.
- Performance: Cangjie is faster than the strongest local reference on the
  same host for representative long text and word-list workloads, not only for
  isolated micro-cases.
- Coverage: GSUB, GPOS, GDEF, cmap, variation selector, feature override,
  script/language selection, legacy `kern`, and relevant variable-font behavior
  have explicit test or corpus coverage.
- Robustness: malformed supported tables are rejected before partial shaping
  results leak, and fuzz/corpus failures have stable regression tests.
- Structure: hot-path optimizations keep parsing, caching, layout, and
  benchmark/reporting concerns separated enough that large files do not keep
  absorbing unrelated logic.

## Current Required Benchmarks

Run these after shaping hot-path changes:

```sh
zig build test
zig build shape-bench -Doptimize=ReleaseFast -- --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-words.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --font ~/Work/harfrust/harfrust/benches/fonts/Roboto-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/en-words.txt --direction ltr --iterations 1 --warmup 1 --samples 2
zig build shape-bench -Doptimize=ReleaseFast -- --engine coretext --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --engine harfbuzz --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
```

Use `--profile` for targeting only. Profile mode applies Arabic GSUB feature
stages separately, so it is not the final performance number for the cached
feature-plan hot path.

For output parity against HarfRust, build the local CLI once:

```sh
(cd ~/Work/harfrust && cargo build --release -p hr-shape)
zig build shape-bench -Doptimize=ReleaseFast -- --engine harfrust --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text "سلام" --direction rtl --iterations 1 --warmup 0 --samples 1 --line-summary --glyph-summary
zig build shape-bench -Doptimize=ReleaseFast -- --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text "سلام" --direction rtl --iterations 1 --warmup 0 --samples 1 --line-summary --glyph-summary
zig build shape-bench -Doptimize=ReleaseFast -- --engine compare-harfrust --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text "سلام" --direction rtl
zig build shape-bench -Doptimize=ReleaseFast -- --engine compare-harfbuzz --font ~/Work/harfrust/harfrust/benches/fonts/Roboto-Regular.ttf --text "ffi" --direction ltr --disable-feature liga
```

Current USE corpus parity gate:

```sh
zig build shape-bench -Doptimize=ReleaseFast -- --engine compare-harfrust --font ~/Work/harfbuzz/perf/fonts/NotoSansDuployan-Regular.otf --text-file ~/Work/harfrust/harfrust/benches/texts/duployan.txt --direction ltr
```

The upstream HarfBuzz `in-house/tests/use.tests` regression set is retained
verbatim as one UTF-8 text corpus per fixture font under `tests/data/use/`.
Together the ten files cover all 17 upstream cases (Balinese, Tai Tham,
Chakma, Newa, Grantha/Vedic, Lepcha, Malayalam, Brahmi, and Kaithi). Run every
font against both references after USE, contextual GSUB, grapheme-cluster, or
source-metadata changes:

```sh
fonts=~/Work/harfbuzz/test/shape/data/in-house/fonts
for corpus in tests/data/use/*.txt; do
  hash=${corpus##*/}
  hash=${hash%.txt}
  zig build shape-bench -Doptimize=ReleaseFast -- \
    --engine compare-harfbuzz \
    --font "$fonts/$hash.ttf" \
    --text-file "$corpus" \
    --direction ltr
  zig build shape-bench -Doptimize=ReleaseFast -- \
    --engine compare-harfrust \
    --harfrust-bin ~/Work/harfrust/target/release/hr-shape \
    --font "$fonts/$hash.ttf" \
    --text-file "$corpus" \
    --direction ltr
done
```

The current expected aggregate checksums, identical for Cangjie, HarfBuzz, and
HarfRust, are:

| Font fixture | Cases | Checksum |
| --- | ---: | ---: |
| `23406a60ab081c4fb15e1596ea1cd4f27ae8443e` | 1 | `2f98be262c8e7b12` |
| `2a670df15b73a5dc75a5cc491bde5ac93c5077dc` | 5 | `9dad5d518d7788f1` |
| `4afb0e8b9a86bb9bd73a1247de4e33fbe3c1fd93` | 4 | `1e72f949bda7bd49` |
| `4cce528e99f600ed9c25a2b69e32eb94a03b4ae8` | 1 | `60ff4045de0745f` |
| `573d3a3177c9a8646e94c8a0d7b224334340946a` | 1 | `89190ef2a86420fc` |
| `6ff0fbead4462d9f229167b4e6839eceb8465058` | 1 | `e00d34dbd7f4bf67` |
| `7c24183f26d60df414578a0a9f5e79ab9d32a22b` | 1 | `d3bc11481ea14192` |
| `dcf774ca21062e7439f98658b18974ea8b956d0c` | 1 | `30fa5ca9dce7bacf` |
| `f518eb6f6b5eec2946c9fbbbde44e45d46f5e2ac` | 1 | `4caf38b3f8bfed32` |
| `fbb6c84c9e1fe0c39e152fbe845e51fd81f6748e` | 1 | `4e3bc2e9eb662fd1` |

Two additional upstream gates close the remaining compact USE test sets:

- `tests/data/use-indic3-tests.txt` retains the one
  `in-house/tests/use-indic3.tests` Kannada fixture. It verifies that a `knd3`
  ScriptList entry selects USE rather than the legacy Indic shaper
  (`3c96e7a303c58475a8c750bf4289bbe73784f37d.ttf`, checksum
  `32fc3493752ad1e9`).
- `tests/data/tai-tham-use-syllable-tests.txt` retains the four Tai Tham cases
  that were the only missing inputs from the 27-case
  `in-house/tests/use-syllable.tests` set
  (`3cc01fede4debd4b7794ccb1b16cdb9987ea7571.ttf`, checksum
  `4f94b265e784b828`). Together with the previously retained per-script files,
  all 27 inputs from that upstream test now have a local corpus gate.

Run each gate with both `compare-harfbuzz` and `compare-harfrust`, following the
same command pattern above. The Tai Tham slice specifically covers independent
SAKOT grapheme boundaries, three adjacent USE syllables, broken-syllable dotted
circle insertion without GDEF classes, and a synthetic base retaining its
advance instead of inheriting the broken mark's fallback class.

The complete 27-case set passes HarfRust 0.12 and matches the expected output
from the local HarfBuzz 14.3 checkout. System HarfBuzz 8.3 differs on the
already-retained Batak `U+1BC7,U+1BF3,U+1BF3` case by omitting the second
dotted circle; that older behavior is not used as the parity target.

The `harfbuzz` engine links the system HarfBuzz C library in-process and is the
preferred HarfBuzz timing baseline when the local development environment has
`pkg-config harfbuzz` available. It supports the shared `--enable-feature` /
`--disable-feature` overrides, `--glyph-summary` output, and
`compare-harfbuzz`, so focused HarfBuzz/Cangjie feature-diff fixtures can be
built without shelling out to `hb-shape`.

The `harfrust` engine shells out to `hr-shape` once per sample and uses
`hr-shape -n` for measured iterations. It is useful for batch output parity and
rough timing against HarfRust, but still includes external process startup and
serialization/parsing overhead. A library runner is still needed for strict
HarfRust timing.

`compare-harfrust` runs Cangjie and HarfRust in the same invocation and compares
per-line glyph-id, UTF-8 cluster, font-unit x/y advance, and x/y offset
sequences in HarfBuzz-style buffer order. When `--language` is not specified,
compare mode forces Cangjie to `dflt` because the current `hr-shape` runner
guesses script and direction but does not guess language. Pass `--language ara`,
`--language zhs`, etc. to compare an explicit LangSys on both engines.

## Current Evidence Snapshot

Latest retained optimization commit before this parity work:

- `266a5ec Fast path accelerated GSUB context records`

Representative performance state near that commit:

- Amiri `fa-thelittleprince`, Cangjie: about `1705 ns/glyph` median.
- Amiri `fa-words`, Cangjie: about `1970 ns/glyph` median.
- Roboto `en-words`, Cangjie: about `1118 ns/glyph` median.
- Amiri `fa-thelittleprince`, CoreText: about `1233 ns/glyph` median.

Current local snapshot after the Nastaliq parity work:

- Amiri `fa-thelittleprince`, Cangjie default visual-order path: about
  `2079 ns/glyph` median after reusing GPOS/GSUB accelerator proofs to skip
  repeated first-input coverage checks in chaining format 3 subtables.
- Amiri `fa-thelittleprince`, Cangjie with `--no-bidi-reorder`: about
  `1496 ns/glyph` median.
- Amiri `fa-thelittleprince`, CoreText: about `1263 ns/glyph` median.
- HarfRust Criterion in-process reference for Amiri `fa-thelittleprince`:
  about `48.2 ms` per full text for HarfRust and `54.9 ms` for HarfBuzz
  through `harfbuzz_rs`; Cangjie remains multiple times slower on the same
  workload, so the performance goal is not close to complete.
- A profile run after the GPOS range-search change reduced Amiri
  `fa-thelittleprince` GPOS time from about `155 ms` to about `111 ms`; lookup
  `74` fell from about `24.4 ms` to `5.7 ms`, and lookup `57` from about
  `21.0 ms` to `6.1 ms`. The host was not fully idle, so use this as hotspot
  direction rather than a final headline benchmark.
- A later profile run after the accelerated GSUB chaining format 3 fast path
  reduced Amiri `fa-thelittleprince` GSUB profile time from about `308 ms` to
  about `257 ms`; the Arabic `calt` stage fell from about `207 ms` to
  `172 ms`.
- Reusing the same first-input coverage proof in accelerated GPOS chaining
  format 3 reduced Amiri GPOS profile time from about `100 ms` to `92.8 ms`;
  lookup `37` fell from about `34.0 ms` to `30.1 ms`.
- Skipping redundant contextual Coverage validation after parse-time GPOS proof
  reduced a later Amiri `fa-thelittleprince --no-bidi-reorder` profile from
  about `216 ms` to `172 ms`; GPOS fell from about `65.7 ms` to `34.7 ms`, and
  lookup `37` from about `32.7 ms` to `4.8 ms`.
- The new in-process HarfBuzz baseline on the same Amiri workload measured
  HarfBuzz at about `737 ns/glyph` median versus Cangjie at about
  `2015 ns/glyph` median with `--no-bidi-reorder` in the same validation pass.
- After the retained pure-RTL bidi, GSUB/GPOS accelerator, CPAL/STAT metadata,
  and chaining-record work through `eaf4908`, the same in-process HarfBuzz
  baseline still measures Amiri `fa-thelittleprince` at about `738 ns/glyph`
  median while Cangjie is about `1790 ns/glyph` median on the default RTL
  visual-order path.  This is a meaningful improvement from the older
  `~2.0 µs/glyph` Amiri state, but Cangjie is still roughly `2.4x` slower than
  HarfBuzz on this workload.
- Reusing GSUB run digests across consecutive no-op format-3 chaining lookups
  reduced a same-session, five-sample Amiri `fa-thelittleprince` median from
  `1769 ns/glyph` at commit `0e38374` to `1700 ns/glyph`, about a `3.9%`
  improvement. The cache is invalidated by a mutation generation after any
  substitution so later lookups see newly produced glyphs. A table-level
  capability bit avoids generation bookkeeping for fonts without an applicable
  chaining accelerator; the paired Roboto `en-words` smoke run did not regress
  (`949 ns/glyph` baseline versus `931 ns/glyph` candidate in that session).
- Validating all source-parallel GSUB metadata requirements once per cached
  feature plan, instead of once again for every Arabic feature stage, reduced
  a later same-session Amiri `fa-thelittleprince` median from
  `1793 ns/glyph` to `1644 ns/glyph`, about `8.3%`. A `perf` sample after the
  change measured about `1640 ns/glyph` over ten iterations and no longer
  reported `validateShapingMetadata` among functions above the `0.5%` cutoff.
  The paired Roboto `en-words` medians were `971 ns/glyph` for the baseline and
  `964 ns/glyph` for the candidate, with identical checksums.
- Inlining the overwhelmingly common zero-flag and `IgnoreMarks` glyph-filter
  branches in GSUB and GPOS, while keeping mark-set and attachment filtering in
  a cold helper, reduced a same-session seven-sample Amiri
  `fa-thelittleprince` median from `1635 ns/glyph` to `1618 ns/glyph`, about
  `1.1%`. The corresponding Roboto `en-words` medians were `974 ns/glyph`
  baseline and `964 ns/glyph` candidate. A follow-up `perf` sample no longer
  showed the common filter as an out-of-line symbol; only the genuinely complex
  GPOS path remained, at about `0.2%`.
- Recording whether an accelerated GSUB chaining lookup has any second input
  avoids resolving the next unignored glyph for its single-input subtables.
  Amiri contains 26 coverage-only chaining lookups whose every subtable has one
  input. A same-session nine-sample `fa-thelittleprince` comparison reduced the
  median from `1612 ns/glyph` to `1602 ns/glyph`, about `0.6%`; Roboto
  `en-words` remained effectively flat (`962 ns/glyph` in both runs).
- Replacing binary search over accelerated GSUB first-input groups with a
  bounded open-addressed `u16` slot table reduced a subsequent same-session
  nine-sample Amiri `fa-thelittleprince` median from `1600 ns/glyph` to
  `1448 ns/glyph`, about `9.5%`. Lookups with fewer than eight groups retain
  binary search; larger lookups use a power-of-two table at no more than 50%
  load, totaling only 14,912 bytes for Amiri. The associated `perf` run
  measured `1443 ns/glyph`, reduced the chaining lookup share from about
  `28.9%` to `21.8%`, and no longer reported the group-search function
  separately.
- Applying the same bounded group index to GPOS lookup-level exact-coverage
  filters and chaining subtable selection reduced the next nine-sample Amiri
  `fa-thelittleprince` median from `1442 ns/glyph` to `1320 ns/glyph`, about
  `8.5%`. The two GPOS slot-table families total about 46,336 bytes for Amiri.
  A follow-up `perf` run measured `1343 ns/glyph`, reduced
  `collectLookupWithIndex` from about `13.6%` to `8.0%`, and removed its group
  binary search as a separate symbol. A reverse-order nine-sample Roboto
  `en-words` check also improved from `1006 ns/glyph` to `954 ns/glyph`.
- Predecoding single-subtable GSUB `SingleSubst` mappings into native-endian
  sorted `(from, to)` records moved top-level application off the generic
  Coverage parser. The records cost four bytes per mapping: about 18.5 KiB for
  Amiri and 3.2 KiB for Roboto. A same-session nine-sample Amiri
  `fa-thelittleprince` median fell from `1329 ns/glyph` to `1268 ns/glyph`,
  about `4.5%`; a reverse-order Roboto `en-words` comparison improved from
  `955 ns/glyph` to `924 ns/glyph`. Follow-up `perf` no longer reported
  top-level `applySingleSubstitution`, and reduced `coverageIndex` from about
  `8.6%` to `5.1%`.
- Direct coverage-only GSUB chaining lookups now reuse the accelerator's
  parse-time format proof instead of rescanning every subtable before each
  application. A same-session eleven-sample Amiri `fa-thelittleprince` median
  improved from `1270 ns/glyph` to `1249 ns/glyph`, about `1.6%`; a
  reverse-order nine-sample Roboto `en-words` check improved from
  `919 ns/glyph` to `913 ns/glyph`. The generic runtime format walk remains for
  uncached low-level calls and mixed-format lookups.
- Predecoding LigatureSubst definitions and component sequences into
  native-endian accelerator arrays removed repeated binary table reads from
  Roboto's dominant `liga` lookup. A same-session nine-sample
  `en-words` median improved from about `910 ns/glyph` to `615 ns/glyph`,
  about `32%`; lookup 6 profile time fell from about `33.4 ms` to `13.3 ms`.
  Font-authored LigatureSet priority and LookupFlag-skipped component offsets
  have dedicated tests. Full Roboto `en-words` and Amiri
  `fa-thelittleprince` still pass in-process HarfBuzz parity. A seven-sample
  Amiri no-bidi-reorder check also improved slightly from about
  `1050 ns/glyph` to `1042 ns/glyph`.
- Large predecoded LigatureSubst lookups now use HarfBuzz's second-component
  prefilter: the next non-ignored glyph is found once and reused while
  definitions remain in font-authored preference order. A lookup-level cost
  model enables the larger matcher only at 32 competing definitions, keeping
  small Arabic lookups on the original direct path. In a fixed-CPU-30 ABBA
  comparison with four 15-sample medians per binary, Roboto `en-words`
  improved from `477.678 ns/glyph` to `429.937 ns/glyph`, about `10.0%`.
  Amiri `fa-thelittleprince` was effectively flat at `1405.212` versus
  `1407.046 ns/glyph` (`+0.13%`, within run noise). Both corpora retained full
  in-process HarfBuzz parity.
- Format-3 chaining accelerators now predecode the first backtrack and
  single-input lookahead Coverage digests. Each candidate position resolves
  those adjacent non-ignored glyphs at most once, then rejects incompatible
  subtables before the full context matcher. A fixed-CPU-30 ABBA comparison
  with four 15-sample medians per binary reduced Roboto `en-words` from
  `432.245 ns/glyph` to `404.817 ns/glyph`, about `6.35%`; Amiri
  `fa-thelittleprince` remained effectively flat at `1406.159` versus
  `1408.387 ns/glyph` (`+0.16%`). Roboto lookup 4 profile time fell from about
  `3.90 ms` to `2.10 ms`, and full Roboto and Amiri HarfBuzz parity remained
  unchanged.
- Predecoding xAdvance-only PairPos format-1 records into sorted native-endian
  `(first, second, advance)` records reduced the next same-session Roboto
  `en-words` median from about `627 ns/glyph` to `570 ns/glyph`, about `9%`.
  GPOS lookup 1 profile time fell from about `22.1 ms` to `18.1 ms`. Ordered
  subtable alternatives remain intact: a zero-valued format-1 pair still
  suppresses a later class-pair fallback. Full Roboto `en-words` and Amiri
  `fa-thelittleprince` continue to pass in-process HarfBuzz parity.
- Extending the same accelerator to xAdvance-only PairPos format-2 subtables
  predecoded first-glyph coverage, sparse class maps (including implicit class
  zero), and the class matrix. The next eleven-sample Roboto `en-words` median
  improved from about `569 ns/glyph` to `481 ns/glyph`, about `15.4%`.
  GPOS lookup 1 profile time fell from about `18.7 ms` to `5.9 ms`; full Roboto
  and Amiri corpus parity remained unchanged.
- Testing the GSUB chaining lookup's three-mask first-input digest before its
  exact group index now rejects definite misses ahead of source-feature, GDEF,
  and hash-table work. The digest was already built for whole-run filtering, so
  this adds no per-font storage and follows HarfBuzz's forward lookup order. A
  fixed-CPU-30 ABBA comparison with four 11-sample medians per binary reduced
  Amiri `fa-thelittleprince` from an average `1407.971 ns/glyph` to
  `1173.736 ns/glyph`, about `16.6%`. A separate Roboto `en-words` ABBA check
  improved from `414.100 ns/glyph` to `401.390 ns/glyph`, about `3.1%`, and
  Amiri `fa-words` improved from `2023.398 ns/glyph` to
  `1953.247 ns/glyph`, about `3.5%`. Full Amiri and Roboto in-process HarfBuzz
  parity remained unchanged. A follow-up profile reduced
  `applyChainingContextSubstitutionLookup` from about `28.9%` to `20.0%` of
  sampled cycles, though it remains the largest isolated shaping hotspot.
- Parsing a MarkBasePos format-1 subtable once per run-level collection, rather
  than once again for every candidate glyph, removes repeated validated header,
  Coverage-offset, and anchor-array-offset reads while retaining a separately
  parsed single-target path for contextual PosLookupRecords. A fixed-CPU-30
  reverse ABBA check with two 21-sample medians per binary reduced Amiri
  `fa-thelittleprince` from an average `1183.588 ns/glyph` to
  `1150.684 ns/glyph`, about `2.8%`. A four-median 15-sample Amiri `fa-words`
  check was effectively flat to slightly better (`1925.188` versus
  `1920.362 ns/glyph`), and Roboto `en-words` remained within noise
  (`406.237` versus `406.005 ns/glyph`). Full Amiri long-text and word-list
  plus Roboto word-list in-process HarfBuzz parity remained unchanged.
- MarkBasePos accelerators now retain native-endian Coverage format-1 glyph
  arrays and format-2 range records, preserving coverage indexes without
  expanding large ranges. This removes repeated bounds checks and big-endian
  reads from both mark and base searches. A fixed-CPU comparison with four
  medians per binary improved Amiri `fa-thelittleprince` from
  `1153.733 ns/glyph` to `1112.239 ns/glyph`, about `3.6%`; Roboto
  `en-words` improved from `409.011 ns/glyph` to `406.619 ns/glyph`, about
  `0.6%`, and Amiri `fa-words` improved from `1921.269 ns/glyph` to
  `1907.787 ns/glyph`, about `0.7%`. The accelerator storage is 1,998 bytes
  for Amiri and 3,712 bytes for Roboto. A follow-up profile reduced generic
  GPOS `coverageIndex` from about `7.1%` to `3.8%` of sampled cycles and no
  longer reports MarkBase collection as a separate hotspot. Full parity for
  all three corpora remained unchanged.
- Format-3 GPOS chaining accelerators now reuse the same native-endian Coverage
  representation for their input, backtrack, and lookahead regions. The common
  single-input/single-lookahead fast path and the general cached matcher no
  longer reread Coverage offsets or big-endian records per candidate. A
  fixed-CPU comparison with four medians per binary reduced Amiri
  `fa-thelittleprince` from `1109.091 ns/glyph` to `1070.655 ns/glyph`, about
  `3.5%`; an eight-median 21-sample word-list check improved `fa-words` from
  `1904.839` to `1869.466 ns/glyph`, about `1.9%`. Roboto `en-words` was flat
  (`408.850` versus `408.847 ns/glyph`) because that font has no direct
  format-3 GPOS chaining lookup. Amiri's 209 cached context Coverages cost
  5,706 bytes without expanding format-2 ranges. Full parity for all three
  corpora remained unchanged.
- Coverage-only GPOS chaining lookups now skip the lookup-level exact group
  preflight because their grouped collector performs the same lookup as its
  first operation for every glyph. A miss no longer scans the run once in the
  preflight and once in the collector, while a hit no longer scans the prefix
  twice. This adds no accelerator storage. Four fixed-CPU medians reduced Amiri
  `fa-thelittleprince` from `1071.944 ns/glyph` to
  `1064.520 ns/glyph`, about `0.7%`, and a four-median 31-sample
  `fa-words` check improved from `1866.696` to `1851.023 ns/glyph`, about
  `0.8%`. Roboto `en-words` remained flat (`406.629` versus
  `406.511 ns/glyph`), and full parity for all three corpora was unchanged.
- GPOS chaining collectors now use the existing first-input Coverage digest as
  a per-glyph prefilter on runs of at least 16 glyphs, where its three bit tests
  amortize over avoided exact group probes. Short word-sized runs compile to a
  separate unfiltered loop and retain the prior hot path. Two reverse-order
  31-sample medians reduced Amiri `fa-thelittleprince` from
  `1066.742 ns/glyph` to `1052.593 ns/glyph`, about `1.3%`. Roboto
  `en-words` improved from `408.582` to `406.415 ns/glyph`, about `0.5%`;
  Amiri `fa-words` remained effectively flat (`1854.894` versus
  `1855.722 ns/glyph`, a `0.045%` difference). The digest adds no storage,
  exact group lookup still resolves false positives, and full parity for all
  three corpora was unchanged.
- RTL bidi-map construction now walks grapheme clusters and logical items with
  one shared backward cursor. The previous implementation searched the full
  logical item array once per grapheme, making long RTL runs effectively
  quadratic. A fixed-CPU-30 ABBA comparison with four 15/21-sample medians per
  binary reduced Amiri `fa-thelittleprince` from an average
  `1110.128 ns/glyph` to `943.117 ns/glyph`, about `15.0%`. Profiled bidi time
  fell from about `21.4 ms` to `9.1 ms`, and `logicalRangeForBytes` disappeared
  from sampled hotspots; GSUB/GPOS stage times were unchanged. A neighboring
  31-sample Roboto-only A/B/B/A check was flat (`435.000` versus
  `435.047 ns/glyph`). Amiri still trails the same-session in-process
  HarfBuzz median (`795.825 ns/glyph`) by about `18.5%`, down from roughly
  `39.5%`, so the overall performance goal remains open. HarfBuzz and HarfRust
  parity both retain checksum `f2da7bb39eb7323a`.
- RTL shaping input now classifies cluster-inheriting Arabic marks through an
  out-of-line, Unicode 17-specific 11-range predicate instead of invoking the
  full ordered script classifier followed by the all-script combining-mark
  table for every scalar. This also closes missing modern Arabic Mn coverage
  for U+0898–U+089F, U+08CA–U+08FF, and supplementary
  U+10EFD–U+10EFF; focused HarfBuzz/HarfRust output matches at checksum
  `7cb1b7bd03a57f5d`. A fixed-CPU-30 A/B/B/A comparison with 31-sample medians
  reduced Amiri `fa-thelittleprince` from `944.499` to
  `909.871 ns/glyph`, about `3.7%`. Profiled cmap/input-map time fell from
  about `7.13 ms` to `4.57 ms`, about `35.9%`, and the old
  `inheritsPreviousClusterInRtlShaping -> scriptForCodepoint/isCombiningMark`
  stack disappeared from sampled hotspots. Roboto timing was frequency-noisy,
  but `perf stat` showed slightly fewer instructions (`-0.022%`) and branches
  (`-0.027%`), confirming no added LTR work. Full Amiri, Amiri word-list, and
  Roboto checksums remain unchanged.
- Arabic joining-form resolution now streams once through the source run,
  retaining only the previous non-transparent Joining_Type and one pending
  Arabic character. The former implementation searched both backward and
  forward for every Arabic scalar and repeatedly binary-searched the joining
  table. A 4,680-sequence exhaustive test (lengths one through four over
  Arabic dual/right/non-joining/transparent characters, ZWJ/ZWNJ, Syriac, and
  separators) proves the new state machine matches the former semantics.
  Unicode 17 U+10EFD–U+10EFF are now also Arabic-script Transparent joining
  marks; the focused `BEH + U+10EFD + BEH` HarfBuzz/HarfRust checksum is
  `fee2f1ada1c3d897`. A fixed-CPU-30 A/B/B/A comparison with 31-sample medians
  reduced Amiri `fa-thelittleprince` from `920.404` to
  `887.327 ns/glyph`, about `3.6%`, and `fa-words` from `1883.453` to
  `1859.196 ns/glyph`, about `1.3%`. Roboto improved slightly from `435.915`
  to `434.621 ns/glyph`. `resolveJoiningForms` and
  `joiningTypeForCodepoint` disappeared as standalone perf hotspots. The
  same-session HarfBuzz median was `796.355 ns/glyph`, leaving Cangjie about
  `11.4%` behind on this Amiri workload; the broad performance goal is still
  open.
- `buildBidiMap` now feeds its already-decoded and already-classified logical
  items into the same `BidiRunBuilder` used by public run itemization. It
  previously decoded the UTF-8 and ran `bidiClassForCodepoint` /
  `scriptForCodepoint` a second time solely to rebuild run boundaries. Direct
  mixed LTR/RTL/number/neutral tests prove logical-item runs match the public
  text itemizer. A fixed-CPU-30 A/B/B/A comparison with 31-sample medians
  reduced Amiri `fa-thelittleprince` from `889.111` to
  `881.534 ns/glyph`, about `0.85%`, and Roboto `en-words` from `437.294` to
  `434.705 ns/glyph`, about `0.59%`. Amiri `fa-words` was effectively flat
  (`1854.735` versus `1856.595 ns/glyph`, `+0.10%`) because each short line
  amortizes little duplicate classification. Profiled bidi time fell from
  about `9.24 ms` to `8.72 ms`, about `5.6%`, while output checksums remained
  unchanged.
- Ligature component provenance now keeps an 8-byte handle beside each glyph
  and stores source positions only for actual ligatures in an append-only
  pool. Ordinary glyphs previously carried a 528-byte inline 64-entry array;
  MultipleSubst outputs now copy and share one compact handle rather than
  copying that array. Source-index renumbering scans each pooled source once,
  so shared handles cannot apply an insertion shift repeatedly. A serial
  fixed-CPU-30 A/B/B/A run with 31-sample medians reduced Amiri
  `fa-thelittleprince` from `878.335` to `837.997 ns/glyph`, about `4.6%`,
  and Roboto `en-words` from `432.246` to `404.230 ns/glyph`, about `6.5%`.
  An eight-median complementary A/B/B/A plus B/A/A/B word-list check improved
  Amiri `fa-words` from `1860.685` to `1824.369 ns/glyph`, about `2.0%`.
  On a five-sample Amiri run, maximum RSS fell from 7,680 to 6,912 KiB. A
  post-change `perf` sample reported generic `memcpy` at about `0.12%`, down
  from about `3.30%` in the independent baseline; compact provenance-array
  growth was about `0.25%`. Full Amiri long-text/word-list, Roboto, HarfRust
  Indic, and retained USE parity checksums remained unchanged.
- Validated GSUB/GPOS lookup accelerators now retain each Lookup's offset,
  type, flag, subtable count, and optional mark-filtering-set index. The shaping
  hot path previously reparsed and revalidated that variable-length header for
  every lookup on every line despite already owning one accelerator per lookup.
  Unvalidated low-level calls and stale/mismatched accelerators still use the
  bounds-checked parser; focused tests cover that fallback, the `0xffff`
  mark-set index, and cached mark-filtering semantics. A final serial
  fixed-CPU-30 B/A/A/B comparison with 31-sample medians reduced Amiri
  `fa-thelittleprince` from `839.309` to `816.077 ns/glyph`, about `2.8%`;
  Amiri `fa-words` from `1827.177` to `1360.967 ns/glyph`, about `25.5%`; and
  Roboto `en-words` from `404.441` to `359.231 ns/glyph`, about `11.2%`.
  The larger short-line gains reflect amortizing the same selected lookup
  schedule across thousands of separately shaped words. Accelerator size grows
  by 16 bytes per lookup (about 4.5 KiB for Amiri and 784 bytes for Roboto).
  Post-change `perf` no longer reports GSUB fixed-header validation, previously
  about `1.5%`; all three corpus checksums and the retained USE gate remain
  unchanged. The same-session Amiri HarfBuzz median was `796.567 ns/glyph`
  versus Cangjie's `815.637 ns/glyph`, narrowing the remaining long-text gap to
  about `2.4%`.
- Bidi visual-order indexing now detects the normal monotone-cluster glyph
  stream in one pass and uses its existing `(cluster, glyph_index)` order
  directly. Script-reordered or mixed native-direction streams still use the
  previous heap sort, so the general ordering contract is unchanged. A serial
  fixed-CPU-30 A/B/B/A run with 31-sample medians reduced Amiri
  `fa-thelittleprince` from `816.200` to `792.650 ns/glyph`, about `2.9%`;
  a reverse B/A/A/B run improved `816.383` to `797.972 ns/glyph`, about
  `2.3%`. Amiri `fa-words` improved `0.2–0.5%`, while Roboto `en-words`
  improved `0.9–1.2%`; all checksums remained unchanged. The post-change
  `perf` sample no longer reports the bidi heap-sort symbol, previously about
  `2.7%`. In the same final Cangjie/HarfBuzz/HarfBuzz/Cangjie sequence, the
  Amiri long-text medians were `793.535` versus `796.110 ns/glyph`, a narrow
  Cangjie lead of about `0.3%`. This is one workload, not evidence that the
  broader cross-font performance goal is complete.
- Coarse bidi classification now handles ASCII, European/Arabic-Indic digits,
  and the authoritative Arabic/Hebrew script ranges before entering the full
  all-script classifier. The LTR paragraph preflight also skips ASCII outright
  because no ASCII scalar has a strong RTL class. A full Unicode scalar-space
  differential test proves every fast-path result matches the original
  number-or-script classification. Fixed-CPU-30 A/B/B/A and reverse B/A/A/B
  comparisons with 31-sample medians reduced Amiri `fa-thelittleprince` by
  `3.1–3.2%` and `fa-words` by `1.6–2.2%`. An additional eight-median
  complementary Roboto check was effectively flat but slightly faster
  (`360.293` versus `360.072 ns/glyph`, about `0.06%`). Post-change `perf`
  reduced the bidi-map `scriptForCodepoint` path from about `3.1%` to about
  `0.4%`. All corpus and retained USE checksums remained unchanged. A final
  Cangjie/HarfBuzz/HarfBuzz/Cangjie sequence measured Amiri long text at
  `766.959` versus `795.355 ns/glyph`, a Cangjie lead of about `3.6%`.
  Amiri and Roboto word lists still trail HarfBuzz, so this does not complete
  the broader objective.
- GSUB and GPOS run-digest caches now initialize only their readable headers
  (`len` and GSUB's mutation generation). Inactive digest entries are written
  before `len` exposes them, but aggregate `{}` construction previously cleared
  all 16 entries—784 bytes for GSUB and 520 bytes for GPOS—on every shaped
  word. Fixed-CPU-30 A/B/B/A and reverse B/A/A/B comparisons with 31-sample
  medians reduced Roboto `en-words` by about `7–9%`, Amiri `fa-words` by about
  `2–6%`, and Amiri `fa-thelittleprince` by about `0.3–0.4%`, with unchanged
  checksums. Post-change Roboto `perf` reduced generic `memset` from about
  `7.0%` to `0.8%`; the two Font-wrapper cache clears disappeared from the
  sampled stacks.
- Validated, non-profiled GSUB now dispatches predecoded ligature and
  coverage-only chaining lookups through a small fast wrapper. The generic
  dispatcher still owns every unvalidated, profiled, unsupported, and
  mismatched-accelerator path, but no longer imposes its roughly 10 KiB unified
  stack frame on each tiny cached lookup. Fixed-CPU-30 A/B/B/A and reverse
  B/A/A/B comparisons with 31-sample medians improved Roboto `en-words` by
  about `1.3–1.8%` and Amiri `fa-words` by about `0.3%`. Four additional
  interleaved medians showed Amiri `fa-thelittleprince` effectively flat
  (`766.525` versus `766.267 ns/glyph`, about `0.03%` faster). Post-change
  Roboto `perf` reduced top-level `applyLookupWithIndex` from about `22%` to
  `4.5%`; the remaining GSUB share is now the actual accelerated ligature
  matching work. Dedicated tests exercise both accelerated chaining and
  ligature dispatch, while all corpus checksums remain unchanged.
- Ligature matchers now write component offsets into one caller-owned scratch
  array and return a compact match containing a pointer to that storage.
  Previously every optional match embedded a 64-entry `usize` array, causing
  failed candidates to construct/clear a roughly 512-byte payload and successful
  matches to copy it. Nested lookup results still copy offsets only after a real
  match must outlive the scratch. Fixed-CPU-30 A/B/B/A and serial reverse
  B/A/A/B runs with 31-sample medians improved Roboto `en-words` by about
  `3.2–3.9%` and Amiri `fa-thelittleprince` by about `0.3%`. An additional
  eight-median complementary Amiri `fa-words` check improved the mean by
  `1.0%` and median by `1.25%`. Matcher assembly/perf no longer shows the
  repeated 64-slot zero stores, and all parity checksums remain unchanged.
- Default shape-plan and lookup-selection keys now reserve zero for empty
  feature-override and variation-coordinate slices instead of constructing and
  finalizing Wyhash state for values with no payload. Non-empty inputs retain
  their existing payload-sensitive hashes, and lookup-selection hits still
  compare the complete feature slices. Serial fixed-CPU-30 A/B/B/A and reverse
  B/A/A/B comparisons, with four 31-sample medians per binary in each order,
  reduced the combined Roboto `en-words` median from `323.938` to
  `321.207 ns/glyph`, about `0.84%`, and Amiri `fa-words` from `1296.696` to
  `1294.172 ns/glyph`, about `0.19%`. Amiri `fa-thelittleprince` remained
  within noise: the combined median favored the candidate by `0.39%`, while
  symmetrically trimming each binary's highest and lowest median yielded a
  `0.08%` improvement. Post-change Roboto `perf` reduced `Wyhash.final` from
  about `3.88%` to `2.91%`; the `layout_cache.lookupSelectionKey` child,
  previously about `0.68%`, disappeared. All corpus and retained USE parity
  checksums remain unchanged.
- Default-ignorable classification now rejects every scalar below U+00AD in
  one comparison. U+00AD SOFT HYPHEN is the lowest scalar in the shaping set,
  so this authoritative bound avoids the full singleton/range chain for ASCII
  while preserving variation selectors and all higher default-ignorables.
  Serial fixed-CPU-30 A/B/B/A and reverse B/A/A/B comparisons, with four
  31-sample medians per binary in each order, reduced the combined Roboto
  `en-words` median by about `0.92%` (a symmetrically trimmed mean improved
  `321.432` to `319.079 ns/glyph`, about `0.73%`). Amiri
  `fa-thelittleprince` and `fa-words` also remained slightly faster: trimmed
  means improved about `0.21%` each. In a same-baseline Roboto `perf` sample,
  `unicode.isDefaultIgnorableForShaping` fell from about `2.65%` to a residual
  `0.20%` child and disappeared as a standalone hotspot. All corpus and
  retained USE parity checksums remain unchanged.
- The cmap pass now reserves all eight parallel glyph/source metadata arrays
  once from the validated UTF-8 byte length, a safe upper bound because each
  retained scalar consumes at least one byte and variation selectors consume
  no glyph/source slot. The scalar loop can consequently use assume-capacity
  appends instead of repeating eight capacity checks per glyph; later USE and
  GSUB cardinality changes retain their existing checked growth paths. Serial
  fixed-CPU-30 A/B/B/A and reverse B/A/A/B comparisons, with four 31-sample
  medians per binary in each order, reduced symmetrically trimmed means for
  Amiri `fa-thelittleprince` from `763.914` to `748.469 ns/glyph`, about
  `2.02%`; Amiri `fa-words` from `1293.898` to `1288.255 ns/glyph`, about
  `0.44%`; and Roboto `en-words` from `319.236` to `309.804 ns/glyph`, about
  `2.96%`. Post-change Roboto `perf` no longer reports the cmap-loop
  `usize`, `u16`, provenance-info, and `u21` capacity checks, which previously
  accounted for about `1.74%`, `0.89%`, `0.30%`, and `0.24%`, respectively.
  Five-sample Amiri long-text probes reported the same 6,912 KiB maximum RSS
  for baseline and candidate. All corpus and retained USE parity checksums
  remain unchanged.
- Modified combining-class lookup now returns zero before consulting the
  generated CCC table for scalars below U+0300, the first Unicode scalar with a
  non-zero canonical combining class. All shaping-specific overrides are also
  above this boundary, so ASCII and Latin-1 mark-order scans avoid a binary
  search without weakening SAKOT/PADMA/Tibetan ordering. Serial fixed-CPU-30
  A/B/B/A and reverse B/A/A/B comparisons, with four 31-sample medians per
  binary in each order, reduced the symmetrically trimmed Roboto `en-words`
  mean from `310.333` to `300.964 ns/glyph`, about `3.02%`; Amiri
  `fa-thelittleprince` improved from `753.668` to `748.335 ns/glyph`, about
  `0.71%`; and Amiri `fa-words` remained effectively flat but slightly faster
  (`1288.538` to `1287.916 ns/glyph`, about `0.05%`). Post-change Roboto
  `perf` no longer reports `layout.markSortClass` above the `0.1%` threshold;
  it was about `2.33%` in the same-baseline profile. All corpus and retained
  USE parity checksums remain unchanged.
- A final fixed-CPU-30 absolute Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix at
  commit `30984d9` measured Amiri `fa-thelittleprince` at `765.566` versus
  `794.637 ns/glyph`, a Cangjie lead of about `3.66%`; Amiri `fa-words` at
  `1293.856` versus `1246.225 ns/glyph`, a Cangjie deficit of about `3.82%`;
  and Roboto `en-words` at `320.234` versus `229.665 ns/glyph`, a Cangjie
  deficit of about `39.4%`. These are workload-specific local measurements;
  the broader cross-font performance objective remains active.
- The retained Gulzar 1,000-line `fa-words` probe remains a Cangjie win:
  current medians are about `9733 ns/glyph` for Cangjie versus
  `12230 ns/glyph` for in-process HarfBuzz, with the same
  `compare-harfbuzz` parity checksum `b30b30028735cdb5`.

Current HarfRust glyph-id, UTF-8 cluster, advance, and offset parity evidence:

- Amiri `"آیت‌الله"` passes `compare-harfrust`.
- Amiri `"اللَّهِ"` passes `compare-harfrust`.
- Amiri `"تثبیت"` passes default `compare-harfrust`; it also passes with
  `--language ara`.
- Amiri `fa-words.txt` passes default `compare-harfrust` for 10,000 lines and
  `compare-harfbuzz` for 10,000 lines (`checksum=246e98435cc9c642`).
- Roboto `en-2letters.txt` passes `compare-harfrust` for 12,391 lines and
  `compare-harfbuzz` for 12,391 lines; focused `"ffi"` also passes
  `compare-harfbuzz --disable-feature liga`.
- Roboto `en-words.txt` passes `compare-harfrust` for 12,391 lines.
- Roboto `en-thelittleprince.txt` passes `compare-harfrust` for 1,172 lines.
- SourceSerifVariable `en-words.txt` passes `compare-harfrust` for 12,391
  lines and `compare-harfbuzz` for 12,391 lines
  (`checksum=8e73660271918db0`).
- SourceSerifVariable `en-thelittleprince.txt` passes `compare-harfrust` for
  1,172 lines and `compare-harfbuzz` for 1,172 lines
  (`checksum=6b0306bd714da380`).
- SourceSerifVariable `react-dom.txt` passes `compare-harfrust` and
  `compare-harfbuzz` for 24,709 non-empty lines and 1,042,546 glyphs
  (`checksum=70fbecf4b19785ef` for HarfBuzz).
- Amiri `fa-thelittleprince.txt` passes default `compare-harfrust` for 771
  lines and `compare-harfbuzz` for 771 lines (`checksum=f2da7bb39eb7323a`).
- Gulzar now parses and focused `"سلام"` passes default `compare-harfbuzz`
  (`checksum=8263e47a0b8deac1`); this covers nested contextual GPOS `kern`
  recursion through ExtensionPos into PairPos. Focused `"این"` also passes
  after enabling nested ExtensionSubst ContextSubst recursion to reach the
  `ddb -> ddb.one` substitution path. `fa-words` now passes the first 1,000-line
  `compare-harfbuzz` probe (`checksum=b30b30028735cdb5`), including the
  previously blocking `"تغییرمسیر"` reverse-chain ordering case.
- NotoNastaliqUrdu `fa-words.txt` passes `compare-harfrust` for 10,000 lines,
  and `fa-thelittleprince.txt` passes for 771 lines; focused blockers `"سلام"`,
  `"به"`, `"ویکی‌پدیا"`, `"هجری"`, `"جزء"`, `"اللَّهِ"`, and `"اللَّهُ"` pass
  individually.
- NotoSansDevanagari parses and focused words `के`, `कि`, `की`, `का`,
  `श्रेणी`, `वार्ता`, `वर्षों`, `उत्तराखण्ड`, `हिन्दी`, `द्वारा`, `रूप`,
  `फ़िल्म`, `क्षेत्र`, `स्थित`, `एक्स्प्रेस`, `सन्`, `व्यक्ति`, `ा`,
  `अंग्रेज़ी`, `सिद्धांत`, `पुनः`, `ज़्यादा`, `सन्‌`, `ि`, `अवार्ड्स`,
  `वर्ल्ड`, `चार्ल्स`, `्य`, `स्‍थान`, `ब्रिटिश`, `स्वागत`, `द्वितीय`, and
  `ट्विटर`, `वैश्विक`, `श्वि`, `क्वि`, and `ट्वि` pass `compare-harfrust`.
- NotoSansDevanagari `hi-words.txt` passes both `compare-harfrust` and
  `compare-harfbuzz` for 10,000 lines and 47,655 glyphs
  (`checksum=da5f74de3edfe093`). This gate covers mixed-length format-2
  ContextSubst rules at syllable boundaries and consecutive contextual
  ligatures whose first substitution shortens the active glyph run.
- NotoSansDuployan `duployan.txt` now passes `compare-harfrust` for all 14
  non-empty lines in the local HarfBuzz/HarfRust corpus, covering 503,948
  glyphs with glyph id, UTF-8 cluster, advance, and offset parity
  (`checksum=9e78013ddfed36e1`). Focused blockers `𛰂𛱛`, `𛰜‌𛰂`, and
  `𛰂𛱛͏͏͏𛰜‌𛰂` also pass individually.
  The fixes are structural rather than sample-specialized: USE final features
  now mirror HarfBuzz/HarfRust's `abvs/blws/haln/pres/psts` stage, common
  typographic features such as `abvm`, `blwm`, `dist`, and `rclt` run in a
  separate typographic pass, and GSUB/GPOS carry a `glyph_substituted` bit so
  untouched default-ignorables remain transparent while glyphs touched by GSUB
  stay visible to later matching and final hiding. This matches the HarfBuzz
  `_hb_glyph_info_is_default_ignorable()` contract used by HarfRust.
  Earlier focused slices also fixed extension-wrapped chaining-context lookup
  ordering and CursivePos placement/advance chaining. The remaining USE work is
  to validate other USE scripts and fonts before making a broader USE parity
  claim.
- NotoSansBalinese passes `compare-harfbuzz` for all 43 SHBALI rendering-test
  cases retained in `tests/data/balinese-rendering-tests.txt`, covering USE
  category assignment, syllable cluster ownership, split pre-base vowels,
  broken-syllable dotted circles, ligature decomposition, and GPOS output
  (`checksum=21249c939189778c`). The gate is:
  ```sh
  zig build shape-bench -Doptimize=ReleaseFast -- \
    --engine compare-harfbuzz \
    --font ~/Work/harfbuzz/test/shape/data/text-rendering-tests/fonts/NotoSansBalinese-Regular.ttf \
    --text-file tests/data/balinese-rendering-tests.txt --direction ltr
  ```
- Javanese passes `compare-harfbuzz` for all 54 upstream
  `in-house/use-javanese.tests` inputs retained in
  `tests/data/javanese-use-tests.txt`, covering pre-base vowels, pref-produced
  pre-base forms, akhand ligatures, ZWNJ/ZWSP boundaries, native digits,
  punctuation, and monotone-grapheme cluster ownership
  (`checksum=6f45576043094fa5`). The gate is:
  ```sh
  zig build shape-bench -Doptimize=ReleaseFast -- \
    --engine compare-harfbuzz \
    --font ~/Work/harfbuzz/test/shape/data/in-house/fonts/f70f345188472b93f565d1d7fae8c668dd6a3244.ttf \
    --text-file tests/data/javanese-use-tests.txt --direction ltr
  ```
- Marchen passes `compare-harfbuzz` for all 35 upstream
  `in-house/use-marchen.tests` inputs retained in
  `tests/data/marchen-use-tests.txt`, covering subjoined consonants, pre/above/
  below/post vowels, vowel modifiers, multi-component substitutions, and mark
  positioning (`checksum=1756df70fe6bf584`). The gate is:
  ```sh
  zig build shape-bench -Doptimize=ReleaseFast -- \
    --engine compare-harfbuzz \
    --font ~/Work/harfbuzz/test/shape/data/in-house/fonts/85414f2552b654585b7a8d13dcc3e8fd9f7970a3.ttf \
    --text-file tests/data/marchen-use-tests.txt --direction ltr
  ```
- Cham passes the five script-specific cases extracted from upstream
  `in-house/use-syllable.tests` across its two fixture fonts. These cover
  above/below vowels, all four medial positions, `pref` reordering, ZWNJ
  handling, and fonts without a usable invisible glyph. Retained corpora are
  `tests/data/cham-use-font1.txt` (`checksum=9aef257a83ae9578`) and
  `tests/data/cham-use-font2.txt` (`checksum=2a55c08e9d3d7e1d`).
- Batak passes both cases extracted from upstream `in-house/use-syllable.tests`
  against HarfRust and a local build of the current HarfBuzz checkout
  (`checksum=94bde9946913f776`). The fixture also covers a real-world Unicode
  cmap EncodingRecord with an unknown platform-0 encoding ID and repeated
  reordering killers that each require a dotted circle. The corpus is retained
  in `tests/data/batak-use-tests.txt`.
- Brahmi passes all four script-specific cases extracted from upstream
  `in-house/use-syllable.tests` across two fixture fonts. These cover numeral
  joiners, consonant-with-stacker bases, dependent vowels, and explicit virama
  clusters. Retained corpora are `tests/data/brahmi-use-font1.txt`
  (`checksum=b27f31c50b8dfdbc`) and `tests/data/brahmi-use-font2.txt`
  (`checksum=f386e68d32dec96b`).
- Chakma passes both joiner cases extracted from upstream
  `in-house/use-syllable.tests` (`checksum=123ca7f06e6519fd`). The retained
  `tests/data/chakma-use-tests.txt` gate distinguishes ZWJ, which stays
  transparent to USE syllable matching, from WORD JOINER, which starts a
  broken dependent-vowel cluster and therefore requires a dotted circle.
- Tai Tham passes `compare-harfbuzz` for all 209 `SHLANA-1..10` rendering-test
  cases retained in `tests/data/tai-tham-rendering-tests.txt`
  (`checksum=33ad224cfc0de28f`). This gate covers Unicode 17 USE categories,
  modified canonical-combining-class reordering (including SAKOT), dynamic
  contextual `SequenceIndex` growth after MultipleSubst, position-major
  chaining-subtable priority, `pref`-classified dotted-circle reordering, and
  ZWNJ-owned Tai Tham stacks. The gate is:
  ```sh
  zig build shape-bench -Doptimize=ReleaseFast -- \
    --engine compare-harfbuzz \
    --font ~/Work/harfbuzz/test/shape/data/text-rendering-tests/fonts/TestShapeLana.ttf \
    --text-file tests/data/tai-tham-rendering-tests.txt --direction ltr
  ```
- Newa passes all five script-specific cases retained from upstream
  `in-house/use-syllable.tests` across three fixture fonts. The slice covers
  virama+ZWNJ termination, CGJ transparency in contextual and nested ligature
  matching, dynamic `rphf` Repha classification/reordering, and Newa sandhi
  mark placement. Retained corpora and checksums are
  `tests/data/newa-use-font1.txt` (`c0ab8e641843aee8`),
  `tests/data/newa-use-font2.txt` (`394d6a8cec84554c`), and
  `tests/data/newa-use-font3.txt` (`826e22dd15be8028`).
- Saurashtra passes both script-specific cases retained from upstream
  `in-house/use-syllable.tests` across two fixture fonts. These cover the
  consonant sign HAARU followed by virama or dependent AA under the `saur`
  script, with grapheme-cluster and advance parity. Retained corpora are
  `tests/data/saurashtra-use-font1.txt` (`275e7cda1944bff1`) and
  `tests/data/saurashtra-use-font2.txt` (`3bf3ed6bddc3dbce`).
- Grantha passes both script-specific cases retained from upstream
  `in-house/use-syllable.tests` across two fixture fonts. The first covers a
  base with common U+20F0 and a combining Grantha digit under the `gran` script
  (`tests/data/grantha-use-font1.txt`, checksum `5cf76a280887fce1`).
  The second verifies that common U+00B2 is a USE `FMPst` non-cluster rather
  than a broken cluster requiring a dotted circle
  (`tests/data/grantha-use-font2.txt`, HarfRust checksum
  `5ec68188a3d8a683`).
- Sharada passes the final script-specific case retained from upstream
  `in-house/use-syllable.tests` against both HarfBuzz and HarfRust
  (`tests/data/sharada-use-tests.txt`, checksum `669777826db1047a`). The
  no-GDEF fixture verifies that Unicode `General_Category=Mn` synthesizes USE
  mark classes, zeroes both sandhi-mark advances, and shifts each mark by its
  original advance when no GPOS table can position it. The Mn data is generated
  from Unicode 17 rather than inferred from grapheme Extend, which would also
  capture spacing modifiers and default-ignorables.
- All 94 upstream `in-house/use-vowel-letter-spoofing.tests` cases pass both
  HarfBuzz and HarfRust (`tests/data/use-vowel-letter-spoofing.txt`, checksum
  `3081b548579c2cfc`). This multi-script gate covers font-dependent Indic
  ScriptList negotiation (`v3` → `v2` → legacy), USE vowel-constraint dotted
  circles, Unicode canonical split-matra decomposition, and Unicode 17
  grapheme/category data through Devanagari, Bengali, Gurmukhi, Gujarati,
  Odia, Telugu, Kannada, Malayalam, Sinhala, Brahmi, Khudawadi, Tirhuta, Modi,
  and Takri.

Conclusion: some complex Arabic/Nastaliq slices now beat HarfBuzz locally, but
ordinary Amiri Arabic long text still trails HarfBuzz substantially. The broad
goal is active, not complete.

## Near-Term Gaps

- Add a library-level HarfRust comparison runner. The `harfbuzz` `shape-bench`
  engine is now in-process, but the current `harfrust` engine remains a batch
  external-process baseline, not a fully fair in-process performance baseline.
- Expand the benchmark matrix beyond Amiri, Roboto, SourceSerifVariable,
  NotoNastaliqUrdu, and the active Devanagari gate; Gulzar now passes a retained
  1,000-line `fa-words` slice, but full broader Arabic font corpora, Urdu,
  Nastaliq, and mixed-script texts still need retained parity coverage.
- Track output parity, not only timing. `compare-harfrust` and
  `compare-harfbuzz` both compare glyph ids, clusters, advances, and offsets in
  HarfBuzz-style buffer order; focused in-process HarfBuzz feature checks are
  covered, but broader font/script matrices still need expansion.
- Expand the new Indic shaper slice beyond the current Devanagari `nukt`,
  `akhn`, `rphf`, `rkrf`, `half`, `cjct`, `pres`, `abvs`, `blws`, and `psts`
  stages; the current `hi-words.txt` gate only covers the active Devanagari
  word corpus, not full HarfBuzz Indic script parity.
- Expand USE shaping parity beyond the retained Duployan, Balinese, Javanese,
  Marchen, Cham, Batak, Brahmi, Chakma, Tai Tham, Newa, Saurashtra, Grantha,
  and Sharada gates. Other USE scripts/fonts and fuzz/corpus failures still
  need retained gates before this can be called broad USE parity.
- Continue Arabic hot-path work from measured profile evidence: GSUB `calt`
  context lookups now dominate after the GPOS lookup `37` cleanup; avoid
  retaining speculative prefilters unless they improve both Arabic and Roboto
  smoke runs reliably.
- Avoid retaining optimizations that only improve a single noisy run or regress
  Roboto/word-list smoke cases.
