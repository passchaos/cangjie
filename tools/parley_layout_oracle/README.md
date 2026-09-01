# Parley layout oracle

This standalone runner reproduces Parley's official default benchmark
construction boundary with an explicit font and UTF-8 text file: reusable
`FontContext`/`LayoutContext`, `RangedBuilder::build_into` with reusable
`Layout` storage, 200-unit line breaking,
and start alignment (or center alignment for the `center` style). It prints
deterministic native, logical-geometry, absolute-placement, and object-geometry
checksums plus median nanoseconds per complete layout so Cangjie's
`paragraph-bench` can be run serially on the same pinned CPU without making
cross-process timing claims from different workloads. Placement checksums use
the resolved paragraph geometry and record the physical visible-left origin.
This preserves alignment translation while normalizing the engines' different
treatment of discarded wrapping whitespace, including RTL physical prefixes.
It is a visible-content line origin, not either engine's raw line-box origin or
the direction-dependent logical inline-start edge.

The relative path pins the local Parley checkout used by this repository's
reference audit. Rust remains optional and is not part of the normal Zig test
graph. Example:

```sh
cargo run --release --manifest-path tools/parley_layout_oracle/Cargo.toml -- \
  /path/to/Roboto-Regular.ttf /path/to/latin.txt 1000 31 [FAMILY] [WIDTH] [DIRECTION] [default|center|spacing|alternating|inline-object|out-of-flow-object|custom-out-of-flow-object|fallback] [layout|reflow] [FALLBACK_FONT]

zig build paragraph-bench -Doptimize=ReleaseFast -- \
  /path/to/Roboto-Regular.ttf /path/to/latin.txt 1000 31 [WIDTH] [PHASE] [DIRECTION] [default|center|spacing|alternating|inline-object|out-of-flow-object|custom-out-of-flow-object|fallback] [FALLBACK_FONT]
```

`zig build parley-matrix -Doptimize=ReleaseFast` runs default, spacing,
alternating-style, in-flow-object, ordinary/custom out-of-flow-object, and
mixed-font fallback boundaries over Parley's Latin, Arabic, and Japanese sample
paragraphs. Four mixed-bidi rows cover default construction and retained reflow
for LTR- and RTL-base Latin/Hebrew/Arabic fixtures using DejaVu Sans. Two
additional ordinary-Latin rows use a dedicated terminal-space-
free fixture and center alignment for one-shot layout and retained reflow. The
matrix requires exact equality for both the translation-invariant
`geometry_checksum` and direction-aware
`placement_checksum` on every directly proven non-object row: all Latin rows,
the comparable Arabic rows, Japanese alternating style, and both fallback
phases. The placement checksum hashes each line's source range and canonicalized
visible-left origin without removing translation. It uses a 1/256-pixel grid
for absolute positions; normalized internal geometry and object coordinates
retain their finer 1/1024-pixel grid. The matrix also rejects
mismatched source-byte, glyph, line, or object counts and requires exact
normalized object geometry (stable id/source/line, x/y, size, and baseline) for
all object rows.
Custom object rows explicitly resume Parley's breaker with zero occupancy and
compare the same caller-owned absolute placement used by Cangjie.
The Parley oracle disables optional paint-time pixel quantization so both
engines expose fractional coordinates. Optional `-- --iterations N --samples
N --cpu CPU --fail-on-slower --minimum-speedup R` arguments provide a
repeatable fixed-core run. The optional strict gate requires the declared
finite margin greater than parity and defaults to `1.01x`. The default font
paths target the local Linux Noto and DejaVu installations and can be
overridden with the script directly when required.
