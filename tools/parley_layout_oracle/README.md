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
  /path/to/Roboto-Regular.ttf /path/to/latin.txt 1000 31 [FAMILY] [WIDTH] [DIRECTION]

zig build paragraph-bench -Doptimize=ReleaseFast -- \
  /path/to/Roboto-Regular.ttf /path/to/latin.txt 1000 31 [WIDTH] [PHASE] [DIRECTION]
```
