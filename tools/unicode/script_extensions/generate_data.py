#!/usr/bin/env python3
"""Generate Unicode 17 Script_Extensions masks.

Usage:
    generate_data.py Scripts.txt ScriptExtensions.txt PropertyValueAliases.txt \
        src/unicode/script_extensions/data.bin

Only explicit ScriptExtensions.txt overrides are stored. Callers fall back to
the scalar's Script value for every other code point, matching UAX #24.
"""

import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "tools/unicode/script/coverage.json"
EXTENSIONS_MANIFEST = Path(__file__).with_name("coverage.json")
SCRIPT_LINE = re.compile(
    r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Za-z_]+)\b"
)
ALIAS_LINE = re.compile(r"^sc\s*;\s*([A-Za-z0-9_]+)\s*;\s*([A-Za-z_]+)")
ENUM = re.compile(r"pub const Script = enum \{(.*?)\n\};", re.DOTALL)
ZIG_SCRIPT_NAME_OVERRIDES = {"Oriya": "odia"}


def script_order() -> list[str]:
    source = (ROOT / "src/unicode/script/types.zig").read_text(encoding="utf-8")
    match = ENUM.search(source)
    if match is None:
        raise SystemExit("could not find Script enum in types.zig")
    return [
        line.split("//", 1)[0].strip().removesuffix(",")
        for line in match.group(1).splitlines()
        if line.split("//", 1)[0].strip()
    ]


def enum_fingerprint(names: list[str]) -> int:
    value = 2166136261
    for name in names:
        for byte in name.encode("ascii"):
            value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
        value = ((value ^ 0xFF) * 16777619) & 0xFFFFFFFF
    return value


def checked_source(path: Path, prefix: str, digest: str) -> str:
    data = path.read_bytes()
    text = data.decode("utf-8")
    if not text.startswith(prefix):
        raise SystemExit(f"unexpected Unicode source header in {path}")
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit(f"Unicode source SHA-256 mismatch for {path}")
    return text


def main() -> None:
    if len(sys.argv) not in (5, 6):
        raise SystemExit(
            "usage: generate_data.py Scripts.txt ScriptExtensions.txt "
            "PropertyValueAliases.txt output.bin [generated_test.zig]"
        )
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    extensions_manifest = json.loads(
        EXTENSIONS_MANIFEST.read_text(encoding="utf-8")
    )
    scripts_text = checked_source(
        Path(sys.argv[1]),
        f"# Scripts-{manifest['unicode_version']}.txt\n",
        manifest["source_sha256"],
    )
    extensions_text = checked_source(
        Path(sys.argv[2]),
        f"# ScriptExtensions-{manifest['unicode_version']}.txt\n",
        extensions_manifest["source_sha256"],
    )
    aliases_text = checked_source(
        Path(sys.argv[3]),
        "# PropertyValueAliases-17.0.0.txt\n",
        extensions_manifest["aliases_sha256"],
    )

    enum_names = script_order()
    ids = {name: index for index, name in enumerate(enum_names)}
    aliases = {}
    for line in aliases_text.splitlines():
        match = ALIAS_LINE.match(line)
        if match is not None:
            aliases[match.group(1)] = match.group(2)

    scripts_seen = set()
    for line in scripts_text.splitlines():
        match = SCRIPT_LINE.match(line)
        if match is None:
            continue
        first = int(match.group(1), 16)
        last = int(match.group(2) or match.group(1), 16)
        name = ZIG_SCRIPT_NAME_OVERRIDES.get(match.group(3), match.group(3).lower())
        _ = first, last, ids[name]
        scripts_seen.add(match.group(3))

    if scripts_seen != set(manifest["modeled_scripts"]):
        raise SystemExit("Scripts.txt coverage differs from the Script manifest")

    sets: list[tuple[int, ...]] = []
    set_ids: dict[tuple[int, ...], int] = {}
    entries = []
    for line in extensions_text.splitlines():
        match = SCRIPT_LINE.match(line)
        if match is None:
            continue
        first = int(match.group(1), 16)
        last = int(match.group(2) or match.group(1), 16)
        tags = line.split(";", 1)[1].split("#", 1)[0].split()
        members = tuple(
            sorted(
                ids[ZIG_SCRIPT_NAME_OVERRIDES.get(aliases[tag], aliases[tag].lower())]
                for tag in tags
            )
        )
        set_id = set_ids.get(members)
        if set_id is None:
            set_id = len(sets)
            set_ids[members] = set_id
            sets.append(members)
        for scalar in range(first, last + 1):
            entries.append((scalar, set_id))
    entries.sort()
    if any(entries[index - 1][0] == entries[index][0] for index in range(1, len(entries))):
        raise SystemExit("overlapping Script_Extensions ranges")
    if len(sets) > 255:
        raise SystemExit("too many unique Script_Extensions sets")
    if len(entries) != extensions_manifest["expected_explicit_scalars"]:
        raise SystemExit("unexpected explicit Script_Extensions scalar count")
    if len(sets) != extensions_manifest["expected_unique_sets"]:
        raise SystemExit("unexpected unique Script_Extensions set count")

    offsets = [0]
    members = bytearray()
    for values in sets:
        members.extend(values)
        offsets.append(len(members))
    output = bytearray(
        struct.pack(
            "<4sBBBBIHHI",
            b"CJSE",
            1,
            17,
            0,
            0,
            enum_fingerprint(enum_names),
            len(sets),
            len(members),
            len(entries),
        )
    )
    output.extend(struct.pack(f"<{len(offsets)}H", *offsets))
    output.extend(members)
    for scalar, set_id in entries:
        output.extend(struct.pack("<IB3x", scalar, set_id))
    output_path = Path(sys.argv[4])
    if output_path.exists() and output_path.read_bytes() == output:
        pass
    else:
        output_path.write_bytes(output)

    if len(sys.argv) == 6:
        test_lines = [
            "// Generated by tools/unicode/script_extensions/generate_data.py.",
            'const std = @import("std");',
            'const script = @import("cangjie").text.script;',
            "",
            'test "Unicode Script_Extensions explicit memberships are exhaustive" {',
        ]
        for scalar, set_id in entries:
            expected = sets[set_id]
            test_lines.append(f"    // U+{scalar:04X}")
            for member in expected:
                test_lines.append(
                    f"    try std.testing.expect(script.extensionsContain(0x{scalar:x}, .{enum_names[member]}));"
                )
            test_lines.append(
                f"    try std.testing.expectEqual(@as(usize, {len(expected)}), script.extensionsCount(0x{scalar:x}));"
            )
        test_lines.extend(["}", ""])
        Path(sys.argv[5]).write_text("\n".join(test_lines), encoding="utf-8")


if __name__ == "__main__":
    main()
