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
zig build shaping-performance-matrix -Doptimize=ReleaseFast -Denable-harfbuzz=true -Dharfbuzz-prefix=~/.cache/cangjie-next/harfbuzz-prefix -- --iterations 5 --samples 11 --cpu 30
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
HarfBuzz and HarfRust. NotoNastaliqUrdu now retains the same two Persian
corpora as cross-font Urdu/Nastaliq controls: `fa-words` produces 83,486
glyphs over 10,000 lines with checksum `fc28919889b8942b`, while
`fa-thelittleprince` produces 110,143 glyphs over 771 lines with checksum
`9e460d90b9034d46`; both pass both references. The gate also includes a
Bengali HarfBuzz in-house shaping
subset that omits `hhea`/`hmtx` and `glyf`, exercising shape-only font parsing
with HarfBuzz-compatible fallback advances, plus Arabic modifier-mark ordering
fixtures with and without CGJ.
The 24,709-line `react-dom.txt` source corpus is retained against both
references as a distinct long mixed-code workload. Roboto produces 1,043,900
glyphs with checksum `eafe0f780e6696cb`; SourceSerifVariable produces
1,042,546 glyphs with checksum `3a6d8292bce55621`. A fixed-CPU-30 serial
Cangjie/HarfBuzz/HarfBuzz/Cangjie timing matrix remained frequency-skewed but
consistently exposed a deficit: Roboto measured `601.73/438.21` versus
`363.76/332.51 ns/glyph`, and SourceSerif measured `438.97/618.12` versus
`332.75/344.36 ns/glyph`. This code-shaped corpus is therefore an active
HarfBuzz-relative performance target, not a Cangjie speed claim.
It also retains focused Indic in-house rows including Bengali contextual `pres`
at syllable boundaries.

As of the local `1ed2cf3` state, the full retained corpus command below
completes successfully with the isolated HarfBuzz prefix:

```sh
zig build shaping-corpus-parity-smoke -Doptimize=ReleaseFast -Denable-harfbuzz=true -Dharfbuzz-prefix=/Users/bytedance/.cache/cangjie-next/harfbuzz-prefix --summary none
```

This is a retained correctness-corpus result, not a completion signal for the
broader performance and cross-script coverage objectives below.
The `shaping-performance-matrix` command runs five representative corpora in
symmetric Cangjie/HarfBuzz/HarfRust/HarfRust/HarfBuzz/Cangjie order and reports
the geometric-mean speedup against the faster reference. The runner normalizes
the Zig engines' aggregate `iterations * samples` glyph count to the HarfRust
oracle's one-corpus count before checking output cardinality. A fixed-CPU-30
`5 * 11` run after adjacent required-component prefiltering measured speedups
of `0.959x` on Roboto, `0.879x` on Source Serif Variable, `1.010x` on Amiri
words, `1.107x` on long Amiri text, and `0.984x` on Noto Sans Devanagari
against the faster reference. This is direct current evidence that broad
shaping-performance superiority remains unproven.

Use `--profile` for defensive-path targeting only. It records glyph windows
around every GSUB lookup and therefore intentionally uses the generic lookup
dispatcher. Use `--profile-fast-path` when investigating optimized production
paths; it keeps validated lookup accelerators active and records lightweight
per-lookup timings without glyph-window snapshots.

Run the deterministic malformed-font smoke harness under safety checks with a
small, structurally varied seed set:

```sh
zig build font-fuzz-smoke -Doptimize=ReleaseSafe -- \
  src/tests/data/fontations_cmap12_font1.ttf \
  src/tests/data/fontations_names_only.ttf \
  src/tests/data/fontations_simple_glyf.ttf \
  src/tests/data/fontations_cmap14_font1.ttf \
  src/tests/data/fontations_vazirmatn_var.ttf \
  tests/data/fontations/vorg.ttf
```

For each seed, the harness tries the unmodified font, every prefix through byte
256, and 256 deterministic single-byte mutations. Every successfully parsed
case continues through public cmap lookup, glyph extents, outline decoding, and
grayscale rasterization. Parse or table-access errors are expected; a crash,
safety trap, or out-of-bounds access fails the command. This is a quick
regression gate, not a replacement for coverage-guided fuzzing or the broader
malformed-table matrix still required by the completion bar.

The same seed set also drives Zig 0.16's coverage-guided fuzzer through a
bounded sequence of correlated byte replacements plus optional truncation. A
second fuzz target constructs valid `morx`, `mort`, `kerx`, and `trak` fonts
before applying the same edit strategy, keeping AAT parsers reachable without
depending on an external Apple-font corpus:

```sh
zig build font-fuzz --fuzz=100K
```

Without `--fuzz`, the step executes each embedded seed and one deterministic
Smith input as a fast CI-compatible smoke check. ReleaseSafe is forced for
this target so safety checks remain enabled regardless of the surrounding
build mode. A retained 100K-run campaign exercised both targets for 213,657
inputs and reached 4,419 of 28,926 instrumented edges without a crash, leak, or
safety trap. The initial campaign exposed a CID CFF ownership leak when parsing
succeeded but a later whole-font validation failed; `Font.parseFace` now
releases that decoded Font DICT state transactionally and a regression retains
the exact failure path.

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

The 27 upstream `in-house/tests/use-syllable.tests` rows are retained in 15
script/font-grouped corpora for Cham, Grantha, Saurashtra, Batak, Brahmi,
Sharada, Tai Tham, Newa, and Chakma. Every corpus now participates directly in
`shaping-use-parity-smoke` against both HarfBuzz and HarfRust, rather than
being documented test data without a build dependency. Two additional compact
USE gates are:

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
runs the full `tests/data/use/*.txt` gate, all 15 grouped `use-syllable`
corpora, and the other compact gates against both HarfBuzz and HarfRust. The
Tai Tham slice specifically covers
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
`compare-harfbuzz` requires HarfBuzz 14.2 or newer because retained rows use
current syllable and attachment semantics; timing-only `--engine harfbuzz`
remains available with older installed libraries. This prevents a system
HarfBuzz 8.x from being mistaken for the documented/current parity oracle.

The `harfrust` engine shells out to `hr-shape` once per sample and uses
`hr-shape -n` for measured iterations. It remains the output-parity surface.
Strict timing is available separately through
`tools/harfrust_shape_oracle`: that executable links HarfRust directly and
retains its parsed font, `ShaperData`, shape plans, and reusable Unicode buffer
across measured iterations. It hashes complete output before and after timing,
then uses a constant-size measured consumer so process startup and serialized
glyph parsing are excluded. See the tool README for the paired command line.
On fixed CPU 30, a Cangjie/HarfRust/HarfRust/Cangjie matrix over five complete
NotoSansDevanagari `hi-words` passes and 11 samples, using the matching summary
consumer in both runners, measured Cangjie at `997.865`/`1009.690 ns/glyph`
and the new HarfRust library runner at `875.616`/`869.981 ns/glyph`. This
replaces subprocess-relative HarfRust timing with the missing strict library
baseline, but still leaves Cangjie about `15.0%` slower on this Indic workload.

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
- The former coarse `buildBidiMap` fed already-decoded and
  already-classified logical items into the same `BidiRunBuilder` used by
  public run itemization. It
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
- Single-font shaping now records bidi visual-reorder triggers while its source
  loop is already decoding UTF-8, then reuses that proof after positioning.
  The same pass skips number/letter classification unless an LTR request for an
  RTL script needs the numeric-direction guard. Devanagari has a direct block
  proof, while mixed text and explicit UAX #9 controls retain exact-class
  lookup. Fixed-CPU-30 A/B/B/A counters over 200 complete
  NotoSansDevanagari `hi-words` passes reduced retired instructions by about
  `2.1%` and branches by about `2.0%`; the retained A/B/B/A candidate timing
  pair measured `991.230`/`990.677 ns/glyph` against baseline
  `993.876`/`995.112 ns/glyph`. Full corpus comparison still passes HarfBuzz
  with checksum `b01a5388ce792b49`. A subsequent strict
  Cangjie/HarfRust/HarfRust/Cangjie matrix over ten passes and 11 samples
  measured `988.042`/`991.416` versus `878.737`/`876.135 ns/glyph`, leaving
  the library-level HarfRust gap at about `12.8%`.
- Homogeneous default-cluster Devanagari runs now use a validated three-byte
  UTF-8 source-population loop. The compact proof accepts only U+0900..U+097F,
  which excludes variation selectors, default-ignorables, bidi controls, and
  Arabic/Thai preprocessing before it bypasses those generic per-scalar
  predicates. The glyph-index cache miss path also reuses the parsed immutable
  face's cmap proof. On fixed CPU 30, an A/B/B/A counter matrix over 200 full
  `hi-words` passes reduced retired instructions by about `3.4%`, branches by
  about `4.3%`, and cycles by about `3.0%`; the candidate timing pair measured
  `955.166`/`953.848 ns/glyph` against baseline
  `963.178`/`958.788 ns/glyph`. A strict 11-sample library matrix measured
  Cangjie at `951.011`/`955.420 ns/glyph` versus HarfRust at
  `869.035`/`871.354 ns/glyph`, narrowing the remaining gap to about `9.5%`.
  Reusing the parsed immutable cmap path on cache misses removed a further
  `0.27%` of retired instructions without changing the hot cache-hit contract.
  The full 10,000-line corpus retains checksum `b01a5388ce792b49` against both
  HarfBuzz and HarfRust.
- The specialized `dev2` syllable/source-feature pass now also reports whether
  the source contains U+25CC or U+093F. Devanagari finish can therefore avoid
  whole-glyph placeholder and pre-base-matra scans for words that cannot need
  them, without changing the generic Indic path. A fixed-CPU-30 A/B/B/A matrix
  over 200 complete `hi-words` passes reduced retired instructions by about
  `0.96%`, branches by about `1.13%`, and cycles by about `0.59%`; output
  remained unchanged.
- Validated GPOS traversal now carries the exact lookup accelerator from the
  LookupList loop into dispatch. The same sidecar had already supplied the
  proved lookup offset, so the dispatcher no longer indexes it again and
  repeats its offset/identity checks merely to recover the cached header.
  Detached, unvalidated, and incomplete sidecars retain the defensive parser.
  Fixed-CPU-30 A/B/B/A counters over 200 complete Devanagari `hi-words`
  passes reduced retired instructions by about `1.31%` and branches by about
  `1.58%`; cycles improved by about `0.15%` in the interleaved matrix while
  branch misses rose about `0.25%`. Passing that proved sidecar through the
  executor then removed its second lookup-array access before coverage
  rejection and parsed-subtable dispatch. An incremental A/B/B/A matrix
  reduced instructions by a further `0.27%`, branches by `0.53%`, and cycles
  by about `1.03%`; 11-sample medians improved from an average `951.001` to
  `947.829 ns/glyph`. Output checksums remained identical.
- Cached GSUB feature plans now carry their table-identity proof into the
  unprofiled lookup boundary. The plan already contains validated lookup
  offsets and shares the exact accelerator slice used to build it, so this
  internal path can reject stale or incomplete sidecars once and avoid
  repeating the offset comparison inside every lookup dispatch; public and
  uncached paths retain the defensive identity check. Fixed-CPU-30 A/B/B/A
  counters over 200 complete Devanagari `hi-words` passes reduced retired
  instructions by about `0.08%` and branches by about `0.52%`; branch misses
  fell about `0.74%` while cycles were effectively neutral. The same check's
  11-sample medians averaged `937.007` versus `936.558 ns/glyph`, with
  identical output checksums.
  The internal proof now also hoists the accelerator-slice unwrap outside each
  plan entry and keeps its length/offset/type invariants as debug assertions;
  release shaping therefore reaches the proved sidecar without repeating
  impossible failure branches. Incremental fixed-CPU-30 A/B/B/A counters over
  200 passes reduced instructions by another `0.43%`, branches by `1.31%`, and
  cycles by about `1.98%`; 11-sample medians improved from an average
  `938.641` to `924.755 ns/glyph`.
- Generic GSUB fallback execution now accepts the same cached-plan proof after
  an accelerator intentionally declines an unsupported fast payload. This
  preserves the complete generic semantics while bypassing profiling setup,
  header lookup, validation gates, and an unconditional options copy that the
  validated plan had already discharged. Fixed-CPU-30 A/B/B/A counters over
  200 complete Devanagari `hi-words` passes reduced retired instructions by
  about `2.27%`, branches by `2.82%`, and cycles by about `2.20%`; branch
  misses rose about `0.73%`. The corresponding 11-sample medians improved from
  an average `944.678` to `912.692 ns/glyph`, with identical checksums.
- The accelerated GSUB dispatcher now treats decoded class-based
  ChainContextSubst as a complete fast strategy, alongside its existing
  coverage-only path, instead of deliberately falling through to the generic
  dispatcher and rediscovering the same class sidecars. Fixed-CPU-30 A/B/B/A
  counters over 200 complete Devanagari `hi-words` passes reduced retired
  instructions by about `1.44%`, branches by `0.56%`, and cycles by about
  `1.88%`; branch misses rose about `0.23%`. Eleven-sample medians improved
  from an average `913.812` to `908.221 ns/glyph`, with identical checksums.
- Accelerated cached-plan dispatch now consumes the feature-stage syllable
  scope that was already projected into its options rather than searching the
  whole-table per-lookup override list. Fixed-CPU-30 A/B/B/A counters over 200
  complete Devanagari `hi-words` passes reduced retired instructions by about
  `0.35%`, branches by `1.18%`, branch misses by `0.69%`, and cycles by about
  `0.06%`; 11-sample medians improved from an average `908.267` to
  `906.401 ns/glyph`, with identical checksums.
- The owned shaping pipeline now installs the validated GSUB/GDEF option state
  once before entering cached script stages. Each stage therefore applies its
  plan directly instead of recopying the full options value and reattaching
  the same immutable GDEF slices. Fixed-CPU-30 A/B/B/A counters over 200 full
  Devanagari `hi-words` passes reduced retired instructions by about `1.16%`,
  branches by `0.88%`, branch misses by `0.90%`, and cycles by about `1.45%`;
  11-sample medians improved from an average `906.894` to `896.611 ns/glyph`,
  with identical checksums.
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
- `glyph-bench --mode raster-reuse` now accepts FreeType as well as Cangjie,
  establishing an explicitly symmetric reused-face/reused-target lifecycle.
  This is a colder boundary than the earlier `raster` row: Cangjie reuses its
  decoded outline, target, and rasterizer, while FreeType reuses its face and
  target but still performs `FT_Load_Glyph(FT_LOAD_RENDER)` per iteration. On
  fixed CPU 30 at 64 px, Cangjie/FreeType medians were approximately
  `10,923/1,751 ns` for Roboto `A`, `15,066/1,902 ns` for `g`, and
  `10,589/2,017 ns` for `é`. The larger `5.2--7.9x` gap proves that scan
  conversion itself, not only Cangjie's one-shot outline/setup overhead,
  remains the dominant FreeType-relative deficit. Checksums are stable within
  each engine but intentionally differ because their antialiasing algorithms
  expose different pixel coverage.
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
  and forwards it to Cangjie, HarfRust, and HarfBuzz reference engines. The
  `DFONT.dfont` face-0 row is retained too; the bounded resource-fork decoder
  exposes its `sfnt` resources in QuickDraw order and rebuilds a TTC when more
  than one resource is present.
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
- GPOS mark attachment now snapshots the parent's cross-axis placement when
  each MarkBase/MarkLig/MarkMark lookup applies, while final attachment
  propagation adds only the deferred main-axis placement and intervening
  advances. Cursive parents resolve their complete cross-axis chain at that
  lookup boundary. This matches HarfBuzz 14.3's post-`6b6f0d977` behavior and
  the shared DirectWrite/CoreText result for the affected axis. The three new
  upstream fixtures that specifically exercise this behavior
  `5479969a7d35aabd6a39dcfacb88e36a8f42a7ac.ttf`,
  `d92da3f226c722c1c67353b2391b3472639f03f5.ttf`, and
  `152825a19abd4a3094a41c9e4b4de5e2577dd1df.ttf` are retained against
  HarfBuzz. The Khmer stacked-mark rows `U+1789,U+17D2,U+1789` followed by
  U+17BB/U+17BC/U+17BD are retained in
  `tests/data/khmer-mark-cross-offset-tests.txt`; their final y placement is
  `-274`, not the old deferred-propagation result `-296`. HarfRust 0.12 still
  implements the old behavior, so these three rows are intentionally excluded
  from its otherwise retained Khmer corpus rather than treated as false
  dual-reference failures.
  The remaining Arabic rows from `mark-attachment.tests` are retained against
  current HarfBuzz as well. MarkLig base search now uses exact
  MultipleSubst provenance, so non-first output components remain transparent
  even when an intervening mark breaks source adjacency. If those pieces later
  participate in LigatureSubst, only the first contributes a component, matching
  HarfBuzz's `_hb_glyph_info_get_lig_num_comps_in_ligation` contract. This
  preserves the logical `{0,2,4}` component map for nested Arabic ligatures
  instead of the erroneous `{0,2,2,4}`, and positions surviving marks on the
  correct MarkLig component.
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
  syllable-machine coverage is described in the later retained-evidence entry.
- NotoSansBalinese passes both HarfBuzz and HarfRust for all 43 SHBALI
  rendering-test cases retained in `tests/data/balinese-rendering-tests.txt`,
  covering USE
  category assignment, syllable cluster ownership, split pre-base vowels,
  broken-syllable dotted circles, ligature decomposition, and GPOS output
  (`checksum=c88e4564e3c0bb73`). Canonical decomposition now retains the
  original scalar's cluster owner on every internal component; these are
  shaping sources, not new text clusters. This lets a later ligature merge the
  split U+1B3D components through the preceding Balinese conjunct, matching
  both references on `U+1B13,U+1B44,U+1B13,U+1B3D`.
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
- Tai Tham passes both HarfBuzz and HarfRust for all 209 `SHLANA-1..10` rendering-test
  cases retained in `tests/data/tai-tham-rendering-tests.txt`
  (`checksum=8c8341778b2acfea`). This gate covers Unicode 17 USE categories,
  modified canonical-combining-class reordering (including SAKOT), dynamic
  contextual `SequenceIndex` growth after MultipleSubst, position-major
  chaining-subtable priority, `pref`-classified dotted-circle reordering, and
  ZWNJ-owned Tai Tham stacks.
- The six Unicode text-rendering `SHARAN-1.tests` Urdu/Nastaliq lines are
  retained in `tests/data/sharan-rendering-tests.txt` with `TestShapeAran.ttf`.
  Both references produce 70 glyphs with checksum `2b8749a819fda434`,
  covering joining-form selection and mixed Urdu presentation sequences in an
  RTL run.
- Unicode text-rendering `GSUB-{1,2}.tests` are retained verbatim in
  `tests/data/gsub-{1,2}-*.txt` against both HarfBuzz and HarfRust.
  `TestGSUBOne.otf` covers context-sensitive substitution across a space
  (three glyphs, checksum `187a97943eb156df`). `TestShapeEthi.ttf` covers all
  eleven Ethiopic numeral joining rows, including initial, medial, and final
  substitutions across two- and five-scalar sequences (27 glyphs, checksum
  `413b2570b14af642`).
- Unicode text-rendering `GSUB-3.tests` is retained as a bounded-rejection
  gate for `TestGSUBThree.ttf`. Its expected output is deliberately `*`: nine
  chaining-context lookups recursively expand the middle `o` with a 19-glyph
  MultipleSubst. HarfBuzz terminates with an unsuccessful 20,001-glyph buffer
  after exhausting its shared operation budget, and HarfRust likewise returns
  a bounded 20,001-glyph result. Cangjie now shares operation and glyph-growth
  guards across the entire top-level GSUB application and all nested lookups;
  it reports `ShapingLimitExceeded` in about 20 ms instead of growing an
  in-place ArrayList without bound for minutes. The 503,948-glyph retained
  Duployan corpus remains accepted with checksum `cfff51d05e65e33f`.
- All 19 Unicode text-rendering `GPOS-1.tests` rows are retained in
  `tests/data/gpos-1-rendering-tests.txt` with `TestGPOSOne.ttf`. Both
  references produce 38 glyphs with checksum `153f5283ab978745`. The font's
  GSUB contains a duplicate glyph in a format-3 chaining backtrack Coverage;
  because this Coverage is used only as a membership set, the shaping
  validator now accepts and bounds-checks it like HarfBuzz/fontations while
  continuing to require strict ordering for index-bearing top-level Coverage
  tables and for the detached defensive API.
- All three `GPOS-2.tests` rows are retained in
  `tests/data/gpos-2-rendering-tests.txt` with `TestGPOSTwo.otf`; both
  references produce four glyphs with checksum `5878e11ef99e95de`. Its middle
  PairPos subtable has two PairSets but only one first-glyph Coverage entry.
  PairSet index one is therefore unreachable: the accelerator now stops at the
  end of Coverage like HarfBuzz instead of rejecting the font, while the
  validator continues to reject the unsafe inverse case where Coverage exposes
  an index without a PairSet.
- All four `GPOS-3.tests` rows are retained in
  `tests/data/gpos-3-ethiopic-tests.txt` with `TestShapeEthi.ttf`; both
  references produce seven glyphs with checksum `e72c69483a94e826`.
  U+135D..U+135F are Ethiopic's combining gemination/vowel-length marks
  (General_Category=Mn, GCB=Extend); Cangjie now keeps the complete range in
  the preceding base's grapheme and shaping cluster instead of exposing a
  separate caret/cluster before the positioned mark.
- All four `GPOS-4.tests` mark-stacking rows are retained in
  `tests/data/gpos-4-mark-stacking-tests.txt` with `TestGPOSThree.ttf`; both
  references produce 13 glyphs with checksum `4aed1aa1061c5ac0`. The font has
  an independent valid GPOS table but a ten-byte GSUB header whose ScriptList,
  FeatureList, and LookupList offsets are all null. Cangjie now treats only
  that exact all-null topology as an inert GSUB, including font-level script
  selection and lookup-plan construction, so it can continue to the mark
  positioning table. Partial-null topologies remain malformed because their
  activation and lookup graphs cannot be navigated consistently.
- All five variable-anchor rows from Unicode text-rendering `GPOS-5.tests`
  pass both HarfBuzz and HarfRust with `TestGPOSFour.ttf` at
  `wght=100,300,600,700,900`. The font carries adjacent duplicate `DFLT`
  ScriptRecords; Cangjie now accepts nondecreasing duplicate Script tags while
  preserving first-record selection, validating every child graph, and still
  rejecting decreasing ScriptLists and duplicate LangSys tags. AnchorFormat3
  VariationIndex children now resolve against GDEF 1.3's ItemVariationStore at
  the final F2Dot14-normalized fvar/avar location. The five retained checksums
  are `56299d01d22a7578`, `cf20e51869c39c0a`, `ba96f0ea76f18d3b`,
  `1128dc6c96d5b0a2`, and `cd0b59b81bd63b62`.
- A portable OpenType AOTS audit now passes all 255 supported GSUB/GPOS rows
  against HarfBuzz. Seven focused rows are permanent dual-reference gates:
  PairPos format 1 consumes the
  second glyph only when `ValueFormat2` is present; ContextPos format 1 advances
  to the end of its matched input rather than blindly skipping or overlapping;
  and SingleSubst format 1 can use modulo-16-bit IDs above `maxp.numGlyphs` as
  intermediate lookup states before a later lookup maps them back. The final
  post-GSUB run is still checked against `maxp` before GPOS and metrics. The
  three AlternateSubst rows now use
  `cangjie.shaping.Engine.shape` requests with public UTF-8 byte-scoped
  `FeatureRange` values, including disabled spans, one-based alternate values,
  lookup-flag skipping, and overlapping declarations where the later value
  wins. The request keeps rare range data out of run-wide `Options` while
  avoiding a duplicate shaping method; ranges still participate in the
  appropriate cache identity. Ranges gate only lookup candidates;
  contextual lookups still see the complete surrounding glyph stream,
  matching HarfBuzz feature masks.
- All twelve Unicode text-rendering `HVAR-{1,2}.tests` rows pass both
  references at `wght=0,200,400,600,800,1000`. `TestHVAROne.otf` exercises
  mapped CFF advance-width deltas across `ABC`; its six checksums are
  `1cde33aa79622f01`, `ff0da980cf4cb6bd`, `843e1f581a14c246`,
  `fbb94c9b0d2e01ca`, `8514cd3f14ac775e`, and `5fc7d4cc3e11cecb`.
  `TestHVARTwo.ttf` exercises the TrueType metric path across `AB`; its
  checksums are `c9e49495a6e43c93`, `6e5b88b1079710a0`,
  `c354056763582773`, `a8fac55de53e66bf`, `73f5831a42821915`, and
  `53efa1cbd254571d`.
- All six Unicode text-rendering `CVAR-{1,2}.tests` shaping rows pass both
  references with `wdth=100,opsz=72` at `wght=28,94,194`.
  `TestCVARGVARTwo.ttf` and `TestCVARGVAROne.ttf` each produce nine total
  glyphs with per-instance checksums `5958eeac8791dab8`,
  `bf8e3d31743b442b`, and `f19e521d929b2871`. This gate proves that fonts
  carrying these cvar topologies load under the three-axis design-coordinate
  contract and that their gvar-derived advances match. It does not claim
  pixel-grid hinting parity: CVT deltas become observable only when a TrueType
  interpreter executes instructions at a specific PPEM.
- All 27 Unicode text-rendering `GVAR-{1,2,3}.tests` instances now retain
  HarfBuzz glyph-extents parity, in addition to HarfBuzz/HarfRust shaping
  parity, for `TestGVAR{One,Two,Three}.ttf` at
  `wght=300,350,400,450,500,550,600,650,700`. This stronger gate exposed that
  the generic `glyphBoundsAtCoords` API returned static glyf-header bounds even
  though the outline and advance paths applied gvar. Non-default TrueType
  bounds now derive from the varied outline, and point/component/phantom
  half-unit ties use OpenType's round-toward-positive-infinity rule. HarfRust's
  current CLI reports zero outline extents for these rows, so it remains the
  second shaping reference while HarfBuzz is the geometry reference.
- The remaining 56 Unicode text-rendering `GVAR-{4..9}.tests` instances are
  retained under the same HarfBuzz-extents/HarfRust-shaping split, completing
  all 83 `GVAR-1..9` rows. The matrix covers Zycon's short padded `M1  `,
  `T1  `, and `HV  ` axis tags, two-axis locations, negative coordinates,
  sparse tuple point sets, and fractional design locations including
  `T1=0.1` and `TEST=0.944444`. It exposed three compatibility boundaries:
  simple-glyph IUP must run independently per TupleVariation before tuple
  deltas accumulate; HarfBuzz quantizes design locations through 16.16 before
  F2Dot14; and zero-pair legacy `kern` format 0 commonly carries the
  FontTools-style `searchRange=6, rangeShift=0` descriptor. The
  `TestGVAREight.ttf` fixture also has a stale optional fvar named-instance
  label; shaping and axis APIs now remain usable while `variationInstances()`
  continues to reject unresolved instance metadata.
- Legacy kern format 0 now treats `searchRange`, `entrySelector`, and
  `rangeShift` as non-authoritative acceleration hints, matching HarfBuzz and
  FreeType. It also recovers a wrapped UInt16 subtable length when the final
  subtable's authoritative pair count fits exactly inside the SFNT `kern`
  record. A 10,921-pair synthetic regression protects that unambiguous
  recovery while sorted pairs, glyph bounds, table ownership, and checksums
  remain strict. This admits the deployed PT Sans Caption fuzz fixture whose
  22,076-pair table previously failed before shaping.
- All 17 Unicode text-rendering `AVAR-1.tests` design locations from
  `TEST=100` through `TEST=900` are retained with HarfBuzz glyph-extents and
  HarfRust shaping parity for `TestAVAR.ttf`. The complete sampling protects
  the font's piecewise avar plateau (`-0.5→0`, `0.5→0`) rather than checking
  only the minimum/default/maximum instances.
- All nine Unicode text-rendering `CFF2-1.tests` weights pass HarfBuzz
  glyph-extents and HarfRust shaping parity for
  `AdobeVFPrototype-Subset.otf`; `wght=800/900` also cover the
  `dollar.nostroke` FeatureVariation result. The real font's variable hint
  arrays require CFF2's 513-entry DICT operand limit rather than the previous
  48-entry scratch, and fractional CFF2 glyph bounds now use OpenType nearest
  rounding instead of an outward floor/ceil box.
- All 28 Unicode text-rendering `CFF-{1,2,3}.tests` rows are retained with
  HarfBuzz glyph-extents and HarfRust shaping parity.
  `FDArrayTest257.otf` and `FDArrayTest65535.otf` exercise CID-keyed CFF
  FDArray selection through FDSelect formats 0 and 3, including per-FD Private
  DICT widths and Local Subrs. `TestCFFThree.otf` covers Type2 `endchar` seac
  composites: StandardEncoding base/accent codes are resolved through custom
  charset format 0 before the component outlines are positioned.
  Making traditional CFF bounds observable also exposed an accidental coupling
  in fallback mark positioning: Thai and Lao now honor HarfBuzz's
  script-level `fallback_position=false` policy instead of enabling geometric
  fallback merely because a CFF outline has valid extents.
- The Unicode text-rendering `GLYF-1.tests` `gcommaabove` row is retained with
  HarfBuzz glyph-extents and HarfRust shaping parity for `TestGLYFOne.ttf`,
  covering compound-glyph point-matched accent placement.
- All four Unicode text-rendering `SFNT-{1,2}.tests` rows are retained with
  HarfBuzz glyph-extents and HarfRust shaping parity. The two fixtures carry
  both CFF and glyf/loca under opposite sfnt flavors; Cangjie now follows the
  internally complete maxp-backed outline stack (`maxp` 1.0 for glyf, 0.5 for
  CFF) rather than treating the scaler flavor as the sole authority.
- Both Unicode text-rendering `KERN-{1,2}.tests` rows are retained in
  `tests/data/kern-rendering-tests.txt` with `TestKERNOne.otf`. Cangjie,
  HarfBuzz, and HarfRust produce 17 glyphs with checksum
  `8442fd65909b069d`, covering the fixture's contextual legacy kerning
  sequence rather than only one isolated pair.
- Unicode text-rendering `CMAP-{1,2,4}.tests` are retained verbatim in
  `tests/data/cmap-{1,2,4}-*.txt` against both references. CMAP-1 and CMAP-2
  cover cmap format-14 default, non-default, and unsupported variation
  sequences (`9d1accb7e5354dae` and `c5c191aec5b5eb3b`); CMAP-4 covers
  format-13 last-resort mappings across the BMP and supplementary planes
  (`af8ccf90ffd477d1`). These gates use the upstream
  `--remove-default-ignorables` mode, now propagated consistently through the
  Cangjie, HarfBuzz, and HarfRust runners and included in shaped-run cache
  identity.
- The upstream `CMAP-3.tests` file remains disabled in HarfBuzz itself because
  it is a non-Unicode Macintosh Turkish cmap. Cangjie now interprets
  platform-1/encoding-0 cmap codes through an extracted Macintosh Roman
  encoding layer and honors the format-0 language value 18 as the Turkish
  variant. Current HarfBuzz and HarfRust do not honor the Turkish language
  variant consistently, so this non-Unicode cmap is not a valid differential
  oracle. The complete 20-row upstream input remains protected by a Cangjie
  expected-output gate at checksum `9038f53721f4d38`, including the six
  Turkish-specific byte slots.
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
  `5dc56e2fc3a8a313`) and are part of `shaping-use-parity-smoke`. This
  multi-script gate covers font-dependent Indic
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

- The public UTF-8 ranged-GSUB path now accepts variation selectors instead of
  rejecting the complete request. Supported cmap format-14 sequences fold into
  the base glyph while preserving the base cluster and full byte extent;
  unsupported selectors remain GSUB-visible default-ignorables, follow the
  requested grapheme/character cluster level, and are hidden, replaced by the
  invisible glyph, or exposed through the not-found-selector diagnostic option
  after shaping. A focused combined cmap14+GSUB fixture covers all three output
  policies. Two production-font `f+FE00+i` ranged-feature probes also pass
  in-process HarfBuzz parity: disabling `liga` on the base range retains three
  glyphs (`80e2ac1352e1d7ea`), while disabling it only on the selector bytes
  leaves the base-owned `fi` ligature and yields two glyphs
  (`534f2ad3a98b676f`). Staged Arabic/Indic/Khmer/Myanmar ranged features remain
  a separate open item because their authored feature pauses require integration
  into the main shaper rather than replaying a generic post-pass.
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
  Arabic joining context are retained against both references. `shape-bench`
  now accepts `--text-before`/`--text-after`; Cangjie uses those contexts only
  to resolve item-boundary Arabic joining forms while keeping GSUB/GPOS matching
  scoped to the shaped item. Its in-process HarfBuzz runner now follows
  `hb-shape` and installs pre-context, item text, and post-context with three
  buffer-add calls. Context affects joining without shifting the shaped item's
  public UTF-8 clusters to paragraph-relative offsets. The `--bot`
  dotted-circle rows are retained too;
  beginning-of-text Arabic marks insert a synthetic dotted-circle base unless a
  pre-context is supplied.
- Mongolian Free Variation Selectors now participate in the Arabic-style
  joining shaper under the `mong` ScriptList. The focused
  `arabic-feature-order.tests` FVS rows for
  `813c2f8e5512187fd982417a7fb4286728e6f4a8.ttf` and
  `8a9fea2a7384f2116e5b84a9b31f83be7850ce21.ttf` are retained. All 19 upstream
  `mongolian-variation-selector.tests` rows are now retained against HarfBuzz,
  covering four production fixtures, positional FVS forms, NIRUGU,
  ZWJ/ZWNJ, and MVS. The
  `a34a7b00f22ffb5fd7eef6933b81c7e71bc2cdfb.ttf` fixture is accepted despite
  a zero-length custom `post` format-2 glyph name: parsing and metrics require
  structural safety, while the public glyph-name accessor continues to reject
  invalid non-empty text and reports an empty custom name as absent. Its
  NIRUGU row now matches because the compact Unicode joining table includes
  the complete Mongolian exceptions from `DerivedJoiningType.txt`, and because
  Mongolian FVS remains non-skippable during GSUB—even with glyph zero—before
  an untouched selector is hidden from final output. Broader coverage also
  reaches `4d4206e30b2dbf1c1ef492a8eae1c9e7829ebad8.ttf` after `gasp` parsing was
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
  rows are retained: Cangjie runs the AAT `morx` ligature state machine that
  forms `A_E_D` across intervening glyphs while preserving HarfBuzz-style
  clusters, and it tolerates the stale static SFNT search/header checksum
  metadata needed by the Tamil `morx` fixture while keeping public lazy table
  APIs strict. AAT Indic rearrangement (`morx` type 0) is now covered by every
  one of the 61 upstream `text-rendering-tests/MORX-{2,3,4,8,9,10,11,12,13,14,16,17}`
  rows across 12 fonts. The retained corpora live under
  `tests/data/aat/morx-rearrangement/` and run against both HarfBuzz and
  HarfRust through `shaping-aat-parity-smoke`; their aggregate per-font
  checksums are:

  | Font | Rows | Checksum |
  | --- | ---: | ---: |
  | `TestMORXTwo` | 16 | `1e2842ace57db2eb` |
  | `TestMORXThree` | 16 | `a7050f4349495469` |
  | `TestMORXFour` | 15 | `3abd150741e44bb1` |
  | `TestMORXEight` | 3 | `14b90ee97e2f5ced` |
  | `TestMORXNine` | 1 | `4bb4c1172c636cff` |
  | `TestMORXTen` | 1 | `580235edc2bd6ec1` |
  | `TestMORXEleven` | 1 | `ffafc3f2446fb103` |
  | `TestMORXTwelve` | 3 | `338aa5e8b5af1f7b` |
  | `TestMORXThirteen` | 1 | `c002b2bbca134649` |
  | `TestMORXFourteen` | 2 | `1cf260dbb8e90b47` |
  | `TestMORXSixteen` | 1 | `c002b2bbca134649` |
  | `TestMORXSeventeen` | 1 | `7fa25edf22ddbdc5` |

  AAT contextual substitution (`morx` type 1) is also retained for all 41
  deterministic upstream `MORX-{18,20,21,22,23,25,26,37,38,39,40}` rows across
  11 fonts. The `tests/data/aat/morx-contextual/` gate covers substitutions of
  marked and current glyphs, end-of-text actions, format 6/8 class lookups,
  format 6/8 action lookups, and all four logical/layout × forward/backward
  coverage combinations. Format 0/2/4 action lookups are implemented and
  covered by focused parser tests rather than these upstream fonts. The per-corpus
  checksums are:

  | Corpus | Rows | Direction | Checksum |
  | --- | ---: | --- | ---: |
  | `TestMORXEighteen` | 4 | LTR | `6b13eeaa2f26a86a` |
  | `TestMORXTwenty` | 7 | LTR | `b5138b59a375ec43` |
  | `TestMORXTwentyone` | 1 | LTR | `367a89a8504c67a6` |
  | `TestMORXTwentytwo` | 1 | LTR | `a20889bbdccb1687` |
  | `TestMORXTwentythree` | 1 | LTR | `da8555bc3bd8f32c` |
  | `TestMORXTwentyfive` | 9 | LTR | `88e69563ca600d19` |
  | `TestMORXTwentysix` | 2 | LTR | `d24186dc270eab53` |
  | `TestMORXThirtyseven` | 2 / 2 | LTR / RTL | `eaf47d933f9227b2` / `9a0528269af6a35a` |
  | `TestMORXThirtyeight` | 2 / 2 | LTR / RTL | `eaf47d933f9227b2` / `44a216133a7658b3` |
  | `TestMORXThirtynine` | 2 / 2 | LTR / RTL | `3d87acc2b7fb875` / `44a216133a7658b3` |
  | `TestMORXForty` | 2 / 2 | LTR / RTL | `3d87acc2b7fb875` / `9a0528269af6a35a` |

  The remaining upstream `MORX-24` row uses `*` rather than an expected
  output: its state table deliberately takes an infinite `DontAdvance` cycle.
  Cangjie rejects that malformed machine under the same bounded operation
  policy used for rearrangement, and retains the topology as a unit regression
  instead of exposing a hang or pretending it has deterministic parity.

  AAT contextual insertion (`morx` type 5) passes all 21 deterministic rows
  from upstream `MORX-{29,31,32,33,35}` against both references. The retained
  `tests/data/aat/morx-insertion/` corpora cover marked/current insertion,
  insertion before and after the template glyph, multi-glyph insertion lists,
  and `DontAdvance` transitions that feed newly inserted glyphs back through
  the machine:

  | Font | Rows | Checksum |
  | --- | ---: | ---: |
  | `TestMORXTwentynine` | 4 | `ad27f263e2f75e18` |
  | `TestMORXThirtyone` | 8 | `1e13a86e0e9ed11d` |
  | `TestMORXThirtytwo` | 4 | `e6860ff3b023a55d` |
  | `TestMORXThirtythree` | 3 | `378c9e777b2158df` |
  | `TestMORXThirtyfive` | 2 | `24643782f5f0287a` |

  The `MORX-34` and `MORX-36` stress rows also use `*`: they intentionally
  expand indefinitely, including across eleven consecutive insertion
  subtables. Cangjie shares one HarfBuzz-compatible operation budget across the
  complete `morx` application, so both fail deterministically instead of
  hanging or allocating without bound. The same fixtures exposed valid
  non-four-byte chain lengths; validation now follows the declared packed
  chain size instead of imposing an alignment rule absent from AAT and the
  reference parsers.

  The implementation keeps glyph ids, source ownership, cluster ownership,
  substitution flags, and ligature provenance in lockstep for all 15 AAT
  rearrangement verbs, bounds rearranged spans to HarfBuzz's 64-glyph context
  limit, and rejects non-terminating malformed state cycles under a
  HarfBuzz-compatible operation budget. All eight
  `aat-trak.tests` rows are retained for `TRAK.ttf`; Cangjie applies AAT
  noncontextual `morx` alternates and interpolates horizontal `trak` advances
  for the requested point size. The retained upstream MORX matrix now covers
  all 166 deterministic rows from `MORX-1..41` against both HarfBuzz and
  HarfRust, not only one sample per subtable kind. The final 44 previously
  ungated rows are grouped by font under `tests/data/aat/morx-complete/`:

  | Font | Additional rows | Checksum |
  | --- | ---: | ---: |
  | `TestMORXOne` | 1 | `5f518e0f6eb70fea` |
  | `TestMORXTwo` | 2 | `76be31541670cbf9` |
  | `TestMORXFour` | 25 | `a9e1174e95b66144` |
  | `TestMORXEighteen` | 2 | `154a67efee1f3287` |
  | `TestMORXTwentyseven` | 3 | `5b7aeceae7187a16` |
  | `TestMORXTwentyeight` | 5 | `4d7edf40aece359e` |
  | `TestMORXTwentynine` | 4 | `4393caf7918f470d` |
  | `TestMORXFourtyone` | 2 | `44bacca4c5faa8a4` |

  This audit also found that a live contextual action uses glyph zero as its
  default marked location before the first explicit `SetMark`; only an
  unmarked end-of-text transition suppresses actions. The two `MORX-19` rows
  retain that distinction. The matrix exercises every supported AAT subtable
  kind (types 0, 1, 2, 4, and 5); broader production-font and malformed-table
  fuzzing remains open.

  A scan of 6,866 local fonts found one deployed legacy `mort` face,
  KaTeX's tracked Honoka Mincho
  `test/screenshotter/fonts/mincho/font_1_honokamin.ttf`
  (SHA-256 `42b090e87f111c48af3d47c167d8b7f1d1d876dda97790d784ba5824bc56739a`).
  Its vertical noncontextual `mort` table and GSUB `vert` feature encode the
  same 599 vertical glyph mappings. HarfBuzz prefers GSUB when the vertical
  font has both tables; Cangjie was missing HarfBuzz's `F_GLOBAL_SEARCH`
  behavior and therefore failed to find `vert` because Common characters have
  no active `kana` LangSys. GSUB now selects the first global `vert`
  FeatureRecord only when the active LangSys lacks one, while `vert=0` remains
  authoritative. All 598 mappings with Unicode cmap sources pass both
  references in `tests/data/vertical/honokamin-mort-mapped.txt`
  (`checksum=3b1a3ef90515923d`). The parity runner can now hide GSUB from both
  engines without rewriting table payloads; all 598 rows still pass HarfBuzz
  through Cangjie's standalone legacy `mort` type-4 noncontextual executor.
  A synthetic format-8 lookup fixture separately proves glyph/substitution
  metadata updates. Legacy type-0 Indic rearrangement now runs the obsolete
  byte-indexed state table while reusing the 15 verified rearrangement verbs
  and glyph-parallel metadata movement; a synthetic `AB` fixture matches
  HarfBuzz. Type-1 contextual substitution now supports obsolete byte-indexed
  states plus signed word offsets from the state-subtable base, with a second
  `AB` fixture retaining substitution metadata and matching HarfBuzz. HarfRust
  currently has no `mort` table parser, so retained
  automated reference coverage for these paths is HarfBuzz. Stateful legacy
  type-5 insertion now executes obsolete byte-indexed states while keeping the
  insertion table's distinct addressing rules: the header carries a
  state-subtable-relative byte offset, but each action is a zero-based glyph
  index and `0xFFFF` is the no-action sentinel. A synthetic `A` fixture inserts
  glyph 2 after glyph 1, clones source/substitution metadata, and matches
  HarfBuzz. Type-2 ligatures now share the proven `morx` out-buffer and
  metadata executor while retaining the obsolete format's three distinct
  address conversions: entry action byte offsets, component word offsets, and
  ligature byte offsets. A synthetic `AB` fixture forms glyph 3, merges its
  cluster and ligature provenance, and matches HarfBuzz. Legacy `mort` now
  executes every defined subtable type (0, 1, 2, 4, and 5); production-font
  expansion and malformed-table fuzzing remain broader AAT work.

  AAT `kerx` formats 0, 1, 2, 4, and 6 now participate in actual shaping rather
  than metadata inspection only. The retained format-0/2/6 synthetic fonts
  encode `(glyph 1, glyph 1) = -30` through sorted pairs, a class matrix, and a
  sparse row/column matrix respectively; at 1000 units, `"AA"` produces
  advances `785,785` and second-glyph offset `-15`. The format-1 fixture uses
  an extended AAT state machine to push the first glyph and consume a
  sentinel-terminated action list, producing advances `770,800` and first
  offset `-30`. Format 4's explicit-coordinate fixture marks the first glyph,
  attaches the second, and produces offsets `-830,25` after attachment
  propagation. A second format-4 fixture resolves both attachment points
  through `ankr` without allocating its public metadata representation and
  produces offset `-800,0`. All retained paths match HarfBuzz and HarfRust and
  carry a conflicting
  legacy `kern` pair to prove that `kerx` suppresses double-kerning. `kern=0`
  restores `800,800` for kerning-requested formats; format 4 remains active
  because attachment positioning is not controlled by the `kern` feature.
  Format 6 supports both 16-bit and 32-bit scalar matrices, while the shared
  AAT lookup reader handles typed `u16`/`u32` values and format 10. Matrix
  indexes and state-machine bounds are validated against maxp before shaping.
  Simple cross-stream positioning is retained for formats 0, 2, and 6 on both
  axes against HarfBuzz and HarfRust. Horizontal `"AAA"` keeps advances
  `800,800,800` and cursively accumulates y offsets `0,-30,-60`. Vertical
  fixtures carry an inert GPOS `vkrn` feature so an explicit `vkrn=1` receives
  the same feature mask in both references; they keep three `-1000` advances
  and report HarfBuzz-space x offsets `-400,-430,-460`. The benchmark's
  vertical x-offset normalization now preserves runtime positioning deltas
  instead of replacing the complete result with the synthesized origin.
  Stateful format-1 cross-stream actions are retained on both axes as well:
  they add to the preinstalled cursive chain, honor the undocumented
  `-0x8000` attachment/reset action, and remain ordered relative to simple
  format-0/2/6 assignments rather than being applied in a separate pass.
  Format-4 outline-control-point actions now resolve raw TrueType point indexes
  through the same simple/compound/gvar-aware loader used for outline point
  matching. A synthetic `"AA"` fixture attaches marked point 1 `(350,700)` to
  current point 0 `(0,0)` and reports final x offsets `0,-450` after
  mark-attachment propagation. Its HarfBuzz gate explicitly enables FreeType
  font funcs because HarfBuzz's native OT backend deliberately omits the
  contour-point callback; an independent expected-output gate prevents a
  missing callback in both engines from producing false parity.
  Selection follows
  HarfBuzz's table plan: when GSUB and GPOS are both active, GPOS owns
  positioning even if the selected LangSys's applicable feature is not named
  `kern`; otherwise `kerx` takes precedence over legacy `kern`.
  Version-4 variation vectors now use their first FUnit as the default and
  accumulate subsequent deltas with scalars derived from `gvar` global tuple
  peaks, reusing the same normalized-coordinate support math as glyph
  variation tuples. Formats 0, 1, 2, and 6 share this resolver; focused tests
  cover each format, the standalone `0xFFFF` format-1 sentinel, unsigned
  16/32-bit vector offsets, and version-3/4 glyph-coverage footers. A synthetic
  format-0 vector `[-30,-20]` retains HarfBuzz parity at the default coordinate
  and produces `-40` at normalized coordinate `0.5`, with an independent
  expected-output gate because current HarfBuzz returns only the vector's first
  member for non-default coordinates.

  The public `font.Glyphs.extents`/`extentsAt` and reusable-session extents
  surface now expose the same bearing/width/negative-height convention used by
  HarfBuzz, rather than leaving that conversion private to the benchmark.
  `shape-bench --show-extents` consumes this public boundary. The
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
  or random metadata. Explicit script shapers now retain that same random bit
  in direct, cached, and lookup-order-merged feature plans. In particular, the
  upstream LTR Arabic `ligature-id.tests` row for
  `8339c821814d9bad7c77169332327ad8b0f33c81.ttf` is retained against both
  HarfBuzz and HarfRust: the common `rand` feature runs in the early Arabic
  stage and advances one shared PRNG state before joining forms and ligatures.
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
  default and the upstream design coordinate `wght=700`; exact duplicate
  HVAR/VVAR DeltaSetIndexMap payloads are accepted, and the parity tool reports
  variation-aware horizontal origins plus HarfBuzz-style VORG y origins. The
  glyf+vmtx `NotoSansCJK-VF.abc.ttf` rows for the same text and variation
  settings are retained too; when VORG is absent, Cangjie derives the HarfBuzz
  vertical origin from glyf bounds plus vmtx top side bearing. With no VVAR,
  gvar pp3/pp4 phantom deltas now update vertical origin/advance metrics just as
  pp1/pp2 already update horizontal metrics.
  The no-vmtx `vertical.tests` U+300C row for
  `191826b9643e3f124d865d617ae609db6a2ce203.ttf` is retained against both
  references as well. After `vert` selects `uni300C.vert`, Cangjie now centers
  its glyph extents inside the horizontal ascender/descender box, producing
  origin `(-512,578)` and advance `-1024` instead of using half the line height
  as the y origin. The Font-level origin API is shared by layout output and the
  parity runner so renderers receive the same complete vertical translation.
  Public positioned glyphs now store the actual HarfBuzz-style negative
  origin offsets, including HVAR/VVAR/gvar variation and odd horizontal
  advances; the parity runner reads those fields directly and retains only its
  explicit synthetic bold/slant adjustment.
  Positioned output now also retains the resolved per-glyph orientation:
  explicit upright/sideways policy applies uniformly, while CSS mixed mode
  keeps U/Tu/Tr upright and marks only UAX #50 R glyphs sideways. CPU
  grayscale, color, and TrueType-hinted run renderers rotate those glyphs
  clockwise around the shaping origin without changing advances.
  Paragraph layout now exposes that same output through vertical greedy
  wrapping. Global, UTF-8 ranged, and attributed `word-break` /
  `overflow-wrap` / wrap-mode policy tailors safe UAX #14 boundaries before
  any requested grapheme-safe emergency breaks. Boundaries belong to the
  preceding source scalar, and ranged no-wrap spans defer rather than globally
  disable later wrapping. `vertical_rl` and `vertical_lr` select right-to-left
  or left-to-right block progression independently from TTB/BTT inline
  direction. Physical column bounds, y-axis hit testing, horizontal
  caret/selection bars, owned TextGeometry, debug overlays, retained reflow,
  renderer draw-list y pens, and source-preserving `preserve` / `collapse` /
  `break-spaces` whitespace policy are covered together. Flow-axis first-line
  indentation and hard-segment paragraph spacing map to vertical y and x
  geometry respectively, including RL/LR mirroring. Explicit and repeating tab
  rulers support start/center/end/decimal y-axis fields. In-flow U+FFFC objects
  map physical height to vertical inline advance and width to centered column
  block extent across wrapping, interaction, retained/styled layout, and draw
  output. Vertical start/center/end alignment maps to top/center/bottom inside
  the post-indent inline region, while active tab-ruler columns remain pinned
  to start. Source-order `max-lines` truncation synchronizes column, glyph/run,
  object, and styled metadata prefixes before physical RL/LR placement.
  Optional ellipsis resolves three periods through the terminal source style's
  cascade, size, and variation instance, then lays them out along positive-down
  y. It uses vertical metrics/origins for upright output and horizontal advance
  for sideways output. Fitting repairs aligned tab fields, column alignment,
  run ownership, object-derived block width, styled metadata, and retained
  restoration; a trailing hard break's omitted empty column still triggers the
  tail, while a zero-column limit remains empty.
  Signed paragraph and attributed letter/word spacing also maps to vertical y:
  negative values are exact while every resulting source advance stays
  nonnegative, and an over-compressed request fails explicitly instead of
  producing reverse wrap/caret topology. Plain, intrinsic, retained, styled,
  tab-ruler, interaction, TextGeometry, and renderer output share that proof.
  UAX #9 source bidi now resolves once per paragraph and applies L1/L2 inside
  each final column along positive-down y, including strong R/AL text,
  embeddings/overrides, isolates, mirroring, hard/soft columns, fallback runs,
  fontless tabs/objects, ellipsis, retained reflow, styled metadata,
  interaction geometry, and renderer output. Explicit `direction=rtl` still
  means unsupported bottom-to-top inline progression; RL/LR remains block-axis
  column order.
  Greedy and balanced line-break strategies now both operate on vertical
  source-order columns. The balanced path preserves greedy's per-hard-segment
  column count, then performs bounded squared-slack optimization over the same
  UAX/dictionary/ranged/emergency and unsafe-to-break boundary graph. Optional
  Thai/Lao/Khmer/Myanmar dictionaries feed one-shot, retained, styled,
  intrinsic, and balanced vertical layout through the shared width-independent
  analysis. Positive-down tab fields, signed spacing, hard segments, bidi,
  retained/styled output, max-lines, and ellipsis are retained; an incomplete
  or complexity-limited search falls back transactionally to greedy columns.
  Explicit U+00AD opportunities now use the same vertical boundary graph and
  materialize a source-owning U+2010/U+002D/U+00AD fallback with the owning
  run's orientation, variable-font instance, vertical origin, and inline
  advance. Both retained invisible outputs and shaper-omitted
  default-ignorables are covered; greedy/balanced fitting, aligned tabs,
  intrinsic sizing, retained/styled metadata, bidi, interaction, renderer
  output, custom hyphen characters, and ellipsis share that result.
  Liang-pattern automatic boundaries now share the same vertical resolver and
  source-neutral insertion transaction. Greedy and balanced column selection
  enforce consecutive-hyphen limits, balanced DP retains horizontal-compatible
  hyphen penalties, and `break-all`, unsafe shaped boundaries, missing custom
  glyphs, retained/styled metadata, intrinsic sizing, bidi, and ellipsis are
  covered directly.
  Generic `TextAlign.justify` now expands UAX #14 spaces or conservative CJK
  source boundaries along positive-down y. Only non-terminal soft columns
  receive a target; hard/terminal/truncated/ellipsized/tab-ruler/unbounded
  columns retain natural size. Greedy and balanced selection, retained/styled
  restoration, bidi, interaction/TextGeometry, renderer pens, punctuation
  processing, and RL/LR placement consume the same expanded advances.
  Caller-selected `line_regions` now map x to the vertical block origin and
  y/width to positive-down inline origin/height. Greedy and balanced wrapping
  use each region's measure, explicit regions bypass first-column indentation,
  RL/LR placement honors supplied x, and retained resolver replay, styled
  metadata, TextGeometry, renderer pens, alignment, justification, optical
  punctuation, and ellipsis consume the retained region geometry.
  Static and out-of-flow-resolver exclusions now support both vertical block
  progressions. Physical
  x-band overlap produces unavailable positive-down y intervals; each column
  selects the widest remaining fragment, while a fully blocked band advances
  to the nearest rectangle edge in block progression without manufacturing
  source output.
  Indentation, explicit-region precedence, retained/styled restoration,
  TextGeometry, and renderer origins are covered. Fully blocked vertical-rl
  bands advance left, and the resolved local coordinates translate into the
  same terminal-at-zero convention as ordinary RL columns.
  `ShapedParagraph.breakLines` now commits one vertical column per caller
  advance. Per-column regions and max-height retry the same source boundary
  transactionally, partial layouts expose only committed columns, checkpoints
  restore cursor/regions/glyph mutations, and final bidi, optical punctuation,
  run pens, and inline objects execute once through retained presentation.
  Line-end East Asian punctuation can now hang along the positive-down inline
  axis. Greedy/emergency/balanced fitting use occupied height; final
  column-local bidi assigns bottom-edge `hang_end`, then top/center/bottom
  alignment, paragraph metrics, retained/styled layout, tabs, interaction,
  renderer output, and ellipsis consume the same unchanged glyph advances.
  CLREQ/JIS/GB/CNS punctuation compression now shares the inline-axis capacity
  model with horizontal lines. Greedy/emergency/balanced fitting and intrinsic
  sizing operate on effective occupied height, final logical-order mutation
  updates y advance/offset before column-local bidi, and retained/styled
  reflow, interaction geometry, renderer output, hanging, tabs, and ellipsis
  consume the same result. Compression is transactional for indivisible
  overfull fragments whose capacity cannot fit the requested measure.
  Ordinary out-of-flow source-anchor fallbacks remain zero-occupancy while
  retaining paint output. Custom out-of-flow markers now accept absolute
  presentation-only geometry directly and through placement-only concrete
  resolver replay; retained/styled layout, intrinsic sizing, draw output, and
  line-limit visibility keep those bounds outside flow metrics. Bottom-to-top
  inline progression and physical left/right alignment are rejected explicitly
  until they are migrated to the shared
  inline/block-axis model; this is not yet full vertical paragraph parity.
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
  is retained in its upstream LTR direction as a dual-reference gate as well.
  The Bengali `indic-syllable.tests`
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
  remaining Tamil `indic-syllable.tests` row for
  `65d1b9099cfb3191931d8d6112d7a03d979d579f.ttf` is retained against both
  references as well: the out-of-script superscript-two control remains a
  separate cluster before U+0B95 instead of being absorbed into the following
  Tamil syllable. Together these gates now represent all 15 deterministic rows
  in the upstream `indic-syllable.tests` file. The
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
  `indic-joiners.tests` rows for
  `8116e5d8fedfbec74e45dc350d2416d810bed8c4.ttf` are retained as one
  four-row dual-reference corpus in
  `tests/data/devanagari-indic-joiners-tests.txt`, covering both single
  `virama+ZWJ/ZWNJ` cases and the corresponding three-stack pure/mixed joiner
  sequences;
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
  All 81 Unicode text-rendering Kannada rows are retained: the 34
  `SHKNDA-1.tests` rows use `tests/data/kannada-shknda-1-tests.txt` with
  `NotoSerifKannada-Regular.ttf`, while the 16 `SHKNDA-2.tests` and 31
  `SHKNDA-3.tests` rows use the corresponding `tests/data/kannada-shknda-*.txt`
  corpora with `NotoSansKannada-Regular.ttf`; its one trailing-U+0020 row is an
  explicit inline gate rather than invisible corpus whitespace. Kannada's initial Indic reorder now moves
  `BEFORE_SUB` vowels, including U+0CBE and U+0CBF, ahead of the complete run
  of post-base `virama+consonant` pairs before `blwf`; it marks those virama
  sources for post-base below forms and merges dependent marks into their
  syllable clusters. U+0CBF is no longer misclassified as a `PRE_M` matra, so
  standalone base+I remains in font-authored `abvs` order. All three corpora
  pass both HarfBuzz and HarfRust: SHKNDA-1 produces 49 glyphs with checksum
  `d5ebe4b7cb61f5ce`, SHKNDA-2 produces 65 glyphs with checksum
  `58fc74916d67eaf8`. The 30-line SHKNDA-3 corpus produces 119 glyphs with
  checksum `51492f0ab2f4e4aa`, and its trailing-space row produces 5 glyphs
  with checksum `5ab0baf139783438`.
- Add a focused Khmer shaper for the `khmr` script tag. The 86
  `khmer-misc.tests` rows for
  `3998336402905b8be8301ef7f47cf7e050cbb1bd.ttf` are retained as
  `tests/data/khmer-misc-tests.txt`; Cangjie now applies Khmer split-matra
  decomposition for `U+17BE/U+17BF/U+17C0/U+17C4/U+17C5`, marks Khmer
  syllable-scoped `pref/blwf/abvf/pstf/cfar` sources, reorders pre-base vowels
  and `COENG+RO` sequences before the base in HarfBuzz stage order, and runs
  the Khmer `pres/abvs/blws/psts/clig` final stage against HarfRust parity.
  The remaining three rows for the same font use the newer cross-axis mark
  attachment contract described above and are retained separately against
  current HarfBuzz.
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
- Expand Myanmar parity beyond the current focused `mym2` fonts and in-house
  rows. The Unicode 17 maximal-munch syllable grammar, kinzi, broken-cluster
  dotted circles, explicit FE00 handling, and the legacy `mymr` default-shaper
  selection now have retained coverage. Broader production-font coverage now
  includes installed Noto Sans Myanmar UI and Noto Serif Myanmar, and retained
  upstream corpora cover Myanmar, Shan, and extension-block sequences, but
  more independent font families and malformed-table/corpus discoveries remain
  before claiming broad Myanmar parity. The in-house
  `myanmar-zawgyi.tests` `Qaag` row passes by
  treating Myanmar Zawgyi as HarfBuzz does: a script tag with auto shaping,
  normalization, zero-width-mark handling, and fallback positioning disabled.
  Noto Serif Myanmar now parses its production GPOS ChainContextPos format-2
  lookup with a null optional lookahead ClassDef; absent backtrack/lookahead
  ClassDefs correctly mean class zero, while InputClassDef remains required. A
  mixed 109-glyph Myanmar, Shan, Tai Laing, and extension-block probe passes
  both HarfBuzz and HarfRust with checksum `17c9e1cfabec5341`. The installed
  production-font smoke test retains parsing and shaping of ordinary Myanmar
  text; a focused synthetic test protects the nullable-offset grammar. All
  five upstream `myanmar-misc.tests` and `myanmar-syllable.tests` rows are now
  retained as per-font corpora under `tests/data/myanmar/` and run against both
  HarfBuzz and HarfRust in the corpus parity umbrella.
- Continue Arabic hot-path work from measured profile evidence: GSUB `calt`
  context lookups now dominate after the GPOS lookup `37` cleanup; avoid
  retaining speculative prefilters unless they improve both Arabic and Roboto
  smoke runs reliably.
- Avoid retaining optimizations that only improve a single noisy run or regress
  Roboto/word-list smoke cases.
- Chaining class windows now track decoded class prefixes by length instead of
  zeroing three 64-byte validity arrays for every candidate glyph. Region
  discovery is monotone, so later authored rules extend the same prefix while a
  changed lookahead origin resets one length. A four-pair fixed-CPU-30 ABBA run
  with 31-sample medians reduced NotoSansDevanagari `hi-words` from an average
  `1556.1` to `1549.1 ns/glyph` (about `0.45%`) and Roboto `en-words` from
  `253.1` to `245.5 ns/glyph` (about `3.0%`), with unchanged corpus checksums.
  The Devanagari win is small but repeatable; more importantly, perf had
  attributed about `5.6%` to memset inside class/glyph/coverage contextual
  windows, and this removes the class-window share without new allocations.
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
- Repeated glyph rendering now has an explicit concrete `render.Prepared` API
  and a `raster-prepared` benchmark mode. Preparation flattens curves once, removes
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
- Repeated public outline decoding now has an explicit parsed-proof
  `font.GlyphSession`, while `Face.glyphs().outline` retains whole-table
  borrowed-byte revalidation. On the built-in compound TrueType fixture, an
  11-sample ReleaseFast run measured about `146 ns/glyph` for the session,
  `616 ns/glyph` for the strict API, and `181 ns/glyph` for FreeType's
  no-scale/no-hinting load: the trusted Cangjie session was about `1.24x`
  faster than FreeType with identical Cangjie outline checksums. The
  `outline-session` benchmark mode retains default and varied-output parity;
  mutation tests document that only the strict API authenticates later source
  changes. Raster benchmarks now use the same parse-proof path as production
  rendering instead of charging the defensive public checksum pass per glyph.
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
- The validated GSUB feature index now retains a table-wide `rand` capability
  bit. Generic script shaping previously checks whether default random
  alternates require value-aware lookup selection once per separately shaped
  line, and that check recalculated the complete borrowed GSUB checksum even
  though the table proof and exact feature accelerator were already cached.
  The fast query verifies the full data pointer/length and table offset/length
  identity, is consumed only after the GSUB proof succeeds, and returns to the
  checksum-validating parser for absent, stale-range, or foreign accelerators.
  Fixed-CPU-8 A/B/B/A comparisons with 15-sample medians reduced Roboto
  `en-words` from a two-run mean of `579.626` to `244.505 ns/glyph`, about
  `57.8%`, and NotoSansDevanagari `hi-words` from `6069.798` to
  `2841.555 ns/glyph`, about `53.2%`. Three-iteration hardware-counter runs
  reduced retired instructions by about `72.6%`/`75.2%`, branches by
  `74.1%`/`75.7%`, and cycles by `56.9%`/`54.6%` for Roboto/Devanagari.
  Amiri `fa-words` and `fa-thelittleprince` retired instructions stayed within
  `0.05%`, confirming the explicit Arabic-stage path does not regress. The
  full dual-reference corpus passes, and focused default `rand`, disabled
  `rand=0`, and valued `rand=2` comparisons retain HarfBuzz parity.
- Stretch-action scratch is now lazy: ordinary runs keep the sidecar empty,
  while the first real `stch` tile backfills preceding emitted output slots
  before subsequent actions remain parallel to public glyphs. This distinction
  matters when default-ignorables are suppressed or GSUB changes cardinality;
  focused tests cover output-count backfill and reuse after a prior active
  sidecar. No-action runs also skip context marking and the stretch dispatcher
  entirely, removing a second full glyph scan. A fixed-CPU-8 A/B/B/A
  comparison with 21-sample medians improved Roboto `en-words` from a two-run
  mean of `245.150` to `241.699 ns/glyph`, about `1.41%`; retired instructions
  fell about `1.36%` and branches about `0.83%`. Devanagari wall time remained
  within `0.1%`, while instructions improved `0.31%`; Amiri
  `fa-thelittleprince` instructions improved `0.55%` and cycles `0.67%`.
  Roboto's profiled `position_stch_ns` fell from about `6.3 ms` to zero.
  The full dual-reference corpus and all three retained Arabic/Syriac active
  `stch` rows pass unchanged.
- Unicode mark predicates now reject scalars below their authoritative first
  members (U+0300 for combining/nonspacing marks and U+0903 for spacing marks)
  before entering long script-range chains. The complete Devanagari block uses
  one early block dispatch and compact exact nonspacing/spacing predicates, so
  Hindi letters also avoid testing the preceding Latin, RTL, and Tibetan mark
  families. Tests exhaust every scalar below both boundaries and all 128
  Devanagari-block scalars against the retained mark sets. Fixed-CPU-8
  A/B/B/A comparisons kept identical checksums. Roboto changed frequency
  plateaus during the run, but both order-matched five-iteration/11-sample
  pairs improved (`439.991` to `295.033` and `242.339` to
  `209.900 ns/glyph`, about `32.9%` and `13.4%`). Stable
  three-iteration/nine-sample Devanagari medians improved from a two-run mean
  of `1333.864` to `1305.386 ns/glyph`, about `2.13%`. Interleaved
  hardware counters reduced retired instructions by about `17.0%`, `2.65%`,
  and `3.07%` for Roboto, Devanagari, and Amiri `fa-thelittleprince`;
  branches fell about `28.2%`, `4.24%`, and `4.93%`, respectively. The full
  dual-reference corpus, including Latin combining-mark zero-width and Indic
  mark/cluster gates, passes unchanged.
- Validated accelerated GSUB dispatch now keeps the common immutable
  `LookupOptions` value on the caller's path and uses a separate noinline
  prepared worker. The options object is 304 bytes; the old inlined wrapper
  copied it unconditionally and compiled to an approximately 3.1 KiB frame per
  lookup. Only lookups that actually override `UseMarkFilteringSet` or
  lookup-local source-syllable scope now materialize a customized copy. The
  common wrapper frame is about 440 bytes and the prepared worker about 312
  bytes. Fixed-CPU-8 A/B/B/A counters reduced retired instructions by about
  `1.55%`, `1.48%`, and `0.51%`, and cycles by `2.41%`, `2.48%`, and
  `0.99%`, for Roboto `en-words`, Devanagari `hi-words`, and Amiri
  `fa-thelittleprince`. Stable Devanagari medians improved from a two-run mean
  of `2720.665` to `2668.695 ns/glyph`, about `1.91%`. Roboto crossed CPU
  frequency states, but both order-matched pairs improved (`724.840` to
  `424.264` and `427.709` to `425.305 ns/glyph`). Focused common/rare-path
  tests, existing mark-filtering and source-syllable tests, and the full
  dual-reference corpus all pass.
- GPOS lookup dispatch now applies the same structural split. `LookupOptions`
  is 216 bytes, and the previous monolithic collector compiled to an
  approximately 5.9 KiB frame while copying the options for every lookup. The
  common wrapper is now about 328 bytes and delegates to an approximately
  872-byte noinline prepared worker; only `UseMarkFilteringSet` lookups make a
  customized options copy. Fixed-CPU-8 A/B/B/A counters reduced retired
  instructions by about `0.50%`, `0.72%`, and `0.28%` for Roboto
  `en-words`, Devanagari `hi-words`, and Amiri `fa-thelittleprince`.
  Devanagari nine-sample medians improved from a two-run mean of `1284.334`
  to `1277.833 ns/glyph`, about `0.51%`. Roboto again crossed frequency
  states, but both order-matched pairs improved (`345.080` to `202.118` and
  `205.716` to `202.203 ns/glyph`). Amiri cycles stayed within `0.06%`.
  Focused common/mark-filtering path tests, existing GPOS mark-set and nested
  extension gates, and the full dual-reference corpus all pass.
- Indic syllable-boundary scanning now resolves the script-specific virama
  once per scan and classifies each scalar's base, dependent-mark, and joiner
  properties once. The previous loop called the composite syllable predicate,
  then repeated base, mark, joiner, and virama classification while advancing
  the same scalar. Keeping one out-of-line scanner also prevents its many
  source-marking and reorder callers from cloning that script-dependent work:
  the ReleaseFast function body shrank from 1,043 to 657 bytes and total text
  fell by 384 bytes. A differential test compares the new traversal with the
  former algorithm for every supported Indic script generation and all
  representative base/virama/mark/joiner/stacker triples. Fixed-CPU-30
  A/B/B/A counters reduced NotoSansDevanagari `hi-words` retired instructions
  by `1.68%`, branches by `4.28%`, cycles by `1.58%`, and branch misses by
  `0.67%`; combined 31-sample medians improved from `1556.913` to
  `1534.526 ns/glyph`, about `1.44%`. Roboto and both Amiri workloads remained
  flat in retired work; their combined medians changed by `-3.80%`, `-0.07%`,
  and `-0.02%`, respectively, with identical checksums. Both retained parity
  gates pass, including Hindi plus Bengali, Gurmukhi, Gujarati, Odia, Tamil,
  Telugu, Kannada, Malayalam, all USE fixtures, and the full Latin/Arabic
  corpora against HarfBuzz and HarfRust.
- Combining-mark classification now dispatches the complete U+0600 Arabic
  block to a compact exact Mn predicate before entering the all-script range
  chain. Ordinary Arabic letters previously tested the Latin and Hebrew mark
  families plus seven Arabic ranges on every grapheme and bidi query. The same
  base-block predicate remains part of the broader out-of-line Arabic helper,
  while the now-unreachable U+0600 ranges were removed from the general chain;
  exhaustive comparison of all 256 block scalars against the generated Unicode
  Mn set protects the dispatch boundary. Fixed-CPU-30 A/B/B/A and B/A/A/B
  matrices with 31-sample medians improved Amiri `fa-words` from `1666.889` to
  `1607.510 ns/glyph`, about `3.56%`, and `fa-thelittleprince` from `857.701`
  to `810.376 ns/glyph`, about `5.52%`. Roboto `en-words` and
  NotoSansDevanagari `hi-words` also improved by about `1.15%` and `0.75%`.
  Reverse-order hardware counters reduced Amiri words/long-text instructions
  by `6.95%`/`9.69%`, branches by `11.43%`/`14.52%`, and cycles by
  `3.53%`/`5.35%`; Roboto and Devanagari retired instructions stayed within
  `0.01%`, while cycles improved `2.43%` and `0.82%`. All checksums were
  identical, and both retained parity gates pass against HarfBuzz and
  HarfRust, including Arabic, Syriac, Hebrew, and Indic mark coverage.
- Large LigatureSubst lookups now retain a sorted exact set of required second
  components when every definition needs a following glyph and the lookup has
  at least 128 competing definitions. A cold necessary-condition scan can then
  reject the whole lookup before probing hundreds of authored alternatives;
  it deliberately inspects every glyph id so lookup flags, feature scope, and
  syllable bounds can cause only harmless false positives, never false
  negatives. The index is appended to the existing component allocation and
  described by a compact range in prior tail padding, so
  `LigatureSubstAccelerator` does not grow for other scripts or lookups.
  Fixed-CPU-30 A/B/B/A plus B/A/A/B matrices with four 31-sample medians per
  binary improved Roboto `en-words` from `218.502` to
  `191.886 ns/glyph`, about `12.18%`; NotoSansDevanagari `hi-words`,
  Amiri `fa-words`, and Amiri `fa-thelittleprince` improved by about
  `0.58%`, `0.64%`, and `0.54%`. Reverse-order counters on the exact retained
  binary reduced Roboto retired instructions by `9.96%`, cycles by `10.91%`,
  branches by `6.61%`, and branch misses by `18.25%`; the three nontarget
  workloads kept instructions within `0.01%` and branches within `0.01%`.
  Profiled Roboto GSUB lookup 6 fell from about `8.77 ms` to `3.13 ms`.
  All corpus checksums remained identical, and both retained parity gates pass
  against HarfBuzz and HarfRust.
- Accelerated ContextSubst format 3 lookups now use a bounded direct
  first-glyph index when the covered glyph space is below 4096. Each u16 slot
  stores `group_index + 1`, retaining zero as the miss sentinel; sparse or
  high-glyph lookups keep the ordered binary-search fallback rather than
  allocating more than 8 KiB. The runtime bounds-checks the decoded index and
  verifies its group key before trusting an externally supplied accelerator.
  Fixed-CPU-30 A/B/B/A plus B/A/A/B matrices with four 31-sample medians per
  binary improved NotoSansDevanagari `hi-words` from `1513.646` to
  `1483.829 ns/glyph`, about `1.97%`. Roboto `en-words`, Amiri `fa-words`,
  and Amiri `fa-thelittleprince` changed by `-0.04%`, `-0.12%`, and `-0.22%`,
  respectively. Interleaved counters reduced Devanagari retired instructions
  by `0.53%`, branches by `0.55%`, cycles by `1.92%`, and branch misses by
  `6.66%`; nontarget instructions and branches stayed within `0.01%`. Focused
  tests cover direct hits, corrupt index/key rejection, and the high-glyph
  fallback. All corpus checksums remained identical, and the complete retained
  parity suite passes against HarfBuzz and HarfRust.
- Indic shaping now proves its maximal glyph/source metadata contract before
  the first explicit `nukt`/`akhn` stage and immediately enters the trusted
  cached-plan path. Source features, syllables, clusters, substitution state,
  and ligature provenance are all complete at that point, while every
  supported GSUB mutation preserves their parallel cardinalities. Previously
  the pre-reorder stage defensively scanned the same run and provenance store,
  then the maximal proof repeated that validation before the remaining stages.
  Fixed-CPU-30 A/B/B/A plus B/A/A/B matrices with four 31-sample medians per
  binary improved NotoSansDevanagari `hi-words` from `1483.831` to
  `1470.815 ns/glyph`, about `0.88%`. Roboto `en-words`,
  SourceSerifVariable `en-words`, Amiri `fa-words`, and Amiri
  `fa-thelittleprince` changed by `-0.05%`, `-0.39%`, `+0.05%`, and `-0.11%`,
  respectively. Interleaved hardware counters reduced Devanagari retired
  instructions by `0.62%`, branches by `0.75%`, cycles/ref-cycles by `1.03%`,
  and branch misses by `1.11%`; nontarget instructions and branches stayed
  within `0.01%`, and nontarget cycles stayed within `0.14%`. All checksums
  were identical. The full ReleaseFast test suite and complete retained parity
  umbrella pass against both HarfBuzz and HarfRust, including the 10,000-line
  Hindi corpus and all retained USE/Indic fixtures.
- Devanagari syllable-boundary scans now use a compact script-specialized
  classifier for bases, dependent marks, virama, joiners, and the Vedic
  stacker. The generic all-Indic scanner remains byte-for-byte separate for
  every other script, while a 29-byte dispatcher and the specialization live
  in a dedicated text section; this avoids shifting unrelated Latin and Arabic
  hot code, which earlier inline predicate experiments had regressed. An
  exhaustive one-scalar differential checks all Unicode scalar values for both
  `dev2` and legacy `deva`, and the existing multi-scalar differential covers
  virama/joiner and stacker state transitions. Fixed-CPU-30 A/B/B/A plus
  B/A/A/B matrices with four 31-sample medians per binary improved
  NotoSansDevanagari `hi-words` from `1467.521` to `1426.814 ns/glyph`, about
  `2.77%`. Roboto `en-words`, SourceSerifVariable `en-words`, Amiri
  `fa-words`, and Amiri `fa-thelittleprince` changed by `-0.61%`, `-0.78%`,
  `-0.02%`, and `-0.03%`, respectively. Interleaved hardware counters reduced
  Devanagari retired instructions by `5.01%`, branches by `8.82%`, and
  cycles/ref-cycles by `2.86%`; nontarget instructions and branches stayed
  within `0.002%`, and nontarget cycles stayed within `0.12%`. All checksums
  were identical. The full ReleaseFast test suite and complete retained parity
  umbrella pass against both HarfBuzz and HarfRust.
- The isolated Devanagari scanner now also classifies its primary block as one
  contiguous U+0900..U+0961 shaping range with the exact U+0950 hole, then
  distinguishes the compact base ranges and U+094D virama. Widening once to
  `u32` removes repeated 21-bit masks and overlapping range tests from every
  scanned scalar. The exhaustive differential compares base, dependent-mark,
  virama, and joiner membership directly for all Unicode scalars. Against
  `0467a6e`, fixed-CPU-30 A/B/B/A plus B/A/A/B 31-sample medians improved
  NotoSansDevanagari `hi-words` from `1428.302` to `1425.175 ns/glyph`, about
  `0.22%`, with both orders improving. Interleaved counters reduced Hindi
  retired instructions by `0.81%`, branches by `0.72%`, cycles by `0.44%`,
  and branch misses by `1.13%`. The SourceSerifVariable control was exactly
  neutral in retired instructions/branches and stayed within `0.13%` in
  cycles; its `.text` section and every shared hot-function address remained
  identical. Corpus checksums were unchanged.
- The same isolated scanner now follows category-major state transitions:
  dependent marks preserve the virama state without materializing all
  predicates, bases and virama update it directly, and a one-bit previous
  Vedic-stacker state replaces reloading the preceding source scalar for every
  base. Against `d0e2838`, fixed-CPU-30 A/B/B/A plus B/A/A/B 31-sample medians
  improved NotoSansDevanagari `hi-words` from `1420.796` to
  `1409.371 ns/glyph`, about `0.80%`, with both orders improving. Interleaved
  counters reduced Hindi retired instructions by `1.44%`, branches by `0.86%`,
  and cycles/ref-cycles by about `0.79%`; branch misses increased `0.21%` but
  did not offset the wall-time gain. The SourceSerifVariable control remained
  exactly neutral in retired instructions and branches and stayed within
  `0.24%` in cycles. Checksums were identical.
- The scanner now seeds the first accepted scalar separately, since that scalar
  always starts a syllable. The main loop consequently handles only subsequent
  scalars and no longer carries an `index != start` counter through every
  classification; the isolated function shrank from 434 to 378 bytes. Against
  `be40cc9`, fixed-CPU-30 A/B/B/A plus B/A/A/B 31-sample medians improved
  NotoSansDevanagari `hi-words` from `1412.536` to `1409.773 ns/glyph`, about
  `0.20%`, with both orders improving. Interleaved counters reduced Hindi
  instructions/cycles by `0.25%`, branches by `0.13%`, and branch misses by
  `0.26%`. The SourceSerifVariable control remained exactly neutral in retired
  instructions/branches and improved about `0.10%` in cycles. Checksums were
  identical.
- The isolated scanner now dispatches the common U+0904..U+0939 base range
  before testing U+094D virama and the rare U+0958..U+0961 bases. Ordinary
  syllable boundaries and conjunct continuations therefore stop or consume
  through one base-range path instead of materializing every category
  predicate; dependent marks retain the existing virama/stacker state
  semantics. The scanner shrank from 378 to 335 bytes, while the shared
  `.text` section and `layout.shapeSegmentInto` address/size stayed exactly
  unchanged. Against `133e9d8`, fixed-CPU-30 A/B/B/A plus B/A/A/B 31-sample
  medians improved NotoSansDevanagari `hi-words` from `1414.743` to
  `1405.313 ns/glyph`, about `0.67%`, with both orders improving (`0.69%` and
  `0.65%`). Interleaved counters reduced Hindi retired instructions by
  `0.43%` and cycles/ref-cycles by about `0.11%`; branches rose `0.39%` and
  branch misses `0.20%`, but the stable wall-time result confirms the tradeoff.
  The SourceSerifVariable control remained exactly neutral in retired
  instructions/branches and improved about `0.23%` in cycles. Checksums were
  identical. All 293 focused Indic tests, the full ReleaseFast suite, and the
  retained parity umbrella pass, including the 10,000-line Hindi HarfBuzz
  comparison (`b01a5388ce792b49`).
- USE invalid-vowel matching now rejects scalars outside the exact generated
  set of 50 possible sequence starts before entering the lower-bound search
  over all 103 constraints. The set and its explanatory counts are generated
  from `IndicShapingInvalidCluster.txt`, and regenerating to a temporary file
  reproduces the checked-in Zig source byte for byte. Against `53f8eda`,
  fixed-CPU-30 reverse-order counters reduced NotoSansDevanagari `hi-words`
  retired instructions by `0.64%`, branches by `0.57%`, cycles by `0.61%`,
  and ref-cycles by `1.31%`; branch misses rose `0.35%`. The 31-sample
  dual-order medians improved Hindi by `0.32%` overall, with both orders
  improving. Roboto and SourceSerifVariable retired work stayed within
  `0.001%`, and both improved in counter cycles; Amiri `fa-words` and
  `fa-thelittleprince` remained neutral or improved. All five A/B checksums
  were identical. The focused test, full ReleaseFast suite, USE parity gate,
  general shaping parity gate, and corpus parity gate all pass.
- Myanmar `mym2` shaping now uses the complete maximal-munch syllable grammar
  instead of grouping every adjacent Myanmar scalar into one run. Its Unicode
  17 category ranges are reproducibly decoded from HarfBuzz's generated Indic
  table; an independent differential against HarfRust's generated Ragel
  machine covered all 475,254 category strings of length one through four and
  1.2 million deterministic random strings of length five through sixteen.
  Broken syllables now receive one dotted circle each, including standalone
  pre-base vowels, incomplete kinzi, adjacent broken clusters, and unsupported
  variation selectors. Synthetic bases retain glyph-level categories through
  reordering and cannot be hidden merely because they share a default-
  ignorable source. The modern shaper also preserves FE00 as an explicit
  Myanmar grammar glyph instead of folding cmap-14 variants into the preceding
  base; legacy `mymr` continues to use the default shaper as HarfBuzz requires.
  The retained 19-line corpus passes HarfBuzz and HarfRust with checksum
  `6ea4513597b3e062`, while the pre-change binary fails its first standalone
  U+1031 row by omitting the dotted circle.
- Generic GSUB runs with a non-empty cached lookup selection now execute that
  immutable plan directly after the layout shaper has proved the borrowed table
  and constructed valid glyph/source-parallel metadata. The trusted executor
  requires an exact table-identity feature accelerator and the shared
  HarfBuzz-compatible operation/growth budget, validates every selected index
  before the first mutation, and declines without changing glyphs for empty,
  foreign, out-of-range, or unbounded inputs. Those cases and every public API
  retain the defensive topology and metadata validators. The executor and its
  orchestration share the isolated Indic-scanner text section so their code
  growth does not shift unrelated Latin/Arabic hot functions in the main
  section. Fixed-CPU-30 A/B/B/A 31-sample medians improved Roboto `en-words`
  by about `4.95%`, NotoSansDevanagari `hi-words` by `0.99%`, and Amiri
  `fa-words` by `0.86%`; Amiri `fa-thelittleprince` changed by `+0.42%`.
  Interleaved native E-core counters reduced retired instructions/branches/
  cycles by `4.11%`/`4.72%`/`8.02%` for Roboto, `1.18%`/`1.43%`/`1.19%`
  for Devanagari, and `0.24%`/`0.15%`/`1.17%` for Amiri words. The Amiri long
  control stayed within `+0.012%` instructions, `+0.006%` branches, and
  `+0.30%` cycles. All A/B checksums were identical; the full ReleaseFast,
  corpus, shaping, and USE gates pass unchanged.
- Direct PairPos lookups now activate an already-built native class-matrix
  accelerator even when the lookup contains no format-1 pair records. The
  former gate used the global format-1 record count as a proxy for every
  PairPos accelerator kind, so Amiri lookup 74 paid to build a bounded
  native-endian `80 x 67` format-2 matrix and then always reparsed the borrowed
  table instead. Activation now asks whether any subtable has non-generic
  native data; ExtensionPos keeps its existing independent path. A focused
  pure-format-2 fixture proves that an empty format-1 record slice still selects
  the matrix and returns the expected class-pair advance. Against `245b9c2`,
  fixed-CPU-30 A/B/B/A 31-sample means improved Amiri `fa-words` by `0.53%`,
  Amiri `fa-thelittleprince` by `0.20%`, and Devanagari `hi-words` by `0.31%`;
  Roboto `en-words` changed by `+1.04%`. Native E-core counters reduced Amiri
  long-text instructions by `7.22%`, branches by `6.02%`, cycles/ref-cycles by
  `8.18%`, and branch misses by `1.31%`; Amiri words also improved. Roboto
  instructions/branches stayed within `+0.05%`, with cycles down `0.48%`;
  Devanagari instructions rose `0.13%`, branches fell `0.20%`, and its
  single-order cycles rose about `1.05%`. All A/B checksums were identical, and
  the full ReleaseFast, corpus, shaping, and USE gates pass unchanged.
- Complete shaped-run caching remains opt-in after a workload audit found that
  Roboto `en-words`, Amiri `fa-words`, and NotoSansDevanagari `hi-words` contain
  no repeated lines: enabling the cache adds lookup and ownership work without
  a possible hit. A two-hit admission prototype still regressed the Roboto
  unique-word median substantially, so it was not retained. The production
  cache now addresses the independent correctness problem instead: it has a
  32-entry LRU bound (with a zero-capacity mode for explicit callers), frees an
  evicted run's complete exact key and shaped output, and refreshes recency on
  exact collision-safe hits. This prevents an opt-in cache from growing without
  bound while preserving its first-repeat hit behavior and the default-off
  performance policy.

- GSUB's mutation-aware run-digest cache now stores one unfiltered glyph
  superset per mutation epoch instead of separate summaries for every lookup
  flag and source-feature scope. These digests are used only as necessary-
  condition rejection filters: lookup/source filtering can remove candidates
  but cannot introduce a glyph absent from the superset, so false positives
  remain safe while false negatives remain impossible. Fixed-CPU-30 B/A/A/B
  comparisons against `321044b` reduced NotoSansDevanagari `hi-words` medians
  from `1603.990`/`1564.477` to `1520.574`/`1496.665 ns/glyph`, about `4.9%`
  overall. The same matrix improved Roboto `en-words` by about `5.1%`,
  SourceSerifVariable `en-words` by about `4.5%`, Amiri `fa-words` by about
  `6.4%`, and Amiri `fa-thelittleprince` by about `2.0%`. All A/B checksums
  were identical.
  A post-change fixed-CPU-30 Cangjie/HarfBuzz/HarfBuzz/Cangjie matrix
  measured NotoSansDevanagari at `1462.429`/`1464.667` versus
  `951.391`/`947.447 ns/glyph`, leaving Cangjie about `54%` slower.
  Amiri `fa-thelittleprince` remained a small Cangjie win at
  `746.081`/`745.761` versus `758.687`/`753.144 ns/glyph`; Roboto,
  SourceSerifVariable, and Amiri words still trailed. The broader performance
  objective therefore remains open.
- Indic source preparation now derives syllable ids and source-scoped basic
  feature masks in one syllable walk. Both maps use the same boundaries, but
  the old production path called the specialized boundary scanner twice per
  shaped item before any staged lookup ran. The independent builders remain as
  focused test surfaces and a new differential verifies the fused result. A
  fixed-CPU-30 B/A/A/B 11-sample matrix reduced NotoSansDevanagari
  `hi-words` medians from `1483.591`/`1487.765` to
  `1454.802`/`1454.693 ns/glyph`, about `2.1%`. Interleaved five-iteration
  counters reduced retired instructions by `0.80%`, branches by `1.19%`, and
  cycles by `1.68%`. Roboto retired instructions/branches were identical and
  cycles improved about `2.4%`; Amiri long text improved about `0.05%` in
  instructions/branches and `0.45%` in cycles. All checksums were unchanged,
  and the complete HarfBuzz/HarfRust parity umbrella passes, including the
  10,000-line Hindi corpus at `b01a5388ce792b49`.
- Chaining class-context matching now returns a boolean and writes its three
  bounded physical-index regions only after a rule succeeds. Returning
  `!?Match` had made each rejected rule initialize or copy the large
  error-union payload even though no region escaped; both accelerated and
  defensive format-2 paths now share the success-only materialization
  contract. The accelerated wrapper remains in the isolated hot-path section,
  preventing its code-size change from shifting unrelated Latin and Arabic
  functions. A fixed-CPU-30 A/B/B/A plus B/A/A/B 31-sample matrix reduced
  NotoSansDevanagari `hi-words` process medians from an average
  `1465.911` to `1417.134 ns/glyph`, about `3.33%`; every process kept
  checksum `e057170f005a0939`. Five-repeat counters reduced retired
  instructions by `3.32%` and branches by `1.76%`; cycles were effectively
  flat in that counter order and branch misses rose `1.43%`, while the
  interleaved wall-time matrix retained the clear gain. Roboto instructions
  and branches changed by less than `0.003%` and cycles improved `0.24%`;
  Amiri long text instructions/branches stayed within `0.001%`. The complete
  test suite and shaping, corpus, and USE HarfBuzz/HarfRust parity umbrellas
  pass, including the 10,000-line Hindi checksum `b01a5388ce792b49`.
- Chaining glyph-context matching now follows the same success-only output
  contract instead of returning its three 64-index regions inside
  `!?Match`. The fixed-position wrapper is kept out of line in the isolated
  hot-path section, so its reduced result traffic cannot perturb unrelated
  code layout. Against `7037c05`, a fixed-CPU-30 B/A/A/B 11-sample probe
  reduced NotoSansDevanagari `hi-words` medians from
  `1432.475/1418.528` to `1409.786/1395.402 ns/glyph`, about `1.61%`;
  retired instructions, branches, and cycles fell `1.84%`, `0.98%`, and
  `0.85%` in five-repeat counters, with branch misses down `0.24%`.
  Roboto and Amiri word/long-text controls improved in the interleaved probe,
  and all checksums were unchanged.
- GPOS now primes the unfiltered per-run coverage digest before lookup
  traversal. LookupFlag-zero is the common path, so every such lookup receives
  an immediate slot-zero cache hit instead of making the first matching lookup
  build the digest lazily after searching an empty cache; filtered variants
  remain keyed and built independently. Fixed-CPU-30 B/A/A/B 11-sample
  medians reduced NotoSansDevanagari `hi-words` from
  `1390.712/1387.722` to `1378.098/1379.724 ns/glyph`, about `0.74%`.
  Five-repeat counters reduced retired instructions and cycles by `0.10%`
  and `0.35%`; branches changed by `+0.01%`. Roboto and Amiri counters
  also reduced retired instructions/cycles, while SourceSerif's instruction
  count improved but its cycle sample regressed, so no broader Latin claim is
  made. All corpus checksums were unchanged.
- ChainContextSubst format-3 now writes its three bounded physical-index
  regions into caller scratch only after the matcher succeeds, rather than
  returning the 1.5 KiB `Regions` value inside `!?Regions` on every failed
  candidate. Direct and indexed paths share the same boolean/out-parameter
  contract. Fixed-CPU-30 five-repeat counters reduced NotoSansDevanagari
  `hi-words` retired instructions by `0.87%`, branches by `0.44%`, and
  cycles by `0.52%`; Roboto and SourceSerif cycle counters improved about
  `2.9%` and `2.8%` with effectively identical retired work. Amiri long
  text retired instructions/branches fell about `1.2%/0.6%` and cycles were
  flat. Interleaved wall-time samples were noisy under the active host load,
  so only the stable counter result is retained. All checksums were unchanged.
- Accelerated LigatureSubst now tests each candidate glyph against the already
  owned first-component digest before probing its exact LigatureSet hash. The
  digest is only a necessary-condition rejector, so collisions still reach the
  exact index and authored preference is unchanged. Fixed-CPU-30 five-repeat
  counters reduced Devanagari `hi-words` cycles by `1.53%`, branches by
  `0.05%`, and branch misses by `2.93%`; retired instructions changed by
  `+0.02%`. Roboto cycles/instructions improved about `2.1%/0.09%`,
  SourceSerif cycles improved about `3.6%` with `+0.08%` instructions, and
  Amiri long text improved about `1.0%` in cycles/instructions and `0.6%`
  in branches. Interleaved medians improved for the target and controls despite
  substantial host outliers, and all checksums were unchanged.
- GPOS coverage prefiltering now caches one unfiltered glyph superset for the
  immutable post-GSUB run instead of rebuilding separate digests for each
  LookupFlag/mark-filtering state. Filtering can only remove candidates, so
  this remains a necessary-condition rejector with safe false positives and no
  false negatives. Fixed-CPU-30 five-repeat counters reduced Devanagari
  `hi-words` retired instructions by `3.09%`, branches by `3.58%`,
  cycles by `1.99%`, and branch misses by `6.65%`. Roboto and SourceSerif
  retired work improved about `0.17%/0.16%` with cycles within `+0.2/0.6%`;
  Amiri long text improved about `1.7%` in instructions, `1.8%` in
  branches, and `0.9%` in cycles. All checksums were unchanged.
- Prepared 4x4 raster rows now accumulate full-pixel interiors as signed range
  differences and resolve them during the already-required blend walk. Exact
  sample-center tests remain at both span boundaries, while 1x1, 2x2, and
  nonstandard sampling densities stay on the compact legacy prepared scanner.
  Direct/prepared byte parity passes for every retained sampling density,
  repeated calls, overlapping non-zero contours, empty outlines, and small-size
  emboldening. Fixed-CPU-30 B/A/A/B 21-sample medians for Roboto 64 px
  prepared rendering improved `A` from `10,724`/`10,768` to
  `9,179`/`9,189 ns` (about `14.5%`), `g` from `11,698`/`11,717` to
  `10,118`/`10,151 ns` (about `13.4%`), and `é` from
  `8,146`/`8,101` to `7,014`/`7,028 ns` (about `13.6%`). Retired
  instructions fell `17.1%`, `16.5%`, and `16.9%`, respectively. The lower
  density control checksums stayed identical on their unchanged implementation.
  Prepared rendering now beats Cangjie's repeated direct scanner on the same
  rows by about `14%` for `A`, `31%` for `g`, and `31%` for `é`, but still
  does not close the larger FreeType raster gap.
- Runtime CFF1/CFF2 hinting now builds the FreeType-derived Type2 horizontal
  hint map rather than applying independent rounded stem edges. It retains
  hintmask/cntrmask state, variation-aware Private DICT blue zones, initial-map
  placement, pair adjustment, overlap rejection, blue capture, and stem
  locking in 16.16 before exposing 26.6-precise pixel paths. The installed
  FreeType differential now passes STIX `A`, `H`, and `o` across 9/13/16 ppem
  plus Cantarell variable-CFF2 `A` and `B` at normalized `-1` and `0.5`,
  comparing every outline point/tag/contour and the grid-fitted advance. The
  Cantarell gate also covers CFF2 Private DICT operator-23 `blend`, which is
  distinct from the charstring blend opcode. This closes a concrete
  Fontations/Skrifa outline-correctness gap, but no Type2 speed claim is made;
  FreeType still leads the broader scan-conversion measurements above.
- Prepared geometry now caches the sorted edge intersections for all four
  fixed 4x4 sample rows during `prepare`, so every repeated draw starts at
  winding/span accumulation instead of rebuilding active edges and sorting the
  same intersections. The immutable cache remains target-independent; target
  clipping chooses a row subrange, and pathological coordinate spans decline
  the cache and retain the bounded legacy scan. Other sampling densities keep
  their former implementation. Fixed-CPU-30 B/A/A/B 21-sample medians for
  Roboto 64 px reduced `A` from about `10,155`/`10,145` to
  `8,308`/`8,218 ns` (about `18.5%`), `g` from `11,039`/`11,008` to
  `9,074`/`9,060 ns` (about `17.7%`), and `é` from `8,171`/`8,179` to
  `7,005`/`6,984 ns` (about `14.5%`). Interleaved counters reduced retired
  instructions by about `15.7%`, `18.3%`, and `12.9%`, and cycles by about
  `18.4%`, `18.3%`, and `14.7%`, respectively. All target checksums and the
  retained direct/prepared 1/2/3/4-density differential are unchanged.
- Prepared non-zero geometry now resolves those cached 4x4 intersections into
  a target-independent byte coverage rectangle during `prepare`. Repeated
  draws clip and blend that rectangle directly; even-odd fills, other sample
  densities, pathological coordinate spans, and coverage over 16 MiB retain
  the bounded scanners. Fixed-CPU-30 B/A/A/B 21-sample medians reduced Roboto
  `A` from about `8,243`/`8,239` to `4,660`/`4,664 ns` (about `43.4%`),
  `g` from `9,100`/`9,157` to `4,565`/`4,560 ns` (about `50.0%`), and `é`
  from `6,986`/`6,990` to `4,402`/`4,396 ns` (about `37.0%`). Counters
  reduced retired instructions by about `46.4%`, `53.7%`, and `40.5%`, and
  cycles by about `44.4%`, `50.2%`, and `36.7%`, respectively. All target
  checksums remain identical; the 1x1 counter control is cycle-neutral, and
  the 2x2/3x3 wall-time controls stayed within noise or improved. FreeType's
  reused raster still remains ahead of this boundary.
- The dense prepared coverage cache now records each row's inclusive non-zero
  x range. Target clipping intersects that range before the blend walk, so
  empty exterior pixels are never loaded. Fixed-CPU-30 comparisons against the
  first coverage-cache state reduced Roboto `A` from about `4.65` to `4.00
  µs`, `g` from `4.49` to `4.15 µs`, and `é` from `4.40` to `3.84 µs`;
  retired instructions fell about `15.6%`, `6.6%`, and `14.2%`, respectively.
  Checksums, clipping behavior, and the retained lower-density controls remain
  unchanged.
- `glyph-bench --dirty-rect` now exposes a public repeated-render boundary
  with matched dirty-target work: both engines reuse their face and target,
  then clear, draw, and hash only the previously discovered clipped glyph
  rectangle. Cangjie also reuses its immutable prepared geometry/coverage;
  FreeType still performs `FT_Load_Glyph(FT_LOAD_RENDER)` because its reusable
  face API does not expose an equivalent prepared-coverage object. Fixed CPU 30
  with 20,000 iterations and 21 samples measured Cangjie/FreeType medians of
  about `2,622/4,433 ns` for Roboto `A`, `2,115/5,578 ns` for `g`, and
  `1,781/5,214 ns` for `é`: Cangjie leads by about `1.69x`, `2.64x`, and
  `2.93x`. The reported dirty rectangles are comparable (`1840/1886`,
  `1421/1421`, and `1421/1470` pixels); per-engine checksums remain stable.
  Five-repeat `perf stat` runs on the same fixed CPU retired about
  `615M/1,506M`, `662M/1,901M`, and `555M/1,780M` instructions and
  `177M/397M`, `195M/501M`, and `165M/475M` cycles for
  Cangjie/FreeType, respectively. Branches were about `92M/229M`,
  `102M/294M`, and `85M/277M`; branch misses stayed below `0.22%` of
  branches for both engines. These counters corroborate the wall-time result
  rather than attributing it only to frequency or scheduling noise.
  This is a public-pipeline win under those stated reuse contracts, not an
  equal-work microbenchmark or a claim that Cangjie's one-shot scan converter
  or antialiasing algorithm is universally faster. A client-side cached
  FreeType bitmap would define a different, upload/blit-only boundary.
- Direct `raster-reuse` now has the same clipped-target consumer as the
  prepared/FreeType dirty-rectangle rows. Both engines discover the stable
  non-zero fringe outside timing, then clear, draw, and hash only that rectangle;
  Cangjie still runs its ordinary flatten-and-scan path on every iteration.
  Fixed-CPU-30 medians on Roboto 64 px leave FreeType ahead: Cangjie/FreeType
  measured about `25.32/10.25 µs` for `A`, `35.70/13.89 µs` for `g`, and
  `33.04/18.24 µs` for `é`. Comparable dirty areas (`1840/1886`, `1421/1421`,
  and `1421/1470` pixels) show that full-target hashing was not the cause of
  the direct scan-conversion deficit.
- Direct scanline intersection sorting now uses fixed compare-swap networks for
  two through four intersections, which dominate ordinary glyph sample rows,
  while retaining insertion/heap sorting for larger rows. Across Roboto 64 px
  `A`, `g`, and `é`, direct dirty-render checksums were byte-identical; 1×1,
  2×2, and 3×3 density controls were byte-identical as well. Fixed-CPU-30
  five-repeat counters reduced retired instructions by about `3.7%`, `3.5%`,
  and `2.1%`, and branches by about `5.8%`, `6.1%`, and `3.3%`, respectively.
  Cycle reductions were about `0.7--1.6%` under substantial frequency noise,
  so this narrows but does not close the FreeType gap above.
- Half-open horizontal sample semantics also make the pixel beginning at
  `ceil(span_end)` unconditionally empty. Direct span accumulation now stops at
  `ceil(span_end)-1` (with clipped target-end handling unchanged), avoiding one
  zero partial-pixel probe and excluding its empty fringe from the row's later
  blend/clear range. Roboto 64 px `A`, `g`, and `é` retained byte-identical
  direct dirty-render output; 1×1, 2×2, and 3×3 controls did as well. Relative
  to the preceding sorting-network binary, fixed-CPU-30 five-repeat counters
  reduced retired instructions by about `6.1%`, `4.7%`, and `4.5%`, and cycles
  by about `7.8%`, `3.1%`, and `3.0%`, respectively.
- Direct 4×4 scanline accumulation now shares the prepared scanner's signed
  range-difference accumulator instead of incrementing every interior pixel for
  every sample span. `scanline_types.zig` owns the cycle-free target/span/blend
  primitives shared by the direct scanner and accumulator; 1×1, 2×2, and 3×3
  continue on the former count-array path. Roboto 64 px `A`, `g`, and `é` kept
  byte-identical direct dirty-render output. Relative to `de71d1c`, fixed-CPU-30
  five-repeat counters reduced instructions by about `16.7%`, `13.0%`, and
  `13.5%`, branches by `11.8%`, `8.7%`, and `9.8%`, and cycles by roughly
  `12.7%`, `10.4%`, and `11.7%`, respectively.
- The 4×4 signed-difference accumulator now applies the same half-open span-end
  bound as the legacy count scanner: the pixel beginning at `ceil(end)` cannot
  contain any sample center and is excluded. Prepared-cache construction uses
  the same bound, and a focused boundary test plus the retained direct/prepared
  byte differentials protect output identity. Fixed-CPU-8 A/B/B/A counters over
  20,000 direct dirty renders reduced retired instructions for Roboto 64 px
  `A` from `2.29416B/2.29411B` to `2.18827B/2.18821B` (about `4.62%`),
  `g` from `3.37542B/3.37536B` to `3.25727B/3.25734B` (about `3.50%`),
  and `é` from `2.32225B/2.32214B` to `2.24255B/2.24248B` (about
  `3.43%`). Branches fell about `5.22%`, `4.00%`, and `4.00%`; cycles
  improved in every order, while all dirty-render checksums and pixel counts
  remained unchanged.
- Direct scan conversion now buckets sufficiently complex prepared edges by
  the first clipped pixel row they can cross. This replaces the per-draw
  comparison sort of complete 24-byte edge records with an O(edges + rows)
  activation pass; outlines below 32 prepared edges retain the cheaper
  insertion-sort path. On fixed CPU 30, B/A/A/B counters over 20,000 direct
  dirty renders reduced retired instructions for Noto Sans 64 px `g` from
  `3.443B/3.443B` to `3.022B/3.022B` (about `12.2%`) and for `é` from
  `2.354B/2.354B` to `2.088B/2.088B` (about `11.3%`); cycles fell about
  `9.5%` and `10.4%`, respectively. The 11-edge `A` control kept the sorted
  path and retired about `1.1%` fewer instructions, with noisy cycles. All three
  output checksums and dirty-pixel counts remained unchanged, and the complete
  ReleaseFast test suite passes. FreeType still leads this direct-render
  boundary, so the broader raster objective remains open.
- Direct fill now derives target-clipped bounds while converting finite,
  non-horizontal edges into `PreparedFillLine` records. This removes a second
  complete flattened-edge walk without changing the public `boundsForTarget`
  helper or prepared-render lifecycle. Relative to the bucketed baseline, a
  fixed-CPU-30 B/A/A/B counter matrix over 20,000 direct dirty renders reduced
  retired instructions by about `1.1%` for Noto Sans 64 px `A`, `2.3%` for
  `g`, and `2.8%` for `é`; branches fell about `0.4%`, `1.6%`, and `2.0%`.
  Cycles improved in every order. Checksums and dirty-pixel counts remained
  unchanged for all three glyphs at 1×1, 2×2, 3×3, and 4×4 sampling, and a
  focused regression compares the fused result against the two public passes.
- The intersection sorter is now inlined into its scan-row callers. Typical
  glyph rows contain only two or four crossings, so this exposes the existing
  fixed sorting networks directly to the surrounding loop while larger sets
  still use insertion/heap sorting. Fixed-CPU-30 B/A/A/B counters over 20,000
  direct dirty renders reduced retired instructions by about `2.0%` for Noto
  Sans 64 px `A`, `2.5%` for `g`, and `2.7%` for `é`; cycles fell about
  `1.5--2.8%`. The output checksum and dirty-pixel count for every glyph stayed
  unchanged.
- Sparse GPOS adjustment output now checks for its common nondecreasing index
  order before invoking heap sort. The isolated noinline helper preserves the
  segment hot frame and falls back to the exact old sort at the first inversion.
  On fixed CPU 30, five-repeat counters reduced Roboto `react-dom` instructions
  by about `6.25%`, branches by `3.11%`, and cycles by roughly `8.4%`; Roboto
  `en-words` improved by about `2.6%`, `1.6%`, and `8.7%`, respectively. Amiri
  long text and Devanagari retired work stayed within `0.05%`, with cycles noisy
  but approximately neutral. All four corpus checksums were unchanged.
- Compact-font GPOS accelerators now build an exact glyph-id to coverage-group
  side index once and use it in native PairPos traversal. The index is capped
  at 4096 glyph ids (8 KiB); sparse CJK/CID lookups retain their bounded hash
  or binary path. Fixed-CPU-30 A/B/B/A counters on Roboto `react-dom` reduced
  retired instructions from `3.9027B/3.9017B` to `3.8913B/3.8914B` (about
  `0.28%`) and branches by about `0.01%`; cycles improved in three of four
  orders but remain frequency-sensitive. Roboto `en-words` instructions fell
  about `0.14%`, while Devanagari and Amiri controls retained identical
  checksums with effectively neutral retired work. The complete 672-row
  HarfBuzz/HarfRust corpus umbrella passes unchanged.
- Multi-stage script shapers can now request several cached GSUB feature plans
  in one lookup-cache pass. Indic finish uses the generic batch API for its
  pre-reorder, basic, `pref`, pre-reph, and final stages, then applies the same
  immutable plans at the existing reorder boundaries. This keeps the cache
  independent of Indic policy while avoiding five separate linear cache walks
  per source run. Fixed-CPU-30 A/B/B/A counters over two complete
  NotoSansDevanagari `hi-words` passes reduced retired instructions from
  `1.0422B/1.0405B` to `1.0194B/1.0194B` (about `2.1%`) and branches from
  `178.6M/178.3M` to `174.3M/174.3M` (about `2.3%`); cycles fell about
  `0.4--2.9%`. Checksum `c53c50e3c7c8ca3f` remained unchanged. The Roboto
  `en-words` control retained checksum `ca4dc411c23af197`; retired instructions
  and branches improved slightly because its generic shaper does not call the
  new batch API, so the difference is code-layout neutral/noise rather than a
  claimed Latin algorithmic gain.
- Cached feature-plan traversal now owns the single top-level disabled-lookup
  check. The contextual record executor no longer repeats the same binary
  search before dispatching every already-admitted top-level lookup; nested
  SequenceLookupRecord paths continue to enforce the JSTF disable set in their
  dedicated executor. Fixed-CPU-30 A/B/B/A counters over two full Devanagari
  `hi-words` passes reduced retired instructions from `1.0190B/1.0198B` to
  `1.0155B/1.0160B` (about `0.36%`) and branches from `174.2M/174.4M` to
  `173.1M/173.2M` (about `0.66%`); cycles fell about `1.2--7.0%` under the
  active frequency noise. Checksum `c53c50e3c7c8ca3f` was unchanged. Roboto
  `en-words` retained checksum `ca4dc411c23af197` and improved retired
  instructions/branches in both candidate passes.
- Accelerated chaining class matching now compares its lazily decoded class
  window directly with the authored class sequence. The old path first copied
  as many as 192 classes into a stack vector, hashed the vector, and then
  walked it again with `mem.eql`; direct comparison exits at the first mismatch
  and materializes no temporary sequence. The implementation stays in the
  flattened `chaining/class/matching.zig` module rather than adding another
  nested matcher file. Fixed-CPU-30 A/B/B/A counters over two Devanagari
  `hi-words` passes reduced retired instructions from `1.0155B/1.0148B` to
  `1.0152B/1.0148B` and branches from `173.12M/173.01M` to
  `173.07M/173.00M`; cycles improved about `1.3--1.7%`. Checksum
  `c53c50e3c7c8ca3f` was unchanged. Roboto `en-words` retained checksum
  `ca4dc411c23af197` with effectively identical retired work.
- Staged GSUB feature application now selects its unfiltered inner loop once
  per plan entry when the JSTF disabled-lookup set is empty. Previously every
  admitted lookup repeated the same empty-slice branch before dispatch. The
  filtered loop remains unchanged for actual JSTF suppression, and nested
  contextual targets retain their dedicated disable enforcement. Fixed-CPU-30
  A/B/B/A counters over two Devanagari `hi-words` passes changed retired
  instructions from `1.0154B/1.0174B` to `1.0148B/1.0155B` and branches from
  `173.10M/173.47M` to `173.09M/173.24M`; cycles improved in three of four
  orders but remain frequency-sensitive. Checksum `c53c50e3c7c8ca3f` was
  unchanged. Roboto `en-words` retained checksum `ca4dc411c23af197` with
  neutral retired work and slightly lower cycles in both candidate passes.
- Modified-combining-class lookup now rejects ordinary U+0900..U+097F
  Devanagari scalars before entering the generated cross-Unicode search. Only
  the block's six non-zero-CCC scalars (U+093C, U+094D, and U+0951..U+0954)
  continue to that table, with contract tests covering every exception. On
  fixed CPU 30, five-pass A/B/B/A counters over NotoSansDevanagari `hi-words`
  reduced retired instructions from `2.9918B/2.9915B` to
  `2.9538B/2.9533B` (about `1.28%`) and branches from
  `510.3M/510.3M` to `503.9M/503.8M` (about `1.26%`); cycles fell about
  `2.0--2.4%`. Checksum `33d837ee98745b5d` was unchanged. Long-batch
  Roboto and Amiri controls kept their checksums and effectively neutral
  retired work: Roboto instructions measured `1.24695B/1.24719B` versus
  `1.24716B/1.24746B` for the baseline, and Amiri measured
  `4.67275B/4.67286B` versus `4.67425B/4.67306B`.
- Ligature component traversal now consumes the source stage's whole-run
  no-default-ignorables proof. For LookupFlag-zero runs, physical adjacency is
  already visibility adjacency, so the matcher compares components directly
  while retaining Indic syllable boundaries and source codepoints needed for
  ligature provenance. On fixed CPU 8, five-repeat counters over five complete
  NotoSansDevanagari `hi-words` passes reduced retired instructions from about
  `3.0196B` to `2.9911B` (about `0.94%`), branches from `514.7M` to `508.6M`
  (about `1.19%`), and cycles from `1.258B` to `1.195B` (about `5.0%`). Wall
  time remained frequency-bimodal, so the retained claim is the reduced work.
  HarfBuzz and HarfRust comparisons both pass all 10,000 lines with checksum
  `b01a5388ce792b49`.
- Unicode Script classification now uses a generated, deduplicated Unicode 17
  page table instead of the growing ordered predicate chain. The pinned
  `Scripts.txt` verifier regenerates the committed table byte-for-byte and
  exhaustively checks every assigned scalar for all 174 Script values; this
  also fixes prior whole-block approximations for Common and Inherited
  characters. Fixed-CPU-8 A/B/B/A counters over five full Devanagari
  `hi-words` passes reduced retired instructions from
  `2.99170B/2.99161B` to `2.94292B/2.94291B` (about `1.63%`) and branches
  from `508.83M/508.82M` to `501.77M/501.77M` (about `1.39%`); cycles fell
  from `1.19551B/1.19619B` to `1.18367B/1.17731B` (about `1.3%`). Output
  checksum `33d837ee98745b5d` was unchanged. A same-host seven-sample comparison
  still measured Cangjie near `1.407--1.410 us/glyph` versus HarfBuzz near
  `0.997--1.001 us/glyph`, so the broader shaping-performance objective
  remains open.
- GPOS's exact whole-run coverage prefilter now consumes the dense glyph-to-
  group index already built for compact fonts instead of falling back to its
  hash table while PairPos later used the dense index. A focused regression
  covers direct-index hits and misses. Fixed-CPU-8 A/B/B/A counters over five
  complete Devanagari `hi-words` passes reduced retired instructions from
  `2.94327B/2.94328B` to `2.93909B/2.93905B` (about `0.14%`) and branches
  from `501.82M/501.82M` to `501.14M/501.13M` (about `0.14%`). Cycles fell
  about `3.0%` in this order, but the broader wall-time samples were noisy, so
  only the retired-work reduction is claimed. Corpus checksum
  `33d837ee98745b5d` remained unchanged.
- The Indic shaper now dispatches current-generation Devanagari through a
  compact orchestration path. It omits post-processing stages that are defined
  only for Kannada, Malayalam, Gujarati, Bengali, and Telugu, while sharing the
  exact same lookup plans and Devanagari reorder operations. Non-Malayalam
  scripts also execute `pref` without allocating and clearing the substitution
  provenance sidecars that only Malayalam consumes. The current-HarfBuzz
  corpus gate explicitly excludes one BOT-only Arabic dotted-circle ordering
  row whose expected order is retained against HarfRust; HarfBuzz 14.3 changed
  that isolated behavior from the older reference used when the gate was
  added. Fixed-CPU-8 B/A/A/B
  counters over five complete NotoSansDevanagari `hi-words` passes reduced
  retired instructions from about `2.939B` to `2.928B` (about `0.38%`) and
  branches from `501.1M` to `498.2M` (about `0.58%`); branch misses fell about
  `1.8%`, while wall time remained noisy. Both current HarfBuzz 14.3 and
  HarfRust still pass all 10,000 lines with checksum `b01a5388ce792b49`.
- Indic preparation now skips the canonical-decomposition table walk when a
  `dev2`/`deva` source is wholly inside U+0900..U+097F, a block with no entries
  in the retained split-matra decomposition table. Explicit script overrides
  containing any out-of-block scalar conservatively keep the generic scan.
  Relative to the preceding specialized shaper, fixed-CPU-8 B/A/A/B counters
  over five complete NotoSansDevanagari `hi-words` passes reduced retired
  instructions from about `2.928B` to `2.901B` (about `0.93%`) and branches
  from `498.3M` to `493.2M` (about `1.02%`); cycles improved in both forward
  comparisons. Current HarfBuzz 14.3 and HarfRust parity remain exact for all
  10,000 lines with checksum `b01a5388ce792b49`, and the complete corpus and
  ReleaseFast test gates pass.
- Indic preparation now lends its dotted-circle glyph result to final broken-
  cluster repair when a glyph-index cache owns the immutable font lookup. The
  cacheless path deliberately repeats its mutation-aware validation, preserving
  the public defensive contract. Fixed-CPU-8 B/A/A/B counters over five full
  NotoSansDevanagari `hi-words` passes reduced retired instructions from about
  `2.901B` to `2.898B` (about `0.11%`) and branches from `493.1M` to `492.6M`
  (about `0.10%`); cycles improved in the forward comparison but remained
  frequency-sensitive. The cached glyph-index hit count falls by exactly one
  per source line, while both current HarfBuzz 14.3 and HarfRust retain exact
  10,000-line parity checksum `b01a5388ce792b49`.
- Direct scan conversion now rejects non-finite edge slopes during its single
  preparation pass, so every subpixel-row intersection can rely on finite
  arithmetic instead of repeating two `isFinite` checks in the hot loop. A
  fixed-CPU-8, seven-repeat comparison at 64 px reduced retired instructions
  by about `2.4%` for Roboto `A`, `1.8%` for `g`, `2.0%` for `é`, `1.5%` for
  Amiri `س`, and `2.4%` for `م`; branches fell by about `1.1--3.6%`. All five
  glyphs retained byte-identical output at 1x1, 2x2, 3x3, and 4x4 sampling,
  and a regression test covers finite endpoints whose subtraction overflows
  to a non-finite slope.
- Four-sample difference accumulation now clears each touched cell during the
  mandatory blend scan and clears only the trailing sentinel afterward. This
  removes a second memset traversal over every covered row without changing
  coverage arithmetic. Fixed-CPU-8/30 reverse A/B measurements at 64 px
  reduced retired instructions by about `2.5--3.4%`, branches by about
  `1.2--2.8%`, and cycles by about `1.8--3.5%` across Roboto `A`, `g`, `é` and
  Amiri `س`, `م`. Every glyph retained byte-identical checksums at 1x1, 2x2,
  3x3, and 4x4 sampling; a regression also renders the same dirty span twice
  to prove that no difference or sentinel state leaks between rows.
- Row blending now slices the target and accumulator to the already-computed
  dirty interval and advances both buffers together. This removes repeated
  absolute-coordinate conversion and target-row address arithmetic from every
  covered pixel while preserving max-alpha compositing. Relative to the
  preceding single-pass clear, fixed-CPU-8/30 reverse A/B measurements reduced
  retired instructions by about `2.7--4.0%` and branches by about `4.5--6.1%`
  across Roboto `A`, `g`, `é` and Amiri `س`, `م`; cycles improved in all but
  one near-noise run. All glyph/sampling checksums remained byte-identical.
- Four-sample boundary accumulation now treats pixels bordering a full span as
  one-sided intervals. A left boundary tests only `sample >= start`, a right
  boundary only `sample < end`; only the at-most-two-pixel interval with no
  full pixel retains both predicates. Fixed-CPU-8/30 reverse A/B measurements
  reduced retired instructions by about `2.4--3.5%`, branches by about
  `0.3--1.7%`, and cycles by about `2.2--8.0%` across Roboto `A`, `g`, `é` and
  Amiri `س`, `م`. Exhaustive sample-boundary tests and all real-glyph sampling
  checks retained identical coverage.
- Direct scan conversion now compares already-sorted intersection coordinates
  with a non-negative subtraction when coalescing coincident crossings. This
  removes a redundant absolute-value operation from the innermost winding loop
  without changing its epsilon. Fixed-CPU-8/30 reverse A/B measurements reduced
  retired instructions by about `0.25--1.07%` across Roboto `A`, `g`, `é` and
  Amiri `س`, `م`; branches were neutral. The real-glyph checksum matrix remained
  byte-identical at 1x1, 2x2, 3x3, and 4x4 sampling.
- Direct non-zero scan conversion now expands the common four-distinct-crossing
  case into its three prefix-winding spans. Coincident crossings retain the
  generic epsilon-coalescing loop, while focused tests cover disjoint, nested,
  and reversed contours. Fixed-CPU-8 reverse A/B counters over 100,000 dirty
  renders reduced retired instructions by about `12.1%` for Roboto `A`, `9.9%`
  for `g`, `5.2%` for `é`, `7.5%` for Amiri `س`, and `0.9%` for `م`; branches
  fell about `17.1%`, `14.2%`, `8.0%`, `11.1%`, and `2.3%`, respectively.
  Cycles improved for four glyphs and were frequency-sensitive for `م`; all
  five glyphs retained byte-identical output at 1×1 through 4×4 sampling.
- The four-crossing path now uses the edge invariant that each crossing changes
  winding by exactly one: after the first and third crossings the winding is
  odd and cannot be zero, so only the middle span needs a runtime winding test.
  Relative to the initial four-crossing specialization, fixed-CPU-8 reverse
  A/B counters reduced retired instructions by about `0.9%` for Roboto `A`,
  `0.7%` for `g`, `0.4%` for `é`, `0.5%` for Amiri `س`, and `0.1%` for `م`;
  branches fell about `2.1%`, `1.7%`, `0.9%`, `1.3%`, and `0.3%`. Output
  remained byte-identical across the complete five-glyph sampling matrix.
- The four-item sorting network now compares opposite pairs before ordering
  the two halves. It remains the same optimal five-comparator network, but the
  input-correlated branch order avoids the previous final-swap register churn.
  Fixed-CPU-8 reverse A/B counters over 100,000 dirty renders reduced retired
  instructions by about `2.0%` for Roboto `A`, `0.1%` for `g`/`é`, `0.9%` for
  Amiri `س`, and was neutral for `م`; branches fell about `1.1%`, `0.2%`,
  `0.2%`, `0.4%`, and `0.1%`. An exhaustive permutation test and the five-
  glyph 1×1--4×4 matrix retained byte-identical ordering and rendered output.
- Four-crossing middle-span selection now compares the first two edge deltas
  directly. Prepared fill edges always contribute exactly `+1` or `-1`, making
  equality equivalent to a non-zero two-edge prefix winding without integer
  promotion and addition. Fixed-CPU-8 reverse A/B counters over 100,000 dirty
  renders reduced retired instructions by about `0.3%` for Roboto `A`/`g`,
  `0.2%` for `é`/Amiri `س`, and `0.04%` for `م`; branches were effectively
  neutral and cycles remained frequency-sensitive. The five-glyph 1×1--4×4
  output matrix remained byte-identical.
- Default 4×4 span accumulation now maps each finite endpoint once to the
  global sequence of quarter-pixel sample indexes. Quotient and remainder then
  identify the two boundary counts and the intervening full-pixel range,
  replacing four floor/ceil conversions and boundary predicate vectors. A
  conservative coordinate guard retains the former f64 path beyond the range
  where f32 represents every 1/8-pixel sample center. Fixed-CPU-8 reverse A/B
  counters over 100,000 dirty renders reduced retired instructions by about
  `5.4%` for Roboto `A`, `4.3%` for `g`, `3.9%` for `é`, `3.9%` for Amiri `س`,
  and `4.2%` for `م`; branches fell about `1.5%`, `0.3%`, `0.5%`, `0.5%`, and
  `0.5%`. Cycles improved for four glyphs and were slightly noisy for `g`.
  Expanded threshold tests and the five-glyph 1×1--4×4 matrix retained
  byte-identical coverage.
- The bounded quarter-sample path now stays in f32/i32 after its exact-range
  guard instead of widening endpoints and sample indexes to f64/i64. Fixed-
  CPU-8 reverse A/B counters over 100,000 dirty renders reduced retired
  instructions by about `2.0%` for Roboto `A`, `1.6%` for `g`, `1.1%` for `é`,
  `1.2%` for Amiri `س`, and `0.4%` for `م`; branches were neutral to `0.2%`
  lower. The expanded boundary test and five-glyph 1×1--4×4 matrix remained
  byte-identical.
- Non-negative quarter-sample indexes now use an unsigned representation for
  their pixel quotient and in-pixel remainder. This lets code generation use
  shifts and masks directly instead of preserving signed division semantics
  that cannot occur after target clipping. Fixed-CPU-8 reverse A/B counters
  over 100,000 dirty renders reduced retired instructions by about `2.3%` for
  Roboto `A`, `1.8%` for `g`, `1.6%` for `é`/Amiri `س`, and `1.8%` for `م`;
  branches were neutral. The five-glyph 1×1--4×4 output matrix remained byte-
  identical.
- Prepared fill edges now anchor x at their lower y endpoint. This removes the
  redundant original endpoint-y field, reduces each active edge from 24 to 20
  bytes, and preserves the same subtract/multiply/add intersection arithmetic
  for either source direction. Fixed-CPU-8 reverse A/B counters over 100,000
  dirty renders reduced retired instructions by about `0.7%` for Roboto `A`,
  `0.8%` for `g`, `0.7%` for `é`, `0.6%` for Amiri `س`, and `0.7%` for `م`;
  branches fell up to `1.1%`. Cycles were frequency-sensitive, so only retired
  work is claimed. Directional anchor tests and the five-glyph 1×1--4×4 matrix
  retained byte-identical intersections and rendered output.
- Equally spaced quadratic and cubic flattening now advances points with
  second- and third-order forward differences instead of rebuilding Bernstein
  bases and dividing for every interior segment. The adaptive segment count is
  unchanged and each authored endpoint is assigned exactly to prevent contour-
  join drift. Fixed-CPU-8 reverse A/B counters over 100,000 dirty renders
  reduced retired instructions by about `0.9%` for Roboto `g`, `0.9%` for `é`,
  `1.2%` for Amiri `س`, and `0.8%` for `م`, while straight-sided Roboto `A` was
  neutral. Branches fell about `0.5--0.7%` on curved glyphs. Point-error tests
  and the five-glyph 1×1--4×4 matrix retained byte-identical rendered output.
- Prepared 4×4 coverage rendering now slices each immutable cached row and the
  clipped target row once, then advances both buffers together. This removes
  repeated source/target index reconstruction from every cached pixel while
  retaining transparent holes, clipping, and max-alpha blending. Fixed-CPU-8
  reverse A/B measurements reduced prepared-raster retired instructions by
  about `12.6--28.3%`, branches by about `12.7--22.9%`, and cycles by about
  `6.8--18.5%` across Roboto `A`, `g`, `é` and Amiri `س`, `م`; direct/prepared
  output remained byte-identical.
- Prepared cached-row blending now writes `max(existing, lut[count])` for every
  pixel in the clipped dirty slice. Because `lut[0]` is transparent, internal
  contour holes need no data-dependent branch. Relative to the row-slice
  baseline, fixed-CPU-8 reverse A/B measurements reduced prepared-raster
  instructions by about `1.3--8.2%`, branches by about `18.8--44.8%`, and
  cycles by about `2.8--8.0%` across the same Roboto/Amiri glyph matrix, with
  byte-identical direct/prepared output.
- Prepared coverage construction now consumes its already-sorted finite
  intersections with a non-negative epsilon difference and clears difference
  cells while resolving each row, leaving only the trailing sentinel to reset.
  This removes an absolute value and a second dirty-span clear during outline
  preparation. A fixed-CPU-8, 10,000-preparation A/B reduced retired
  instructions by about `2.3--3.1%`, branches by about `1.9--2.8%`, and cycles
  by about `1.1--7.8%` for Roboto `A`, `g` and Amiri `س`, with unchanged cached
  coverage and rendered output.
- Prepared coverage construction now uses the direct rasterizer's quarter-
  sample endpoint representation inside the exact f32 coordinate range, while
  preserving the scalar/f64 fallback for extreme negative or positive bounds.
  The new `raster-prepare` gate on fixed CPU 8, over 20,000 prepare/deinit
  iterations, reduced retired instructions by about `9.6%` for Roboto `A`,
  `7.0%` for `g`, `6.8%` for `é`, `6.3%` for Amiri `س`, and `7.5%` for `م`;
  branches fell about `7.3%`, `5.4%`, `5.0%`, `4.9%`, and `5.3%`. Expanded
  negative-coordinate threshold tests and the prepared-render glyph matrix
  retained byte-identical coverage.
- Prepared quarter-sample indexes now add a fixed exact-range bias and use
  unsigned shifts/masks for pixel quotient and remainder. This preserves floor
  semantics for negative raw glyph bounds without i64 floor-division machinery.
  Fixed-CPU-8 reverse A/B `raster-prepare` counters over 20,000 preparations
  reduced retired instructions by about `2.3%` for Roboto `A`, `1.6%` for `g`/
  `é`, `1.5%` for Amiri `س`, and `1.9%` for `م`; branches were neutral. Cycles
  improved in both candidate passes for all five glyphs, and prepared-render
  checksums remained byte-identical.
- Dense prepared coverage is now generated directly from the sorted prepared
  edges in one row pass. The ordinary path no longer allocates, fills, and then
  frees a complete intermediate sample-row/intersection cache; geometry that
  exceeds the dense-cache cap still builds and retains exactly that fallback.
  Fixed-CPU-8 reverse A/B `raster-prepare` counters over 20,000 preparations
  reduced retired instructions by about `8.1%` for Roboto `A`, `5.4%` for `g`,
  `11.5%` for `é`, `5.0%` for Amiri `س`, and `15.5%` for `م`; branches fell
  about `11.5%`, `8.0%`, `13.7%`, `7.4%`, and `17.4%`. Construction and
  prepared-render checksums remained identical across all five glyphs.
- Successful dense prepared coverage now releases the larger intermediate
  sample-row/intersection cache instead of retaining two equivalent immutable
  render representations for the lifetime of a prepared glyph. Oversized or
  hostile geometry that declines the bounded dense cache keeps and exercises
  the sorted-sample fallback. Focused lifecycle tests cover both ownership
  outcomes; rendered output is unchanged.
- Glyph benchmarking now exposes `raster-prepare`, which decodes the outline
  once and times only repeated flatten/edge/cache construction plus teardown.
  This separates prepared-glyph construction from `raster-prepared`'s cached
  draw loop and provides a stable fixed-CPU gate for future cache-building
  changes. The mode rejects FreeType comparison and dirty-rectangle accounting
  because neither has an equivalent preparation-only contract.
- Dense prepared coverage now packs each row's dirty interval contiguously
  instead of retaining the complete rectangular zero-padded bitmap. An 8-byte
  row record carries the packed offset and x interval, so clipped draws no
  longer reconstruct a full-width source stride and prepared glyphs retain no
  leading, trailing, or empty-row pixels. Fixed-CPU-8 reverse A/B counters over
  200,000 dirty prepared draws reduced retired instructions by about
  `1.2--2.2%` for Roboto `A`, `g`, `é` and Amiri `س`, `م`; branches were
  neutral. Cycles improved for Roboto `g`/`é` and were noisy or near neutral
  elsewhere. Direct checksums remained byte-identical at 1×1, 2×2, 3×3, and
  4×4 sampling, and direct/prepared output remained identical at 4×4.
- Dense prepared coverage now stores final 8-bit alpha values instead of the
  intermediate `0..16` sample counts. Construction performs the 17-entry LUT
  lookup once, so every repeated draw directly max-blends cached bytes without
  another indexed load. Fixed-CPU-8 reverse A/B counters over 200,000 prepared
  draws reduced retired instructions by about `6.3%` for Roboto `A`, `6.5%`
  for `g`, `5.3%` for `é`, `6.3%` for Amiri `س`, and `3.3%` for `م`; branches
  were neutral. Prepared-render checksums remained byte-identical for all five
  glyphs.
- GSUB run-state preparation is now inlined into its small set of whole-run and
  cached-plan callers. This removes an out-of-line call and large by-value
  `Options` return at each Indic feature stage while preserving the shared
  mutation epoch and operation limits. Fixed-CPU-8 seven-repeat counters over
  five NotoSansDevanagari `hi-words` passes reduced retired instructions by
  about `1.47%` and branches by about `1.73%`; fixed-CPU-30 reproduced about
  `1.47%` and `1.74%`. Amiri `fa-words` also reduced instructions by about
  `4.2%` and branches by about `5.4%` on both cores, while Roboto stayed within
  `0.03%`. All corpus checksums remained unchanged.
- The cached-plan/ranged-feature bridge now inlines its ordinary empty-range
  branch, allowing Indic stages to enter the already-proven plan executor
  without another large by-value context/options boundary. Against the
  preceding state-preparation optimization, fixed-CPU-8 reverse B/A/A/B
  counters over NotoSansDevanagari `hi-words` reduced retired instructions by
  about `0.70%`, branches by about `1.12%`, and cycles by about `1.2%`; Roboto
  and Amiri retired work remained within `0.02%`. The feature-range path keeps
  its existing per-entry value materialization and all corpus checksums remain
  unchanged.
- Generic GSUB fallback now reuses an exact validated accelerator sidecar as
  proof of the fixed Lookup header, including class-chaining lookups whose
  payload execution intentionally remains in the generic dispatcher. Detached,
  stale, and cacheless tables still run the complete header validator. Relative
  to the preceding state, fixed-CPU-8/30 counters over five complete
  NotoSansDevanagari `hi-words` passes reduced retired instructions by about
  `0.45%` and branches by about `0.37%`; Amiri `fa-words` improved about
  `0.4--0.5%` in both counters, and Roboto remained within `0.02%`. Current
  HarfBuzz 14.3 and HarfRust parity remain exact for the 10,000-line corpus.
- The same generic fallback now treats a validated table plus its complete
  lookup-accelerator array as a table-wide fixed-header proof. Accelerator
  construction validates every LookupList header, so payload-capability misses
  no longer need a second lookup-specific identity probe; cacheless callers
  still run the full validator. Relative to the preceding exact-sidecar check,
  fixed-CPU-8 counters reduced Devanagari `hi-words` instructions by about
  `0.41%` and branches by about `0.31%`, and Amiri `fa-words` by about `0.37%`
  and `0.28%`; CPU-30 reproduced the improvements. Roboto retired work stayed
  within `0.02%`, and all output checksums were unchanged.
- Chaining-class region discovery now consumes the existing whole-run proof
  that the immutable source contains no default-ignorable scalars. With a zero
  LookupFlag, adjacent physical glyphs are therefore adjacent contextual
  glyphs; the specialized forward, lookahead, and backtrack traversals retain
  Indic syllable-boundary checks while skipping per-glyph LookupFlag and
  Unicode visibility classification. Fixed-CPU-8 reverse A/B/B/A counters over
  five complete NotoSansDevanagari `hi-words` passes reduced retired
  instructions by about `0.13%` and branches by about `0.10%`; fixed CPU 30
  reproduced both reductions. Roboto `en-words` and Amiri `fa-words` controls
  remained within `0.002%` retired work, and the complete corpus gate plus
  direct 10,000-line HarfBuzz/HarfRust comparisons retained checksum
  `b01a5388ce792b49`.
- Accelerator-backed ContextSubst and ChainContextSubst class matchers now use
  a trusted first-glyph index probe. The builders already guarantee that this
  compact index is the final `classes` region, has a recognized encoding, and
  references a live rule group; the public defensive probe remains available
  for independently supplied data. Relative to the preceding chaining-window
  optimization, fixed-CPU-8 and fixed-CPU-30 counters over five complete
  NotoSansDevanagari `hi-words` passes reduced retired instructions by about
  `0.47%` and branches by about `0.73%`. Roboto `en-words` and Amiri `fa-words`
  controls remained within `0.01%` retired work.
- Compact first-glyph class indexes now select a dense direct map when a glyph
  span is smaller than the corresponding sorted and hash encodings. This turns
  NotoSansDevanagari's consecutive 12-glyph ContextSubst group into one bounds
  check and array load while its sparse chaining groups retain the hash form.
  Relative to the trusted-index baseline, fixed-CPU-8 and fixed-CPU-30 counters
  over five complete `hi-words` passes reduced retired instructions by about
  `0.13%` and branches by about `0.09%`; Roboto and Amiri controls remained
  within `0.003%` retired work.
- Trusted class-index probes now return a borrowed `RuleGroup` rather than a
  roughly 32-byte value copy. The defensive public probe keeps its value-return
  contract, while the two accelerator executors retain the group in its owned
  sidecar for the complete match. Fixed-CPU-30 reverse A/B/B/A counters over
  five complete Devanagari `hi-words` passes reduced retired instructions by
  about `0.02%` and branches by about `0.13%`; CPU 8 reproduced the branch
  reduction. Roboto and Amiri controls remained within `0.01%` retired work.
- Whole-lookup class-context scans now probe the compact first-glyph index
  before entering the large per-position matcher and lend the selected
  `RuleGroup` across that boundary. This rejects misses before constructing
  matcher state and avoids a duplicate index probe for hits, while nested
  single-position entry points keep their existing checks. Fixed-CPU-8/30
  reverse A/B measurements over five complete Devanagari `hi-words` passes
  reduced retired instructions by about `2.26%` and branches by about `1.61%`.
  Roboto remained within `0.01%` retired work; Amiri instructions/branches
  improved about `0.07%`/`0.03%`.
- Cached staged GSUB plans now omit absent features whose selected lookup list
  is empty. Such entries have no observable execution but previously rebuilt
  per-entry `Options` and entered shared dispatch for every source run. Fixed-
  CPU-8 reverse A/B counters over five complete corpus passes reduced retired
  instructions by about `0.69%` for NotoSansDevanagari `hi-words` and `0.69%`
  for Amiri `fa-words`, with branches down about `0.20%` and `0.16%`; Roboto
  `en-words` stayed within `0.02%`. Current HarfBuzz parity remains exact on
  all 10,000 Devanagari lines with checksum `b01a5388ce792b49`.
- ChainContextSubst format-2 matching now uses a compact physical-adjacency
  window when a zero LookupFlag and the source-run proof establish that no
  default-ignorable glyph can intervene. It computes input, backtrack, and
  lookahead positions arithmetically while preserving source-syllable bounds;
  filtered and default-ignorable runs retain the lazy skip-aware window. A
  focused reversed-backtrack regression covers the direct-index ordering.
  Fixed-CPU-8 A/B/B/A counters over five complete NotoSansDevanagari
  `hi-words` passes reduced retired instructions by about `0.58%` and branches
  by about `0.56%`. Roboto `en-words` and Amiri `fa-words` controls improved
  about `0.1%` in retired instructions with unchanged checksums. The full
  ReleaseFast suite and shaping parity umbrella pass, including exact
  HarfBuzz parity for all 10,000 Devanagari lines with checksum
  `b01a5388ce792b49`.
- Accelerated LigatureSubst scanning now applies its existing first-component
  digest before source-feature and LookupFlag eligibility checks. The digest is
  a permissive necessary condition, so every possible hit still reaches those
  authoritative filters and the exact LigatureSet index. Fixed-CPU-8 reverse
  A/B counters over five complete NotoSansDevanagari `hi-words` passes reduced
  retired instructions by about `0.8%` and branches by about `1.0%`; Roboto
  `en-words` and Amiri `fa-words` also improved slightly in both counters. All
  corpus checksums were unchanged.
- Contextual forward-prefix collection now consumes the same zero-LookupFlag,
  no-default-ignorables proof as the specialized chaining traversal. Physical
  glyphs are then the contextual sequence, so it writes adjacent indexes while
  retaining source-syllable boundaries instead of running the general Unicode
  visibility predicate for every component. Focused tests cover both bounded
  Indic syllables and unrestricted runs. Fixed-CPU-8 A/B/B/A counters over five
  complete Devanagari `hi-words` passes reduced retired instructions by about
  `0.72%` and branches by about `0.72%`; Roboto `en-words` and Amiri `fa-words`
  also improved slightly. The complete ReleaseFast suite and shaping parity
  umbrella pass unchanged.
- The unfiltered ChainContextSubst format-2 fast path now compares adjacent
  backtrack, input, and lookahead classes directly and materializes its three
  bounded index arrays only after a rule matches. This removes the former
  `SimpleWindow`/`SimpleRegions` wrapper state while retaining reversed
  backtrack order and source-syllable checks. Fixed-CPU-8 A/B/B/A counters
  over five complete Devanagari `hi-words` passes reduced retired instructions
  by about `0.74%` and branches by about `0.72%`; Amiri `fa-words` improved
  about `0.15%` in both counters, and Roboto `en-words` remained effectively
  neutral. The complete ReleaseFast suite and shaping parity umbrella pass
  unchanged.
- Validated accelerated GSUB dispatch now selects a separate unprofiled
  executor before crossing its noinline boundary. Ordinary shaping therefore
  carries neither lookup timestamps/count snapshots nor per-lookup recording
  calls; `--profile-fast-path` retains the original instrumented executor and
  its static nested binding. Fixed-CPU-8 reverse A/B counters over five corpus
  passes reduced retired instructions by about `2.5%` for Devanagari
  `hi-words`, `2.0%` for Roboto `en-words`, and `3.9%` for Amiri `fa-words`;
  branches also fell about `0.7%`, `1.0%`, and `0.9%`. The full ReleaseFast
  suite, benchmark smoke gate, and shaping parity umbrella pass unchanged.
- Accelerated GSUB now branches to that unprofiled executor immediately after
  validating the sidecar identity, before computing timestamps, glyph-count
  snapshots, or lookup-specific option overrides. The profiled path remains
  unchanged and a focused fast-profile test exercises its static nested
  dispatch. Relative to the first unprofiled split, fixed-CPU-8 reverse A/B
  counters over five corpus passes further reduced retired instructions by
  about `0.43%` for Devanagari `hi-words`, `0.29%` for Roboto `en-words`, and
  `0.68%` for Amiri `fa-words`; branches fell about `0.43%`, `0.28%`, and
  `0.70%`. The full ReleaseFast suite, benchmark smoke gate, and shaping
  parity umbrella pass unchanged.
- Current-generation Devanagari source marking now uses a dedicated `dev2`
  category path. It shares the specialized syllable scanner, omits the
  Malayalam-only `pref` source pass, and evaluates reph/half candidates with
  compact Devanagari predicates instead of repeatedly entering the all-Indic
  script switches. An exhaustive three-codepoint representative differential
  retains the generic marker as its oracle. Fixed-CPU-8 reverse A/B counters
  over five complete `hi-words` passes reduced retired instructions by about
  `1.05%` and branches by about `2.1%`; Roboto `en-words` and Amiri `fa-words`
  controls remained within about `0.03%`. The full ReleaseFast suite,
  benchmark smoke gate, and shaping parity umbrella pass unchanged.
- The production-only accelerated GSUB executor is now inlined into its small
  caller. This lets the optimizer specialize the lookup-kind dispatch together
  with already-resolved source/LookupFlag options, while the instrumented
  executor remains out of line for profiling. Fixed-CPU-8 reverse A/B counters
  over five corpus passes reduced retired instructions by about `3.1%` for
  Devanagari `hi-words`, `1.1%` for Roboto `en-words`, and `3.1%` for Amiri
  `fa-words`; fixed E-core CPU 30 reproduced about `3.1%` for Devanagari.
  Branches fell about `3.2%`, `0.6%`, and `2.4%`, respectively. The complete
  ReleaseFast suite, benchmark smoke gate, and shaping parity umbrella pass
  unchanged.
- Source population now decodes scalars through a compact out-of-line decoder
  after the public shaping boundary has validated the complete UTF-8 input.
  This removes the standard iterator's redundant per-scalar length and decode
  calls without weakening malformed-input rejection, and a boundary-value
  differential covers all UTF-8 widths against `std.unicode.utf8Decode`. On
  fixed CPU 8/30 reverse A/B runs over complete corpora, retired instructions
  fell about `0.78%` for Devanagari `hi-words` and `0.29%` for Amiri
  `fa-words`; Roboto `en-words`, which is almost entirely handled by the
  existing ASCII path, remained within `0.04%`. Branches also fell about
  `0.40%` and `0.13%` for the two non-ASCII corpora. The full ReleaseFast
  suite, benchmark smoke gate, and shaping parity umbrella pass unchanged,
  including all 10,000 Devanagari lines with checksum `b01a5388ce792b49`.
- Modern Devanagari post-GSUB reordering now consumes the source-syllable
  serial map that the shaper already built. Dedicated pre-base-matra, `init`
  marking, and reph paths avoid repeatedly recovering syllable boundaries and
  dispatching all-Indic character predicates; generic and legacy Indic scripts
  retain their former routines. Fixed-CPU-8/30 reverse A/B counters over full
  `hi-words` runs reduced retired instructions by about `3.5%`, branches by
  about `5.8%`, and cycles by about `1.9--3.9%`. Roboto and Amiri retired work
  remained within `0.01%`; their cycle variation was within about `1%`. Exact
  HarfBuzz parity remains unchanged on all 10,000 Devanagari lines with
  checksum `b01a5388ce792b49`.
- The same `dev2` split now covers broken-cluster dotted-circle insertion and
  placeholder/dependent-mark cluster merging. Fixed Devanagari predicates
  replace the generic all-Indic category/virama dispatch, while every other
  script retains its existing implementation. Fixed-CPU-8/30 reverse A/B
  counters over complete `hi-words` passes reduced retired instructions by
  about `1.28%`, branches by about `2.10%`, and cycles by about `1.5%`.
  Roboto and Amiri retired work remained within `0.02%`; the full 10,000-line
  HarfBuzz comparison still passes with checksum `b01a5388ce792b49`.
- Cached staged GSUB plans now enter a dedicated unprofiled executor when the
  run has neither disabled JSTF lookups nor a profiling sink. The plan already
  owns concrete LookupList indexes and validated offsets, so this boundary
  avoids rebuilding the optional/profiling wrapper on every staged lookup while
  preserving the generic fallback for unsupported sidecars. Fixed-CPU-8/30
  reverse A/B counters reduced Devanagari `hi-words` retired instructions by
  about `3.0%`, branches by about `2.6%`, and cycles by `1.0--1.8%`; Amiri
  `fa-words` improved about `0.75%`/`0.69%` in instructions/branches, while
  Roboto remained neutral. The complete Devanagari HarfBuzz corpus still
  passes with checksum `b01a5388ce792b49`.
- The dedicated modern-Devanagari finishing path no longer repeats the generic
  script-shaper metadata scan after the immediately preceding generic GSUB pass
  proved every glyph-parallel sidecar. Its dotted-circle preparation maintains
  those sidecars atomically and its source maps are resized to the exact source
  length before staged GSUB; generic Indic entry points retain the defensive
  validation. Fixed-CPU-8/30 reverse A/B counters over five complete `hi-words`
  passes reduced retired instructions by about `1.3%`, branches by about
  `1.7%`, and E-core cycles by about `2.2%`; Roboto and Amiri controls were
  neutral because they do not enter this path. The full 10,000-line checksum
  remains `b01a5388ce792b49`.
- Internal shaping now enters GPOS through an after-run-proof boundary once it
  has maintained the source/provenance sidecars through GSUB and validated the
  final glyph ids. Public and detached GPOS callers retain complete metadata
  validation, while the owned pipeline no longer rescans every glyph and
  ligature component before positioning. Fixed-
  CPU-8/30 reverse A/B counters reduced retired instructions by about `0.75%`
  for Devanagari `hi-words`, `1.8--1.9%` for Roboto `en-words`, and `0.4%` for
  Amiri `fa-words`; branches fell about `1.0%`, `2.7--2.8%`, and `0.5%`,
  respectively. E-core cycles improved about `2.1%`, `8.0%`, and `1.2%`; all
  corpus checksums remained unchanged.
- Validated GPOS accelerator sidecars now explicitly retain the already-
  resolved LookupList offset. Cached shaping therefore avoids decoding and
  bounds-checking the same Offset16 before every selected lookup, while
  hand-constructed and detached sidecars default to the existing defensive
  resolution path. Fixed-CPU-8/30 reverse A/B counters reduced retired
  instructions by about `0.3%` for Devanagari, `0.1%` for Roboto, and `0.18%`
  for Amiri; branches fell about `0.6%`, `0.1%`, and `0.36%`, respectively.
  E-core cycles improved about `0.45%` for Devanagari and remained within run
  noise for the controls; all corpus checksums were unchanged.
- Source population now rejects non-starters before entering the font-aware
  Arabic canonical-composition lookahead. Only six Unicode scalars can begin
  one of these pairs, so Devanagari, Latin, and ordinary Arabic sources avoid
  an out-of-line call while the helper retains its own defensive guard. Fixed-
  CPU-30 A/B/B/A counters over ten complete corpus passes reduced retired
  instructions by about `0.91%` for Devanagari `hi-words`, `0.31%` for Roboto
  `en-words`, and `0.42%` for Amiri `fa-words`; branches fell about `1.05%`,
  `0.12%`, and `0.54%`, respectively. Cycles were neutral for Devanagari and
  improved slightly for Roboto; Amiri cycle variation remained noisy.
- Segment positioning now derives the effective shaping direction once from
  the already-computed native-direction decision and reuses it for JSTF,
  `stch`, and final reversal. This avoids repeating the Unicode script-direction
  resolution several times per run. Fixed-CPU-30 A/B/B/A counters over five
  complete corpus passes reduced retired instructions by about `0.11%` for
  Devanagari, `0.10%` for Roboto, and `0.28%` for Amiri; cycles improved about
  `0.96%`, `1.1%`, and `0.29%`, respectively, with unchanged output.
- Accelerator-backed class ContextSubst and ChainContextSubst now probe their
  exact first-glyph index before consulting source-scope and LookupFlag
  metadata. Most run glyphs have no rule group at all, so the hot miss path no
  longer pays the more expensive filtering predicates. Fixed-CPU-30 A/B/B/A
  counters over 200 complete NotoSansDevanagari `hi-words` passes reduced
  retired instructions by about `1.83%`, branches by about `2.45%`, and cycles
  by about `1.64%`; 11-sample medians improved by roughly `1.3--1.7%`. Roboto
  `en-words` and Amiri `fa-words` retired work remained within `0.01%`, and all
  shaping checksums were unchanged.
- Syllable-scoped coverage ContextSubst now applies the same exact-first-
  coverage rejection before source-syllable and GDEF filtering. Unscoped
  scripts retain their prior branch layout. Fixed-CPU-30 A/B/B/A counters over
  200 complete NotoSansDevanagari `hi-words` passes reduced retired
  instructions by about `1.72%`, branches by about `2.04%`, branch misses by
  about `1.5%`, and cycles by about `1.4%`; 11-sample medians improved by
  roughly `1.1--1.3%`. Roboto and Amiri retired-work controls remained within
  `0.02%`, and all checksums were unchanged.
- Cached GSUB plans whose sidecars share the plan's construction proof no
  longer decode LookupList solely to recover a defensive lookup count. Their
  per-lookup bounds checks are debug ownership assertions, while detached plans
  retain the runtime count and errors. Fixed-CPU-30 A/B/B/A counters over 200
  NotoSansDevanagari `hi-words` passes reduced retired instructions by about
  `0.86%`, branches by about `1.09%`, and cycles by about `0.5%`. Roboto stayed
  instruction-neutral, Amiri improved about `0.08%`, and checksums were
  unchanged.
- Direct scan conversion now dispatches the common two-active-edge row once,
  outside the subpixel loop, instead of retesting that invariant for all four
  vertical samples. Fixed-CPU-30 A/B/B/A counters over 20,000 direct dirty
  renders reduced branches by about `1.2%` for Roboto 64 px `A`, `1.6%` for
  `g`, and `0.2%` for `é`; cycles improved by about `0.1%`, `1.0%`, and
  `1.6%`, respectively. The `A` retired-instruction count fell about `0.28%`;
  the more complex controls traded roughly `0.1--0.7%` more instructions for
  fewer branches and cycles. CPU-8 counters reproduced the `A` and `é` cycle
  gains while `g` remained frequency-noisy. Roboto and Amiri five-glyph wall
  probes improved or remained neutral, and all target checksums stayed byte-
  identical.
- The fused direct edge-preparation pass now accumulates finite floating-point
  extrema and performs saturating floor/ceil conversion only for the final four
  bounds. Previously it converted both endpoints of every edge even though the
  same pass had already proved them finite. Relative to the two-edge baseline,
  fixed-CPU-30 A/B/B/A counters over 20,000 direct dirty renders reduced
  retired instructions by about `0.31%` for Roboto 64 px `A`, `0.20%` for
  `g`, and `0.06%` for `é`; cycles improved about `1.1%`, `1.0%`, and
  `0.7%`. Amiri `س` improved in wall probes while the simpler `م` control
  remained within noise. All five target checksums stayed byte-identical.
- Direct 4×4 scan conversion now keeps 128 pixels of signed row-difference
  scratch inline instead of reserving 512 pixels on every call; wider glyphs
  retain the existing allocator-backed path. Fixed-CPU-30 A/B/B/A counters over
  20,000 dirty renders kept retired work neutral while slightly reducing cycles
  and instruction-cache misses for the retained Roboto `A`, `g`, and `é`
  matrix. The complete raster checksum matrix is unchanged.
- The fused direct edge-preparation pass now retains floating-point extrema
  and performs saturating floor/ceil conversion only for its final four
  bounds. This restores the cheaper conversion policy inside the fused path
  instead of converting both endpoints of every edge. Fixed-CPU-30 A/B/B/A
  counters over 200,000 Roboto 64 px direct dirty renders reduced retired
  instructions by about `3.2%` for `g` and `3.9%` for `é`, branches by about
  `6.2%` and `7.7%`, and cycles by about `4.4%` and `3.4%`; `A` remained
  frequency-sensitive and did not regress consistently. Checksums stayed
  byte-identical.
- Four-sample row blending now includes zero-coverage pixels in the same
  branchless max/LUT loop. The zero LUT entry preserves exact compositing while
  allowing LLVM to eliminate a data-dependent branch for every pixel in the
  dirty span. Fixed-CPU-30 A/B/B/A counters over 200,000 Roboto 64 px direct
  dirty renders reduced branches by about `9--11%` and cycles by about
  `1.4--2.4%` for `A`, `g`, and `é`. Retired instructions improved about
  `1.2%` for `é`, stayed near-neutral for `g`, and traded about `0.6%` more for
  `A`; all target checksums remained byte-identical.
- Scanline edge intersections now use an explicit fused multiply-add. This
  preserves the exact single-rounding result already selected by ReleaseFast
  while making that hot arithmetic contract independent of optimizer pattern
  recognition. Fixed-CPU-30 A/B/B/A counters over 200,000 Roboto 64 px direct
  dirty renders reduced retired instructions by about `0.14%` for `A`, `0.03%`
  for `g`, and `0.20%` for `é`; cycles improved about `1.5%`, remained neutral,
  and improved about `1.2%`, respectively. Checksums remained byte-identical.
- Four-intersection rows belonging to complex active-edge sets now use
  insertion sorting instead of the fixed five-comparator network. Their edge
  order is strongly correlated across adjacent sample rows, so this path often
  finishes after the three already-sorted comparisons while simple contours
  retain the compact network. Fixed-CPU-30 A/B/B/A counters over 200,000
  Roboto 64 px direct dirty renders reduced branches by about `1.65%` for `g`
  and `0.9%` for `é`, and cycles by about `3.1%` and `2.0%`; `A` stayed on the
  former path. Checksums remained byte-identical.
- The complex four-intersection path now folds its ordered span results into
  row dirty bounds once per subpixel sample rather than after every occupied
  span. Fixed-CPU-30 A/B/B/A counters over 200,000 Roboto 64 px direct dirty
  renders reduced retired instructions by about `1.2%` for `A`, `1.2%` for
  `g`, and `0.4%` for `é`; branches fell about `0.02%`, `2.9%`, and `2.0%`,
  respectively. Cycles improved about `1.8--2.8%` with byte-identical output.
- Quantized 4×4 spans now merge adjacent boundary/full-range difference deltas
  before writing row scratch. The common partial/full/partial span therefore
  touches four transition slots instead of issuing three separate range
  updates with six endpoint writes. Fixed-CPU-30 A/B/B/A counters over 200,000
  Roboto 64 px direct dirty renders reduced branches by about `2.5%` for `A`,
  `3.0%` for `g`, and `1.7%` for `é`; cycles improved about `2.3%`, `3.0%`,
  and `0.7%`, respectively, with byte-identical output.
- Generic shaping normalization now preserves supported precomposed cmap
  glyphs, decomposes missing scalars through the shortest supported canonical
  chain, and falls back to recursive NFD when necessary. The generated Unicode
  17 table includes both direct and recursive canonical mappings while retaining
  the former mark-leading USE view. Generic scripts now also synthesize late
  zero-width Mn behavior when GDEF classes are absent. The HarfRust fuzz
  regression `PT_Sans-Caption-Web-Regular.ttf` with `U+1EA4 U+006E` matches
  HarfBuzz 14.3.0 and HarfRust exactly: glyph ids `132,609,81`, advances
  `645,0,641`, and comparison checksum `ee69c47f6c0d1b83`. Synthetic tests cover
  direct decomposition, recursive-NFD fallback, singleton canonical mappings,
  original UTF-8 spans, and zero-width decomposed marks.
- Contextual GSUB now distinguishes input-iterator and context-iterator joiner
  policy exactly: `auto_zwj=false` keeps ZWJ visible as authored input, while
  lookbehind/lookahead still skips an untouched ZWJ. This closes HarfRust's
  upstream Sinhala fuzz regression
  `U+0DC1 U+200D U+0DCA U+200D U+0DBB U+0DD3`.
- Generic mark zeroing now follows the default-shaper policy for Thai and Lao
  while preserving the explicit no-zeroing policies for Indic, Khmer, Hangul,
  and Myanmar Zawgyi. This restores all four retained Thai
  `zero-width-marks.tests` cases and keeps the Zawgyi authored-advance control
  unchanged.
- MultipleSubst output now retains HarfBuzz's MarkLig component semantics: its
  first piece may act as the attachment base but, without a real ligature id,
  selects the last component anchor. The Rasa Gujarati fuzz row
  `U+0A93 U+0ABC` now matches HarfBuzz 14.3.0 and HarfRust with glyph ids
  `5,22,21`, advances `982,0,0`, offsets `0,-1,0`, and checksum
  `993f2b76f17eda72`. All nine upstream HarfRust `tests/custom/fuzzer.tests`
  rows are retained as `shaping-corpus-parity-smoke` HarfRust gates.
- Broad PairPos format 1 tables now retain a dense first-glyph-to-PairSet
  range beside their compact native records. The hot lookup therefore binary
  searches only the selected first glyph's second-glyph records instead of the
  complete 11,509-record Roboto kerning table; small or excessively sparse
  tables keep the compact global search. Fixed-CPU-30 A/B/B/A counters over
  twenty complete `en-words` passes reduced Roboto retired instructions by
  about `4.6%`, branches by `5.9%`, and cycles by `5.6%`. Source Serif, which
  has a much smaller extension-wrapped format 1 subtable and does not activate
  the dense map, remained instruction/branch neutral while cycles improved
  about `1.7%`. Eleven-sample A/B/B/A wall medians improved Roboto by roughly
  `5.8--7.2%`; Source Serif wall time was noisy despite neutral retired work.
  The complete ReleaseFast suite and HarfBuzz/HarfRust corpus parity umbrella
  pass unchanged.
- The same PairPos format 1 range index now covers extension-wrapped tables
  with at least 64 reachable PairSets. Source Serif's five-subtable kerning
  lookup otherwise searched each subtable's complete record interval for every
  pair. Relative to the preceding broad-table threshold, fixed-CPU-30 A/B/B/A
  counters over twenty complete `en-words` passes reduced Source Serif retired
  instructions by about `0.54%`, branches by `0.70%`, branch misses by `1.85%`,
  and cycles by `0.85%`. Roboto, whose table already used the dense path, was
  instruction/branch neutral. Eleven-sample wall medians improved Source Serif
  by about `0.56%` and left Roboto within noise, with unchanged checksums.
- Single-font shaping now resolves script/language before validation and reuses
  the resulting all-ASCII proof to skip a second full UTF-8 scan of the source
  text. Context strings, font size, feature overrides, and variation coordinates
  remain validated at the public boundary, while all non-ASCII requests retain
  the general UTF-8 validator. Against the preceding PairPos state, fixed-CPU-30
  A/B/B/A counters over twenty complete `en-words` passes reduced retired
  instructions by about `0.66--0.67%`, branches by `0.95--0.96%`, and cycles
  by about `3.5%` for Roboto and `7.6%` for Source Serif. Eleven-sample wall
  medians improved about `4.5%` and `6.9%`, respectively, with unchanged
  output checksums.
- A fresh fixed-CPU-30 direct dirty-raster comparison (20,000 iterations, 15
  samples) measured Cangjie/FreeType medians of `4,869/4,388 ns` for Roboto
  64 px `A`, `6,898/5,593 ns` for `g`, and `5,308/5,284 ns` for `é`. The
  stable dirty areas and per-engine checksums were unchanged. Cangjie therefore
  still trails FreeType by about `1.11x`, `1.23x`, and `1.00x` on the direct
  boundary even though the prepared-coverage boundary remains a clear Cangjie
  win; overall raster superiority is not yet established.
- Horizontal ASCII output now returns directly from geometry resolution after
  applying the equivalent horizontal metrics, GPOS, kerx, and legacy-kern
  terms. ASCII cannot trigger space-emulation, default-ignorable, mark-zeroing,
  or vertical-orientation policy; attachment-bearing results remain on the
  general path. Fixed-CPU-30 A/B/B/A counters over twenty complete `en-words`
  passes reduced retired instructions by about `5.82%` for Roboto and `5.97%`
  for Source Serif, branches by `9.73%` and `9.88%`, and cycles by `5.10%` and
  `2.96%`. Eleven-sample wall medians improved about `5.2%` and `2.4%`, with
  unchanged checksums; the complete ReleaseFast suite, including mark-
  attachment coverage, passes.
- Final output now reuses the post-GSUB run proofs already computed for GPOS:
  mark-free runs skip per-glyph GDEF class lookup, and runs without default
  ignorables, kerx, or visible variation selectors skip the substituted-state
  sidecar and Unicode default-ignorable test. Fixed-CPU-30 A/B/B/A counters
  over twenty complete `en-words` passes reduced retired instructions by about
  `6.96%` for Roboto and `7.12%` for Source Serif, branches by `11.79%` and
  `11.85%`, and cycles by about `3.83%` and `2.24%`. Eleven-sample wall medians
  improved about `3.4%` and `2.2%`, respectively, with unchanged checksums and
  a passing complete ReleaseFast suite.
- Validated PairPos lookups now enter their exact first-glyph candidate map
  without first building a whole-run glyph digest and scanning the same
  coverage groups. Other GPOS kinds keep the lazy digest/group prefilter, and
  coverage-only chaining retains its single exact walk. Fixed-CPU-30 A/B/B/A
  counters over twenty complete `en-words` passes reduced retired instructions
  by about `1.34%` for Roboto and `1.30%` for Source Serif, branches by `1.32%`
  and `1.15%`, and cycles by about `2.90%` and `5.33%`. Eleven-sample wall
  medians improved about `2.5%` and `4.2%`, with unchanged checksums and a
  passing complete ReleaseFast suite.
- Legacy-kern planning now returns no lookup for fonts that do not contain a
  `kern` table, instead of installing a non-null wrapper whose every pair query
  returns zero. This lets the final positioning loop compile and execute the
  actual no-legacy-kern path for modern GPOS fonts. Fixed-CPU-30 A/B/B/A
  counters over twenty complete `en-words` passes reduced retired instructions
  by about `2.52%` for Roboto and `2.56%` for Source Serif, branches by about
  `2.53%` and `2.56%`, and cycles by `2.66%` and `2.91%`. Eleven-sample wall
  medians improved about `2.6%` and `3.0%`, respectively, with unchanged
  checksums and a passing complete ReleaseFast suite.
- OpenType property inference now runs a compact ASCII-only scan first. It
  determines the same first strong script and proves default language without
  decoding or querying Unicode script tables byte by byte; non-ASCII input
  falls through to the full multilingual inference state machine. Fixed-CPU-30
  A/B/B/A counters over twenty complete `en-words` passes reduced retired
  instructions by about `2.69%` for Roboto and `2.73%` for Source Serif,
  branches by `2.53%` and `2.56%`, and cycles by about `3.53%` and `4.39%`.
  Eleven-sample wall medians improved about `4.1%` and `4.9%`, respectively,
  with unchanged checksums and a passing complete ReleaseFast suite.
- Cached ASCII source population now lives in a dedicated out-of-line loop.
  The hot caller resolves its cache mode once instead of re-unwrapping the
  optional glyph-index cache for every byte, while the uncached API retains a
  direct font lookup loop. Fixed-CPU-30 A/B/B/A counters over twenty complete
  `en-words` passes reduced retired instructions by about `2.96%` for Roboto
  and `2.97%` for Source Serif, branches by `3.13%` and `3.34%`, and cycles by
  about `6.44%` and `4.40%`. Eleven-sample wall medians improved about `6.8%`
  and `5.5%`, respectively, with unchanged checksums and a passing complete
  ReleaseFast suite.
- Horizontal post-processing now checks the parsed face's `trak` capability
  before entering the allocation/validation/interpolation helper. Fonts without
  AAT tracking therefore skip the helper entirely. Fixed-CPU-30 A/B/B/A
  counters over twenty complete `en-words` passes reduced retired instructions
  by about `0.33%` for Roboto and `0.30%` for Source Serif, branches by `0.59%`
  and `0.76%`, branch misses by `0.94%` and `0.57%`, and cycles by about `3.46%`
  and `1.62%`. Eleven-sample wall medians improved about `3.4%` and `2.2%`,
  with unchanged checksums and a passing complete ReleaseFast suite.
- Cached ASCII cmap mapping now enters a tiny inline direct-slot lookup after
  the source stage proves every scalar is below U+0080. Exact font identity is
  still checked, and cold misses fall through to the authoritative Unicode/hash
  path. Fixed-CPU-30 A/B/B/A counters over twenty complete `en-words` passes
  reduced retired instructions by about `1.60%` for Roboto and `1.63%` for
  Source Serif, branches by `1.89%` and `1.92%`, branch misses by `4.23%` and
  `6.12%`, and cycles by about `1.73%` and `4.21%`. Eleven-sample wall medians
  improved about `2.2%` and `1.9%`, with unchanged checksums and a passing
  complete ReleaseFast suite.
- Post-GSUB mark capability detection now consumes the existing all-ASCII
  proof. It still checks every output glyph's GDEF class, including ligatures
  introduced by substitution, but skips source-index recovery and Unicode mark
  classification because no ASCII scalar can be a Unicode mark. The same
  result is reused by optional JSTF positioning. Fixed-CPU-30 A/B/B/A counters
  over twenty complete `en-words` passes reduced retired instructions by about
  `1.95%` for Roboto and `1.98%` for Source Serif, branches by `2.26%` and
  `2.29%`, and cycles by about `1.52%` and `3.76%`. Eleven-sample wall medians
  improved about `1.9%` and `4.6%`, with unchanged checksums and a passing
  complete ReleaseFast suite.
- Required-second LigatureSubst prefiltering now checks adjacent first/second
  candidates directly when LookupFlag is zero and the run proves it has no
  default ignorables. In that case no glyph may be skipped between the first
  and second components, so separated candidates cannot form a ligature;
  filtered and control-bearing runs retain the former permissive whole-run
  scan. Fixed-CPU-30 A/B/B/A counters over twenty complete `en-words` passes
  reduced retired instructions by about `1.92%` for Roboto and `1.98%` for
  Source Serif, branches by `2.04%` and `2.29%`, and cycles by `1.96%` and
  `3.64%`. Eleven-sample wall medians improved about `1.2%` and `5.0%`, with
  unchanged checksums and a passing complete ReleaseFast suite.
- Large required-second LigatureSubst indexes now encode their three-word
  second-component digest inside the existing compact component tail. Runtime
  shaping intersects it with the already-built mutation-aware run digest before
  entering the exact adjacent matcher, without widening the lookup sidecar.
  Fixed-CPU-30 A/B/B/A counters over twenty complete `en-words` passes reduced
  Roboto retired instructions by about `5.99%`, branches by `7.49%`, branch
  misses by `1.77%`, and cycles by `4.69%`; Source Serif controls improved
  about `1.98%`, `2.29%`, and `1.93%` in instructions, branches, and cycles.
  Eleven-sample wall medians improved about `5.4%` and `5.0%`, respectively,
  with unchanged checksums and a passing complete ReleaseFast suite.
- Cached ASCII source population now publishes the already-reserved parallel
  array lengths once and initializes each glyph record by index. This removes
  eight independent `ArrayList` length updates per byte without changing the
  source, cluster, substitution, or ligature-provenance values. Against the
  exact `c98f7917` parent binaries, fixed-CPU-30 A/B/B/A counters over twenty
  complete `en-words` passes reduced retired instructions by about `1.73%` for
  Roboto and `1.70%` for Source Serif, while branches stayed neutral; cycles
  improved about `3.12%` and `4.28%`. Eleven-sample wall medians improved about
  `3.6%` and `4.8%`, respectively, with unchanged checksums. The complete
  ReleaseFast suite passes.
- Legacy-kern planning now checks the parsed face's table capability before
  calling the fallible lookup constructor. This preserves the same nullable
  result for kern-less OpenType fonts while removing exception-style
  `MissingTable` control flow from every segment. Against exact `c81ddf7c`
  parent and candidate binaries, fixed-CPU-30 A/B/B/A counters over twenty
  complete `en-words` passes reduced retired instructions by about `0.18%` for
  Roboto and `0.21%` for Source Serif, branches by `0.58%` and `0.56%`, and
  cycles by about `1.47%` and `1.19%`. Eleven-sample wall medians improved by
  about `1.9%` and `0.9%`, respectively, with unchanged checksums and a
  passing complete ReleaseFast suite.
- The direct horizontal-metrics cache now indexes its small exact front cache
  by glyph id. Glyph ids are already dense font-table indexes and dominate
  locality inside one run; full font and variation identity remains in each
  entry and is still compared before every hit. Against the preceding exact
  binaries, fixed-CPU-30 A/B/B/A counters over twenty complete `en-words`
  passes reduced retired instructions by about `0.56%` for Roboto and `0.55%`
  for Source Serif, with neutral branches and cycle reductions of about `2.65%`
  and `3.69%`. Eleven-sample wall medians improved about `3.4%` and `4.0%`,
  respectively, with unchanged checksums and a passing complete ReleaseFast
  suite.
- Ranged-GSUB positioning now tests the parsed face's legacy-`kern` capability
  before constructing a kern lookup, matching the ordinary shaping pipeline's
  nullable-table contract. This closes the `MissingTable` failures exposed by
  the AOTS `gsub3_1_simple_f1.otf` and `gsub3_1_lookupflag_f1.otf` feature-range
  rows. The complete `shaping-corpus-parity-smoke` umbrella now passes,
  including both rows against HarfBuzz and HarfRust.
- Direct scan conversion no longer clears the complete per-edge link array
  before bucketing complex outlines. Every retained edge receives its link
  exactly once during the same construction pass, so the blanket initialization
  was redundant. Fixed-CPU-30 A/B/B/A counters over 200,000 Roboto 64 px dirty
  renders reduced retired instructions by about `0.85%` for `g` and `0.90%`
  for `é`, branches by about `0.56%` and `0.60%`, and cycles by about `1.24%`
  and `1.73%`; the straight-sided `A` control stayed instruction/branch neutral
  and improved about `2.14%` in cycles. Fifteen-sample wall medians improved
  about `1.1%` for `g` and `2.1%` for `é`, while `A` stayed within noise. All
  target checksums and dirty-pixel counts remained unchanged, and the complete
  ReleaseFast suite passes.
- Final positioning output now carries the existing all-ASCII source proof.
  GSUB still mutates the glyph-parallel source and cluster maps for ligatures
  and reordering, but their lengths remain equal to the glyph buffer, so ASCII
  output can read both maps directly instead of repeating generic missing-map
  fallbacks and source bounds clamps for every glyph. Against exact
  `a2d889c3` parent and candidate binaries, fixed-CPU-30 A/B/B/A counters over
  twenty complete Source Serif Variable `en-words` passes reduced retired
  instructions by about `1.45%`, branches by about `0.10%`, and cycles by
  about `1.99%`; branch misses increased by about `2.77%`. Eleven-sample wall
  medians improved from an average `136.197` to `135.106 ns/glyph` (about
  `0.80%`), with identical checksums. The complete ReleaseFast suite and the
  retained HarfBuzz/HarfRust corpus parity umbrella pass.
- ASCII source-span recovery now uses the same proof to bypass generic
  saturation, optional-span, and per-component min/max work. Ordinary glyphs
  read their already-parallel source end directly; for a ligature, the
  monotone provenance list makes its last retained component the maximal end,
  while the mutated cluster-owner sidecar remains authoritative for the public
  start. Against exact `5f612dfc` parent and candidate binaries, fixed-CPU-30
  A/B/B/A counters over twenty Source Serif Variable `en-words` passes reduced
  retired instructions by about `3.26%`, branches by about `4.34%`, and branch
  misses by about `2.82%`; cycles improved about `0.77%` in the frequency-
  normalized perf result. Eleven-sample medians improved from an average
  `134.600` to `133.467 ns/glyph` (about `0.84%`), with identical checksums.
  Roboto controls showed the same instruction/branch reduction, and the full
  ReleaseFast suite plus retained HarfBuzz/HarfRust corpus parity pass.
