#!/usr/bin/env python3
"""Run a cross-script Cangjie/Parley paragraph benchmark matrix."""

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
    executable: Path, case: Case, style: str, iterations: int, samples: int
) -> list[str]:
    return [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.width, "layout", "auto", style,
    ]


def parley_command(
    executable: Path, case: Case, style: str, iterations: int, samples: int
) -> list[str]:
    return [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.family, case.width, "auto", style,
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
        for style in ("default", "spacing", "alternating"):
            cangjie = run(
                cangjie_command(args.cangjie, case, style, args.iterations, args.samples),
                args.cpu,
            )
            reference = run(
                parley_command(parley, case, style, args.iterations, args.samples),
                args.cpu,
            )
            shape = (cangjie.get("text_bytes"), cangjie.get("glyphs"), cangjie.get("lines"))
            expected = (reference.get("text_bytes"), reference.get("glyphs"), reference.get("lines"))
            if shape != expected:
                failures.append(f"{case.name}/{style}: Cangjie={shape}, Parley={expected}")
            cangjie_ns = float(cangjie["median_ns_per_iter"])
            parley_ns = float(reference["median_ns_per_iter"])
            speedup = math.inf if cangjie_ns == 0 else parley_ns / cangjie_ns
            print(
                f"{case.name}/{style}: cangjie_ns={cangjie_ns:.3f} "
                f"parley_ns={parley_ns:.3f} speedup={speedup:.3f}x "
                f"glyphs={cangjie.get('glyphs')} lines={cangjie.get('lines')}"
            )
    if failures:
        print("Cangjie/Parley output-count matrix failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Cangjie/Parley output-count matrix passed: 9 cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
