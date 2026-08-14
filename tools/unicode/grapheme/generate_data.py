#!/usr/bin/env python3
"""Generate compact Unicode 17.0 UAX #29 grapheme property data.

Usage:
    tools/unicode/grapheme/generate_data.py \
        GraphemeBreakProperty.txt emoji-data.txt DerivedCoreProperties.txt \
        src/unicode/grapheme/data.bin

Each Unicode scalar is encoded in one byte: the low nibble stores GCB, bits
4..5 store InCB, and bit 6 stores Extended_Pictographic. The scalar array is
split into deduplicated 256-byte pages with a u16 page index, keeping runtime
lookup branch-free while avoiding a 1.1 MiB static table.
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path
from typing import Pattern


GCB_NAMES = (
    "Other",
    "CR",
    "LF",
    "Control",
    "Extend",
    "ZWJ",
    "Regional_Indicator",
    "Prepend",
    "SpacingMark",
    "L",
    "V",
    "T",
    "LV",
    "LVT",
)
GCB = {name: value for value, name in enumerate(GCB_NAMES)}
INCB = {"None": 0, "Consonant": 1, "Extend": 2, "Linker": 3}
SCALAR_LIMIT = 0x110000


def parse_ranges(
    path: str,
    pattern: Pattern[str],
) -> list[tuple[int, int, str]]:
    ranges: list[tuple[int, int, str]] = []
    for line_number, raw in enumerate(
        Path(path).read_text(encoding="utf-8").splitlines(), 1
    ):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = pattern.match(line)
        if match is None:
            # DerivedCoreProperties contains many unrelated properties. Lines
            # in the requested input syntax are consumed; others are ignored.
            continue
        start = int(match.group(1), 16)
        end = int(match.group(2) or match.group(1), 16)
        if end >= SCALAR_LIMIT or start > end:
            raise SystemExit(f"{path}:{line_number}: invalid scalar range")
        ranges.append((start, end, match.group(3)))
    return ranges


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} GraphemeBreakProperty.txt "
            "emoji-data.txt DerivedCoreProperties.txt output.bin"
        )

    properties = bytearray(SCALAR_LIMIT)
    plain_property = re.compile(
        r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Za-z_]+)$"
    )
    for start, end, name in parse_ranges(sys.argv[1], plain_property):
        if name not in GCB:
            raise SystemExit(f"unknown Grapheme_Cluster_Break value {name!r}")
        properties[start : end + 1] = bytes([GCB[name]]) * (end - start + 1)

    for start, end, name in parse_ranges(sys.argv[2], plain_property):
        if name == "Extended_Pictographic":
            for codepoint in range(start, end + 1):
                properties[codepoint] |= 0x40

    incb_property = re.compile(
        r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*InCB\s*;\s*([A-Za-z_]+)$"
    )
    for start, end, name in parse_ranges(sys.argv[3], incb_property):
        if name not in INCB:
            raise SystemExit(f"unknown Indic_Conjunct_Break value {name!r}")
        value = INCB[name] << 4
        for codepoint in range(start, end + 1):
            properties[codepoint] = (properties[codepoint] & 0xCF) | value

    pages: list[bytes] = []
    slots: dict[bytes, int] = {}
    index: list[int] = []
    for offset in range(0, SCALAR_LIMIT, 256):
        page = bytes(properties[offset : offset + 256])
        slot = slots.get(page)
        if slot is None:
            slot = len(pages)
            slots[page] = slot
            pages.append(page)
        index.append(slot)
    if len(pages) > 0xFFFF:
        raise SystemExit("too many unique pages for u16 index")

    output = bytearray(
        struct.pack("<4sBBBBHH", b"CJGB", 1, 17, 0, 0, len(index), len(pages))
    )
    output.extend(struct.pack(f"<{len(index)}H", *index))
    output.extend(b"".join(pages))
    Path(sys.argv[4]).write_bytes(output)


if __name__ == "__main__":
    main()
