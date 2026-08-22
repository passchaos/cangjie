#!/usr/bin/env python3
"""Generate the exact Unicode 17 Script property page table.

Usage: generate_data.py Scripts.txt src/unicode/script/data.bin

The binary stores one Script enum discriminant per Unicode scalar in
deduplicated 256-scalar pages. Enum order is read from root.zig so the runtime
table and its public Script type cannot silently use different numbering.
"""

import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = Path(__file__).with_name("coverage.json")
LIMIT = 0x110000
LINE = re.compile(r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Za-z_]+)\b")
ENUM = re.compile(r"pub const Script = enum \{(.*?)\n\};", re.DOTALL)
ZIG_SCRIPT_NAME_OVERRIDES = {"Oriya": "odia"}


def script_order() -> list[str]:
    source = (ROOT / "src/unicode/script/types.zig").read_text(encoding="utf-8")
    match = ENUM.search(source)
    if match is None:
        raise SystemExit("could not find Script enum in types.zig")
    names = []
    for line in match.group(1).splitlines():
        name = line.split("//", 1)[0].strip().removesuffix(",")
        if name:
            names.append(name)
    if len(names) > 256 or len(names) != len(set(names)):
        raise SystemExit("Script enum must contain at most 256 unique values")
    return names


def enum_fingerprint(names: list[str]) -> int:
    value = 2166136261
    for name in names:
        for byte in name.encode("ascii"):
            value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
        value = ((value ^ 0xFF) * 16777619) & 0xFFFFFFFF
    return value


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_data.py Scripts.txt output.bin")
    source_path = Path(sys.argv[1])
    source_bytes = source_path.read_bytes()
    source = source_bytes.decode("utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected_header = f"# Scripts-{manifest['unicode_version']}.txt\n"
    if not source.startswith(expected_header):
        raise SystemExit(f"expected {expected_header.strip()}")
    if hashlib.sha256(source_bytes).hexdigest() != manifest["source_sha256"]:
        raise SystemExit("Scripts.txt SHA-256 does not match the pinned Unicode source")

    order = script_order()
    identifiers = {name: index for index, name in enumerate(order)}
    unknown = identifiers.get("unknown")
    if unknown is None:
        raise SystemExit("Script enum lacks unknown")
    values = bytearray([unknown]) * LIMIT
    seen = set()
    for line in source.splitlines():
        match = LINE.match(line)
        if match is None:
            continue
        first = int(match.group(1), 16)
        last = int(match.group(2) or match.group(1), 16)
        property_name = match.group(3)
        zig_name = ZIG_SCRIPT_NAME_OVERRIDES.get(property_name, property_name.lower())
        script_id = identifiers.get(zig_name)
        if script_id is None:
            raise SystemExit(f"Script enum lacks {zig_name} for {property_name}")
        values[first : last + 1] = bytes([script_id]) * (last - first + 1)
        seen.add(property_name)
    if seen != set(manifest["modeled_scripts"]):
        raise SystemExit("Script enum/source coverage differs from the manifest")

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
        raise SystemExit("too many Script-property pages")

    output = bytearray(
        struct.pack(
            "<4sBBBBIHH",
            b"CJS1",
            1,
            17,
            0,
            0,
            enum_fingerprint(order),
            len(index),
            len(pages),
        )
    )
    output.extend(struct.pack(f"<{len(index)}H", *index))
    output.extend(b"".join(pages))
    output_path = Path(sys.argv[2])
    if output_path.exists() and output_path.read_bytes() == output:
        return
    output_path.write_bytes(output)


if __name__ == "__main__":
    main()
