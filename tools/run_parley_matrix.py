#!/usr/bin/env python3
"""Run a cross-script Cangjie/Parley layout and reflow matrix."""

from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Case:
    name: str
    font: Path
    text: Path
    family: str
    width: str


def run(command: list[str], cpu: int | None) -> dict[str, str]:
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr, end="")
        raise RuntimeError(f"command failed ({completed.returncode}): {' '.join(command)}")
    fields: dict[str, str] = {}
    for token in re.split(r"[\t\n ]", completed.stdout):
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


def cangjie_command(
    executable: Path, case: Case, style: str, phase: str, iterations: int, samples: int
) -> list[str]:
    return [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.width, phase, "auto", style,
    ]


def parley_command(
    executable: Path, case: Case, style: str, phase: str, iterations: int, samples: int
) -> list[str]:
    return [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.family, case.width, "auto", style, phase,
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--parley-manifest", required=True, type=Path)
    parser.add_argument("--parley-root", required=True, type=Path)
    parser.add_argument("--roboto", required=True, type=Path)
    parser.add_argument("--arabic-font", required=True, type=Path)
    parser.add_argument("--japanese-font", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--cpu", type=int)
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")

    subprocess.run(
        ["cargo", "build", "--release", "--quiet",
         "--manifest-path", str(args.parley_manifest)],
        check=True,
    )
    parley = args.parley_manifest.parent / "target/release/parley-layout-oracle"
    samples_root = args.parley_root / "parley_dev/assets/text_samples"
    cases = (
        Case("latin", args.roboto, samples_root / "latin.txt", "Roboto", "200"),
        Case("arabic", args.arabic_font, samples_root / "arabic.txt", "Noto Kufi Arabic", "180"),
        Case("japanese", args.japanese_font, samples_root / "japanese.txt", "Noto Sans CJK JP", "200"),
    )
    failures: list[str] = []
    for case in cases:
        for phase, style in (
            ("layout", "default"),
            ("layout", "spacing"),
            ("layout", "alternating"),
            ("reflow", "default"),
            ("layout", "inline-object"),
            ("reflow", "inline-object"),
        ):
            cangjie_first = run(
                cangjie_command(args.cangjie, case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            parley_first = run(
                parley_command(parley, case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            parley_second = run(
                parley_command(parley, case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            cangjie_second = run(
                cangjie_command(args.cangjie, case, style, phase, args.iterations, args.samples),
                args.cpu,
            )
            records = (cangjie_first, parley_first, parley_second, cangjie_second)
            shapes = {
                (item.get("text_bytes"), item.get("glyphs"), item.get("lines"))
                for item in records
            }
            if len(shapes) != 1:
                failures.append(f"{case.name}/{phase}/{style}: output counts={sorted(shapes)}")
            # Native geometry is normalized to logical lines/graphemes by both
            # oracles. Only default Latin currently has identical semantics;
            # other rows remain visible audit evidence rather than being
            # mistaken for parity from counts alone.
            geometry_checksums = {item.get("geometry_checksum") for item in records}
            geometry_equivalent = len(geometry_checksums) == 1 and None not in geometry_checksums
            # Each implementation also hashes its complete native layout. The
            # hash encodings intentionally differ (Cangjie uses Wyhash over its
            # public layout records; Parley uses FNV over line/glyph fields),
            # so cross-engine equality is not meaningful. Requiring stable,
            # non-zero hashes across both symmetric runs still prevents a count-
            # equivalent but internally unstable layout from passing this gate.
            for engine, first, second in (
                ("cangjie", cangjie_first, cangjie_second),
                ("parley", parley_first, parley_second),
            ):
                first_checksum = first.get("checksum")
                second_checksum = second.get("checksum")
                if (
                    first_checksum is None
                    or second_checksum is None
                    or first_checksum == "0000000000000000"
                    or first_checksum != second_checksum
                ):
                    failures.append(
                        f"{case.name}/{phase}/{style}: {engine} checksum="
                        f"{first_checksum!r}/{second_checksum!r}"
                    )
            cangjie_a = float(cangjie_first["median_ns_per_iter"])
            cangjie_b = float(cangjie_second["median_ns_per_iter"])
            parley_a = float(parley_first["median_ns_per_iter"])
            parley_b = float(parley_second["median_ns_per_iter"])
            cangjie_ns = math.sqrt(cangjie_a * cangjie_b)
            parley_ns = math.sqrt(parley_a * parley_b)
            speedup = math.inf if cangjie_ns == 0 else parley_ns / cangjie_ns
            print(
                f"{case.name}/{phase}/{style}: "
                f"cangjie_ns={cangjie_a:.3f}/{cangjie_b:.3f} "
                f"parley_ns={parley_a:.3f}/{parley_b:.3f} "
                f"speedup={speedup:.3f}x glyphs={cangjie_first.get('glyphs')} "
                f"lines={cangjie_first.get('lines')} "
                f"geometry_equal={str(geometry_equivalent).lower()}"
            )
    if failures:
        print("Cangjie/Parley output-count matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Cangjie/Parley output-count matrix passed: 18 cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
