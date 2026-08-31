# Parley layout oracle

This standalone runner reproduces Parley's official default benchmark
construction boundary with an explicit font and UTF-8 text file: reusable
`FontContext`/`LayoutContext`, `RangedBuilder::build`, 200-unit line breaking,
and start alignment (or center alignment for the `center` style). It prints
deterministic native, logical-geometry, absolute-placement, and object-geometry
checksums plus median nanoseconds per complete layout so Cangjie's
`paragraph-bench` can be run serially on the same pinned CPU without making
cross-process timing claims from different workloads.

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
paragraphs. One additional ordinary-Latin row uses a dedicated terminal-space-
free fixture and center alignment. It requires exact equality for both the
existing translation-invariant `geometry_checksum` and the new
`placement_checksum`, which hashes each line's source range and canonicalized
absolute x origin without removing translation. The matrix also rejects
mismatched source-byte, glyph, line, or object counts and requires exact
normalized object geometry (stable id/source/line, x/y, size, and baseline) for
all object rows.
Custom object rows explicitly resume Parley's breaker with zero occupancy and
compare the same caller-owned absolute placement used by Cangjie.
The Parley oracle disables optional paint-time pixel quantization so both
engines expose fractional coordinates. Optional `-- --iterations N --samples
N --cpu CPU --fail-on-slower` arguments provide a repeatable fixed-core run
whose optional strict gate rejects any row without a positive Cangjie margin. The
default font paths target the local Linux Noto installation and can be
overridden with the script directly when required.
