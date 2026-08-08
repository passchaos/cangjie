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
- NotoSansDevanagari `hi-words.txt` passes `compare-harfrust` for 10,000
  lines.
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
  (`checksum=b7767f522a7f1ef`). The gate is:
  ```sh
  zig build shape-bench -Doptimize=ReleaseFast -- \
    --engine compare-harfbuzz \
    --font ~/Work/harfbuzz/test/shape/data/text-rendering-tests/fonts/NotoSansBalinese-Regular.ttf \
    --text-file tests/data/balinese-rendering-tests.txt --direction ltr
  ```

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
- Expand USE shaping parity beyond the retained Duployan and Balinese gates.
  Other USE scripts/fonts and fuzz/corpus failures still need retained gates
  before this can be called broad USE parity.
- Continue Arabic hot-path work from measured profile evidence: GSUB `calt`
  context lookups now dominate after the GPOS lookup `37` cleanup; avoid
  retaining speculative prefilters unless they improve both Arabic and Roboto
  smoke runs reliably.
- Avoid retaining optimizations that only improve a single noisy run or regress
  Roboto/word-list smoke cases.
