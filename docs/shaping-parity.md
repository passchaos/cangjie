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
zig build shaping-parity-smoke -Doptimize=ReleaseFast -Denable-harfbuzz=true -Dharfbuzz-prefix=~/.cache/cangjie-next/harfbuzz-prefix
zig build shape-bench -Doptimize=ReleaseFast -- --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-words.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --font ~/Work/harfrust/harfrust/benches/fonts/Roboto-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/en-words.txt --direction ltr --iterations 1 --warmup 1 --samples 2
zig build shape-bench -Doptimize=ReleaseFast -- --engine coretext --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --engine harfbuzz --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file ~/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
```

HarfBuzz reference runs require `-Denable-harfbuzz=true`. If the local
`~/Work/harfbuzz` checkout is installed into an isolated prefix, pass
`-Dharfbuzz-prefix=/path/to/prefix`; otherwise the build uses
`pkg-config harfbuzz`. `shaping-parity-smoke` runs retained HarfBuzz comparison
gates for NotoSansDevanagari `hi-words`, the Duployan USE corpus, and every
fixture under `tests/data/use/`; it defaults to `~/Work` and accepts
`-Dparity-work-root=/path/to/Work` for other local reference roots.
`shaping-corpus-parity-smoke` is also available for the retained Roboto
`en-words`/`en-thelittleprince`, Amiri `fa-words`/`fa-thelittleprince`, and
SourceSerifVariable `en-words`/`en-thelittleprince` corpus gates against both
HarfBuzz and HarfRust. It also includes a Bengali HarfBuzz in-house shaping
subset that omits `hhea`/`hmtx` and `glyf`, exercising shape-only font parsing
with HarfBuzz-compatible fallback advances, plus Arabic modifier-mark ordering
fixtures with and without CGJ.
It also retains focused Indic in-house rows including Bengali contextual `pres`
at syllable boundaries.

As of the local `1ed2cf3` state, the full retained corpus command below
completes successfully with the isolated HarfBuzz prefix:

```sh
zig build shaping-corpus-parity-smoke -Doptimize=ReleaseFast -Denable-harfbuzz=true -Dharfbuzz-prefix=/Users/bytedance/.cache/cangjie-next/harfbuzz-prefix --summary none
```

This is a retained correctness-corpus result, not a completion signal for the
broader performance and cross-script coverage objectives below.

Use `--profile` for defensive-path targeting only. It records glyph windows
around every GSUB lookup and therefore intentionally uses the generic lookup
dispatcher. Use `--profile-fast-path` when investigating optimized production
paths; it keeps validated lookup accelerators active and records lightweight
per-lookup timings without glyph-window snapshots.

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

`zig build shaping-use-parity-smoke -Doptimize=ReleaseFast -Denable-harfbuzz=true`
runs the full `tests/data/use/*.txt` gate plus these two compact extra gates
against both HarfBuzz and HarfRust. The Tai Tham slice specifically covers
independent SAKOT grapheme boundaries, three adjacent USE syllables,
broken-syllable dotted circle insertion without GDEF classes, and a synthetic
base retaining its advance instead of inheriting the broken mark's fallback
class.

The complete 27-case set passes HarfRust 0.12 and matches the expected output
from the local HarfBuzz 14.3 checkout. System HarfBuzz 8.3 differs on the
already-retained Batak `U+1BC7,U+1BF3,U+1BF3` case by omitting the second
dotted circle; that older behavior is not used as the parity target.

The `harfbuzz` engine links a HarfBuzz C library in-process and is the
preferred HarfBuzz timing baseline. Enable it with `-Denable-harfbuzz=true`;
use `-Dharfbuzz-prefix` for an isolated local checkout install, or rely on
`pkg-config harfbuzz` when HarfBuzz is installed system-wide. It supports the
shared `--enable-feature` / `--disable-feature` overrides, `--glyph-summary`
output, and `compare-harfbuzz`, so focused HarfBuzz/Cangjie feature-diff
fixtures can be built without shelling out to `hb-shape`.

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

`compare-coretext` is available for local macOS glyph-id parity probes against
CoreText. It compares glyph IDs and intentionally skips positions because the
current CoreText runner does not yet capture clusters or advances. The focused
SFNS `hello` probe passes locally with matching glyph IDs.

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
  U+10EFD–U+10EFF. Hebrew nonspacing marks now share the same RTL cluster
  inheritance path; all 31 HarfBuzz `hebrew-diacritics.tests` rows for
  `b895f8ff06493cc893ec44de380690ca0074edfa.ttf` are retained as
  `tests/data/hebrew-diacritics-31.txt`. Base-plus-mark GSUB ligatures such as
  `nun+dagesh` now retain source-component provenance for Indic reorder logic
  while carrying a GPOS hint that makes Hebrew MarkLig/MarkMark attachment treat
  the ligature as one base. Focused
  HarfBuzz/HarfRust Arabic output matches at checksum `7cb1b7bd03a57f5d`. A
  fixed-CPU-30 A/B/B/A comparison with 31-sample medians
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
- Final glyph positioning now reserves the post-GSUB glyph count once and uses
  assume-capacity appends in the output loop. Positioning can remove untouched
  default-ignorables when no invisible glyph exists, but it cannot increase
  cardinality, so the post-GSUB stream is a guaranteed capacity upper bound
  while keeping the suppression path unchanged. Fixed-CPU-30 A/B/B/A plus reverse
  B/A/A/B comparisons, with four 31/41-sample medians per binary, improved
  Roboto `en-words` from a combined mean of `302.094` to
  `301.152 ns/glyph`, about `0.31%`, and Amiri `fa-thelittleprince` from
  `746.936` to `744.978 ns/glyph`, about `0.26%`. A separate 31-sample
  Amiri `fa-words` A/B/B/A check improved `1290.691` to
  `1285.697 ns/glyph`, about `0.39%`. Full HarfBuzz parity for all three
  corpora and HarfRust parity for Roboto remained unchanged.
- Default OpenType script and language inference now shares one UTF-8/Script
  scan instead of classifying the leading strong scalar once for each
  property. The combined state still follows later CJK language hints, so Han
  followed by Hiragana selects the Han script and Japanese LangSys; explicit
  language callers retain the early-exit script-only path. ASCII bytes bypass
  UTF-8 decoding, and after the first strong ASCII script they also bypass
  Unicode Script lookup. A fixed-CPU-30 41-sample A/B/B/A comparison reduced
  Roboto `en-words` from `299.186` to `287.023 ns/glyph`, about `4.07%`;
  Amiri `fa-words` improved from `1286.669` to `1278.313 ns/glyph`, about
  `0.65%`; and Amiri `fa-thelittleprince` remained effectively flat but
  slightly faster (`743.725` to `743.144 ns/glyph`). Roboto profile
  `options_ns` fell from about `1.13 ms` before this work to about `0.39 ms`.
  Full HarfBuzz parity for all three corpora and the retained multi-script USE
  fixture remained unchanged.
- A fixed-CPU-30 Cangjie/HarfBuzz/HarfBuzz/Cangjie absolute matrix at commit
  `4c3446f`, with 31-sample medians, measured Roboto `en-words` at
  `291.122` versus `228.537 ns/glyph`, leaving Cangjie about `27.4%` slower;
  Amiri `fa-thelittleprince` at `745.034` versus `796.559 ns/glyph`, making
  Cangjie about `6.5%` faster; and Amiri `fa-words` at `1283.056` versus
  `1248.622 ns/glyph`, leaving Cangjie about `2.8%` slower. These measurements
  use the in-process system HarfBuzz 8.3 runner and demonstrate that the result
  remains workload-dependent rather than a broad shaping-performance win.
- GSUB and GPOS table-proof caches now remember the most recently used font
  address before consulting their hash sets. Consecutive runs from one face
  therefore prove cache membership with one pointer comparison, while
  alternating fallback faces retain the original hash-set semantics. Combined
  fixed-CPU-30 forward/reverse comparisons improved four Roboto `en-words`
  medians from `289.942` to `289.132 ns/glyph`, about `0.28%`, and Amiri
  `fa-words` from `1288.756` to `1272.163 ns/glyph`, about `1.29%`. An
  additional reverse 101-sample Amiri `fa-thelittleprince` check improved
  `743.212` to `741.412 ns/glyph`, about `0.24%`. On a five-iteration Roboto
  `perf stat` run, retired instructions fell about `0.38%` and branches about
  `0.37%`; all three HarfBuzz corpus checksums and Roboto HarfRust parity
  remained unchanged.
- Accelerated PairPos now uses adjacent glyphs directly when the cmap pass
  proves the run has no default-ignorables and the lookup has no glyph-filter
  flags. The general skip-aware loop remains separate for default-ignorables,
  marks, and other LookupFlag behavior, so the common loop contains no source
  index or Unicode-property checks. Combined fixed-CPU-30 forward/reverse
  comparisons improved four Roboto `en-words` medians from `289.977` to
  `286.149 ns/glyph`, about `1.32%`, and Amiri `fa-words` from `1274.177`
  to `1268.538 ns/glyph`, about `0.44%`; Amiri `fa-thelittleprince` remained
  flat (`741.827` versus `741.989 ns/glyph`, about `0.02%`). Post-change
  Roboto sampling no longer reports `gpos.nextUnignoredGlyph`, previously
  about `1.75%`. Full HarfBuzz parity for all three corpora and Roboto
  HarfRust parity remained unchanged.
- Horizontal glyph metrics now use a 512-slot exact direct-mapped front cache
  before the existing hash map. Slots retain the complete font address, glyph
  id, and variation hash, so collisions and fallback/variation changes safely
  fall through to the authoritative map and refill the slot. The vertical
  cache remains unchanged, avoiding per-context storage for an inactive path.
  Fixed-P-core interleaved `perf stat` comparisons reduced Roboto `en-words`
  retired instructions by about `3.33%` and cycles by `5.00%`; Amiri
  `fa-words` improved `0.85%` and `0.39%`, and Amiri
  `fa-thelittleprince` improved `1.35%` and `1.16%`, respectively. Generic
  `Wyhash.final`, previously about `3.46%` in Roboto sampling, disappeared
  from the post-change profile. Full HarfBuzz parity for all three corpora and
  Roboto HarfRust parity remained unchanged.
- Default property inference now also reports whether it consumed an all-ASCII
  run. The LTR cmap pass reuses that existing whole-run proof and maps one byte
  per source directly, avoiding a second UTF-8 decode plus variation-selector,
  default-ignorable, bidi-mirroring, and inherited-cluster checks. The proof is
  kept outside the frequently copied OpenType lookup options; non-ASCII and
  forced-RTL text retain the original scalar loop. Fixed-P-core interleaved
  `perf stat` comparisons reduced Roboto `en-words` retired instructions by
  about `2.57%` and cycles by `1.96%`. Amiri `fa-words` remained flat to
  slightly faster (`-0.04%` instructions, `-0.31%` cycles), while Amiri
  `fa-thelittleprince` improved `0.14%` and `0.54%`. Post-change Roboto
  sampling no longer attributes any `utf8Decode` cycles to the cmap pass.
  Full HarfBuzz parity for all three corpora and Roboto HarfRust parity
  remained unchanged.
- LTR all-ASCII runs now omit GSUB's optional source-codepoint slice. Such a
  run cannot contain CGJ, joiners, or other default-ignorables, so ligature and
  contextual matching need no Unicode source lookup; the existing metadata
  validator consequently returns after its required parallel-array cardinality
  checks instead of rescanning the identity source map. Fixed-P-core
  interleaved `perf stat` comparisons reduced Roboto `en-words` retired
  instructions by about `1.71%` and cycles by `1.33%`. Amiri `fa-words`
  remained flat to slightly faster, while Amiri `fa-thelittleprince` improved
  about `0.06%` in instructions and `0.71%` in cycles. Full HarfBuzz parity
  for all three corpora and Roboto HarfRust parity remained unchanged.
- LigatureSubst accelerators with at least eight first-glyph sets now retain a
  read-only open-addressed set index at no more than 50% load. Exact glyph
  verification resolves probes, small lookups keep binary search, and the
  immutable index remains safe to share across shaping threads. Fixed-P-core
  interleaved `perf stat` comparisons reduced Roboto `en-words` retired
  instructions by about `2.02%` and cycles by `1.54%`; Amiri `fa-words`
  improved `0.73%` and `0.39%`, and Amiri `fa-thelittleprince` improved
  `0.98%` and `0.56%`, respectively. Full HarfBuzz parity for all three
  corpora and Roboto HarfRust parity remained unchanged.
- LigatureSubst accelerators now also retain an approximate digest of every
  first-component glyph. Tables with at least two accelerated ligature lookups
  share one mutation-aware run digest, so lookups whose first-component sets
  cannot intersect the run return before scanning it; one-ligature-lookup
  tables keep the exact scan alone because building a summary would duplicate
  that work. Exact set lookup remains authoritative after digest false
  positives, and every substitution invalidates the shared digest before a
  later lookup can reject a newly introduced glyph. On fixed E-core CPU 30,
  serial 31-sample A/B/B/A medians reduced Roboto `en-words` from `252.770`
  to `229.138 ns/glyph`, about `9.35%`. Serial 21-sample B/A/A/B medians
  reduced Amiri `fa-words` from `1278.704` to `1251.860 ns/glyph`, about
  `2.10%`, and `fa-thelittleprince` from `733.361` to `713.282 ns/glyph`,
  about `2.74%`. Five-iteration A/B/B/A `perf stat` means corroborated the
  timing: Roboto instructions/cycles fell `7.94%`/`9.49%`; Amiri words fell
  `1.52%`/`2.27%`; and Amiri long text fell `2.26%`/`2.66%`. Branches and
  branch misses also decreased on all three corpora. Full HarfBuzz parity for
  all three corpora and Roboto HarfRust parity remained unchanged.
- A post-change fixed-CPU-30 Cangjie/HarfBuzz/HarfBuzz/Cangjie absolute matrix,
  with 31-sample medians, measured Roboto `en-words` at `229.705` versus
  `228.308 ns/glyph`, leaving Cangjie about `0.61%` slower; Amiri
  `fa-words` at `1252.537` versus `1245.834 ns/glyph`, leaving Cangjie about
  `0.54%` slower; and Amiri `fa-thelittleprince` at `711.887` versus
  `796.167 ns/glyph`, making Cangjie about `10.59%` faster. Ordinary Latin
  and the Arabic word list are therefore near parity on these fonts, not yet
  broad wins; the cross-font and cross-script performance objective remains
  active.
- Single-font shaping now reuses default property inference's complete
  all-ASCII proof when deciding whether an LTR run needs post-shape bidi
  reordering. Previously the same word was decoded a second time after
  shaping solely to prove that no ASCII scalar has a strong RTL bidi class;
  explicit RTL and every non-ASCII or explicitly languaged run retain the
  original scan. On fixed P-core CPU 8, a five-iteration A/B/B/A `perf stat`
  comparison reduced Roboto `en-words` retired instructions by `1.49%`,
  branches by `1.82%`, and cycles by `2.05%`; 31-sample timing medians
  improved about `2.37%`. The same E-core CPU 30 check reduced instructions
  by about `1.50%`, while Amiri word-list and long-text instructions remained
  effectively flat because their forced RTL path returns before the new ASCII
  test. A longer fixed-P-core Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix measured
  Cangjie at `201.445 ns/glyph` versus HarfBuzz at `215.896 ns/glyph`, a
  Cangjie lead of about `6.69%`; the noisier E-core matrix also favored Cangjie
  (`223.548` versus `228.445 ns/glyph`, about `2.14%`). Full HarfBuzz parity
  for Roboto and both Amiri corpora, Roboto HarfRust parity, and all ten
  retained USE fixtures against both references remained unchanged. These are
  still one font/corpus and one host, not a broad Latin-performance claim.
- Final positioning now allocates, clears, remaps, and propagates attachment
  scratch only when the collected GPOS adjustments actually contain a mark or
  cursive attachment. PairPos/SinglePos-only runs previously paid two
  glyph-count-sized clears and a full remapping/propagation pass even though
  every link was empty; fonts and Arabic lines that emit real attachments keep
  the original path. Fixed-P-core CPU 8 A/B/B/A `perf stat` comparisons reduced
  Roboto `en-words` retired instructions by `4.21%`, branches by `3.21%`, and
  cycles by `4.53%`; Amiri `fa-words` instructions/cycles improved
  `1.05%`/`1.51%`, and `fa-thelittleprince` improved `0.62%`/`0.56%`.
  Fixed-E-core CPU 30 reproduced the Roboto reduction at `4.20%`
  instructions and `4.79%` cycles. A post-change 31-sample, three-iteration
  Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix measured Roboto at `193.855`
  versus `215.091 ns/glyph` on CPU 8, a Cangjie lead of about `9.87%`, and
  `210.454` versus `229.616 ns/glyph` on CPU 30, about `8.35%`. Full
  HarfBuzz parity for Roboto and both Amiri corpora, Roboto HarfRust parity,
  and all ten retained USE fixtures against both references remained
  unchanged.
- Homogeneous ExtensionPos(PairPos) lookups now build and consume the same
  predecoded sparse/class-pair accelerators as direct PairPos. The wrapper
  still preserves authored subtable alternatives and falls back per generic
  subtable, while xAdvance records with trailing Device/VariationIndex offset
  fields use their complete ValueRecord stride; those offsets remain validated
  and intentionally ignored exactly as in the generic value reader. This
  removes repeated wrapper, coverage, ClassDef, and matrix parsing for
  SourceSerifVariable's five-subtable `kern` lookup. Fixed-P-core CPU 8
  A/B/B/A `perf stat` comparisons reduced SourceSerifVariable `en-words`
  retired instructions by `47.66%`, branches by `45.26%`, and cycles by
  `60.71%`, improving timing from `453.456` to `173.778 ns/glyph`. Fixed
  E-core CPU 30 reproduced `47.65%` fewer instructions and `56.54%` fewer
  cycles. Roboto and Amiri instructions remained flat. Full HarfBuzz parity
  remained unchanged for SourceSerifVariable `en-words`,
  `en-thelittleprince`, and `react-dom`, Roboto and both Amiri corpora;
  SourceSerifVariable/Roboto HarfRust parity and all ten retained USE fixtures
  against both references also remained unchanged. The optimized
  SourceSerifVariable word list is now within roughly `8%` of HarfBuzz on the
  less noisy fixed-CPU comparisons, down from about `2.8x` slower.
- Accelerated PairPos now dispatches each first glyph through the existing
  exact coverage-group index and probes only the authored subtables whose
  coverage can contain it. The grouped indexes preserve original subtable
  order, so explicit-zero PairPos matches still stop later fallbacks; generic
  subtables retain their parser fallback. Fixed-P-core CPU 8 A/B/B/A
  comparisons reduced SourceSerifVariable `en-words` retired instructions by
  `5.93%` and branches by `7.02%`; fixed E-core CPU 30 reproduced `5.92%`
  fewer instructions and `7.01%` fewer branches. Roboto instructions also
  improved `2.64%`, while Amiri remained flat. A post-change
  Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix measured SourceSerifVariable at
  `168.062` versus `161.225 ns/glyph` on CPU 8, leaving about a `4.24%`
  gap, and `178.412` versus `170.635 ns/glyph` on CPU 30, about `4.56%`.
- Validated GPOS accelerators now retain a homogeneous ExtensionPos lookup's
  wrapped type. Runtime dispatch reuses it only when lookup offset, outer type,
  and subtable count all match; unvalidated calls and stale/foreign cache
  entries still parse the wrappers. This removes five wrapper-header reads per
  SourceSerifVariable word. Fixed-P-core CPU 8 A/B/B/A comparisons reduced
  `en-words` retired instructions by `3.16%`, branches by `3.48%`, and cycles
  by `4.79%`; fixed E-core CPU 30 reproduced `3.15%` fewer instructions and
  `6.25%` fewer cycles. Roboto and Amiri instructions remained effectively
  flat. A post-change Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix measured
  SourceSerifVariable at `158.791` versus `161.268 ns/glyph` on CPU 8, a
  Cangjie lead of about `1.54%`, and `168.077` versus `171.115 ns/glyph` on
  CPU 30, about `1.78%`. Full SourceSerifVariable, Roboto, and Amiri HarfBuzz
  parity plus SourceSerifVariable HarfRust parity remained unchanged.
- GSUB accelerators now retain the validated FeatureList as immutable
  `(tag, lookup-slice)` records. Explicit script-shaper stages can borrow a
  canonical unique record directly instead of rereading FeatureList and
  allocating/sorting lookup indexes for every word; duplicate feature tags,
  non-canonical lookup order, unvalidated calls, detached LookupList-only
  fixtures, and foreign table identities retain the original owned fallback.
  Fixed-P-core CPU 8 A/B/B/A comparisons reduced NotoSansDevanagari
  `hi-words` retired instructions by `10.15%`, branches by `7.59%`, and
  cycles by `12.08%`; fixed E-core CPU 30 reproduced `10.16%` fewer
  instructions and `11.19%` fewer cycles. Roboto and Amiri instructions
  remained flat. The complete 10,000-line Devanagari corpus retained
  HarfBuzz/HarfRust parity checksum `da5f74de3edfe093`, and all ten retained
  USE fixtures continued to pass both references. Devanagari remains roughly
  `2.6x` slower than HarfBuzz after this change, so contextual coverage/class
  acceleration is still a major open performance task.
- ContextSubst format 3 lookups now predecode coverage offsets and nested
  record positions, group first-input coverage by exact glyph, and try only
  candidate subtables in font order. Later input coverages remain exact checks,
  while the existing nested-record mapper still owns IgnoreMarks/default-
  ignorable skipping and cardinality-changing substitutions. Generic direct
  ContextSubst was also made position-major, matching ExtensionSubst/class
  accelerator ordering instead of independently running each whole-run
  subtable. A regression fixture covers overlapping subtable priority, an
  ignored intervening mark, MultipleSubst expansion, and a later match in the
  mutated run. Fixed-P-core CPU 8 A/B/B/A comparisons reduced
  NotoSansDevanagari `hi-words` retired instructions by `34.10%`, branches by
  `33.05%`, and cycles by `34.36%`, improving timing from `2255.574` to
  `1473.931 ns/glyph`. Roboto and Amiri instructions remained flat. The full
  Devanagari corpus and all ten retained USE fixtures continued to pass both
  HarfBuzz and HarfRust; Devanagari still trails HarfBuzz materially, so the
  complex-script performance objective remains open.
- The existing conservative ChainContextSubst format-2 class accelerator now
  also builds for direct lookup type 6, not only ExtensionSubst wrappers.
  Direct and wrapped builders share the same matcher and accept only its proven
  subset: bounded backtrack/input/lookahead regions and one nested record at
  sequence index zero; other rules retain the generic parser. Backtrack
  classes stay in OpenType's nearest-first order and reuse the existing
  IgnoreMarks/default-ignorable and source-syllable-aware match window. The
  enlarged matcher is kept out of line so it does not inflate the lookup scan
  used by fonts without these rules. Regressions cover direct/extension
  builder parity, backtrack direction, ignored marks, lookahead, syllable
  boundaries, nested SingleSubst, and conservative fallback. Against commit
  `c281812`, fixed CPU-8 P-core A/B/B/A means reduced NotoSansDevanagari
  `hi-words` retired instructions by `2.75%`, branches by `3.08%`, cycles by
  `5.38%`, and L1I misses by `2.09%`; fixed CPU-30 E-core reproduced
  `2.76%`, `3.09%`, `4.35%`, and `9.82%` reductions. Roboto, Amiri, and the
  503,948-glyph Duployan USE corpus remained effectively flat in retired
  instructions and branches. The complete Devanagari corpus retained
  HarfBuzz/HarfRust checksum `da5f74de3edfe093`; all ten retained USE
  fixtures, Roboto, SourceSerifVariable, and both Amiri corpora also retained
  dual-reference parity.
- ChainContextSubst format-2 accelerators now append an exact
  `(first glyph, RuleGroup)` index to their existing class sidecar. The hot
  matcher therefore replaces Coverage parsing, input ClassDef lookup, and
  class-group binary search with one exact probe; small indexes stay sorted,
  while indexes with at least eight glyphs use a 50%-load open-addressed table.
  Appending to the existing allocation and reusing the former Coverage-offset
  word keeps the accelerator struct and allocation count unchanged. Legal
  overlapping Coverage format-2 ranges are sorted and deduplicated, and
  covered classes without rules remain exact misses. Against `b096ec4`, fixed
  CPU-8 P-core A/B/B/A means reduced NotoSansDevanagari `hi-words`
  instructions by `4.42%`, branches by `4.18%`, and cycles by `7.48%`; fixed
  CPU-30 E-core reproduced `4.39%`, `4.15%`, and `5.23%` reductions.
  Roboto, Amiri, and the 503,948-glyph Duployan corpus remained flat in
  retired work, and a reverse-order long Amiri run kept cycles within `0.1%`.
  The complete Devanagari corpus, all ten retained USE fixtures, Roboto,
  SourceSerifVariable, and both Amiri corpora retained HarfBuzz/HarfRust
  parity.
- ContextSubst format-2 accelerators now reuse the same exact first-glyph
  sidecar and lookup helper as chaining class subtables. Their former Coverage
  offset is likewise replaced in place, so the optimization adds neither an
  accelerator field nor an allocation. A direct/ExtensionSubst builder fixture
  proves identical rules, class sidecars, groups, and first-glyph indexes.
  Against `651173b`, fixed CPU-8 P-core A/B/B/A means reduced
  NotoSansDevanagari `hi-words` instructions by `1.18%`, branches by `1.06%`,
  and cycles by `1.39%`; fixed CPU-30 E-core reproduced `1.17%`, `1.06%`,
  and `1.26%` reductions. Roboto and Amiri retired work remained flat, and the
  full Devanagari/USE/Latin/variable/Arabic dual-reference parity matrix was
  unchanged.
- Explicit GSUB feature sequences now collect the selected LangSys feature
  indexes in a 64-entry stack buffer. Required/optional duplicates still
  collapse with the required bit preserved; larger LangSys tables keep the
  allocator-backed path without truncation. This removes one grow/free cycle
  from every Indic feature stage while retaining the original ScriptList,
  language fallback, required-feature, and FeatureList parsing semantics.
  Against `aa45bda`, fixed CPU-8 P-core A/B/B/A means reduced
  NotoSansDevanagari `hi-words` instructions by about `6.51%`, branches by
  `5.15%`, and cycles by about `6.0%`; fixed CPU-30 E-core reproduced about
  `6.50%`, `5.14%`, and `3.6%` reductions. Roboto and Amiri retired work
  remained flat, and the retained Devanagari/USE/Latin/variable/Arabic
  HarfBuzz/HarfRust parity matrix was unchanged.
- ContextSubst format-1 now reuses the format-2 contextual rule accelerator.
  Coverage format-1 glyphs map directly to RuleGroups, while extra inputs are
  compared as exact glyph ids through the existing sidecar matcher. Arbitrary
  SubstLookupRecord counts and sequence indexes still use the original mapped
  record applier, preserving IgnoreMarks, source-syllable boundaries, cardinality
  changes, and font-authored rule order. Coverage format-2 remains on the generic
  path because legal overlapping ranges select RuleSets by first matching range,
  not merely by glyph id. Against `729ee20`, fixed CPU-8 P-core A/B/B/A means
  reduced NotoSansDevanagari `hi-words` instructions by `4.26%`, branches by
  `4.08%`, and cycles by about `5.8%`; fixed CPU-30 E-core reproduced `4.27%`,
  `4.11%`, and about `6.1%` reductions. Roboto and Amiri retired work remained
  flat, and all retained dual-reference parity gates were unchanged.
- Predecoded GPOS PairPos format-2 xAdvance subtables now use bounded direct
  class maps when the combined ClassDef1-coverage and ClassDef2 glyph spans
  fit within 8,192 entries. The existing PairPos sidecar storage and otherwise
  idle format-1 fields retain both dense-map bases, so the hot adjacent-pair
  path replaces two binary searches with range checks and indexed loads
  without widening `LookupAccelerator`. Covered class zero remains distinct
  from a coverage hole through an impossible-class sentinel, while glyphs
  outside the explicit ClassDef2 span retain OpenType's implicit class zero.
  Larger or sparse tables keep the prior sorted-entry fallback. Fixed CPU-8
  P-core and CPU-30 E-core 10-iteration A/B/B/A plus reverse B/A/A/B
  comparisons reduced Roboto `en-words` retired instructions by about `3.36%`
  and branches by `5.93%`; cycles improved by roughly `2.5–3.4%` on the
  stable P-core runs and `5.2–5.7%` on E-core. SourceSerifVariable
  `en-words` reduced instructions by about `6.86%`, branches by `10.72%`,
  and cycles by about `14.6–16.5%`. NotoSansDevanagari retired work remained
  flat while cycles improved by about `0.37–0.73%`; Amiri and Tai Tham
  retired work remained effectively flat, with no stable cycles regression.
  Full Devanagari, Roboto, SourceSerifVariable, and Amiri corpora retained
  HarfBuzz/HarfRust parity, as did the retained USE differential matrix.
- All explicit script-shaper stages now reuse cached `FeatureLookupPlan`
  records after the GSUB table has been proven, extending the existing Arabic
  path to Indic and USE. The immutable plan preserves required-feature and
  authored lookup order plus source-feature, joiner, and source-syllable flags,
  while removing repeated ScriptList/LangSys/FeatureList walks from every stage
  of every word. The plan cache's exact application comparison now also
  includes `match_source_syllable`, preventing otherwise-identical global and
  syllable-scoped stages from aliasing. Fixed CPU-8 B/A/A/B timing reduced
  NotoSansDevanagari `hi-words` from `1125.249` to `1005.963 ns/glyph`,
  about `10.60%`; fixed CPU-30 B/A/A/B reduced `1339.402` to
  `1194.031 ns/glyph`, about `10.85%`. Interleaved hardware-counter runs on
  both cores reduced retired instructions by about `13.76%` and branches by
  about `21.4%`; cycles fell by about `13.22%` on CPU 8 and `10.49%` on
  CPU 30. The post-change Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix leaves
  Cangjie about `28.74%` slower on the stable CPU-8 run; the CPU-30 reverse
  matrix observed about a `34%` gap, with its first HarfBuzz sample showing
  transient frequency noise. Full Devanagari and the ten retained USE corpora,
  the Indic3/Tai Tham compact gates, the 94-case vowel-letter-spoofing corpus,
  Roboto, SourceSerifVariable, and Amiri retained dual-reference parity.
  Fixed-core Roboto, SourceSerifVariable, and Amiri word-list timings stayed
  within about `0.61%` of their baselines and mostly improved slightly.
- Consecutive Indic/USE stages now validate their maximal glyph/source metadata
  contract once, then use a narrowly scoped internal after-run-proof entry.
  The first stage retains complete glyph-id and source-parallel validation;
  subsequent validated GSUB lookups can only emit maxp-bounded glyphs, and the
  centralized mutation helpers atomically preserve source, cluster,
  substitution, and ligature-provenance cardinalities and bounds. Public and
  independently supplied runs retain the defensive validation path. Relative
  to `b4df999`, fixed CPU-8 A/B/B/A timing reduced NotoSansDevanagari
  `hi-words` from `1009.933` to `995.457 ns/glyph`, about `1.43%`.
  Fixed CPU-30 timing was effectively flat (`1193.270` versus
  `1194.834 ns/glyph`, `+0.13%`, within run noise), while interleaved hardware
  counters on both cores reduced retired instructions by about `1.42%` and
  branches by about `2.27%`; CPU-8 cycles fell about `1.55%`. The 503,948-glyph
  Duployan gate kept retired instructions and branches flat, and Devanagari,
  all ten USE corpora, Indic3, Tai Tham, vowel-letter spoofing, Roboto,
  SourceSerifVariable, and Amiri retained dual-reference parity.
- `GlyphIndexCache` now puts a 512-slot exact direct-mapped front cache ahead
  of its authoritative hash map for all codepoints, while retaining the
  existing dedicated ASCII array. Each compact 16-byte slot stores the full
  font address and Unicode scalar, so collisions and fallback-font changes
  fall through safely; the additional footprint is 8 KiB per cache. This
  removes repeated Wyhash from non-ASCII cmap lookup, which accounted for
  about `1.29%` of the post-`0780173` Devanagari profile. Fixed CPU-8
  A/B/B/A timing reduced NotoSansDevanagari `hi-words` from `998.090` to
  `983.263 ns/glyph`, about `1.49%`; fixed CPU-30 B/A/A/B reduced
  `1194.126` to `1165.804 ns/glyph`, about `2.37%`. Interleaved hardware
  counters reduced retired instructions by `1.15%`/`1.19%` and cycles by
  `1.10%`/`1.74%` on CPU 8/30. Roboto's ASCII retired instructions stayed
  within `0.07%`, while Amiri `fa-words` instructions and cycles improved by
  about `0.85%` and `1%`. Devanagari, Roboto, SourceSerifVariable, Amiri, and
  all ten retained USE corpora kept dual-reference parity.
- Coarse bidi classification now recognizes the authoritative U+0900..U+097F
  Devanagari Script block as LTR before entering the complete all-script
  classifier. This primarily accelerates the post-shape “does this LTR run
  contain any strong RTL scalar?” scan; Arabic and Hebrew are resolved first,
  and the existing full-Unicode scalar-space differential test proves every
  fast result matches the reference number-or-script classification. Fixed
  CPU-8 A/B/B/A timing reduced NotoSansDevanagari `hi-words` from `975.876`
  to `956.646 ns/glyph`, about `1.97%`; CPU-30 B/A/A/B reduced `1166.333`
  to `1146.629 ns/glyph`, about `1.69%`. Interleaved counters on both cores
  reduced retired instructions by about `4.04%`, branches by `3.8%`, and
  cycles by `1.46%`/`2.01%`. Roboto and Amiri retired work stayed within
  `0.01%`, and the main Latin/variable/Arabic/Devanagari plus ten USE corpora
  retained dual-reference parity. A post-change fixed CPU-8
  Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix measured `957.022` versus
  `784.909 ns/glyph`, leaving Cangjie about `21.93%` slower—still the largest
  active shaping-performance gap, but down from the prior `28.74%`.
- Validated, non-profiled GSUB now also dispatches accelerated direct
  ContextSubst lookups through the small fast wrapper instead of entering the
  generic profiling-capable dispatcher before reaching the same predecoded
  context accelerators. This extends the existing ligature and chaining fast
  wrapper to lookup type 5 without changing unsupported, profiled,
  unvalidated, or stale-cache behavior. A serial B/A/A/B timing check against
  `8b0038c` on NotoSansDevanagari `hi-words` measured baseline medians of
  `825.716` and `789.428 ns/glyph`, versus candidate medians of `734.119`
  and `737.643 ns/glyph`. Roboto `en-words` and Devanagari `hi-words`
  retained in-process HarfBuzz parity.
- The lookup-selection cache now retains merged GSUB feature plans as well as
  one-stage feature plans. USE final and typographic stages merge several
  features for every shaped word; caching their resolved lookup slices avoids
  rebuilding the same merged plan for NotoSansDevanagari `hi-words` thousands
  of times. A serial B/A/A/B timing check against `5042673` measured baseline
  medians of `825.660` and `764.896 ns/glyph`, versus candidate medians of
  `757.872` and `735.510 ns/glyph`. Devanagari `hi-words` retained
  in-process HarfBuzz parity.
- Top-level MarkBasePos collection now caches the most recent non-transparent
  base candidate while walking a subtable, following HarfBuzz's `last_base`
  strategy without changing nested contextual single-target lookup semantics.
  The shared skip predicate preserves attached-mark, lookup-flag, GDEF mark,
  and multiple-substitution continuation transparency. A serial B/A/A/B timing
  check against `7fdb518` on NotoSansDevanagari `hi-words` measured baseline
  medians of `754.726` and `753.918 ns/glyph`, versus candidate medians of
  `743.858` and `748.150 ns/glyph`; a 21-sample B/A check measured `760.489`
  versus `749.470 ns/glyph`. The complete Devanagari corpus retained
  in-process HarfBuzz parity checksum `da5f74de3edfe093`.
- The default 4x4 grayscale raster path now expands its four horizontal
  boundary-sample comparisons instead of iterating a runtime slice for every
  partial pixel. The comparisons retain the original order and half-open
  boundary rules; 1x1, 2x2, and arbitrary sample counts keep the generic
  fallback. Fixed-P-core `raster-reuse` measurements across Roboto `A`, `g`,
  `é` and Amiri `س`, `م` reduced cycles by roughly `6.3–20.8%` and
  instructions by `4.5–9.0%`, with byte-identical target checksums for every
  glyph and for 1/2/3/4 samples per axis. A serial 64 px Roboto
  Cangjie/FreeType matrix after the change still leaves FreeType ahead:
  Cangjie/FreeType median ratios were about `1.82x` for `A`, `2.09x` for
  `g`, and `1.65x` for `é` (geometric mean `1.84x`), so the broader raster
  objective remains open.
- Internal scan conversion now routes already-finite edge intersections through
  a dedicated covered-span path. Off-target endpoints are clamped before
  integer conversion, while overlapping endpoints use direct floor/ceil
  conversion instead of repeating finite checks and four generic saturating
  conversions per span; the defensive wrapper remains for external/unchecked
  inputs. Fixed-P-core `raster-reuse` probes reduced cycles by about `6.7%`
  for Roboto `A`, `4.6%` for `g`, `4.3%` for `é`, `2.9%` for Amiri `س`,
  and `4.8%` for `م`. All five target checksums remained byte-identical, and
  boundary/huge-finite differential tests cover the fast and defensive paths.
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
- HarfBuzz in-house `simple.tests` OT baseline row for
  `49c9f7485c1392fa09a1b801bc2ffea79275f22e.ttf` is retained for
  `VABEabcd`, covering nominal glyph ids and advances without fallback shaping.
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
- NotoNastaliqUrdu `fa-words.txt` passes `compare-harfrust` for 10,000 lines
  (`checksum=fc28919889b8942b`),
  and `fa-thelittleprince.txt` passes for 771 lines; focused blockers `"سلام"`,
  `"به"`, `"ویکی‌پدیا"`, `"هجری"`, `"جزء"`, `"اللَّهِ"`, and `"اللَّهُ"` pass
  individually. The `"ویکی‌پدیا"` and leading-ZWNJ `"‌بودن"` rows are retained
  as inline HarfRust gates;
  RTL ZWNJ cluster inheritance now only applies when the joiner glyph is
  suppressed, so visible/invisible joiner glyphs keep the following Nastaliq
  ligature components anchored to their own post-ZWNJ source cluster.
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
  ordering and CursivePos placement/advance chaining. Tai Tham
  `context-matching.tests` coverage for
  `4cce528e99f600ed9c25a2b69e32eb94a03b4ae8.ttf` now retains the
  `U+1A48,U+1A58,U+1A25,U+1A48,U+1A58,U+1A25,U+1A6E,U+1A63` row after USE
  zeroing learned to honor explicit GDEF mark classes on spacing marks. The
  same upstream file now retains the regional-indicator context row for
  `5bbf3712e6f79775c66a4407837a90e591efbef2.ttf` and the dotted punctuation
  ligature row for `bef923f4ccb474f961c43b63a9c74b7d9b7a023f.ttf`, covering
  compact non-Brahmic contextual matching in the retained inline gate set. The
  remaining USE work is
  to validate other USE scripts and fonts before making a broader USE parity
  claim.
- HarfBuzz in-house `default-ignorables.tests` rows that `shape-bench` can
  express now pass focused `compare-harfbuzz`. This includes CGJ cases where
  CGJ stays transparent for ordinary contextual matching, but must not be skipped
  by a ligature lookup when it actually blocked canonical mark reordering; it
  also includes Arabic joining across CGJ so `صِ͏ّا` shapes to initial/final
  forms while preserving separate mark glyphs. The ZWJ rows for
  `fcea341ba6489536390384d8403ce5287ba71a4a.ttf`,
  `6677074106f94a2644da6aaaacd5bbd48cbdc7de.ttf`, and
  `08b4b136f418add748dc641eb4a83033476f1170.ttf` (`U+0647,U+200D`) are now
  retained as well; ZWJ inherits the previous glyph's cluster before native
  direction reversal, so HarfBuzz-style reverse-grapheme shaping keeps the base
  and joiner in input order for `rlig`. The Latin mark row for
  `051d92f8bc6ff724511b296c27623f824de256e9.ttf`
  (`U+0075,U+0361,U+034F,U+0301,U+0069`) is retained too, covering a CGJ that
  remains transparent to ordinary mark matching without collapsing the mark
  sequence incorrectly. The Arabic mark row for
  `bf962d3202883a820aed019d9b5c1838c2ff69c6.ttf`
  (`U+0020,U+06CC,U+064E,U+034F,U+0651`) is now retained after native-direction
  reversal learned to group by HarfBuzz-style grapheme continuation bits rather
  than only by cluster owner. The related
  `cee442574141a0304e780b27dd872519f7d229db.ttf`
  (`U+0635,U+0650,U+034F,U+0651,U+0627`) CGJ row is retained too; Arabic
  positional feature masks are now assigned in the post-native-direction glyph
  order so bases separated by marks/CGJ keep HarfBuzz's nominal forms when they
  do not join in the native shaping buffer. All six `arabic-mark-order.tests`
  rows are now retained as well; Cangjie mirrors HarfBuzz's Arabic modifier
  combining mark reordering by moving only same-CCC MCM groups instead of
  hoisting every MCM to the start of the mark run.
- The focused HarfBuzz in-house `variation-selectors.tests` row for
  `bbc24004e776f348a0f72287d24b0124867ee750.ttf`
  (`U+0066,U+FE00,U+0069`) passes in both upstream modes: by default unsupported
  variation selectors remain in the GSUB stream as fallback default-ignorables,
  block and/or participate in ligature matching like HarfBuzz, then render as
  zero-advance fallback space; with
  `--not-found-variation-selector-glyph=1000000`, the selector remains visible
  to matching and is reported as that zero-advance synthetic glyph. The latter
  row is retained in `shaping-corpus-parity-smoke`.
- The two HarfBuzz in-house `emoji.tests` tag-sequence rows for
  `53374c7ca3657be37efde7ed02ae34229a56ae1f.ttf` are retained as
  `tests/data/emoji-tag-sequence-tests.txt`, covering both an unsupported tag
  sequence that preserves default-ignorable tag glyphs and the supported `de`
  tag ligature path.
- All 3,825 HarfBuzz in-house `emoji-clusters.tests` rows for `AdobeBlank2.ttf`
  are retained as `tests/data/emoji-clusters-adobeblank2.txt`. Cangjie now
  accepts Windows full-repertoire cmap format 13 subtables, so this
  last-resort-style font can map emoji variation-selector and ZWJ sequences to
  its shared fallback glyph like HarfBuzz/HarfRust.
- The simple joining rows from HarfBuzz in-house `arabic-phags-pa.tests` are
  retained for `ec404b8524cd56efa5d25524cc8541a0b6604b4f.ttf` as
  `tests/data/arabic-phags-pa-tests.txt`; Cangjie now classifies Phags-Pa as
  `phag` and routes it through the USE path while reusing Arabic joining masks
  for topographical forms. The leading ZWJ rows from the same fixture are
  retained too; ZWJ still triggers joining but no longer pulls the following
  Phags-Pa base back to the leading joiner's output cluster. The
  `U+A86A,U+A85E` mirror row plus both FE00 variation-selector mirror/unmirror
  rows are retained after Phags-Pa applies its direction and positional forms
  in the same stage ordering as HarfBuzz/HarfRust.
- HarfBuzz in-house `collections.tests` TTC rows are retained for
  `TTC.ttc` face indices 0 and 1. `shape-bench` now accepts `--face-index`
  and forwards it to Cangjie, HarfRust, and HarfBuzz reference engines; DFONT
  remains outside the current SFNT/TTC/WOFF container support.
- HarfBuzz in-house `harfbust.tests` rows for `HarfBust.ttf` are retained in
  `tests/data/harfbust-tests.txt`. Cangjie accepts the font even though name ID
  6 contains an invalid space, while explicit `postscript_name` reads and font
  database matching still reject that value. The GSUB path now also mirrors the
  HarfRust/HarfBuzz behavior for this stress font: malformed Script/LangSys
  selection falls back to the reachable lookup pass, and malformed individual
  ligature set/ligature offsets are skipped while valid ligature records in the
  same lookup still apply.
- All three HarfBuzz in-house `positioning-features.tests` rows are retained as
  inline HarfRust gates. This includes a real GPOS table whose FeatureList
  records are not sorted by tag (`kern` before `abvm`), plus both mark
  positioning rows (`U+006D,U+0315` and `U+0079,U+0325`); Cangjie validates
  feature and lookup references without rejecting that noncanonical but
  HarfBuzz-tolerated ordering.
- The first five HarfBuzz in-house `mark-filtering-sets.tests` rows for
  `f22416c692720a7d46fadf4af99f4c9e094f00b9.ttf` are retained, covering Arabic
  mark attachment through lookup-level mark filtering sets and cached lookup
  flag metadata.
- All four HarfBuzz in-house `nested-mark-filtering-sets.tests` rows for
  `NotoNastaliqUrdu-Regular.ttf` are retained too, covering nested contextual
  Nastaliq mark filtering and attachment propagation across increasingly long
  Beh chains.
- HarfBuzz in-house `fallback-positioning.tests` rows that `shape-bench` can
  express now pass for `8228d035fcd65d62ec9728fb34f42c63be93a5d3.ttf`
  (`U+0078,U+0301,U+0058,U+0301`) and
  `856ff9562451293cbeff6f396d4e3877c4f0a436.ttf`
  (`U+0061,U+035C,U+0062`). Cangjie synthesizes HarfBuzz-compatible fallback
  mark offsets from glyph extents when GPOS is absent, while leaving real
  GPOS mark/cursive attachment paths in control when present. The Arabic
  fallback-shaping row for `df768b9c257e0c9c35786c47cae15c46571d56be.ttf`
  is retained too; Arabic/Syriac modified combining classes now fold to
  HarfBuzz-compatible above/below fallback mark categories, and reverse-order
  fallback bases no longer add an extra base advance to mark x offsets. The
  comparable `arabic-fallback-shaping.tests` rows for `SimpArabicTest.ttf` and
  `TradArabicTest.ttf` are retained as `tests/data/arabic-fallback-simp-tests.txt`
  and `tests/data/arabic-fallback-trad-tests.txt`.
- HarfBuzz in-house `spaces.tests` horizontal and `ttb` rows are retained in
  `tests/data/spaces-horizontal.txt` for
  `1c2c3fc37b2d4c3cb2ef726c6cdaaabd4b7f3eb9.ttf`. Cangjie now maps Unicode
  space separators such as U+2000..U+200A, U+202F, U+205F, and U+3000 through
  the ASCII space glyph when the font lacks nominal coverage, then applies
  HarfBuzz-compatible horizontal and top-to-bottom fallback advances/origins.
- HarfBuzz in-house `automatic-fractions.tests` rows for ASCII digits
  (`U+0031,U+0032,U+0033,U+2044,U+0034,U+0035,U+0036`) and Arabic-Indic digits
  (`U+0661,U+0662,U+0663,U+2044,U+0664,U+0665,U+0666`) pass for
  `15dfc433a135a658b9f4b1a861b5cdd9658ccbb9.ttf`. Cangjie now assigns
  fraction-scoped `numr/frac/dnom` features when digits appear on both sides of
  U+2044 while leaving one-sided fraction-slash inputs unmodified. The four
  one-sided ASCII and Arabic-Indic fraction-slash controls from the same upstream
  file are retained as well.
- The U+2010 and U+2011 rows from HarfBuzz in-house `hyphens.tests` pass for
  `1c04a16f32a39c26c851b7fc014d2e8d298ba2b8.ttf`. When a font lacks a nominal
  non-breaking hyphen glyph but has U+2010, Cangjie mirrors HarfBuzz's normalize
  fallback and uses the U+2010 glyph while preserving the original source
  cluster.
- The two HarfBuzz in-house `hangul-jamo.tests` rows are retained for
  `757ebd573617a24aa9dfbf0b885c54875c6fe06b.ttf` and
  `7e14e7883ed152baa158b80e207b66114c823a8b.ttf`. Cangjie now keeps `calt`
  away from a standalone Hangul Jamo scalar while leaving the multi-jamo fixture
  intact. Focused `hangul-calt.tests` rows for
  `600387433d01cd5799e421dad6510a54c862f56b.ttf` are retained for
  `U+AC00,U+003D,U+003E`, `U+AC00,U+B098`, conjoining Jamo `U+1100,U+1100`,
  `U+B098,U+B098`, and explicit
  `calt=0`; conjoining-Jamo runs now default `calt` off, while precomposed
  Hangul syllables and common punctuation keep HarfBuzz's default contextual
  alternates. The parity tool keeps conjoining-Jamo byte clusters instead of
  folding them to the grapheme start.
- The Thai rows from HarfBuzz in-house `zero-width-marks.tests` pass for
  `45855bc8d46332b39c4ab9e2ee1a26b1f896da6b.ttf`,
  `7a37dc4d5bf018456aea291cee06daf004c0221c.ttf`,
  `8099955657a54e9ee38a6ba1d6f950ce58e3cc25.ttf`, and
  `bb0c53752e85c3d28973ebc913287b8987d3dfe8.ttf`
  (`U+0E01,U+0E34,U+0E01`). Cangjie now keeps GPOS MarkBasePos active when a
  Unicode mark is present even if GDEF misclassifies that glyph as a base,
  synthesizes late zero-width mark classes for no-GDEF Thai runs, and separates
  mark attachment offset propagation from mark advance zeroing so HarfBuzz's
  zero-advance and preserved-advance fixture variants both match.
  The simple Latin `ABA` row for
  `a98e908e2ed21b22228ea59ebcc0f05034c86f2e.ttf` is retained too, covering a
  zero-advance middle glyph without mark attachment.
  The Myanmar standalone U+1030 row for
  `bb9473d2403488714043bcfb946c9f78b86ad627.ttf` is retained as well, covering
  dotted-circle insertion before a zero-width vowel sign.
  The Hebrew mark-positioning row for
  `8454d22037f892e76614e1645d066689a0200e61.ttf` is retained too, covering a
  zero-width Hebrew mark in an RTL run.
  The four Latin combining-tilde rows for
  `ffa0f5d2d9025486d8469d8b1fdd983e7632499b.ttf`,
  `cc5f3d2d717fb6bd4dfae1c16d48a2cb8e12233b.ttf`,
  `fcdcffbdf1c4c97c05308d7600e4c283eb47dbca.ttf`, and
  `56cfd0e18d07f41c38e9598545a6d369127fc6f9.ttf` are retained as inline
  HarfRust gates, covering zero-advance and preserved-advance combining marks.
- The default-script legacy `kern` row from HarfBuzz in-house
  `per-script-kern-fallback.tests` passes for
  `a04cc6365876308945033b2a49f54afe899e7bf8.ttf`
  (`U+002E,U+002E`). Cangjie now mirrors HarfBuzz's fallback kern machine by
  splitting a legacy kern value across the first glyph's advance and the second
  glyph's advance/offset, while still letting GPOS pair positioning suppress
  duplicate legacy kern application. The explicit `deva` script row for the
  same fixture also passes with legacy kern fallback disabled, matching
  HarfBuzz's `dist`-script exception. The no-GPOS/no-kern controls for
  `36b3cea27560cf68b1f3a5d5b6f29d29a96393aa.ttf` are now retained for default,
  Devanagari, and Latin script selection. GPOS-only and GPOS-plus-legacy-kern
  rows from the same upstream file are retained for
  `96fcf8dc57095c3d89f69b0f74f0d802c213f4da.ttf` and
  `8a312e38b9b90183ef154a0c2ab92a9def6cb82f.ttf`; `tt-kern-gpos.tests` is
  retained for `b121d4306b2e3add5abbaad21d95fcf04aacbd64.ttf`. Apple/AAT
  `kern` format-2 class subtables are now applied for horizontal fallback
  kerning as well; all three
  `kern-format2.tests` rows for
  `e39391c77a6321c2ac7a2d644de0396470cd4bfe.ttf` are retained.
- The explicit `pnum` row from HarfBuzz in-house `digits.tests` passes for
  `e5ff44940364c2247abed50bdda30d2ef5aedfe4.ttf`
  (`U+0661,U+0662,U+0668,U+0663,U+0667`, script `arab`). Cangjie now applies
  caller-enabled optional GSUB features after the core Arabic shaping stages,
  and `shape-bench` can force an OpenType script tag for retained upstream rows
  that specify `--script`.
- The U+06DD enclosed-number row from HarfBuzz in-house `digits.tests` passes
  for `a6b17da98b9f1565ba428719777bbf94a66403c1.ttf`
  (`U+06DD,U+0661,U+0662,U+0663`, script `arab`). Cangjie accepts contextual
  GPOS class subtables whose covered class has no ClassSet slot, matching
  HarfBuzz's no-match behavior, and the parity tool keeps Arabic Prepend
  clusters in HarfBuzz buffer-cluster order for this row. The related
  `b082211be29a3e2cf91f0fd43497e40b2a27b344.ttf` row
  (`U+06DD,U+0661,U+0662,U+0628`) also passes. `compare-harfbuzz` now forwards
  explicit `--script` tags to the in-process HarfBuzz reference, enables
  HarfBuzz-style native-direction shaping while keeping comparison output in
  buffer order, and preserves HarfBuzz's exception that pure Arabic numeric runs
  stay LTR while mixed Arabic-letter runs shape internally RTL. The enclosed
  Arabic-number rows for `3b791518a9ba89675df02f1eefbc9026a50648a6.ttf` are
  retained in both LTR and RTL directions.
- All 13 HarfBuzz in-house `language-tags.tests` rows are retained. Cangjie maps
  BCP-47 `dv` to OpenType `DHV ` for the Dhivehi-localized `U+007C` row, maps
  Persian `fa` to `FAR `, and distinguishes generic Simplified/Traditional
  Chinese (`ZHS `/`ZHT `) from Hong Kong/Macau Traditional Chinese (`ZHH `).
  `shape-bench` accepts the upstream BCP-47 spellings directly in retained
  gates, including `zh-cn`, `zh-sg`, `zh-tw`, `zh-hans`, `zh-hant`,
  `zh-hant-hk`, `zh-HK`, `zh-mo`, and `zh-Hant-mo`.
- Representative Thai and Lao rows from HarfBuzz in-house `sara-am.tests` pass
  for `63a539a90a371ccf028dc2dcced9b63b07163be7.ttf`
  (`U+0E01,U+0E31,U+0E33` and `U+0E81,U+0EB1,U+0EB3`). Cangjie now performs
  HarfBuzz-compatible SARA AM preprocessing by decomposing SARA AM into
  Nikhahit plus SARA AA, moving the generated Nikhahit before preceding
  above-base marks, and keeping the decomposed cluster attached to the base.
  The Lao row `U+0E81,U+0ECE,U+0ECD,U+0EB2` is retained too; Thai/Lao
  combining marks now inherit the preceding cluster before shaping.
- HarfBuzz in-house `cursive-positioning.tests` rows that `shape-bench` can
  express now include the Arabic fixtures
  `c4e48b0886ef460f532fb49f00047ec92c432ec0.ttf` and
  `298c9e1d955f10f6f72c6915c3c6ff9bf9695cec.ttf` for `U+0643,U+0645,U+0645,U+062B,U+0644`,
  plus the Miao/Pollard fixture
  `9fc3e6960b3520e5304033ef5fd540285f72f14d.ttf`
  (`U+16F0A,U+16F57,U+16F8F`). TrueType subset faces with stale `maxp.maxZones`
  values remain loadable for shaping, and Miao vowel/tone signs stay in the
  base glyph's UTF-8 cluster, matching HarfBuzz's USE category data for
  dependent vowels and tone marks. The Pollard `be10ea33...` fixture's
  `rtl1,ltr2` row is retained too; later cursive lookups now clear reciprocal
  attachment links from earlier lookups before installing the replacement chain,
  matching HarfBuzz's final y-offset propagation.
- Myanmar now has a dedicated modern `mym2` shaping slice instead of falling
  through generic GSUB. Focused HarfBuzz in-house rows pass for
  `mark-attachment.tests` (`98b7887cff91f722b92a8ff800120954606354f9.ttf`,
  `U+100F,U+103C,U+102F,U+1036`) and the simple `myanmar-misc.tests` rows
  (`065b01e54f35f0d849fd43bd5b936212739a50cb.ttf` `U+101A,U+1035`, plus
  `a232bb734d4c6c898a44506547d19768f0eba6a6.ttf`
  `U+1000,U+1031,U+1084`). The simple `myanmar-syllable.tests` common-prefix
  row for `65d1b9099cfb3191931d8d6112d7a03d979d579f.ttf`
  (`U+00B2,U+1000`) is retained as well. The FE00 variation-selector syllable
  row for `af3086380b743099c54a3b11b96766039ea62fcd.ttf` is retained after GSUB
  ligature matching learned to skip only fallback variation-selector glyph id
  zero, while real FE00 glyphs remain visible to `rlig`. The tone-sign ordering
  row for `f4ba5a767ef56a40133844507efb98fee5635e71.ttf` is retained too. The
  Myanmar `ligature-id.tests` row for
  `a6c76d1bafde4a0b1026ebcc932d2e5c6fd02442.ttf` is retained as
  `tests/data/myanmar-ligature-id-tests.txt`; the shaper now keeps the
  `nga+asat+virama` kinzi prefix after the base for `rphf`, so the subsequent
  `blwf` ligatures can collapse `ra+medial wa` and kinzi plus U+102D. The
  slice covers `mym2` cluster ownership, basic Myanmar initial reordering for
  medial RA and left matras, variation selectors inheriting the preceding
  Myanmar position, the `rphf/pref/blwf` `/pstf` stage order, and final
  `pres/abvs/blws/psts` plus typographic ligature features; full Myanmar
  syllable-machine coverage is still a follow-up.
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
  The `glyph-props-no-gdef.tests` Javanese fallback row for
  `FallbackPlus-Javanese-no-GDEF.otf` is retained as well, covering mark/base
  property fallback when a font lacks GDEF.
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

Conclusion: Amiri Arabic long text and some complex Arabic/Nastaliq slices now
beat HarfBuzz locally. Roboto Latin words now also beat HarfBuzz on the current
fixed-P-core matrix, while the Amiri word list was within about one percent but
still trailed slightly in the preceding absolute matrix. This is not yet a
broad cross-font or cross-script performance win, and the overall goal remains
active.

The latest post-`077a833` fixed-P/E-core absolute matrix sharpens that
workload-dependent conclusion:

- Roboto `en-words` was about `17.30%` faster than HarfBuzz on CPU 8 and
  `13.93%` faster on CPU 30.
- SourceSerifVariable `en-words` was about `18.43%` faster on CPU 8 and
  `17.52%` faster on CPU 30.
- Amiri `fa-thelittleprince` was about `14.86%` faster on CPU 8 but about
  `0.51%` slower on CPU 30, which is effectively the boundary of run noise.
- Before the later cross-stage feature-plan reuse, NotoSansDevanagari
  `hi-words` was about `42.89%` slower on CPU 8 and `52.23%` slower on CPU
  30. The later optimizations above reduced the stable CPU-8 gap first to
  `28.74%` and then to about `21.93%`;
  Indic therefore remains the largest shaping-performance deficit, but the
  older percentages are no longer the current state.

These are serial same-host Cangjie/HarfBuzz/HarfBuzz/Cangjie measurements, not
cross-machine headlines. Latin and selected Arabic/variable-font paths now have
real local wins, but the Devanagari result alone rules out claiming broad
shaping-performance superiority.

## Near-Term Gaps

- Add a library-level HarfRust comparison runner. The `harfbuzz` `shape-bench`
  engine is now in-process, but the current `harfrust` engine remains a batch
  external-process baseline, not a fully fair in-process performance baseline.
- Expand the benchmark matrix beyond Amiri, Roboto, SourceSerifVariable,
  NotoNastaliqUrdu, and the active Devanagari gate; Gulzar now passes a retained
  1,000-line `fa-words` slice, but full broader Arabic font corpora, Urdu,
  Nastaliq, and mixed-script texts still need retained parity coverage.
- Arabic normalization now composes the focused canonical base+hamza/madda
  pairs when the selected font has the precomposed cmap glyph. The
  HarfBuzz in-house `872d2955d326bd6676a06f66b8238ebbaabc212f.ttf`
  `arabic-normalization.tests` slice passes for all 32 lines covered by that
  font, including contextual forms after `beh` and repeated `yeh+hamza`
  sequences. The same in-house file's
  `3e46c3b84c1370a06594736c7f8acebf810bbb3b.ttf` slice is retained as
  `tests/data/arabic-normalization-3e46-tests.txt` and covers all 32
  normalization lines after GSUB class-format validation learned to treat
  covered classes with no ClassSet slot as legal no-op matches, matching the
  runtime behavior already used by Cangjie and HarfBuzz. The `uniscribe.tests`
  `U+0628,U+0628,U+0628` row for
  `872d2955d326bd6676a06f66b8238ebbaabc212f.ttf` is retained too, covering the
  high contextual medial form. The expressible `coretext.tests` file contains
  the same Arabic high-contextual row and is represented by this retained gate.
- HarfBuzz in-house `kbts.tests` rows that `shape-bench` can express are
  retained against HarfRust. `tests/data/kbts-arabic-tests.txt` covers the high
  contextual Arabic forms for `872d2955d326bd6676a06f66b8238ebbaabc212f.ttf`;
  `tests/data/kbts-mixed-tests.txt` covers the `ffi` ligature and the `waw beh
  alef` Arabic row for `7bbd3175734d5d291e1c15271ec0cbb97b626ebf.ttf`. The
  disabled-`liga` `ffif` row is retained as an inline HarfRust gate.
- HarfBuzz in-house `item-context.tests` rows that only require before/after
  Arabic joining context are retained as inline HarfRust gates. `shape-bench`
  now accepts `--text-before`/`--text-after`; Cangjie uses those contexts only
  to resolve item-boundary Arabic joining forms while keeping GSUB/GPOS matching
  scoped to the shaped item. The `--bot` dotted-circle rows are retained too;
  beginning-of-text Arabic marks insert a synthetic dotted-circle base unless a
  pre-context is supplied.
- Mongolian Free Variation Selectors now participate in the Arabic-style
  joining shaper under the `mong` ScriptList. The focused
  `arabic-feature-order.tests` FVS rows for
  `813c2f8e5512187fd982417a7fb4286728e6f4a8.ttf` and
  `8a9fea2a7384f2116e5b84a9b31f83be7850ce21.ttf` are retained, and the simple
  `mongolian-variation-selector.tests` rows for
  `ef86fe710cfea877bbe0dbb6946a1f88d0661031.ttf` plus
  `37033cc5cf37bb223d7355153016b6ccece93b28.ttf` pass. Broader Mongolian
  fixture coverage now reaches
  `4d4206e30b2dbf1c1ef492a8eae1c9e7829ebad8.ttf` after `gasp` parsing was
  relaxed to match FreeType/HarfBuzz-style structural validation: version-0
  tables that carry version-1 behavior bits are accepted, while behavior
  queries mask those bits to the version-0 low-bit contract. The MVS word case
  `U+182A,U+1820,U+1822,U+182D,U+180E,U+1820,U+202F,U+1836,U+1822,U+1828`
  now also matches after contextual GSUB learned to keep U+180E visible for
  explicit Mongolian backtrack/lookahead rules. The Arabic Allah-ligature row
  for `a919b33197965846f21074b24e30250d67277bce.ttf` is retained after Arabic
  shaping learned HarfBuzz's required pause between `rlig` and `calt`. The
  remaining Arabic `calt` row for `bf39b0e91ef9807f15a9e283a21a14a209fd2cfc.ttf`
  is retained too; Arabic now runs `calt/rclt` before later `liga/clig`, matching
  HarfBuzz's additional post-`calt` pause.
- Track output parity, not only timing. `compare-harfrust` and
  `compare-harfbuzz` both compare glyph ids, clusters, advances, and offsets in
  HarfBuzz-style buffer order; focused in-process HarfBuzz feature checks are
  covered, but broader font/script matrices still need expansion.
- `shape-bench` now exposes HarfBuzz-compatible `--cluster-level 0|1|2|3` and
  forwards it to Cangjie, HarfRust, and the in-process HarfBuzz runner. The
  x/X plus ring rows from HarfBuzz in-house `cluster.tests` are retained for
  `4fac3929fc3332834e93673780ec0fe94342d193.ttf` at cluster levels 3 and 2,
  covering grapheme-level cluster merging versus character-level cluster
  retention. The Hebrew RTL `cluster-level=1` row for
  `43ef465752be9af900745f72fe29cb853a1401a5.ttf` is retained too; Cangjie now
  mirrors HarfBuzz's cluster merge when mark reordering moves a Hebrew point
  leftward under an explicit monotone cluster level. `shape-bench` also accepts
  `--no-positions`, matching upstream cluster-only fixtures; all eight Thai
  SARA AM `cluster.tests` rows for the same `4fac...` font are retained for
  cluster levels 0-3 without letting fallback-positioning differences hide the
  cluster signal. The Malayalam `cluster-level=1` dot-reph broken-cluster row
  for `fd07ea46e4d8368ada1776208c07fd596f727852.ttf` is retained too; the
  inserted dotted circle, virama, and ZWJ now keep HarfBuzz-compatible cluster
  ownership on U+0D4E. The Sinhala row for
  `c2d320136762887c43d245ecd2ffc2c0d57cfcb3.ttf` is retained as well. The
  Bengali `cluster-level=1` row for
  `6f36d056bad6d478fc0bf7397bd52dc3bd197d5f.ttf` is retained after parse-time
  GSUB validation stopped rejecting HarfBuzz-accepted unsorted FeatureList
  records and Bengali split-matra/below-vowel cluster ownership learned to
  mirror HarfBuzz. With these gates, the full HarfBuzz in-house
  `cluster.tests` file is retained.
- The expressible HarfBuzz in-house `directwrite.tests` rows are represented by
  existing retained gates: Arabic high contextual forms for
  `872d2955d326bd6676a06f66b8238ebbaabc212f.ttf`, the `ffi`/disabled-`liga`
  and Arabic `waw beh alef` rows for
  `7bbd3175734d5d291e1c15271ec0cbb97b626ebf.ttf`, plus the variable-font
  spacing rows for `HBTest-VF.ttf`, `ab40c89624a6104e5d0a2308e448a989302f515b.ttf`,
  and `e8691822f6a705e3e9fb48a0405c645b1a036590.ttf`.
- The `synthetic.tests` fixture font `NotoSans-VF.abc.ttf` now parses for
  shaping even though its optional STAT table carries stale name references;
  public STAT APIs still revalidate and report the invalid metadata. The
  `shape-bench` now exposes `--font-slant` and `--font-bold`, and retained
  Cangjie expected-output gates cover both upstream `synthetic.tests` rows:
  slanted `abc` in `ttb` with offsets `-280,-948`, `-307,-1056`,
  `-240,-949`, and synthetic-bold `abc` with offsets `-430,-1148`,
  `-457,-1256`, `-390,-1149`.
- AAT and extents parity remain open. Both HarfBuzz in-house `aat-morx.tests`
  rows are retained: Cangjie now runs a focused AAT `morx` ligature
  state-machine path that forms `A_E_D` across intervening glyphs while
  preserving HarfBuzz-style clusters, and it tolerates the stale static SFNT
  search/header checksum metadata needed by the Tamil `morx` fixture while
  keeping public lazy table APIs strict. All eight `aat-trak.tests` rows are
  retained for `TRAK.ttf`; Cangjie applies AAT noncontextual `morx` alternates
  and interpolates horizontal `trak` advances for the requested point size. The
  `shape-bench` now has a `--show-extents` summary surface, and the
  `color-fonts.tests` CBDT and sbix rows are retained against in-process
  HarfBuzz extents (`0,2179,2963,-2789` and `0,1898,2555,-2405`). The HarfRust
  CLI still reports zero color-glyph extents for these rows, so the retained
  automated reference is HarfBuzz rather than HarfRust.
- The full six-row HarfBuzz in-house `default-ignorables.tests` file is retained
  as inline gates. It covers CGJ/Arabic and ZWJ/mark interactions across the
  fixture fonts named above; broader default-ignorable work now belongs to
  expanding other upstream files rather than this in-house fixture.
- The HarfBuzz in-house `unsafe-to-concat.tests` glyph/cluster/advance row is
  retained for `34da9aab7bee86c4dfc3b85e423435822fdf4b62.ttf` as
  `tests/data/unsafe-to-concat-tests.txt`; RTL ZWNJ now keeps the following
  visible Arabic glyph on the join-control cluster like HarfBuzz/HarfRust.
  `shape-bench` now exposes `--show-flags --unsafe-to-concat` and compares the
  HarfBuzz-style `HB_GLYPH_FLAG_UNSAFE_TO_CONCAT` value against HarfRust for
  the retained row.
- Arabic/Syriac stretch shaping now runs the HarfBuzz-style `stch` GSUB stage
  before positional Arabic features, records MultipleSubst component parity as
  fixed/repeating tiles, and stretches those tiles in the final glyph stream
  using font-unit advances and overlap arithmetic. The three upstream
  `arabic-stch.tests` rows for
  `507637795ce4f2975593da54d12b46f76c7cc4cc.ttf` and
  `d9b8bc10985f24796826c29f7ccba3d0ae11ec02.ttf` are retained as inline
  HarfBuzz parity gates. HarfBuzz in-house `reverse-sub.tests` rows 1 and 3
  are retained for `a706511c65fb278fda87eaf2180ca6684a80f423.ttf` and
  `1b66a1f4b076b734caa6397b3e57231af1feaafb.ttf`; row 2 is retained for
  `3f24aff8b768e586162e9b9d03b15c36508dd2ae.ttf` with `salt=2`;
  the benchmark parser now preserves feature values, and the Arabic final GSUB
  stage merges default and caller-enabled optional features by lookup order so
  alternate-selection values reach contextual final forms. The explicit
  `rand=2` row from `rand.tests` is retained for
  `5bb74492f5e0ffa1fbb72e4c881be035120b6513.ttf`; the disabled `rand=0` row is
  retained for the same font as a control. Generic GSUB feature selection now
  carries feature values to AlternateSubst lookups instead of reducing selected
  lookups to bare indexes. The default `rand` row for the same font is retained
  too; Cangjie enables HarfBuzz-style random
  AlternateSubst by default, uses the same 32-bit wrapping minstd LCG state, and
  bypasses index-only GSUB selection caching when a lookup needs feature-value
  or random metadata.
- Arabic-like joining now includes Adlam in the Arabic-style positional shaper:
  the HarfBuzz in-house `arabic-like-joining.tests` Adlam long joining row for
  `5dfad7735c6a67085f1b90d4d497e32907db4c78.ttf` is retained as an inline
  HarfRust gate. The same in-house file's
  `ec404b8524cd56efa5d25524cc8541a0b6604b4f.ttf` Phags-Pa rows now pass after
  Cangjie enabled HarfBuzz-style direction features (`ltrm`/`rtlm`) and kept
  variation selectors with ordinary cmap glyphs visible for GSUB fallback
  matching when no cmap-14 variation record exists.
- The Old Italic LTR/default and explicit-RTL rows from HarfBuzz in-house
  `none-directional.tests` now have retained inline gates for
  `73e84dac2fc6a2d1bc9250d1414353661088937d.ttf`
  (`U+10300,U+10301`). Cangjie's benchmark CLI can now request native-direction
  shaping explicitly with `--native-direction-shaping`; with
  `--no-bidi-reorder`, this exposes HarfBuzz buffer-order semantics and keeps
  the `rtlm` substitutions in final RTL order.
- The HarfBuzz in-house `variations-rvrn.tests` boundary for
  `d23d76ea0909c14972796937ba072b5a40c1e257.ttf` is retained with normalized
  coordinates `0,0.65,0` and `0,0.7,0`. Cangjie now enables `rvrn` by default
  and applies GSUB FeatureVariations condition sets so the low coordinate keeps
  `rvrn_base` while the high coordinate selects `rvrn_subst`.
- `shape-bench --variation` now accepts HarfBuzz-style `tag=value` design
  coordinates in addition to normalized CSV coordinates. Four HarfRust retained
  inline gates cover `variations.tests` rows for `HBTest-VF.ttf` (`TEST=491`
  and `TEST=509`), `ab40c89624a6104e5d0a2308e448a989302f515b.ttf`
  (`wdth=60` and `wdth=402`), and
  `e8691822f6a705e3e9fb48a0405c645b1a036590.ttf` (`0001=500`). Cangjie now
  tolerates hidden duplicate `fvar` axes and matching duplicate STAT design axes
  so this FontForge/HOI-style variation font can map one public design tag onto
  every same-tag internal axis, matching HarfBuzz/HarfRust.
- The HarfBuzz in-house `tibetan-vowels.tests` rows for
  `82f4f3b57bb55344e72e70231380202a52af5805.ttf` are retained for
  `U+0F68,U+0F72` and `U+0F68,U+0F7F`. Cangjie now applies Tibetan
  `abvs`/`blws` shaping features by default and keeps Tibetan vowel/sign marks
  in the base cluster, covering both the `uni0F680F72` ligature and the rnam
  bcad cluster merge case.
- All 60 HarfBuzz in-house `tibetan-contractions-1.tests` rows for
  `a02a7f0ad42c2922cb37ad1358c9df4eb81f1bca.ttf` are retained as
  `tests/data/tibetan-contraction-feff-tests.txt`; leading `U+FEFF` no longer
  misclassifies the run as Arabic presentation-form text during
  native-direction parity shaping, and the first visible Tibetan glyph inherits
  the leading default-ignorable cluster to match HarfBuzz/HarfRust.
  All 53 `tibetan-contractions-2.tests` rows for
  `2de1ab4907ab688c0cfc236b0bf51151db38bf2e.ttf` are retained as
  `tests/data/tibetan-contraction-2-tests.txt`.
- The single HarfBuzz in-house `sinhala.tests` row for
  `5af5361ed4d1e8305780b100e1730cb09132f8d1.ttf` is retained for
  `U+0DBB,U+0DCA,U+200D,U+0DBA,U+0DCA,U+200D,U+0DBA`, covering the Sinhala
  rakaransaya/yansaya ligature path against HarfRust.
- The HarfBuzz in-house `rotation.tests` / `vertical.tests` angle-bracket fallback rows for
  `2681c1c72d6484ed3410417f521b1b819b4e2392.ttf` are retained for
  `U+3008` in `rtl`, `ttb`, and `btt` directions. Cangjie now applies the
  HarfBuzz vertical-presentation fallback forms when the font has the target
  cmap glyph, and bottom-to-top vertical shaping no longer lets the horizontal
  bidi mirroring pass replace `U+FE40` with the ordinary mirrored bracket.
  The CFF2+VORG `NotoSansCJK-VF.abc.otf` rows for `AB` in `ttb` are retained at
  default and `wght=700`; exact duplicate HVAR/VVAR DeltaSetIndexMap payloads
  are accepted, and the parity tool reports HarfBuzz-style VORG y origins. The
  glyf+vmtx `NotoSansCJK-VF.abc.ttf` rows for the same text and variation
  settings are retained too; when VORG is absent, `shape-bench` derives the
  HarfBuzz vertical origin from glyf bounds plus vmtx top side bearing.
- Expand the new Indic shaper slice beyond the current Devanagari `nukt`,
  `akhn`, `rphf`, `rkrf`, `half`, `cjct`, `pres`, `abvs`, `blws`, and `psts`
  stages; the current `hi-words.txt` gate only covers the active Devanagari
  word corpus, not full HarfBuzz Indic script parity. The focused
  `indic-init.tests` Bengali row for
  `1a3d8f381387dd29be1e897e4b5100ac8b4829e1.ttf` now passes after the Indic
  slice learned `bng2`/`beng` pre-base matra reordering, source-scoped `init`
  on word-start left matras, and cluster merging for the moved matra. The
  Bengali `context-matching.tests` row for
  `49bd922bd447fb15bb05abab5c7ceac8d547a3a2.ttf` is retained too; Cangjie now
  classifies U+09BF as a Bengali left matra and constrains Indic contextual
  GSUB stages to source syllables, so `pres` can form `uni09BF.short01` before
  `uni09B9` without letting that syllable's `uni09B9` satisfy a later
  cross-syllable backtrack for `uni09A8`. The Bengali `indic-decompose.tests`
  row for `932ad5132c2761297c74e9976fe25b08e5ffa10b.ttf` is retained too,
  covering the no-decompose treatment for RRA/RHA alongside explicit nukta
  sequences. The Devanagari
  `context-matching.tests` row for
  `d629e7fedc0b350222d7987345fe61613fa3929a.ttf` is retained for
  `U+0915,U+093F,U+0915,U+093F`, covering repeated pre-base matra context in a
  compact Indic fixture. The Bengali conjunct row from the same upstream file
  is retained for `f499fbc23865022234775c43503bba2e63978fe1.ttf` with
  `U+09B0,U+09CD,U+09A5,U+09CD,U+09AF,U+09C0`; Cangjie now marks Bengali
  post-base `virama+consonant` sources for `pstf` and reorders formed reph
  before the post-base consonant form so the final contextual `psts` rule can
  collapse `reph + post-form + ii`. The remaining `context-matching.tests` row
  for `a59fd13f1525a91cbe529c882e93d9d1fbb80463.ttf` is retained as an inline
  HarfRust gate for `AB`; Cangjie now accepts HarfBuzz-style `OTTO`
  layout-only shaping subsets without `CFF`/`CFF2` while leaving outline APIs
  to report `MissingTable` if glyph geometry is requested. The Bengali
  `ligature-id.tests` file for
  `1c2fb74c1b2aa173262734c1f616148f1648cfd6.ttf` now retains the leading
  `U+0995,U+09CD,U+0995` conjunct by keeping the pre-base virama available for
  `half` before the `pres` ligature stage. Old-spec Bengali still normalizes
  `virama+ra` to the `ra+virama` glyph order for `blwf/vatu`. The Arabic
  `ligature-id.tests` row for
  `b31e6c52a31edadc16f1bec9efe6019e2d59824a.ttf` is retained too, covering a
  `lam + fatha + lam + damma + heh` ligature with mark positioning; the long
  repeated `fa + alef` Arabic row for `8339c821814d9bad7c77169332327ad8b0f33c81.ttf`
  is retained as an inline HarfRust gate as well. The Bengali `indic-syllable.tests`
  placeholder row for `87f85d17d26f1fe9ad28d7365101958edaefb967.ttf` is
  retained too; U+0980 now acts as a placeholder base so the following
  candrabindu merges into the same shaping cluster.
  Malayalam `indic-pref-blocking.tests` rows for
  `226bc2deab3846f1a682085f70c67d0421014144.ttf` and
  `e207635780b42f898d58654b65098763e340f5c7.ttf` now pass as retained inline
  gates too: the Indic slice handles `mlm2`/`mlym` categories, source-scoped
  `pref`, formed `virama+ra` pre-base ligature reordering, and the blocked path
  where a contextual `pref` lookup decomposes the ligature back to visible
  `virama,ra`. The Malayalam `indic-special-cases.tests` stacker row for
  `c825900b8a5b6571f0eb6c8c25c6512880bc42e9.ttf`
  (`U+0D15,U+0D4D,U+0D2F`) now passes by keeping the modern `mlm2` virama before
  the stacker consonant until `pstf` can form the stacker glyph. The first
  Malayalam `indic-malayalam-dot-reph.tests` row for
  `55e2910dbc9ef5dd89f4e146e7e0152169545b6a.ttf` is retained for
  `U+0D4E,U+0D15`; the same modern Malayalam ordering fix now also retains
  doubled-consonant stackers such as `U+0D17,U+0D4D,U+0D17`,
  `U+0D17,U+0D4D,U+0D17,U+0D4B`, and logical-repha combinations such as
  `U+0D4E,U+0D28,U+0D4D,U+0D28`. Cangjie now runs canonical split-matra
  decomposition in the Indic path so U+0D4B shapes as `E + AA` components before
  GSUB/GPOS, but the old Malayalam stacker/pref ligature stage still needs
  broader parity work.
  Traditional Indic shaping now follows HarfBuzz's no-zero-width-mark policy,
  so rows 13 and 14 keep the Malayalam U vowel sign advance. The Malayalam
  `indic-old-spec.tests` row for
  `270b89df543a7e48e206a2d830c0e10e5265c630.ttf` is retained for
  `U+0D38,U+0D4D,U+0D31,U+0D4D,U+0D31,U+0D4D`, covering the old-spec
  `sa+virama+rra` ligature path. The
  Gurmukhi standalone U+0A51 row from
  `indic-syllable.tests` is retained for
  `1735326da89f0818cd8c51a0600e9789812c0f94.ttf`, along with the explicit
  `U+25CC,U+0A51` control row. Cangjie now routes `gur2`/`guru` through the
  Indic shaper with Gurmukhi-specific consonant, mark, and virama
  classification so broken Gurmukhi mark clusters receive the HarfBuzz
  dotted-circle base without duplicating one already present in the input.
  Additional Gurmukhi `indic-syllable.tests` rows are retained for
  `85fe0be440c64ac77699e21c2f1bd933a919167e.ttf` and
  `f75c4b05a0a4d67c1a808081ae3d74a9c66509e8.ttf`, covering yakash and udaat
  mark positioning around `U+0A47` and `U+0A42`. The Gurmukhi
  `indic-special-cases.tests` rows for
  `5f73fff1ffc07b5a99a90c0909609f2b09fef274.ttf` are retained as
  `tests/data/gurmukhi-special-mark-order-tests.txt`, covering the two
  `ka + ii + bindi` mark-order permutations.
  The three Kannada `indic-special-cases.tests` rows for
  `3cae6bfe5b57c07ba81ddbd54c02fe4f3a1e3bf6.ttf` are retained for
  `U+0CB0,U+0CCD,U+0C95`, `U+0CB0,U+200D,U+0CCD,U+0C95`, and
  `U+0CB0,U+0CCD,U+200D,U+0C95`; Cangjie now routes `knd2`/`knda` through the
  Indic shaper, uses Kannada's virama and consonant/mark classes, preserves
  HarfBuzz's Kannada `Ra+Halant+ZWJ` compatibility ordering, and merges the
  formed reph cluster across the syllable. The Kannada placeholder row
  `U+0C80,U+0C82` from `indic-syllable.tests` is retained for
  `81c368a33816fb20e9f647e8f24e2180f4720263.ttf`; Cangjie now treats U+0C80
  as a HarfBuzz placeholder/base and merges the following dependent mark into
  its shaping cluster instead of inserting a dotted circle. The Kannada
  `U+0CF1` and `U+0CF2` rows for
  `3d0b77a2360aa6faa1385aaa510509ab70dfbeff.ttf` are retained as compact
  single-glyph syllable controls. The Kannada `indic-consonant-with-stacker.tests` rows for
  `a014549f766436cf55b2ceb40e462038938ee899.ttf` and
  `55c88ebbe938680b08f92c3de20713183e0c7481.ttf` are retained too; Cangjie now
  keeps `U+0CF1/U+0CF2` in the same source syllable as the following consonant,
  allowing contextual `psts` stacker forms. The Vedic `U+1CF5,U+0915`
  consonant-with-stacker row for `4fbf14f4f51c21480971aa9ea81c229660924caa.ttf`
  is retained as well; U+1CF5 now participates as a Devanagari
  consonant-with-stacker base. The Telugu
  `indic-special-cases.tests`
  word `U+0C1A,U+0C3F,U+0C32,U+0C4D,U+0C15,U+0C42,U+0C30,U+0C4D` now has a
  retained gate for `e716f6bd00a108d186b7e9f47b4515565f784f36.ttf`; Cangjie
  routes `tel2`/`telu` through the Indic shaper, applies Telugu `blwf`/`abvs`
  and final `haln`, and reorders before-subscript vowels ahead of formed
  subscript consonants. The Tamil `indic-syllable.tests` row for
  `54674a3111d209fb6be0ed31745314b7a8d2c244.ttf` is retained for
  `U+0BA4,U+0BCD,U+00B3`; Cangjie now routes `tml2`/`taml` through the Indic
  shaper and marks Tamil `consonant+virama` sources for `half`, covering the
  `ta + pulli` pre-half form before a non-Tamil following glyph. The Tamil
  `pa,pa,pulli` row for `e2b17207c4b7ad78d843e1b0c4d00b09398a1137.ttf` is
  retained too, covering same-script consonant-plus-pulli output ordering. The
  Tamil `indic-feature-order.tests` row for
  `190a621e48d4af1fffd8144bd41d2027e9a32fbf.ttf` is retained with `ss03`
  enabled, covering explicit feature overrides before dependent-vowel output.
  The `indic-script-extensions.tests` row for
  `b151cfcdaa77585d77f17a42158e0873fc8e2633.ttf` is retained for Tamil plus
  Grantha marks. The longer mixed Tamil/Grantha pre-base vowel row for
  `3493e92eaded2661cadde752a39f9d58b11f0326.ttf` is retained too; Cangjie now
  treats U+1133C as a Tamil script-extension dependent mark and moves following
  nonspacing marks with pre-base matras. The Gurmukhi `indic-misc.tests` row for
  `755160ddba002332349fda3eb999e629d63dccf6.ttf` is retained for
  `U+0A2D,U+0A4D,U+0A30,U+0A42`; Cangjie now marks Gurmukhi `virama+ra` sources
  for `blwf` and keeps the following dependent
  vowel in the syllable cluster. The Odia `indic-joiner-candrabindu.tests`
  rows for `5028afb650b1bb718ed2131e872fbcce57828fff.ttf` are retained for
  `U+0B13,U+200D,U+0B01` and `U+0B13,U+200C,U+0B01`; Cangjie now routes
  `ory2`/`orya` through the Indic shaper so ZWJ can trigger the `abvs`
  candrabindu ligature, while the ZWNJ row keeps the dependent mark in the
  joiner's shaping cluster. The Odia `indic-syllable.tests` rows for
  `b3075ca42b27dde7341c2d0ae16703c5b6640df0.ttf` are retained for both
  `U+0B2C,U+0B55,U+0B3E` and `U+0B2C,U+0B3E,U+0B55`, covering mark order without
  reclassifying either mark as a broken cluster. The Devanagari
  `indic-joiners.tests` row for `8116e5d8fedfbec74e45dc350d2416d810bed8c4.ttf`
  is retained for `U+091F,U+094D,U+200C,U+092F,U+093F` and the mixed
  `ZWJ/ZWNJ/ZWJ` row `U+091F,U+094D,U+200D,U+091F,U+094D,U+200C,U+091F,U+094D,U+200D,U+092F,U+093F`;
  Cangjie now treats `virama+ZWNJ` as a syllable terminator, so the following
  pre-base matra targets the following `ya` syllable instead of jumping before
  the previous `tta`. The first 17 Devanagari rows of
  `indic-vowel-letter-spoofing.tests` are retained for
  `1a5face3fcbd929d228235c2f72bbd6f8eb37424.ttf`; rows 6-17 are retained in
  `tests/data/devanagari-vowel-letter-spoofing-extra-tests.txt`. Rows 18-20
  are retained for the Bengali font
  `881642af1667ae30a54e58de8be904566d00508f.ttf` in
  `tests/data/bengali-vowel-letter-spoofing-tests.txt`; rows 21-29 are
  retained for the Gurmukhi font
  `604026ae5aaca83c49cd8416909d71ba3e1c1194.ttf` in
  `tests/data/gurmukhi-vowel-letter-spoofing-tests.txt`; rows 38-40 are
  retained for the Odia font
  `2c25beb56d9c556622d56b0b5d02b4670c034f89.ttf` in
  `tests/data/odia-vowel-letter-spoofing-tests.txt`; rows 41-45 are retained
  for the Telugu font `03e3f463c3a985bc42096620cc415342818454fb.ttf` in
  `tests/data/telugu-vowel-letter-spoofing-tests.txt`; rows 46-48 are retained
  for the Kannada font `7d18685e1529e4ceaad5b6095dfab2f9789e5bce.ttf` in
  `tests/data/kannada-vowel-letter-spoofing-tests.txt`; rows 49-53 are
  retained for the Malayalam font
  `af85624080af5627fb050f570d148a62f04fda74.ttf` in
  `tests/data/malayalam-vowel-letter-spoofing-tests.txt`. Together with the
  Gujarati rows 30-37 below, all 53 upstream `indic-vowel-letter-spoofing.tests`
  rows are retained. Cangjie now runs the
  HarfBuzz vowel-constraint dotted-circle insertion table in the traditional
  Indic path before GSUB, and treats the synthetic dotted circle as an Indic
  placeholder base so the third row's `ra,virama,i` sequence forms `reph`
  around that dotted circle. The Devanagari `indic-old-spec.tests` rows for
  `b722a7d09e60421f3efbc706ad348ab47b88567b.ttf` are retained as
  `tests/data/devanagari-old-spec-tests.txt`; legacy `deva` fonts now run
  through the traditional Indic shaper, move old-spec halants after post-base
  consonants, and mark post-base Ra for `blwf` vattu before `vatu` forms
  `Tra`. The Devanagari `indic-special-cases.tests` U+094E rows for
  `9d8c53cb64b8747abdd2b70755cce2ee0eb42ef7.ttf` are retained as
  `tests/data/devanagari-special-prishthamatra-tests.txt`; U+094E now leads
  the reordered pre-base matra group while preserving neighboring nukta order.
  The `indic-syllable.tests` Devanagari word
  `U+0926,U+093F,U+0938,U+0902,U+092C,U+0930` is retained for
  `41071178fbce4956d151f50967af458dbf555f7b.ttf`; GSUB ligature matching now
  honors source-syllable boundaries while skipping lookup-flag ignored glyphs,
  so the pre-base matra does not combine with the next syllable's anusvara.
  Gujarati `gjr3`/`gjr2`/`gujr` now routes through
  the Indic shaper as well, retaining rows 30-34 of the same fixture for
  `738d9f3b8c2dfd03875bf35a61d28fd78faf17c8.ttf`; rows 35-37 are retained too
  after Gujarati split-matra components learned to keep the candra/ai component
  before the AA length component inside the same Indic syllable. The Gujarati
  `indic-joiners.tests` row for `63e224dcb3d559d590f80c83b832cfca789e5dcc.ttf`
  is retained as `tests/data/gujarati-indic-joiners-tests.txt`; Gujarati now
  marks `consonant+virama` sources for `half` and treats U+0ABF as a pre-base
  matra so the joined `na+virama` half form shapes before the following `ta`.
  The legacy
  Kannada `indic-old-spec.tests` row for
  `57a9d9f83020155cbb1d2be1f43d82388cbecc88.ttf` is retained for
  `U+0C9A,U+0CCD,U+0C9A,U+0CCD`; Cangjie now marks the trailing old-spec
  Kannada `consonant+virama` source for `blwf` and merges it into the syllable
  cluster, while the first pair remains the visible `haln` form.
- Add a focused Khmer shaper for the `khmr` script tag. The 89
  `khmer-misc.tests` rows for
  `3998336402905b8be8301ef7f47cf7e050cbb1bd.ttf` are retained as
  `tests/data/khmer-misc-tests.txt`; Cangjie now applies Khmer split-matra
  decomposition for `U+17BE/U+17BF/U+17C0/U+17C4/U+17C5`, marks Khmer
  syllable-scoped `pref/blwf/abvf/pstf/cfar` sources, reorders pre-base vowels
  and `COENG+RO` sequences before the base in HarfBuzz stage order, and runs
  the Khmer `pres/abvs/blws/psts/clig` final stage against HarfRust parity.
  The remaining `khmer-misc.tests` broken-mark rows are retained separately for
  `ad01ab2ea1cb1a4d3a2783e2675112ef11ae6404.ttf` and
  `086d83239e8f958391ff6cdd8fda9376a4bd3673.ttf`; standalone COENG and
  standalone Khmer xgroup marks now synthesize dotted-circle bases, while the
  `U+17D9,U+17C9` symbol-plus-mark control remains unchanged.
  The Khmer `indic-joiners.tests` rows for
  `f443753e8ffe8e8aae606cfba158e00334b6efb1.ttf` are retained as
  `tests/data/khmer-indic-joiners-tests.txt`; ZWNJ now terminates the Khmer
  syllable and owns the following mark cluster, while the no-ZWNJ control keeps
  the dependent marks in the preceding consonant cluster.
  All 25 `khmer-mark-order.tests` rows for
  `b6031119874ae9ff1dd65383a335e361c0962220.ttf` are retained as
  `tests/data/khmer-mark-order-tests.txt`; the Khmer shaper now inserts
  dotted circles before broken dependent-mark groups, including repeated marks
  that arise after split-matra decomposition.
- Expand USE shaping parity beyond the retained Duployan, Balinese, Javanese,
  Marchen, Cham, Batak, Brahmi, Chakma, Tai Tham, Newa, Saurashtra, Grantha,
  and Sharada gates. Other USE scripts/fonts and fuzz/corpus failures still
  need retained gates before this can be called broad USE parity.
- Expand the new Myanmar shaper beyond the current focused `mym2`
  mark-attachment, FE00 variation-selector syllable, tone-sign ordering, and
  simple `myanmar-misc` rows. Kinzi, dotted-circle handling, complex syllable
  segmentation, older `mymr` fallback behavior, and broader Myanmar in-house
  coverage still need retained gates before claiming broad Myanmar parity. The
  in-house `myanmar-zawgyi.tests` `Qaag` row now passes by
  treating Myanmar Zawgyi as HarfBuzz does: a script tag with auto shaping,
  normalization, zero-width-mark handling, and fallback positioning disabled.
- Continue Arabic hot-path work from measured profile evidence: GSUB `calt`
  context lookups now dominate after the GPOS lookup `37` cleanup; avoid
  retaining speculative prefilters unless they improve both Arabic and Roboto
  smoke runs reliably.
- Avoid retaining optimizations that only improve a single noisy run or regress
  Roboto/word-list smoke cases.
- Font cascade selection now treats each extended grapheme/shaping cluster as
  one fallback unit. A font must cover every visible scalar, explicit cmap-14
  UVS support wins when present, and default-ignorable join controls do not
  require nominal glyphs. If no font fully covers a sequence, the base font
  retains the cluster so missing marks remain diagnosable instead of being
  detached. The zero-allocation grapheme iterator has a direct ASCII path, and
  fixed-P-core HEAD/current probes over a cached two-font 1024-byte ASCII
  cascade reduced retired instructions from about 316.7M to 289.6M and cycles
  from roughly 90.5M to 70.8M median, rather than regressing the common path.
  Full Roboto `en-words` (`checksum=fd03166ae7017b20`) and Amiri `fa-words`
  (`checksum=246e98435cc9c642`) still pass in-process HarfBuzz parity.
- Repeated glyph rendering now has an explicit `PreparedGlyph` API and a
  `raster-prepared` benchmark mode. Preparation flattens curves once, removes
  horizontal/non-finite edges, computes slopes, sorts by activation y, and
  caches raw bounds; subsequent renders retain independent scratch and are safe
  to run concurrently. The existing direct `renderGlyph` scanner remains in its
  original module/code shape: an isolated fixed-P-core HEAD/current harness
  differed by less than 0.01% retired instructions. Prepared/direct fixed-P-core
  comparisons at 64 px reduced retired instructions by about 0.6% for Roboto
  `A`, 19.2% for `g`, 19.5% for `é`, 22.6% for Amiri `س`, and 14.0% for `م`;
  the four complex glyphs reduced cycles by roughly 16.7–22.0%. Direct and
  prepared target checksums are byte-identical, with differential tests for
  1/2/3/4 samples, repeated calls, empty outlines, and small-size emboldening.
- Predecoded PairPos format 2 accelerators now merge coverage membership and
  class1 into one sorted `(glyph, class)` table. Every covered first glyph gets
  its explicit or implicit-zero class during accelerator construction, so the
  hot adjacent-pair path performs one binary search instead of separate
  coverage and class1 searches; class2 and matrix indexing retain their prior
  semantics. Fixed-P-core HEAD/current comparisons kept retired instructions
  flat and improved median cycles by about `0.40%` for Roboto `en-words`,
  `0.11%` for Amiri `fa-words`, and `0.32%` for Amiri
  `fa-thelittleprince`. All three full in-process HarfBuzz parity checks remain
  unchanged (`fd03166ae7017b20`, `246e98435cc9c642`, and
  `f2da7bb39eb7323a`).
- Space-glyph fallback now runs only after the primary cmap lookup reports a
  missing glyph, and both that lookup and the fallback U+0020 lookup use
  `GlyphIndexCache` when supplied. Ordinary U+0020 previously bypassed the
  cache through the fallback helper, revalidating the borrowed cmap table
  13,881 times per Amiri `fa-thelittleprince` pass. A fixed-CPU-8 A/B/B/A
  comparison with 31-sample medians reduced the two-run mean from
  `1745.866` to `1431.046 ns/glyph`, about `18.0%`. Interleaved five-iteration
  hardware-counter runs reduced retired instructions by about `34.8%`,
  branches by `36.9%`, and cycles by `18.4%`; the profiled cmap/input stage
  fell from about `14.7 ms` to `5.9 ms`. Roboto `en-words` retired
  instructions and branches stayed within `0.02%`, while cycles varied by
  about `0.5%`. Focused tests retain the public borrowed-cmap mutation defense
  and missing Unicode-space fallback, and the full corpus gate passes both
  references, including `spaces-horizontal.txt`, Amiri, Roboto, and variable
  fonts.
