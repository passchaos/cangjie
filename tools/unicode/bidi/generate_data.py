#!/usr/bin/env python3
"""Generate Unicode 17 UAX #9 classes, paired brackets, and mirrors.

Usage:
    tools/unicode/bidi/generate_data.py \
        DerivedBidiClass.txt BidiBrackets.txt BidiMirroring.txt \
        src/unicode/bidi/data.bin

The runtime property table uses deduplicated 256-scalar pages. Sparse bracket
and mirroring records follow the pages in sorted codepoint order.
"""
from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

LIMIT = 0x110000
CLASSES = (
    "L", "R", "AL", "EN", "ES", "ET", "AN", "CS", "NSM", "BN", "B",
    "S", "WS", "ON", "LRE", "LRO", "RLE", "RLO", "PDF", "LRI", "RLI",
    "FSI", "PDI",
)
CLASS = {name: index for index, name in enumerate(CLASSES)}
RANGE = re.compile(
    r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Z]+)"
)
MISSING = re.compile(
    r"^#\s*@missing:\s*([0-9A-F]+)(?:\.\.([0-9A-F]+))?"
    r"\s*;\s*([A-Za-z_]+)"
)
LONG_TO_SHORT = {
    "Left_To_Right": "L",
    "Right_To_Left": "R",
    "Arabic_Letter": "AL",
    "European_Number": "EN",
    "European_Separator": "ES",
    "European_Terminator": "ET",
    "Arabic_Number": "AN",
    "Common_Separator": "CS",
    "Nonspacing_Mark": "NSM",
    "Boundary_Neutral": "BN",
    "Paragraph_Separator": "B",
    "Segment_Separator": "S",
    "White_Space": "WS",
    "Other_Neutral": "ON",
    "Left_To_Right_Embedding": "LRE",
    "Left_To_Right_Override": "LRO",
    "Right_To_Left_Embedding": "RLE",
    "Right_To_Left_Override": "RLO",
    "Pop_Directional_Format": "PDF",
    "Left_To_Right_Isolate": "LRI",
    "Right_To_Left_Isolate": "RLI",
    "First_Strong_Isolate": "FSI",
    "Pop_Directional_Isolate": "PDI",
}


def checked_range(path: str, line_no: int, match: re.Match[str]):
    first = int(match[1], 16)
    last = int(match[2] or match[1], 16)
    if first > last or last >= LIMIT:
        raise SystemExit(f"{path}:{line_no}: invalid scalar range")
    return first, last


def load_classes(path: str) -> list[int]:
    text = Path(path).read_text(encoding="utf-8")
    if not text.startswith("# DerivedBidiClass-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17 DerivedBidiClass data")

    values = [CLASS["L"]] * LIMIT
    # UAX #44 gives script-block defaults through @missing directives. Apply
    # those first, in file order, and let explicit property rows win below.
    for line_no, line in enumerate(text.splitlines(), 1):
        match = MISSING.match(line)
        if not match:
            continue
        first, last = checked_range(path, line_no, match)
        name = LONG_TO_SHORT.get(match[3])
        if name is None:
            raise SystemExit(f"{path}:{line_no}: unknown @missing class {match[3]}")
        values[first : last + 1] = [CLASS[name]] * (last - first + 1)

    for line_no, line in enumerate(text.splitlines(), 1):
        match = RANGE.match(line)
        if not match:
            continue
        first, last = checked_range(path, line_no, match)
        name = match[3]
        if name not in CLASS:
            raise SystemExit(f"{path}:{line_no}: unknown Bidi_Class {name}")
        values[first : last + 1] = [CLASS[name]] * (last - first + 1)
    return values


def load_brackets(path: str):
    text = Path(path).read_text(encoding="utf-8")
    if not text.startswith("# BidiBrackets-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17 BidiBrackets data")
    records = []
    for line_no, line in enumerate(text.splitlines(), 1):
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 3 or fields[2] not in ("o", "c"):
            raise SystemExit(f"{path}:{line_no}: malformed bracket row")
        codepoint = int(fields[0], 16)
        paired = int(fields[1], 16)
        records.append((codepoint, paired, fields[2] == "o"))

    opening_for_pair = {
        codepoint: codepoint for codepoint, _, is_open in records if is_open
    }
    opening_for_pair.update(
        (paired, codepoint)
        for codepoint, paired, is_open in records
        if is_open
    )
    normalized = []
    for codepoint, paired, is_open in records:
        opening = codepoint if is_open else opening_for_pair.get(paired, paired)
        # UAX #9 BD16 treats U+2329/U+3008 and U+232A/U+3009 as canonically
        # equivalent. Normalize both families to the CJK bracket skeleton.
        if opening == 0x2329:
            opening = 0x3008
        normalized.append((codepoint, opening, is_open))
    return sorted(normalized)


def load_mirrors(path: str):
    text = Path(path).read_text(encoding="utf-8")
    if not text.startswith("# BidiMirroring-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17 BidiMirroring data")
    records = []
    for line_no, line in enumerate(text.splitlines(), 1):
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 2:
            raise SystemExit(f"{path}:{line_no}: malformed mirror row")
        records.append((int(fields[0], 16), int(fields[1], 16)))
    return sorted(records)


def main():
    if len(sys.argv) != 5:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} "
            "DerivedBidiClass.txt BidiBrackets.txt BidiMirroring.txt output.bin"
        )
    values = load_classes(sys.argv[1])
    brackets = load_brackets(sys.argv[2])
    mirrors = load_mirrors(sys.argv[3])

    pages = []
    slots = {}
    index = []
    for offset in range(0, LIMIT, 256):
        page = bytes(values[offset : offset + 256])
        slot = slots.get(page)
        if slot is None:
            slot = len(pages)
            slots[page] = slot
            pages.append(page)
        index.append(slot)
    if len(pages) > 0xFFFF:
        raise SystemExit("too many class pages")

    output = bytearray(
        struct.pack(
            "<4sBBBBHHHH",
            b"CJB1",
            1,
            17,
            0,
            0,
            len(index),
            len(pages),
            len(brackets),
            len(mirrors),
        )
    )
    output.extend(struct.pack(f"<{len(index)}H", *index))
    output.extend(b"".join(pages))
    for codepoint, opening, is_open in brackets:
        output.extend(struct.pack("<IIB3x", codepoint, opening, is_open))
    for codepoint, mirror in mirrors:
        output.extend(struct.pack("<II", codepoint, mirror))
    Path(sys.argv[4]).write_bytes(output)


if __name__ == "__main__":
    main()
