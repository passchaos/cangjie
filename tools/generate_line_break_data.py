#!/usr/bin/env python3
"""Convert unicode-linebreak's generated Rust tables to a compact binary blob.

Usage:
    tools/generate_line_break_data.py path/to/unicode-linebreak/src/tables.rs \
        src/text/line_break_data.bin

The expected input is the generated `tables.rs` from unicode-linebreak 0.1.5.
That release is based on Unicode 15.0.0 and has crate SHA-256:
3b09c83c3c29d37506a3e260c08c03743a6bb66a9cd432c6934ab501a190571f

Binary format (all multi-byte integers are little-endian):
    magic[4] = "CJLB"
    format_version: u8 = 1
    unicode_version[3]: u8 = {15, 0, 0}
    trie_high_start: u32
    trie_index_count: u32
    trie_data_count: u32
    pair_rows: u16
    pair_columns: u16
    trie_index[trie_index_count]: u16
    trie_data[trie_data_count]: u8
    pair_table[pair_rows * pair_columns]: u8
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path


CLASS_VALUES = {
    name: value
    for value, name in enumerate(
        (
            "BK",
            "CR",
            "LF",
            "CM",
            "NL",
            "SG",
            "WJ",
            "ZW",
            "GL",
            "SP",
            "ZWJ",
            "B2",
            "BA",
            "BB",
            "HY",
            "CB",
            "CL",
            "CP",
            "EX",
            "IN",
            "NS",
            "OP",
            "QU",
            "IS",
            "NU",
            "PO",
            "PR",
            "SY",
            "AI",
            "AL",
            "CJ",
            "EB",
            "EM",
            "H2",
            "H3",
            "HL",
            "ID",
            "JL",
            "JV",
            "JT",
            "RI",
            "SA",
            "XX",
        )
    )
}


def extract(source: str, pattern: str, label: str) -> str:
    match = re.search(pattern, source, re.DOTALL)
    if match is None:
        raise SystemExit(f"could not find {label}")
    return match.group(1)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} path/to/tables.rs output.bin"
        )
    source = Path(sys.argv[1]).read_text(encoding="utf-8")

    high_start = int(
        extract(
            source,
            r"const BREAK_PROP_TRIE_HIGH_START: u32 = (\d+);",
            "trie high start",
        )
    )
    index_body = extract(
        source,
        r"static BREAK_PROP_TRIE_INDEX: \[u16; \d+\] = \[(.*?)\];",
        "trie index",
    )
    index = [int(value) for value in re.findall(r"\d+", index_body)]
    declared_index_count = int(
        extract(
            source,
            r"static BREAK_PROP_TRIE_INDEX: \[u16; (\d+)\]",
            "trie index count",
        )
    )
    if len(index) != declared_index_count:
        raise SystemExit(
            f"expected {declared_index_count} trie indexes, found {len(index)}"
        )

    data_body = extract(
        source,
        r"static BREAK_PROP_TRIE_DATA: \[BreakClass; \d+\] = \[(.*?)\];",
        "trie data",
    )
    class_names = re.findall(r"\b[A-Z][A-Z0-9]*\b", data_body)
    try:
        data = [CLASS_VALUES[name] for name in class_names]
    except KeyError as error:
        raise SystemExit(f"unknown break class {error.args[0]}") from error
    declared_data_count = int(
        extract(
            source,
            r"static BREAK_PROP_TRIE_DATA: \[BreakClass; (\d+)\]",
            "trie data count",
        )
    )
    if len(data) != declared_data_count:
        raise SystemExit(
            f"expected {declared_data_count} trie values, found {len(data)}"
        )

    pair_body = extract(
        source,
        r"static PAIR_TABLE: \[\[u8; 44\]; 53\] = \[(.*?)\];\s*"
        r"fn is_safe_pair",
        "pair table",
    )
    pairs = [int(value) for value in re.findall(r"\d+", pair_body)]
    if len(pairs) != 53 * 44:
        raise SystemExit(f"expected {53 * 44} pair values, found {len(pairs)}")

    output = bytearray(
        struct.pack(
            "<4sBBBBIIIHH",
            b"CJLB",
            1,
            15,
            0,
            0,
            high_start,
            len(index),
            len(data),
            53,
            44,
        )
    )
    output.extend(struct.pack(f"<{len(index)}H", *index))
    output.extend(bytes(data))
    output.extend(bytes(pairs))
    Path(sys.argv[2]).write_bytes(output)


if __name__ == "__main__":
    main()
