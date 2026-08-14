#!/usr/bin/env python3
"""Generate compact Unicode 17.0 UAX #29 sentence-break property data.

Usage:
    tools/unicode/sentence/generate_data.py \
        SentenceBreakProperty.txt src/unicode/sentence/data.bin
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path


SB_NAMES = (
    "Other",
    "CR",
    "LF",
    "Sep",
    "Extend",
    "Format",
    "Sp",
    "Lower",
    "Upper",
    "OLetter",
    "Numeric",
    "ATerm",
    "STerm",
    "Close",
    "SContinue",
)
SB = {name: value for value, name in enumerate(SB_NAMES)}
SCALAR_LIMIT = 0x110000
RANGE_RE = re.compile(
    r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Za-z_]+)$"
)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} SentenceBreakProperty.txt output.bin"
        )
    source = Path(sys.argv[1]).read_text(encoding="utf-8")
    if not source.startswith("# SentenceBreakProperty-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17.0 SentenceBreakProperty data")

    properties = bytearray(SCALAR_LIMIT)
    for line_number, raw in enumerate(source.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = RANGE_RE.match(line)
        if match is None:
            raise SystemExit(f"line {line_number}: malformed property range")
        start = int(match.group(1), 16)
        end = int(match.group(2) or match.group(1), 16)
        name = match.group(3)
        if start > end or end >= SCALAR_LIMIT:
            raise SystemExit(f"line {line_number}: invalid scalar range")
        if name not in SB:
            raise SystemExit(f"line {line_number}: unknown Sentence_Break {name!r}")
        properties[start : end + 1] = bytes([SB[name]]) * (end - start + 1)

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
        struct.pack("<4sBBBBHH", b"CJSB", 1, 17, 0, 0, len(index), len(pages))
    )
    output.extend(struct.pack(f"<{len(index)}H", *index))
    output.extend(b"".join(pages))
    Path(sys.argv[2]).write_bytes(output)


if __name__ == "__main__":
    main()
