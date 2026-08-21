#!/usr/bin/env python3
"""Verify Cangjie's declared Unicode 17 script-coverage frontier.

Usage: verify_coverage.py Scripts.txt

This intentionally reports partial coverage: the manifest is an auditable
frontier, not a claim that the compact shaping classifier models every Unicode
Script value. Newly audited large scripts must have exact scalar coverage and
an OpenType tag mapping before they may appear in the manifest.

This build-time developer verifier intentionally uses Python, matching the
other Unicode data generators and the Fontations coverage gate in this repo.
"""

import json
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = Path(__file__).with_name("coverage.json")
LINE = re.compile(r"^([0-9A-F]+)(?:\.\.([0-9A-F]+))?\s*;\s*([A-Za-z_]+)\b")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_coverage.py Scripts.txt")
    source_path = Path(sys.argv[1])
    source_bytes = source_path.read_bytes()
    source = source_bytes.decode("utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected_header = f"# Scripts-{manifest['unicode_version']}.txt\n"
    if not source.startswith(expected_header):
        raise SystemExit(f"expected {expected_header.strip()}")
    if hashlib.sha256(source_bytes).hexdigest() != manifest["source_sha256"]:
        raise SystemExit("Scripts.txt SHA-256 does not match the pinned Unicode source")

    counts: dict[str, int] = {}
    scripts: set[str] = set()
    for line in source.splitlines():
        match = LINE.match(line)
        if match is None:
            continue
        first = int(match.group(1), 16)
        last = int(match.group(2) or match.group(1), 16)
        script = match.group(3)
        scripts.add(script)
        counts[script] = counts.get(script, 0) + last - first + 1

    modeled = manifest["modeled_scripts"]
    if len(modeled) != len(set(modeled)):
        raise SystemExit("duplicate modeled script in coverage manifest")
    unknown = sorted(set(modeled) - scripts)
    if unknown:
        raise SystemExit(f"manifest names unknown Unicode scripts: {unknown}")

    root = (ROOT / "src/unicode/script/root.zig").read_text(encoding="utf-8")
    facade = (ROOT / "src/unicode.zig").read_text(encoding="utf-8")
    missing_artifacts = []
    for script in manifest["newly_audited_large_scripts"]:
        zig_name = script.lower()
        if f"    {zig_name}," not in root:
            missing_artifacts.append(f"{script}: Script enum")
        if f".{zig_name} =>" not in facade:
            missing_artifacts.append(f"{script}: OpenType mapping")
        expected = manifest["expected_assigned_scalar_counts"][script]
        if counts.get(script) != expected:
            missing_artifacts.append(
                f"{script}: expected {expected} assigned scalars, got {counts.get(script)}"
            )
    if missing_artifacts:
        raise SystemExit("script coverage verification failed:\n  - " + "\n  - ".join(missing_artifacts))

    covered = set(modeled)
    print(
        f"Unicode {manifest['unicode_version']} script coverage: "
        f"{len(covered)}/{len(scripts)} scripts modeled; "
        f"{len(scripts - covered)} remain explicit gaps"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
