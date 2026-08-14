#!/usr/bin/env python3
"""Generate compact Unicode 17.0 UAX #29 word-boundary property data.

Usage:
    tools/unicode/word/generate_data.py \
        WordBreakProperty.txt emoji-data.txt UnicodeData.txt \
        src/unicode/word/data.bin

Each scalar uses one byte before page deduplication: bits 0..4 store
Word_Break, bit 5 stores Extended_Pictographic, and bit 6 stores a selectable
word anchor. The anchor is true for Unicode letters/numbers and for Katakana
or connector classes, allowing callers to distinguish text from punctuation
without reintroducing script range tables.
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path
from typing import Pattern


WB_NAMES = (
    "Other",
    "CR",
    "LF",
    "Newline",
    "Extend",
    "Format",
    "Katakana",
    "ALetter",
    "MidLetter",
    "MidNum",
    "MidNumLet",
    "Numeric",
    "ExtendNumLet",
    "Regional_Indicator",
    "Hebrew_Letter",
    "Single_Quote",
    "Double_Quote",
    "ZWJ",
    "WSegSpace",
)
WB = {name: value for value, name in enumerate(WB_NAMES)}
WORD_ANCHOR_CLASSES = {
    "ALetter",
    "Hebrew_Letter",
    "Numeric",
    "Katakana",
    "ExtendNumLet",
}
SCALAR_LIMIT = 0x110000
RANGE_RE = re.compile(
    r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Za-z_]+)$"
)


def parse_ranges(
    path: str,
    pattern: Pattern[str] = RANGE_RE,
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
            continue
        start = int(match.group(1), 16)
        end = int(match.group(2) or match.group(1), 16)
        if start > end or end >= SCALAR_LIMIT:
            raise SystemExit(f"{path}:{line_number}: invalid scalar range")
        ranges.append((start, end, match.group(3)))
    return ranges


def set_flag(properties: bytearray, start: int, end: int, flag: int) -> None:
    for codepoint in range(start, end + 1):
        properties[codepoint] |= flag


def apply_unicode_word_anchors(properties: bytearray, path: str) -> None:
    range_start: int | None = None
    range_category: str | None = None
    for line_number, raw in enumerate(
        Path(path).read_text(encoding="utf-8").splitlines(), 1
    ):
        fields = raw.split(";")
        if len(fields) < 3:
            raise SystemExit(f"{path}:{line_number}: malformed UnicodeData row")
        codepoint = int(fields[0], 16)
        name = fields[1]
        category = fields[2]
        if name.endswith(", First>"):
            if range_start is not None:
                raise SystemExit(f"{path}:{line_number}: nested UnicodeData range")
            range_start = codepoint
            range_category = category
            continue
        if name.endswith(", Last>"):
            if range_start is None or range_category != category:
                raise SystemExit(f"{path}:{line_number}: unmatched UnicodeData range")
            if category.startswith(("L", "N")):
                set_flag(properties, range_start, codepoint, 0x40)
            range_start = None
            range_category = None
            continue
        if category.startswith(("L", "N")):
            properties[codepoint] |= 0x40
    if range_start is not None:
        raise SystemExit(f"{path}: unterminated UnicodeData range")


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} WordBreakProperty.txt "
            "emoji-data.txt UnicodeData.txt output.bin"
        )

    word_break_text = Path(sys.argv[1]).read_text(encoding="utf-8")
    if not word_break_text.startswith("# WordBreakProperty-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17.0 WordBreakProperty data")
    emoji_text = Path(sys.argv[2]).read_text(encoding="utf-8")
    if "# Version: 17.0\n" not in emoji_text[:1024]:
        raise SystemExit("expected Unicode Emoji 17.0 data")
    unicode_data_text = Path(sys.argv[3]).read_text(encoding="utf-8")
    if not unicode_data_text.startswith("0000;<control>;Cc;"):
        raise SystemExit("unexpected UnicodeData input")

    properties = bytearray(SCALAR_LIMIT)
    for start, end, name in parse_ranges(sys.argv[1]):
        if name not in WB:
            raise SystemExit(f"unknown Word_Break value {name!r}")
        value = WB[name]
        if name in WORD_ANCHOR_CLASSES:
            value |= 0x40
        properties[start : end + 1] = bytes([value]) * (end - start + 1)

    for start, end, name in parse_ranges(sys.argv[2]):
        if name == "Extended_Pictographic":
            set_flag(properties, start, end, 0x20)

    # Dictionary-segmented scripts and ideographs often have WB=Other. General
    # Category still identifies their letter/number segments as word content
    # without changing the default UAX #29 boundaries.
    apply_unicode_word_anchors(properties, sys.argv[3])

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
        struct.pack("<4sBBBBHH", b"CJWB", 1, 17, 0, 0, len(index), len(pages))
    )
    output.extend(struct.pack(f"<{len(index)}H", *index))
    output.extend(b"".join(pages))
    Path(sys.argv[4]).write_bytes(output)


if __name__ == "__main__":
    main()
