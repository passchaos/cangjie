# Parley layout oracle

This standalone runner reproduces Parley's official default benchmark
construction boundary with an explicit font and UTF-8 text file: reusable
`FontContext`/`LayoutContext`, `RangedBuilder::build`, 200-unit line breaking,
and start alignment. It prints a deterministic output checksum and median
nanoseconds per complete layout so Cangjie's `paragraph-bench` can be run
serially on the same pinned CPU without making cross-process timing claims from
different workloads.

The relative path pins the local Parley checkout used by this repository's
reference audit. Rust remains optional and is not part of the normal Zig test
graph. Example:

```sh
cargo run --release --manifest-path tools/parley_layout_oracle/Cargo.toml -- \
  /path/to/Roboto-Regular.ttf /path/to/latin.txt 1000 31 [FAMILY] [WIDTH] [DIRECTION] [default|spacing|alternating|inline-object|out-of-flow-object] [layout|reflow]

zig build paragraph-bench -Doptimize=ReleaseFast -- \
  /path/to/Roboto-Regular.ttf /path/to/latin.txt 1000 31 [WIDTH] [PHASE] [DIRECTION] [default|spacing|alternating|inline-object|out-of-flow-object]
```

`zig build parley-matrix -Doptimize=ReleaseFast` runs default, spacing,
alternating-style, in-flow-object, out-of-flow-object, and mixed-font fallback boundaries over
Parley's Latin, Arabic, and Japanese sample paragraphs. It rejects mismatched
source-byte, glyph, line, or object counts and requires exact normalized object
geometry (stable id/source/line, x/y, size, and baseline) for all object rows.
The Parley oracle disables optional paint-time pixel quantization so both
engines expose fractional coordinates. Optional `-- --iterations N --samples
N --cpu CPU --fail-on-slower` arguments provide a repeatable fixed-core run
whose optional strict gate rejects any row without a positive Cangjie margin. The
default font paths target the local Linux Noto installation and can be
overridden with the script directly when required.
