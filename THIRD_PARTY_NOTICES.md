# Third-Party Notices

## unicode-linebreak

`src/text/line_break_data.bin` is generated from the compressed Unicode
property trie and pair-state table distributed in `unicode-linebreak 0.1.5`.
The Cangjie iterator is an independent Zig implementation of the same
table-driven algorithm.

- Project: <https://github.com/axelf4/unicode-linebreak>
- Copyright: Axel Forsman and unicode-linebreak contributors
- License: Apache License 2.0; see `licenses/Apache-2.0.txt`

## Unicode Character Database

`src/text/line_break_data.bin` ultimately contains derived Unicode
`Line_Break` property data. `src/text/line_break_test_data.bin` is a compact
encoding of default cases from `LineBreakTest-15.0.0.txt`.

- Project: <https://www.unicode.org/>
- Copyright: Unicode, Inc.
- License: Unicode License v3; see `licenses/Unicode-3.0.txt`

The generation inputs, checksums, excluded tailorable cases, and reproducible
commands are recorded in `docs/text-pipeline.md`.
